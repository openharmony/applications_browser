import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { audio } from '@kit.AudioKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { webview } from '@kit.ArkWeb'
import { UIContext } from '@kit.ArkUI'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { SitePermissionId, SitePermissionPolicy } from 'common'
import { AppPermissionService } from '../security/AppPermissionService'

/** 单次网页权限申请的判定结果 */
export type WebPermissionDecision = 'grant' | 'deny'

/** 决策结构体：放行结果 + 决策来源 */
interface PolicyDecision {
  allow: boolean
  source: 'origin' | 'global'
}

/** 会话级决策缓存条目 */
interface CachedDecision {
  decision: WebPermissionDecision
  /** 决策时间戳（Date.now()） */
  ts: number
}

/** 会话级缓存有效期：30 秒（同一 origin+permId 复用上次决策，避免反复 toast） */
const SESSION_CACHE_TTL_MS: number = 30 * 1000

/**
 * 权限资源名常量，对应 web.d.ts 的 ProtectedResourceType。
 * ArkTS 不允许在运行时动态生成空类型，因此把回调形式直接暴露给 UI 层调用。
 */
const RESOURCE_VIDEO_CAPTURE: string = 'TYPE_VIDEO_CAPTURE'
const RESOURCE_AUDIO_CAPTURE: string = 'TYPE_AUDIO_CAPTURE'

/** 解析网页侧 resource 列表，映射到本端 camera/microphone（可同时包含两者） */
function collectPermIdsFromResources(resources: Array<string>): SitePermissionId[] {
  const list: Array<string> = Array.isArray(resources) ? resources : []
  const result: SitePermissionId[] = []
  if (list.indexOf(RESOURCE_VIDEO_CAPTURE) >= 0) {
    result.push('camera')
  }
  if (list.indexOf(RESOURCE_AUDIO_CAPTURE) >= 0) {
    result.push('microphone')
  }
  return result
}

/** 解析网页侧 resource 列表，映射到本端 4 类之一（兼容旧调用：优先 video） */
export function mapResourcesToPermId(resources: Array<string>): SitePermissionId | null {
  const ids = collectPermIdsFromResources(resources)
  if (ids.length === 0) {
    return null
  }
  return ids[0]
}

/** 单一权限的资源 → 应用权限 + 策略查询的描述 */
interface WebPermissionDescriptor {
  /** 系统应用权限名（多个时按序申请） */
  appPermissions: Permissions[]
  /** 通知权限是否走 notificationManager 申请（仅 notification 时为 true） */
  viaNotificationKit: boolean
}

const LOCATION_DESCRIPTOR: WebPermissionDescriptor = {
  appPermissions: ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'],
  viaNotificationKit: false
}
const CAMERA_DESCRIPTOR: WebPermissionDescriptor = {
  appPermissions: ['ohos.permission.CAMERA'],
  viaNotificationKit: false
}
const MICROPHONE_DESCRIPTOR: WebPermissionDescriptor = {
  appPermissions: ['ohos.permission.MICROPHONE'],
  viaNotificationKit: false
}
const NOTIFICATION_DESCRIPTOR: WebPermissionDescriptor = {
  appPermissions: [],
  viaNotificationKit: true
}

/** 网页权限申请的处理入口（单例） */
export class WebPermissionGate {
  private static instance: WebPermissionGate | null = null
  /** 会话级决策缓存：key = origin|permId */
  private sessionCache: Map<string, CachedDecision> = new Map()
  /** origin 级别持久化策略：key = origin|permId，启动时从 SettingsStore 加载 */
  private originPerms: Map<string, SitePermissionPolicy> = new Map()
  private originPermsLoaded: boolean = false

  static getInstance(): WebPermissionGate {
    if (WebPermissionGate.instance === null) {
      WebPermissionGate.instance = new WebPermissionGate()
    }
    return WebPermissionGate.instance
  }

  /** 读取会话缓存（命中且未过期） */
  private readSessionCache(origin: string, permId: SitePermissionId): WebPermissionDecision | null {
    const key = `${origin}|${permId}`
    const cached = this.sessionCache.get(key)
    if (cached === undefined) {
      return null
    }
    if (Date.now() - cached.ts > SESSION_CACHE_TTL_MS) {
      const next: Map<string, CachedDecision> = new Map()
      const ks: IterableIterator<string> = this.sessionCache.keys()
      let it: IteratorResult<string> = ks.next()
      while (!it.done) {
        const k: string = it.value
        if (k !== key) {
          const v: CachedDecision | undefined = this.sessionCache.get(k)
          if (v !== undefined) {
            next.set(k, v)
          }
        }
        it = ks.next()
      }
      this.sessionCache = next
      return null
    }
    return cached.decision
  }

  /** 写入会话缓存 */
  private writeSessionCache(origin: string, permId: SitePermissionId, decision: WebPermissionDecision): void {
    const key = `${origin}|${permId}`
    this.sessionCache.set(key, { decision, ts: Date.now() })
  }

  /** 清空会话缓存（无痕切换 / 主页重置时调用） */
  clearSessionCache(): void {
    this.sessionCache.clear()
  }

  /** 应用启动时加载 origin 级别持久化策略（异步一次性） */
  async loadOriginPermissions(): Promise<void> {
    const map = await BrowserStore.getOriginPermissions()
    this.originPerms = map
    this.originPermsLoaded = true
  }

  /** 读取某 origin+permId 的持久化策略（未记录时返回 null） */
  getOriginPermission(origin: string, permId: SitePermissionId): SitePermissionPolicy | null {
    if (!this.originPermsLoaded) {
      return null
    }
    return this.originPerms.get(`${origin}|${permId}`) ?? null
  }

  /** 写 origin 级别策略（异步） */
  async writeOriginPermission(origin: string, permId: SitePermissionId, policy: SitePermissionPolicy): Promise<void> {
    this.originPerms.set(`${origin}|${permId}`, policy)
    await BrowserStore.setOriginPermission(origin, permId, policy)
  }

  /** 删除 origin 级别策略（异步） */
  async clearOriginPermission(origin: string, permId: SitePermissionId): Promise<void> {
    this.originPerms.delete(`${origin}|${permId}`)
    await BrowserStore.setOriginPermission(origin, permId, 'clear')
  }

  /**
   * 网站位置权限是否允许（与 onGeolocationShow 判定一致）。
   * 全局禁止优先于 origin 允许；origin 禁止优先于全局允许。
   */
  static isSiteLocationAllowed(origin: string): boolean {
    const normOrigin = WebPermissionGate.normalizeWebOrigin(origin)
    const globalPolicy = BrowserStore.getSitePermission('location')
    if (globalPolicy === 'deny') {
      return false
    }
    const originPolicy = WebPermissionGate.getInstance().getOriginPermission(normOrigin, 'location')
    if (originPolicy === 'deny') {
      return false
    }
    if (originPolicy === 'allow') {
      return true
    }
    return globalPolicy === 'allow'
  }

  /** 清除 origin 位置会话缓存，避免旧 grant 绕过策略 */
  invalidateLocationSession(origin: string): void {
    const norm = WebPermissionGate.normalizeWebOrigin(origin)
    if (norm.length === 0) {
      return
    }
    const key = `${norm}|location`
    if (!this.sessionCache.has(key)) {
      return
    }
    const next: Map<string, CachedDecision> = new Map()
    const ks: IterableIterator<string> = this.sessionCache.keys()
    let it: IteratorResult<string> = ks.next()
    while (!it.done) {
      const k: string = it.value
      if (k !== key) {
        const v: CachedDecision | undefined = this.sessionCache.get(k)
        if (v !== undefined) {
          next.set(k, v)
        }
      }
      it = ks.next()
    }
    this.sessionCache = next
  }

  /**
   * 网站位置被禁止：每次 H5 触发 onGeolocationShow 均 Toast，并清除静态授权以便后续请求仍走回调。
   */
  /** 拒绝网站定位：仅走 GeolocationPermissions 静态 API，不调用 event.geolocation native 方法 */
  denySiteLocationRequest(origin: string, incognito: boolean): void {
    const normOrigin = WebPermissionGate.normalizeWebOrigin(origin)
    BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast('location'))
    this.clearGeolocationOrigin(normOrigin, incognito)
    this.invalidateLocationSession(normOrigin)
    BrowserLog.info(`[WebPerm] denySiteLocationRequest static-deny origin=${normOrigin.slice(0, 80)}`)
  }

  /**
   * 统一判定 origin+permId 的放行结果。
   * 返回 true 表示放行（应用级权限需另外确保已授予），false 表示拒绝。
   * 全局禁止优先于 origin 允许；origin 禁止优先于全局允许。
   */
  private decidePolicy(origin: string, permId: SitePermissionId): PolicyDecision {
    const globalPolicy = BrowserStore.getSitePermission(permId)
    if (globalPolicy === 'deny') {
      const r: PolicyDecision = { allow: false, source: 'global' }
      return r
    }
    const originPolicy = this.getOriginPermission(origin, permId)
    if (originPolicy === 'allow') {
      const r: PolicyDecision = { allow: true, source: 'origin' }
      return r
    }
    if (originPolicy === 'deny') {
      const r: PolicyDecision = { allow: false, source: 'origin' }
      return r
    }
    const r: PolicyDecision = { allow: globalPolicy === 'allow', source: 'global' }
    return r
  }

  /**
   * 处理 ArkWeb onPermissionRequest 回调（camera/microphone）。
   * UI 层将 event.request 拆解为 origin / resources / grant / deny 传入，
   * 避免直接传递 web PermissionRequest 类型（ArkTS 不允许 structural typing）。
   */
  async handlePermissionRequest(origin: string, resources: Array<string>, grant: () => void, deny: () => void): Promise<WebPermissionDecision> {
    const permIds = collectPermIdsFromResources(resources)
    if (permIds.length === 0) {
      BrowserLog.info(`[WebPerm] deny unsupported resources origin=${origin} res=${JSON.stringify(resources)}`)
      deny()
      return 'deny'
    }
    BrowserLog.info(`[WebPerm] request permIds=${JSON.stringify(permIds)} origin=${origin}`)
    // 仅麦克风：拒绝 ArkWeb 采集通路（日志 audioBus/frameCount:4800 会丢光 PCM），
    // 改由文档注入的 getUserMedia 旁路走原生 AudioCapturer。
    if (permIds.length === 1 && permIds[0] === 'microphone') {
      BrowserLog.info('[WebPerm] deny ArkWeb AUDIO_CAPTURE only; native mic bypass handles audio')
      deny()
      return 'deny'
    }
    if (BrowserStore.isIncognito()) {
      BrowserLog.info(`[WebPerm] deny in incognito permIds=${JSON.stringify(permIds)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.perm_denied_toast')))
      for (let i = 0; i < permIds.length; i++) {
        this.writeSessionCache(origin, permIds[i], 'deny')
      }
      deny()
      return 'deny'
    }

    for (let i = 0; i < permIds.length; i++) {
      const permId = permIds[i]
      const cached = this.readSessionCache(origin, permId)
      if (cached === 'deny') {
        deny()
        return 'deny'
      }
      if (cached === 'grant') {
        if (AppPermissionService.getInstance().isGranted(permId)) {
          continue
        }
        const appGranted = await AppPermissionService.getInstance().ensureCategoryGranted(permId)
        if (!appGranted) {
          this.writeSessionCache(origin, permId, 'deny')
          deny()
          return 'deny'
        }
        continue
      }

      const decision = this.decidePolicy(origin, permId)
      BrowserLog.info(`[WebPerm] decision permId=${permId} source=${decision.source} allow=${decision.allow}`)
      if (!decision.allow) {
        BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
        this.writeSessionCache(origin, permId, 'deny')
        deny()
        return 'deny'
      }

      if (!AppPermissionService.getInstance().isGranted(permId)) {
        BrowserLog.warn(`[WebPerm] site allow but app perm missing permId=${permId}, requesting`)
        const appGranted = await AppPermissionService.getInstance().ensureCategoryGranted(permId)
        if (!appGranted) {
          BrowserLog.warn(`[WebPerm] app perm still missing after request permId=${permId}`)
          BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
          this.writeSessionCache(origin, permId, 'deny')
          deny()
          return 'deny'
        }
      }
      this.writeSessionCache(origin, permId, 'grant')
    }

    // 麦克风：原生旁路采集前也会走 ensureWebMicrophone；此处仅保证会话就绪
    if (permIds.indexOf('microphone') >= 0) {
      const switchOk = await WebPermissionGate.requestCaptureGlobalSwitch('microphone')
      if (!switchOk) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.perm_global_switch_off_toast'),
          BrowserStrings.permCategoryLabel('microphone')))
        for (let i = 0; i < permIds.length; i++) {
          this.writeSessionCache(origin, permIds[i], 'deny')
        }
        deny()
        return 'deny'
      }
      await WebPermissionGate.prepareMicrophoneAudioSession()
    }
    grant()
    return 'grant'
  }

  /**
   * 网页原生麦克风旁路：校验站点策略 + 应用权限 + 全局开关（不调用 ArkWeb grant）。
   * 日志：GetGlobalSwitchStatus MICROPHONE status=0 时系统走 FAKE/空采；需 requestGlobalSwitch。
   */
  async ensureWebMicrophone(origin: string): Promise<boolean> {
    const permId: SitePermissionId = 'microphone'
    const normOrigin = WebPermissionGate.normalizeWebOrigin(origin)
    if (BrowserStore.isIncognito()) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.perm_denied_toast')))
      this.writeSessionCache(normOrigin, permId, 'deny')
      return false
    }
    const decision = this.decidePolicy(normOrigin, permId)
    BrowserLog.info(`[WebPerm] ensureWebMicrophone origin=${normOrigin.slice(0, 80)} source=${decision.source} allow=${decision.allow}`)
    if (!decision.allow) {
      BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
      this.writeSessionCache(normOrigin, permId, 'deny')
      return false
    }
    if (!AppPermissionService.getInstance().isGranted(permId)) {
      const appGranted = await AppPermissionService.getInstance().ensureCategoryGranted(permId)
      if (!appGranted) {
        BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
        this.writeSessionCache(normOrigin, permId, 'deny')
        return false
      }
    }
    const switchOk = await WebPermissionGate.requestCaptureGlobalSwitch(permId)
    if (!switchOk) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.perm_global_switch_off_toast'),
        BrowserStrings.permCategoryLabel(permId)))
      this.writeSessionCache(normOrigin, permId, 'deny')
      return false
    }
    this.writeSessionCache(normOrigin, permId, 'grant')
    return true
  }

  /**
   * 拉起相机/麦克风全局开关；已开启则返回 true。
   * 错误码 12100013 表示已开启。
   */
  static async requestCaptureGlobalSwitch(permId: SitePermissionId): Promise<boolean> {
    if (permId !== 'camera' && permId !== 'microphone') {
      return true
    }
    const ctx = BrowserStore.getContext()
    if (ctx === null) {
      BrowserLog.warn(`[WebPerm] requestGlobalSwitch no context permId=${permId}`)
      return true
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const switchType = permId === 'camera' ?
        abilityAccessCtrl.SwitchType.CAMERA : abilityAccessCtrl.SwitchType.MICROPHONE
      const opened = await atManager.requestGlobalSwitch(ctx, switchType)
      BrowserLog.info(`[WebPerm] requestGlobalSwitch permId=${permId} opened=${opened}`)
      return opened === true
    } catch (err) {
      const code = (err as BusinessError).code
      if (code === 12100013) {
        BrowserLog.info(`[WebPerm] requestGlobalSwitch already open permId=${permId}`)
        return true
      }
      BrowserLog.warn(`[WebPerm] requestGlobalSwitch failed permId=${permId}: ${JSON.stringify(err)}`)
      // 拉起失败不阻断（部分机型无此开关），由后续采集结果验证
      return true
    }
  }

  /**
   * 激活 AudioSession，供原生旁路采集与 Web 放行共用。
   */
  static async prepareMicrophoneAudioSession(): Promise<void> {
    try {
      const sessionMgr = audio.getAudioManager().getSessionManager()
      if (!sessionMgr.isAudioSessionActivated()) {
        const strategy: audio.AudioSessionStrategy = {
          concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
        }
        await sessionMgr.activateAudioSession(strategy)
        BrowserLog.info('[WebPerm] mic audioSession activated')
      } else {
        BrowserLog.info('[WebPerm] mic audioSession already active')
      }
    } catch (err) {
      BrowserLog.warn(`[WebPerm] mic audioSession prepare failed: ${JSON.stringify(err)}`)
    }
  }

  /**
   * 同步版地理位置入口：仅在 onGeolocationShow 同步回调内调用。
   * 关键约束：
   * - 不调用 event.geolocation 上的任何 native 方法（getOrigin/invoke 都有 SIGSEGV 风险）。
   * - origin 由调用方（BrowsePageView）从 this.currentUrl 解析并传入。
   * - 放行走 webview.GeolocationPermissions.allowGeolocation（静态 API，与 native 句柄解耦）。
   * - 拒绝走 webview.GeolocationPermissions.deleteGeolocation（静态 API）。
   * - 应用级位置权限未授予 → 直接 deny（用户在设置页中应有"去设置"引导）。
   */
  handleGeolocationShowSync(origin: string, allow: (origin: string) => void, deny: (origin: string) => void,
    _uiCtx: UIContext | null): void {
    const permId: SitePermissionId = 'location'
    if (BrowserStore.isIncognito()) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.perm_denied_toast')))
      this.writeSessionCache(origin, permId, 'deny')
      deny(origin)
      return
    }
    // 会话级缓存
    const cached = this.readSessionCache(origin, permId)
    if (cached === 'grant') {
      if (AppPermissionService.getInstance().isGranted(permId)) {
        this.grantLocation(origin, allow)
      } else {
        deny(origin)
      }
      return
    }
    if (cached === 'deny') {
      if (!this.decidePolicy(origin, permId).allow) {
        BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
      }
      deny(origin)
      return
    }
    const decision = this.decidePolicy(origin, permId)
    BrowserLog.info(`[WebPerm] geo decision origin=${origin} source=${decision.source} allow=${decision.allow}`)
    if (!decision.allow) {
      BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
      this.invalidateLocationSession(origin)
      deny(origin)
      return
    }
    if (AppPermissionService.getInstance().isGranted(permId)) {
      this.writeSessionCache(origin, permId, 'grant')
      this.grantLocation(origin, allow)
      return
    }
    BrowserLog.warn(`[WebPerm] site allow but app location missing origin=${origin}`)
    this.writeSessionCache(origin, permId, 'deny')
    deny(origin)
  }

  /** 真正放行位置：清 cache → 写静态表 + 调用 allow 闭包 */
  private grantLocation(origin: string, allow: (origin: string) => void): void {
    WebPermissionGate.getInstance().grantGeolocationForShow(origin, false)
    allow(origin)
  }

  /** 从 URL 中抽取 origin（scheme://host[:port]）；非 http(s) 返回空串 */
  static extractOriginFromUrl(url: string): string {
    const trimmed = (url || '').trim()
    if (!trimmed) {
      return ''
    }
    const lower = trimmed.toLowerCase()
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return ''
    }
    const proto = '://'
    const idx = trimmed.indexOf(proto)
    if (idx < 0) {
      return ''
    }
    const rest = trimmed.substring(idx + proto.length)
    const slash = rest.indexOf('/')
    const host = slash < 0 ? rest : rest.substring(0, slash)
    return trimmed.substring(0, idx + proto.length) + host
  }

  /**
   * 同步记录一次位置请求被拒绝的提示（不再区分策略，已统一为 deny/allow）。
   */
  notifyGeolocationDeniedForCurrentPolicy(origin: string): void {
    const permId: SitePermissionId = 'location'
    const decision = this.decidePolicy(origin, permId)
    if (!decision.allow) {
      BrowserStore.showToast(BrowserStrings.sitePermissionDeniedToast(permId))
      return
    }
    this.writeSessionCache(origin, permId, 'grant')
  }

  /**
   * 设置面板改了全局 site 策略后调用：通知所有 BrowsePageView 重新把
   * 当前 origin 写入/清除 webview.GeolocationPermissions 静态表。
   */
  private policyChangeListeners: Set<(origin: string) => void> = new Set()
  notifyPolicyChanged(): void {
    const ls = this.policyChangeListeners
    ls.forEach((cb) => {
      try {
        cb('')
      } catch (e) {
        BrowserLog.warn(`[WebPerm] policy listener threw: ${JSON.stringify(e)}`)
      }
    })
  }
  addPolicyChangeListener(cb: (origin: string) => void): void {
    this.policyChangeListeners.add(cb)
  }
  removePolicyChangeListener(cb: (origin: string) => void): void {
    const next: Set<(origin: string) => void> = new Set()
    const it = this.policyChangeListeners.values()
    let r = it.next()
    while (!r.done) {
      if (r.value !== cb) {
        next.add(r.value)
      }
      r = it.next()
    }
    this.policyChangeListeners = next
  }

  /**
   * 按当前策略同步 webview.GeolocationPermissions 静态表。
   * @param deferAllow 为 true 时（onPageBegin）仅处理 deny，不写 allowGeolocation——
   *   避免 ArkWeb 预取 cached 位置导致 amap 等 H5 首次 getCurrentPosition 拿到过期 timestamp。
   *   allow 路径改在 onGeolocationShow 中 delete→allow→invoke 走实时 native 查询。
   */
  applyLocationPolicyToOrigin(origin: string, _uiCtx: UIContext | null, incognito: boolean,
    deferAllow: boolean = false): void {
    if (!origin || origin.length === 0) {
      return
    }
    const permId: SitePermissionId = 'location'
    const normOrigin = WebPermissionGate.normalizeWebOrigin(origin)
    const decision = this.decidePolicy(normOrigin, permId)
    BrowserLog.info(`[WebPerm] applyLocationPolicyToOrigin origin=${normOrigin} source=${decision.source} allow=${decision.allow} incognito=${incognito} deferAllow=${deferAllow}`)
    try {
      if (decision.allow) {
        if (!deferAllow) {
          webview.GeolocationPermissions.allowGeolocation(normOrigin, incognito)
          this.writeSessionCache(normOrigin, permId, 'grant')
        }
      } else {
        this.clearGeolocationOrigin(normOrigin, incognito)
        this.invalidateLocationSession(normOrigin)
      }
    } catch (e) {
      BrowserLog.warn(`[WebPerm] applyLocationPolicyToOrigin failed: ${JSON.stringify(e)}`)
    }
  }

  /** 去掉 origin 末尾斜杠，便于与 GeolocationPermissions / 策略表 key 对齐 */
  static normalizeWebOrigin(origin: string): string {
    let o = (origin ?? '').trim()
    while (o.length > 0 && o.endsWith('/')) {
      o = o.slice(0, -1)
    }
    return o
  }

  /**
   * 清除 origin 静态位置授权（含末尾带 / 变体），强制下次 H5 请求触发 onGeolocationShow。
   */
  clearGeolocationOrigin(origin: string, incognito: boolean): void {
    const norm = WebPermissionGate.normalizeWebOrigin(origin)
    if (norm.length === 0) {
      return
    }
    const variants: string[] = [norm, `${norm}/`]
    try {
      for (let i = 0; i < variants.length; i++) {
        webview.GeolocationPermissions.deleteGeolocation(variants[i], incognito)
      }
      BrowserLog.info(`[WebPerm] clearGeolocationOrigin origin=${norm} incognito=${incognito}`)
    } catch (e) {
      BrowserLog.warn(`[WebPerm] clearGeolocationOrigin failed: ${JSON.stringify(e)}`)
    }
  }

  /**
   * onGeolocationShow 放行后持久化到静态表（供设置变更等场景使用）。
   */
  grantGeolocationForShow(origin: string, incognito: boolean): void {
    try {
      webview.GeolocationPermissions.allowGeolocation(origin, incognito)
      BrowserLog.info(`[WebPerm] grantGeolocationForShow origin=${origin} incognito=${incognito}`)
    } catch (e) {
      BrowserLog.warn(`[WebPerm] grantGeolocationForShow failed: ${JSON.stringify(e)}`)
    }
  }

  private getDescriptor(permId: SitePermissionId): WebPermissionDescriptor {
    if (permId === 'location') {
      return LOCATION_DESCRIPTOR
    }
    if (permId === 'camera') {
      return CAMERA_DESCRIPTOR
    }
    if (permId === 'microphone') {
      return MICROPHONE_DESCRIPTOR
    }
    return NOTIFICATION_DESCRIPTOR
  }

  private permLabelRes(permId: SitePermissionId): Resource {
    if (permId === 'location') {
      return $r('app.string.perm_location')
    }
    if (permId === 'camera') {
      return $r('app.string.perm_camera')
    }
    if (permId === 'microphone') {
      return $r('app.string.perm_microphone')
    }
    return $r('app.string.perm_notification')
  }

  private static shortHost(origin: string): string {
    const trimmed = (origin || '').trim()
    if (!trimmed) {
      return ''
    }
    const proto = '://'
    const idx = trimmed.indexOf(proto)
    if (idx < 0) {
      return trimmed
    }
    const rest = trimmed.substring(idx + proto.length)
    const slash = rest.indexOf('/')
    return slash < 0 ? rest : rest.substring(0, slash)
  }

  /**
   * 应用级权限检查 + 申请：返回 true 表示浏览器已持有该权限。
   * - 通知走 notificationManager（API 9+）
   * - 其余走 abilityAccessCtrl.requestPermissionsFromUser，必要时再走设置页
   */
  async ensureAppPermission(permId: SitePermissionId): Promise<boolean> {
    const desc = this.getDescriptor(permId)
    if (desc.viaNotificationKit) {
      return WebPermissionGate.ensureNotificationPermission()
    }
    if (desc.appPermissions.length === 0) {
      return true
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserLog.warn('[WebPerm] no UIAbilityContext for app permission')
      return false
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      if (WebPermissionGate.isAllGranted(atManager, ctx, desc.appPermissions)) {
        return true
      }
      BrowserLog.info(`[WebPerm] requestAppPermission permId=${permId} perms=${JSON.stringify(desc.appPermissions)}`)
      const result = await atManager.requestPermissionsFromUser(ctx, desc.appPermissions)
      const granted = WebPermissionGate.isAnyGranted(result)
      if (granted) {
        return true
      }
      const dialogShown = WebPermissionGate.wasDialogShown(result)
      if (!dialogShown) {
        try {
          await atManager.requestPermissionOnSetting(ctx, desc.appPermissions)
          if (WebPermissionGate.isAllGranted(atManager, ctx, desc.appPermissions)) {
            return true
          }
        } catch (settingErr) {
          BrowserLog.warn(`[WebPerm] open settings failed: ${JSON.stringify(settingErr)}`)
        }
      }
    } catch (err) {
      BrowserLog.error(`[WebPerm] ensureAppPermission failed permId=${permId}: ${JSON.stringify(err)}`)
    }
    return false
  }

  private static isAllGranted(atManager: abilityAccessCtrl.AtManager, ctx: common.UIAbilityContext,
    perms: Permissions[]): boolean {
    try {
      const tokenId = ctx.applicationInfo.accessTokenId
      for (let i = 0; i < perms.length; i++) {
        const status = atManager.checkAccessTokenSync(tokenId, perms[i])
        if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false
        }
      }
      return true
    } catch (err) {
      BrowserLog.warn(`[WebPerm] checkAccessTokenSync failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  private static isAnyGranted(result: PermissionRequestResult): boolean {
    for (let i = 0; i < result.authResults.length; i++) {
      if (result.authResults[i] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true
      }
    }
    return false
  }

  private static wasDialogShown(result: PermissionRequestResult): boolean {
    if (!result.dialogShownResults || result.dialogShownResults.length === 0) {
      return true
    }
    return result.dialogShownResults[0] === true
  }

  /** 通知权限：先确保全局已开启，再加 SERVICE_INFORMATION 槽位 */
  private static async ensureNotificationPermission(): Promise<boolean> {
    try {
      if (!notificationManager.isNotificationEnabledSync()) {
        const ctx = BrowserStore.getContext()
        if (!ctx) {
          return false
        }
        await notificationManager.requestEnableNotification(ctx)
        if (!notificationManager.isNotificationEnabledSync()) {
          return false
        }
      }
      try {
        await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION)
      } catch (_err) {
        // 槽位可能已存在
      }
      return true
    } catch (err) {
      BrowserLog.warn(`[WebPerm] ensureNotificationPermission failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 静默清理无痕窗口残留的位置授权（每 incognito 关闭时调用） */
  static clearIncognitoGeolocation(): void {
    try {
      webview.GeolocationPermissions.deleteAllGeolocation(true)
    } catch (err) {
      BrowserLog.warn(`[WebPerm] clearIncognitoGeolocation failed: ${JSON.stringify(err)}`)
    }
  }
}
