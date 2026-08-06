import { webview } from '@kit.ArkWeb'
import { BrowserNavigation } from 'browser_core'
import { bindBrowserPageContext } from 'common'
import { BrowserRouterBridge } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { BrowserUtils } from 'common'
import { BrowseRouteParams, DownloadRequest, BrowseTabPatch, tabHostname } from 'browser_core'
import { BookmarkItem } from 'common'
import { SitePermissionId } from 'common'
import { BrowserStrings } from 'common'
import { DownloadFlowDialog } from 'download'
import { FeaturePanel } from 'bookmark'
import { ShareSheet } from 'settings'
import { ToastBar } from 'commons'
import { BrowseWebContextSheet } from './BrowseWebContextSheet'
import { BrowseLinkContextMenu } from './BrowseLinkContextMenu'
import { WebImageLightbox } from './WebImageLightbox'
import { image } from '@kit.ImageKit'
import { WebTextMenuHelper } from './WebTextMenuHelper'
import { WebPageController } from 'browser_core'
import { WebBrowseJsBridge } from './WebBrowseJsBridge'
import { buildMicGumPolyfillScript } from './WebMicGumPolyfill'
import { WebDownloadService } from 'browser_core'
import { WebMicCaptureService } from 'browser_core'
import { TabThumbnailRetryService } from 'browser_core'
import { TabThumbnailService } from 'browser_core'
import { HistorySiteIconService } from 'bookmark'
import { WebStabilityGuard } from 'browser_core'
import { BrowserWindowService } from 'browser_core'
import { BrowseBackBridge } from 'browser_core'
import { FeaturePanelBackBridge } from 'browser_core'
import { BrowserLog } from 'common'
import { SslHandler } from 'browser_core'
import { PanelConfirmDialog } from 'commons'
import { DarkModePickerDialog } from 'commons'
import { AddBookmarkDialog } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'
import { SearchLeadingIcon, ShareCircleIcon, StarBookmarkIcon, TabCountBadge, StatBookmarkIcon, StatDownloadIcon, StatHistoryIcon, BOOKMARK_STAR_COLOR, IncognitoServiceIcon, ServiceToggleItem, serviceToggleLabelColor, serviceTileBgDefault, BrowseToolbarBackIcon, BrowseToolbarForwardIcon, BrowseToolbarMoreIcon, BrowseToolbarDownloadProgressIcon, NavHomeIcon, NavChevronRight, BROWSE_TOOLBAR_ICON_BOX } from 'commons'
import { AppStorageKeys } from 'common'
import { DownloadTask } from 'common'
import { BrowseAddressBar } from './BrowseUrlEditInput'
import { WebBrowseViewModel } from './WebBrowseViewModel'
import { SecurityPrivacyViewModel } from 'security'
import { WebErrorPageHelper } from './WebErrorPageHelper'
import { WebLoadNetworkRetryService } from './WebLoadNetworkRetryService'
import { WebPermissionGate, WebPermissionDecision } from 'browser_core'
import { LocationWarmupService } from 'browser_core'
import { HistoryEntry } from 'common'

/** ArkWeb PermissionRequest 适配器：web.d.ts 未导出该类型，仅在 Web 组件内可见 */
interface PermissionRequestAdapter {
  getOrigin(): string
  getAccessibleResource(): string[]
  grant(resources: string[]): void
  deny(): void
}

class PermissionRequestAdapterImpl implements PermissionRequestAdapter {
  private readonly getOriginFn: () => string
  private readonly getResourceFn: () => string[]
  private readonly grantFn: (r: string[]) => void
  private readonly denyFn: () => void

  constructor(getOrigin: () => string, getResource: () => string[],
    grant: (r: string[]) => void, deny: () => void) {
    this.getOriginFn = getOrigin
    this.getResourceFn = getResource
    this.grantFn = grant
    this.denyFn = deny
  }

  getOrigin(): string {
    return this.getOriginFn()
  }

  getAccessibleResource(): string[] {
    return this.getResourceFn()
  }

  grant(resources: string[]): void {
    this.grantFn(resources)
  }

  deny(): void {
    this.denyFn()
  }
}

function asPermissionRequest(obj: object): PermissionRequestAdapter | null {
  const fns = obj as Record<string, Object>
  if (typeof fns['getOrigin'] !== 'function' || typeof fns['getAccessibleResource'] !== 'function' ||
    typeof fns['grant'] !== 'function' || typeof fns['deny'] !== 'function') {
    return null
  }
  // 必须通过原对象调用方法以保留 native this；直接拆函数指针会导致
  // JSWebPermissionRequest::GetOrigin 空指针 SIGSEGV（@0x28）。
  const host = obj as PermissionRequestAdapter
  return new PermissionRequestAdapterImpl(
    (): string => host.getOrigin(),
    (): string[] => host.getAccessibleResource(),
    (r: string[]): void => host.grant(r),
    (): void => host.deny()
  )
}

/** 网页浏览 View：Web 渲染、地址栏、工具栏与各类弹层 */
@Component
export struct BrowsePageView {
  private webController: webview.WebviewController = new webview.WebviewController()
  private webPage: WebPageController = WebPageController.getInstance()
  @State webVm: WebBrowseViewModel = new WebBrowseViewModel()
  @State securityVm: SecurityPrivacyViewModel = new SecurityPrivacyViewModel()
  @State currentUrl: string = 'https://www.baidu.com'
  /** Web 组件初始 src，仅在进入页面时设置一次，页内跳转不再改 src */
  @State webEntryUrl: string = 'https://www.baidu.com'
  @State pageTitle: string = ''
  @State progress: number = 100
  @State isLoading: boolean = false
  @StorageLink('browser_bookmarks') bookmarks: BookmarkItem[] = []
  @StorageLink('browser_history') historyList: HistoryEntry[] = []
  @StorageLink('browser_feature_panel') featurePanel: string = ''
  @StorageLink('browser_share_visible') shareVisible: boolean = false
  @StorageLink('browser_dl_dialog') dlDialog: string = ''
  @StorageLink('browser_image_preview_visible') imagePreviewVisible: boolean = false
  @StorageLink('browser_theme') @Watch('onThemeChanged') theme: string = 'light'
  @StorageLink('browser_incognito') @Watch('onIncognitoModeChanged') isIncognito: boolean = false
  @StorageLink('browser_image_less') imageLessMode: boolean = false
  @StorageLink('browser_font_size') @Watch('onFontSettingsChanged') fontSizeKey: string = 'system'
  @StorageLink('browser_system_font_size_scale') @Watch('onFontSettingsChanged') systemFontSizeScale: number = 1
  @StorageLink('browser_font_ui_rev') @Watch('onFontSettingsChanged') fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) @Watch('onFontSettingsChanged') fontUiScale: number = 1
  @StorageLink(AppStorageKeys.FONT_FOREGROUND_TICK) @Watch('onFontForegroundTick') fontForegroundTick: number = 0
  @StorageLink(AppStorageKeys.NAV_IDX) navIdx: number = 0
  @StorageLink(AppStorageKeys.DOWNLOADS) downloads: DownloadTask[] = []
  @StorageLink(AppStorageKeys.DOWNLOADS_REV) downloadsRev: number = 0
  @StorageLink(AppStorageKeys.DOWNLOAD_PROGRESS_REV) downloadProgressRev: number = 0
  @StorageLink(AppStorageKeys.WINDOW_REV) @Watch('onWindowLayoutChanged') windowRev: number = 0
  @StorageProp(AppStorageKeys.SAFE_AREA_BOTTOM) safeAreaBottom: number = 0
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  /** 底部后退/前进是否可用（显式 @State，避免 @Builder 未随 AppStorage 刷新） */
  @State navCanGoBack: boolean = false
  @State navCanGoForward: boolean = false
  /** 触发底部工具栏前进/后退按钮状态刷新 */
  @State navUiRev: number = 0
  /** H5 视频进入系统全屏时隐藏浏览器 chrome */
  @State webMediaFullscreen: boolean = false
  /** 地址栏是否处于编辑态 */
  @State urlEditActive: boolean = false
  /** 地址栏编辑：打开时的初始文本 */
  @State urlEditInputText: string = ''
  /** 递增以重建地址栏输入子组件 */
  @State urlEditFocusKey: number = 0
  /** 添加书签弹窗 */
  @State showAddBookmarkDialog: boolean = false
  @State showDarkModePicker: boolean = false
  @State addBookmarkDefaultTitle: string = ''

  @State browseTabId: string = ''
  /** Web 文本缩放（100=默认），@State 绑定 textZoomRatio 以支持热更新 */
  @State webTextZoom: number = 100
  /** 递增以强制重建 Web 组件，避免 GPU 合成层残留（如相机帧冻屏） */
  @State webRenderKey: number = 0
  /** 入口页同站重定向稳定后再收尾（360 等桌面站会连续跳转） */
  private static readonly ENTRY_SETTLE_MS: number = 450
  private thumbCaptureTimer: number = -1
  /** 入口加载阶段：不同步导航栈，避免重定向撑栈 */
  private entrySessionPending: boolean = true
  private entrySettleTimer: number = -1
  /** 本次浏览会话的入口站点（www/m 归一） */
  private sessionEntrySiteKey: string = ''
  /** 用户请求的入口 URL（搜索/直达），入口稳定后作为导航栈根 */
  private sessionEntryUrl: string = ''
  /** 应用栈 programmatic 后退中：抑制 Web 历史同步撑栈 */
  private appNavPending: boolean = false
  private appNavTargetUrl: string = ''
  /** 用户触发刷新后，onPageEnd 清除 Web 内 refresh 累积的后退项 */
  private webRefreshPending: boolean = false
  /** onPageHide 触发的截图任务，aboutToDisappear 完成后再解绑 Web */
  private hideThumbCaptureTask: Promise<void> | null = null
  /** 当前导航是否已写入历史（每次 onPageBegin 重置） */
  private historyCommittedForNavigation: boolean = false
  private lastCommittedHistoryUrl: string = ''
  private screenPaintReady: boolean = false
  /** 上次已同步到标签页元数据的标题，用于跳过重复 syncBrowseTab */
  private lastSyncedTitle: string = ''
  /** 上次已同步到标签页元数据的 URL，用于跳过重复 syncBrowseTab */
  private lastSyncedUrl: string = ''
  private webJsBridge: WebBrowseJsBridge = new WebBrowseJsBridge((url: string) => {
    BrowserStore.openImagePreview(url)
  })
  /**
   * 文档起始注入：getUserMedia 音频走原生旁路，规避 ArkWeb audioBus 丢帧无声。
   */
  private micGumScripts: ScriptItem[] = [{
    script: buildMicGumPolyfillScript(),
    scriptRules: ['*']
  }]
  /** Web 内核上下文菜单句柄，关闭自定义菜单时需 closeContextMenu */
  private webCtxResult: WebContextMenuResult | null = null
  /** Web 可视区相对窗口左上角的 vp 坐标（长按菜单锚点换算用） */
  @State webViewGlobalX: number = 0
  @State webViewGlobalY: number = 0
  /** 页面 Web 仍挂载时可安全处理 Web 回调 */
  private browseWebActive: boolean = true
  /** 离页截图防抖定时器 */
  private static readonly HIDE_THUMB_DEFER_MS: number = 900
  /** 已应用的字体 rev，避免重复刷新 Web */
  private lastAppliedFontRev: number = -1
  private lastAppliedFontKey: string = ''
  /** 上次以 remount 路径落到 Web 上的 zoom；用于避免无效热更新 */
  private lastRemountedZoom: number = -1

  /** 将当前 URL/标题绑定到标签页会话 */
  private async bindBrowseTab(url: string, tabId?: string): Promise<void> {
    const resolved = await BrowserStore.resolveBrowseTabId(url, this.isIncognito, false, tabId)
    this.browseTabId = resolved
    const bindPatch: BrowseTabPatch = {
      url,
      title: this.pageTitle || BrowserUtils.browsePageTitle(url),
      isHome: false
    }
    await BrowserStore.syncBrowseTab(resolved, bindPatch)
  }

  /** onFirstScreenPaint 成功后标记当前 Web 标签并补抓缺失缩略图 */
  private notifyThumbRetryReady(): void {
    if (this.browseTabId) {
      TabThumbnailRetryService.getInstance().notifyWebReady(this.browseTabId)
    }
  }

  /** 首屏绘制完成或回到浏览页后：若仍无缩略图则在后台补抓（页签管理页可见时也会刷新 UI） */
  private async captureMissingThumbnailAfterPaint(): Promise<void> {
    if (!this.browseTabId || !this.screenPaintReady) {
      return
    }
    const thumbSvc = TabThumbnailService.getInstance()
    thumbSvc.beginCaptureWindow()
    try {
      const ok = await BrowserStore.captureTabThumbnailIfMissing(this.browseTabId)
      BrowserLog.info(`[TabThumb] paintReady capture tab=${this.browseTabId} ok=${ok}`)
    } finally {
      thumbSvc.endCaptureWindow()
    }
  }

  /** 离开浏览页 / 进标签管理前截图（防抖 + GPU 节流，降低 render_service 压力） */
  private flushThumbnailCapture(): Promise<void> {
    if (!this.browseTabId || !this.screenPaintReady) {
      return Promise.resolve()
    }
    if (this.thumbCaptureTimer >= 0) {
      clearTimeout(this.thumbCaptureTimer)
      this.thumbCaptureTimer = -1
    }
    return new Promise((resolve) => {
      this.thumbCaptureTimer = setTimeout(() => {
        this.thumbCaptureTimer = -1
        if (!this.browseTabId || !this.screenPaintReady) {
          resolve()
          return
        }
        const thumbSvc = TabThumbnailService.getInstance()
        thumbSvc.beginCaptureWindow()
        void BrowserStore.captureTabThumbnail(this.browseTabId).finally(() => {
          thumbSvc.endCaptureWindow()
          resolve()
        })
      }, BrowsePageView.HIDE_THUMB_DEFER_MS) as number
    })
  }

  /** 立即进入标签管理：先截图再落盘元数据，避免 flush 清空缩略图后截图失败 */
  private openTabsWithThumbnail(): void {
    const tabId = this.browseTabId
    BrowserLog.info(`openTabsWithThumbnail tabId=${tabId} paintReady=${this.screenPaintReady}`)
    void BrowserStore.whenReady().then(async () => {
      if (tabId) {
        const thumbSvc = TabThumbnailService.getInstance()
        thumbSvc.beginCaptureWindow()
        try {
          const ok = await BrowserStore.captureTabThumbnail(tabId)
          BrowserLog.info(`openTabsWithThumbnail capture ok=${ok} tab=${tabId} paintReady=${this.screenPaintReady}`)
          if (!ok && !this.screenPaintReady) {
            TabThumbnailRetryService.getInstance().enqueue(tabId, 'web', true)
            BrowserLog.info(`openTabsWithThumbnail defer thumb until paintReady tab=${tabId}`)
          }
        } finally {
          thumbSvc.endCaptureWindow()
        }
      }
      await BrowserStore.flushSyncBrowseTab(tabId)
      BrowserNavigation.openTabs()
    })
  }

  /** 将页面标题/URL 同步到标签页元数据（跳过与上次相同的值） */
  private syncTabMeta(title?: string, url?: string): void {
    if (!this.browseTabId) {
      return
    }
    const nextTitle = title ?? this.pageTitle
    const nextUrl = url ?? this.currentUrl
    if (nextTitle === this.lastSyncedTitle && nextUrl === this.lastSyncedUrl) {
      return
    }
    this.lastSyncedTitle = nextTitle
    this.lastSyncedUrl = nextUrl
    const metaPatch: BrowseTabPatch = {
      url: nextUrl,
      title: nextTitle,
      isHome: false
    }
    void BrowserStore.syncBrowseTab(this.browseTabId, metaPatch)
  }

  /** 当前浏览页主框架主机，用于子资源 SSL 联动放行 */
  private sslPageHost(): string {
    const pageUrl = this.currentUrl.trim()
    if (pageUrl.length > 0) {
      return tabHostname(pageUrl)
    }
    return ''
  }

  /** 主框架/子资源 SSL 错误：已信任主机直接放行；主框架弹窗确认；子资源未信任则取消 */
  private onWebSslError(event: SslErrorEvent): void {
    if (!event?.handler) {
      return
    }
    const errUrl = event.url.length > 0 ? event.url :
      (event.originalUrl.length > 0 ? event.originalUrl : this.currentUrl)
    const host = tabHostname(errUrl)
    const pageHost = this.sslPageHost()
    BrowserLog.warn(`[SslError] main=${event.isMainFrame} host=${host} pageHost=${pageHost} error=${event.error}`)

    if (SslHandler.shouldProceedResource(host, pageHost)) {
      BrowserLog.info(`[SslError] proceed host=${host} pageHost=${pageHost}`)
      event.handler.handleConfirm()
      return
    }

    if (!event.isMainFrame) {
      event.handler.handleCancel()
      return
    }

    if (this.securityVm.showSslDialog) {
      event.handler.handleCancel()
      return
    }

    SslHandler.bindPending(event.handler, host)
    this.securityVm.onSslError(host)
  }

  /** 清理弹层残留，避免全屏层拦截 Web / 工具栏触摸 */
  private resetBrowsePageInteractionState(source: string): void {
    this.webVm.showMoreSheet = false
    this.closeWebContextMenu()
    this.webVm.showUrlEdit = false
    this.webVm.urlEditText = ''
    this.urlEditActive = false
    this.urlEditInputText = ''
    BrowserStore.closeImagePreview()
    BrowserStore.closeShareSheet()
    BrowserStore.closeFeaturePanel()
    BrowserStore.closeDownloadDialog()
    BrowserLog.info(`[BrowsePage] reset interaction source=${source} ` +
      `more=${this.webVm.showMoreSheet} webCtx=${this.webVm.showWebCtx} linkCtx=${this.webVm.showLinkCtx} preview=${this.imagePreviewVisible} ` +
      `share=${this.shareVisible} panel=${this.featurePanel}`)
  }

  /** 设置面板改了全局 site 策略：把当前 active 页 origin 写入 webview 静态表 */
  private onPolicyChanged = (_origin: string): void => {
    try {
      const url = this.webPage?.getCurrentUrl?.() ?? this.currentUrl
      const origin = WebPermissionGate.extractOriginFromUrl(typeof url === 'string' ? url : '')
      if (origin.length > 0) {
        WebPermissionGate.getInstance().applyLocationPolicyToOrigin(origin, this.getUIContext(), this.isIncognito)
      }
    } catch (e) {
      BrowserLog.warn(`[WebPerm] onPolicyChanged threw: ${JSON.stringify(e)}`)
    }
  }

  aboutToAppear(): void {
    this.browseWebActive = true
    this.webTextZoom = BrowserStrings.computeWebTextZoomRatio(this.fontSizeKey, this.systemFontSizeScale)
    this.lastAppliedFontRev = -1
    this.lastRemountedZoom = this.webTextZoom
    bindBrowserPageContext(this.getUIContext())
    BrowserWindowService.getInstance().ensureWindowSizeSynced()
    WebTextMenuHelper.initTextMenuPolicy()
    this.webRenderKey++
    this.resetBrowsePageInteractionState('aboutToAppear')
    BrowseBackBridge.register(() => this.onBrowseBackPress())
    BrowserWindowService.getInstance().setGestureBackEnabled(true)
    BrowserWindowService.getInstance().setPageSwipeBackEnabled(this.getUIContext(), true)
    BrowserStore.init()
    this.webPage.bindController(this.webController)
    WebPermissionGate.getInstance().addPolicyChangeListener(this.onPolicyChanged)
    if (!this.pageTitle) {
      this.pageTitle = BrowserStrings.browsePageTitleDefault()
    }
    const params = BrowserRouterBridge.getInstance().getParams() as BrowseRouteParams
    if (params?.url) {
      const resolvedUrl = BrowserUtils.resolveBrowseUrl(params.url)
      this.currentUrl = resolvedUrl
      this.applyWebEntryForUrl(resolvedUrl)
      this.pageTitle = BrowserUtils.browsePageTitle(resolvedUrl)
      if (params.skipNav !== '1') {
        BrowserStore.resetNavStack(resolvedUrl)
      }
    } else {
      this.applyWebEntryForUrl(this.currentUrl)
    }
    this.entrySessionPending = true
    this.sessionEntrySiteKey = BrowserUtils.browseSiteKey(this.currentUrl)
    this.sessionEntryUrl = this.currentUrl
    void this.bindBrowseTab(this.currentUrl, params?.tabId)
    BrowserStore.recordBrowseIncognito(this.isIncognito)
    TabThumbnailService.getInstance().setBrowsePageForeground(true)
  }

  aboutToDisappear(): void {
    BrowseBackBridge.unregister()
    WebPermissionGate.getInstance().removePolicyChangeListener(this.onPolicyChanged)
    if (this.imagePreviewVisible) {
      BrowserLog.info('[ImagePreview] aboutToDisappear force close')
      BrowserStore.closeImagePreview()
    }
    this.flushBrowseHistoryIfNeeded()
    if (this.thumbCaptureTimer >= 0) {
      clearTimeout(this.thumbCaptureTimer)
      this.thumbCaptureTimer = -1
    }
    this.clearEntrySettleTimer()
    const captureTask = this.hideThumbCaptureTask
    this.hideThumbCaptureTask = null
    if (captureTask) {
      void captureTask.finally(() => {
        this.teardownBrowseWeb()
      })
    } else {
      this.teardownBrowseWeb()
    }
  }

  /** 无痕模式切换后重建 Web，使 incognitoMode 生效 */
  private onIncognitoModeChanged(): void {
    this.webRenderKey++
  }

  /** 页面销毁时释放 Web 与下载监听 */
  private teardownBrowseWeb(): void {
    this.browseWebActive = false
    WebMicCaptureService.getInstance().stop()
    WebLoadNetworkRetryService.getInstance().clearPending()
    this.webPage.unbindController()
    WebDownloadService.getInstance().detach()
    this.webPage.clearFind()
  }

  onPageHide(): void {
    this.browseWebActive = false
    WebStabilityGuard.suspendGpuHeavyWork(5000)
    BrowserWindowService.getInstance().setGestureBackEnabled(true)
    BrowserWindowService.getInstance().setPageSwipeBackEnabled(this.getUIContext(), true)
    this.flushBrowseHistoryIfNeeded()
    TabThumbnailService.getInstance().setBrowsePageForeground(false)
    this.hideThumbCaptureTask = this.flushThumbnailCapture()
  }

  onPageShow(): void {
    this.browseWebActive = true
    if (this.thumbCaptureTimer >= 0) {
      clearTimeout(this.thumbCaptureTimer)
      this.thumbCaptureTimer = -1
    }
    bindBrowserPageContext(this.getUIContext())
    TabThumbnailService.getInstance().setBrowsePageForeground(true)
    BrowserStore.closeImagePreview()
    this.resetBrowsePageInteractionState('onPageShow')
    BrowserWindowService.getInstance().setGestureBackEnabled(true)
    BrowserWindowService.getInstance().setPageSwipeBackEnabled(this.getUIContext(), true)
    BrowserWindowService.getInstance().syncSystemBarForTheme(this.isBrowseDark(), null, true)
    BrowserStore.recordBrowseIncognito(this.isIncognito)
    // 多任务切回：Ability onForeground 已同步 AppStorage，此处强制把 textZoom 再应用到 Web
    // 多任务切回：Ability onForeground 已同步 AppStorage；仅当 native zoom 落后时 remount
    const pageShowZoom = BrowserStrings.computeWebTextZoomRatio(
      BrowserStrings.normalizeFontSizeKey(this.fontSizeKey), this.systemFontSizeScale)
    this.forceApplyWebTextZoom('onPageShow', pageShowZoom, undefined,
      this.lastRemountedZoom !== pageShowZoom)
    if (this.browseTabId) {
      TabThumbnailRetryService.getInstance().notifyWebReady(this.browseTabId)
    }
    if (this.screenPaintReady) {
      void this.captureMissingThumbnailAfterPaint()
    }
  }

  /** 主题切换后重载 Web，使 darkMode / forceDarkAccess 生效 */
  private onThemeChanged(): void {
    BrowserWindowService.getInstance().syncSystemBarForTheme(this.isBrowseDark(), null, true)
    const url = this.webPage.getCurrentUrl() || this.currentUrl
    BrowserLog.info(`[Theme] BrowsePage theme=${this.theme} reload=${url.slice(0, 80)}`)
    if (url.length > 0) {
      this.webPage.loadUrl(url)
    }
  }

  /** 横竖屏切换后刷新导航按钮 */
  private onWindowLayoutChanged(): void {
    if (BrowserWindowService.getInstance().isLayoutFrozen()) {
      return
    }
    BrowserLog.info(`[Window] BrowsePage layout rev=${this.windowRev}`)
    this.scheduleRefreshNavActions()
  }

  private isBrowseDark(): boolean {
    return this.theme === 'dark'
  }

  private browsePageBg(): string {
    return this.isBrowseDark() ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  private browsePanelBg(): string {
    return this.isBrowseDark() ? BrowserTheme.DARK_PANEL_BG : BrowserTheme.LIGHT_PANEL_BG
  }

  private browseText(): string {
    return BrowserTheme.text(this.isBrowseDark())
  }

  private browseTextMuted(): string {
    return BrowserTheme.textMuted(this.isBrowseDark())
  }

  private browseTextSecondary(): string {
    return BrowserTheme.textSecondary(this.isBrowseDark())
  }

  private browsePrimary(): string {
    return BrowserTheme.primaryColor(this.isBrowseDark())
  }

  /** 仅关闭图片预览，不触发 Web/路由后退 */
  private closeImagePreviewOnly(source: string): void {
    if (!this.imagePreviewVisible) {
      return
    }
    BrowserLog.info(`[ImagePreview] close source=${source}`)
    BrowserStore.closeImagePreview()
  }

  private shouldBlockPageNavigateBack(): boolean {
    const until = AppStorage.get<number>(AppStorageKeys.IMAGE_PREVIEW_BACK_BLOCK_UNTIL) ?? 0
    return Date.now() < until
  }

  /** 先关闭弹层，返回 true 表示已消费返回事件 */
  private consumeBrowseOverlayBack(source: string): boolean {
    if (this.featurePanel.length > 0 && FeaturePanelBackBridge.handleBackPress()) {
      return true
    }
    if (this.shareVisible && this.imagePreviewVisible) {
      BrowserStore.closeShareSheet()
      BrowserLog.info(`[ImagePreview] ${source} close share`)
      return true
    }
    if (this.shareVisible && !this.imagePreviewVisible) {
      BrowserStore.closeShareSheet()
      return true
    }
    if (this.dlDialog.length > 0) {
      BrowserStore.closeDownloadDialog()
      if (this.imagePreviewVisible) {
        BrowserLog.info(`[ImagePreview] ${source} close download dialog`)
      }
      return true
    }
    if (this.featurePanel.length > 0) {
      BrowserStore.closeFeaturePanel()
      return true
    }
    if (this.webVm.showMoreSheet) {
      this.webVm.showMoreSheet = false
      return true
    }
    if (this.imagePreviewVisible) {
      this.closeImagePreviewOnly(source)
      return true
    }
    return false
  }

  /** 系统导航条返回 / 侧滑返回（经 BrowsePage.onBackPress → BrowseBackBridge） */
  private onBrowseBackPress(): boolean {
    if (this.consumeBrowseOverlayBack('onBackPress')) {
      return true
    }
    if (this.shouldBlockPageNavigateBack()) {
      BrowserLog.info('[ImagePreview] onBackPress blocked post-dismiss')
      return true
    }
    const target = this.resolveBrowseBackNavigation('onBackPress')
    if (target === 'home') {
      if (BrowserNavigation.canPopBrowsePageToMain()) {
        void BrowserStore.whenReady().then(() => {
          void BrowserStore.activateHomeTabForUi()
        })
        return false
      }
      BrowserNavigation.goHome()
      return true
    }
    return true
  }

  /** 应用导航栈已在入口时，跳过 Web 内部重定向历史（如 360 首页） */
  private shouldExitBrowseToHome(): boolean {
    if (!BrowserStore.canBrowseBack()) {
      return true
    }
    if (this.entrySessionPending &&
      BrowserUtils.browseSiteKey(this.currentUrl) === this.sessionEntrySiteKey) {
      return true
    }
    return false
  }

  /** 入口重定向链稳定后：折叠导航栈并清除 Web 内部后退历史 */
  private scheduleEntrySessionFinalize(loadedUrl: string): void {
    if (!this.entrySessionPending) {
      return
    }
    if (this.entrySettleTimer >= 0) {
      clearTimeout(this.entrySettleTimer)
    }
    this.entrySettleTimer = setTimeout(() => {
      this.entrySettleTimer = -1
      this.finalizeEntrySession(loadedUrl)
    }, BrowsePageView.ENTRY_SETTLE_MS) as number
  }

  private finalizeEntrySession(loadedUrl: string): void {
    if (!this.entrySessionPending) {
      return
    }
    this.entrySessionPending = false
    const anchorUrl = this.resolveEntryStackAnchor(loadedUrl)
    if (this.shouldTrackNavUrl(anchorUrl)) {
      BrowserStore.resetNavStack(anchorUrl)
    }
    this.webPage.clearWebHistory()
    this.scheduleRefreshNavActions()
    BrowserLog.info(`[NavEntry] finalized site=${this.sessionEntrySiteKey} anchor=${anchorUrl.slice(0, 80)}`)
  }

  /** 入口稳定后保留用户请求的 URL，避免 baidu.php 等中转页成为后退目标 */
  private resolveEntryStackAnchor(loadedUrl: string): string {
    const entry = BrowserUtils.normalizeHistoryUrl(this.sessionEntryUrl)
    const loaded = BrowserUtils.normalizeHistoryUrl(loadedUrl)
    if (entry.length > 0 &&
      BrowserUtils.browseSiteKey(entry) === BrowserUtils.browseSiteKey(loaded) &&
      !BrowserUtils.isNavTransitUrl(entry)) {
      return entry
    }
    if (BrowserUtils.isNavTransitUrl(loaded) && entry.length > 0) {
      return entry
    }
    return loaded
  }

  /** 当前页已离开入口站（如外链结果页），优先走应用导航栈 */
  private shouldPreferAppNavBack(): boolean {
    if (this.sessionEntrySiteKey.length === 0) {
      return false
    }
    return BrowserUtils.browseSiteKey(this.currentUrl) !== this.sessionEntrySiteKey
  }

  /** 仍在入口站内且有应用栈时，优先应用栈后退，跳过 Web refresh 累积项 */
  private shouldPreferAppNavOverWebBack(): boolean {
    if (!BrowserStore.canBrowseBack() || this.sessionEntrySiteKey.length === 0) {
      return false
    }
    return BrowserUtils.browseSiteKey(this.currentUrl) === this.sessionEntrySiteKey
  }

  /** 刷新完成后折叠 Web 内后退历史，避免底栏后退逐次回退 refresh 快照 */
  private finalizeWebRefreshIfNeeded(): void {
    if (!this.webRefreshPending) {
      return
    }
    this.webRefreshPending = false
    this.webPage.clearWebHistory()
    BrowserLog.info('[NavRefresh] cleared web history after refresh')
  }

  /** 应用栈在根 (idx=0) 时不消费 Web 内 refresh 历史 */
  private shouldUseWebHistoryBack(webBack: boolean): boolean {
    if (!webBack) {
      return false
    }
    return BrowserStore.canBrowseBack()
  }

  /** 应用栈后退并 loadUrl，完成后清除 Web 内部历史 */
  private performAppNavBack(source: string): boolean {
    const prev = BrowserStore.browseBackSkippingTransit()
    if (!prev) {
      return false
    }
    this.loadAppNavUrl(prev, source)
    return true
  }

  private loadAppNavUrl(url: string, source: string): void {
    const target = BrowserUtils.normalizeHistoryUrl(url)
    BrowserLog.info(`[NavGoBack] source=${source} via=app url=${target.slice(0, 80)}`)
    this.appNavTargetUrl = target
    this.appNavPending = true
    this.currentUrl = url
    this.webPage.loadUrl(url)
    this.refreshNavActions()
  }

  private tryCompleteAppNav(url: string): void {
    if (!this.appNavPending) {
      return
    }
    const normalized = BrowserUtils.normalizeHistoryUrl(url)
    if (normalized.length === 0) {
      return
    }
    if (normalized === this.appNavTargetUrl) {
      this.finishAppNav(normalized)
      return
    }
    if (BrowserUtils.browseSiteKey(normalized) === BrowserUtils.browseSiteKey(this.appNavTargetUrl) &&
      !BrowserUtils.isNavTransitUrl(normalized)) {
      this.finishAppNav(normalized)
    }
  }

  private finishAppNav(url: string): void {
    this.appNavPending = false
    this.currentUrl = url
    BrowserStore.syncNavToUrl(url)
    this.webPage.clearWebHistory()
    this.scheduleRefreshNavActions()
    BrowserLog.info(`[NavAppBack] settled url=${url.slice(0, 80)}`)
  }

  private clearEntrySettleTimer(): void {
    if (this.entrySettleTimer >= 0) {
      clearTimeout(this.entrySettleTimer)
      this.entrySettleTimer = -1
    }
  }

  /** 统一后退决策：工具栏 / 导航条 / 边缘侧滑提交共用 */
  private resolveBrowseBackNavigation(source: string): 'web' | 'app' | 'home' {
    const webBack = this.webPage.canGoBack()
    const appBack = BrowserStore.canBrowseBack()
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    const stackLen = (AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []).length
    BrowserLog.info(`[NavGoBack] source=${source} webBack=${webBack} appBack=${appBack} idx=${idx} stack=${stackLen}`)
    if (this.shouldExitBrowseToHome()) {
      BrowserLog.info(`[NavGoBack] source=${source} via=home (app-root)`)
      return 'home'
    }
    if (appBack && this.shouldPreferAppNavBack()) {
      if (this.performAppNavBack(source)) {
        return 'app'
      }
    }
    if (appBack && this.shouldPreferAppNavOverWebBack()) {
      if (this.performAppNavBack(source)) {
        return 'app'
      }
    }
    if (this.shouldUseWebHistoryBack(webBack) && this.webPage.goBack()) {
      BrowserLog.info(`[NavGoBack] source=${source} via=web`)
      this.refreshNavActions()
      return 'web'
    }
    if (appBack && this.performAppNavBack(source)) {
      return 'app'
    }
    BrowserLog.info(`[NavGoBack] source=${source} via=home`)
    return 'home'
  }

  /** 后退：弹层 → 全屏图片预览 → Web 历史栈 / 应用导航栈 / 首页 */
  private goBack(source: string = 'toolbar'): void {
    if (this.consumeBrowseOverlayBack(source)) {
      return
    }
    if (this.shouldBlockPageNavigateBack()) {
      BrowserLog.info(`[NavGoBack] source=${source} blocked post-dismiss`)
      return
    }
    const target = this.resolveBrowseBackNavigation(source)
    if (target === 'home') {
      BrowserNavigation.goHome()
    }
  }

  /** 前进：优先 Web 历史栈，其次应用导航栈 */
  private goForward(): void {
    if (this.webPage.goForward()) {
      this.refreshNavActions()
      return
    }
    const next = BrowserStore.browseForward()
    if (next) {
      this.currentUrl = next
      this.webPage.loadUrl(next)
      this.refreshNavActions()
    }
  }

  /** 刷新底部后退/前进按钮可用态 */
  private refreshNavActions(): void {
    const webBack = this.webPage.canGoBack()
    const webFwd = this.webPage.canGoForward()
    const appBack = BrowserStore.canBrowseBack()
    const appFwd = BrowserStore.canBrowseForward()
    const exitHome = this.shouldExitBrowseToHome()
    // 应用栈在入口时仍可后退回主页（即使 Web 内有重定向/refresh 历史）
    this.navCanGoBack = webBack || appBack || exitHome
    this.navCanGoForward = webFwd || appFwd
    this.navUiRev++
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    const stackLen = (AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []).length
    BrowserLog.info(`[NavUi] webBack=${webBack} webFwd=${webFwd} appBack=${appBack} appFwd=${appFwd} ` +
      `exitHome=${exitHome} canBack=${this.navCanGoBack} idx=${idx} stack=${stackLen} rev=${this.navUiRev}`)
  }

  /** Web 历史更新后延迟再刷一次按钮态（accessBackward 可能尚未就绪） */
  private scheduleRefreshNavActions(): void {
    this.refreshNavActions()
    setTimeout(() => this.refreshNavActions(), 80)
    setTimeout(() => this.refreshNavActions(), 300)
  }

  /** 是否应写入导航栈 / 更新地址栏（排除 about:blank 等） */
  private shouldTrackNavUrl(url: string): boolean {
    return BrowserUtils.isRecordableHistoryUrl(BrowserUtils.normalizeHistoryUrl(url.trim()))
  }

  /** 页内跳转 / 历史变化：更新地址栏并同步应用导航栈（不改 Web src） */
  private handleWebNavUrl(url: string): void {
    const loaded = url.trim()
    if (!this.shouldTrackNavUrl(loaded)) {
      return
    }
    this.currentUrl = loaded
    if (this.appNavPending) {
      this.tryCompleteAppNav(loaded)
      return
    }
    if (this.entrySessionPending) {
      return
    }
    BrowserStore.syncNavToUrl(loaded)
  }

  /** 从 Web 事件解析 URL 并同步导航栈（onPageEnd 可能不触发，progress/history 亦会调用） */
  private commitWebNavigation(eventUrl?: string): void {
    const url = this.resolvePageUrl(eventUrl)
    if (!this.shouldTrackNavUrl(url)) {
      return
    }
    BrowserLog.info(`[NavCommit] url=${url.slice(0, 100)}`)
    this.handleWebNavUrl(url)
  }

  private onRefreshOrStop(): void {
    if (this.isLoading || this.progress < 100) {
      this.webPage.stop()
      this.isLoading = false
      this.progress = 100
    } else {
      this.webRefreshPending = true
      this.webPage.refresh()
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_refreshing')))
    }
  }

  /** 关闭网页长按上下文菜单并重置状态（含 Web 内核原生菜单） */
  private closeWebContextMenu(): void {
    const pendingResult = this.webCtxResult
    this.webVm.closeWebContextMenu()
    this.webCtxResult = null
    this.dismissNativeWebContextMenu(pendingResult)
  }

  /** 关闭 Web 内核原生上下文菜单（避免盖住自定义菜单） */
  private dismissNativeWebContextMenu(result: WebContextMenuResult | null = this.webCtxResult): void {
    try {
      result?.closeContextMenu()
    } catch (_err) {
      // 忽略重复关闭
    }
  }

  /** 打开图片长按菜单 */
  private openImageContextMenu(imageUrl: string, result: WebContextMenuResult): void {
    const src = imageUrl.trim()
    if (!src) {
      return
    }
    this.webVm.openImageContextMenu(src, ['copy_image', 'save_image', 'share_image'])
    this.webCtxResult = result
    BrowserLog.info(`[BrowsePage] image context menu url=${src.slice(0, 80)}`)
  }

  /** 打开链接长按菜单（event.param 坐标为 Web 组件内 px，须叠加 Web 全局偏移） */
  private openLinkContextMenu(linkUrl: string, xPx: number, yPx: number, result: WebContextMenuResult): void {
    const uiCtx = this.getUIContext()
    const localX = uiCtx.px2vp(xPx)
    const localY = uiCtx.px2vp(yPx)
    const anchorX = localX + this.webViewGlobalX
    const anchorY = localY + this.webViewGlobalY
    this.webVm.openLinkContextMenu(linkUrl, anchorX, anchorY)
    this.webCtxResult = result
    BrowserWindowService.getInstance().ensureWindowSizeSynced()
    const winSize = BrowserWindowService.getInstance().resolveWindowSizePx()
    const placement = BrowseLinkContextMenu.computePlacement(anchorX, anchorY, winSize.width, winSize.height)
    const vpWinW = winSize.width > 0 ? uiCtx.px2vp(winSize.width) : 0
    const vpWinH = winSize.height > 0 ? uiCtx.px2vp(winSize.height) : 0
    const menuRightX = placement.leftX + BrowseLinkContextMenu.MENU_WIDTH
    BrowserLog.info(`[BrowsePage] link menu px=(${xPx},${yPx}) local=(${localX.toFixed(1)},${localY.toFixed(1)}) ` +
      `webGlobal=(${this.webViewGlobalX.toFixed(1)},${this.webViewGlobalY.toFixed(1)}) ` +
      `anchor=(${anchorX.toFixed(1)},${anchorY.toFixed(1)}) vpWin=${vpWinW.toFixed(1)}x${vpWinH.toFixed(1)} ` +
      `menu=(${placement.leftX.toFixed(1)},${placement.topY.toFixed(1)}) right=${menuRightX.toFixed(1)} ` +
      `mode=${placement.mode} url=${linkUrl.slice(0, 50)}`)
  }

  /** 复制长按图片到剪贴板并关闭菜单 */
  private copyContextImageAndCloseMenu(): void {
    this.webVm.copyContextImage(this.currentUrl)
    this.closeWebContextMenu()
  }

  /** 字体档位变更：同步 Web textZoomRatio 并 JS 热更新当前页 */
  private onFontSettingsChanged(): void {
    const key = BrowserStrings.normalizeFontSizeKey(this.fontSizeKey)
    const zoom = BrowserStrings.computeWebTextZoomRatio(key, this.systemFontSizeScale)
    const revChanged = this.fontUiRev !== this.lastAppliedFontRev
    const keyChanged = key !== this.lastAppliedFontKey
    const zoomChanged = this.webTextZoom !== zoom
    if (!revChanged && !keyChanged && !zoomChanged) {
      return
    }
    this.forceApplyWebTextZoom('storageWatch', zoom, key, zoomChanged)
  }

  /**
   * Ability 回前台延迟 tick：多任务场景下 Web 此时通常已可见。
   * 仅当 native textZoom 仍落后于目标值时 remount（等同热启动路径）。
   */
  private onFontForegroundTick(): void {
    if (this.fontForegroundTick <= 0 || !this.browseWebActive) {
      return
    }
    const key = BrowserStrings.normalizeFontSizeKey(this.fontSizeKey)
    const zoom = BrowserStrings.computeWebTextZoomRatio(key, this.systemFontSizeScale)
    const needRemount = this.lastRemountedZoom !== zoom
    this.forceApplyWebTextZoom('foregroundTick', zoom, key, needRemount)
  }

  /**
   * 将当前字体档位应用到 Web。
   * textZoomRatio 热更新在 ArkWeb 上常不即时生效；多任务恢复时 onPageShow 也不一定回调。
   * remount=true 时按热启动路径重建 Web，保证原生缩放生效。
   */
  private forceApplyWebTextZoom(
    reason: string,
    zoomOverride?: number,
    keyOverride?: string,
    remount: boolean = false
  ): void {
    const key = keyOverride ?? BrowserStrings.normalizeFontSizeKey(this.fontSizeKey)
    const zoom = zoomOverride ?? BrowserStrings.computeWebTextZoomRatio(key, this.systemFontSizeScale)
    const zoomChanged = this.webTextZoom !== zoom
    const doRemount = remount || zoomChanged || this.lastRemountedZoom !== zoom
    this.webTextZoom = zoom
    this.lastAppliedFontRev = this.fontUiRev
    this.lastAppliedFontKey = key
    BrowserLog.info(`[Font] browse apply reason=${reason} key=${key} zoom=${zoom} rev=${this.fontUiRev} ` +
      `scale=${this.fontUiScale.toFixed(2)} zoomCh=${zoomChanged} remount=${doRemount} ` +
      `lastRemount=${this.lastRemountedZoom}`)
    if (doRemount) {
      const live = (this.webPage.getCurrentUrl() || this.currentUrl).trim()
      if (live.length > 0) {
        this.applyWebEntryForUrl(live)
      }
      this.webRenderKey++
      this.lastRemountedZoom = zoom
      BrowserLog.info(`[Font] remount web key=${this.webRenderKey} url=${live.slice(0, 80)}`)
    }
    this.scheduleWebTextZoomInject(zoom)
  }

  /** Web 可见后再注入；多档延迟兜底 Inactive 期间 runJS 失败 */
  private scheduleWebTextZoomInject(zoom: number): void {
    const delays: number[] = [0, 120, 450]
    for (let i = 0; i < delays.length; i++) {
      const delay = delays[i]
      setTimeout((): void => {
        if (!this.browseWebActive) {
          return
        }
        this.webPage.applyTextZoomRatio(zoom)
      }, delay)
    }
  }

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  private bookmarkStarColor(): string {
    return BOOKMARK_STAR_COLOR
  }

  private toggleBookmark(): void {
    if (this.webVm.isCurrentPageBookmarked(this.currentUrl, this.bookmarks)) {
      void BrowserStore.removePageBookmark(this.currentUrl)
      return
    }
    this.addBookmarkDefaultTitle = this.pageTitle.trim() || tabHostname(this.currentUrl)
    this.showAddBookmarkDialog = true
  }

  private confirmAddBookmark(name: string, parentId: string = ''): void {
    this.showAddBookmarkDialog = false
    void BrowserStore.addPageBookmark(name, this.currentUrl, parentId)
  }

  /** 进入地址栏编辑（不在此处递增 focusKey，避免 TextInput 被 key 重建） */
  private openBrowseUrlEdit(): void {
    const clamped = BrowserNavigation.clampAddressInput(this.currentUrl)
    this.urlEditInputText = clamped.text
    this.urlEditActive = true
    this.webVm.showUrlEdit = true
    this.webVm = this.webVm
  }

  /** 子组件提交 */
  private onUrlEditSubmit(text: string): void {
    this.submitUrlEdit(text)
  }

  /** 子组件建议项跳转 */
  private onUrlEditNavigate(url: string): void {
    const check = BrowserNavigation.validateUrlInput(url)
    if (!check.ok || !check.url) {
      BrowserStore.showToast(check.message ?? BrowserStrings.urlFormatInvalid())
      return
    }
    this.closeUrlEditSession()
    this.currentUrl = check.url
    this.pageTitle = tabHostname(check.url)
    BrowserStore.pushNavStack(check.url)
    this.webPage.loadUrl(check.url)
    this.syncTabMeta(this.pageTitle, check.url)
  }

  private closeUrlEditSession(): void {
    this.webVm.closeUrlEdit()
    this.urlEditActive = false
    this.urlEditInputText = ''
  }

  /** 点击地址栏外区域：取消编辑并关闭输入法 */
  private cancelBrowseUrlEdit(): void {
    if (!this.urlEditActive) {
      return
    }
    this.closeUrlEditSession()
  }

  /** 切换无痕模式：先关面板并提示，后台迁移标签与截图 */
  private toggleIncognitoMode(): void {
    this.webVm.closeMoreSheet()
    const tabId = this.browseTabId
    const title = this.pageTitle
    const url = this.currentUrl
    const next = !BrowserStore.isIncognito()
    if (next) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.incognito_enabled')))
    }
    if (tabId) {
      BrowserStore.scheduleBackgroundTabThumbnail(tabId, 'web')
    }
    void BrowserStore.toggleIncognitoForBrowseTab(tabId, title, url).then((newTabId) => {
      this.browseTabId = newTabId
      BrowserStore.recordBrowseIncognito(BrowserStore.isIncognito())
    })
  }

  /** 地址栏编辑提交：URL 直开，否则走搜索引擎 */
  private submitUrlEdit(text: string): void {
    const q = BrowserNavigation.normalizeNavigateInput(text)
    if (!q) {
      this.closeUrlEditSession()
      return
    }
    const isUrl = /^(https?:\/\/|www\.)/i.test(q) ||
      /^[\w.-]+\.(com|cn|net|org|io|gov|edu)/i.test(q)
    if (isUrl) {
      const check = BrowserNavigation.validateUrlInput(q)
      if (!check.ok || !check.url) {
        BrowserStore.showToast(check.message ?? BrowserStrings.urlFormatInvalid())
        return
      }
      this.closeUrlEditSession()
      this.currentUrl = check.url
      this.pageTitle = tabHostname(check.url)
      BrowserStore.pushNavStack(check.url)
      this.webPage.loadUrl(check.url)
      this.syncTabMeta(this.pageTitle, check.url)
      return
    }
    const searchUrl = BrowserNavigation.getSearchEngineUrl(q)
    this.closeUrlEditSession()
    BrowserStore.addSearchHistory(q)
    this.currentUrl = searchUrl
    this.pageTitle = tabHostname(searchUrl)
    BrowserStore.pushNavStack(searchUrl)
    this.webPage.loadUrl(searchUrl)
    this.syncTabMeta(this.pageTitle, searchUrl)
  }

  /** 解析当前页 URL：优先事件回调，其次 WebviewController（忽略 about:blank） */
  private resolvePageUrl(eventUrl?: string): string {
    const fromEvent = (eventUrl ?? '').trim()
    if (fromEvent.length > 0 && this.shouldTrackNavUrl(fromEvent)) {
      return fromEvent
    }
    const fromWeb = this.webPage.getCurrentUrl().trim()
    if (fromWeb.length > 0 && this.shouldTrackNavUrl(fromWeb)) {
      return fromWeb
    }
    return this.currentUrl.trim()
  }

  /** 写入浏览历史；同一次导航内重复调用仅更新标题 */
  private recordPageHistory(url: string, title?: string): void {
    const resolved = BrowserUtils.normalizeHistoryUrl(url)
    if (!BrowserUtils.isRecordableHistoryUrl(resolved)) {
      BrowserLog.warn(`[History] skip invalid url=${resolved}`)
      return
    }
    this.currentUrl = resolved
    const pageTitle = (title ?? this.pageTitle).trim() || tabHostname(resolved)
    if (this.historyCommittedForNavigation && resolved === this.lastCommittedHistoryUrl) {
      void BrowserStore.updateHistoryTitle(resolved, pageTitle)
      return
    }
    this.historyCommittedForNavigation = true
    this.lastCommittedHistoryUrl = resolved
    void BrowserStore.addHistoryEntry(pageTitle, resolved)
  }

  /** 将 Web favicon 写入历史记录（本地缓存 + DB） */
  private persistHistoryFavicon(pageUrl: string, favicon: image.PixelMap): void {
    const resolved = BrowserUtils.normalizeHistoryUrl(pageUrl)
    if (!BrowserUtils.isRecordableHistoryUrl(resolved)) {
      return
    }
    void HistorySiteIconService.getInstance().saveFavicon(resolved, favicon).then((path) => {
      if (path) {
        void BrowserStore.updateHistoryIcon(resolved, path)
      }
    })
  }

  /** 页面加载完成后尝试从 WebView 读取 favicon */
  private tryPersistHistoryFaviconFromController(pageUrl: string): void {
    try {
      const favicon = this.webController.getFavicon()
      if (favicon) {
        this.persistHistoryFavicon(pageUrl, favicon)
      }
    } catch (err) {
      BrowserLog.warn(`[HistoryIcon] getFavicon failed: ${JSON.stringify(err)}`)
    }
  }

  /** 页面加载完成后：图片直链进全屏预览，普通页面注入图片点击钩子 */
  private onWebPageLoaded(loadedUrl: string): void {
    if (BrowserUtils.isImageUrl(loadedUrl)) {
      BrowserStore.openImagePreview(loadedUrl)
      return
    }
    this.webPage.ensureViewportMeta()
    this.webPage.installImageInteractionHooks()
    this.webPage.installLinkDragBlock()
  }

  /** 离开页面前补写尚未记录的历史 */
  private flushBrowseHistoryIfNeeded(): void {
    if (this.historyCommittedForNavigation) {
      return
    }
    this.recordPageHistory(this.resolvePageUrl())
  }

  private applyWebEntryForUrl(resolvedUrl: string): void {
    this.webEntryUrl = resolvedUrl
  }

  /** 控制器就绪后加载入口 URL */
  private scheduleInitialWebLoad(uaUpdated: boolean): void {
    const target = this.currentUrl.trim()
    if (uaUpdated) {
      this.webPage.loadUrl(target)
    } else {
      this.ensureWebLoad(target)
    }
  }

  /** 控制器就绪后补载 URL（src 已绑定时跳过，避免重复 loadUrl） */
  private ensureWebLoad(url: string): void {
    const target = url.trim()
    if (target.length === 0) {
      return
    }
    try {
      const loaded = this.webController.getUrl().trim()
      if (loaded.length > 0 && loaded === target) {
        return
      }
      BrowserLog.info(`[WebLoad] loadUrl target=${target} current=${loaded}`)
      this.webPage.loadUrl(target)
    } catch (_err) {
      BrowserLog.info(`[WebLoad] loadUrl fallback target=${target}`)
      this.webPage.loadUrl(target)
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.browsePageBg())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Column() {
          if (this.webVm.showFindBar && !this.webMediaFullscreen) {
            Row({ space: 6 }) {
              TextInput({ text: this.webVm.findText, placeholder: $r('app.string.find_in_page_placeholder') })
                .fontSize(this.uiFp(14))
                .layoutWeight(1)
                .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
                .onChange((v: string) => {
                  BrowserNavigation.applyTextInputChange(v, this.webVm.findText.length, (text: string) => {
                    this.webVm.findText = text
                    this.webVm.runFindInPage(text, this.webPage)
                  })
                })
                .onSubmit(() => this.webVm.stepFindMatch(true, this.webPage))
              Text(this.webVm.findDisplay())
                .fontSize(this.uiFp(13))
                .fontColor(this.browseTextMuted())
                .width(40)
                .textAlign(TextAlign.Center)
              this.FindBarBtn('↑', () => this.webVm.stepFindMatch(false, this.webPage))
              this.FindBarBtn('↓', () => this.webVm.stepFindMatch(true, this.webPage))
              this.FindBarBtn('×', () => this.webVm.closeFindBar(this.webPage))
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.browsePanelBg())
            .onClick(() => {
              if (this.urlEditActive) {
                this.cancelBrowseUrlEdit()
              }
            })
          }

          Column() {
            BrowseAddressBar({
              isEditing: this.urlEditActive,
              displayText: this.addressBarDisplayText(),
              textColor: this.addressBarTextColor(),
              placeholderColor: this.addressBarMutedColor(),
              pillBorderColor: this.moreDividerColor(),
              pillBgColor: this.addressBarBg(),
              refreshColor: this.addressBarRefreshColor(),
              refreshLabel: '↻',
              showStopIcon: this.isLoading || this.progress < 100,
              bookmarked: this.webVm.isCurrentPageBookmarked(this.currentUrl, this.bookmarks),
              bookmarkColor: this.addressBarBookmarkColor(),
              bookmarks: this.bookmarks,
              historyList: this.historyList,
              isIncognito: this.isIncognito,
              onStartEdit: (): void => {
                this.openBrowseUrlEdit()
              },
              onSubmit: (text: string): void => {
                this.onUrlEditSubmit(text)
              },
              onNavigate: (url: string): void => {
                this.onUrlEditNavigate(url)
              },
              onRefresh: (): void => {
                this.onRefreshOrStop()
              },
              onBookmark: (): void => {
                this.toggleBookmark()
              },
              onCopyUrl: (): void => {
                this.webVm.copyPageUrl(this.currentUrl)
              },
              onViewAllDownloads: (): void => {
                BrowserStore.openFeaturePanel('downloads')
              }
            })
          }
          .width('100%')
          .backgroundColor(this.browsePanelBg())

          if (this.progress < 100 && !this.webMediaFullscreen) {
            Row() {
              Row()
                .width(`${this.progress}%`)
                .height(2)
                .backgroundColor(this.browsePrimary())
            }
            .width('100%')
            .height(2)
            .justifyContent(FlexAlign.Start)
            .onClick(() => {
              if (this.urlEditActive) {
                this.cancelBrowseUrlEdit()
              }
            })
          }
        }
        .width('100%')
        .backgroundColor(this.browsePanelBg())
        .border({ width: { bottom: 1 }, color: this.moreDividerColor() })
        .key(`browse-chrome-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}`)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .padding({ top: this.webMediaFullscreen ? 0 : this.safeAreaTop })
        .visibility(this.webMediaFullscreen ? Visibility.None : Visibility.Visible)

        Stack() {
          Web({ src: this.webEntryUrl, controller: this.webController, incognitoMode: this.isIncognito })
            .id(TabThumbnailService.WEB_SNAPSHOT_ID)
            .key(`browse-web-${this.webRenderKey}`)
            .enableAutoFill(!this.isIncognito)
            .cacheMode(this.isIncognito ? CacheMode.Online : CacheMode.Default)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .geolocationAccess(true)
            .imageAccess(!this.imageLessMode)
            .fileAccess(true)
            .onlineImageAccess(!this.imageLessMode)
            .metaViewport(true)
            .overviewModeAccess(true)
            .javaScriptOnDocumentStart(this.micGumScripts)
            .editMenuOptions(WebTextMenuHelper.buildEditMenuOptions())
            .zoomAccess(true)
            .pinchSmooth(true)
            .darkMode(this.isBrowseDark() ? WebDarkMode.On : WebDarkMode.Off)
            .forceDarkAccess(this.isBrowseDark())
            .textZoomRatio(this.webTextZoom)
            .enableFollowSystemFontWeight(true)
            .javaScriptProxy({
              object: this.webJsBridge,
              name: 'BrowserBridge',
              methodList: ['openImagePreview', 'startNativeMic', 'stopNativeMic', 'getNativeMicState', 'pullMicPcm'],
              controller: this.webController
            })
            .layoutWeight(1)
            .width('100%')
            .height('100%')
            .hitTestBehavior(this.webVm.showUrlEdit ? HitTestMode.None : HitTestMode.Default)
            .backgroundColor(this.isBrowseDark() ? BrowserTheme.DARK_BG : '#FFFFFF')
            .onControllerAttached(() => {
              WebDownloadService.getInstance().attachController(this.webController)
              this.webPage.ensureErrorPageEnabled()
              BrowserLog.info(`[Incognito] web incognito=${this.isIncognito} autoFill=${!this.isIncognito}`)
              const uaUpdated = this.webPage.ensureMobileUserAgent()
              this.scheduleInitialWebLoad(uaUpdated)
              this.refreshNavActions()
            })
            .onSearchResultReceive((event) => {
              if (!event) {
                return
              }
              this.webVm.applySearchResult(
                event.activeMatchOrdinal,
                event.numberOfMatches,
                event.isDoneCounting
              )
            })
            .onLoadIntercept((event) => {
              const reqUrl = event?.data?.getRequestUrl?.() ?? ''
              if (BrowserUtils.isExternalAppScheme(reqUrl)) {
                BrowserLog.info(`[NavIntercept] block external scheme url=${reqUrl.slice(0, 120)}`)
                return true
              }
              return false
            })
            .onOverrideErrorPage((event) => {
              const reqUrl = event.request?.getRequestUrl?.() ?? this.currentUrl
              const code = event.error?.getErrorCode?.() ?? 0
              BrowserLog.warn(`[WebError] code=${code} url=${reqUrl.slice(0, 120)}`)
              if (WebErrorPageHelper.isOfflineLoadError(code)) {
                const targetUrl = reqUrl.trim().length > 0 ? reqUrl : this.currentUrl
                WebLoadNetworkRetryService.getInstance().cancelPageEndClear()
                WebLoadNetworkRetryService.getInstance().scheduleReloadOnNetworkRestore(targetUrl, (): void => {
                  if (!this.browseWebActive) {
                    return
                  }
                  this.isLoading = true
                  this.progress = 0
                  this.currentUrl = targetUrl
                  this.webPage.loadUrl(targetUrl)
                  this.refreshNavActions()
                })
              }
              return WebErrorPageHelper.buildOverrideHtml(reqUrl, code, this.isBrowseDark())
            })
            .onPermissionRequest((event) => {
              if (!event || !event.request) {
                BrowserLog.warn('[WebPerm] onPermissionRequest missing event/request')
                return
              }
              // 必须通过 event.request 对象调用方法以保留 native this。
              // 切勿把 getOrigin/grant/deny 拆成无绑定函数，否则会 SIGSEGV
              // （JSWebPermissionRequest::GetOrigin +0x28 / null this）。
              // grant/deny 延后到下一事件循环，避开同步 Prompt 链路竞态。
              const req = asPermissionRequest(event.request as object)
              if (req === null) {
                BrowserLog.warn('[WebPerm] onPermissionRequest: invalid request adapter')
                return
              }
              let reqOrigin = ''
              let resources: string[] = []
              try {
                reqOrigin = (req.getOrigin() ?? '').trim()
                resources = req.getAccessibleResource() ?? []
              } catch (readErr) {
                BrowserLog.warn(`[WebPerm] read request failed: ${JSON.stringify(readErr)}`)
                return
              }
              const policyOrigin = WebPermissionGate.normalizeWebOrigin(
                reqOrigin.length > 0 ? reqOrigin : WebPermissionGate.extractOriginFromUrl(this.currentUrl))
              const grantResources: string[] = resources.slice()
              BrowserLog.info(
                `[WebPerm] onPermissionRequest origin=${policyOrigin.slice(0, 80)} res=${JSON.stringify(grantResources)}`)
              setTimeout((): void => {
                void WebPermissionGate.getInstance().handlePermissionRequest(
                  policyOrigin,
                  grantResources,
                  (): void => {
                    try {
                      req.grant(grantResources)
                      BrowserLog.info(`[WebPerm] granted origin=${policyOrigin.slice(0, 80)} res=${JSON.stringify(grantResources)}`)
                    } catch (grantErr) {
                      BrowserLog.warn(`[WebPerm] grant failed: ${JSON.stringify(grantErr)}`)
                    }
                  },
                  (): void => {
                    try {
                      req.deny()
                      BrowserLog.info(`[WebPerm] denied origin=${policyOrigin.slice(0, 80)}`)
                    } catch (denyErr) {
                      BrowserLog.warn(`[WebPerm] deny failed: ${JSON.stringify(denyErr)}`)
                    }
                  })
              }, 0)
            })
            .onGeolocationShow((event) => {
              if (!event) {
                return
              }
              const reqOrigin = (event.origin ?? '').trim()
              const policyOrigin = WebPermissionGate.normalizeWebOrigin(
                reqOrigin.length > 0 ? reqOrigin : WebPermissionGate.extractOriginFromUrl(this.currentUrl))
              const globalPolicy = BrowserStore.getSitePermission('location')
              const originPolicy = WebPermissionGate.getInstance().getOriginPermission(policyOrigin, 'location')
              const siteAllowed = WebPermissionGate.isSiteLocationAllowed(policyOrigin)
              const appGranted = BrowserStore.isAppPermissionGranted('location')
              BrowserLog.info(`[Location] onGeolocationShow origin=${policyOrigin.slice(0, 80)} global=${globalPolicy} originPol=${originPolicy ?? 'null'} siteAllowed=${siteAllowed} appGranted=${appGranted}`)
              LocationWarmupService.handleWebGeolocationShow(
                policyOrigin,
                siteAllowed,
                appGranted,
                this.isIncognito)
            })
            .onProgressChange((event) => {
              if (event) {
                if (!this.webVm.showUrlEdit) {
                  this.progress = event.newProgress
                  this.isLoading = event.newProgress < 100
                }
                if (event.newProgress >= 100) {
                  if (!this.webRefreshPending) {
                    this.commitWebNavigation()
                  }
                  this.finalizeWebRefreshIfNeeded()
                  this.scheduleRefreshNavActions()
                  if (!this.historyCommittedForNavigation) {
                    this.recordPageHistory(this.resolvePageUrl())
                  }
                }
              }
            })
            .onPageBegin((event) => {
              // 跨页导航时停掉上一页的原生麦克风旁路，避免采集器泄漏
              WebMicCaptureService.getInstance().stop()
              if (!this.webVm.showUrlEdit) {
                this.isLoading = true
                this.progress = 5
              }
              this.screenPaintReady = false
              this.historyCommittedForNavigation = false
              this.lastCommittedHistoryUrl = ''
              this.webMediaFullscreen = false
              if (this.imagePreviewVisible) {
                BrowserStore.closeImagePreview()
              }
              const beginUrl = (event?.url ?? '').trim()
              // 仅对 http(s) 页面写入位置策略；store:// 等外部 scheme 不应触发
              if (beginUrl.length > 0 && BrowserUtils.isWebViewLoadableUrl(beginUrl)) {
                const origin = WebPermissionGate.extractOriginFromUrl(beginUrl)
                if (origin.length > 0) {
                  const deferAllow = !LocationWarmupService.isWarmupReady()
                  WebPermissionGate.getInstance().applyLocationPolicyToOrigin(
                    origin, this.getUIContext(), this.isIncognito, deferAllow)
                }
              }
              if (beginUrl.length > 0) {
                BrowserLog.info(`[NavBegin] url=${beginUrl.slice(0, 100)}`)
              }
            })
            .onPageEnd((event) => {
              if (!this.webVm.showUrlEdit) {
                this.isLoading = false
                this.progress = 100
              }
              const loadedUrl = this.resolvePageUrl(event?.url)
              BrowserLog.info(`[NavEnd] eventUrl=${(event?.url ?? '').slice(0, 100)} resolved=${loadedUrl.slice(0, 100)}`)
              if (loadedUrl) {
                WebLoadNetworkRetryService.getInstance().notifyPageEndForRetry(loadedUrl)
              }
              if (loadedUrl) {
                this.commitWebNavigation(loadedUrl)
              }
              this.finalizeWebRefreshIfNeeded()
              this.scheduleEntrySessionFinalize(loadedUrl)
              this.syncTabMeta(this.pageTitle, this.currentUrl)
              this.recordPageHistory(loadedUrl)
              this.tryPersistHistoryFaviconFromController(loadedUrl)
              this.onWebPageLoaded(loadedUrl)
              this.scheduleRefreshNavActions()
            })
            .onRefreshAccessedHistory((event) => {
              if (event?.isMainFrame === false) {
                return
              }
              const historyUrl = (event?.url ?? '').trim()
              const refreshed = event?.isRefreshed === true
              BrowserLog.info(`[NavHistory] url=${historyUrl.slice(0, 100)} refreshed=${refreshed}`)
              if (refreshed) {
                this.webRefreshPending = true
                this.scheduleRefreshNavActions()
                return
              }
              if (historyUrl.length > 0) {
                this.commitWebNavigation(historyUrl)
              }
              this.scheduleRefreshNavActions()
            })
            .onFirstScreenPaint(() => {
              this.screenPaintReady = true
              this.notifyThumbRetryReady()
              this.webPage.applyTextZoomRatio(this.webTextZoom)
              void this.captureMissingThumbnailAfterPaint()
            })
            .onTitleReceive((event) => {
              if (event && event.title && BrowserUtils.isValidPageTitle(event.title)) {
                this.pageTitle = event.title
                this.syncTabMeta(event.title)
                const url = this.resolvePageUrl()
                if (this.historyCommittedForNavigation) {
                  void BrowserStore.updateHistoryTitle(url, event.title)
                } else if (BrowserUtils.isRecordableHistoryUrl(url)) {
                  this.recordPageHistory(url, event.title)
                }
              }
            })
            .onFaviconReceived((event) => {
              const favicon = event?.favicon
              if (!favicon) {
                return
              }
              this.persistHistoryFavicon(this.resolvePageUrl(), favicon)
            })
            .onSslErrorEvent((event: SslErrorEvent) => {
              this.onWebSslError(event)
            })
            .onContextMenuShow((event) => {
              if (!event) {
                return false
              }
              try {
                const mediaType = event.param.getMediaType()
                const dataMediaType = event.param.getContextMenuMediaType()
                // 视频/音频长按交给 H5/内核默认控件
                if (dataMediaType === ContextMenuDataMediaType.VIDEO ||
                  dataMediaType === ContextMenuDataMediaType.AUDIO) {
                  return false
                }
                if (mediaType === ContextMenuMediaType.Image) {
                  const src = event.param.getSourceUrl().trim()
                  if (this.webVm.showWebCtx) {
                    if (!this.webCtxResult) {
                      this.webCtxResult = event.result
                    }
                    return true
                  }
                  if (src.length > 0) {
                    this.openImageContextMenu(src, event.result)
                  }
                  return true
                }
                if (this.webVm.isWebContextMenuVisible()) {
                  return true
                }
                const linkUrl = event.param.getLinkUrl().trim()
                if (linkUrl.length > 0) {
                  this.openLinkContextMenu(linkUrl, event.param.x(), event.param.y(), event.result)
                  return true
                }
                return false
              } catch (err) {
                BrowserLog.warn(`onContextMenuShow failed: ${JSON.stringify(err)}`)
                return false
              }
            })
            .onFullScreenEnter((event: FullScreenEnterEvent) => {
              this.webMediaFullscreen = true
              BrowserLog.info('[WebVideo] onFullScreenEnter')
            })
            .onFullScreenExit(() => {
              this.webMediaFullscreen = false
              BrowserLog.info('[WebVideo] onFullScreenExit')
            })

          if (this.webVm.showUrlEdit) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              .zIndex(100)
              .onClick((): void => {
                this.cancelBrowseUrlEdit()
              })
          }

        }
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((_old, area) => {
          const g = area.globalPosition
          if (g) {
            this.webViewGlobalX = g.x as number
            this.webViewGlobalY = g.y as number
          }
        })

        Column() {
          Stack() {
            Row() {
              this.ToolBtn('back', () => this.goBack())
              this.ToolBtn('forward', () => this.goForward())
              this.ToolBtn('home', () => BrowserNavigation.goHome())
              this.ToolBtn('tabs', () => {
                this.openTabsWithThumbnail()
              })
              this.ToolBtn('more', () => {
                this.webVm.openMoreSheet()
              })
            }
            .width('100%')
            .height(BrowserSafeAreaInsets.BROWSE_TOOLBAR_HEIGHT)
            .alignItems(VerticalAlign.Center)

            if (this.urlEditActive) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.cancelBrowseUrlEdit()
                })
            }
          }
          .width('100%')
          .height(BrowserSafeAreaInsets.BROWSE_TOOLBAR_HEIGHT)
        }
        .key(`browse-nav-${this.navUiRev}-${this.windowRev}-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}-${this.downloadsRev}`)
        .width('100%')
        .padding({ bottom: BrowserSafeAreaInsets.bottom(10) })
        .backgroundColor(this.browsePanelBg())
        .border({ width: { top: 1 }, color: this.moreDividerColor() })
        .visibility(this.webMediaFullscreen ? Visibility.None : Visibility.Visible)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.browsePageBg())
      .id('browse_page_content')
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          BrowserLog.info('[BrowsePage] content touch down')
        }
      })

      if (this.webVm.showMoreSheet) {
        this.MoreSheet()
      }

      if (this.featurePanel.length > 0) {
        FeaturePanel()
          .width('100%')
          .height('100%')
          .key(`browse-feature-panel-${this.fontUiRev}-${this.fontSizeKey}-${this.fontUiScale.toFixed(2)}`)
      }

      ToastBar()

      if (this.imagePreviewVisible) {
        WebImageLightbox()
      }

      // 非全屏预览场景下的下载确认（预览内由 WebImageLightbox 承载，避免被 zIndex 6000 遮挡）
      if (this.dlDialog.length > 0 && !this.imagePreviewVisible) {
        DownloadFlowDialog()
          .width('100%')
          .height('100%')
          .zIndex(6500)
      }

      // 非全屏预览场景下的分享（预览内分享由 WebImageLightbox 承载，避免 Image 合成层遮挡）
      if (this.shareVisible && !this.imagePreviewVisible) {
        ShareSheet()
          .width('100%')
          .height('100%')
          .zIndex(6500)
      }

      if (this.securityVm.showSslDialog) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.ssl_error_message')),
          subtitle: BrowserStrings.txt($r('app.string.ssl_error_title')),
          confirmLabel: BrowserStrings.txt($r('app.string.ssl_continue')),
          cancelLabel: BrowserStrings.txt($r('app.string.cancel')),
          onConfirm: () => {
            this.securityVm.allowSslProceed()
          },
          onCancel: () => {
            this.securityVm.cancelSsl()
          }
        })
      }

      if (this.showAddBookmarkDialog) {
        AddBookmarkDialog({
          visible: true,
          defaultTitle: this.addBookmarkDefaultTitle,
          halfModal: true,
          url: this.currentUrl,
          onCancel: (): void => {
            this.showAddBookmarkDialog = false
          },
          onConfirm: (name: string, parentId: string): void => {
            this.confirmAddBookmark(name, parentId)
          }
        })
      }

      DarkModePickerDialog({
        visible: this.showDarkModePicker,
        onClose: (): void => {
          this.showDarkModePicker = false
        }
      })

      if (this.webVm.showLinkCtx) {
        BrowseLinkContextMenu({
          visible: true,
          linkUrl: this.webVm.contextLinkUrl,
          anchorX: this.webVm.contextMenuX,
          anchorY: this.webVm.contextMenuY,
          onClose: (): void => {
            this.closeWebContextMenu()
          },
          onOpenInNewWindow: (): void => {
            this.webVm.openLinkInNewWindow()
          },
          onCopyLink: (): void => {
            this.webVm.copyContextLink()
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(6700)
      }
    }
    .width('100%')
    .height('100%')
    .bindContentCover(this.webVm.showWebCtx, this.WebContextCover(), {
      modalTransition: ModalTransition.NONE
    })
  }

  @Builder
  WebContextCover() {
    if (this.webVm.showWebCtx) {
      BrowseWebContextSheet({
        visible: true,
        actions: this.webVm.webCtxActions,
        onClose: (): void => {
          this.closeWebContextMenu()
        },
        onAction: (action: string): void => {
          if (action === 'copy_image') {
            this.copyContextImageAndCloseMenu()
            return
          }
          this.webVm.handleWebContextAction(action, this.currentUrl)
          this.closeWebContextMenu()
        }
      })
    }
  }

  @Builder
  FindBarBtn(label: string, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(this.uiFp(label === '×' ? 24 : 22))
        .fontWeight(BrowserTheme.uiFontWeight(label === '×' ? FontWeight.Medium : FontWeight.Regular))
        .fontColor(this.browseText())
    }
    .width(36)
    .height(36)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .justifyContent(FlexAlign.Center)
    .onClick(onTap)
  }

  /** 底部工具栏按钮是否禁用（须在 @Builder 内读取 @State，不可通过参数传入） */
  private toolBtnDisabled(action: string): boolean {
    const touch = this.navUiRev + this.navIdx
    if (action === 'back') {
      return touch >= 0 && !this.navCanGoBack
    }
    if (action === 'forward') {
      return touch >= 0 && !this.navCanGoForward
    }
    return false
  }

  private toolBtnIconColor(action: string): string {
    return this.toolBtnDisabled(action) ? this.browseTextMuted() : this.browseText()
  }

  private toolBtnIconSize(): number {
    return this.uiFp(BROWSE_TOOLBAR_ICON_BOX)
  }

  /**
   * 标签方框贴边绘制会显得比 Symbol/主页图标更大。
   * 外槽仍用 toolBtnIconSize，内绘缩小并居中，等效外边距约 11%。
   */
  private tabBadgeInnerSize(): number {
    return this.toolBtnIconSize() * 0.78
  }

  /** 主页实心图标同理，略留边使目测与返回/更多接近 */
  private homeIconInnerSize(): number {
    return this.toolBtnIconSize() * 0.82
  }

  private tabBadgeStroke(): number {
    return this.toolBtnIconSize() * (1.8 / BROWSE_TOOLBAR_ICON_BOX)
  }

  private tabBadgeFontSize(): number {
    return 12
  }

  private tabBadgeCornerRadius(): number {
    return this.uiFp(4.5)
  }

  /** 是否存在进行中的下载（running / queued） */
  private hasActiveDownloadTask(): boolean {
    const rev = this.downloadsRev
    if (rev < 0) {
      return false
    }
    return this.pickLatestActiveDownload() !== null
  }

  /** 最新进行中下载任务的进度（0–100） */
  private latestActiveDownloadProgress(): number {
    const _tick = this.downloadProgressRev
    if (_tick < 0) {
      return 0
    }
    const task = this.pickLatestActiveDownload()
    if (!task) {
      return 0
    }
    return Math.min(100, Math.max(0, task.progress))
  }

  /** 进行中任务是否为排队/尚未上报进度 */
  private latestActiveDownloadIndeterminate(): boolean {
    const task = this.pickLatestActiveDownload()
    if (!task) {
      return false
    }
    return task.status === 'queued' || task.progress <= 0
  }

  private pickLatestActiveDownload(): DownloadTask | null {
    let pick: DownloadTask | null = null
    for (let i = 0; i < this.downloads.length; i++) {
      const item = this.downloads[i]
      if (item.status !== 'running' && item.status !== 'queued') {
        continue
      }
      if (pick === null || item.updatedAt > pick.updatedAt) {
        pick = item
      }
    }
    return pick
  }

  @Builder
  ToolBtn(action: string, onTap: () => void) {
    Column() {
      if (action === 'tabs') {
        Column() {
          TabCountBadge({
            boxSize: this.tabBadgeInnerSize(),
            fontSize: this.tabBadgeFontSize(),
            frameStroke: this.tabBadgeStroke(),
            cornerRadius: this.tabBadgeCornerRadius(),
            useTotalCount: true
          })
        }
        .width(this.toolBtnIconSize())
        .height(this.toolBtnIconSize())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (action === 'back') {
        BrowseToolbarBackIcon({ color: this.toolBtnIconColor(action), boxSize: this.toolBtnIconSize() })
      } else if (action === 'forward') {
        BrowseToolbarForwardIcon({ color: this.toolBtnIconColor(action), boxSize: this.toolBtnIconSize() })
      } else if (action === 'home') {
        Column() {
          NavHomeIcon({ color: this.toolBtnIconColor(action), iconSize: this.homeIconInnerSize() })
        }
        .width(this.toolBtnIconSize())
        .height(this.toolBtnIconSize())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (action === 'more') {
        if (this.hasActiveDownloadTask()) {
          BrowseToolbarDownloadProgressIcon({
            boxSize: this.toolBtnIconSize(),
            progress: this.latestActiveDownloadProgress(),
            isDark: this.theme === 'dark',
            indeterminate: this.latestActiveDownloadIndeterminate(),
            variant: 'toolbar',
            iconColor: this.toolBtnIconColor('more')
          })
        } else {
          BrowseToolbarMoreIcon({ color: this.toolBtnIconColor(action), boxSize: this.toolBtnIconSize() })
        }
      } else {
        Text('⋯')
          .fontSize(this.uiFp(17))
          .fontColor(this.toolBtnIconColor(action))
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.toolBtnDisabled(action) ? 0.4 : 1)
    .enabled(!this.toolBtnDisabled(action))
    .onClick(() => {
      if (!this.toolBtnDisabled(action)) {
        BrowserLog.info(`[BrowsePage] toolbar tap action=${action}`)
        onTap()
      }
    })
  }

  /** 地址栏展示文案：优先显示当前网址，过长时由 TextOverflow 在末尾截断为 ... */
  private addressBarDisplayText(): string {
    const url = this.currentUrl.trim()
    if (url.length > 0) {
      return url
    }
    return this.pageTitle.trim()
  }

  /** 无痕：仅胶囊黑/深灰底；浅色用纯黑，深色用略亮深灰保可见度 */
  private addressBarBg(): string {
    if (this.isIncognito) {
      return this.isBrowseDark() ? BrowserTheme.INCOGNITO_ADDRESS_BG : BrowserTheme.INCOGNITO_NAV_BG
    }
    return this.theme === 'dark' ? 'rgba(255, 255, 255, 0.04)' : BrowserTheme.LIGHT_PANEL_BG
  }

  /** 无痕模式下地址输入框内文字色（白色） */
  private addressBarTextColor(): string {
    if (this.isIncognito) {
      return '#FFFFFF'
    }
    return this.browseText()
  }

  /** 无痕模式下地址输入框内次级文字/图标色（浅灰） */
  private addressBarMutedColor(): string {
    if (this.isIncognito) {
      return 'rgba(255, 255, 255, 0.7)'
    }
    return this.browseTextMuted()
  }

  /** 无痕模式下地址输入框内刷新/停止按钮色（浅灰） */
  private addressBarRefreshColor(): string {
    if (this.isIncognito) {
      return 'rgba(255, 255, 255, 0.7)'
    }
    return this.browseTextSecondary()
  }

  /** 地址栏右侧收藏星标色（星标在胶囊外面板背景上，无痕+浅色主题勿用纯白） */
  private addressBarBookmarkColor(): string {
    if (this.isIncognito && !this.isBrowseDark()) {
      return BOOKMARK_STAR_COLOR
    }
    if (this.isIncognito) {
      return '#FFFFFF'
    }
    return BOOKMARK_STAR_COLOR
  }

  private moreQuickContainerBg(): string {
    return this.theme === 'dark' ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'
  }

  private moreCloseBtnBg(): string {
    return this.theme === 'dark' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'
  }

  private moreDividerColor(): string {
    return this.theme === 'dark' ? BrowserTheme.DARK_BORDER : BrowserTheme.BORDER
  }

  @Builder
  MoreSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.webVm.closeMoreSheet()
        })

      Column() {
        Row() {
          Text($r('app.string.common_functions'))
            .fontSize(this.uiFp(18))
            .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Bold))
            .fontColor(this.browseText())
            .layoutWeight(1)

          Column() {
            Text('×')
              .fontSize(this.uiFp(20))
              .fontColor(this.browseTextSecondary())
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.moreCloseBtnBg())
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.webVm.closeMoreSheet()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 14 })

        // 顶部快捷入口：书签 / 历史 / 下载 / 无痕 / 深色（卡片外边距 16）
        Column() {
          Column() {
            Row() {
              this.MoreQuickItem('bookmarks', BrowserStrings.txt($r('app.string.shortcut_bookmarks')), () => {
                this.webVm.closeMoreSheet()
                BrowserStore.openFeaturePanel('bookmarks')
              })
              this.MoreQuickItem('history', BrowserStrings.txt($r('app.string.shortcut_history')), () => {
                this.webVm.closeMoreSheet()
                BrowserStore.openFeaturePanel('history')
              })
              this.MoreQuickItem('downloads', BrowserStrings.txt($r('app.string.shortcut_downloads')), () => {
                this.webVm.closeMoreSheet()
                BrowserStore.openFeaturePanel('downloads')
              })
              this.MoreQuickItem('incognito', BrowserStrings.txt($r('app.string.incognito_mode_title')), () => {
                void this.toggleIncognitoMode()
              })
              Column() {
                ServiceToggleItem({
                  serviceKind: 'dark',
                  label: BrowserStrings.txt($r('app.string.dark_mode')),
                  onTap: (): void => {
                    this.showDarkModePicker = true
                  }
                })
              }
              .layoutWeight(1)
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceEvenly)
          }
          .width('100%')
          .padding({ top: 12, bottom: 14 })
          .backgroundColor(this.moreQuickContainerBg())
          .borderRadius(14)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .key(`more-quick-${this.downloadsRev}`)

        // 列表入口：设计文档中的分享 / 页内搜索 / 设置 / 关于
        Column() {
          this.MoreListRow('share', BrowserStrings.txt($r('app.string.share_action')), () => {
            this.webVm.closeMoreSheet()
            this.webVm.openShare(this.pageTitle, this.currentUrl)
          })
          this.MoreListDivider()
          this.MoreListRow('find', BrowserStrings.txt($r('app.string.find_in_page')), () => {
            this.webVm.closeMoreSheet()
            this.webVm.showFindBar = true
          })
          this.MoreListDivider()
          this.MoreListRow('settings', BrowserStrings.txt($r('app.string.settings')), () => {
            this.webVm.closeMoreSheet()
            BrowserStore.openFeaturePanel('toolbox')
          })
          this.MoreListDivider()
          this.MoreListRow('about', BrowserStrings.txt($r('app.string.about_browser')), () => {
            this.webVm.closeMoreSheet()
            BrowserStore.openFeaturePanel('about')
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 28 })
      }
      .width('100%')
      .backgroundColor(this.browsePanelBg())
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
    .zIndex(1000)
  }

  @Builder
  MoreQuickItem(kind: string, label: string, onTap: () => void) {
    Column({ space: 8 }) {
      // 与「我的」管理入口三标签一致：强调色浅底，深浅色自动适配
      if (kind === 'bookmarks') {
        StatBookmarkIcon()
      } else if (kind === 'history') {
        StatHistoryIcon()
      } else if (kind === 'downloads') {
        if (this.hasActiveDownloadTask()) {
          Column() {
            BrowseToolbarDownloadProgressIcon({
              boxSize: 22,
              progress: this.latestActiveDownloadProgress(),
              isDark: this.theme === 'dark',
              indeterminate: this.latestActiveDownloadIndeterminate(),
              variant: 'accent'
            })
          }
          .width(36)
          .height(36)
          .backgroundColor(serviceTileBgDefault())
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
        } else {
          StatDownloadIcon()
        }
      } else {
        IncognitoServiceIcon({ iconSize: 22, showTile: true })
      }

      Text(label)
        .fontSize(this.uiFp(11))
        .fontColor(kind === 'incognito' ?
          serviceToggleLabelColor(this.isIncognito, this.theme === 'dark') : this.browseTextSecondary())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  MoreListDivider() {
    Divider()
      .color(this.moreDividerColor())
      .strokeWidth(1)
      .margin({ left: 56, right: 16 })
  }

  @Builder
  MoreListRow(kind: string, label: string, onTap: () => void) {
    Row() {
      Column() {
        if (kind === 'share') {
          ShareCircleIcon({ color: this.browseText(), iconSize: 20 })
        } else if (kind === 'find') {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(this.uiFp(18))
            .fontColor([this.browseText()])
            .fontWeight(FontWeight.Medium)
        } else if (kind === 'settings') {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(this.uiFp(18))
            .fontColor([this.browseText()])
            .fontWeight(FontWeight.Medium)
        } else {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(this.uiFp(18))
            .fontColor([this.browseText()])
            .fontWeight(FontWeight.Medium)
        }
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(this.uiFp(16))
        .fontColor(this.browseText())
        .layoutWeight(1)
        .margin({ left: 12 })

      NavChevronRight({ color: this.browseTextMuted(), iconSize: this.uiFp(18) })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onTap)
  }
}
