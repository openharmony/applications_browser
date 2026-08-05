import { relationalStore } from '@kit.ArkData'
import { BrowserDatabase } from './BrowserDatabase'
import { BrowserStrings } from '../utils/BrowserStrings'
import { SettingsKeys, DEFAULT_BROWSER_SETTINGS, BrowserSettings, SettingsUpdateInput,
  DEFAULT_SITE_PERMISSIONS, SitePermissionId, SitePermissionPolicy, SitePermissionsMap,
  LastActiveTabRecord } from '../model/BrowserSettings'

/** 设置持久化，对应 browser_settings 表 */
export class SettingsRepository {
  private static instance: SettingsRepository | null = null

  /** 获取设置仓库单例实例 */
  static getInstance(): SettingsRepository {
    if (SettingsRepository.instance === null) {
      SettingsRepository.instance = new SettingsRepository()
    }
    return SettingsRepository.instance
  }

  /** 为缺失的设置项写入默认值 */
  async initDefaults(): Promise<void> {
    const keys: string[] = [
      SettingsKeys.DEFAULT_SEARCH_ENGINE,
      SettingsKeys.THEME_MODE,
      SettingsKeys.IMAGE_LESS_MODE,
      SettingsKeys.NIGHT_MODE,
      SettingsKeys.INCOGNITO_MODE,
      SettingsKeys.UA_MODE,
      SettingsKeys.FONT_SIZE,
      SettingsKeys.SEARCH_HISTORY,
      SettingsKeys.SITE_PERMISSIONS,
      SettingsKeys.LAST_ACTIVE_TAB,
      SettingsKeys.SSL_ALLOWED_HOSTS,
      SettingsKeys.NOTIFICATION_STARTUP_DECLINED
    ]
    for (const key of keys) {
      const existing = await this.getValue(key)
      if (existing === null) {
        await this.setValue(key, this.defaultValueForKey(key))
      }
    }
  }

  /** 按键读取设置值，不存在则返回 null */
  async getValue(key: string): Promise<string | null> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('browser_settings')
    predicates.equalTo('setting_key', key)
    const rs = await store.query(predicates, ['setting_value'])
    try {
      if (rs.goToFirstRow()) {
        return rs.getString(rs.getColumnIndex('setting_value'))
      }
      return null
    } finally {
      rs.close()
    }
  }

  /** 写入或更新指定键的设置值 */
  async setValue(key: string, value: string): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const now = Date.now()
    const existing = await this.getValue(key)
    const bucket: relationalStore.ValuesBucket = {
      setting_key: key,
      setting_value: value,
      updated_at: now
    }
    if (existing === null) {
      await store.insert('browser_settings', bucket)
    } else {
      const predicates = new relationalStore.RdbPredicates('browser_settings')
      predicates.equalTo('setting_key', key)
      await store.update(bucket, predicates)
    }
  }

  /** 从数据库加载并组装浏览器设置对象 */
  async loadSettings(): Promise<BrowserSettings> {
    const engine = await this.getValue(SettingsKeys.DEFAULT_SEARCH_ENGINE)
    const theme = await this.getValue(SettingsKeys.THEME_MODE)
    const imageLess = await this.getValue(SettingsKeys.IMAGE_LESS_MODE)
    const night = await this.getValue(SettingsKeys.NIGHT_MODE)
    const incognito = await this.getValue(SettingsKeys.INCOGNITO_MODE)
    const ua = await this.getValue(SettingsKeys.UA_MODE)
    const font = await this.getValue(SettingsKeys.FONT_SIZE)
    return {
      defaultSearchEngine: engine ?? DEFAULT_BROWSER_SETTINGS.defaultSearchEngine,
      themeMode: theme ?? DEFAULT_BROWSER_SETTINGS.themeMode,
      imageLessMode: imageLess === 'true',
      nightMode: night === 'true',
      incognitoMode: incognito === 'true',
      uaMode: ua ?? DEFAULT_BROWSER_SETTINGS.uaMode,
      fontSize: BrowserStrings.normalizeFontSizeKey(font ?? DEFAULT_BROWSER_SETTINGS.fontSize)
    }
  }

  /** 读取最后活跃页签记录 */
  async getLastActiveTab(): Promise<LastActiveTabRecord | null> {
    const raw = await this.getValue(SettingsKeys.LAST_ACTIVE_TAB)
    if (!raw || raw.trim().length === 0) {
      return null
    }
    try {
      const parsed = JSON.parse(raw) as LastActiveTabRecord
      if (parsed?.id && typeof parsed.id === 'string') {
        return { id: parsed.id, incognito: parsed.incognito === true }
      }
      return null
    } catch {
      return null
    }
  }

  /** 持久化最后活跃页签 */
  async setLastActiveTab(record: LastActiveTabRecord): Promise<void> {
    await this.setValue(SettingsKeys.LAST_ACTIVE_TAB, JSON.stringify(record))
  }

  /** 清除最后活跃页签记录 */
  async clearLastActiveTab(): Promise<void> {
    await this.setValue(SettingsKeys.LAST_ACTIVE_TAB, '')
  }

  /** 将设置对象中的变更项持久化到数据库 */
  async saveSettings(settings: SettingsUpdateInput): Promise<void> {
    if (settings.defaultSearchEngine !== undefined) {
      await this.setValue(SettingsKeys.DEFAULT_SEARCH_ENGINE, settings.defaultSearchEngine)
    }
    if (settings.themeMode !== undefined) {
      await this.setValue(SettingsKeys.THEME_MODE, settings.themeMode)
    }
    if (settings.imageLessMode !== undefined) {
      await this.setValue(SettingsKeys.IMAGE_LESS_MODE, settings.imageLessMode ? 'true' : 'false')
    }
    if (settings.nightMode !== undefined) {
      await this.setValue(SettingsKeys.NIGHT_MODE, settings.nightMode ? 'true' : 'false')
    }
    if (settings.incognitoMode !== undefined) {
      await this.setValue(SettingsKeys.INCOGNITO_MODE, settings.incognitoMode ? 'true' : 'false')
    }
    if (settings.uaMode !== undefined) {
      await this.setValue(SettingsKeys.UA_MODE, settings.uaMode)
    }
    if (settings.fontSize !== undefined) {
      await this.setValue(SettingsKeys.FONT_SIZE, settings.fontSize)
    }
  }

  /** 读取搜索历史关键词列表 */
  async getSearchHistory(): Promise<string[]> {
    const raw = await this.getValue(SettingsKeys.SEARCH_HISTORY)
    if (!raw) {
      return []
    }
    try {
      const parsed = JSON.parse(raw) as string[]
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  }

  /** 保存搜索历史，最多保留 20 条 */
  async setSearchHistory(list: string[]): Promise<void> {
    await this.setValue(SettingsKeys.SEARCH_HISTORY, JSON.stringify(list.slice(0, 20)))
  }

  /** 读取网站权限策略映射 */
  async getSitePermissions(): Promise<SitePermissionsMap> {
    const raw = await this.getValue(SettingsKeys.SITE_PERMISSIONS)
    if (!raw) {
      return {
        location: DEFAULT_SITE_PERMISSIONS.location,
        camera: DEFAULT_SITE_PERMISSIONS.camera,
        microphone: DEFAULT_SITE_PERMISSIONS.microphone,
        notification: DEFAULT_SITE_PERMISSIONS.notification
      }
    }
    try {
      const parsed = JSON.parse(raw) as SitePermissionsMap
      return {
        location: SettingsRepository.normalizeSitePermission(parsed.location),
        camera: SettingsRepository.normalizeSitePermission(parsed.camera),
        microphone: SettingsRepository.normalizeSitePermission(parsed.microphone),
        notification: SettingsRepository.normalizeSitePermission(parsed.notification)
      }
    } catch {
      return {
        location: DEFAULT_SITE_PERMISSIONS.location,
        camera: DEFAULT_SITE_PERMISSIONS.camera,
        microphone: DEFAULT_SITE_PERMISSIONS.microphone,
        notification: DEFAULT_SITE_PERMISSIONS.notification
      }
    }
  }

  /** 更新单项网站权限策略 */
  async setSitePermission(permId: SitePermissionId, policy: SitePermissionPolicy): Promise<void> {
    const current = await this.getSitePermissions()
    if (permId === 'location') {
      current.location = policy
    } else if (permId === 'camera') {
      current.camera = policy
    } else if (permId === 'microphone') {
      current.microphone = policy
    } else {
      current.notification = policy
    }
    await this.setValue(SettingsKeys.SITE_PERMISSIONS, JSON.stringify(current))
  }

  /**
   * 读取 origin 级别持久化策略。
   * 返回 Map 视图，key 形如 `https://m.amap.com|location`，value 为 allow/deny/ask。
   * 应用重启后该 Map 仍包含用户对各 origin 的"始终允许 / 始终禁止"决定。
   */
  async getOriginPermissions(): Promise<Map<string, SitePermissionPolicy>> {
    const raw = await this.getValue(SettingsKeys.ORIGIN_PERMISSIONS)
    const result: Map<string, SitePermissionPolicy> = new Map()
    if (!raw) {
      return result
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, string>
      const keys: string[] = Object.keys(parsed)
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i]
        const v = parsed[k]
        const norm = SettingsRepository.normalizeSitePermission(v)
        result.set(k, norm)
      }
    } catch {
      // 解析失败时返回空 Map（视为未答过）
    }
    return result
  }

  /**
   * 写入/删除单条 origin 级别策略。
   * policy 为 'allow' / 'deny' / 'ask' 时持久化；为 'clear' 时删除该条目（恢复 ask 询问）。
   */
  async setOriginPermission(origin: string, permId: SitePermissionId, policy: SitePermissionPolicy | 'clear'): Promise<void> {
    const key = `${origin}|${permId}`
    const current = await this.getOriginPermissions()
    if (policy === 'clear') {
      current.delete(key)
    } else {
      current.set(key, policy)
    }
    await this.setValue(SettingsKeys.ORIGIN_PERMISSIONS, JSON.stringify(this.mapToRecord(current)))
  }

  private mapToRecord(map: Map<string, SitePermissionPolicy>): Record<string, string> {
    const out: Record<string, string> = {}
    const it: IterableIterator<string> = map.keys()
    let r: IteratorResult<string> = it.next()
    while (!r.done) {
      const k: string = r.value
      const v: SitePermissionPolicy | undefined = map.get(k)
      if (v !== undefined) {
        out[k] = v
      }
      r = it.next()
    }
    return out
  }

  /** 启动时用户是否已拒绝通知授权（持久化，避免每次冷启动重复弹窗） */
  async isNotificationStartupDeclined(): Promise<boolean> {
    const raw = await this.getValue(SettingsKeys.NOTIFICATION_STARTUP_DECLINED)
    return raw === 'true'
  }

  /** 记录用户已拒绝启动通知授权 */
  async setNotificationStartupDeclined(declined: boolean): Promise<void> {
    await this.setValue(SettingsKeys.NOTIFICATION_STARTUP_DECLINED, declined ? 'true' : 'false')
  }

  /** 校验并规范化权限策略值 */
  private static normalizeSitePermission(value: string | undefined): SitePermissionPolicy {
    if (value === 'allow' || value === 'deny') {
      return value
    }
    // 兼容旧持久化数据：'ask' 全部当作 'deny'（已移除询问模式）
    return 'deny'
  }

  /** 根据设置键返回对应的默认值 */
  private defaultValueForKey(key: string): string {
    switch (key) {
      case SettingsKeys.DEFAULT_SEARCH_ENGINE:
        return DEFAULT_BROWSER_SETTINGS.defaultSearchEngine
      case SettingsKeys.THEME_MODE:
        return DEFAULT_BROWSER_SETTINGS.themeMode
      case SettingsKeys.IMAGE_LESS_MODE:
        return 'false'
      case SettingsKeys.NIGHT_MODE:
        return 'false'
      case SettingsKeys.INCOGNITO_MODE:
        return 'false'
      case SettingsKeys.UA_MODE:
        return DEFAULT_BROWSER_SETTINGS.uaMode
      case SettingsKeys.FONT_SIZE:
        return DEFAULT_BROWSER_SETTINGS.fontSize
      case SettingsKeys.SEARCH_HISTORY:
        return '[]'
      case SettingsKeys.SITE_PERMISSIONS:
        return JSON.stringify(DEFAULT_SITE_PERMISSIONS)
      case SettingsKeys.ORIGIN_PERMISSIONS:
        return '{}'
      case SettingsKeys.LAST_ACTIVE_TAB:
        return ''
      case SettingsKeys.SSL_ALLOWED_HOSTS:
        return '[]'
      case SettingsKeys.NOTIFICATION_STARTUP_DECLINED:
        return 'false'
      default:
        return ''
    }
  }
}
