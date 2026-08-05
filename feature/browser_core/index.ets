// ── 核心门面 ──
export { BrowserApp } from './src/main/ets/BrowserApp'
export { BrowserStore } from './src/main/ets/BrowserStore'
export { BrowserNavigation } from './src/main/ets/BrowserNavigation'
export type { UrlValidation } from './src/main/ets/BrowserNavigation'
export { BrowserTheme } from './src/main/ets/BrowserTheme'
export { ShortcutManager } from './src/main/ets/ShortcutManager'
export { AppStateSync } from './src/main/ets/AppStateSync'

// ── 标签页管理 ──
export { TabManager } from './src/main/ets/tab/TabManager'
export { TabThumbnailService } from './src/main/ets/tab/TabThumbnailService'
export { TabThumbnailRetryService } from './src/main/ets/tab/TabThumbnailRetryService'

// ── 网页浏览与交互 (Web 层) ──
export { WebPageController } from './src/main/ets/web/WebPageController'
export { WebStabilityGuard } from './src/main/ets/web/WebStabilityGuard'
export { WebPermissionGate } from './src/main/ets/web/WebPermissionGate'
export type { WebPermissionDecision } from './src/main/ets/web/WebPermissionGate'
export { WebMicCaptureService } from './src/main/ets/web/WebMicCaptureService'
export { ImageClipboardService } from './src/main/ets/web/ImageClipboardService'
export { LocationWarmupService } from './src/main/ets/web/LocationWarmupService'

// ── 下载管理 ──
export { DownloadManager, OpenDownloadResult, ShareService } from './src/main/ets/download_svc/DownloadManager'
export { DownloadNetworkWatcher } from './src/main/ets/download_svc/DownloadNetworkWatcher'
export { DownloadNotificationActionHandler } from './src/main/ets/download_svc/DownloadNotificationActionHandler'
export { DownloadNotificationEventBridge } from './src/main/ets/download_svc/DownloadNotificationEventBridge'
export { DownloadNotificationParams } from './src/main/ets/download_svc/DownloadNotificationParams'
export { DownloadNotificationService } from './src/main/ets/download_svc/DownloadNotificationService'
export { DownloadPathService } from './src/main/ets/download_svc/DownloadPathService'
export { DownloadPermissionHelper } from './src/main/ets/download_svc/DownloadPermissionHelper'
export { DownloadPublishService } from './src/main/ets/download_svc/DownloadPublishService'
export { DownloadSpaceGuard } from './src/main/ets/download_svc/DownloadSpaceGuard'
export { SystemDownloadService } from './src/main/ets/download_svc/SystemDownloadService'
export { MobileDownloadPublishService } from './src/main/ets/download_svc/MobileDownloadPublishService'
export { WebDownloadService } from './src/main/ets/download_svc/WebDownloadService'

// ── 安全与隐私 ──
export { GalleryPermissionHelper } from './src/main/ets/security/GalleryPermissionHelper'
export { SslHandler } from './src/main/ets/security/SslHandler'
export { IncognitoPolicy } from './src/main/ets/security/IncognitoPolicy'
export { IncognitoWebDataCleaner } from './src/main/ets/security/IncognitoWebDataCleaner'
export { AppPermissionService } from './src/main/ets/security/AppPermissionService'

// ── 设置与个性化 ──
export { SettingsStore } from './src/main/ets/settings/SettingsStore'
export { SystemThemeSync } from './src/main/ets/settings/SystemThemeSync'
export { SystemFontSync } from './src/main/ets/settings/SystemFontSync'
export { FontScaleService } from './src/main/ets/settings/FontScaleService'
export { BrowserWindowService } from './src/main/ets/settings/BrowserWindowService'

// ── 系统集成 ──
export { ShareAppAvailability, DEFAULT_SHARE_APPS } from './src/main/ets/system/ShareAppAvailability'
export { ImageGalleryService } from './src/main/ets/system/ImageGalleryService'
export { DownloadNetworkHelper } from './src/main/ets/system/DownloadNetworkHelper'
export { ShareAppsAvailability } from './src/main/ets/system/ShareAppAvailability'

// ── 书签与历史 ──
export { HistorySiteIconService } from './src/main/ets/history/HistorySiteIconService'

// ── 导航 ──
export { NavigationController } from './src/main/ets/navigation/NavigationController'
export { BrowseBackBridge } from './src/main/ets/navigation/BrowseBackBridge'
export { FeaturePanelBackBridge } from './src/main/ets/navigation/FeaturePanelBackBridge'
export { ScanQrService } from './src/main/ets/navigation/ScanQrService'

// ── BrowserModels 重导出 ──
export { TabSession, createTabSession } from './src/main/ets/BrowserModels'
export type { TabEntry } from './src/main/ets/BrowserModels'
export { BookmarkItem, BOOKMARK_ROOT_ID, createBookmarkItem } from './src/main/ets/BrowserModels'
export type { CreateBookmarkItemInput, BookmarkUpdateInput } from './src/main/ets/BrowserModels'
export { BOOKMARK_ROOT_FOLDER } from './src/main/ets/BrowserModels'
export type { BookmarkEntry } from './src/main/ets/BrowserModels'
export { HistoryEntry, createHistoryEntry } from './src/main/ets/BrowserModels'
export { DownloadTask, createDownloadTask, formatFileSizeText } from './src/main/ets/BrowserModels'
export type { DownloadEntry, DownloadStatus } from './src/main/ets/BrowserModels'
export { ShortcutItem, createShortcutItem } from './src/main/ets/BrowserModels'
export type { ShortcutCatalogEntry, ShortcutKind, ShortcutFeature } from './src/main/ets/BrowserModels'
export { FeaturePanelType, DateGroup, ShareSheetParams, OpenShareOptions,
  DownloadRequest, AddTabOptions, OpenBrowseOptions, BrowseRouteParams,
  TabsRouteParams, ShortcutMoveDirection, BrowseTabPatch,
  BOOKMARK_LIMIT, TAB_LIMIT, TAB_LIMIT_DISPLAY, AppStorageKeys
} from './src/main/ets/BrowserModels'
export { BrowserUtils, getSearchEngineBase, tabHostname, isImageFile,
  suggestRename, inferFileTypeLabel, groupHistoryByDate, groupDownloadsByDate,
  historySiteIconChar, formatHistorySectionDate, formatDownloadSectionDate
} from './src/main/ets/BrowserModels'

