import { SystemFontSync } from './settings/SystemFontSync'
import { FontScaleService } from './settings/FontScaleService'
import { BrowserLog } from 'common'
import { DownloadTask } from 'common'
import { AppStorageKeys, cloneBookmark, cloneDownload, cloneHistory, cloneShortcut, cloneTab } from 'common'
import { TabSession } from 'common'
import { DEFAULT_SITE_PERMISSIONS } from 'common'
import { BookmarkRepository } from 'common'
import { DownloadRepository } from 'common'
import { HistoryRepository } from 'common'
import { SettingsRepository } from 'common'
import { ShortcutRepository } from 'common'
import { TabRepository } from 'common'
import { BrowserWindowService } from './settings/BrowserWindowService'
import { BrowserStrings } from 'common'
import { SystemThemeSync } from './settings/SystemThemeSync'
import { ShareAppAvailability } from './system/ShareAppAvailability'
import { DEFAULT_SHARE_APPS } from './system/ShareAppAvailability'

/** 将 Repository 数据同步到 AppStorage，供 UI @StorageLink 绑定 */
export class AppStateSync {
  /** 刷新全部 AppStorage 绑定数据 */
  static async refreshAll(tabs: TabSession[]): Promise<void> {
    await AppStateSync.refreshTabs(tabs)
    await AppStateSync.refreshBookmarks()
    await AppStateSync.refreshHistory()
    await AppStateSync.refreshDownloads()
    await AppStateSync.refreshShortcuts()
    await AppStateSync.refreshSettings()
    await AppStateSync.refreshSitePermissions()
  }

  /** 同步标签列表到 AppStorage（递增 rev，用于结构性变更） */
  static async refreshTabs(tabs: TabSession[]): Promise<void> {
    const normalCount = tabs.filter((t) => !t.isIncognito).length
    const incognitoCount = tabs.filter((t) => t.isIncognito).length
    AppStorage.set(AppStorageKeys.TABS, tabs.map((t) => cloneTab(t)))
    const rev = (AppStorage.get<number>(AppStorageKeys.TABS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.TABS_REV, rev)
    BrowserLog.info(`refreshTabs total=${tabs.length} normal=${normalCount} incognito=${incognitoCount} rev=${rev}`)
  }

  /** 仅刷新标签数据，不递增 rev（缩略图等局部更新，避免页签页闪动） */
  static patchTabsQuiet(tabs: TabSession[]): void {
    AppStorage.set(AppStorageKeys.TABS, tabs.map((t) => cloneTab(t)))
  }

  /** 缩略图等局部更新：刷新 tabs 并递增 rev，确保 @StorageLink/@Watch 与 ForEach 重绘 */
  static notifyTabsChanged(tabs: TabSession[]): void {
    AppStorage.set(AppStorageKeys.TABS, tabs.map((t) => cloneTab(t)))
    const rev = (AppStorage.get<number>(AppStorageKeys.TABS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.TABS_REV, rev)
    BrowserLog.info(`notifyTabsChanged count=${tabs.length} rev=${rev}`)
  }

  /** 同步书签列表到 AppStorage */
  static async refreshBookmarks(): Promise<void> {
    const list = await BookmarkRepository.getInstance().findAll()
    const cloned = list.map((b) => cloneBookmark(b))
    AppStorage.setOrCreate(AppStorageKeys.BOOKMARKS, cloned)
    AppStorage.set(AppStorageKeys.BOOKMARKS, cloned)
    const rev = (AppStorage.get<number>(AppStorageKeys.BOOKMARKS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.BOOKMARKS_REV, rev)
    BrowserLog.info(`[ProfileStats] refreshBookmarks count=${list.length} rev=${rev}`)
  }

  /** 同步浏览历史到 AppStorage */
  static async refreshHistory(): Promise<void> {
    const list = await HistoryRepository.getInstance().findAll()
    const cloned = list.map((h) => cloneHistory(h))
    AppStorage.setOrCreate(AppStorageKeys.HISTORY, cloned)
    AppStorage.set(AppStorageKeys.HISTORY, cloned)
    const rev = (AppStorage.get<number>(AppStorageKeys.HISTORY_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.HISTORY_REV, rev)
    BrowserLog.info(`[ProfileStats] refreshHistory count=${list.length} rev=${rev}`)
  }

  /** 同步下载列表到 AppStorage 并递增版本号 */
  static async refreshDownloads(): Promise<void> {
    const list = await DownloadRepository.getInstance().findAll()
    const cloned = list.map((d) => cloneDownload(d))
    AppStorage.setOrCreate(AppStorageKeys.DOWNLOADS, cloned)
    AppStorage.set(AppStorageKeys.DOWNLOADS, cloned)
    const rev = (AppStorage.get<number>(AppStorageKeys.DOWNLOADS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.DOWNLOADS_REV, rev)
    BrowserLog.info(`[ProfileStats] refreshDownloads count=${list.length} rev=${rev}`)
  }

  /** 仅更新单条下载任务到 AppStorage（不递增 rev，避免列表行/缩略图整行重建） */
  static patchDownloadItem(task: DownloadTask): void {
    const list = AppStorage.get<DownloadTask[]>(AppStorageKeys.DOWNLOADS) ?? []
    let found = false
    const patched = list.map((d) => {
      if (d.id !== task.id) {
        return d
      }
      found = true
      return cloneDownload(task)
    })
    if (!found) {
      return
    }
    AppStorage.set(AppStorageKeys.DOWNLOADS, patched)
    const rev = (AppStorage.get<number>(AppStorageKeys.DOWNLOAD_PROGRESS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.DOWNLOAD_PROGRESS_REV, rev)
  }

  /** 「我的」页显示时从 DB 重载统计 */
  static async refreshProfileStatsOnShow(source: string): Promise<void> {
    await AppStateSync.refreshBookmarks()
    await AppStateSync.refreshHistory()
    await AppStateSync.refreshDownloads()
    AppStateSync.notifyListStatsUiRefresh()
    const bookmarks = AppStorage.get<object[]>(AppStorageKeys.BOOKMARKS) ?? []
    const history = AppStorage.get<object[]>(AppStorageKeys.HISTORY) ?? []
    const downloads = AppStorage.get<object[]>(AppStorageKeys.DOWNLOADS) ?? []
    BrowserLog.info(`[ProfileStats] onShow source=${source} bm=${bookmarks.length} hi=${history.length} dl=${downloads.length}`)
  }

  /** 关闭书签/历史/下载面板后：从 DB 重载并刷新「我的」统计 */
  static async refreshProfileStatsAfterPanelClose(panel: string): Promise<void> {
    BrowserLog.info(`[ProfileStats] refreshAfterPanelClose panel=${panel}`)
    await AppStateSync.refreshProfileStatsOnShow(`panelClose:${panel}`)
  }

  /** 关闭书签/历史/下载面板时触发「我的」页统计区重绘 */
  static notifyListStatsUiRefresh(): void {
    const rev = (AppStorage.get<number>(AppStorageKeys.LIST_STATS_UI_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.LIST_STATS_UI_REV, rev)
    BrowserLog.info(`[ProfileStats] notifyListStatsUiRefresh rev=${rev}`)
  }

  /** 同步快捷方式列表到 AppStorage */
  static async refreshShortcuts(): Promise<void> {
    const items = await ShortcutRepository.getInstance().findAll()
    AppStorage.setOrCreate(AppStorageKeys.SHORTCUT_IDS, items.map((s) => s.id))
    AppStorage.setOrCreate(AppStorageKeys.SHORTCUTS, items.map((s) => cloneShortcut(s)))
    const rev = (AppStorage.get<number>(AppStorageKeys.SHORTCUTS_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.SHORTCUTS_REV, rev)
  }

  /** 同步用户设置与搜索历史到 AppStorage */
  static async refreshSettings(): Promise<void> {
    const repo = SettingsRepository.getInstance()
    const settings = await repo.loadSettings()
    const searchHistory = await repo.getSearchHistory()
    const pref = BrowserStrings.normalizeThemeModeKey(settings.themeMode)
    AppStorage.setOrCreate(AppStorageKeys.THEME_PREFERENCE, pref)
    SystemThemeSync.applyPreference(pref)
    const dark = (AppStorage.get<string>(AppStorageKeys.THEME) ?? 'light') === 'dark'
    BrowserLog.info(`[Theme] refreshSettings pref=${pref} effective=${dark ? 'dark' : 'light'}`)
    AppStorage.setOrCreate(AppStorageKeys.SEARCH_ENGINE, settings.defaultSearchEngine)
    AppStorage.setOrCreate(AppStorageKeys.NIGHT_MODE, dark)
    AppStorage.setOrCreate(AppStorageKeys.INCOGNITO, settings.incognitoMode)
    AppStorage.setOrCreate(AppStorageKeys.BROWSE_INCOGNITO, settings.incognitoMode)
    AppStorage.setOrCreate(AppStorageKeys.UA_MODE, settings.uaMode)
    const prevSize = BrowserStrings.normalizeFontSizeKey(
      AppStorage.get<string>(AppStorageKeys.FONT_SIZE) ?? 'system')
    const prevScale = AppStorage.get<number>(AppStorageKeys.FONT_UI_SCALE) ?? 1
    const newSize = BrowserStrings.normalizeFontSizeKey(settings.fontSize)
    AppStorage.setOrCreate(AppStorageKeys.FONT_SIZE, newSize)
    const newScale = FontScaleService.currentFactor()
    const fontChanged = newSize !== prevSize || Math.abs(newScale - prevScale) > 0.001
    FontScaleService.publish('refreshSettings', fontChanged)
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_LESS_MODE, settings.imageLessMode)
    AppStorage.setOrCreate(AppStorageKeys.SEARCH_HISTORY, searchHistory)
  }

  /** 同步网站权限策略到 AppStorage */
  static async refreshSitePermissions(): Promise<void> {
    const perms = await SettingsRepository.getInstance().getSitePermissions()
    AppStorage.setOrCreate(AppStorageKeys.SITE_PERMISSIONS, perms)
  }

  /** 初始化 UI 相关的 AppStorage 默认值 */
  static initUiDefaults(): void {
    AppStorage.setOrCreate(AppStorageKeys.FEATURE_PANEL, '')
    AppStorage.setOrCreate(AppStorageKeys.TOAST, '')
    AppStorage.setOrCreate(AppStorageKeys.NAV_STACK, [] as string[])
    AppStorage.setOrCreate(AppStorageKeys.NAV_IDX, 0)
    AppStorage.setOrCreate(AppStorageKeys.SHARE_VISIBLE, false)
    AppStorage.setOrCreate(AppStorageKeys.SHARE_TITLE, '')
    AppStorage.setOrCreate(AppStorageKeys.SHARE_URL, '')
    AppStorage.setOrCreate(AppStorageKeys.SHARE_SIZE, '')
    AppStorage.setOrCreate(AppStorageKeys.SHARE_IMAGE, false)
    AppStorage.setOrCreate(AppStorageKeys.SHARE_APPS, DEFAULT_SHARE_APPS)
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_PREVIEW_VISIBLE, false)
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_PREVIEW_URL, '')
    AppStorage.setOrCreate(AppStorageKeys.TABS_RETURN_TAB_ID, '')
    AppStorage.setOrCreate(AppStorageKeys.DL_DIALOG, '')
    AppStorage.setOrCreate(AppStorageKeys.DL_NAME, '')
    AppStorage.setOrCreate(AppStorageKeys.DL_SIZE, '')
    AppStorage.setOrCreate(AppStorageKeys.DL_TYPE, '')
    AppStorage.setOrCreate(AppStorageKeys.DL_SOURCE, '')
    AppStorage.setOrCreate(AppStorageKeys.DOWNLOADS_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.DOWNLOAD_PROGRESS_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.BOOKMARKS_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.HISTORY_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.LIST_STATS_UI_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.BOOKMARKS, [] as object[])
    AppStorage.setOrCreate(AppStorageKeys.HISTORY, [] as object[])
    AppStorage.setOrCreate(AppStorageKeys.DOWNLOADS, [] as object[])
    AppStorage.setOrCreate(AppStorageKeys.TABS, [] as TabSession[])
    AppStorage.setOrCreate(AppStorageKeys.TABS_PERSISTED, [] as TabSession[])
    AppStorage.setOrCreate(AppStorageKeys.TABS_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.SHORTCUTS_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.BROWSE_INCOGNITO, false)
    AppStorage.setOrCreate(AppStorageKeys.IMAGE_LESS_MODE, false)
    AppStorage.setOrCreate(AppStorageKeys.NIGHT_MODE, false)
    AppStorage.setOrCreate(AppStorageKeys.THEME, 'light')
    AppStorage.setOrCreate(AppStorageKeys.THEME_PREFERENCE, 'light')
    AppStorage.setOrCreate(AppStorageKeys.THEME_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.DARK_MODE_PICKER_VISIBLE, false)
    AppStorage.setOrCreate(AppStorageKeys.SAFE_AREA_TOP, 0)
    AppStorage.setOrCreate(AppStorageKeys.SAFE_AREA_BOTTOM, 0)
    AppStorage.setOrCreate(AppStorageKeys.FONT_SIZE, 'system')
    AppStorage.setOrCreate(AppStorageKeys.FONT_UI_REV, 0)
    AppStorage.setOrCreate(AppStorageKeys.FONT_UI_SCALE, 1)
    AppStorage.setOrCreate(AppStorageKeys.FONT_FOREGROUND_TICK, 0)
    AppStorage.setOrCreate(AppStorageKeys.SITE_PERMISSIONS, {
      location: DEFAULT_SITE_PERMISSIONS.location,
      camera: DEFAULT_SITE_PERMISSIONS.camera,
      microphone: DEFAULT_SITE_PERMISSIONS.microphone,
      notification: DEFAULT_SITE_PERMISSIONS.notification
    })
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_WIDTH, 0)
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_HEIGHT, 0)
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_LANDSCAPE, false)
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_REV, 0)
    SystemFontSync.initDefaults()
  }
}
