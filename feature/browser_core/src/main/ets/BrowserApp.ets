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
    // 以下各步仅依赖 DB/设置就绪且分属不同数据域，并行执行摊薄启动串行等待
    const initTasks: Promise<void>[] = [
      SslHandler.loadPersisted(),
      // 启动时清理旧版内置测试数据（书签/历史/下载），不再写入示例记录
      BookmarkRepository.getInstance().seedDefaultsIfEmpty(),
      HistoryRepository.getInstance().seedDefaultsIfEmpty(),
      DownloadRepository.getInstance().seedDefaultsIfEmpty(),
      DownloadManager.getInstance().recoverInterruptedDownloadsOnStartup(),
      // 导入推荐目录全部八项作为默认首页快捷方式（旧版三项安装会一次性补齐站点）
      ShortcutManager.getInstance().importPresetsIfNeeded(),
      TabManager.getInstance().loadFromRepository()
    ]
    await Promise.all(initTasks)
    AppInitGate.markReady()
    // 去除原本「markReady → refreshTabs（预刷）→ ensureDefaultTab → refreshTabs（终刷）」的预刷环节。
    // loadFromRepository 已通过 syncPersistedFromDb 把 TABS_PERSISTED 写入完毕；ensureDefaultTab
    // 内部如需 addTab 自带 refreshTabs；末尾 refreshTabs 作为最终一致点（与原版等价）
    await TabManager.getInstance().ensureDefaultTabForCurrentMode()
    await AppStateSync.refreshTabs(TabManager.getInstance().getAllTabs())
    this.initialized = true
    hilog.info(DOMAIN, TAG, 'BrowserApp initialized')
    // 异常退出后可能残留无痕 Web 缓存；延后清理避免 WebEngine 初始化（清理内部会自启引擎）阻塞启动关键路径
    setTimeout(() => {
      IncognitoWebDataCleaner.getInstance().purgeIncognitoWebData()
    }, 300)
    // 书签/历史等非关键数据后台刷新，缩短冷启动主线程占用
    void AppStateSync.refreshBookmarks()
    void AppStateSync.refreshHistory()
    void AppStateSync.refreshDownloads()
    // 编辑功能关键：refreshShortcuts 之前先把 feature catalog 缓存清掉，让第一次实际调 buildFeatureCatalog()
    // 时能用上已 ready 的 BrowserContext，否则 keyGenerator / getCatalogEntry 反复触发会导致 title 解析
    // 用 id 替代真实文案，引发「编辑打开后无响应 / 整个界面卡住」现象。
    ShortcutManager.invalidateFeatureCatalogCache()
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
