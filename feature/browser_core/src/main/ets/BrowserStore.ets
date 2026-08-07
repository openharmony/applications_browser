import { common } from '@kit.AbilityKit'
import { BrowserLog } from 'common'
import { BrowserStrings } from 'common'
import { bindBrowserContext } from 'common'
import { AppInitGate } from 'common'
import { BrowserRouterBridge } from 'common'
import { BrowserUtils } from 'common'
import { AddTabOptions, AppStorageKeys, BOOKMARK_LIMIT, BrowseTabPatch, DownloadRequest,
  FeaturePanelType,
  OpenShareOptions,
  ShareSheetParams,
  ShortcutMoveDirection,
  TAB_LIMIT,
  TAB_LIMIT_DISPLAY,
  reorderArrayIds
} from 'common'
import { BookmarkItem, BOOKMARK_ROOT_ID, BookmarkUpdateInput, CreateBookmarkItemInput, createBookmarkItem } from 'common'
import { SitePermissionId, SitePermissionPolicy, SitePermissionsMap } from 'common'
import { TabSession } from 'common'
import { DownloadTask } from 'common'
import { HistoryEntry } from 'common'
import { BookmarkRepository } from 'common'
import { HistoryRepository } from 'common'
import { BrowserApp } from './BrowserApp'
import { BrowserNavigation } from './BrowserNavigation'
import { DownloadManager, OpenDownloadResult, ShareService } from './download_svc/DownloadManager'
import { DownloadPathService } from './download_svc/DownloadPathService'
import { IncognitoPolicy } from './security/IncognitoPolicy'
import { NavigationController } from './navigation/NavigationController'
import { SettingsRepository } from 'common'
import { SettingsStore } from './settings/SettingsStore'
import { SystemThemeSync } from './settings/SystemThemeSync'
import { ShortcutManager } from './ShortcutManager'
import { TabManager } from './tab/TabManager'
import { AppStateSync } from './AppStateSync'
import { TabThumbnailService } from './tab/TabThumbnailService'
import { TabThumbnailRetryService } from './tab/TabThumbnailRetryService'
import { WebStabilityGuard } from './web/WebStabilityGuard'
import { WebPageController } from './web/WebPageController'
import { BrowserWindowService } from './settings/BrowserWindowService'
import { GalleryPermissionHelper } from './security/GalleryPermissionHelper'
import { ImageClipboardService } from './web/ImageClipboardService'
import { ScanQrService } from './navigation/ScanQrService'
/**
 * UI 层统一入口，委托 services/repository 实现业务逻辑。
 * 保持与原有页面/组件的调用习惯兼容。
 */
export class BrowserStore {
  private static context: common.UIAbilityContext | null = null

  /** 绑定 UIAbility 上下文，供国际化与资源访问使用 */
  static bindContext(context: common.UIAbilityContext): void {
    BrowserStore.context = context
    bindBrowserContext(context)
  }

  /** 获取已绑定的 UIAbility 上下文 */
  static getContext(): common.UIAbilityContext | null {
    return BrowserStore.context
  }

  /** 等待 BrowserApp 初始化完成（标签写操作须先 await） */
  static async whenReady(): Promise<void> {
    const ctx = BrowserStore.context ?? BrowserStore.getContext()
    if (!ctx) {
      return
    }
    await BrowserApp.getInstance().ensureInitialized(ctx)
  }

  /** 初始化浏览器应用（数据库、种子数据、AppStorage 同步） */
  static async init(context?: common.UIAbilityContext): Promise<void> {
    const ctx = context ?? BrowserStore.context
    if (!ctx) {
      return
    }
    const initPromise = BrowserApp.getInstance().ensureInitialized(ctx)
    AppInitGate.bind(initPromise)
    await initPromise
  }

  /** 显示 Toast 提示，约 2.2 秒后自动清除 */
  static showToast(msg: string): void {
    AppStorage.set(AppStorageKeys.TOAST, msg)
    setTimeout(() => {
      if (AppStorage.get<string>(AppStorageKeys.TOAST) === msg) {
        AppStorage.set(AppStorageKeys.TOAST, '')
      }
    }, 2200)
  }

  /** 获取全部标签页列表（含无痕）；AppStorage 未就绪时回退到 TabManager */
  static getTabs(): TabSession[] {
    const fromManager = TabManager.getInstance().getAllTabs()
    const linked = AppStorage.get<TabSession[]>(AppStorageKeys.TABS)
    if (linked !== undefined && linked !== null && linked.length > 0) {
      return linked
    }
    return fromManager
  }

  /** 获取指定分区标签页数量（与标签管理页计数一致） */
  static getTabCount(incognito: boolean): number {
    return BrowserStore.getTabs().filter((t) => incognito ? t.isIncognito : !t.isIncognito).length
  }

  /** 标签数量 UI 展示值（封顶 TAB_LIMIT_DISPLAY，含主页） */
  static getTabDisplayCount(incognito?: boolean): number {
    const count = incognito === undefined ?
      BrowserStore.getTabs().length :
      BrowserStore.getTabCount(incognito)
    return Math.min(count, TAB_LIMIT_DISPLAY)
  }

  /** 指定分区标签是否已达实际上限 */
  static isTabPartitionFull(incognito: boolean): boolean {
    return BrowserStore.getTabCount(incognito) >= TAB_LIMIT
  }

  /** 标签数量达上限提示 */
  static showTabLimitReachedToast(): void {
    BrowserStore.showToast(BrowserStrings.tabLimitReached())
  }

  /** 导航栏徽章：当前浏览模式下的标签页展示数量 */
  static getNavTabCount(): number {
    const incognito = AppStorage.get<boolean>(AppStorageKeys.INCOGNITO) ?? false
    return BrowserStore.getTabDisplayCount(incognito)
  }

  /** 刷新标签列表到 AppStorage，供导航栏与标签管理页同步 */
  static async refreshTabList(): Promise<void> {
    await AppStateSync.refreshTabs(TabManager.getInstance().getAllTabs())
  }

  /** 当前模式下若无标签页，则补建一个主页占位标签（可指定分区） */
  static async ensureDefaultTabForCurrentMode(incognito?: boolean): Promise<void> {
    await BrowserStore.whenReady()
    await TabManager.getInstance().ensureDefaultTabForCurrentMode(incognito)
  }

  /** 持久化普通标签页列表到仓库 */
  static async setTabs(tabs: TabSession[]): Promise<void> {
    await BrowserStore.whenReady()
    AppStorage.setOrCreate(AppStorageKeys.TABS_PERSISTED, tabs.filter((t) => !t.isIncognito))
    for (const t of tabs.filter((t) => !t.isIncognito)) {
      await TabManager.getInstance().updateTab(t)
    }
  }

  /** 获取普通（非无痕）标签页数量 */
  static getNormalTabCount(): number {
    return BrowserStore.getTabCount(false)
  }

  /** 获取无痕标签页数量 */
  static getIncognitoTabCount(): number {
    return BrowserStore.getTabCount(true)
  }

  /** 新建标签页并返回会话实体 */
  static async addTabEntry(opts: AddTabOptions): Promise<TabSession | null> {
    return TabManager.getInstance().addTab(opts)
  }

  /** 在指定分区新建主页占位标签，并同步模式与 UI 列表 */
  static async createWindowTab(incognito: boolean): Promise<TabSession> {
    await BrowserStore.whenReady()
    BrowserLog.info(`createWindowTab begin incognito=${incognito}`)
    try {
      const tabOpts: AddTabOptions = {
        isHome: true,
        incognito: incognito,
        title: BrowserStrings.newTab()
      }
      const tab = await TabManager.getInstance().addTab(tabOpts)
      if (!tab) {
        throw new Error('createWindowTab: tab limit reached')
      }
      BrowserLog.info(`createWindowTab done id=${tab.id} isIncognito=${tab.isIncognito}`)
      return tab
    } catch (err) {
      BrowserLog.error(`createWindowTab failed: ${JSON.stringify(err)}`)
      throw new Error(`createWindowTab failed: ${JSON.stringify(err)}`)
    }
  }

  /** 按 ID 关闭并删除标签页 */
  static async removeTabById(id: string): Promise<void> {
    await BrowserStore.whenReady()
    const tab = BrowserStore.getTabs().find((t) => t.id === id)
    if (tab?.thumbnailPath) {
      TabThumbnailService.getInstance().deleteThumbnail(tab.thumbnailPath)
    }
    await TabManager.getInstance().removeTab(id)
  }

  /** 页签管理：同一分区内调整标签顺序 */
  static async reorderTabs(incognito: boolean, fromIndex: number, toIndex: number): Promise<void> {
    await BrowserStore.whenReady()
    await TabManager.getInstance().reorderTabsInPartition(incognito, fromIndex, toIndex)
  }

  /** 关闭指定类型的全部标签页 */
  static async closeAllTabs(incognito: boolean): Promise<void> {
    await BrowserStore.whenReady()
    BrowserLog.info(`closeAllTabs begin incognito=${incognito}`)
    const toClose = BrowserStore.getTabs().filter((t) => t.isIncognito === incognito)
    for (const tab of toClose) {
      if (tab.thumbnailPath) {
        TabThumbnailService.getInstance().deleteThumbnail(tab.thumbnailPath)
      }
    }
    await TabManager.getInstance().closeAllTabs(incognito)
    BrowserLog.info(`closeAllTabs done`)
  }

  /** 从 AppStorage 获取书签列表 */
  static getBookmarks(): BookmarkItem[] {
    return AppStorage.get<BookmarkItem[]>(AppStorageKeys.BOOKMARKS) ?? []
  }

  /** 获取指定父文件夹下的子文件夹列表 */
  static getChildFolders(parentId: string): BookmarkItem[] {
    return BrowserStore.bookmarksInFolder(parentId).filter((b) => b.isFolder)
  }

  /** 获取所有文件夹 ID 列表 */
  static getAllFolderIds(): string[] {
    return BrowserStore.getBookmarks().filter((b) => b.isFolder).map((b) => b.id)
  }

  /** 获取文件夹路径展示标签（根目录或文件夹标题） */
  static folderLocationLabel(parentId: string): string {
    if (!parentId || parentId === BOOKMARK_ROOT_ID) {
      return BrowserStrings.bookmarkRoot()
    }
    return BrowserStore.getFolderTitle(parentId) || BrowserStrings.bookmarkRoot()
  }

  /** 从数据库刷新书签到 AppStorage */
  static async refreshBookmarks(): Promise<void> {
    await AppStateSync.refreshBookmarks()
  }

  /** 获取根目录下的一级文件夹 ID 列表 */
  static getBookmarkFolders(): string[] {
    return BrowserStore.getChildFolders(BOOKMARK_ROOT_ID).map((f) => f.id)
  }

  /** 部分更新书签字段并持久化 */
  static async updateBookmark(id: string, patch: BookmarkUpdateInput): Promise<void> {
    const item = await BookmarkRepository.getInstance().findById(id)
    if (!item) {
      return
    }
    if (patch.title !== undefined) {
      item.title = patch.title
    }
    if (patch.url !== undefined) {
      item.url = patch.url
    }
    await BookmarkRepository.getInstance().update(item)
    await AppStateSync.refreshBookmarks()
  }

  /** 触发书签 AppStorage 刷新（兼容旧接口） */
  static async setBookmarks(_list: BookmarkItem[]): Promise<void> {
    await AppStateSync.refreshBookmarks()
  }

  /** 从 AppStorage 获取浏览历史列表 */
  static getHistory(): HistoryEntry[] {
    return AppStorage.get<HistoryEntry[]>(AppStorageKeys.HISTORY) ?? []
  }

  /** 写入浏览历史（无痕模式下由策略拦截） */
  static async addHistoryEntry(title: string, url: string): Promise<void> {
    await IncognitoPolicy.getInstance().recordHistoryIfAllowed(title, url)
  }

  /** 更新历史标题（页面标题晚于 URL 回调到达时使用） */
  static async updateHistoryTitle(url: string, title: string): Promise<void> {
    await IncognitoPolicy.getInstance().updateHistoryTitleIfAllowed(url, title)
  }

  /** 更新历史站点图标（Web favicon 到达后写入） */
  static async updateHistoryIcon(url: string, iconUrl: string): Promise<void> {
    await IncognitoPolicy.getInstance().updateHistoryIconIfAllowed(url, iconUrl)
  }

  /** 从 AppStorage 获取下载任务列表 */
  static getDownloads(): DownloadTask[] {
    return AppStorage.get<DownloadTask[]>(AppStorageKeys.DOWNLOADS) ?? []
  }

  /** 获取首页快捷方式 ID 顺序列表 */
  static getShortcuts(): string[] {
    return AppStorage.get<string[]>(AppStorageKeys.SHORTCUT_IDS) ?? []
  }

  /** 添加快捷方式到首页 */
  static async addShortcut(id: string): Promise<boolean> {
    return ShortcutManager.getInstance().addShortcut(id)
  }

  /** 添加自定义网址快捷方式 */
  static async addCustomShortcut(title: string, url: string): Promise<boolean> {
    return ShortcutManager.getInstance().addCustomShortcut(title, url)
  }

  /** 从书签添加快捷方式 */
  static async addBookmarkShortcut(bookmark: BookmarkItem): Promise<boolean> {
    return ShortcutManager.getInstance().addBookmarkShortcut(bookmark)
  }

  /** 从历史记录添加快捷方式 */
  static async addHistoryShortcut(entry: HistoryEntry): Promise<boolean> {
    return ShortcutManager.getInstance().addHistoryShortcut(entry)
  }

  /** 从首页移除快捷方式 */
  static async removeShortcut(id: string): Promise<void> {
    await ShortcutManager.getInstance().removeShortcut(id)
  }

  /** 更新首页快捷方式 */
  static async updateShortcut(id: string, title: string, url?: string): Promise<boolean> {
    return ShortcutManager.getInstance().updateShortcut(id, title, url)
  }

  /** 首页快捷方式动态数量上限 */
  static getShortcutMaxCount(): number {
    return ShortcutManager.getMaxHomeShortcuts()
  }

  /** 拖拽重排快捷方式顺序 */
  static async reorderShortcut(fromIndex: number, toIndex: number): Promise<void> {
    await ShortcutManager.getInstance().reorder(fromIndex, toIndex)
  }

  /** 按方向移动快捷方式网格位置 */
  static async moveShortcut(index: number, direction: ShortcutMoveDirection): Promise<void> {
    await ShortcutManager.getInstance().moveShortcut(index, direction)
  }

  /** 打开分享弹窗并设置展示参数 */
  static openShareSheet(opts: ShareSheetParams): void {
    ShareService.getInstance().openShareSheet(opts)
  }

  /** 打开分享（简化参数版） */
  static openShare(opts: OpenShareOptions): void {
    ShareService.getInstance().openShare(opts)
  }

  /** 打开网页图片全屏预览 */
  static openImagePreview(url: string): void {
    const src = url.trim()
    if (!src) {
      return
    }
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_PREVIEW_VISIBLE, true)
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_PREVIEW_URL, src)
  }

  /** 关闭网页图片全屏预览 */
  static closeImagePreview(): void {
    AppStorage.set(AppStorageKeys.IMAGE_PREVIEW_VISIBLE, false)
    AppStorage.set(AppStorageKeys.IMAGE_PREVIEW_URL, '')
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_PREVIEW_BACK_BLOCK_UNTIL, Date.now() + 450)
    BrowserLog.info('[ImagePreview] store close')
  }

  /** 关闭分享弹窗 */
  static closeShareSheet(): void {
    ShareService.getInstance().closeShareSheet()
  }

  /** 获取搜索历史关键词列表 */
  static getSearchHistory(): string[] {
    return AppStorage.get<string[]>(AppStorageKeys.SEARCH_HISTORY) ?? []
  }

  /** 追加搜索历史（无痕模式下由策略拦截） */
  static async addSearchHistory(keyword: string): Promise<void> {
    await IncognitoPolicy.getInstance().recordSearchIfAllowed(keyword)
  }

  /** 清空搜索历史 */
  static async clearSearchHistory(): Promise<void> {
    await SettingsRepository.getInstance().setSearchHistory([])
    await AppStateSync.refreshSettings()
  }

  /** 当前是否处于无痕模式 */
  static isIncognito(): boolean {
    return IncognitoPolicy.getInstance().isIncognito()
  }

  /** 记录当前浏览页的无痕上下文，供「我的」页同步开关状态 */
  static recordBrowseIncognito(incognito: boolean): void {
    AppStorage.set(AppStorageKeys.BROWSE_INCOGNITO, incognito)
  }

  /** 进入「我的」页时，将无痕开关同步为最近一次浏览上下文 */
  static syncIncognitoForProfile(): void {
    const browseIncognito = AppStorage.get<boolean>(AppStorageKeys.BROWSE_INCOGNITO) ?? false
    const current = AppStorage.get<boolean>(AppStorageKeys.INCOGNITO) ?? false
    if (current === browseIncognito) {
      return
    }
    AppStorage.set(AppStorageKeys.INCOGNITO, browseIncognito)
    IncognitoPolicy.getInstance().setIncognito(browseIncognito).then(() => {})
  }

  /** 静默切换无痕模式（不弹 Toast） */
  static async setIncognitoSilent(on: boolean): Promise<void> {
    AppStorage.set(AppStorageKeys.INCOGNITO, on)
    AppStorage.set(AppStorageKeys.BROWSE_INCOGNITO, on)
    await IncognitoPolicy.getInstance().setIncognito(on)
  }

  /** 切换无痕模式并跳转标签页管理（常用服务入口，无 Toast） */
  static async toggleIncognitoAndOpenTabs(): Promise<boolean> {
    const next = !BrowserStore.isIncognito()
    await BrowserStore.setIncognitoSilent(next)
    return next
  }

  /** 浏览页「更多」切换无痕：迁移当前标签到对应分区并同步模式 */
  static async toggleIncognitoForBrowseTab(tabId: string, title: string, url: string): Promise<string> {
    await BrowserStore.whenReady()
    const next = !BrowserStore.isIncognito()
    const tabPatch: BrowseTabPatch = {
      title: title.trim() || BrowserUtils.tabHostname(url),
      url: url
    }
    const migrated = await TabManager.getInstance().migrateTabPartition(tabId, next, tabPatch)
    await BrowserStore.setIncognitoSilent(next)
    AppStorage.set(AppStorageKeys.ACTIVE_TAB, migrated.id)
    if (next) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.incognito_enabled')))
    }
    return migrated.id
  }

  /** 开启或关闭无痕模式 */
  static async setIncognito(on: boolean): Promise<void> {
    await BrowserStore.setIncognitoSilent(on)
    if (on) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.incognito_enabled')))
    }
  }

  /** 当前是否为深色主题（等同夜间模式） */
  static isDarkMode(): boolean {
    return SettingsStore.getInstance().isDarkMode()
  }

  /** 当前主题偏好：system / light / dark */
  static getThemePreference(): string {
    const raw = AppStorage.get<string>(AppStorageKeys.THEME_PREFERENCE) ?? 'light'
    return BrowserStrings.normalizeThemeModeKey(raw)
  }

  /** 设置主题偏好并立即刷新 UI */
  static setThemePreference(mode: string): void {
    const normalized = BrowserStrings.normalizeThemeModeKey(mode)
    if (normalized === 'system') {
      SystemThemeSync.refreshForFollowSystemMode()
    }
    SystemThemeSync.applyPreference(normalized)
    const rev = (AppStorage.get<number>(AppStorageKeys.THEME_REV) ?? 0) + 1
    AppStorage.setOrCreate(AppStorageKeys.THEME_REV, rev)
    BrowserLog.info(`[Theme] setThemePreference=${normalized} rev=${rev}`)
    void SettingsStore.getInstance().applyThemePreference(normalized)
  }

  /** 统一设置深色/夜间模式：立即刷新 UI，后台持久化（兼容旧调用） */
  static setDarkMode(on: boolean): void {
    BrowserStore.setThemePreference(on ? 'dark' : 'light')
  }

  /** 切换深色/浅色主题（兼容旧调用，不含跟随系统） */
  static toggleDarkMode(): void {
    BrowserStore.setThemePreference(BrowserStore.isDarkMode() ? 'light' : 'dark')
  }

  /** 设置主题模式并持久化（与夜间模式同步） */
  static setThemeMode(mode: string): void {
    BrowserStore.setThemePreference(mode)
  }

  /** 获取当前默认搜索引擎 ID */
  static getSearchEngine(): string {
    return SettingsStore.getInstance().getSearchEngine()
  }

  /** 设置默认搜索引擎 */
  static async setSearchEngine(id: string): Promise<void> {
    await SettingsStore.getInstance().setSearchEngine(id)
  }

  /** 获取网站权限策略映射 */
  static getSitePermissions(): SitePermissionsMap {
    return SettingsStore.getInstance().getSitePermissions()
  }

  /** 获取单项网站权限策略 */
  static getSitePermission(permId: SitePermissionId): SitePermissionPolicy {
    return SettingsStore.getInstance().getSitePermission(permId)
  }

  /** 设置单项网站权限策略（含应用权限 clamp） */
  static async setSitePermission(permId: SitePermissionId, policy: SitePermissionPolicy): Promise<void> {
    await SettingsStore.getInstance().setSitePermission(permId, policy)
  }

  /** 直接持久化网站权限策略（调用方已完成应用权限校验） */
  static async setSitePermissionUnchecked(permId: SitePermissionId, policy: SitePermissionPolicy): Promise<void> {
    await SettingsStore.getInstance().setSitePermissionUnchecked(permId, policy)
  }

  /** 读取 origin 级别持久化策略（key: `${origin}|${permId}`） */
  static async getOriginPermissions(): Promise<Map<string, SitePermissionPolicy>> {
    return SettingsStore.getInstance().getOriginPermissions()
  }

  /**
   * 设置单条 origin 级别策略。'clear' 表示清除该条记录。
   * 应用重启后仍生效——实现"始终允许"语义。
   */
  static async setOriginPermission(origin: string, permId: SitePermissionId, policy: SitePermissionPolicy | 'clear'): Promise<void> {
    await SettingsStore.getInstance().setOriginPermission(origin, permId, policy)
  }

  /** 浏览器应用是否已持有该类别的应用级（系统级）权限 */
  static isAppPermissionGranted(permId: SitePermissionId): boolean {
    return SettingsStore.getInstance().isAppPermissionGranted(permId)
  }

  /** 获取字体大小档位 */
  static getFontSize(): string {
    return SettingsStore.getInstance().getFontSize()
  }

  /** 设置字体大小档位并提示 */
  static async setFontSize(size: string): Promise<void> {
    const normalized = BrowserStrings.normalizeFontSizeKey(size)
    await SettingsStore.getInstance().setFontSize(normalized)
    BrowserStore.showToast(`${BrowserStrings.txt($r('app.string.font_size'))}: ${BrowserStrings.fontSizeLabel(normalized)}`)
  }

  /** 无图模式是否开启 */
  static isImageLessMode(): boolean {
    return SettingsStore.getInstance().isImageLessMode()
  }

  /** 设置无图模式 */
  static async setImageLessMode(on: boolean): Promise<void> {
    AppStorage.set(AppStorageKeys.IMAGE_LESS_MODE, on)
    await SettingsStore.getInstance().setImageLessMode(on)
    BrowserStore.showToast(on ?
      BrowserStrings.txt($r('app.string.image_less_on')) :
      BrowserStrings.txt($r('app.string.image_less_off')))
  }

  /** 夜间浏览模式是否开启（等同深色主题） */
  static isNightMode(): boolean {
    return BrowserStore.isDarkMode()
  }

  /** 设置夜间浏览模式（与深色主题同步） */
  static setNightMode(on: boolean): void {
    if (on === BrowserStore.isDarkMode()) {
      return
    }
    BrowserStore.setDarkMode(on)
  }

  /** 清理 Cookie 与网站缓存 */
  static async clearCookiesAndCache(): Promise<void> {
    try {
      await SettingsStore.getInstance().clearCookiesAndCache()
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.clear_data_done')))
    } catch (_err) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.clear_data_failed')))
    }
  }

  /** 复制文本到系统剪贴板 */
  static async copyToClipboard(text: string): Promise<void> {
    await ShareService.getInstance().copyText(text)
  }

  /** 调用分享面板分享链接 */
  static async shareViaSystem(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareLinkViaSystem(title, url)
  }

  /** 分享到微信 */
  static async shareViaWeChat(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareLinkViaWeChat(title, url)
  }

  /** 分享到 QQ */
  static async shareViaQQ(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareLinkViaQQ(title, url)
  }

  /** 分享到企业微信 */
  static async shareViaWeCom(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareLinkViaWeCom(title, url)
  }

  /** 分享到抖音 */
  static async shareViaDouyin(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareLinkViaDouyin(title, url)
  }

  /** 添加到超级中转站 */
  static async shareViaTransfer(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareToTransferStation(title, url)
  }

  /** 打印或设备分享（系统选择器） */
  static async shareViaPrint(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareForDeviceAction(title, url)
  }

  /** 蓝牙分享 */
  static async shareViaBluetooth(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareViaBluetooth(title, url)
  }

  /** 拉起系统短信应用并预填分享内容 */
  static async shareViaSms(title: string, url: string): Promise<void> {
    await ShareService.getInstance().shareLinkViaSms(title, url)
  }

  /** 首页扫一扫：识别二维码后跳转对应网页 */
  static scanQrCode(): void {
    ScanQrService.startScanFromHome()
  }

  /** 分享图片（优先本地文件，否则分享 URL） */
  static async shareImageViaSystem(title: string, imageUrl: string, localPath: string = ''): Promise<void> {
    await ShareService.getInstance().shareImageViaSystem(title, imageUrl, localPath)
  }

  /** 发起保存网页图片：先申请图库权限，再走下载流程（完成后写入图库） */
  static requestSaveImage(imageUrl: string): void {
    const url = imageUrl.trim()
    if (!url) {
      return
    }
    void GalleryPermissionHelper.ensureWriteImagePermission().then((granted) => {
      if (!granted) {
        return
      }
      const fileName = BrowserUtils.deriveDownloadFileName(url, `photo_${Date.now()}.jpg`)
      const file: DownloadRequest = {
        fileName,
        fileSizeText: '',
        mimeType: BrowserUtils.inferMimeType(fileName),
        sourceUrl: url,
      }
      BrowserStore.requestDownload(file)
    })
  }

  /** 复制网页图片到剪贴板（PixelMap + HTML Base64） */
  static requestCopyImage(imageUrl: string): void {
    const url = imageUrl.trim()
    if (!url) {
      return
    }
    void ImageClipboardService.getInstance().copyImageFromUrl(url).then((ok) => {
      if (ok) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_image_copy_success')))
      } else {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.copy_failed')))
      }
    })
  }

  /** 将当前浏览页添加为书签 */
  static async addPageBookmark(title: string, url: string, parentId: string = BOOKMARK_ROOT_ID): Promise<void> {
    if (BrowserStore.isPageBookmarked(url)) {
      return
    }
    const pid = parentId || BOOKMARK_ROOT_ID
    const item = createBookmarkItem({
      id: `bm${Date.now()}`,
      title: title.trim() || BrowserUtils.tabHostname(url),
      url,
      parentId: pid,
      isFolder: false,
      sortOrder: BrowserStore.bookmarksInFolder(pid).length
    })
    const ok = await BrowserStore.tryAddBookmark(item)
    if (ok) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_bookmark_added')))
    } else {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.bookmark_limit_title')))
    }
  }

  /** 按 URL 查找已收藏的书签项 */
  static findBookmarkByUrl(url: string): BookmarkItem | null {
    const normalized = BrowserUtils.normalizePageUrl(url)
    if (!normalized) {
      return null
    }
    const match = BrowserStore.getBookmarks().find((b) => {
      return !b.isFolder && !!b.url && BrowserUtils.normalizePageUrl(b.url) === normalized
    })
    return match ?? null
  }

  /** 当前 URL 是否已加入书签 */
  static isPageBookmarked(url: string): boolean {
    return BrowserStore.findBookmarkByUrl(url) !== null
  }

  /** 从书签中移除当前页面 */
  static async removePageBookmark(url: string): Promise<void> {
    const item = BrowserStore.findBookmarkByUrl(url)
    if (!item) {
      return
    }
    await BrowserStore.deleteBookmarks([item.id])
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_bookmark_removed')))
  }

  /** 切换当前页面的书签收藏状态 */
  static async togglePageBookmark(title: string, url: string): Promise<void> {
    if (BrowserStore.isPageBookmarked(url)) {
      await BrowserStore.removePageBookmark(url)
      return
    }
    await BrowserStore.addPageBookmark(title, url)
  }

  /** 重新下载失败的任务 */
  static async retryDownload(id: string): Promise<void> {
    const ok = await DownloadManager.getInstance().retryDownload(id)
    if (ok) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_started')))
    }
  }

  /** 打开指定类型的功能面板（子页跟随系统旋转；首页/我的壳层仍锁竖屏） */
  static openFeaturePanel(type: FeaturePanelType): void {
    AppStorage.set(AppStorageKeys.FEATURE_PANEL, type)
    BrowserWindowService.getInstance().applyOrientationForRotatablePage()
  }

  /** 关闭功能面板，并从 DB 重载统计所需数据 */
  static closeFeaturePanel(): void {
    const panel = AppStorage.get<string>(AppStorageKeys.FEATURE_PANEL) ?? ''
    AppStorage.set(AppStorageKeys.FEATURE_PANEL, '')
    // 仅在 MainPage 壳层恢复竖屏；BrowsePage 上关闭面板须保持可旋转
    try {
      const page = BrowserRouterBridge.getInstance().getCurrentPageName()
      if (page.includes('MainPage')) {
        BrowserWindowService.getInstance().applyOrientationForMainShell()
      }
    } catch (_err) {
      // Router 未绑定（销毁阶段）时忽略
    }
    if (panel === 'bookmarks' || panel === 'history' || panel === 'downloads') {
      void AppStateSync.refreshProfileStatsAfterPanelClose(panel)
    } else {
      AppStateSync.notifyListStatsUiRefresh()
    }
  }

  /** 获取当前打开的功能面板类型 */
  static getFeaturePanel(): FeaturePanelType {
    return AppStorage.get<FeaturePanelType>(AppStorageKeys.FEATURE_PANEL) ?? ''
  }

  /** 获取书签数量展示文本（当前数/上限） */
  static getBookmarkCountText(): string {
    const count = BrowserStore.getBookmarks().filter((b) => !b.isFolder).length
    return `${count}/${BOOKMARK_LIMIT}`
  }

  /** 将 URL 压入浏览页内导航栈 */
  static pushNavStack(url: string): void {
    NavigationController.getInstance().pushNavStack(url)
  }

  /** 浏览页内是否可以后退 */
  static canBrowseBack(): boolean {
    return NavigationController.getInstance().canBrowseBack()
  }

  /** 浏览页内是否可以前进 */
  static canBrowseForward(): boolean {
    return NavigationController.getInstance().canBrowseForward()
  }

  /** 浏览页内后退，返回目标 URL 或 null */
  static browseBack(): string | null {
    return NavigationController.getInstance().browseBack()
  }

  /** 浏览页内后退，跳过中转跳转页与重复项 */
  static browseBackSkippingTransit(): string | null {
    return NavigationController.getInstance().browseBackSkippingTransit()
  }

  /** 浏览页内前进，返回目标 URL 或 null */
  static browseForward(): string | null {
    return NavigationController.getInstance().browseForward()
  }

  /** 按 Web 当前 URL 同步浏览导航栈（后退/前进/新页面） */
  static syncNavToUrl(url: string): void {
    NavigationController.getInstance().syncNavToUrl(url)
  }

  /** 重置浏览页内导航栈为单一 URL */
  static resetNavStack(url: string): void {
    NavigationController.getInstance().resetNavStack(url)
  }

  /** 解析当前记录的最后活跃页签（须已加载标签列表） */
  static resolveLastActiveTab(): TabSession | null {
    const id = AppStorage.get<string>(AppStorageKeys.ACTIVE_TAB) ?? ''
    if (!id) {
      return null
    }
    return BrowserStore.getTabs().find((t) => t.id === id) ?? null
  }

  /** 标记并持久化最后活跃页签 */
  static async markActiveTab(tabId: string): Promise<void> {
    await BrowserStore.whenReady()
    await TabManager.getInstance().markActiveTab(tabId)
  }

  /** 确保当前分区存在主页占位页签，不存在则创建 */
  static async ensureHomeTab(incognito?: boolean): Promise<TabSession | null> {
    await BrowserStore.whenReady()
    const mode = incognito ?? BrowserStore.isIncognito()
    // 以 TabManager 为准，避免 AppStorage.browser_tabs 冷启动未刷新时误判已有主页
    let partition = TabManager.getInstance().getAllTabs().filter((t) => t.isIncognito === mode)
    let home = BrowserStore.findHomePlaceholderTab(partition)
    if (home) {
      return home
    }
    if (partition.length === 0) {
      await TabManager.getInstance().ensureDefaultTabForCurrentMode(mode)
    } else {
      const created = await TabManager.getInstance().addTab({
        isHome: true,
        incognito: mode,
        title: BrowserStrings.newTab()
      })
      if (!created) {
        return BrowserStore.findHomePlaceholderTab(partition) ?? null
      }
      home = created
      BrowserLog.info(`ensureHomeTab created id=${created.id} incognito=${mode}`)
    }
    partition = TabManager.getInstance().getAllTabs().filter((t) => t.isIncognito === mode)
    return BrowserStore.findHomePlaceholderTab(partition) ?? home ?? null
  }

  /** 识别主页占位页签（isHome 未入库时以空 URL 兜底） */
  static findHomePlaceholderTab(tabs: TabSession[]): TabSession | undefined {
    const flagged = tabs.find((t) => t.isHome === true)
    if (flagged) {
      return flagged
    }
    return tabs.find((t) => !t.url.trim())
  }

  /** 激活当前分区的主页占位页签（不存在则创建，供标签管理/冷启动等场景） */
  static async activateHomeTab(): Promise<void> {
    await BrowserStore.whenReady()
    const incognito = BrowserStore.isIncognito()
    const home = await BrowserStore.ensureHomeTab(incognito)
    if (home) {
      await TabManager.getInstance().markActiveTab(home.id)
    }
  }

  /**
   * 仅切回首页 UI 时激活标签：有主页占位则切过去，否则保持当前活跃网页标签，不新建。
   * 避免「首页快捷方式打开网页 → 底部回主页 → 再点快捷方式」多出一个空标签。
   */
  static async activateHomeTabForUi(): Promise<void> {
    await BrowserStore.whenReady()
    const incognito = BrowserStore.isIncognito()
    const partition = TabManager.getInstance().getAllTabs().filter((t) => t.isIncognito === incognito)
    const home = BrowserStore.findHomePlaceholderTab(partition)
    if (home) {
      BrowserLog.info(`activateHomeTabForUi use home=${home.id}`)
      await TabManager.getInstance().markActiveTab(home.id)
      return
    }
    const activeId = AppStorage.get<string>(AppStorageKeys.ACTIVE_TAB) ?? ''
    if (activeId.length > 0 && partition.some((t) => t.id === activeId)) {
      BrowserLog.info(`activateHomeTabForUi keep active=${activeId}`)
      return
    }
    if (partition.length > 0) {
      const last = partition[partition.length - 1]
      BrowserLog.info(`activateHomeTabForUi fallback last=${last.id}`)
      await TabManager.getInstance().markActiveTab(last.id)
    }
  }

  /** 从首页打开网址时解析应绑定的标签（优先主页占位；无占位则补建，勿复用已有网址标签） */
  static async resolveHomeBrowseTabId(incognito: boolean): Promise<string> {
    await BrowserStore.whenReady()
    const partition = TabManager.getInstance().getAllTabs().filter((t) => t.isIncognito === incognito)
    const home = BrowserStore.findHomePlaceholderTab(partition)
    if (home) {
      BrowserLog.info(`resolveHomeBrowseTabId home=${home.id}`)
      return home.id
    }
    // 无空主页占位时补建，避免回落到「当前活跃网页标签」把旧网址覆盖掉、计数也不变
    const created = await BrowserStore.ensureHomeTab(incognito)
    BrowserLog.info(`resolveHomeBrowseTabId ensured=${created?.id ?? 'none'}`)
    return created?.id ?? ''
  }

  /** 解析浏览页应绑定的标签 ID */
  static async resolveBrowseTabId(url: string, incognito: boolean, newTab?: boolean, explicitId?: string): Promise<string> {
    await BrowserStore.whenReady()
    if (explicitId) {
      return explicitId
    }
    const trimmedUrl = url.trim()
    if (newTab) {
      const tab = await TabManager.getInstance().addTab({
        url: trimmedUrl,
        title: BrowserUtils.tabHostname(trimmedUrl),
        incognito
      })
      return tab?.id ?? ''
    }
    const partition = TabManager.getInstance().getAllTabs().filter((t) => t.isIncognito === incognito)
    const stored = AppStorage.get<string>(AppStorageKeys.ACTIVE_TAB) ?? ''
    if (stored) {
      const active = partition.find((t) => t.id === stored)
      if (active) {
        return stored
      }
    }
    const homeTab = BrowserStore.findHomePlaceholderTab(partition)
    if (homeTab) {
      return homeTab.id
    }
    if (partition.length > 0) {
      return partition[partition.length - 1].id
    }
    const tab = await TabManager.getInstance().addTab({
      url: trimmedUrl,
      title: BrowserUtils.tabHostname(trimmedUrl),
      incognito
    })
    return tab?.id ?? ''
  }

  /** 同步浏览页 URL/标题/缩略图到标签会话（防抖合并，减少连续 markActiveTab） */
  static async syncBrowseTab(tabId: string, patch: BrowseTabPatch): Promise<void> {
    await BrowserStore.whenReady()
    const prev = BrowserStore.syncBrowsePending.get(tabId) ?? {}
    BrowserStore.syncBrowsePending.set(tabId, {
      url: patch.url ?? prev.url,
      title: patch.title ?? prev.title,
      thumbnailPath: patch.thumbnailPath ?? prev.thumbnailPath,
      isHome: patch.isHome ?? prev.isHome
    })
    const existing = BrowserStore.syncBrowseTimers.get(tabId)
    if (existing !== undefined && existing >= 0) {
      clearTimeout(existing)
    }
    return new Promise<void>((resolve) => {
      const timer = setTimeout(() => {
        BrowserStore.syncBrowseTimers.delete(tabId)
        const merged = BrowserStore.syncBrowsePending.get(tabId)
        BrowserStore.syncBrowsePending.delete(tabId)
        if (merged) {
          void BrowserStore.applySyncBrowseTab(tabId, merged).then(() => resolve())
        } else {
          resolve()
        }
      }, BrowserStore.SYNC_BROWSE_DEBOUNCE_MS) as number
      BrowserStore.syncBrowseTimers.set(tabId, timer)
    })
  }

  /** 进入标签管理前立即落盘当前标签元数据（不阻塞路由） */
  static async flushSyncBrowseTab(tabId: string): Promise<void> {
    if (!tabId) {
      return
    }
    await BrowserStore.whenReady()
    const existing = BrowserStore.syncBrowseTimers.get(tabId)
    if (existing !== undefined && existing >= 0) {
      clearTimeout(existing)
      BrowserStore.syncBrowseTimers.delete(tabId)
    }
    const merged = BrowserStore.syncBrowsePending.get(tabId)
    BrowserStore.syncBrowsePending.delete(tabId)
    if (merged) {
      await BrowserStore.applySyncBrowseTab(tabId, merged)
    }
  }

  private static syncBrowsePending: Map<string, BrowseTabPatch> = new Map()
  private static syncBrowseTimers: Map<string, number> = new Map()
  private static readonly SYNC_BROWSE_DEBOUNCE_MS: number = 350

  /** 立即应用浏览页标签元数据同步（供 syncBrowseTab 防抖回调使用） */
  private static async applySyncBrowseTab(tabId: string, patch: BrowseTabPatch): Promise<void> {
    const tab = BrowserStore.getTabs().find((t) => t.id === tabId)
    if (!tab) {
      return
    }
    const hasUrl = patch.url !== undefined && patch.url.length > 0
    const nextUrl = patch.url ?? tab.url
    const leavingHome = tab.isHome === true && (patch.isHome === false || hasUrl)
    const urlChanged = hasUrl &&
      BrowserUtils.normalizeHistoryUrl(patch.url ?? '') !== BrowserUtils.normalizeHistoryUrl(tab.url)
    let thumbnailPath = patch.thumbnailPath ?? tab.thumbnailPath
    // 离开主页或 URL 实质变化时失效旧缩略图，避免标题/网址已更新仍显示上一页画面
    if (leavingHome || urlChanged) {
      TabThumbnailService.getInstance().deleteThumbnail(tab.thumbnailPath)
      thumbnailPath = ''
    }
    const updated: TabSession = {
      id: tab.id,
      title: patch.title ?? tab.title,
      url: nextUrl,
      isIncognito: tab.isIncognito,
      webState: tab.webState,
      thumbnailPath: thumbnailPath,
      sortOrder: tab.sortOrder,
      isActive: true,
      createdAt: tab.createdAt,
      updatedAt: Date.now(),
      isHome: patch.isHome ?? (hasUrl ? false : tab.isHome),
      hideDesc: true
    }
    await TabManager.getInstance().updateTab(updated)
    await TabManager.getInstance().markActiveTab(tabId)
  }

  /** 当前 Web 画面是否仍对应该页签（共享 WebView，禁止张冠李戴） */
  private static isLiveWebMatchingTab(tab: TabSession): boolean {
    if (!tab || tab.isHome === true || !(tab.url ?? '').trim()) {
      return false
    }
    const liveUrl = BrowserUtils.normalizeHistoryUrl(WebPageController.getInstance().getCurrentUrl())
    const tabUrl = BrowserUtils.normalizeHistoryUrl(tab.url)
    if (!liveUrl || !tabUrl) {
      return false
    }
    return liveUrl === tabUrl
  }

  /** 页签是否仍是可截首页缩略图的主页占位 */
  private static isHomePlaceholderTab(tab: TabSession | undefined): boolean {
    if (!tab) {
      return false
    }
    return tab.isHome === true || !(tab.url ?? '').trim()
  }

  /** 截取当前 Web 页面并更新标签缩略图 */
  static async captureTabThumbnail(tabId: string): Promise<boolean> {
    if (!tabId) {
      return false
    }
    await BrowserStore.whenReady()
    const before = BrowserStore.getTabs().find((t) => t.id === tabId)
    if (!before || before.isIncognito || BrowserStore.isHomePlaceholderTab(before)) {
      return false
    }
    if (!BrowserStore.isLiveWebMatchingTab(before)) {
      BrowserLog.info(`captureTabThumbnail skip mismatch tab=${tabId} ` +
        `tabUrl=${(before.url ?? '').slice(0, 48)} ` +
        `live=${WebPageController.getInstance().getCurrentUrl().slice(0, 48)}`)
      return false
    }
    const path = await TabThumbnailService.getInstance().captureForTab(tabId)
    if (!path) {
      TabThumbnailRetryService.getInstance().enqueue(tabId, 'web', true)
      return false
    }
    const after = BrowserStore.getTabs().find((t) => t.id === tabId)
    if (!after || !BrowserStore.isLiveWebMatchingTab(after)) {
      TabThumbnailService.getInstance().deleteThumbnail(path)
      BrowserLog.info(`captureTabThumbnail discard stale tab=${tabId}`)
      TabThumbnailRetryService.getInstance().enqueue(tabId, 'web', true)
      return false
    }
    TabThumbnailRetryService.getInstance().cancel(tabId)
    await TabManager.getInstance().applyTabThumbnail(tabId, path)
    BrowserLog.info(`captureTabThumbnail saved tabId=${tabId}`)
    return true
  }

  /** 标签缺少缩略图时补抓（页签管理页在栈顶、BrowsePage 在后台时也可触发） */
  static async captureTabThumbnailIfMissing(tabId: string): Promise<boolean> {
    if (!tabId) {
      return false
    }
    await BrowserStore.whenReady()
    const tab = BrowserStore.getTabs().find((t) => t.id === tabId)
    if (!tab || tab.isIncognito || tab.isHome === true) {
      return false
    }
    if ((tab.thumbnailPath ?? '').length > 0) {
      return false
    }
    if ((tab.url ?? '').trim().length === 0) {
      return false
    }
    BrowserLog.info(`captureTabThumbnailIfMissing tab=${tabId}`)
    return BrowserStore.captureTabThumbnail(tabId)
  }

  /** 首页组件截图并更新指定主页标签缩略图；须传入 MainPage 的 UIContext */
  static async captureHomeTabThumbnailForTab(tabId: string, uiContext?: UIContext | null): Promise<boolean> {
    if (!tabId) {
      return false
    }
    await BrowserStore.whenReady()
    const before = BrowserStore.getTabs().find((t) => t.id === tabId)
    if (!BrowserStore.isHomePlaceholderTab(before)) {
      BrowserLog.info(`captureHomeTabThumbnail skip non-home tab=${tabId}`)
      return false
    }
    const path = await TabThumbnailService.getInstance().captureHomeFromComponent(
      tabId, TabThumbnailRetryService.MAIN_PAGE_SNAPSHOT_ID, uiContext)
    if (!path) {
      BrowserLog.warn(`captureHomeTabThumbnail failed tabId=${tabId}`)
      return false
    }
    const after = BrowserStore.getTabs().find((t) => t.id === tabId)
    if (!BrowserStore.isHomePlaceholderTab(after)) {
      TabThumbnailService.getInstance().deleteThumbnail(path)
      BrowserLog.info(`captureHomeTabThumbnail discard promoted tab=${tabId}`)
      return false
    }
    TabThumbnailRetryService.getInstance().cancel(tabId)
    await TabManager.getInstance().applyTabThumbnail(tabId, path)
    BrowserLog.info(`captureHomeTabThumbnail saved tabId=${tabId}`)
    return true
  }

  /** 进入页签管理前捕获当前主页缩略图（后台调用，不阻塞 UI） */
  static async captureHomeTabThumbnail(): Promise<boolean> {
    await BrowserStore.whenReady()
    const home = await BrowserStore.ensureHomeTab(BrowserStore.isIncognito())
    if (!home) {
      return false
    }
    return BrowserStore.captureHomeTabThumbnailForTab(home.id)
  }

  /** 从首页进入页签管理：先抓取主页缩略图再跳转（须 MainPage UIContext） */
  static openTabsWithHomeThumbnail(pageUiContext?: UIContext): void {
    BrowserLog.info('openTabsWithHomeThumbnail begin')
    void BrowserStore.whenReady().then(async () => {
      const home = await BrowserStore.ensureHomeTab(BrowserStore.isIncognito())
      if (home) {
        await BrowserStore.captureHomeTabThumbnailForTab(home.id, pageUiContext)
      }
      BrowserNavigation.openTabs()
      BrowserLog.info('openTabsWithHomeThumbnail navigated')
    })
  }

  /** 跳转完成后后台抓取缩略图（先入队，下一帧再尝试，不阻塞导航） */
  static scheduleBackgroundTabThumbnail(tabId: string, kind: 'web' | 'home'): void {
    if (!tabId) {
      return
    }
    TabThumbnailRetryService.getInstance().enqueue(tabId, kind)
    WebStabilityGuard.suspendGpuHeavyWork(2500)
    setTimeout(() => {
      void BrowserStore.runBackgroundTabThumbnail(tabId, kind)
    }, 1500)
  }

  private static async runBackgroundTabThumbnail(tabId: string, kind: 'web' | 'home'): Promise<void> {
    if (kind === 'home') {
      BrowserLog.info(`[TabThumbnailBg] skip home tab=${tabId} (MainPage off-screen)`)
      return
    }
    const ok = await BrowserStore.captureTabThumbnail(tabId)
    BrowserLog.info(`[TabThumbnailBg] kind=${kind} tab=${tabId} ok=${ok}`)
  }

  /** 页签管理页：为缺失缩略图的标签启动后台重试（优先当前返回/活跃标签） */
  static requestMissingTabThumbnails(tabs: TabSession[], limit: number = 8): void {
    const priorityId = AppStorage.get<string>(AppStorageKeys.TABS_RETURN_TAB_ID) ??
      AppStorage.get<string>(AppStorageKeys.ACTIVE_TAB) ?? ''
    TabThumbnailRetryService.getInstance().enqueueMissing(tabs, limit, priorityId)
  }

  private static thumbUiTimers: Map<string, number> = new Map()
  private static readonly THUMB_UI_DEBOUNCE_MS: number = 250

  /** 防抖合并缩略图 UI 刷新；immediate 用于首页截图等需即时展示场景 */
  private static scheduleTabThumbnailUi(tabId: string, path: string, immediate: boolean = false): void {
    const prev = BrowserStore.thumbUiTimers.get(tabId)
    if (prev !== undefined && prev >= 0) {
      clearTimeout(prev)
    }
    const delayMs = immediate ? 0 : BrowserStore.THUMB_UI_DEBOUNCE_MS
    const timer = setTimeout(() => {
      BrowserStore.thumbUiTimers.delete(tabId)
      void TabManager.getInstance().applyTabThumbnail(tabId, path)
    }, delayMs) as number
    BrowserStore.thumbUiTimers.set(tabId, timer)
  }

  /** 标签缩略图 URI（供 Image 组件使用；刷新依赖 ForEach/Image .key） */
  static tabThumbnailUri(path: string, _cacheKey?: number): string {
    return TabThumbnailService.toDisplayUri(path)
  }

  /** 获取指定文件夹下的书签/子文件夹（已排序） */
  static bookmarksInFolder(parentId: string): BookmarkItem[] {
    const pid = parentId || BOOKMARK_ROOT_ID
    return BrowserStore.getBookmarks()
      .filter((b) => (b.parentId || BOOKMARK_ROOT_ID) === pid)
      .sort((a, b) => a.sortOrder - b.sortOrder)
  }

  /** 同层书签拖拽重排并持久化 sort_order */
  static async reorderBookmarksInFolder(parentId: string, fromIndex: number, toIndex: number): Promise<void> {
    const siblings = BrowserStore.bookmarksInFolder(parentId)
    if (fromIndex < 0 || toIndex < 0 || fromIndex >= siblings.length || toIndex >= siblings.length ||
      fromIndex === toIndex) {
      return
    }
    const ids = siblings.map((s: BookmarkItem) => s.id)
    const nextIds = reorderArrayIds(ids, fromIndex, toIndex)
    const orderMap: Map<string, number> = new Map()
    for (let i = 0; i < nextIds.length; i++) {
      orderMap.set(nextIds[i], i)
    }
    const all = BrowserStore.getBookmarks()
    const now = Date.now()
    const patched: BookmarkItem[] = []
    for (let i = 0; i < all.length; i++) {
      const b = all[i]
      const nextOrder = orderMap.get(b.id)
      if (nextOrder === undefined || b.sortOrder === nextOrder) {
        patched.push(b)
      } else {
        patched.push({
          id: b.id,
          parentId: b.parentId,
          title: b.title,
          url: b.url,
          iconUrl: b.iconUrl,
          sortOrder: nextOrder as number,
          isFolder: b.isFolder,
          createdAt: b.createdAt,
          updatedAt: now
        })
      }
    }
    AppStorage.set(AppStorageKeys.BOOKMARKS, patched)
    const rev = (AppStorage.get<number>(AppStorageKeys.BOOKMARKS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.BOOKMARKS_REV, rev)
    await BookmarkRepository.getInstance().reorderByIds(nextIds)
  }

  /** 获取根目录下的全部书签/文件夹 */
  static bookmarksAtRoot(): BookmarkItem[] {
    return BrowserStore.bookmarksInFolder(BOOKMARK_ROOT_ID)
  }

  /** 统计文件夹内全部书签链接数（含嵌套子文件夹中的书签） */
  static countBookmarksUnderFolder(folderId: string): number {
    let count = 0
    const stack: string[] = [folderId]
    while (stack.length > 0) {
      const pid = stack.pop() as string
      const children = BrowserStore.bookmarksInFolder(pid)
      for (let i = 0; i < children.length; i++) {
        const item = children[i]
        if (item.isFolder) {
          stack.push(item.id)
        } else {
          count++
        }
      }
    }
    return count
  }

  /** 获取文件夹内书签数量文本（含嵌套） */
  static folderItemCountLabel(folderId: string): string {
    return BrowserStrings.bookmarkCount(BrowserStore.countBookmarksUnderFolder(folderId))
  }

  /** 尝试添加书签，超出上限时返回 false */
  static async tryAddBookmark(item: BookmarkItem): Promise<boolean> {
    const count = BrowserStore.getBookmarks().filter((b) => !b.isFolder).length
    if (count >= BOOKMARK_LIMIT) {
      return false
    }
    await BookmarkRepository.getInstance().insert(item)
    await AppStateSync.refreshBookmarks()
    return true
  }

  /** 在指定父目录下新建文件夹，重名时返回 false */
  static async addFolderEntry(title: string, parentId: string = BOOKMARK_ROOT_ID): Promise<boolean> {
    const n = title.trim()
    if (!n) {
      return false
    }
    const siblings = BrowserStore.bookmarksInFolder(parentId)
    if (siblings.some((b) => b.isFolder && b.title === n)) {
      return false
    }
    const folderInput: CreateBookmarkItemInput = {
      id: `bf${Date.now()}`,
      title: n,
      parentId: parentId || BOOKMARK_ROOT_ID,
      isFolder: true,
      sortOrder: siblings.length
    }
    const folder = createBookmarkItem(folderInput)
    await BookmarkRepository.getInstance().insert(folder)
    await AppStateSync.refreshBookmarks()
    return true
  }

  /** 批量删除书签或文件夹 */
  static async deleteBookmarks(ids: string[]): Promise<void> {
    await BookmarkRepository.getInstance().deleteByIds(ids)
    await AppStateSync.refreshBookmarks()
  }

  /** 批量移动书签/文件夹到目标父目录；含子树整体跟随、失败回滚 */
  static async moveItemsToFolder(itemIds: string[], parentId: string): Promise<'success' | 'invalid' | 'failed'> {
    const all = BrowserStore.getBookmarks()
    const candidates = BrowserStore.filterMoveRootCandidates(itemIds, all)
    if (candidates.length === 0) {
      return 'invalid'
    }
    if (!BrowserStore.canMoveItemsToParent(candidates, parentId)) {
      return 'invalid'
    }
    const target = parentId || BOOKMARK_ROOT_ID
    const snapshot: BookmarkItem[] = []
    for (const id of candidates) {
      const item = all.find((b) => b.id === id)
      if (item) {
        snapshot.push({
          id: item.id,
          parentId: item.parentId || BOOKMARK_ROOT_ID,
          title: item.title,
          url: item.url,
          iconUrl: item.iconUrl,
          sortOrder: item.sortOrder,
          isFolder: item.isFolder,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt
        })
      }
    }
    try {
      // 仅更新候选根节点 parentId；子文件夹/书签仍挂在原父节点下，随父文件夹整体移动
      await BookmarkRepository.getInstance().moveToParent(candidates, target)
      await AppStateSync.refreshBookmarks()
      return 'success'
    } catch (err) {
      BrowserLog.error(`moveItemsToFolder failed: ${JSON.stringify(err)}`)
      try {
        for (const prev of snapshot) {
          await BookmarkRepository.getInstance().moveToParent([prev.id], prev.parentId)
        }
        await AppStateSync.refreshBookmarks()
      } catch (rollbackErr) {
        BrowserLog.error(`moveItemsToFolder rollback failed: ${JSON.stringify(rollbackErr)}`)
        await AppStateSync.refreshBookmarks()
      }
      return 'failed'
    }
  }

  /** 选中项是否均已位于目标父目录（无需移动） */
  static isAlreadyAtTarget(itemIds: string[], parentId: string): boolean {
    const all = BrowserStore.getBookmarks()
    const candidates = BrowserStore.filterMoveRootCandidates(itemIds, all)
    if (candidates.length === 0) {
      return false
    }
    const target = parentId || BOOKMARK_ROOT_ID
    return candidates.every((id) => {
      const item = all.find((b) => b.id === id)
      return !!item && (item.parentId || BOOKMARK_ROOT_ID) === target
    })
  }

  /** @deprecated 请使用 moveItemsToFolder */
  static async moveBookmarksToFolder(bookmarkIds: string[], parentId: string): Promise<void> {
    await BrowserStore.moveItemsToFolder(bookmarkIds, parentId)
  }

  /** 目标文件夹是否为 ancestorFolderId 自身或其子文件夹 */
  static isDescendantOf(targetFolderId: string, ancestorFolderId: string): boolean {
    if (!ancestorFolderId) {
      return false
    }
    const target = targetFolderId || BOOKMARK_ROOT_ID
    if (target === ancestorFolderId) {
      return true
    }
    let current: string = target
    const guard = new Set<string>()
    while (current && current !== BOOKMARK_ROOT_ID) {
      if (guard.has(current)) {
        break
      }
      guard.add(current)
      const item = BrowserStore.getBookmarks().find((b) => b.id === current)
      if (!item) {
        break
      }
      const parent = item.parentId || BOOKMARK_ROOT_ID
      if (parent === ancestorFolderId) {
        return true
      }
      if (!parent || parent === BOOKMARK_ROOT_ID) {
        break
      }
      current = parent
    }
    return false
  }

  /** 多选移动时排除「父项也在选中列表中」的子项，避免打散文件夹层级 */
  static filterMoveRootCandidates(itemIds: string[], all: BookmarkItem[]): string[] {
    const selected = new Set(itemIds)
    return itemIds.filter((id) => {
      const item = all.find((b) => b.id === id)
      if (!item) {
        return false
      }
      const parent = item.parentId || BOOKMARK_ROOT_ID
      return !selected.has(parent)
    })
  }

  /** 校验书签/文件夹能否移动到目标父目录 */
  static canMoveItemsToParent(itemIds: string[], parentId: string): boolean {
    const all = BrowserStore.getBookmarks()
    const candidates = BrowserStore.filterMoveRootCandidates(itemIds, all)
    for (const id of candidates) {
      const item = all.find((b) => b.id === id)
      if (item?.isFolder && BrowserStore.isDescendantOf(parentId, id)) {
        return false
      }
    }
    return candidates.length > 0
  }

  /** 重命名书签或文件夹；文件夹重名时返回 false，名称为空时返回 false */
  static async tryRenameBookmark(id: string, title: string): Promise<boolean> {
    const n = title.trim()
    if (!n) {
      return false
    }
    const item = await BookmarkRepository.getInstance().findById(id)
    if (!item) {
      return false
    }
    if (item.isFolder) {
      const parentId = item.parentId || BOOKMARK_ROOT_ID
      const siblings = BrowserStore.bookmarksInFolder(parentId)
      if (siblings.some((b) => b.isFolder && b.id !== id && b.title === n)) {
        return false
      }
    }
    item.title = n
    await BookmarkRepository.getInstance().update(item)
    await AppStateSync.refreshBookmarks()
    return true
  }

  /** 获取文件夹标题，根目录返回空字符串 */
  static getFolderTitle(folderId: string): string {
    if (!folderId || folderId === BOOKMARK_ROOT_ID) {
      return ''
    }
    const folder = BrowserStore.getBookmarks().find((b) => b.id === folderId)
    return folder?.title ?? ''
  }

  /** 获取文件夹的父 ID */
  static getFolderParentId(folderId: string): string {
    if (!folderId || folderId === BOOKMARK_ROOT_ID) {
      return BOOKMARK_ROOT_ID
    }
    const folder = BrowserStore.getBookmarks().find((b) => b.id === folderId)
    return folder?.parentId ?? BOOKMARK_ROOT_ID
  }

  /** 弹出下载确认对话框 */
  static requestDownload(file: DownloadRequest): void {
    DownloadManager.getInstance().requestDownload(file)
  }

  /** 关闭下载确认对话框 */
  static closeDownloadDialog(): void {
    DownloadManager.getInstance().closeDownloadDialog()
  }

  /** 确认开始下载 */
  static async confirmDownloadProceed(): Promise<void> {
    const outcome = await DownloadManager.getInstance().confirmDownloadProceed()
    if (!outcome.started) {
      return
    }
    if (outcome.notificationEnabled) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_started')))
    } else {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_no_notification_started')))
    }
  }

  /** 处理重名文件下载冲突（覆盖/重命名/取消） */
  static async handleDuplicateDownload(act: string): Promise<void> {
    await DownloadManager.getInstance().handleDuplicateDownload(act)
  }

  /** 更新网页下载进度 */
  static updateWebDownloadProgress(id: string, progress: number): void {
    void DownloadManager.getInstance().updateWebDownloadProgress(id, progress)
  }

  /** 网页下载完成 */
  static async completeWebDownload(id: string): Promise<void> {
    await DownloadManager.getInstance().completeWebDownload(id)
  }

  /** 网页下载失败 */
  static async failWebDownload(id: string): Promise<void> {
    await DownloadManager.getInstance().failWebDownload(id)
  }

  static async failWebDownloadWithMessage(id: string, reason: string): Promise<void> {
    await DownloadManager.getInstance().failWebDownloadWithMessage(id, reason)
  }

  /** 开始或重启指定下载任务 */
  static async startDownload(id: string): Promise<void> {
    const ok = await DownloadManager.getInstance().startDownload(id)
    if (ok) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_started')))
    }
  }

  /** 暂停指定下载任务 */
  static async pauseDownload(id: string): Promise<void> {
    await DownloadManager.getInstance().pauseDownload(id)
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_paused')))
  }

  /** 恢复指定下载任务 */
  static async resumeDownload(id: string): Promise<void> {
    const ok = await DownloadManager.getInstance().resumeDownload(id)
    if (ok) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_resumed')))
    }
  }

  /** 删除下载任务记录；deleteLocal 为 true 时同步删除本地/文管文件 */
  static async removeDownload(id: string, deleteLocal: boolean = true): Promise<void> {
    await DownloadManager.getInstance().removeDownload(id, deleteLocal)
  }

  /** 进入下载管理页时同步文件存在性（文管删除后显示「已删除」） */
  static async syncDownloadFileStates(): Promise<void> {
    await DownloadManager.getInstance().syncDownloadFileStates()
  }

  /** 打开已完成的下载文件；文件缺失时返回 missing 供 UI 弹窗 */
  static async openDownload(id: string): Promise<OpenDownloadResult> {
    return DownloadManager.getInstance().openDownloadFile(id)
  }

  /**
   * 用当前浏览器 ArkWeb 预览本地文件（PDF/HTML 等）。
   * 关闭功能面板后跳转浏览页 loadUrl。
   */
  static openLocalFilePreview(localUrl: string, title: string = ''): void {
    const url = localUrl.trim()
    if (url.length === 0) {
      return
    }
    BrowserStore.closeFeaturePanel()
    const pageTitle = title.trim()
    BrowserLog.info(`[FilePreview] navigate url=${url.slice(0, 120)} title=${pageTitle}`)
    BrowserNavigation.openBrowse(url, {
      preferHomeTab: true,
      title: pageTitle.length > 0 ? pageTitle : undefined
    })
  }

  /**
   * 文件管理器等外部 Want 传入的 file:// URI：复制到沙箱后用 ArkWeb 预览。
   */
  static async openExternalLocalFile(uri: string, title: string = ''): Promise<void> {
    const src = uri.trim()
    if (src.length === 0) {
      return
    }
    try {
      await BrowserStore.whenReady()
      const fileName = title.trim().length > 0 ? title.trim() : BrowserUtils.localFileDisplayName(src)
      if (!BrowserUtils.canPreviewInBrowser(fileName) && !BrowserUtils.canPreviewInBrowserUrl(src)) {
        BrowserLog.warn(`[FilePreview] unsupported external file=${src.slice(0, 120)}`)
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
        return
      }
      const loadPath = DownloadPathService.getInstance().prepareExternalUriPreview(src, fileName)
      if (loadPath.length === 0) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
        return
      }
      const previewUrl = BrowserUtils.buildLocalFilePreviewUrl(loadPath)
      BrowserLog.info(`[FilePreview] external ready name=${fileName} path=${previewUrl.slice(0, 120)}`)
      BrowserStore.openLocalFilePreview(previewUrl, fileName)
    } catch (err) {
      BrowserLog.error(`[FilePreview] external open failed: ${JSON.stringify(err)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
    }
  }

  /** 本地文件缺失时重新下载 */
  static async redownloadMissingFile(id: string): Promise<void> {
    const ok = await DownloadManager.getInstance().redownloadMissingFile(id)
    if (ok) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_started')))
    } else {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_redownload_no_source')))
    }
  }

  /** 重命名下载文件 */
  static async renameDownload(id: string, fileName: string): Promise<void> {
    await DownloadManager.getInstance().renameDownload(id, fileName)
  }

  /** 批量删除历史记录 */
  static async deleteHistory(ids: number[]): Promise<void> {
    await HistoryRepository.getInstance().deleteByIds(ids)
    await AppStateSync.refreshHistory()
  }

  /** 清空全部浏览历史 */
  static async clearHistory(): Promise<void> {
    await HistoryRepository.getInstance().clearAll()
    await AppStateSync.refreshHistory()
  }
}


