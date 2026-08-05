import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppInitGate } from 'common'
import { WebPermissionGate } from './web/WebPermissionGate'
import { BrowserDatabase } from 'common'
import { BookmarkRepository } from 'common'
import { DownloadRepository } from 'common'
import { HistoryRepository } from 'common'
import { SettingsRepository } from 'common'
import { TabRepository } from 'common'
import { AppStateSync } from './AppStateSync'
import { ShortcutManager } from './ShortcutManager'
import { TabManager } from './tab/TabManager'
import { TabThumbnailRetryService } from './tab/TabThumbnailRetryService'
import { IncognitoWebDataCleaner } from './security/IncognitoWebDataCleaner'
import { DownloadManager } from './download_svc/DownloadManager'
import { DownloadNetworkWatcher } from './download_svc/DownloadNetworkWatcher'
import { SslHandler } from './security/SslHandler'
import { ShareAppAvailability } from './system/ShareAppAvailability'

const DOMAIN: number = 0x0000
const TAG: string = 'BrowserApp'

/** 应用级初始化、配置加载、模块装配 */
export class BrowserApp {
  private static instance: BrowserApp | null = null
  private initialized: boolean = false
  private initPromise: Promise<void> | null = null

  /** 获取 BrowserApp 单例 */
  static getInstance(): BrowserApp {
    if (BrowserApp.instance === null) {
      BrowserApp.instance = new BrowserApp()
    }
    return BrowserApp.instance
  }

  /** 判断应用是否已完成初始化 */
  isReady(): boolean {
    return this.initialized
  }

  /** 确保应用已初始化，支持并发等待同一初始化流程 */
  async ensureInitialized(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return
    }
    if (this.initPromise !== null) {
      await this.initPromise
      return
    }
    this.initPromise = this.init(context)
    await this.initPromise
  }

  /** 执行数据库、仓库与各业务模块的初始化 */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return
    }
    AppStateSync.initUiDefaults()
    await BrowserDatabase.getInstance().init(context)
    await SettingsRepository.getInstance().initDefaults()
    await SslHandler.loadPersisted()
    // 启动时清理旧版内置测试数据（书签/历史/下载），不再写入示例记录
    await BookmarkRepository.getInstance().seedDefaultsIfEmpty()
    await HistoryRepository.getInstance().seedDefaultsIfEmpty()
    await DownloadRepository.getInstance().seedDefaultsIfEmpty()
    await DownloadManager.getInstance().recoverInterruptedDownloadsOnStartup()
    await ShortcutManager.getInstance().importPresetsIfNeeded()
    await TabManager.getInstance().loadFromRepository()
    AppInitGate.markReady()
    // 异常退出后可能残留无痕 Web 缓存，启动时先清理无痕分区
    IncognitoWebDataCleaner.getInstance().purgeIncognitoWebData()
    await AppStateSync.refreshTabs(TabManager.getInstance().getAllTabs())
    await TabManager.getInstance().ensureDefaultTabForCurrentMode()
    await AppStateSync.refreshTabs(TabManager.getInstance().getAllTabs())
    this.initialized = true
    hilog.info(DOMAIN, TAG, 'BrowserApp initialized')
    // 书签/历史等非关键数据后台刷新，缩短冷启动主线程占用
    void AppStateSync.refreshBookmarks()
    void AppStateSync.refreshHistory()
    void AppStateSync.refreshDownloads()
    void AppStateSync.refreshShortcuts()
    void AppStateSync.refreshSettings()
    void AppStateSync.refreshSitePermissions()
    void ShareAppAvailability.probe()
    TabThumbnailRetryService.getInstance().start()
    DownloadNetworkWatcher.getInstance().start()
    // 应用权限校验/申请改在 MainAbility 窗口就绪后执行（requestEnableNotification 需 UI 上下文）
    void WebPermissionGate.getInstance().loadOriginPermissions()
  }
}
