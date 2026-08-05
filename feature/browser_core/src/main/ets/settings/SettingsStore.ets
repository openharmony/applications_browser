import { SettingsRepository } from 'common'
import { AppStorageKeys } from 'common'
import {
  BrowserSettings,
  DEFAULT_BROWSER_SETTINGS,
  SitePermissionId,
  SitePermissionPolicy,
  SitePermissionsMap,
  DEFAULT_SITE_PERMISSIONS
} from 'common'
import { AppStateSync } from '../AppStateSync'
import { BrowserLog } from 'common'
import { BrowserStrings } from 'common'
import { SystemFontSync } from './SystemFontSync'
import { SystemThemeSync } from './SystemThemeSync'
import { FontScaleService } from './FontScaleService'
import { webview } from '@kit.ArkWeb'
/** 搜索引擎、主题、无图/夜间开关等业务设置 */
export class SettingsStore {
  private static instance: SettingsStore | null = null

  /** 获取 SettingsStore 单例 */
  static getInstance(): SettingsStore {
    if (SettingsStore.instance === null) {
      SettingsStore.instance = new SettingsStore()
    }
    return SettingsStore.instance
  }

  /** 加载完整浏览器设置 */
  async getSettings(): Promise<BrowserSettings> {
    return SettingsRepository.getInstance().loadSettings()
  }

  /** 设置默认搜索引擎 */
  async setSearchEngine(engineId: string): Promise<void> {
    await SettingsRepository.getInstance().saveSettings({ defaultSearchEngine: engineId })
    await AppStateSync.refreshSettings()
  }

  /** 获取当前搜索引擎 ID */
  getSearchEngine(): string {
    return AppStorage.get<string>('browser_search_engine') ?? DEFAULT_BROWSER_SETTINGS.defaultSearchEngine
  }

  /** 设置主题模式（system/light/dark） */
  async setThemeMode(mode: string): Promise<void> {
    await SettingsRepository.getInstance().saveSettings({
      themeMode: mode,
      nightMode: mode === 'dark'
    })
  }

  /** 判断当前是否为深色模式（读有效 theme，非偏好） */
  isDarkMode(): boolean {
    return (AppStorage.get<string>(AppStorageKeys.THEME) ?? 'light') === 'dark'
  }

  /** 应用主题偏好并持久化 */
  async applyThemePreference(preference: string): Promise<void> {
    const normalized = BrowserStrings.normalizeThemeModeKey(preference)
    const dark = normalized === 'dark'
    await SettingsRepository.getInstance().saveSettings({
      themeMode: normalized,
      nightMode: normalized === 'dark' || (normalized === 'system' && SystemThemeSync.isSystemDark())
    })
  }

  /** 切换深色/浅色模式并返回新状态（兼容旧调用） */
  async toggleDarkMode(): Promise<boolean> {
    const next = !this.isDarkMode()
    await this.applyDarkMode(next)
    return next
  }

  /** 统一设置深色/夜间模式（二者等价，同时持久化 DB + 同步 AppStorage） */
  async applyDarkMode(on: boolean): Promise<void> {
    await this.applyThemePreference(on ? 'dark' : 'light')
  }

  /** 设置页面字体大小（先同步 AppStorage 触发 UI 实时刷新，再持久化） */
  async setFontSize(size: string): Promise<void> {
    const normalized = BrowserStrings.normalizeFontSizeKey(size)
    AppStorage.setOrCreate(AppStorageKeys.FONT_SIZE, normalized)
    if (normalized === 'system') {
      SystemFontSync.refreshForFollowSystemMode()
    } else {
      FontScaleService.publish('setFontSize', true)
    }
    BrowserLog.info(`[Font] setFontSize=${normalized}`)
    await SettingsRepository.getInstance().saveSettings({ fontSize: normalized })
  }

  /** 获取当前字体大小设置 */
  getFontSize(): string {
    const raw = AppStorage.get<string>('browser_font_size') ?? DEFAULT_BROWSER_SETTINGS.fontSize
    return BrowserStrings.normalizeFontSizeKey(raw)
  }

  /** 获取搜索历史关键词列表 */
  async getSearchHistory(): Promise<string[]> {
    return SettingsRepository.getInstance().getSearchHistory()
  }

  /** 更新搜索历史关键词列表 */
  async setSearchHistory(list: string[]): Promise<void> {
    await SettingsRepository.getInstance().setSearchHistory(list)
    await AppStateSync.refreshSettings()
  }

  /** 获取网站权限策略映射 */
  getSitePermissions(): SitePermissionsMap {
    const stored = AppStorage.get<SitePermissionsMap>(AppStorageKeys.SITE_PERMISSIONS)
    if (stored === undefined || stored === null) {
      return {
        location: DEFAULT_SITE_PERMISSIONS.location,
        camera: DEFAULT_SITE_PERMISSIONS.camera,
        microphone: DEFAULT_SITE_PERMISSIONS.microphone,
        notification: DEFAULT_SITE_PERMISSIONS.notification
      }
    }
    return stored
  }

  /** 获取单项网站权限策略 */
  getSitePermission(permId: SitePermissionId): SitePermissionPolicy {
    const perms = SettingsStore.getInstance().getSitePermissions()
    if (permId === 'location') {
      return perms.location
    }
    if (permId === 'camera') {
      return perms.camera
    }
    if (permId === 'microphone') {
      return perms.microphone
    }
    return perms.notification
  }
  /** 设置单项网站权限策略（含应用权限 clamp，供内部兜底调用） */
  async setSitePermission(permId: SitePermissionId, policy: SitePermissionPolicy): Promise<void> {
    const finalPolicy = this.clampPolicyByAppPermission(permId, policy)
    await this.setSitePermissionUnchecked(permId, finalPolicy)
  }

  /** 直接持久化网站权限策略，不做应用权限 clamp（由调用方完成校验） */
  async setSitePermissionUnchecked(permId: SitePermissionId, policy: SitePermissionPolicy): Promise<void> {
    await SettingsRepository.getInstance().setSitePermission(permId, policy)
    await AppStateSync.refreshSitePermissions()
  }

  /**
   * 读取 origin 级别持久化策略。key 形如 `https://m.amap.com|location`。
   * 应用重启后该 Map 仍包含用户对各 origin 的"始终允许 / 始终禁止"决定。
   */
  async getOriginPermissions(): Promise<Map<string, SitePermissionPolicy>> {
    return SettingsRepository.getInstance().getOriginPermissions()
  }

  /**
   * 设置单条 origin 级别策略。policy 为 'allow'/'deny'/'ask' 持久化；'clear' 删除该条目。
   * 约束：若应用未持有该类别的应用级权限，allow/ask 强制为 deny。
   */
  async setOriginPermission(origin: string, permId: SitePermissionId, policy: SitePermissionPolicy | 'clear'): Promise<void> {
    let finalPolicy: SitePermissionPolicy | 'clear' = policy
    if (policy !== 'clear') {
      finalPolicy = this.clampPolicyByAppPermission(permId, policy)
    }
    await SettingsRepository.getInstance().setOriginPermission(origin, permId, finalPolicy)
    await AppStateSync.refreshSitePermissions()
  }

  /**
   * 读取受应用权限约束后的策略：
   * - 若应用未持有该类别的应用级权限 → 始终返回 'deny'
   * - 否则返回调用方传入的策略
   */
  clampPolicyByAppPermission(permId: SitePermissionId, policy: SitePermissionPolicy): SitePermissionPolicy {
    // 动态 import 避免循环依赖
    const statusKey = `browser_app_perm_${permId}`
    const v = AppStorage.get<string>(statusKey)
    if (v === undefined || v === null || v === 'unknown' || v === 'denied') {
      return 'deny'
    }
    return policy
  }

  /** 当前应用是否已持有该类别应用级权限（用于 UI 决定是否禁用 allow/ask） */
  isAppPermissionGranted(permId: SitePermissionId): boolean {
    const statusKey = `browser_app_perm_${permId}`
    return AppStorage.get<string>(statusKey) === 'granted'
  }

  /** 设置无图模式 */
  async setImageLessMode(on: boolean): Promise<void> {
    await SettingsRepository.getInstance().saveSettings({ imageLessMode: on })
    await AppStateSync.refreshSettings()
  }

  /** 无图模式是否开启 */
  isImageLessMode(): boolean {
    return AppStorage.get<boolean>(AppStorageKeys.IMAGE_LESS_MODE) ?? DEFAULT_BROWSER_SETTINGS.imageLessMode
  }

  /** 设置夜间浏览模式（与深色主题同步） */
  async setNightMode(on: boolean): Promise<void> {
    await this.applyDarkMode(on)
  }

  /** 夜间浏览模式是否开启（等同 isDarkMode） */
  isNightMode(): boolean {
    return this.isDarkMode()
  }

  /** 清理 Cookie 与网站缓存数据 */
  async clearCookiesAndCache(): Promise<void> {
    try {
      webview.WebviewController.initializeWebEngine()
      await webview.WebCookieManager.clearAllCookies()
      BrowserLog.info('clearCookiesAndCache done')
    } catch (err) {
      BrowserLog.error(`clearCookiesAndCache failed: ${JSON.stringify(err)}`)
      throw err as Error
    }
  }
}
