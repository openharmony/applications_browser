import { abilityAccessCtrl, common, Permissions, PermissionRequestResult, Want } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { SitePermissionId, SitePermissionsMap, AppSystemPermissionId } from 'common'
import { SettingsStore } from '../settings/SettingsStore'
import { AppStateSync } from '../AppStateSync'
import { LocationWarmupService } from '../web/LocationWarmupService'
import { SettingsRepository } from 'common'

/**
 * 应用级（系统级）权限状态。
 * - granted：系统已授予
 * - denied：用户拒绝或系统未授予（无法放行网站权限）
 * - unknown：尚未检查
 */
export type AppPermissionStatus = 'granted' | 'denied' | 'unknown'

const ALL_CATEGORIES: SitePermissionId[] = ['location', 'camera', 'microphone', 'notification']
const WRITE_IMAGE_VIDEO: Permissions = 'ohos.permission.WRITE_IMAGEVIDEO'
const READ_IMAGE_VIDEO: Permissions = 'ohos.permission.READ_IMAGEVIDEO'
/** 系统设置应用（OpenHarmony / HarmonyOS NEXT 兼容） */
interface SettingsAbilityTarget {
  bundleName: string
  abilityName: string
}

const SETTINGS_ABILITY_TARGETS: SettingsAbilityTarget[] = [
  { bundleName: 'com.ohos.settings', abilityName: 'com.ohos.settings.MainAbility' },
  { bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility' }
]
/** 通知已关闭或用户曾拒绝：requestEnableNotification 不再弹窗，需引导至系统设置 */
const NOTIFICATION_DENIED_CODE: number = 1600004

/**
 * 应用级权限检查 + 申请服务。
 * 启动时 syncSitePermissionsWithAppGrants() 对设置为 allow 的网站权限逐项校验并申请。
 */
export class AppPermissionService {
  private static instance: AppPermissionService | null = null
  private launchSyncDone: boolean = false

  static getInstance(): AppPermissionService {
    if (AppPermissionService.instance === null) {
      AppPermissionService.instance = new AppPermissionService()
    }
    return AppPermissionService.instance
  }

  /**
   * 启动兜底：刷新全部应用权限状态；对网站权限设为 allow 的项，
   * 若浏览器未持有对应应用权限则主动申请，仍无则强制改回 deny。
   * 通知为系统级开关，不受 site 策略限制，首次启动未开启时会主动申请。
   */
  async syncSitePermissionsWithAppGrants(): Promise<void> {
    if (this.launchSyncDone) {
      return
    }
    this.launchSyncDone = true
    BrowserLog.info('[AppPerm] syncSitePermissionsWithAppGrants begin')
    await this.refreshAllStatuses()
    const perms: SitePermissionsMap = BrowserStore.getSitePermissions()
    for (let i = 0; i < ALL_CATEGORIES.length; i++) {
      const cat: SitePermissionId = ALL_CATEGORIES[i]
      const sitePolicy = AppPermissionService.sitePolicyOf(perms, cat)
      // 通知是系统级开关，与 site 策略无关：首次启动若未开启需要主动弹一次申请框。
      // 其它类别仍保持"site 设为 allow 才校验/申请"的原行为。
      if (cat !== 'notification' && sitePolicy !== 'allow') {
        continue
      }
      if (this.isGranted(cat)) {
        BrowserLog.info(`[AppPerm] startup skip cat=${cat} already granted`)
        continue
      }
      if (cat === 'notification' && await this.hasNotificationStartupDeclined()) {
        BrowserLog.info('[AppPerm] startup skip notification user declined previously')
        continue
      }
      BrowserLog.info(`[AppPerm] startup missing app grant cat=${cat} sitePolicy=${sitePolicy}, requesting`)
      const granted = await this.ensureCategoryGranted(cat)
      BrowserLog.info(`[AppPerm] startup request result cat=${cat} granted=${granted}`)
      if (!granted && cat !== 'notification') {
        BrowserLog.info(`[AppPerm] startup force site deny cat=${cat}`)
        await SettingsStore.getInstance().setSitePermissionUnchecked(cat, 'deny')
      }
    }
    await AppStateSync.refreshSitePermissions()
    if (BrowserStore.getSitePermission('location') === 'allow' && this.isGranted('location')) {
      LocationWarmupService.startAtAppLaunch('appInit')
    }
    BrowserLog.info('[AppPerm] syncSitePermissionsWithAppGrants done')
  }

  /** 从设置页返回时刷新全部应用权限缓存 */
  refreshAllOnForeground(): void {
    void this.refreshAllStatuses()
    void this.refreshImageVideoStatus()
    this.refreshNotificationOnForeground()
  }

  /** 刷新图片/视频（相册）系统权限缓存 */
  async refreshImageVideoStatus(): Promise<AppPermissionStatus> {
    return this.refreshCategoryStatus('image_video')
  }

  /** 从设置页返回时刷新通知授权缓存 */
  refreshNotificationOnForeground(): void {
    void this.refreshCategoryStatus('notification').then((status) => {
      if (status === 'granted') {
        void SettingsRepository.getInstance().setNotificationStartupDeclined(false)
      }
    })
  }

  /** 从系统刷新全部应用权限缓存（不弹申请框） */
  async refreshAllStatuses(): Promise<void> {
    for (let i = 0; i < ALL_CATEGORIES.length; i++) {
      await this.refreshCategoryStatus(ALL_CATEGORIES[i])
    }
    await this.refreshImageVideoStatus()
  }

  /** 从系统刷新单项应用权限缓存 */
  async refreshCategoryStatus(category: AppSystemPermissionId): Promise<AppPermissionStatus> {
    const ctx = BrowserStore.getContext()
    if (ctx === null) {
      return 'unknown'
    }
    try {
      if (category === 'notification') {
        const enabled = await notificationManager.isNotificationEnabled()
        if (enabled) {
          this.markGranted(category)
          void SettingsRepository.getInstance().setNotificationStartupDeclined(false)
          return 'granted'
        }
        this.markDenied(category)
        return 'denied'
      }
      const atManager = abilityAccessCtrl.createAtManager()
      let granted = false
      if (category === 'location') {
        granted = await this.checkLocationGranted(ctx, atManager)
      } else if (category === 'camera') {
        granted = await this.checkStandardGranted(ctx, atManager, 'ohos.permission.CAMERA' as Permissions)
      } else if (category === 'microphone') {
        granted = await this.checkStandardGranted(ctx, atManager, 'ohos.permission.MICROPHONE' as Permissions)
      } else if (category === 'image_video') {
        granted = AppPermissionService.isImageVideoGrantedBySystem(atManager, ctx)
      }
      if (granted) {
        this.markGranted(category)
        return 'granted'
      }
      this.markDenied(category)
      return 'denied'
    } catch (e) {
      BrowserLog.warn(`[AppPerm] refreshCategoryStatus ${category} failed: ${JSON.stringify(e)}`)
      return AppPermissionService.getStatus(category)
    }
  }

  /**
   * 确保浏览器已持有某类应用权限：先刷新，缺失则弹系统申请框，完成后再次刷新并返回结果。
   * 用于设置页从禁止切到允许时的前置校验。
   */
  async ensureCategoryGranted(category: AppSystemPermissionId): Promise<boolean> {
    await this.refreshCategoryStatus(category)
    if (this.isGranted(category)) {
      return true
    }
    BrowserLog.info(`[AppPerm] ensureCategoryGranted request cat=${category}`)
    await this.requestCategory(category)
    await this.refreshCategoryStatus(category)
    return this.isGranted(category)
  }

  /**
   * 主动申请单项应用权限：弹系统授权框；若系统不再弹窗则引导至设置页授权。
   * 返回申请完成后浏览器是否已持有该权限。
   */
  async requestCategory(category: AppSystemPermissionId, suppressToast: boolean = false): Promise<boolean> {
    const ctx = BrowserStore.getContext()
    if (ctx === null) {
      BrowserLog.warn(`[AppPerm] requestCategory ${category}: no context`)
      return false
    }
    try {
      if (category === 'notification') {
        return await this.requestNotificationPermission(ctx, suppressToast)
      }
      const atManager = abilityAccessCtrl.createAtManager()
      const wantList = AppPermissionService.permissionsForCategory(category)
      if (wantList.length === 0) {
        return false
      }
      if (AppPermissionService.isCategoryGrantedBySystem(atManager, ctx, category)) {
        this.markGranted(category)
        return true
      }
      BrowserLog.info(`[AppPerm] requestPermissionsFromUser cat=${category} perms=${JSON.stringify(wantList)}`)
      const result = await atManager.requestPermissionsFromUser(ctx, wantList)
      BrowserLog.info(`[AppPerm] requestCategory ${category} result: ${JSON.stringify(result)}`)
      AppPermissionService.applyRequestResult(category, result)
      if (AppPermissionService.isCategoryGrantedBySystem(atManager, ctx, category)) {
        this.markGranted(category)
        return true
      }
      // 用户曾永久拒绝时系统不再弹窗，改走设置页引导授权
      if (!AppPermissionService.wasDialogShown(result)) {
        BrowserLog.info(`[AppPerm] requestPermissionOnSetting cat=${category}`)
        try {
          await atManager.requestPermissionOnSetting(ctx, wantList)
        } catch (settingErr) {
          BrowserLog.warn(`[AppPerm] requestPermissionOnSetting failed: ${JSON.stringify(settingErr)}`)
        }
        if (AppPermissionService.isCategoryGrantedBySystem(atManager, ctx, category)) {
          this.markGranted(category)
          return true
        }
      }
      this.markDenied(category)
      return false
    } catch (e) {
      BrowserLog.warn(`[AppPerm] requestCategory ${category} threw: ${JSON.stringify(e)}`)
      return false
    }
  }

  /**
   * 打开系统「应用信息」页，用户可在其中管理相机/麦克风等权限。
   * 兼容 OpenHarmony（com.ohos.settings）与 HarmonyOS NEXT 设置包名。
   */
  async openAppDetailInSystemSettings(): Promise<boolean> {
    const ctx = BrowserStore.getContext()
    if (ctx === null) {
      BrowserLog.warn('[AppPerm] openAppDetailInSystemSettings no context')
      return false
    }
    const pushParams = ctx.abilityInfo.bundleName
    for (let i = 0; i < SETTINGS_ABILITY_TARGETS.length; i++) {
      const target = SETTINGS_ABILITY_TARGETS[i]
      const want: Want = {
        bundleName: target.bundleName,
        abilityName: target.abilityName,
        uri: 'application_info_entry',
        parameters: {
          pushParams: pushParams
        }
      }
      try {
        await ctx.startAbility(want)
        BrowserLog.info(`[AppPerm] openAppDetail ok bundle=${target.bundleName}`)
        return true
      } catch (err) {
        BrowserLog.warn(`[AppPerm] openAppDetail failed bundle=${target.bundleName}: ${JSON.stringify(err)}`)
      }
    }
    return false
  }

  /** 应用内主动申请单项系统权限（弹系统授权框） */
  async requestAppCategoryPermission(category: AppSystemPermissionId,
    suppressToast: boolean = false): Promise<boolean> {
    const granted = await this.requestCategory(category, suppressToast)
    await this.refreshCategoryStatus(category)
    return granted
  }

  /**
   * 当前应用是否已拥有某个权限类别（读 AppStorage 缓存）。
   * 调用 ensureCategoryGranted / refreshCategoryStatus 后会更新。
   */
  isGranted(category: AppSystemPermissionId): boolean {
    return AppPermissionService.getStatus(category) === 'granted'
  }

  /** 读取最新缓存状态（默认 unknown） */
  static getStatus(category: AppSystemPermissionId): AppPermissionStatus {
    const key = AppPermissionService.statusKey(category)
    const v = AppStorage.get<string>(key)
    if (v === 'granted' || v === 'denied') {
      return v
    }
    return 'unknown'
  }

  /** 标记已授予 */
  markGranted(category: AppSystemPermissionId): void {
    AppStorage.setOrCreate(AppPermissionService.statusKey(category), 'granted')
  }

  /** 标记未授予 */
  markDenied(category: AppSystemPermissionId): void {
    AppStorage.setOrCreate(AppPermissionService.statusKey(category), 'denied')
  }

  private static statusKey(category: string): string {
    return `browser_app_perm_${category}`
  }

  private async hasNotificationStartupDeclined(): Promise<boolean> {
    return SettingsRepository.getInstance().isNotificationStartupDeclined()
  }

  private static sitePolicyOf(perms: SitePermissionsMap, cat: SitePermissionId): string {
    if (cat === 'location') {
      return perms.location
    }
    if (cat === 'camera') {
      return perms.camera
    }
    if (cat === 'microphone') {
      return perms.microphone
    }
    return perms.notification
  }

  private async checkLocationGranted(ctx: common.UIAbilityContext,
    atManager: abilityAccessCtrl.AtManager): Promise<boolean> {
    const tokenId = ctx.applicationInfo.accessTokenId
    const r1 = atManager.checkAccessTokenSync(tokenId, 'ohos.permission.LOCATION')
    const r2 = atManager.checkAccessTokenSync(tokenId, 'ohos.permission.APPROXIMATELY_LOCATION')
    return r1 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ||
      r2 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  private async checkStandardGranted(ctx: common.UIAbilityContext,
    atManager: abilityAccessCtrl.AtManager, perm: Permissions): Promise<boolean> {
    const tokenId = ctx.applicationInfo.accessTokenId
    const r = atManager.checkAccessTokenSync(tokenId, perm)
    return r === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  private static permissionsForCategory(category: AppSystemPermissionId): Permissions[] {
    if (category === 'location') {
      return ['ohos.permission.LOCATION' as Permissions, 'ohos.permission.APPROXIMATELY_LOCATION' as Permissions]
    }
    if (category === 'camera') {
      return ['ohos.permission.CAMERA' as Permissions]
    }
    if (category === 'microphone') {
      return ['ohos.permission.MICROPHONE' as Permissions]
    }
    if (category === 'image_video') {
      return [READ_IMAGE_VIDEO, WRITE_IMAGE_VIDEO]
    }
    return []
  }

  private static isImageVideoGrantedBySystem(atManager: abilityAccessCtrl.AtManager,
    ctx: common.UIAbilityContext): boolean {
    const tokenId = ctx.applicationInfo.accessTokenId
    const read = atManager.checkAccessTokenSync(tokenId, READ_IMAGE_VIDEO)
    const write = atManager.checkAccessTokenSync(tokenId, WRITE_IMAGE_VIDEO)
    return read === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ||
      write === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
  }

  private static isCategoryGrantedBySystem(atManager: abilityAccessCtrl.AtManager,
    ctx: common.UIAbilityContext, category: AppSystemPermissionId): boolean {
    const tokenId = ctx.applicationInfo.accessTokenId
    if (category === 'location') {
      const r1 = atManager.checkAccessTokenSync(tokenId, 'ohos.permission.LOCATION')
      const r2 = atManager.checkAccessTokenSync(tokenId, 'ohos.permission.APPROXIMATELY_LOCATION')
      return r1 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ||
        r2 === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    }
    if (category === 'image_video') {
      return AppPermissionService.isImageVideoGrantedBySystem(atManager, ctx)
    }
    const perms = AppPermissionService.permissionsForCategory(category)
    for (let i = 0; i < perms.length; i++) {
      const status = atManager.checkAccessTokenSync(tokenId, perms[i])
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
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

  private static applyRequestResult(category: AppSystemPermissionId, result: PermissionRequestResult): void {
    const authResults: number[] = result.authResults
    const permissions: string[] = result.permissions
    if (category === 'location') {
      let anyGranted = false
      for (let i = 0; i < permissions.length; i++) {
        const p = permissions[i]
        if (p === 'ohos.permission.LOCATION' || p === 'ohos.permission.APPROXIMATELY_LOCATION') {
          if (authResults[i] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
            anyGranted = true
          }
        }
      }
      if (anyGranted) {
        AppPermissionService.getInstance().markGranted('location')
      } else {
        AppPermissionService.getInstance().markDenied('location')
      }
      return
    }
    if (category === 'image_video') {
      let anyGranted = false
      for (let i = 0; i < permissions.length; i++) {
        if (authResults[i] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          anyGranted = true
        }
      }
      if (anyGranted) {
        AppPermissionService.getInstance().markGranted('image_video')
      } else {
        AppPermissionService.getInstance().markDenied('image_video')
      }
      return
    }
    for (let i = 0; i < permissions.length; i++) {
      AppPermissionService.getInstance().applyOneResult(permissions[i],
        authResults[i] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)
    }
  }

  /**
   * 申请系统通知权限：优先 requestEnableNotification；1600004 时打开系统通知设置页。
   */
  private async requestNotificationPermission(ctx: common.UIAbilityContext,
    suppressToast: boolean = false): Promise<boolean> {
    const before = await notificationManager.isNotificationEnabled()
    if (before) {
      this.markGranted('notification')
      return true
    }
    BrowserLog.info('[AppPerm] requestEnableNotification begin')
    try {
      await notificationManager.requestEnableNotification(ctx)
    } catch (err) {
      const code = (err as BusinessError).code ?? 0
      BrowserLog.warn(`[AppPerm] requestEnableNotification failed code=${code}`)
      if (code === NOTIFICATION_DENIED_CODE) {
        if (!suppressToast) {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.notification_permission_open_settings')))
        }
        await this.openAppNotificationSettings(ctx)
      }
    }
    const after = await notificationManager.isNotificationEnabled()
    BrowserLog.info(`[AppPerm] requestNotificationPermission done enabled=${after}`)
    if (after) {
      this.markGranted('notification')
      void SettingsRepository.getInstance().setNotificationStartupDeclined(false)
      return true
    }
    this.markDenied('notification')
    await SettingsRepository.getInstance().setNotificationStartupDeclined(true)
    BrowserLog.info('[AppPerm] notification startup declined persisted')
    return false
  }

  /** 打开系统通知管理页；失败时回退到应用详情设置 */
  private async openAppNotificationSettings(ctx: common.UIAbilityContext): Promise<void> {
    BrowserLog.info('[AppPerm] openNotificationSettings begin')
    try {
      await notificationManager.openNotificationSettings(ctx)
      BrowserLog.info('[AppPerm] openNotificationSettings ok')
      return
    } catch (err) {
      BrowserLog.warn(`[AppPerm] openNotificationSettings failed: ${JSON.stringify(err)}`)
    }
    const opened = await AppPermissionService.getInstance().openAppDetailInSystemSettings()
    if (!opened) {
      BrowserLog.warn('[AppPerm] openNotificationSettings fallback failed')
    }
  }

  private applyOneResult(p: string, granted: boolean): void {
    if (p === 'ohos.permission.LOCATION' || p === 'ohos.permission.APPROXIMATELY_LOCATION') {
      if (granted) {
        this.markGranted('location')
      } else {
        this.markDenied('location')
      }
    } else if (p === 'ohos.permission.CAMERA') {
      if (granted) {
        this.markGranted('camera')
      } else {
        this.markDenied('camera')
      }
    } else if (p === 'ohos.permission.MICROPHONE') {
      if (granted) {
        this.markGranted('microphone')
      } else {
        this.markDenied('microphone')
      }
    } else if (p === 'ohos.permission.READ_IMAGEVIDEO' || p === 'ohos.permission.WRITE_IMAGEVIDEO') {
      if (granted) {
        this.markGranted('image_video')
      } else {
        this.markDenied('image_video')
      }
    }
  }
}
