// BrowserPage：最小可用的单窗口浏览体验 + 新标签页 Homepage。

import webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { print } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TabBar, TabContextMenuPosition, TabFaviconPresentation } from '../components/TabBar';
import { NavigationBar } from '../components/NavigationBar';
import { AddressBar } from '../components/AddressBar';
import { ADDRESS_BAR_INPUT_ID } from '../components/AddressBar';
import { AddressSuggestionPanel } from '../components/AddressSuggestionPanel';
import { DownloadStatusButton } from '../components/DownloadStatusButton';
import { PermissionDialog } from '../components/PermissionDialog';
import { BrowserMenu, BrowserMenuItem, BrowserSubMenuState } from '../components/BrowserMenu';
import { BrowserContextMenu, BrowserContextMenuItem } from '../components/BrowserContextMenu';
import { BookmarkBar } from '../components/BookmarkBar';
import { BrowserHome } from './BrowserHome';
import { SettingsShellPage } from './SettingsShellPage';
import { BrowserErrorPage } from '../components/BrowserErrorPage';
import { BrowserPageViewModel, BrowserPageViewState } from '../viewmodels/BrowserPageViewModel';
import { JSBridgeFacade, JSBridgeFacadeOptions } from '../../runtime/jsBridgeFacade';
import { ScriptStore } from '../../runtime/scriptStore';
import {
  appLifecycleEvents,
  AppLifecyclePayload,
  memoryPressureEvents,
  MemoryPressurePayload,
  getCurrentMemoryPressureLevel,
} from '../../runtime/nativeEventBus';
import { JSBridgePolicyManager, JSBridgePolicy } from '../../runtime/jsBridgePolicyManager';
import { WebRuntime, WebViewManager } from '../../runtime/webViewManager';
import {
  TabMediaBridge,
  TAB_MEDIA_BRIDGE_NAME,
  TAB_MEDIA_MONITOR_SCRIPT,
  TAB_MEDIA_PLAYING_METHOD,
} from '../../runtime/tabMediaMonitor';
import { AppliedCookieSettings, AppliedWebSettings, WebSettingsAdapter } from '../../runtime/webSettingsAdapter';
import { AppRoute, AppRouter } from '../../core/appRouter';
import { DebugGate } from '../../core/debugGate';
import { BrowserSettings, SettingsManager } from '../../core/settingsManager';
import { BrowserShortcutAction, ShortcutManager } from '../../core/shortcutManager';
import { WindowManager } from '../../core/windowManager';
import { WindowTitleButtonRectInfo } from '../../integration/windowService';
import { Tab, TabId } from '../../core/types';
import { BookmarkItem, BookmarkManager, BookmarkTreeNode } from '../../core/bookmarkManager';
import { cloneFaviconPixelMap, encodeFaviconDataUri, normalizeFaviconCacheKey } from '../../core/faviconService';
import {
  extractUrlScheme,
  isExternalAppSchemeUrl,
  isSameHttpDocumentUrl,
  isSameHttpNavigationUrl,
} from '../../core/urlNormalizer';
import { PermissionManager, SITE_PERMISSION_PROMPT_ENABLED } from '../../core/permissionManager';
import {
  extractSiteOriginFromUrl,
  getSitePermissionMessage,
  getSitePermissionTitle,
  mapProtectedResourceToSitePermissionType,
  SitePermissionRequest,
  SitePermissionType,
} from '../../core/permissionTypes';
import { PermissionService } from '../../integration/permissionService';
import { ClipboardService } from '../../integration/clipboardService';
import { DownloadSettingsService } from '../../integration/downloadSettingsService';
import { AddressBarService } from '../../core/addressBarService';
import { AddressSuggestion } from '../../core/addressSuggestionTypes';
import { DownloadManager } from '../../core/downloadManager';
import {
  buildImageDownloadFileName,
  createIdleDownloadIndicatorSnapshot,
  DownloadIndicatorSnapshot,
  DownloadTask,
  extractFileNameFromContentDisposition,
  inferImageMimeType,
} from '../../core/downloadTypes';
import { PrivateSessionCoordinator } from '../../core/privateSessionCoordinator';
import { UaManager, UaMode } from '../../core/uaManager';
import {
  BrowserWebErrorKind,
  BrowserResponseHeader,
  BrowserWebErrorState,
  clearBrowserWebError,
  createBrowserWebError,
  findBrowserWebError,
  hasHttpResponseBody,
  isCurrentMainFrameNavigation,
  upsertBrowserWebError,
} from '../../core/browserWebError';
import {
  WebNavigationLifecycleState,
  acceptWebPageBegin,
  canCompleteWebNavigation,
  canFailWebNavigation,
  completeWebNavigation,
  createWebNavigationLifecycleState,
  enterWebNavigationHome,
  failWebNavigation,
  startWebNavigation,
  stopWebNavigation,
} from '../../core/webNavigationLifecycle';

const EMPTY_PERMISSION_REQUEST: SitePermissionRequest = {
  requestId: '',
  origin: '',
  permissionType: 'location',
  title: '站点权限请求',
  message: '',
  allowRememberChoice: true,
  rememberChoiceDefault: false,
  isSecureContext: true,
  requestedAt: 0,
};

const EMPTY_BROWSER_SUB_MENU_STATE: BrowserSubMenuState = {
  visible: false,
  items: [],
  activeItemId: '',
  anchorX: 0,
  anchorY: 0,
  menuWidth: 220,
};

const TAB_SEARCH_INPUT_ID: string = 'browser_tab_search_input';
const FAVICON_LOG_DOMAIN: number = 0x0000;
const FAVICON_LOG_TAG: string = 'FaviconTrace';
const NAVIGATION_LOG_TAG: string = 'NavigationTrace';
const WEB_DIALOG_LOG_TAG: string = 'WebDialogTrace';
const WEB_WINDOW_LOG_TAG: string = 'WebWindowTrace';
const DOWNLOAD_LOG_TAG: string = 'DownloadTrace';
const FAVICON_RELEASE_DELAY_MS: number = 100;
const NAVIGATION_STATE_SETTLE_MS: number = 500;
// App-side safety net for the tab media state. The in-page monitor pushes every
// change, so this sweep only exists to repair a missed or throttled report.
const MEDIA_STATE_PROBE_INTERVAL_MS: number = 2000;
interface ControllerNavigationState {
  canGoBack: boolean;
  canGoForward: boolean;
  hasHistorySnapshot: boolean;
  accessBackward: boolean;
  accessForward: boolean;
  accessBackwardKnown: boolean;
  accessForwardKnown: boolean;
  historyIndex: number;
  historySize: number;
  historyUrl: string;
}

type RuntimeFaviconSource = 'fallback' | 'callback';
type PendingNativeNavigation = 'back' | 'forward';
type JavaScriptDialogKind = 'alert' | 'confirm' | 'prompt' | 'beforeunload';

interface PendingJavaScriptDialog {
  tabId: string;
  runtimeRevision: number;
  kind: JavaScriptDialogKind;
  url: string;
  message: string;
  defaultValue: string;
  result: JsResult;
}

interface TabWebRuntimeState {
  runtimeRevision: number;
  navigationRevision: number;
  navigationUrl: string;
  controllerAttached: boolean;
  pendingUrl: string;
  requestedUrl: string;
  committedUrl: string;
  loadedUrl: string;
  lastError: string;
  navigationLifecycle: WebNavigationLifecycleState;
  updatedAt: number;
}

interface WebResourceErrorInfo {
  code: string;
  info: string;
}

interface ContextMenuCommandState {
  tabId: string;
  result: WebContextMenuResult;
  linkUrl: string;
  sourceUrl: string;
  selectionText: string;
}

interface ContextMenuResolution {
  items: BrowserContextMenuItem[];
  linkUrl: string;
  sourceUrl: string;
  selectionText: string;
}

interface ContextMenuPosition {
  x: number;
  y: number;
}

interface WebPointerPosition {
  x: number;
  y: number;
}

interface PendingSourceViewer {
  document: string;
  baseUrl: string;
  historyUrl: string;
}

interface BookmarkEditFolderOption {
  id: string;
  label: string;
}

@Component
export struct BrowserPage {
  private jsBridgeOptions: JSBridgeFacadeOptions = {
    enabled: false, // browser-grade JSBridge should be off by default
    autoExposeAliases: ['OHBridge'],
    overrideExistingGlobals: false,
  };

  private jsBridgePolicy: JSBridgePolicyManager = JSBridgePolicyManager.getInstance();
  private webViewManager: WebViewManager = new WebViewManager();
  private shortcutManager: ShortcutManager = new ShortcutManager();
  private windowManager: WindowManager = WindowManager.getInstance();
  private viewModel: BrowserPageViewModel = new BrowserPageViewModel();
  private debugGate: DebugGate = DebugGate.getInstance();
  private bookmarkManager: BookmarkManager = BookmarkManager.getInstance();
  private permissionManager: PermissionManager = PermissionManager.getInstance();
  private permissionService: PermissionService = new PermissionService();
  private clipboardService: ClipboardService = new ClipboardService();
  private addressBarService: AddressBarService = new AddressBarService();
  private downloadManager: DownloadManager = DownloadManager.getInstance();
  private downloadSettingsService: DownloadSettingsService = new DownloadSettingsService();
  // Star's bottom-right corner in window vp coordinates (from onAreaChange).
  private starAnchorRight: number = 0;
  private starAnchorBottom: number = 0;
  private privateSessionCoordinator: PrivateSessionCoordinator = PrivateSessionCoordinator.getInstance();
  private privateSessionOwnerId: string = this.privateSessionCoordinator.createOwnerId('browser-page');
  private privateSessionOwnerActive: boolean = false;
  private webSettingsAdapter: WebSettingsAdapter = new WebSettingsAdapter();
  private uaManager: UaManager = new UaManager();
  private addressSuggestionRequestId: number = 0;
  private webRuntimeStateByTabId: Map<string, TabWebRuntimeState> = new Map();
  // ArkWeb updates its back/forward list slightly after PageEnd. During this
  // short settling window, a native snapshot may still describe the previous
  // document and must not clear an app-confirmed navigation direction.
  private navigationStateSettlingUntilByTabId: Map<string, number> = new Map();
  private pendingNativeNavigationByTabId: Map<string, PendingNativeNavigation> = new Map();
  // Monotonic command tokens prevent an old timeout from clearing a newer
  // back/forward request on the same tab.
  private nativeNavigationCommandSequenceByTabId: Map<string, number> = new Map();
  private nativeNavigationCommandTokenByTabId: Map<string, number> = new Map();
  // A navigation command belongs to the WebView runtime that accepted it.
  // Runtime recreation (UA switch, detach/re-attach, renderer recovery) must
  // invalidate the command instead of blocking the new controller.
  private nativeNavigationCommandRuntimeRevisionByTabId: Map<string, number> = new Map();
  private nativeNavigationInitialUrlByTabId: Map<string, string> = new Map();
  private nativeNavigationTargetUrlByTabId: Map<string, string> = new Map();
  // “清除浏览数据”触发的标签页自动刷新不应把 URL 重新写回历史库，否则刚清空的
  // 历史会被刷新动作当场重建。清理信号到来时登记，recordTabPageHistory 消费一次
  // 即跳过。值为 string 化的 tabId，与上方 per-tab Map 的键保持一致。
  private skipNextHistoryRecordTabIds: Set<string> = new Set();
  private runtimeFaviconRevision: number = 0;
  // Encoded favicon data is kept per tab so bookmark creation can use the
  // real icon even when the asynchronous image encoding has completed first.
  private faviconDataUriByTabId: Map<string, string> = new Map();
  // The encoded image is shared by URL only. PixelMaps remain per-tab because
  // ArkWeb/ArkUI can release or recycle a PixelMap independently.
  private faviconDataUriByUrl: Map<string, string> = new Map();
  private faviconGenerationByTabId: Map<string, number> = new Map();
  // An explicit navigation starts favicon invalidation before ArkWeb emits
  // PAGE_BEGIN. Track that hand-off so one document gets one generation.
  private faviconGenerationExpectedUrlByTabId: Map<string, string> = new Map();
  private faviconGenerationAwaitingPageBeginByTabId: Map<string, boolean> = new Map();
  // The Web callback can deliver a favicon before onPageBegin. Record the
  // navigation it belongs to so PageBegin does not clear a valid new icon.
  private runtimeFaviconUrlByTabId: Map<string, string> = new Map();
  // Keep the source explicit. A fallback PixelMap is provisional and must be
  // replaceable by ArkWeb's later callback for the same navigation.
  private runtimeFaviconSourceByTabId: Map<string, RuntimeFaviconSource> = new Map();
  // Keep the copied PixelMap available as a tab-bar fallback for the lifetime
  // of its document. Retain its navigation while the PNG round-trip is in
  // flight so an early favicon callback is not discarded by PageBegin.
  private pendingFaviconUrlByTabId: Map<string, string> = new Map();
  // A single navigation can emit several favicon callbacks. Keep only the
  // newest asynchronous encoding result for each tab.
  private faviconCaptureSequenceByTabId: Map<string, number> = new Map();
  private pendingNavigationGeneration: number = 0;
  // Session restoration is asynchronous. Any user interaction that changes
  // the current browser state must invalidate the pending restore result so
  // a late preferences callback cannot overwrite the user's newer choice.
  private startupRestoreGeneration: number = 0;
  private startupRestorePending: boolean = false;
  private startupRestoreApplying: boolean = false;
  // Async settings/session callbacks and delayed navigation refreshes must not
  // touch a page instance after it has left the navigation stack.
  private pageLifecycleGeneration: number = 0;
  private pageVisible: boolean = false;
  private titleReceiveSequenceByTabId: Map<string, number> = new Map();
  private mediaProbeSequenceByTabId: Map<string, number> = new Map();
  // Last raw MediaPlaybackState reported per tab. Kept separately from
  // tab.audible so a state that never maps to "audible" is still visible in the
  // logs instead of being collapsed into "no change".
  private mediaProbeStateByTabId: Map<string, number> = new Map();
  // Kernel answer: the page is producing sound right now.
  private mediaKernelPlayingByTabId: Map<string, boolean> = new Map();
  // In-page monitor answer: an <audio>/<video> is playing, audible or not. This
  // is the only source that sees a video the page muted itself (autoplay).
  private mediaDomPlayingByTabId: Map<string, boolean> = new Map();
  // One bridge per tab. ArkWeb binds the proxy object when the Web component is
  // created, so the instance must outlive every rebuild of that component.
  private tabMediaBridges: Map<string, TabMediaBridge> = new Map();
  // Injected at document start for every tab. The script is identical for all
  // tabs because the bridge instance, not the page, carries the tab id.
  private mediaMonitorScripts: ScriptItem[] = [
    { script: TAB_MEDIA_MONITOR_SCRIPT, scriptRules: ['*'] },
  ];
  private lastDefaultZoomPercent: number = 100;
  private settingsListener: (settings: BrowserSettings) => void = (settings: BrowserSettings) => {
    this.applyBrowserSettingsChange(settings);
  };

  @Link route: AppRoute;
  @Link @Watch('handlePendingUrlChanged') pendingUrl: string;
  @Link @Watch('handlePendingNewTabUrlChanged') pendingNewTabUrl: string;
  @Link @Watch('handlePendingNewWindowUrlChanged') pendingNewWindowUrl: string;
  @Link @Watch('handlePendingPrivateWindowUrlChanged') pendingPrivateWindowUrl: string;
  // 清除浏览数据完成信号（SettingsViewModel 在站点数据清理成功后写入时间戳）。
  // 存活的 Web 组件持有内存态，不会自动感知 cookie/站点存储被外部清理，必须
  // 主动硬加载刷新才能不重启应用就生效。
  @StorageLink('browsingDataClearedAt') @Watch('handleBrowsingDataCleared')
  browsingDataClearedAt: number = 0;
  @Link settingsSectionId: string;
  sessionPersistenceEnabled: boolean = true;

  @State viewState: BrowserPageViewState = {
    tabs: [],
    activeTabId: '',
    addressText: '',
    showHome: true,
    currentUrl: 'about:blank',
    canGoBack: false,
    canGoForward: false,
    isPrivate: false,
  };

  // 地址栏当前文本
  @State addressText: string = '';
  // Web 组件当前加载的地址
  @State webSrc: string = 'about:blank';
  // 是否展示首页（新标签页内容），而不是 Web 页面；启动默认展示首页。
  @State showHome: boolean = true;
  @State navCanGoBack: boolean = false;
  @State navCanGoForward: boolean = false;
  // Changes whenever inactive WebView runtimes are evicted so the Web stack
  // unmounts the corresponding native views on the next render pass.
  @State private runtimeMountRevision: number = 0;

  @State showPermissionDialog: boolean = false;
  @State permissionRequest: SitePermissionRequest = EMPTY_PERMISSION_REQUEST;
  @State permissionRememberChoice: boolean = false;
  @State permissionDecisionPending: boolean = false;
  // ArkWeb JavaScript dialogs are application-owned. Keep one pending result
  // per BrowserPage and bind it to the originating tab/runtime so a late
  // callback cannot resolve a dialog belonging to another tab.
  @State showJavaScriptDialog: boolean = false;
  @State javaScriptDialogKind: JavaScriptDialogKind = 'alert';
  @State javaScriptDialogMessage: string = '';
  @State javaScriptDialogDefaultValue: string = '';
  @State javaScriptDialogInputValue: string = '';
  @State javaScriptDialogUrl: string = '';
  private pendingJavaScriptDialog: PendingJavaScriptDialog | null = null;
  @State isAddressEditing: boolean = false;
  @State currentPageBookmarked: boolean = false;
  @State addressSuggestions: AddressSuggestion[] = [];
  @State activeAddressSuggestionIndex: number = -1;
  @State showAddressSuggestions: boolean = false;
  @State downloadIndicator: DownloadIndicatorSnapshot = createIdleDownloadIndicatorSnapshot();
  @State showMainMenu: boolean = false;
  @State mainMenuActiveItemId: string = '';
  @State mainMenuWidth: number = 328;
  @State pageZoomPercent: number = 100;
  @State showBookmarksSubMenu: boolean = false;
  @State bookmarksSubMenuActiveItemId: string = '';
  @State showUaSubMenu: boolean = false;
  @State uaSubMenuActiveItemId: string = '';
  @State showFindPanel: boolean = false;
  @State findText: string = '';
  @State findMatchCount: number = 0;
  @State findActiveIndex: number = 0;
  @State findCaseSensitive: boolean = false;
  @State findIsCounting: boolean = false;
  @State viewportWidth: number = 1280;
  @State viewportHeight: number = 800;
  @State bookmarksSubMenuOffsetX: number = 328;
  @State bookmarksSubMenuOffsetY: number = 0;
  @State uaSubMenuOffsetX: number = 328;
  @State uaSubMenuOffsetY: number = 0;
  @State selectedUaMode: UaMode = 'desktop';
  @State uaRenderRevision: number = 0;
  @State appliedWebSettings: AppliedWebSettings = {
    javaScriptAccess: true,
    imageAccess: true,
    onlineImageAccess: true,
    domStorageAccess: true,
    databaseAccess: true,
  };
  @State currentPageScalePercent: number = 100;
  @State titleButtonAreaWidth: number = 0;
  @State showBookmarkBar: boolean = true;
  @State bookmarkBarItems: BookmarkItem[] = [];
  @State runtimeTabFavicons: TabFaviconPresentation[] = [];
  @State browserWebErrors: BrowserWebErrorState[] = [];
  @State addressSelectionRevision: number = 0;
  @State showContextMenu: boolean = false;
  @State contextMenuX: number = 0;
  @State contextMenuY: number = 0;
  @State contextMenuItems: BrowserContextMenuItem[] = [];
  @State showTabContextMenu: boolean = false;
  @State tabContextMenuX: number = 0;
  @State tabContextMenuY: number = 0;
  @State tabContextMenuItems: BrowserContextMenuItem[] = [];
  @State tabContextTargetId: string = '';
  @State showBookmarkContextMenu: boolean = false;
  @State bookmarkContextMenuX: number = 0;
  @State bookmarkContextMenuY: number = 0;
  @State bookmarkContextMenuItems: BrowserContextMenuItem[] = [];
  @State bookmarkContextTargetId: string = '';
  @State bookmarkFolderMenuX: number = 0;
  @State bookmarkFolderMenuY: number = 0;
  @State bookmarkFolderMenuItems: BrowserContextMenuItem[] = [];
  @State bookmarkFolderMenuTargetId: string = '';
  @State bookmarkFolderMenuTitle: string = '';
  // 文件夹菜单里正在拖拽的书签。普通字段而非 @State：drag 开始瞬间写 @State 会
  // 触发整页重渲染，可能打断刚起步的 drag 会话；BookmarkBar 在 drop 时经回调解析。
  private bookmarkFolderMenuDraggingItem: BookmarkItem | null = null;
  @State showBookmarkRenameDialog: boolean = false;
  @State bookmarkRenameId: string = '';
  @State bookmarkRenameTitle: string = '';
  @State showBookmarkDeleteDialog: boolean = false;
  @State bookmarkDeleteId: string = '';
  @State bookmarkDeleteTitle: string = '';
  @State showBookmarkEditDialog: boolean = false;
  @State bookmarkEditDialogTitle: string = '已添加书签';
  @State bookmarkEditNodeId: string = '';
  @State bookmarkEditName: string = '';
  @State bookmarkEditFolderId: string = BookmarkManager.ROOT_FOLDER_ID;
  @State bookmarkEditFolderIndex: number = 0;
  @State bookmarkEditFolderOptions: BookmarkEditFolderOption[] = [];
  @State bookmarkEditAnchorX: number = 0;
  @State bookmarkEditAnchorY: number = 0;
  @State webContentWidth: number = 1280;
  @State webContentHeight: number = 600;
  @State isFullScreen: boolean = false;
  @State showTabSearch: boolean = false;
  @State tabSearchQuery: string = '';
  @State tabSearchActiveIndex: number = 0;

  private pendingContextMenu: ContextMenuCommandState | null = null;
  private contextMenuTriggerX: number = 0;
  private contextMenuTriggerY: number = 0;
  private webPointerPositionByTabId: Map<string, WebPointerPosition> = new Map();
  // Tabs created through a page's window.open/target=_blank request. This
  // lets window.close() close only script-created tabs, never ordinary tabs.
  private webOpenedTabIds: Set<string> = new Set();
  private pendingSourceViewerByTabId: Map<string, PendingSourceViewer> = new Map();
  private lastFindTextByTabId: Map<string, string> = new Map();
  private pendingFindNavigationDirection: number = 0;

  private readonly mainMenuItems: BrowserMenuItem[] = [
    {
      id: 'new_tab',
      label: '打开新的标签页',
      leadingIconResource: $r('app.media.settings_menu_new_tab'),
      shortcut: 'Ctrl+T'
    },
    {
      id: 'new_window',
      label: '打开新窗口',
      leadingIconResource: $r('app.media.settings_menu_new_window'),
      shortcut: 'Ctrl+N'
    },
    // 暂时预留，后期完善：无痕模式当前不对用户开放，因此不加入主菜单。
    {
      id: 'bookmarks',
      label: '书签',
      leadingIconResource: $r('app.media.settings_menu_bookmarks'),
      showArrow: true,
      shortcut: 'Ctrl+Shift+O'
    },
    {
      id: 'history',
      label: '历史记录',
      leadingIconResource: $r('app.media.settings_menu_history'),
      shortcut: 'Ctrl+H'
    },
    {
      id: 'downloads',
      label: '下载管理',
      leadingIconResource: $r('app.media.settings_menu_downloads'),
      shortcut: 'Ctrl+J'
    },
    // 暂时隐藏：ArkWeb 缩小方向受页面 fit-width 最小比例钳制，待方案完善后再开放。
    // {
    //   id: 'zoom', label: '缩放', leadingIconResource: $r('app.media.settings_menu_zoom'),
    //   kind: 'zoom', dividerBefore: true, zoomPercent: 100
    // },
    {
      id: 'find_in_page',
      label: '页内查找',
      leadingIconResource: $r('app.media.settings_menu_find_in_page'),
      shortcut: 'Ctrl+F',
      dividerBefore: true
    },
    {
      id: 'print',
      label: '打印',
      leadingIconResource: $r('app.media.settings_menu_print'),
      shortcut: 'Ctrl+P'
    },
    {
      id: 'add_to_desktop',
      label: '添加至桌面',
      leadingIconResource: $r('app.media.settings_menu_add_to_desktop'),
      disabled: true
    },
    {
      id: 'save_page_as',
      label: '网页另存为',
      leadingIconResource: $r('app.media.settings_menu_save_page_as'),
      shortcut: 'Ctrl+S'
    },
    // Keep the UA switch available from the browser menu. The submenu and
    // runtime application logic remain shared for every open tab.
    { id: 'ua', label: '浏览器UA标识', leadingIcon: 'A', showArrow: true },
    {
      id: 'settings',
      label: '设置',
      leadingIconResource: $r('app.media.settings_menu_settings'),
      dividerBefore: true
    },
  ];

  private readonly bookmarksSubMenuItems: BrowserMenuItem[] = [
    { id: 'bookmarks_manager', label: '书签管理器' },
    { id: 'toggle_page_bookmark', label: '收藏当前页面' },
    { id: 'show_bookmark_bar', label: '显示书签栏', checked: true },
  ];

  private readonly uaSubMenuItems: BrowserMenuItem[] = [
    { id: 'desktop', label: '桌面版 UA' },
    { id: 'mobile', label: '手机版 UA' },
  ];

  private getResolvedMainMenuItems(): BrowserMenuItem[] {
    return this.mainMenuItems.map((item: BrowserMenuItem) => {
      if (item.id === 'zoom') {
        const resolvedItem: BrowserMenuItem = {
          id: item.id,
          label: item.label,
          leadingIcon: item.leadingIcon,
          leadingIconResource: item.leadingIconResource,
          shortcut: item.shortcut,
          disabled: item.disabled,
          checked: item.checked,
          danger: item.danger,
          dividerBefore: item.dividerBefore,
          hoverHighlightDisabled: item.hoverHighlightDisabled,
          showArrow: item.showArrow,
          trailingText: item.trailingText,
          kind: item.kind,
          zoomPercent: this.pageZoomPercent,
        };
        return resolvedItem;
      }
      return item;
    });
  }

  private getResolvedBookmarksSubMenuItems(): BrowserMenuItem[] {
    return this.bookmarksSubMenuItems.map((item: BrowserMenuItem) => {
      if (item.id === 'toggle_page_bookmark') {
        const resolvedItem: BrowserMenuItem = {
          id: item.id,
          label: this.currentPageBookmarked ? '取消收藏当前页面' : '收藏当前页面',
          checked: this.currentPageBookmarked,
          disabled: !this.canToggleCurrentPageBookmark(),
        };
        return resolvedItem;
      }
      if (item.id === 'show_bookmark_bar') {
        const resolvedItem: BrowserMenuItem = {
          id: item.id,
          label: item.label,
          checked: this.showBookmarkBar,
        };
        return resolvedItem;
      }
      return item;
    });
  }

  private getBookmarksSubMenuState(): BrowserSubMenuState {
    return {
      visible: this.showBookmarksSubMenu && !this.showUaSubMenu,
      items: this.getResolvedBookmarksSubMenuItems(),
      activeItemId: this.bookmarksSubMenuActiveItemId,
      anchorX: this.bookmarksSubMenuOffsetX,
      anchorY: this.bookmarksSubMenuOffsetY,
      menuWidth: 220,
    };
  }

  private getResolvedUaSubMenuItems(): BrowserMenuItem[] {
    return this.uaSubMenuItems.map((item: BrowserMenuItem) => {
      const resolvedItem: BrowserMenuItem = {
        id: item.id,
        label: item.label,
        checked: this.selectedUaMode === item.id,
      };
      return resolvedItem;
    });
  }

  private getUaSubMenuState(): BrowserSubMenuState {
    return {
      visible: this.showUaSubMenu,
      items: this.getResolvedUaSubMenuItems(),
      activeItemId: this.uaSubMenuActiveItemId,
      anchorX: this.uaSubMenuOffsetX,
      anchorY: this.uaSubMenuOffsetY,
      menuWidth: 220,
    };
  }

  private getActiveMainMenuSubMenuState(): BrowserSubMenuState {
    if (this.showUaSubMenu) {
      return this.getUaSubMenuState();
    }
    if (this.showBookmarksSubMenu) {
      return this.getBookmarksSubMenuState();
    }
    return EMPTY_BROWSER_SUB_MENU_STATE;
  }

  private shouldCloseTransientOverlays(): boolean {
    return this.showContextMenu || this.showTabContextMenu || this.showBookmarkContextMenu ||
      this.bookmarkFolderMenuItems.length > 0 || this.showBookmarkRenameDialog ||
      this.showBookmarkDeleteDialog || this.showMainMenu ||
      this.showBookmarkEditDialog ||
      this.showFindPanel || this.showTabSearch ||
      this.showAddressSuggestions || this.isAddressEditing || this.showJavaScriptDialog;
  }

  private closeTransientOverlays(): void {
    if (this.showBookmarkEditDialog) {
      this.closeBookmarkEditDialog();
    }
    if (this.showContextMenu) {
      this.closeContextMenu();
    }
    if (this.showTabContextMenu) {
      this.closeTabContextMenu();
    }
    if (this.showBookmarkContextMenu) {
      this.closeBookmarkContextMenu();
    }
    if (this.bookmarkFolderMenuItems.length > 0) {
      this.closeBookmarkFolderMenu();
    }
    if (this.showBookmarkRenameDialog) {
      this.cancelBookmarkRename();
    }
    if (this.showBookmarkDeleteDialog) {
      this.cancelBookmarkDelete();
    }
    if (this.showMainMenu) {
      this.closeMainMenu();
    }
    if (this.showFindPanel) {
      this.closeFindPanel();
    }
    if (this.showTabSearch) {
      this.closeTabSearch();
    }
    if (this.showAddressSuggestions || this.isAddressEditing) {
      this.cancelAddressEditing();
    }
    if (this.showJavaScriptDialog) {
      this.resolveJavaScriptDialog(false);
    }
  }

  private navigateToRoute(nextRoute: AppRoute): void {
    this.closeTransientOverlays();
    // Keep legacy standalone routes as compatibility aliases, but canonicalize
    // them to the settings shell so no entry can accidentally cover the
    // browser toolbar or create a second full-screen settings implementation.
    if (nextRoute === AppRouter.downloads) {
      this.settingsSectionId = 'download-manager';
      this.route = AppRouter.settings;
      return;
    }
    if (nextRoute === AppRouter.bookmarks) {
      this.settingsSectionId = 'bookmarks-manager';
      this.route = AppRouter.settings;
      return;
    }
    if (nextRoute === AppRouter.history) {
      this.settingsSectionId = 'history';
      this.route = AppRouter.settings;
      return;
    }
    this.route = nextRoute;
  }

  private normalizeEmbeddedSettingsRoute(): void {
    if (this.route === AppRouter.downloads) {
      this.settingsSectionId = 'download-manager';
      this.route = AppRouter.settings;
    } else if (this.route === AppRouter.bookmarks) {
      this.settingsSectionId = 'bookmarks-manager';
      this.route = AppRouter.settings;
    } else if (this.route === AppRouter.history) {
      this.settingsSectionId = 'history';
      this.route = AppRouter.settings;
    }
  }

  /** 设置相关页面覆盖内容区时，顶部壳始终保留标签栏、地址栏和书签栏。 */
  private isSettingsRouteActive(): boolean {
    return this.route === AppRouter.settings || this.route === AppRouter.downloads ||
      this.route === AppRouter.bookmarks || this.route === AppRouter.history;
  }

  private getSettingsSectionForRoute(): string {
    if (this.route === AppRouter.downloads) {
      return 'download-manager';
    }
    if (this.route === AppRouter.bookmarks) {
      return 'bookmarks-manager';
    }
    if (this.route === AppRouter.history) {
      return 'history';
    }
    return this.settingsSectionId;
  }

  /**
   * 顶部壳发起的导航会改变内容区，设置页必须先让出内容区，
   * 否则用户按了返回/刷新/地址栏跳转却看不到任何结果。
   */
  private exitSettingsOverlayForNavigation(): void {
    if (this.isSettingsRouteActive()) {
      this.route = AppRouter.browser;
    }
  }

  /** Opens the single bookmarks manager hosted by the Settings shell. */
  private openBookmarksManager(): void {
    this.settingsSectionId = 'bookmarks-manager';
    this.navigateToRoute(AppRouter.settings);
  }

  /** Opens the unified downloads list hosted by the Settings shell. */
  private openDownloadsManager(): void {
    this.settingsSectionId = 'download-manager';
    this.navigateToRoute(AppRouter.settings);
  }

  /** Opens the history list hosted by the Settings shell. */
  private openHistoryManager(): void {
    this.settingsSectionId = 'history';
    this.navigateToRoute(AppRouter.settings);
  }

  private updateMainMenuLayout(width: number, height: number): void {
    if (width > 0) {
      this.viewportWidth = width;
    }
    if (height > 0) {
      this.viewportHeight = height;
    }
    if (this.showBookmarksSubMenu) {
      this.updateBookmarksSubMenuAnchor();
    }
    if (this.showUaSubMenu) {
      this.updateUaSubMenuAnchor();
    }
  }

  private getMainMenuRightInset(): number {
    return 12;
  }

  private getResolvedMainMenuWidth(): number {
    const availableWidth = this.viewportWidth - this.getMainMenuRightInset() - 24;
    const fallbackWidth = Math.max(160, this.viewportWidth - 24);
    return Math.min(this.mainMenuWidth, Math.max(160, Math.min(availableWidth, fallbackWidth)));
  }

  private getMainMenuAnchorX(): number {
    return Math.max(12, this.viewportWidth - this.getResolvedMainMenuWidth() - this.getMainMenuRightInset());
  }

  private getMainMenuAnchorY(): number {
    return 84;
  }

  private getFindPanelAnchorX(): number {
    return Math.max(12, this.viewportWidth - this.getFindPanelWidth() - 12);
  }

  private getFindPanelAnchorY(): number {
    return 84;
  }

  private getFindPanelWidth(): number {
    return Math.min(320, Math.max(220, this.viewportWidth - 24));
  }

  private getAddressSuggestionMaxHeight(): number {
    return Math.max(120, Math.min(360, this.viewportHeight - 132));
  }

  private getPermissionDialogWidth(): number {
    return Math.min(360, Math.max(260, this.viewportWidth - 48));
  }

  private getMainMenuMaxHeight(): number {
    return Math.max(96, this.viewportHeight - this.getMainMenuAnchorY() - 16);
  }

  private getSubMenuMaxHeight(): number {
    return Math.max(96, this.viewportHeight - this.getMainMenuAnchorY() - 16);
  }

  private getSubMenuOffsetX(subMenuWidth: number): number {
    const gap = 8;
    const menuAnchorX = this.getMainMenuAnchorX();
    const menuWidth = this.getResolvedMainMenuWidth();
    const leftOffset = -(subMenuWidth + gap);
    const rightOffset = menuWidth + gap;
    const leftSpace = menuAnchorX - 12;
    const rightSpace = this.viewportWidth - menuAnchorX - menuWidth - 12;

    if (leftSpace >= subMenuWidth + gap) {
      return leftOffset;
    }
    if (rightSpace >= subMenuWidth + gap) {
      return rightOffset;
    }

    const minOffset = 12 - menuAnchorX;
    const maxOffset = this.viewportWidth - menuAnchorX - subMenuWidth - 12;
    return Math.max(minOffset, Math.min(rightOffset, maxOffset));
  }

  private updateBookmarksSubMenuAnchor(): void {
    const subMenuWidth = 220;
    this.bookmarksSubMenuOffsetX = this.getSubMenuOffsetX(subMenuWidth);

    const preferredTop = this.getMainMenuItemOffsetY('bookmarks');
    const subMenuHeight = this.getResolvedBookmarksSubMenuItems().length * 42 + 16;
    const maxTop = Math.max(0, this.getMainMenuMaxHeight() - Math.min(subMenuHeight, this.getSubMenuMaxHeight()));
    this.bookmarksSubMenuOffsetY = preferredTop > maxTop ? maxTop : preferredTop;
  }

  private updateUaSubMenuAnchor(): void {
    const subMenuWidth = 220;
    this.uaSubMenuOffsetX = this.getSubMenuOffsetX(subMenuWidth);

    const preferredTop = this.getMainMenuItemOffsetY('ua');
    const subMenuHeight = this.getResolvedUaSubMenuItems().length * 42 + 16;
    const maxTop = Math.max(0, this.getMainMenuMaxHeight() - Math.min(subMenuHeight, this.getSubMenuMaxHeight()));
    this.uaSubMenuOffsetY = preferredTop > maxTop ? maxTop : preferredTop;
  }

  private getMainMenuItemOffsetY(itemId: string): number {
    let offsetY = 0;
    const items = this.getResolvedMainMenuItems();
    for (let index = 0; index < items.length; index++) {
      const item = items[index];
      if (item.dividerBefore) {
        offsetY += 11;
      }
      if (item.id === itemId) {
        return offsetY;
      }
      offsetY += item.kind === 'zoom' ? 52 : 44;
    }
    return 0;
  }

  // 拖拽重排/移入期间同步抑制 notify 引发的文件夹菜单关闭（notify 是同步回调）。
  private suppressBookmarkFolderMenuClose: boolean = false;

  private bookmarkListener: (_: BookmarkItem[]) => void = (_: BookmarkItem[]) => {
    this.refreshBookmarkBarItems();
    this.syncCurrentBookmarkState(this.viewState.currentUrl);
    if (this.isAddressEditing && this.addressText.trim().length > 0) {
      this.refreshAddressSuggestions(this.addressText);
    }
    this.closeBookmarkContextMenu();
    if (!this.suppressBookmarkFolderMenuClose) {
      this.closeBookmarkFolderMenu();
    }
    // A mutation may invalidate the item currently being edited/deleted (for
    // example, another window removes it). Close transient dialogs as well so
    // a late confirmation cannot act on a stale bookmark id.
    if (this.showBookmarkRenameDialog) {
      this.cancelBookmarkRename();
    }
    if (this.showBookmarkDeleteDialog) {
      this.cancelBookmarkDelete();
    }
  }

  private refreshBookmarkBarItems(): void {
    // Keep folders in the same ordered root list as bookmarks. The bar is a
    // projection of BookmarkManager rather than a second, flattened store.
    this.bookmarkBarItems = this.bookmarkManager.listBookmarksByParent(BookmarkManager.ROOT_FOLDER_ID);
  }

  private getBookmarkBarContextMenuItems(bookmark: BookmarkItem | null): BrowserContextMenuItem[] {
    if (!bookmark) {
      return [
        { id: 'open_manager', label: '书签管理器', leadingIcon: '▤' },
        { id: 'toggle_bar', label: this.showBookmarkBar ? '隐藏书签栏' : '显示书签栏', leadingIcon: '▤' },
      ];
    }
    if (bookmark.isFolder) {
      return [
        { id: 'open_folder', label: '打开文件夹', leadingIcon: '□' },
        { id: 'rename', label: '重命名', leadingIcon: '✎' },
        { id: 'delete', label: '删除文件夹', leadingIcon: '⌫', dividerBefore: true },
        { id: 'open_manager', label: '书签管理器', leadingIcon: '▤' },
        { id: 'toggle_bar', label: this.showBookmarkBar ? '隐藏书签栏' : '显示书签栏', leadingIcon: '▤' },
      ];
    }
    return [
      { id: 'open_current', label: '在当前标签页打开', leadingIcon: '↗' },
      { id: 'open_new_tab', label: '在新标签页打开', leadingIcon: '+' },
      { id: 'open_new_window', label: '在新窗口打开', leadingIcon: '□' },
      // 暂时预留，后期完善：无痕窗口打开方式当前不对用户开放。
      { id: 'rename', label: '修改', leadingIcon: '✎', dividerBefore: true },
      { id: 'delete', label: '删除', leadingIcon: '⌫' },
      { id: 'open_manager', label: '书签管理器', leadingIcon: '▤', dividerBefore: true },
      { id: 'toggle_bar', label: this.showBookmarkBar ? '隐藏书签栏' : '显示书签栏', leadingIcon: '▤' },
    ];
  }

  private getBookmarkFolderChildren(folderId: string): BookmarkItem[] {
    return this.bookmarkManager.listBookmarksByParent(folderId);
  }

  private resolveBookmarkMenuPosition(rawX: number, rawY: number, itemCount: number): ContextMenuPosition {
    const menuWidth = Math.min(280, Math.max(220, this.viewportWidth - 24));
    const menuHeight = Math.min(420, itemCount * 40 + 16);
    const maxX = Math.max(8, this.viewportWidth - menuWidth - 8);
    const maxY = Math.max(8, this.viewportHeight - menuHeight - 8);
    const x = Number.isFinite(rawX) ? rawX : 8;
    const y = Number.isFinite(rawY) ? rawY : 40;
    return {
      x: Math.max(8, Math.min(x, maxX)),
      y: Math.max(8, Math.min(y + 2, maxY)),
    };
  }

  private showBookmarkBarContextMenu(bookmark: BookmarkItem | null, rawX: number, rawY: number): void {
    this.closeContextMenu();
    this.closeTabContextMenu();
    this.closeMainMenu();
    this.bookmarkContextTargetId = bookmark ? bookmark.id : '';
    this.bookmarkContextMenuItems = this.getBookmarkBarContextMenuItems(bookmark);
    const position = this.resolveBookmarkMenuPosition(rawX, rawY, this.bookmarkContextMenuItems.length);
    this.bookmarkContextMenuX = position.x;
    this.bookmarkContextMenuY = position.y;
    this.showBookmarkContextMenu = true;
    hilog.info(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
      'BAR_CONTEXT_OPEN target=%{public}s folder=%{public}s x=%{public}d y=%{public}d items=%{public}d',
      bookmark?.id ?? '', String(bookmark?.isFolder === true), position.x, position.y,
      this.bookmarkContextMenuItems.length);
  }

  private getBookmarkMenuIcon(item: BookmarkItem): ResourceStr {
    if (item.isFolder) {
      return $r('app.media.home_tab_folder');
    }
    const faviconUrl = item.faviconUrl ? item.faviconUrl.trim() : '';
    return faviconUrl.length > 0 ? faviconUrl : $r('app.media.default_site_icon');
  }

  private buildBookmarkFolderMenuItems(children: BookmarkItem[]): BrowserContextMenuItem[] {
    if (children.length === 0) {
      return [{
        id: 'bookmark_folder_empty',
        label: '文件夹为空',
        leadingIcon: '·',
        disabled: true
      } as BrowserContextMenuItem];
    }
    return children.map((item: BookmarkItem): BrowserContextMenuItem => ({
      id: `bookmark_child:${item.id}`,
      label: item.isFolder ? `${item.title}  ›` : item.title,
      leadingImage: this.getBookmarkMenuIcon(item)
    }));
  }

  private showBookmarkFolderMenu(folder: BookmarkItem, rawX: number, rawY: number): void {
    this.closeBookmarkContextMenu();
    this.bookmarkFolderMenuTargetId = folder.id;
    this.bookmarkFolderMenuTitle = folder.title;
    const children = this.getBookmarkFolderChildren(folder.id);
    this.bookmarkFolderMenuItems = this.buildBookmarkFolderMenuItems(children);
    const position = this.resolveBookmarkMenuPosition(rawX, rawY, this.bookmarkFolderMenuItems.length);
    this.bookmarkFolderMenuX = position.x;
    this.bookmarkFolderMenuY = position.y;
    hilog.info(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
      'BAR_FOLDER_OPEN folder=%{public}s title=%{public}s x=%{public}d y=%{public}d children=%{public}d',
      folder.id, folder.title, position.x, position.y, children.length);
  }

  private refreshBookmarkFolderMenuItems(): void {
    const folderId = this.bookmarkFolderMenuTargetId;
    if (folderId.length === 0) {
      return;
    }
    this.bookmarkFolderMenuItems = this.buildBookmarkFolderMenuItems(this.getBookmarkFolderChildren(folderId));
  }

  private handleBookmarkFolderDragStart(itemId: string): void {
    const prefix = 'bookmark_child:';
    if (!itemId.startsWith(prefix)) {
      this.bookmarkFolderMenuDraggingItem = null;
      return;
    }
    this.bookmarkFolderMenuDraggingItem = this.bookmarkManager.getBookmarkById(itemId.substring(prefix.length));
    hilog.info(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
      'FOLDER_DRAG_START item=%{public}s resolved=%{public}s',
      itemId, String(this.bookmarkFolderMenuDraggingItem !== null));
  }

  private handleBookmarkFolderDragEnd(): void {
    this.bookmarkFolderMenuDraggingItem = null;
  }

  private handleBookmarkFolderMenuReorder(sourceItemId: string, targetItemId: string): void {
    const prefix = 'bookmark_child:';
    if (!sourceItemId.startsWith(prefix) || !targetItemId.startsWith(prefix)) {
      return;
    }
    const sourceId = sourceItemId.substring(prefix.length);
    const targetId = targetItemId.substring(prefix.length);
    const parentId = this.bookmarkFolderMenuTargetId;
    const source = this.bookmarkManager.getBookmarkById(sourceId);
    const target = this.bookmarkManager.getBookmarkById(targetId);
    if (!source || !target || source.id === target.id || parentId.length === 0) {
      return;
    }
    // 与书签栏的拖放语义保持一致：落在书签上=重排到目标位置，落在子文件夹上=移入其中。
    // moveNode 会同步 notify 书签监听器，抑制期间保住文件夹菜单不关。
    this.suppressBookmarkFolderMenuClose = true;
    let moved: BookmarkItem | null = null;
    try {
      if (target.isFolder) {
        moved = this.bookmarkManager.moveNode(source.id, target.id);
      } else {
        moved = this.bookmarkManager.moveNode(source.id, parentId, target.sortOrder);
      }
    } finally {
      this.suppressBookmarkFolderMenuClose = false;
    }
    hilog.info(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
      'FOLDER_REORDER source=%{public}s target=%{public}s folder=%{public}s moved=%{public}s',
      source.id, target.id, parentId, String(moved !== null));
    if (moved) {
      this.refreshBookmarkFolderMenuItems();
      this.flushBookmarkMutation('FOLDER_REORDER', source.id);
    }
  }

  private closeBookmarkContextMenu(): void {
    this.showBookmarkContextMenu = false;
    this.bookmarkContextTargetId = '';
    this.bookmarkContextMenuItems = [];
  }

  private closeBookmarkFolderMenu(): void {
    this.bookmarkFolderMenuItems = [];
    this.bookmarkFolderMenuTargetId = '';
    this.bookmarkFolderMenuTitle = '';
    this.bookmarkFolderMenuDraggingItem = null;
  }

  private handleBookmarkFolderMenuSelect(item: BrowserContextMenuItem): void {
    if (item.disabled || !item.id.startsWith('bookmark_child:')) {
      return;
    }
    const childId = item.id.substring('bookmark_child:'.length);
    const parentId = this.bookmarkFolderMenuTargetId;
    const child = this.getBookmarkFolderChildren(parentId).find((entry: BookmarkItem) => entry.id === childId);
    if (!child) {
      this.closeBookmarkFolderMenu();
      return;
    }
    if (child.isFolder) {
      this.showBookmarkFolderMenu(child, this.bookmarkFolderMenuX, this.bookmarkFolderMenuY);
      return;
    }
    this.closeBookmarkFolderMenu();
    this.openBookmarkBarItem(child);
  }

  private handleBookmarkBarDrop(source: BookmarkItem, target: BookmarkItem | null, targetIndex: number): void {
    if (source.id === target?.id) {
      return;
    }
    // moveNode 同步 notify 监听器；若正从文件夹菜单拖出到书签栏，菜单应保持打开。
    this.suppressBookmarkFolderMenuClose = true;
    let moved: BookmarkItem | null = null;
    try {
      if (target?.isFolder) {
        moved = this.bookmarkManager.moveNode(source.id, target.id);
      } else if (target) {
        moved = this.bookmarkManager.moveNode(source.id, target.parentId, target.sortOrder);
      } else {
        moved = this.bookmarkManager.moveNode(source.id, BookmarkManager.ROOT_FOLDER_ID, targetIndex);
      }
    } finally {
      this.suppressBookmarkFolderMenuClose = false;
    }
    hilog.info(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
      'BAR_DROP source=%{public}s target=%{public}s targetIndex=%{public}d moved=%{public}s',
      source.id, target?.id ?? '', targetIndex, String(moved !== null));
    this.bookmarkFolderMenuDraggingItem = null;
    if (this.bookmarkFolderMenuItems.length > 0) {
      // 从文件夹菜单拖出落到书签栏：菜单保持打开并移除已拖走的项。
      this.refreshBookmarkFolderMenuItems();
    }
    this.bookmarkManager.flushPersistence().catch(() => {
      hilog.warn(FAVICON_LOG_DOMAIN, 'BookmarkTrace', 'BAR_DROP_PERSIST_FAILED source=%{public}s', source.id);
    });
  }

  private flushBookmarkMutation(action: string, nodeId: string): void {
    this.bookmarkManager.flushPersistence()
      .then(() => {
        hilog.info(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
          'BAR_MUTATION_PERSISTED action=%{public}s node=%{public}s', action, nodeId);
      })
      .catch(() => {
        hilog.warn(FAVICON_LOG_DOMAIN, 'BookmarkTrace',
          'BAR_MUTATION_PERSIST_FAILED action=%{public}s node=%{public}s', action, nodeId);
        this.showOperationToast('书签变更保存失败，请稍后重试');
      });
  }

  private handleBookmarkContextMenuSelect(item: BrowserContextMenuItem): void {
    const target = this.bookmarkContextTargetId.length > 0 ?
      this.bookmarkManager.getBookmarkById(this.bookmarkContextTargetId) : null;
    const menuX = this.bookmarkContextMenuX;
    const menuY = this.bookmarkContextMenuY;
    this.closeBookmarkContextMenu();
    if (item.disabled) {
      return;
    }
    if (item.id === 'toggle_bar') {
      this.toggleBookmarkBar();
      return;
    }
    if (item.id === 'open_manager') {
      this.openBookmarksManager();
      return;
    }
    if (!target) {
      return;
    }
    if (item.id === 'open_folder') {
      this.showBookmarkFolderMenu(target, menuX, menuY);
    } else if (item.id === 'open_current') {
      this.openBookmarkBarItem(target);
    } else if (item.id === 'open_new_tab' && target.url) {
      this.applyViewState(this.viewModel.newTabWithUrl(target.url), true);
    } else if (item.id === 'open_new_window' && target.url) {
      this.windowManager.openNormalWindow(this.getUIContext(), target.url)
        .catch(() => this.showOperationToast('无法打开新窗口'));
    // 暂时预留，后期完善：无痕窗口打开能力保留在底层，但当前不处理用户入口。
    } else if (item.id === 'rename') {
      this.bookmarkRenameId = target.id;
      this.bookmarkRenameTitle = target.title;
      this.showBookmarkRenameDialog = true;
    } else if (item.id === 'delete') {
      this.bookmarkDeleteId = target.id;
      this.bookmarkDeleteTitle = target.title;
      this.showBookmarkDeleteDialog = true;
    }
  }

  private confirmBookmarkRename(): void {
    if (!this.bookmarkRenameId || !this.bookmarkRenameTitle.trim()) {
      return;
    }
    this.bookmarkManager.renameNode(this.bookmarkRenameId, this.bookmarkRenameTitle);
    this.flushBookmarkMutation('rename', this.bookmarkRenameId);
    this.showBookmarkRenameDialog = false;
    this.bookmarkRenameId = '';
    this.bookmarkRenameTitle = '';
  }

  private cancelBookmarkRename(): void {
    this.showBookmarkRenameDialog = false;
    this.bookmarkRenameId = '';
    this.bookmarkRenameTitle = '';
  }

  private cancelBookmarkDelete(): void {
    this.showBookmarkDeleteDialog = false;
    this.bookmarkDeleteId = '';
    this.bookmarkDeleteTitle = '';
  }

  private confirmBookmarkDelete(): void {
    if (!this.bookmarkDeleteId) {
      this.cancelBookmarkDelete();
      return;
    }
    const nodeId = this.bookmarkDeleteId;
    this.bookmarkManager.removeNode(nodeId);
    this.flushBookmarkMutation('delete', nodeId);
    this.cancelBookmarkDelete();
  }

  private appLifecycleListener: (p: AppLifecyclePayload) => void = (p: AppLifecyclePayload) => {
    if (p.state === 'background') {
      this.persistSession();
    }
    // Emit app lifecycle events to H5 when JSBridge is enabled for the current page.
    // Event names follow a simple convention: app:foreground / app:background.
    // Standard event envelope: { ts, data }
    const dataJson: string = `{"ts":${p.ts},"data":{"state":${JSON.stringify(p.state)}}}`;
    const jsBridge = this.getActiveJsBridge();
    if (jsBridge) {
      jsBridge.emitEvent(`app:${p.state}`, dataJson);
    }
  }

  private memoryPressureListener: (p: MemoryPressurePayload) => void = (p: MemoryPressurePayload) => {
    this.handleMemoryPressure(p);
  }

  private handleMemoryPressure(payload: MemoryPressurePayload): void {
    if (!this.pageVisible) {
      return;
    }
    const beforeCount = this.webViewManager.getRuntimeCount();
    const protectedTabIds = this.getRuntimeProtectionIds();
    this.webViewManager.setMemoryPressureLevel(payload.level, protectedTabIds);
    const afterCount = this.webViewManager.getRuntimeCount();
    if (afterCount !== beforeCount) {
      this.runtimeMountRevision += 1;
    }
    hilog.info(FAVICON_LOG_DOMAIN, 'RuntimeMemory',
      'MEMORY_PRESSURE_APPLIED level=%{public}d before=%{public}d after=%{public}d ' +
      'limit=%{public}d protected=%{public}d mountRevision=%{public}d',
      payload.level, beforeCount, afterCount, this.webViewManager.getEffectiveRuntimeLimit(),
      protectedTabIds.length, this.runtimeMountRevision);
  }

  private downloadListener: (_: DownloadTask[]) => void = (_: DownloadTask[]) => {
    this.refreshDownloadIndicator();
  }

  private restoreSessionOnStart(): void {
    const lifecycleGeneration = this.pageLifecycleGeneration;
    if (!this.sessionPersistenceEnabled) {
      const fallbackState = this.viewModel.getInitialState();
      this.applyViewState(fallbackState, false, true, false);
      this.focusAddressBarAfterStartup(fallbackState);
      return;
    }
    SettingsManager.getInstance().whenReady()
      .then(() => {
        if (this.isPageLifecycleCurrent(lifecycleGeneration)) {
          this.applyStartupBehaviorOnStart(lifecycleGeneration);
        }
      })
      .catch(() => {
        if (this.isPageLifecycleCurrent(lifecycleGeneration)) {
          this.applyStartupBehaviorOnStart(lifecycleGeneration);
        }
      });
  }

  private persistSession(): void {
    if (this.sessionPersistenceEnabled) {
      this.viewModel.persistCurrentSession();
    }
  }

  private handlePendingUrlChanged(): void {
    const nextUrl = this.pendingUrl.trim();
    if (!nextUrl) {
      return;
    }
    this.pendingNavigationGeneration += 1;
    this.pendingUrl = '';
    this.handleAddressSubmit(nextUrl);
  }

  private handlePendingNewTabUrlChanged(): void {
    const nextUrl = this.pendingNewTabUrl.trim();
    if (!nextUrl) {
      return;
    }
    this.pendingNewTabUrl = '';
    this.invalidatePendingStartupRestore('bookmark_new_tab');
    this.closeTransientOverlays();
    this.applyViewState(this.viewModel.newTabWithUrl(nextUrl), true);
  }

  private handlePendingNewWindowUrlChanged(): void {
    const nextUrl = this.pendingNewWindowUrl.trim();
    if (!nextUrl) {
      return;
    }
    this.pendingNewWindowUrl = '';
    this.windowManager.openNormalWindow(this.getUIContext(), nextUrl)
      .catch(() => this.showOperationToast('无法打开新窗口'));
  }

  private handlePendingPrivateWindowUrlChanged(): void {
    const nextUrl = this.pendingPrivateWindowUrl.trim();
    if (!nextUrl) {
      return;
    }
    // 暂时预留，后期完善：当前版本不支持无痕模式，消费并忽略外部残留请求。
    this.pendingPrivateWindowUrl = '';
  }

  // 清除浏览数据完成后立即生效：销毁重建全部 Web 运行时。
  // 实测仅清持久层并 loadUrl 刷新不足以让存活页面退出登录——ArkWeb 渲染
  // 进程持有内存 cookie/会话缓存，不随 WebCookieManager 清理失效（原 bug
  // 的“重启应用才退出登录”正是组件销毁重建后才丢弃内存态的表现）。因此
  // 复用 UA 切换 restartWebRuntimesForUaMode 的重建流程：destroyAll 后递增
  // uaRenderRevision，ForEach key 变化强制所有 Web 组件销毁重建，新组件从
  // 已清空的持久层重新读取站点数据。
  private handleBrowsingDataCleared(): void {
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'CLEAR_DATA_RUNTIME_RECREATE tabs=%{public}d active=%{public}s',
      this.viewState.tabs.length, this.viewState.activeTabId);
    const activeTab = this.findTab(this.viewState.activeTabId);
    if (activeTab && activeTab.loadState !== 'home' && activeTab.url.trim().length > 0) {
      this.applyViewState(this.viewModel.reloadActiveTab(), false, false);
    }

    this.skipNextHistoryRecordTabIds.clear();
    this.viewState.tabs.forEach((tab: Tab) => {
      this.cancelPendingNativeNavigation(tab.id, 'clear_data_runtime_recreate');
      this.navigationStateSettlingUntilByTabId.delete(String(tab.id));
      // 重建后的首轮加载不回写历史，避免刚清空的历史记录被当场重建。
      if (!tab.isPrivate && tab.loadState !== 'home' && this.isHttpUrl(tab.url)) {
        this.skipNextHistoryRecordTabIds.add(String(tab.id));
      }
      const state = this.getTabWebRuntimeState(tab.id);
      state.controllerAttached = false;
      state.pendingUrl = tab.loadState === 'home' ? '' : tab.url.trim();
      state.requestedUrl = state.pendingUrl;
      state.committedUrl = '';
      state.loadedUrl = '';
      state.lastError = '';
      if (state.pendingUrl.length > 0) {
        this.markTabLoadRequested(tab.id, state.pendingUrl);
        state.pendingUrl = tab.url.trim();
      }
    });
    this.webViewManager.destroyAll();
    this.uaRenderRevision += 1;
    // 地址栏联想正展开时，立即按已清空的历史库刷新建议列表。
    if (this.isAddressEditing && this.addressText.trim().length > 0) {
      this.refreshAddressSuggestions(this.addressText);
    }
  }

  private applyStartupBehaviorOnStart(lifecycleGeneration: number = this.pageLifecycleGeneration): void {
    if (!this.isPageLifecycleCurrent(lifecycleGeneration)) {
      return;
    }
    const initial: string = (this.pendingUrl && this.pendingUrl.trim()) ? this.pendingUrl : '';
    if (initial) {
      this.pendingUrl = '';
      this.handleAddressSubmit(initial);
      return;
    }

    const startupBehavior = SettingsManager.getInstance().getSettings().startupBehavior;
    if (startupBehavior === 'new_tab') {
      const state = this.viewModel.getInitialState();
      this.applyViewState(state, false);
      this.focusAddressBarAfterStartup(state);
      return;
    }

    if (startupBehavior === 'home_page') {
      const state = this.viewModel.goHome();
      this.applyViewState(state, !state.showHome);
      this.focusAddressBarAfterStartup(state);
      return;
    }

    const restoreGeneration = this.pendingNavigationGeneration;
    const startupRestoreGeneration = this.startupRestoreGeneration + 1;
    this.startupRestoreGeneration = startupRestoreGeneration;
    this.startupRestorePending = true;
    this.viewModel.restoreLastSession((): boolean => {
      return this.isPageLifecycleCurrent(lifecycleGeneration) &&
        restoreGeneration === this.pendingNavigationGeneration &&
        startupRestoreGeneration === this.startupRestoreGeneration &&
        this.startupRestorePending && this.pendingUrl.trim().length === 0;
    })
      .then((state: BrowserPageViewState) => {
        if (!this.isPageLifecycleCurrent(lifecycleGeneration) ||
          restoreGeneration !== this.pendingNavigationGeneration ||
          startupRestoreGeneration !== this.startupRestoreGeneration ||
          !this.startupRestorePending || this.pendingUrl.trim().length > 0) {
          return;
        }
        this.startupRestoreApplying = true;
        try {
          this.applyViewState(state, !state.showHome);
          // 恢复出的活跃标签若是空白新标签页，地址栏同样自动聚焦。
          this.focusAddressBarAfterStartup(state);
        } finally {
          this.startupRestoreApplying = false;
          this.startupRestorePending = false;
        }
      })
      .catch(() => {
        if (!this.isPageLifecycleCurrent(lifecycleGeneration) ||
          restoreGeneration !== this.pendingNavigationGeneration ||
          startupRestoreGeneration !== this.startupRestoreGeneration ||
          !this.startupRestorePending || this.pendingUrl.trim().length > 0) {
          return;
        }
        this.startupRestoreApplying = true;
        try {
          const fallbackState = this.viewModel.getInitialState();
          this.applyViewState(fallbackState, false);
          this.focusAddressBarAfterStartup(fallbackState);
        } finally {
          this.startupRestoreApplying = false;
          this.startupRestorePending = false;
        }
      });
  }

  private isPageLifecycleCurrent(generation: number = this.pageLifecycleGeneration): boolean {
    return this.pageVisible && generation === this.pageLifecycleGeneration;
  }

  private invalidatePendingStartupRestore(reason: string): void {
    if (!this.startupRestorePending || this.startupRestoreApplying) {
      return;
    }
    this.startupRestorePending = false;
    this.startupRestoreGeneration += 1;
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'SESSION_RESTORE_CANCEL reason=%{public}s generation=%{public}d',
      reason, this.startupRestoreGeneration);
  }

  private titleButtonRectListener: (info: WindowTitleButtonRectInfo) => void = (info: WindowTitleButtonRectInfo) => {
    this.titleButtonAreaWidth = info.width > 0 ? info.width : 0;
    if (this.showBookmarksSubMenu) {
      this.updateBookmarksSubMenuAnchor();
    }
    if (this.showUaSubMenu) {
      this.updateUaSubMenuAnchor();
    }
  }

  private refreshDownloadIndicator(): void {
    this.downloadIndicator = this.downloadManager.getIndicatorSnapshot();
  }

  private getTabStripBackgroundColor(): string {
    return this.viewState.isPrivate ? '#1f232b' : '#E6E6E6';
  }

  private getToolbarBackgroundColor(): string {
    return this.viewState.isPrivate ? '#252a33' : '#ffffff';
  }

  private getToolbarBorderColor(): string {
    return this.viewState.isPrivate ? '#343b48' : '#e2e5ea';
  }

  private getBookmarkBarBackgroundColor(): string {
    return this.viewState.isPrivate ? '#20242d' : '#ffffff';
  }

  private getPageBackgroundColor(): string {
    return this.viewState.isPrivate ? '#202227' : '#ffffff';
  }

  private countPrivateTabs(tabs: Tab[]): number {
    let count = 0;
    tabs.forEach((tab: Tab) => {
      if (tab.isPrivate) {
        count += 1;
      }
    });
    return count;
  }

  private syncPrivateSessionOwner(privateTabCount: number): void {
    const shouldBeActive = privateTabCount > 0;
    if (shouldBeActive === this.privateSessionOwnerActive) {
      return;
    }
    if (shouldBeActive) {
      this.privateSessionCoordinator.acquire(this.privateSessionOwnerId);
      this.privateSessionOwnerActive = true;
      return;
    }
    this.privateSessionCoordinator.release(this.privateSessionOwnerId);
    this.privateSessionOwnerActive = false;
  }

  private releasePrivateSessionOwner(): void {
    if (!this.privateSessionOwnerActive) {
      return;
    }
    this.privateSessionCoordinator.release(this.privateSessionOwnerId);
    this.privateSessionOwnerActive = false;
  }

  private applyBrowserSettingsChange(settings: BrowserSettings, forceApplyPageDefaults: boolean = false): void {
    this.appliedWebSettings = this.webSettingsAdapter.getAppliedWebSettings();
    this.applyCookieSettings();
    this.clearRequestedUrlsForAllTabs();
    // UA 标识跨启动持久化：启动时存储异步加载完成会经 notify 走到这里，
    // 把上次选择的 UA 恢复到 selectedUaMode；若 Web 运行时已创建则整体重建，
    // 保证恢复后首个请求即携带正确 UA（与菜单内切换同一套重建流程）。
    const persistedUaMode = this.uaManager.normalizeMode(settings.uaMode);
    if (persistedUaMode !== this.selectedUaMode) {
      this.selectedUaMode = persistedUaMode;
      hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
        'UA_RESTORE mode=%{public}s action=recreate_web_context', persistedUaMode);
      this.restartWebRuntimesForUaMode();
    }
    const defaultZoomPercent = this.clampPageZoomPercent(settings.defaultZoomPercent);
    if (forceApplyPageDefaults || defaultZoomPercent !== this.lastDefaultZoomPercent) {
      this.pageZoomPercent = defaultZoomPercent;
      this.applyPageZoom();
    }
    this.lastDefaultZoomPercent = defaultZoomPercent;
  }

  private applyCookieSettings(): void {
    const settings: AppliedCookieSettings = this.webSettingsAdapter.getAppliedCookieSettings();
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(settings.acceptCookies);
    } catch (_) {
    }

    try {
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(settings.acceptThirdPartyCookies);
    } catch (_) {
    }
  }

  private permissionPromptListener: (
    request: SitePermissionRequest | null
  ) => void = (request: SitePermissionRequest | null) => {
    if (!request) {
      this.showPermissionDialog = false;
      this.permissionRequest = EMPTY_PERMISSION_REQUEST;
      this.permissionRememberChoice = false;
      this.permissionDecisionPending = false;
      return;
    }

    this.permissionRequest = request;
    this.permissionRememberChoice = request.rememberChoiceDefault;
    this.permissionDecisionPending = false;
    this.closeMainMenu();
    if (this.showFindPanel) {
      this.closeFindPanel();
    }
    if (this.showAddressSuggestions || this.isAddressEditing) {
      this.cancelAddressEditing();
    }
    this.showPermissionDialog = true;
    this.tracePermission('BROWSER_PERMISSION_PROMPT_SHOWN',
      `requestId=${request.requestId} type=${request.permissionType} origin=${request.origin} prompt=custom`);
  }

  aboutToAppear(): void {
    this.pageLifecycleGeneration += 1;
    this.pageVisible = true;
    this.normalizeEmbeddedSettingsRoute();
    this.windowManager.bind(this.getUIContext())
      .then(() => this.windowManager.enableImmersiveTitleBar(this.getUIContext()))
      .then(() => this.windowManager.subscribeTitleButtonRectChange(this.getUIContext(), this.titleButtonRectListener))
      .catch(() => {
      });
    this.downloadManager.setHostContext(this.getUIContext().getHostContext());
    this.downloadManager.addListener(this.downloadListener);
    this.bookmarkManager.addListener(this.bookmarkListener);
    SettingsManager.getInstance().addListener(this.settingsListener);
    this.applyBrowserSettingsChange(SettingsManager.getInstance().getSettings(), true);
    this.refreshBookmarkBarItems();
    this.refreshDownloadIndicator();

    // Inject SDK source if preloaded by EntryAbility.
    const sdk = ScriptStore.getCachedJsBridgeSdk();
    if (sdk) {
      this.webViewManager.setSdkSource(sdk);
    }

    // Subscribe native lifecycle events.
    appLifecycleEvents.on(this.appLifecycleListener);
    memoryPressureEvents.on(this.memoryPressureListener);
    this.handleMemoryPressure({ level: getCurrentMemoryPressureLevel(), ts: Date.now() });
    this.permissionManager.addPromptListener(this.permissionPromptListener);
    this.permissionPromptListener(this.permissionManager.getActiveRequest());
    this.applyViewState(this.viewModel.getInitialState(), false, true, false);
    this.restoreSessionOnStart();
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    if (this.pendingJavaScriptDialog) {
      this.resolveJavaScriptDialog(false);
    }
    this.pageLifecycleGeneration += 1;
    this.invalidatePendingStartupRestore('page_disappear');
    // Unsubscribe to avoid leaking listeners across page recreations.
    this.persistSession();
    this.releasePrivateSessionOwner();
    appLifecycleEvents.off(this.appLifecycleListener);
    memoryPressureEvents.off(this.memoryPressureListener);
    this.permissionManager.removePromptListener(this.permissionPromptListener);
    this.downloadManager.removeListener(this.downloadListener);
    this.bookmarkManager.removeListener(this.bookmarkListener);
    SettingsManager.getInstance().removeListener(this.settingsListener);
    this.webOpenedTabIds.clear();
    this.webRuntimeStateByTabId.clear();
    this.navigationStateSettlingUntilByTabId.clear();
    this.pendingNativeNavigationByTabId.clear();
    this.nativeNavigationCommandSequenceByTabId.clear();
    this.nativeNavigationCommandTokenByTabId.clear();
    this.nativeNavigationCommandRuntimeRevisionByTabId.clear();
    this.nativeNavigationInitialUrlByTabId.clear();
    this.nativeNavigationTargetUrlByTabId.clear();
    this.mediaProbeSequenceByTabId.clear();
    this.mediaProbeStateByTabId.clear();
    this.mediaKernelPlayingByTabId.clear();
    this.mediaDomPlayingByTabId.clear();
    this.tabMediaBridges.clear();
    this.pendingSourceViewerByTabId.clear();
    this.lastFindTextByTabId.clear();
    this.releaseOwnedRuntimeFavicons(this.runtimeTabFavicons);
    this.runtimeTabFavicons = [];
    this.faviconDataUriByTabId.clear();
    this.faviconDataUriByUrl.clear();
    this.faviconGenerationByTabId.clear();
    this.faviconGenerationExpectedUrlByTabId.clear();
    this.faviconGenerationAwaitingPageBeginByTabId.clear();
    this.runtimeFaviconUrlByTabId.clear();
    this.runtimeFaviconSourceByTabId.clear();
    this.pendingFaviconUrlByTabId.clear();
    this.faviconCaptureSequenceByTabId.clear();
    this.titleReceiveSequenceByTabId.clear();
    this.skipNextHistoryRecordTabIds.clear();
    this.browserWebErrors = [];
    this.webViewManager.destroyAll();
  }

  // 首页搜索框提交时导航
  private navigateFromHome(text: string): void {
    this.handleAddressSubmit(text);
  }

  private goBack(): void {
    this.invalidatePendingStartupRestore('toolbar_back');
    const activeTabId = this.viewModel.getActiveTabId();
    if (!activeTabId) {
      return;
    }
    const activeTabKey = String(activeTabId);
    const pendingDirection = this.pendingNativeNavigationByTabId.get(activeTabKey);
    if (pendingDirection) {
      this.traceNavigationState('NAV_BACK_IGNORED', activeTabId, null,
        `reason=native_navigation_pending direction=${pendingDirection}`);
      return;
    }
    this.clearTabBrowserWebError(activeTabId);
    const controller = this.getActiveController();
    const controllerNavigation = controller ? this.readControllerNavigationState(controller) : null;
    this.traceNavigationState('NAV_BACK_CLICK', activeTabId, controllerNavigation);
    // A controller can briefly report false while its history list is being
    // attached or while a navigation is settling. Keep app-side history as a
    // positive hint so a valid action is not blocked by a transient read.
    const snapshotMatchesTab = controllerNavigation !== null &&
      this.isNavigationSnapshotCurrent(activeTabId, controllerNavigation);
    const settlingUntil = activeTabId ?
      (this.navigationStateSettlingUntilByTabId.get(String(activeTabId)) ?? 0) : 0;
    const nativeSnapshotAuthoritative = snapshotMatchesTab && settlingUntil <= Date.now();
    this.traceNavigationState('NAV_BACK_DECISION', activeTabId, controllerNavigation,
      `snapshotCurrent=${snapshotMatchesTab} authoritative=${nativeSnapshotAuthoritative} ` +
      `appCanBack=${this.viewState.canGoBack}`);
    const activeTab = this.findTab(activeTabId);
    const appCanGoBack = activeTab?.canGoBack === true || this.viewState.canGoBack || this.navCanGoBack;
    const canUseControllerBack = controller !== null && controllerNavigation !== null &&
      (controllerNavigation.canGoBack ||
        appCanGoBack);
    if (canUseControllerBack) {
      const commandToken = this.beginNativeNavigationCommand(activeTabId, 'back');
      try {
        this.beginTabControllerNavigation(activeTabId as TabId,
          this.nativeNavigationTargetUrlByTabId.get(activeTabKey) ?? '');
        controller.backward();
        // Mark the tab loading after the native call succeeds. This prevents
        // the immediate state refresh from reading the controller's still-
        // current (pre-back) history entry.
        this.applyViewState(this.viewModel.reloadActiveTab(), false, false);
        setTimeout(() => {
          this.handleNativeNavigationTimeout(activeTabId as TabId, 'back', commandToken);
        }, NAVIGATION_STATE_SETTLE_MS + 1000);
      } catch (_) {
        this.clearNativeNavigationCommand(activeTabId as TabId, 'back', commandToken, false);
        this.fallbackToModelNavigation(activeTabId as TabId, 'back');
      }
      this.scheduleActiveNavigationStateRefresh();
      return;
    }

    if (appCanGoBack) {
      this.fallbackToModelNavigation(activeTabId as TabId, 'back');
      return;
    }

    this.scheduleActiveNavigationStateRefresh();
  }

  private goForward(): void {
    this.invalidatePendingStartupRestore('toolbar_forward');
    const activeTabId = this.viewModel.getActiveTabId();
    if (!activeTabId) {
      return;
    }
    const activeTabKey = String(activeTabId);
    const pendingDirection = this.pendingNativeNavigationByTabId.get(activeTabKey);
    if (pendingDirection) {
      this.traceNavigationState('NAV_FORWARD_IGNORED', activeTabId, null,
        `reason=native_navigation_pending direction=${pendingDirection}`);
      return;
    }
    this.clearTabBrowserWebError(activeTabId);
    const controller = this.getActiveController();
    const controllerNavigation = controller ? this.readControllerNavigationState(controller) : null;
    this.traceNavigationState('NAV_FORWARD_CLICK', activeTabId, controllerNavigation);
    const snapshotMatchesTab = controllerNavigation !== null &&
      this.isNavigationSnapshotCurrent(activeTabId, controllerNavigation);
    const settlingUntil = activeTabId ?
      (this.navigationStateSettlingUntilByTabId.get(String(activeTabId)) ?? 0) : 0;
    const nativeSnapshotAuthoritative = snapshotMatchesTab && settlingUntil <= Date.now();
    this.traceNavigationState('NAV_FORWARD_DECISION', activeTabId, controllerNavigation,
      `snapshotCurrent=${snapshotMatchesTab} authoritative=${nativeSnapshotAuthoritative} ` +
      `appCanForward=${this.viewState.canGoForward}`);
    const activeTab = this.findTab(activeTabId);
    const appCanGoForward = activeTab?.canGoForward === true || this.viewState.canGoForward || this.navCanGoForward;
    const canUseControllerForward = controller !== null && controllerNavigation !== null &&
      (controllerNavigation.canGoForward ||
        appCanGoForward);
    if (canUseControllerForward) {
      const commandToken = this.beginNativeNavigationCommand(activeTabId, 'forward');
      try {
        this.beginTabControllerNavigation(activeTabId as TabId,
          this.nativeNavigationTargetUrlByTabId.get(activeTabKey) ?? '');
        controller.forward();
        // See goBack(): native forward() completes asynchronously.
        this.applyViewState(this.viewModel.reloadActiveTab(), false, false);
        setTimeout(() => {
          this.handleNativeNavigationTimeout(activeTabId as TabId, 'forward', commandToken);
        }, NAVIGATION_STATE_SETTLE_MS + 1000);
      } catch (_) {
        this.clearNativeNavigationCommand(activeTabId as TabId, 'forward', commandToken, false);
        this.fallbackToModelNavigation(activeTabId as TabId, 'forward');
      }
      this.scheduleActiveNavigationStateRefresh();
      return;
    }

    if (appCanGoForward) {
      this.fallbackToModelNavigation(activeTabId as TabId, 'forward');
      return;
    }

    this.scheduleActiveNavigationStateRefresh();
  }

  private beginNativeNavigationCommand(tabId: TabId, direction: PendingNativeNavigation): number {
    const key = String(tabId);
    const token = (this.nativeNavigationCommandSequenceByTabId.get(key) ?? 0) + 1;
    const tab = this.findTab(tabId);
    const initialUrl = tab?.url?.trim() ?? '';
    const targetUrl = direction === 'back' ? this.viewModel.peekBack(tabId) : this.viewModel.peekForward(tabId);
    this.nativeNavigationCommandSequenceByTabId.set(key, token);
    this.nativeNavigationCommandTokenByTabId.set(key, token);
    this.nativeNavigationCommandRuntimeRevisionByTabId.set(key, this.currentRuntimeRevision(tabId));
    this.nativeNavigationInitialUrlByTabId.set(key, initialUrl);
    this.nativeNavigationTargetUrlByTabId.set(key, targetUrl?.trim() ?? '');
    this.pendingNativeNavigationByTabId.set(key, direction);
    this.traceNavigationState('NAV_NATIVE_COMMAND_BEGIN', tabId, null,
      `direction=${direction} commandToken=${token} runtimeRevision=${this.currentRuntimeRevision(tabId)} ` +
      `initialUrl=${initialUrl || 'none'} targetUrl=${targetUrl || 'none'}`);
    return token;
  }

  private clearNativeNavigationCommand(
    tabId: TabId,
    direction: PendingNativeNavigation,
    token: number,
    timedOut: boolean,
  ): boolean {
    const key = String(tabId);
    if (this.pendingNativeNavigationByTabId.get(key) !== direction ||
      this.nativeNavigationCommandTokenByTabId.get(key) !== token) {
      return false;
    }
    this.pendingNativeNavigationByTabId.delete(key);
    this.nativeNavigationCommandTokenByTabId.delete(key);
    this.nativeNavigationCommandRuntimeRevisionByTabId.delete(key);
    this.nativeNavigationInitialUrlByTabId.delete(key);
    this.nativeNavigationTargetUrlByTabId.delete(key);
    this.traceNavigationState('NAV_NATIVE_COMMAND_CLEAR', tabId, null,
      `direction=${direction} commandToken=${token} reason=${timedOut ? 'timeout' : 'completed_or_failed'}`);
    if (this.isActiveTabId(tabId)) {
      this.scheduleActiveNavigationStateRefresh();
    }
    return true;
  }

  private cancelPendingNativeNavigation(tabId: TabId, reason: string): boolean {
    const key = String(tabId);
    const direction = this.pendingNativeNavigationByTabId.get(key);
    if (!direction) {
      return false;
    }
    const token = this.nativeNavigationCommandTokenByTabId.get(key) ?? 0;
    const runtimeRevision = this.nativeNavigationCommandRuntimeRevisionByTabId.get(key) ?? 0;
    this.pendingNativeNavigationByTabId.delete(key);
    this.nativeNavigationCommandTokenByTabId.delete(key);
    this.nativeNavigationCommandRuntimeRevisionByTabId.delete(key);
    this.nativeNavigationInitialUrlByTabId.delete(key);
    this.nativeNavigationTargetUrlByTabId.delete(key);
    this.traceNavigationState('NAV_NATIVE_COMMAND_CANCEL', tabId, null,
      `direction=${direction} commandToken=${token} commandRuntimeRevision=${runtimeRevision} ` +
      `currentRuntimeRevision=${this.currentRuntimeRevision(tabId)} reason=${reason}`);
    if (this.isActiveTabId(tabId)) {
      this.scheduleActiveNavigationStateRefresh();
    }
    return true;
  }

  private handleNativeNavigationTimeout(
    tabId: TabId,
    direction: PendingNativeNavigation,
    token: number,
  ): void {
    const key = String(tabId);
    if (this.pendingNativeNavigationByTabId.get(key) !== direction ||
      this.nativeNavigationCommandTokenByTabId.get(key) !== token) {
      return;
    }

    const initialUrl = this.nativeNavigationInitialUrlByTabId.get(key) ?? '';
    const targetUrl = this.nativeNavigationTargetUrlByTabId.get(key) ?? '';
    const runtime = this.webViewManager.get(tabId);
    const runtimeRevision = this.nativeNavigationCommandRuntimeRevisionByTabId.get(key) ?? 0;
    if (!runtime || runtime.revision !== runtimeRevision) {
      this.clearNativeNavigationCommand(tabId, direction, token, true);
      this.traceNavigationState('NAV_NATIVE_TIMEOUT_IGNORED', tabId, null,
        `direction=${direction} commandToken=${token} reason=runtime_unavailable`);
      return;
    }

    const controllerUrl = this.readControllerUrl(runtime.controller);
    const navigationState = this.readControllerNavigationState(runtime.controller);
    const observedUrl = controllerUrl || navigationState.historyUrl;
    const movedFromInitial = initialUrl.length > 0 && observedUrl.length > 0 &&
      !isSameHttpNavigationUrl(initialUrl, observedUrl);
    const reachedExpectedTarget = targetUrl.length > 0 && observedUrl.length > 0 &&
      isSameHttpNavigationUrl(targetUrl, observedUrl);

    this.traceNavigationState('NAV_NATIVE_TIMEOUT_CHECK', tabId, navigationState,
      `direction=${direction} commandToken=${token} initialUrl=${initialUrl || 'none'} ` +
      `targetUrl=${targetUrl || 'none'} observedUrl=${observedUrl || 'none'} ` +
      `reachedExpectedTarget=${String(reachedExpectedTarget)} movedFromInitial=${String(movedFromInitial)}`);

    this.clearNativeNavigationCommand(tabId, direction, token, true);
    if (reachedExpectedTarget || movedFromInitial) {
      this.reconcileNativeNavigationWithoutCallbacks(tabId, runtime, observedUrl, direction);
      return;
    }
    if (targetUrl.length > 0 && (observedUrl.length === 0 || isSameHttpNavigationUrl(initialUrl, observedUrl))) {
      this.traceNavigationState('NAV_MODEL_FALLBACK_TIMEOUT', tabId, navigationState,
        `direction=${direction} commandToken=${token} reason=native_target_not_reached`);
      this.fallbackToModelNavigation(tabId, direction);
      return;
    }
    this.traceNavigationState('NAV_NATIVE_TIMEOUT_AMBIGUOUS', tabId, navigationState,
      `direction=${direction} commandToken=${token} reason=observed_url_not_classified`);
    if (this.isActiveTabId(tabId)) {
      this.scheduleActiveNavigationStateRefresh();
    }
  }

  private reconcileNativeNavigationWithoutCallbacks(
    tabId: TabId,
    runtime: WebRuntime,
    url: string,
    direction: PendingNativeNavigation,
  ): void {
    if (!url || !this.isHttpUrl(url) || !this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab || !this.isPageLifecycleCurrent()) {
      return;
    }
    this.clearTabBrowserWebError(tabId);
    // Rebuild the app-side navigation snapshot from the URL observed in the
    // native history. This path is only used after the command timeout, so it
    // prevents a successful native move with missing callbacks from leaving
    // the model at the old history position.
    this.markTabLoadCommitted(tabId, url);
    this.markTabLoadCompleted(tabId, url);
    let title = '';
    try {
      title = runtime.controller.getTitle()?.trim() ?? '';
    } catch (_) {
    }
    this.traceNavigationState('NAV_NATIVE_RECONCILED', tabId, null,
      `direction=${direction} url=${url} title=${title || 'empty'}`);
    this.applyViewState(this.viewModel.updateTabFromPageEnd(
      tabId,
      url,
      title.length > 0 ? title : undefined,
    ), false, false);
    const navigationRevision = this.getTabNavigationRevision(tabId);
    this.navigationStateSettlingUntilByTabId.set(String(tabId), Date.now() + NAVIGATION_STATE_SETTLE_MS);
    this.scheduleTabFaviconCapture(tabId, runtime, navigationRevision);
    this.scheduleTabTitleCapture(tabId, runtime, url, navigationRevision);
    if (this.isActiveTabId(tabId)) {
      this.scheduleActiveNavigationStateRefresh();
    }
  }

  private fallbackToModelNavigation(tabId: TabId, direction: PendingNativeNavigation): void {
    const currentUrl = this.findTab(tabId)?.url ?? '';
    const nextState = direction === 'back' ? this.viewModel.goBack() : this.viewModel.goForward();
    const nextTab = nextState.tabs.find((tab: Tab) => String(tab.id) === String(tabId));
    if (!nextTab || isSameHttpDocumentUrl(nextTab.url, currentUrl)) {
      this.traceNavigationState('NAV_MODEL_FALLBACK_IGNORED', tabId, null,
        `direction=${direction} reason=no_distinct_target`);
      return;
    }
    this.traceNavigationState('NAV_MODEL_FALLBACK', tabId, null,
      `direction=${direction} targetUrl=${nextTab.url}`);
    this.applyViewState(nextState, !nextState.showHome);
  }

  private readControllerNavigationState(controller: webview.WebviewController): ControllerNavigationState {
    let canGoBack = false;
    let canGoForward = false;
    let accessBackward = false;
    let accessForward = false;
    let accessBackwardKnown = false;
    let accessForwardKnown = false;
    let accessBackwardRead = false;
    let accessForwardRead = false;
    let historyIndex = -1;
    let historySize = -1;
    let historyUrl = '';
    let hasHistorySnapshot = false;

    try {
      accessBackwardRead = controller.accessBackward();
      accessBackward = accessBackwardRead;
      accessBackwardKnown = true;
      canGoBack = accessBackward;
    } catch (_) {
      try {
        accessBackwardRead = controller.accessStep(-1);
        accessBackward = accessBackwardRead;
        accessBackwardKnown = true;
        canGoBack = accessBackwardRead;
      } catch (_) {
      }
    }

    try {
      accessForwardRead = controller.accessForward();
      accessForward = accessForwardRead;
      accessForwardKnown = true;
      canGoForward = accessForward;
    } catch (_) {
      try {
        accessForwardRead = controller.accessStep(1);
        accessForward = accessForwardRead;
        accessForwardKnown = true;
        canGoForward = accessForwardRead;
      } catch (_) {
      }
    }

    try {
      const entries = controller.getBackForwardEntries();
      historyIndex = entries.currentIndex;
      historySize = entries.size;
      if (historyIndex >= 0 && historyIndex < historySize) {
        try {
          historyUrl = entries.getItemAtIndex(historyIndex).historyUrl.trim();
        } catch (_) {
        }
      }
      // A complete native history snapshot is the only source that can
      // reliably clear a previously enabled direction at a history edge.
      // accessBackward/accessForward are still useful positive hints while a
      // Web component is being attached, but their false result is ambiguous
      // until the snapshot is available.
      // A numeric list is not enough to identify the current document. The
      // URL of the current entry lets us reject a snapshot left over from a
      // previous tab navigation while ArkWeb is still settling.
      hasHistorySnapshot = historyIndex >= 0 && historySize > 0 && historyUrl.length > 0;
      if (hasHistorySnapshot) {
        canGoBack = historyIndex > 0;
        canGoForward = historyIndex < historySize - 1;
      }
    } catch (_) {
    }

    return {
      canGoBack,
      canGoForward,
      hasHistorySnapshot,
      accessBackward,
      accessForward,
      accessBackwardKnown,
      accessForwardKnown,
      historyIndex,
      historySize,
      historyUrl,
    };
  }

  private isNavigationSnapshotCurrent(tabId: TabId | null, state: ControllerNavigationState | null): boolean {
    if (!tabId || !state || !state.hasHistorySnapshot || state.historyUrl.length === 0) {
      return false;
    }
    const tabUrl = this.findTab(tabId)?.url ?? '';
    return this.isHttpUrl(tabUrl) && isSameHttpDocumentUrl(state.historyUrl, tabUrl);
  }

  private syncTabNavigationStateFromController(tabId: TabId): void {
    if (!this.pageVisible) {
      return;
    }
    const tab = this.viewState.tabs.find((item: Tab) => String(item.id) === String(tabId));
    if (!tab) {
      return;
    }

    if (tab.loadState === 'home') {
      this.applyViewState(this.viewModel.updateNavigationState(tabId, false, false), false, false);
      return;
    }

    // During a navigation the controller commonly still reports the previous
    // document (address submission and backward()/forward() are asynchronous).
    // PageBegin has already synchronized the app history from the new URL, so
    // accepting the stale controller result here can briefly disable/enable
    // the wrong button. Reconcile with native history after PageEnd instead.
    if (tab.isLoading) {
      this.traceNavigationState('NAV_STATE_SKIP', tabId, null, 'reason=tab_loading');
      return;
    }

    const runtime = this.webViewManager.get(tabId);
    if (!runtime) {
      this.applyViewState(this.viewModel.updateNavigationState(tabId, tab.canGoBack, tab.canGoForward), false, false);
      return;
    }

    const navigationState = this.readControllerNavigationState(runtime.controller);
    this.traceNavigationState('NAV_STATE_SYNC', tabId, navigationState,
      `appBack=${tab.canGoBack} appForward=${tab.canGoForward}`);
    // A matching, settled native snapshot is authoritative and can clear a
    // direction at a history edge. While ArkWeb is still publishing the new
    // entry, retain app-confirmed history and only use native true values as
    // recovery hints for restored/unseeded tabs.
    const snapshotMatchesTab = this.isNavigationSnapshotCurrent(tabId, navigationState);
    const settlingUntil = this.navigationStateSettlingUntilByTabId.get(String(tabId)) ?? 0;
    const isSettling = settlingUntil > Date.now();
    const hasPendingNativeNavigation = this.pendingNativeNavigationByTabId.has(String(tabId));
    const pendingCommandRuntimeRevision = this.nativeNavigationCommandRuntimeRevisionByTabId.get(String(tabId));
    const currentRuntimeRevision = this.currentRuntimeRevision(tabId);
    if (hasPendingNativeNavigation && pendingCommandRuntimeRevision !== undefined &&
      pendingCommandRuntimeRevision !== currentRuntimeRevision) {
      this.cancelPendingNativeNavigation(tabId, 'runtime_revision_changed');
    }
    const effectiveHasPendingNativeNavigation = this.pendingNativeNavigationByTabId.has(String(tabId));
    // Only a toolbar back/forward action gives the native list authority to
    // clear app-side state. For ordinary page links, NavigationController is
    // the reliable source because ArkWeb may expose a stale/incomplete list.
    const nativeSnapshotAuthoritative = snapshotMatchesTab && !isSettling &&
      effectiveHasPendingNativeNavigation;
    if (nativeSnapshotAuthoritative && effectiveHasPendingNativeNavigation) {
      const pendingDirection = this.pendingNativeNavigationByTabId.get(String(tabId));
      this.pendingNativeNavigationByTabId.delete(String(tabId));
      this.nativeNavigationCommandTokenByTabId.delete(String(tabId));
      this.nativeNavigationCommandRuntimeRevisionByTabId.delete(String(tabId));
      this.nativeNavigationInitialUrlByTabId.delete(String(tabId));
      this.nativeNavigationTargetUrlByTabId.delete(String(tabId));
      this.traceNavigationState('NAV_NATIVE_COMMAND_SETTLED', tabId, navigationState,
        `direction=${pendingDirection ?? 'none'} reason=native_snapshot`);
    }
    const canGoBack = nativeSnapshotAuthoritative ? navigationState.canGoBack :
      (tab.canGoBack || navigationState.canGoBack);
    const canGoForward = nativeSnapshotAuthoritative ? navigationState.canGoForward :
      (tab.canGoForward || navigationState.canGoForward);
    if (isSettling || effectiveHasPendingNativeNavigation) {
      this.traceNavigationState('NAV_STATE_SETTLING', tabId, navigationState,
        `until=${settlingUntil} pending=${this.pendingNativeNavigationByTabId.get(String(tabId)) ?? 'none'} ` +
        `appBack=${tab.canGoBack} appForward=${tab.canGoForward}`);
    }
    this.applyViewState(this.viewModel.updateNavigationState(
      tabId,
      canGoBack,
      canGoForward,
    ), false, false);
  }

  private scheduleActiveNavigationStateRefresh(): void {
    const tabId = this.viewModel.getActiveTabId();
    if (!tabId) {
      return;
    }
    const lifecycleGeneration = this.pageLifecycleGeneration;
    const isRefreshStillValid = (): boolean => {
      return this.isPageLifecycleCurrent(lifecycleGeneration) &&
        String(this.viewModel.getActiveTabId()) === String(tabId) &&
        this.findTab(tabId) !== null;
    };
    Promise.resolve().then(() => {
      if (isRefreshStillValid()) {
        this.syncTabNavigationStateFromController(tabId);
      }
    });
    setTimeout(() => {
      if (isRefreshStillValid()) {
        this.syncTabNavigationStateFromController(tabId);
      }
    }, 120);
    // A second refresh runs after ArkWeb's history list has normally settled,
    // allowing the native snapshot to clear a direction at the real edge.
    setTimeout(() => {
      if (isRefreshStillValid()) {
        this.syncTabNavigationStateFromController(tabId);
      }
    }, NAVIGATION_STATE_SETTLE_MS + 80);
  }

  private reload(ignoreCache: boolean = false): void {
    this.invalidatePendingStartupRestore('toolbar_reload');
    const activeTabId = this.viewModel.getActiveTabId();
    const controller = this.getActiveController();
    if (!activeTabId || !controller) {
      return;
    }
    const url = this.findTab(activeTabId)?.url ?? '';
    if (!url || url === 'about:blank') {
      return;
    }
    const runtimeState = this.getTabWebRuntimeState(activeTabId);
    const shouldLoadExplicitly = runtimeState.lastError.length > 0 ||
      findBrowserWebError(this.browserWebErrors, String(activeTabId)) !== null ||
      runtimeState.committedUrl.length === 0;
    this.clearTabBrowserWebError(activeTabId);
    this.applyViewState(this.viewModel.reloadActiveTab(), false, false);
    if (!runtimeState.controllerAttached) {
      this.markTabLoadRequested(activeTabId, url);
      runtimeState.pendingUrl = url;
      runtimeState.updatedAt = Date.now();
      return;
    }
    if (ignoreCache) {
      // A UA change must issue a fresh navigation request. controller.refresh()
      // is allowed to reuse the existing navigation context on some ArkWeb
      // versions, which leaves the server seeing the previous UA.
      this.loadTabUrl(activeTabId, url, true);
      return;
    }
    if (shouldLoadExplicitly) {
      this.loadTabUrl(activeTabId, url, true);
      return;
    }
    this.markTabLoadRequested(activeTabId, url);
    try {
      controller.refresh();
    } catch (_) {
      this.invalidateTabFavicon(activeTabId);
      this.markTabLoadFailed(activeTabId, url);
      this.setTabBrowserWebError(createBrowserWebError({
        tabId: String(activeTabId),
        kind: 'network',
        url,
        errorCode: 'REFRESH_FAILED',
      }));
    }
  }

  private goHome(): void {
    this.invalidatePendingStartupRestore('toolbar_home');
    const nextState = this.viewModel.goHome();
    if (nextState.showHome) {
      const activeTabId = this.viewModel.getActiveTabId();
      if (activeTabId) {
        this.clearTabBrowserWebError(activeTabId);
        this.enterTabHome(activeTabId);
        this.invalidateTabFavicon(activeTabId);
      }
    }
    this.applyViewState(nextState, !nextState.showHome);
  }

  private handleNewTab(): void {
    this.invalidatePendingStartupRestore('new_tab');
    this.closeTransientOverlays();
    this.exitSettingsOverlayForNavigation();
    this.applyViewState(this.viewModel.newTab(), false);
    // 新标签页：地址栏自动进入编辑态并聚焦，方便直接输入搜索/网址。
    // 若此前正处于编辑态，先退出再重进，确保地址文本刷新为新标签页内容。
    if (this.isAddressEditing) {
      this.completeAddressEditing();
    }
    this.startAddressEditing();
  }

  // 暂时预留，后期完善：无痕标签页底层实现保留，暂不提供用户入口。
  private handleNewPrivateTab(): void {
    this.invalidatePendingStartupRestore('new_private_tab');
    this.closeTransientOverlays();
    this.applyViewState(this.viewModel.newTab(true), false);
  }

  // 暂时预留，后期完善：无痕窗口底层实现保留，暂不提供用户入口。
  private handleNewPrivateWindow(): void {
    this.closeTransientOverlays();
    this.windowManager.openPrivateWindow(this.getUIContext())
      .catch(() => {
        this.handleNewPrivateTab();
      });
  }

  private handleNewWindow(): void {
    this.closeTransientOverlays();
    this.windowManager.openNormalWindow(this.getUIContext())
      .catch(() => this.showOperationToast('无法打开新窗口'));
  }

  private handleTabSelect(tabId: TabId): void {
    this.invalidatePendingStartupRestore('select_tab');
    if (this.viewState.activeTabId === String(tabId)) {
      return;
    }
    this.closeTransientOverlays();
    this.exitSettingsOverlayForNavigation();
    const nextState = this.viewModel.selectTab(tabId);
    const shouldLoadWeb = !nextState.showHome && this.webViewManager.get(tabId) === null;
    this.applyViewState(nextState, shouldLoadWeb);
  }

  private handleTabClose(tabId: TabId): void {
    if (!this.viewModel.canCloseTab(tabId)) {
      this.showOperationToast('有未保存内容，无法关闭');
      return;
    }
    this.invalidatePendingStartupRestore('close_tab');
    if (this.pendingJavaScriptDialog?.tabId === String(tabId)) {
      this.resolveJavaScriptDialog(false);
    }
    const previousActiveTabId = this.viewState.activeTabId;
    this.webOpenedTabIds.delete(String(tabId));
    this.webPointerPositionByTabId.delete(String(tabId));
    this.lastFindTextByTabId.delete(String(tabId));
    this.clearTabWebRuntimeState(tabId);
    this.clearTabBrowserWebError(tabId);
    this.invalidateTabFavicon(tabId);
    this.faviconGenerationByTabId.delete(String(tabId));
    this.faviconGenerationExpectedUrlByTabId.delete(String(tabId));
    this.faviconGenerationAwaitingPageBeginByTabId.delete(String(tabId));
    this.runtimeFaviconUrlByTabId.delete(String(tabId));
    this.runtimeFaviconSourceByTabId.delete(String(tabId));
    this.pendingFaviconUrlByTabId.delete(String(tabId));
    this.faviconCaptureSequenceByTabId.delete(String(tabId));
    this.navigationStateSettlingUntilByTabId.delete(String(tabId));
    this.pendingNativeNavigationByTabId.delete(String(tabId));
    this.nativeNavigationCommandSequenceByTabId.delete(String(tabId));
    this.nativeNavigationCommandTokenByTabId.delete(String(tabId));
    this.nativeNavigationCommandRuntimeRevisionByTabId.delete(String(tabId));
    this.nativeNavigationInitialUrlByTabId.delete(String(tabId));
    this.nativeNavigationTargetUrlByTabId.delete(String(tabId));
    this.titleReceiveSequenceByTabId.delete(String(tabId));
    this.skipNextHistoryRecordTabIds.delete(String(tabId));
    this.releaseTabMediaBridge(tabId);
    this.faviconDataUriByTabId.delete(String(tabId));
    this.webViewManager.destroy(tabId);
    this.closeTransientOverlays();
    const nextState = this.viewModel.closeTab(tabId);
    const shouldLoadWeb = !nextState.showHome && previousActiveTabId !== nextState.activeTabId;
    this.applyViewState(nextState, shouldLoadWeb);
  }

  private handleCloseTabSet(tabIds: TabId[], reason: string): void {
    const closeableIds = tabIds.filter((tabId: TabId) => this.viewModel.canCloseTab(tabId));
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'TAB_BATCH_CLOSE reason=%{public}s requested=%{public}d closeable=%{public}d active=%{public}s',
      reason, tabIds.length, closeableIds.length, this.viewState.activeTabId);
    if (closeableIds.length === 0) {
      this.showOperationToast('没有可关闭的标签');
      return;
    }
    this.invalidatePendingStartupRestore(reason);
    const previousActiveTabId = this.viewState.activeTabId;
    closeableIds.forEach((tabId: TabId) => {
      const key = String(tabId);
      this.webOpenedTabIds.delete(key);
      this.webPointerPositionByTabId.delete(key);
      this.lastFindTextByTabId.delete(key);
      this.clearTabWebRuntimeState(tabId);
      this.clearTabBrowserWebError(tabId);
      this.invalidateTabFavicon(tabId);
      this.faviconGenerationByTabId.delete(key);
      this.faviconGenerationExpectedUrlByTabId.delete(key);
      this.faviconGenerationAwaitingPageBeginByTabId.delete(key);
      this.runtimeFaviconUrlByTabId.delete(key);
      this.runtimeFaviconSourceByTabId.delete(key);
      this.pendingFaviconUrlByTabId.delete(key);
      this.faviconCaptureSequenceByTabId.delete(key);
      this.navigationStateSettlingUntilByTabId.delete(key);
      this.pendingNativeNavigationByTabId.delete(key);
      this.nativeNavigationCommandSequenceByTabId.delete(key);
      this.nativeNavigationCommandTokenByTabId.delete(key);
      this.nativeNavigationCommandRuntimeRevisionByTabId.delete(key);
      this.nativeNavigationInitialUrlByTabId.delete(key);
      this.nativeNavigationTargetUrlByTabId.delete(key);
      this.titleReceiveSequenceByTabId.delete(key);
      this.releaseTabMediaBridge(tabId);
      this.faviconDataUriByTabId.delete(key);
      this.webViewManager.destroy(tabId);
    });
    this.closeTabContextMenu();
    const nextState = this.viewModel.closeTabs(closeableIds);
    const shouldLoadWeb = !nextState.showHome && previousActiveTabId !== nextState.activeTabId;
    this.applyViewState(nextState, shouldLoadWeb);
  }

  private getTabContextTarget(): Tab | null {
    return this.viewState.tabs.find((tab: Tab) => String(tab.id) === this.tabContextTargetId) ?? null;
  }

  private buildTabContextMenuItems(tab: Tab): BrowserContextMenuItem[] {
    const otherTabs = this.viewState.tabs.filter((item: Tab) => String(item.id) !== String(tab.id));
    const targetIndex = this.viewState.tabs.findIndex((item: Tab) => String(item.id) === String(tab.id));
    const rightTabs = targetIndex < 0 ? [] : this.viewState.tabs.slice(targetIndex + 1);
    const canClose = this.viewModel.canCloseTab(tab.id);
    return [
      { id: 'new_tab', label: '新建标签页', leadingIcon: '+' },
      // Always enabled: the tab's mute state is meaningful even while the page
      // is silent, and a disabled entry made the control look broken on pages
      // whose audio the kernel never reported.
      {
        id: 'mute_tab',
        label: tab.muted ? '取消此网页静音' : '使此网页静音',
        leadingIcon: tab.muted ? '🔊' : '🔇'
      },
      { id: 'close_tab', label: '关闭标签页', leadingIcon: '×', disabled: !canClose },
      { id: 'close_other_tabs', label: '关闭其他标签页', leadingIcon: '⊗', disabled: otherTabs.length === 0 },
      {
        id: 'close_tabs_to_right',
        label: '关闭右侧标签页',
        leadingIcon: '▷',
        disabled: rightTabs.length === 0
      },
      {
        id: 'reopen_closed_tab',
        label: '重新打开已关闭的标签页',
        leadingIcon: '↶',
        dividerBefore: true,
        disabled: !this.viewModel.canRestoreLastClosedTab()
      },
    ];
  }

  private getTabContextMenuHeight(): number {
    const dividerCount = this.tabContextMenuItems.filter((item: BrowserContextMenuItem) => item.dividerBefore).length;
    const preferredHeight = (this.tabContextMenuItems.length * 40) + (dividerCount * 10) + 16;
    return Math.min(360, Math.max(1, preferredHeight));
  }

  private resolveTabContextMenuPosition(position: TabContextMenuPosition): ContextMenuPosition {
    const menuWidth = 248;
    const menuHeight = this.getTabContextMenuHeight();
    const width = Math.max(1, this.viewportWidth);
    const height = Math.max(1, this.viewportHeight);
    const maxX = Math.max(8, width - menuWidth - 8);
    const maxY = Math.max(8, height - menuHeight - 8);
    const rawX = Number.isFinite(position.x) && position.x >= 0 ? position.x : 8;
    const rawY = Number.isFinite(position.y) && position.y >= 0 ? position.y : 40;
    // A tab click normally lands inside the 40px tab strip. Put the menu just
    // below the strip instead of covering the click target, while preserving
    // the mouse's horizontal alignment. If there is no room below, place it
    // above the pointer and clamp it to the page bounds.
    const preferredY = rawY < 40 ? 40 : rawY + 2;
    const y = preferredY + menuHeight <= height - 8 ? preferredY : rawY - menuHeight - 2;
    return {
      x: Math.max(8, Math.min(rawX, maxX)),
      y: Math.max(8, Math.min(y, maxY)),
    };
  }

  private handleTabContextMenu(tabId: TabId, index: number, position: TabContextMenuPosition): void {
    const runtime = this.webViewManager.get(tabId);
    if (runtime) {
      this.syncTabMediaState(tabId, runtime);
    }
    const target = this.viewState.tabs.find((tab: Tab) => String(tab.id) === String(tabId));
    if (!target) {
      return;
    }
    if (this.showContextMenu) {
      this.closeContextMenu();
    }
    this.closeMainMenu();
    this.tabContextTargetId = String(tabId);
    this.tabContextMenuItems = this.buildTabContextMenuItems(target);
    const resolvedPosition = this.resolveTabContextMenuPosition(position);
    this.tabContextMenuX = resolvedPosition.x;
    this.tabContextMenuY = resolvedPosition.y;
    this.showTabContextMenu = true;
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'TAB_CONTEXT_MENU_OPEN tab=%{public}s index=%{public}d x=%{public}d y=%{public}d ' +
      'audible=%{public}s muted=%{public}s',
      String(tabId), index, resolvedPosition.x, resolvedPosition.y,
      String(target.audible), String(target.muted));
  }

  private closeTabContextMenu(): void {
    this.showTabContextMenu = false;
    this.tabContextTargetId = '';
    this.tabContextMenuItems = [];
  }

  private handleTabContextMenuSelect(item: BrowserContextMenuItem): void {
    const target = this.getTabContextTarget();
    const targetId = this.tabContextTargetId;
    if (item.disabled) {
      return;
    }
    this.closeTabContextMenu();
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'TAB_CONTEXT_MENU_SELECT item=%{public}s target=%{public}s', item.id, targetId);
    if (item.id === 'new_tab') {
      this.handleNewTab();
      return;
    }
    if (item.id === 'reopen_closed_tab') {
      this.handleRestoreClosedTab();
      return;
    }
    if (!target) {
      return;
    }
    if (item.id === 'close_tab') {
      this.handleTabClose(target.id);
      return;
    }
    if (item.id === 'close_other_tabs') {
      const ids = this.viewState.tabs
        .filter((tab: Tab) => String(tab.id) !== String(target.id))
        .map((tab: Tab) => tab.id);
      this.handleCloseTabSet(ids, 'close_other_tabs');
      return;
    }
    if (item.id === 'close_tabs_to_right') {
      const targetIndex = this.viewState.tabs.findIndex((tab: Tab) => String(tab.id) === String(target.id));
      const ids = targetIndex < 0 ? [] : this.viewState.tabs.slice(targetIndex + 1).map((tab: Tab) => tab.id);
      this.handleCloseTabSet(ids, 'close_tabs_to_right');
      return;
    }
    if (item.id === 'mute_tab') {
      this.handleTabMuteToggle(target);
    }
  }

  private handleTabMuteIconClick(tabId: TabId): void {
    const tab = this.viewState.tabs.find((item: Tab) => String(item.id) === String(tabId));
    if (tab) {
      this.handleTabMuteToggle(tab);
    }
  }

  private handleTabMuteToggle(tab: Tab): void {
    const runtime = this.webViewManager.get(tab.id);
    if (!runtime) {
      this.showOperationToast('当前标签页尚未准备好');
      return;
    }
    const nextMuted = !tab.muted;
    try {
      runtime.controller.setAudioMuted(nextMuted);
      this.invalidatePendingStartupRestore('toggle_tab_mute');
      this.applyViewState(this.viewModel.updateTabMute(tab.id, nextMuted), false);
    } catch (_) {
      this.showOperationToast('当前设备不支持网页静音');
    }
  }

  private reapplyTabMuteToRuntime(tabId: TabId, runtime: WebRuntime): void {
    // ArkWeb applies muting per document. Re-assert the tab model's mute state
    // on every accepted navigation, otherwise a muted tab can start playing
    // audio again after the document swaps and the tab icon would be lying
    // about the audio state. Unmuted tabs need no native call.
    const tab = this.findTab(tabId);
    if (!tab || !tab.muted) {
      return;
    }
    try {
      runtime.controller.setAudioMuted(true);
    } catch (_) {
      // Older devices may expose the enum but reject the controller call.
    }
  }

  private ensureTabMediaBridge(tabId: TabId): TabMediaBridge {
    // The bridge instance must be stable for as long as the tab lives: ArkWeb
    // binds the proxy object when the Web component is created, and a swapped
    // instance would leave the page talking to an orphan.
    const key = String(tabId);
    const existing = this.tabMediaBridges.get(key);
    if (existing) {
      return existing;
    }
    const bridge = new TabMediaBridge(key, (id: string, playing: boolean): void => {
      this.handleTabMediaPlayingChanged(id, playing);
    });
    this.tabMediaBridges.set(key, bridge);
    return bridge;
  }

  private releaseTabMediaBridge(tabId: TabId): void {
    const key = String(tabId);
    this.tabMediaBridges.delete(key);
    this.mediaDomPlayingByTabId.delete(key);
    this.mediaKernelPlayingByTabId.delete(key);
    this.mediaProbeStateByTabId.delete(key);
    this.mediaProbeSequenceByTabId.delete(key);
  }

  private handleTabMediaPlayingChanged(tabId: TabId, playing: boolean): void {
    const key = String(tabId);
    if (this.mediaDomPlayingByTabId.get(key) === playing) {
      return;
    }
    this.mediaDomPlayingByTabId.set(key, playing);
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'TAB_MEDIA_DOM_STATE tab=%{public}s playing=%{public}s', key, String(playing));
    this.applyTabAudibleState(tabId);
  }

  private invalidateTabDomMediaState(tabId: TabId): void {
    // A new document starts a fresh copy of the injected monitor, so the answer
    // the previous document gave is stale until the new one reports.
    const key = String(tabId);
    if (this.mediaDomPlayingByTabId.get(key) !== true) {
      return;
    }
    this.mediaDomPlayingByTabId.set(key, false);
    this.applyTabAudibleState(tabId);
  }

  private applyTabAudibleState(tabId: TabId): void {
    // Two independent sources, unioned:
    // - the kernel (getMediaPlaybackState / onAudioStateChanged) knows what is
    //   actually audible, including in background tabs;
    // - the in-page monitor knows whether an <audio>/<video> is running at all,
    //   which is the only way to notice a video the page muted itself.
    // Either one being true is enough for the tab to expose its mute control.
    const key = String(tabId);
    const audible = this.mediaKernelPlayingByTabId.get(key) === true ||
      this.mediaDomPlayingByTabId.get(key) === true;
    const tab = this.findTab(tabId);
    if (!tab || tab.audible === audible) {
      return;
    }
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'TAB_MEDIA_STATE tab=%{public}s audible=%{public}s kernel=%{public}s dom=%{public}s',
      key, String(audible), String(this.mediaKernelPlayingByTabId.get(key) === true),
      String(this.mediaDomPlayingByTabId.get(key) === true));
    this.applyViewState(this.viewModel.updateTabAudio(tabId, audible), false, false);
  }

  private handleTabAudioStateChanged(tabId: TabId, event: OnAudioStateChangedEvent): void {
    // onAudioStateChanged is pushed by the kernel for every mounted Web
    // component, so background tabs that start or stop making sound are
    // reported too. The scheduled sweep below is only a fallback.
    const key = String(tabId);
    const audible = event.playing === true;
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'TAB_AUDIO_STATE tab=%{public}s playing=%{public}s', key, String(audible));
    if (this.mediaKernelPlayingByTabId.get(key) === audible) {
      return;
    }
    this.mediaKernelPlayingByTabId.set(key, audible);
    this.applyTabAudibleState(tabId);
  }

  private syncTabMediaState(tabId: TabId, runtime: WebRuntime): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    try {
      const playbackState = runtime.controller.getMediaPlaybackState();
      const key = String(tabId);
      if (this.mediaProbeStateByTabId.get(key) !== playbackState) {
        this.mediaProbeStateByTabId.set(key, playbackState);
        hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
          'TAB_MEDIA_PROBE tab=%{public}s state=%{public}d', key, playbackState);
      }
      const audible = playbackState === webview.MediaPlaybackState.PLAYING;
      if (this.mediaKernelPlayingByTabId.get(key) === audible) {
        return;
      }
      this.mediaKernelPlayingByTabId.set(key, audible);
      this.applyTabAudibleState(tabId);
    } catch (error) {
      // Older devices may expose the enum but reject the controller call. Log
      // it instead of swallowing: a silent failure here leaves every tab
      // without an audio indicator and looks exactly like a UI bug.
      hilog.warn(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
        'TAB_MEDIA_STATE_FAILED tab=%{public}s error=%{public}s',
        String(tabId), String(error));
    }
  }

  private scheduleTabMediaProbe(tabId: TabId, runtime: WebRuntime): void {
    const key = String(tabId);
    const sequence = (this.mediaProbeSequenceByTabId.get(key) ?? 0) + 1;
    this.mediaProbeSequenceByTabId.set(key, sequence);
    const pageGeneration = this.pageLifecycleGeneration;
    setTimeout(() => {
      if (!this.pageVisible || pageGeneration !== this.pageLifecycleGeneration ||
        this.mediaProbeSequenceByTabId.get(key) !== sequence || !this.isCurrentTabRuntime(tabId, runtime)) {
        return;
      }
      this.syncTabMediaState(tabId, runtime);
      if (this.findTab(tabId) !== null) {
        this.scheduleTabMediaProbe(tabId, runtime);
      }
    }, MEDIA_STATE_PROBE_INTERVAL_MS);
  }

  private handleRestoreClosedTab(): void {
    this.invalidatePendingStartupRestore('restore_closed_tab');
    const previousActiveTabId = this.viewState.activeTabId;
    const nextState = this.viewModel.restoreLastClosedTab();
    const shouldLoadWeb = !nextState.showHome && previousActiveTabId !== nextState.activeTabId;
    this.closeTransientOverlays();
    this.applyViewState(nextState, shouldLoadWeb);
  }

  private handleAddressDraftChange(value: string): void {
    this.invalidatePendingStartupRestore('address_edit');
    this.applyViewState(this.viewModel.updateAddressDraft(value), false);
    this.refreshAddressSuggestions(value);
  }

  private handleAddressSubmit(value: string): void {
    this.invalidatePendingStartupRestore('address_submit');
    this.exitSettingsOverlayForNavigation();
    const trimmedValue = value.trim();
    if (!trimmedValue) {
      this.completeAddressEditing();
      const nextState = this.viewModel.submitAddress('');
      this.applyViewState(nextState, false);
      return;
    }

    this.completeAddressEditing();
    const nextState = this.viewModel.submitAddress(value);
    this.applyViewState(nextState, !nextState.showHome);
    this.syncCurrentBookmarkState(nextState.currentUrl);
  }

  private handleAddressSuggestionSelect(suggestion: AddressSuggestion): void {
    this.invalidatePendingStartupRestore('address_suggestion_select');
    this.completeAddressEditing();
    if (suggestion.type === 'tab' && suggestion.targetTabId) {
      const targetTab = this.viewState.tabs.find((tab: Tab) => String(tab.id) === String(suggestion.targetTabId));
      if (targetTab) {
        this.handleTabSelect(targetTab.id);
        return;
      }
    }
    const nextState = this.viewModel.submitAddress(suggestion.targetUrl);
    this.applyViewState(nextState, !nextState.showHome);
    this.syncCurrentBookmarkState(nextState.currentUrl);
  }

  private handleBack(): void {
    this.closeTransientOverlays();
    this.exitSettingsOverlayForNavigation();
    this.goBack();
  }

  private handleForward(): void {
    this.closeTransientOverlays();
    this.exitSettingsOverlayForNavigation();
    this.goForward();
  }

  private handleReload(): void {
    this.closeTransientOverlays();
    this.exitSettingsOverlayForNavigation();
    this.reload();
  }

  private handleHome(): void {
    this.closeTransientOverlays();
    this.exitSettingsOverlayForNavigation();
    this.goHome();
  }

  private startAddressEditing(): void {
    if (this.isAddressEditing) {
      return;
    }
    if (this.showMainMenu) {
      this.closeMainMenu();
    }
    if (this.showFindPanel) {
      this.closeFindPanel();
    }
    this.addressText = this.viewState.currentUrl === 'about:blank' ? '' : this.viewState.currentUrl;
    this.isAddressEditing = true;
    // 全选交给 AddressBar 内部处理：editing 变化 → 等挂载 → 请求焦点 → onFocus 时 setTextSelection。
    // 此处微任务 requestFocus 跑在渲染之前（TextInput 未挂载）会静默失败，不在此处做全选。
    Promise.resolve().then(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(ADDRESS_BAR_INPUT_ID);
      } catch (_) {
      }
    });
  }

  private focusAddressBar(): void {
    this.closeTransientOverlays();
    if (!this.isAddressEditing) {
      this.startAddressEditing();
    }
    this.addressSelectionRevision += 1;
    Promise.resolve().then(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(ADDRESS_BAR_INPUT_ID);
      } catch (_) {
      }
    });
  }

  // 启动后若落在空白新标签页/主页，地址栏自动进入编辑态（与手动新建标签页行为一致）。
  // 焦点落地仍由 AddressBar 的 editing watch → 延迟 requestFocus 兜底，此处只负责切入编辑态。
  private focusAddressBarAfterStartup(state: BrowserPageViewState): void {
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'STARTUP_FOCUS showHome=%{public}s editing=%{public}s',
      String(state.showHome), String(this.isAddressEditing));
    if (!state.showHome) {
      return;
    }
    this.startAddressEditing();
  }

  private completeAddressEditing(): void {
    this.isAddressEditing = false;
    this.clearAddressSuggestions();
  }

  private cancelAddressEditing(): void {
    this.isAddressEditing = false;
    this.addressText = this.viewState.addressText;
    this.clearAddressSuggestions();
  }

  private getAddressDisplayText(): string {
    if (this.showHome) {
      return '';
    }
    return this.simplifyAddressForDisplay(this.viewState.currentUrl);
  }

  private simplifyAddressForDisplay(url: string): string {
    const trimmedUrl = url.trim();
    if (!trimmedUrl || trimmedUrl === 'about:blank') {
      return '';
    }

    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
      let simplifiedUrl = trimmedUrl.replace(/^https?:\/\//, '');
      simplifiedUrl = simplifiedUrl.replace(/^www\./i, '');
      if (simplifiedUrl.endsWith('/') && !simplifiedUrl.includes('?') && !simplifiedUrl.includes('#')) {
        simplifiedUrl = simplifiedUrl.slice(0, simplifiedUrl.length - 1);
      }
      return simplifiedUrl;
    }

    return trimmedUrl;
  }

  private canToggleCurrentPageBookmark(): boolean {
    const url = this.getCurrentBookmarkableUrl().trim().toLowerCase();
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private getCurrentBookmarkableUrl(): string {
    const currentUrl = this.viewState.currentUrl.trim();
    if (currentUrl && currentUrl !== 'about:blank') {
      return currentUrl;
    }
    return this.webSrc.trim();
  }

  private resolveCurrentPageFaviconUrl(): string | undefined {
    const activeTab = this.viewState.tabs.find((tab) => String(tab.id) === this.viewState.activeTabId);
    const cachedDataUri = this.faviconDataUriByTabId.get(String(activeTab?.id ?? ''));
    if (cachedDataUri) {
      return cachedDataUri;
    }
    return activeTab?.faviconUrl;
  }

  private handleToggleCurrentPageBookmark(): void {
    const url = this.getCurrentBookmarkableUrl();
    if (!this.canToggleCurrentPageBookmark()) {
      return;
    }
    this.bookmarkManager.toggleBookmark(url, this.resolveCurrentPageTitle(), this.resolveCurrentPageFaviconUrl());
    this.syncCurrentBookmarkState(url);
  }

  private resolveCurrentPageTitle(): string {
    const activeTab = this.viewState.tabs.find((tab) => String(tab.id) === this.viewState.activeTabId);
    if (activeTab && activeTab.title.trim().length > 0) {
      return activeTab.title;
    }
    return this.viewState.currentUrl;
  }

  private syncCurrentBookmarkState(url: string): void {
    const normalizedTargetUrl = url.trim().length > 0 ? url : this.getCurrentBookmarkableUrl();
    this.currentPageBookmarked = this.bookmarkManager.isBookmarked(normalizedTargetUrl);
  }

  /**
   * Star button entry. Chrome semantics: clicking the star when the page is
   * not bookmarked adds it immediately and opens the "已添加书签" dialog;
   * when already bookmarked it opens the same dialog as "修改书签".
   */
  private openBookmarkEditDialogForCurrentPage(): void {
    if (!this.canToggleCurrentPageBookmark() || this.showBookmarkEditDialog) {
      return;
    }
    const url = this.getCurrentBookmarkableUrl();
    const existing = this.bookmarkManager.getBookmark(url);
    let node = existing;
    if (node) {
      this.bookmarkEditDialogTitle = '修改书签';
    } else {
      node = this.bookmarkManager.addBookmark(url, this.resolveCurrentPageTitle(),
        this.resolveCurrentPageFaviconUrl());
      if (!node) {
        return;
      }
      this.bookmarkEditDialogTitle = '已添加书签';
    }
    this.bookmarkEditNodeId = node.id;
    this.bookmarkEditName = node.title;
    this.bookmarkEditFolderId = node.parentId;
    this.bookmarkEditFolderOptions = this.buildBookmarkEditFolderOptions();
    this.bookmarkEditFolderIndex =
      Math.max(0, this.bookmarkEditFolderOptions.findIndex((option: BookmarkEditFolderOption) =>
        option.id === this.bookmarkEditFolderId));
    this.updateBookmarkEditDialogAnchor();
    this.syncCurrentBookmarkState(url);
    this.showBookmarkEditDialog = true;
  }

  /**
   * Anchor the popover right under the address-bar star. Coordinates come
   * from the star's onAreaChange (window vp, same unit and frame as
   * position()), and the web-area Stack spans the whole window, so window
   * coordinates apply directly. Falls back below the toolbar.
   */
  private updateBookmarkEditDialogAnchor(): void {
    const dialogWidth = this.getBookmarkEditDialogWidth();
    const fallbackRight = this.viewportWidth - 40;
    const fallbackBottom = 90;
    const right = this.starAnchorRight > 0 ? this.starAnchorRight : fallbackRight;
    const bottom = this.starAnchorBottom > 0 ? this.starAnchorBottom : fallbackBottom;
    this.bookmarkEditAnchorX = Math.max(12, Math.min(right - dialogWidth, this.viewportWidth - dialogWidth - 12));
    this.bookmarkEditAnchorY = Math.max(0, bottom + 6);
  }

  private getBookmarkEditDialogWidth(): number {
    return Math.min(360, Math.max(280, this.viewportWidth - 24));
  }

  private buildBookmarkEditFolderOptions(): BookmarkEditFolderOption[] {
    const options: BookmarkEditFolderOption[] = [{
      id: BookmarkManager.ROOT_FOLDER_ID,
      label: '书签栏',
    }];
    const appendFolders = (nodes: BookmarkTreeNode[], depth: number): void => {
      nodes.forEach((node: BookmarkTreeNode) => {
        if (node.type !== 'folder') {
          return;
        }
        const indent = depth > 1 ? '　'.repeat(depth - 1) : '';
        options.push({ id: node.id, label: `${indent}${node.title}` });
        appendFolders(node.children, depth + 1);
      });
    };
    appendFolders(this.bookmarkManager.listTree(), 1);
    return options;
  }

  private confirmBookmarkEditDialog(): void {
    const node = this.bookmarkManager.getBookmarkById(this.bookmarkEditNodeId);
    if (node && !node.isFolder) {
      const newTitle = this.bookmarkEditName.trim();
      if (newTitle.length > 0 && newTitle !== node.title) {
        this.bookmarkManager.updateBookmark(node.id, newTitle, node.url);
      }
      if (this.bookmarkEditFolderId !== node.parentId) {
        this.bookmarkManager.moveNode(node.id, this.bookmarkEditFolderId);
      }
      this.flushBookmarkMutation('edit-dialog', node.id);
    }
    this.syncCurrentBookmarkState(this.getCurrentBookmarkableUrl());
    this.closeBookmarkEditDialog();
  }

  private removeBookmarkFromEditDialog(): void {
    if (this.bookmarkEditNodeId) {
      this.bookmarkManager.removeBookmarkById(this.bookmarkEditNodeId);
      this.flushBookmarkMutation('edit-dialog-remove', this.bookmarkEditNodeId);
    }
    this.syncCurrentBookmarkState(this.getCurrentBookmarkableUrl());
    this.closeBookmarkEditDialog();
  }

  private closeBookmarkEditDialog(): void {
    this.showBookmarkEditDialog = false;
    this.bookmarkEditNodeId = '';
    this.bookmarkEditName = '';
    this.bookmarkEditFolderId = BookmarkManager.ROOT_FOLDER_ID;
    this.bookmarkEditFolderIndex = 0;
    this.bookmarkEditFolderOptions = [];
  }

  private clearAddressSuggestions(): void {
    this.addressSuggestionRequestId = this.addressSuggestionRequestId + 1;
    this.addressSuggestions = [];
    this.activeAddressSuggestionIndex = -1;
    this.showAddressSuggestions = false;
  }

  private hasAddressSuggestions(): boolean {
    return this.showAddressSuggestions && this.addressSuggestions.length > 0;
  }

  private getHighlightedAddressSuggestion(): AddressSuggestion | null {
    if (!this.hasAddressSuggestions()) {
      return null;
    }
    if (this.activeAddressSuggestionIndex < 0 || this.activeAddressSuggestionIndex >= this.addressSuggestions.length) {
      return null;
    }
    return this.addressSuggestions[this.activeAddressSuggestionIndex];
  }

  private getSelectedAddressSuggestionId(): string {
    const highlightedSuggestion = this.getHighlightedAddressSuggestion();
    return highlightedSuggestion ? highlightedSuggestion.id : '';
  }

  private moveAddressSuggestionSelection(step: number): void {
    if (!this.hasAddressSuggestions()) {
      return;
    }

    const count = this.addressSuggestions.length;
    if (this.activeAddressSuggestionIndex < 0) {
      this.activeAddressSuggestionIndex = step > 0 ? 0 : count - 1;
      return;
    }

    let nextIndex = this.activeAddressSuggestionIndex + step;
    if (nextIndex < 0) {
      nextIndex = count - 1;
    } else if (nextIndex >= count) {
      nextIndex = 0;
    }
    this.activeAddressSuggestionIndex = nextIndex;
  }

  private handleAddressSuggestionKeyEvent(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || !this.hasAddressSuggestions()) {
      return false;
    }

    if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveAddressSuggestionSelection(1);
      return true;
    }

    if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.moveAddressSuggestionSelection(-1);
      return true;
    }

    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      const highlightedSuggestion = this.getHighlightedAddressSuggestion();
      if (highlightedSuggestion) {
        this.handleAddressSuggestionSelect(highlightedSuggestion);
        return true;
      }
    }

    return false;
  }

  private isShiftPressed(event: KeyEvent): boolean {
    if (event.getModifierKeyState) {
      try {
        return event.getModifierKeyState(['shift']);
      } catch (_) {
      }
    }
    return false;
  }

  private refreshAddressSuggestions(value: string): void {
    const trimmedValue = value.trim();
    if (!trimmedValue) {
      this.clearAddressSuggestions();
      return;
    }

    // A new input value invalidates keyboard selection from the previous
    // result set. Plain Enter must submit the typed value, not switch tabs.
    this.activeAddressSuggestionIndex = -1;
    const requestId = this.addressSuggestionRequestId + 1;
    this.addressSuggestionRequestId = requestId;
    this.addressBarService.querySuggestions(trimmedValue, this.viewState.tabs, 6, this.viewState.isPrivate)
      .then((suggestions: AddressSuggestion[]) => {
        if (this.addressSuggestionRequestId !== requestId || !this.isAddressEditing) {
          return;
        }
        this.addressSuggestions = suggestions;
        this.activeAddressSuggestionIndex = -1;
        this.showAddressSuggestions = suggestions.length > 0;
      })
      .catch(() => {
        if (this.addressSuggestionRequestId !== requestId || !this.isAddressEditing) {
          return;
        }
        this.addressSuggestions = [];
        this.activeAddressSuggestionIndex = -1;
        this.showAddressSuggestions = false;
      });
  }

  private recordTabPageHistory(tabId: TabId, url: string, title?: string): void {
    const tab = this.findTab(tabId);
    if (!tab || tab.isPrivate || !this.isHttpUrl(url)) {
      return;
    }
    // “清除浏览数据”触发的自动刷新：跳过这一次回写，避免刚清空的历史记录
    // 被刷新动作当场重建。一次性消费。
    const skipKey = String(tabId);
    if (this.skipNextHistoryRecordTabIds.has(skipKey)) {
      this.skipNextHistoryRecordTabIds.delete(skipKey);
      return;
    }
    this.addressBarService.recordVisit(url, title, false)
      .catch(() => {
      });
    this.bookmarkManager.refreshBookmark(
      url,
      title,
      // The tab's /favicon.ico value is only a rendering fallback. Never use
      // it to overwrite a previously persisted favicon while a real PixelMap
      // is still being captured.
      this.faviconDataUriByTabId.get(String(tabId)),
    );
  }

  private isHttpUrl(url: string): boolean {
    return /^https?:\/\//i.test(url.trim());
  }

  private isAboutBlankUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized === 'about:blank' || normalized.startsWith('about:blank?') ||
      normalized.startsWith('about:blank#');
  }

  private findTab(tabId: TabId): Tab | null {
    return this.viewState.tabs.find((tab: Tab) => String(tab.id) === String(tabId)) ?? null;
  }

  private openDevLauncher(): void {
    if (!this.debugGate.canOpenDevLauncher()) {
      return;
    }
    this.navigateToRoute(AppRouter.devLauncher);
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (this.showJavaScriptDialog) {
      if (event.type !== KeyType.Down) {
        return true;
      }
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.resolveJavaScriptDialog(false);
        return true;
      }
      if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
        this.resolveJavaScriptDialog(true);
        return true;
      }
      return true;
    }

    if (this.isAddressEditing) {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        if (this.hasAddressSuggestions()) {
          this.clearAddressSuggestions();
        } else {
          this.cancelAddressEditing();
        }
        return true;
      }

      if (this.handleAddressSuggestionKeyEvent(event)) {
        return true;
      }

      const action = this.shortcutManager.resolve(event, this.viewState.tabs, this.viewState.activeTabId);
      if (!action) {
        return false;
      }

      this.applyShortcutAction(action);
      return true;
    }

    if (this.showPermissionDialog) {
      if (event.type !== KeyType.Down) {
        return true;
      }
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        if (!this.permissionDecisionPending) {
          this.permissionManager.dismissActiveRequest();
        }
        return true;
      }
      if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
        if (!this.permissionDecisionPending) {
          this.handlePermissionDialogDecision();
        }
        return true;
      }
      return true;
    }

    if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (this.showBookmarkEditDialog) {
        this.closeBookmarkEditDialog();
        return true;
      }
      if (this.showBookmarkRenameDialog) {
        this.cancelBookmarkRename();
        return true;
      }
      if (this.showBookmarkDeleteDialog) {
        this.cancelBookmarkDelete();
        return true;
      }
      if (this.bookmarkFolderMenuItems.length > 0) {
        this.closeBookmarkFolderMenu();
        return true;
      }
      if (this.showBookmarkContextMenu) {
        this.closeBookmarkContextMenu();
        return true;
      }
      if (this.showTabContextMenu) {
        this.closeTabContextMenu();
        return true;
      }
      if (this.showContextMenu) {
        this.closeContextMenu();
        return true;
      }
    }

    if (this.handleTabSearchKeyEvent(event)) {
      return true;
    }

    if (this.handleFindPanelKeyEvent(event)) {
      return true;
    }

    if (this.handleMainMenuKeyEvent(event)) {
      return true;
    }

    if (this.handleAddressSuggestionKeyEvent(event)) {
      return true;
    }

    const action = this.shortcutManager.resolve(event, this.viewState.tabs, this.viewState.activeTabId);
    if (!action) {
      return false;
    }

    this.applyShortcutAction(action);
    return true;
  }

  private handleFindPanelKeyEvent(event: KeyEvent): boolean {
    if (!this.showFindPanel || event.type !== KeyType.Down) {
      return false;
    }

    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeFindPanel();
      return true;
    }

    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      if (this.isShiftPressed(event)) {
        this.focusPrevFindResult();
      } else {
        this.focusNextFindResult();
      }
      return true;
    }

    return false;
  }

  private handleMainMenuKeyEvent(event: KeyEvent): boolean {
    if (!this.showMainMenu || event.type !== KeyType.Down) {
      return false;
    }

    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeMainMenu();
      return true;
    }

    if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      if (this.showUaSubMenu) {
        this.moveUaSubMenuHighlight(1);
      } else if (this.showBookmarksSubMenu) {
        this.moveBookmarksSubMenuHighlight(1);
      } else {
        this.moveMainMenuHighlight(1);
      }
      return true;
    }

    if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      if (this.showUaSubMenu) {
        this.moveUaSubMenuHighlight(-1);
      } else if (this.showBookmarksSubMenu) {
        this.moveBookmarksSubMenuHighlight(-1);
      } else {
        this.moveMainMenuHighlight(-1);
      }
      return true;
    }

    if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      const item = this.getActiveMainMenuItem();
      if (item && item.id === 'bookmarks') {
        this.openBookmarksSubMenu();
        return true;
      }
      if (item && item.id === 'ua') {
        this.openUaSubMenu();
        return true;
      }
      return false;
    }

    if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      if (this.showUaSubMenu) {
        this.closeUaSubMenu();
        return true;
      }
      if (this.showBookmarksSubMenu) {
        this.closeBookmarksSubMenu();
        return true;
      }
    }

    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      if (this.showUaSubMenu) {
        const uaSubMenuItem = this.getActiveUaSubMenuItem();
        if (uaSubMenuItem) {
          this.handleUaSubMenuSelect(uaSubMenuItem);
        }
        return true;
      }

      if (this.showBookmarksSubMenu) {
        const subMenuItem = this.getActiveBookmarksSubMenuItem();
        if (subMenuItem) {
          this.handleBookmarksSubMenuSelect(subMenuItem);
        }
        return true;
      }

      const item = this.getActiveMainMenuItem();
      if (item) {
        if (item.id === 'zoom') {
          return true;
        }
        this.handleMainMenuSelect(item);
      }
      return true;
    }

    return false;
  }

  private getEnabledMainMenuItems(): BrowserMenuItem[] {
    return this.getResolvedMainMenuItems().filter((item: BrowserMenuItem) => !item.disabled);
  }

  private getDefaultMainMenuItemId(): string {
    const items = this.getEnabledMainMenuItems();
    return items.length > 0 ? items[0].id : '';
  }

  private getActiveMainMenuItem(): BrowserMenuItem | null {
    const item = this.getResolvedMainMenuItems().find(
      (entry: BrowserMenuItem) => entry.id === this.mainMenuActiveItemId
    );
    return item ? item : null;
  }

  private moveMainMenuHighlight(step: number): void {
    const items = this.getEnabledMainMenuItems();
    if (items.length === 0) {
      this.mainMenuActiveItemId = '';
      return;
    }

    const currentIndex = items.findIndex((item: BrowserMenuItem) => item.id === this.mainMenuActiveItemId);
    if (currentIndex === -1) {
      this.mainMenuActiveItemId = items[0].id;
      this.syncMainMenuSubMenuForActiveItem();
      return;
    }

    const nextIndex = (currentIndex + step + items.length) % items.length;
    this.mainMenuActiveItemId = items[nextIndex].id;
    this.syncMainMenuSubMenuForActiveItem();
  }

  private syncMainMenuSubMenuForActiveItem(): void {
    const item = this.getActiveMainMenuItem();
    if (!item) {
      this.closeBookmarksSubMenu();
      this.closeUaSubMenu();
      return;
    }
    if (item.id === 'bookmarks') {
      this.closeUaSubMenu();
      this.openBookmarksSubMenu();
      return;
    }
    if (item.id === 'ua') {
      this.closeBookmarksSubMenu();
      this.openUaSubMenu();
      return;
    }
    this.closeBookmarksSubMenu();
    this.closeUaSubMenu();
  }

  private openMainMenu(): void {
    this.cancelAddressEditing();
    if (this.showFindPanel) {
      this.closeFindPanel();
    }
    if (this.showMainMenu) {
      this.closeMainMenu();
    }
    this.showMainMenu = true;
    this.mainMenuActiveItemId = this.getDefaultMainMenuItemId();
    this.closeBookmarksSubMenu();
    this.closeUaSubMenu();
  }

  private closeMainMenu(): void {
    this.showMainMenu = false;
    this.mainMenuActiveItemId = '';
    this.closeBookmarksSubMenu();
    this.closeUaSubMenu();
  }

  private updateMainMenuHover(item: BrowserMenuItem): void {
    if (item.disabled || item.hoverHighlightDisabled === true) {
      return;
    }
    this.mainMenuActiveItemId = item.id;
    if (item.id === 'bookmarks') {
      this.closeUaSubMenu();
      this.openBookmarksSubMenu();
      return;
    }
    if (item.id === 'ua') {
      this.closeBookmarksSubMenu();
      this.openUaSubMenu();
      return;
    }
    this.closeBookmarksSubMenu();
    this.closeUaSubMenu();
  }

  private handleMainMenuSelect(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }

    if (item.id === 'zoom') {
      return;
    }

    if (item.id === 'bookmarks') {
      this.mainMenuActiveItemId = item.id;
      this.closeUaSubMenu();
      this.openBookmarksSubMenu();
      return;
    }

    if (item.id === 'ua') {
      this.mainMenuActiveItemId = item.id;
      this.closeBookmarksSubMenu();
      this.openUaSubMenu();
      return;
    }

    this.closeMainMenu();

    if (item.id === 'new_tab') {
      this.handleNewTab();
      return;
    }

    if (item.id === 'new_window') {
      this.handleNewWindow();
      return;
    }

    // 暂时预留，后期完善：无痕窗口命令当前不会从主菜单产生。

    if (item.id === 'history') {
      this.openHistoryManager();
      return;
    }

    if (item.id === 'downloads') {
      this.openDownloadsManager();
      return;
    }

    if (item.id === 'find_in_page') {
      this.openFindPanel();
      return;
    }

    if (item.id === 'print') {
      this.printCurrentPage();
      return;
    }

    if (item.id === 'save_page_as') {
      this.saveCurrentPage();
      return;
    }

    if (item.id === 'exit') {
      this.onCloseWindow();
      return;
    }

    if (item.id === 'settings') {
      this.settingsSectionId = 'search-engine';
      this.navigateToRoute(AppRouter.settings);
    }
  }

  private getEnabledBookmarksSubMenuItems(): BrowserMenuItem[] {
    return this.getResolvedBookmarksSubMenuItems().filter((item: BrowserMenuItem) => !item.disabled);
  }

  private getActiveBookmarksSubMenuItem(): BrowserMenuItem | null {
    const item = this.getResolvedBookmarksSubMenuItems().find(
      (entry: BrowserMenuItem) => entry.id === this.bookmarksSubMenuActiveItemId
    );
    return item ? item : null;
  }

  private openBookmarksSubMenu(): void {
    this.showBookmarksSubMenu = true;
    this.updateBookmarksSubMenuAnchor();
    const items = this.getEnabledBookmarksSubMenuItems();
    if (!this.bookmarksSubMenuActiveItemId && items.length > 0) {
      this.bookmarksSubMenuActiveItemId = items[0].id;
    }
  }

  private closeBookmarksSubMenu(): void {
    this.showBookmarksSubMenu = false;
    this.bookmarksSubMenuActiveItemId = '';
  }

  private moveBookmarksSubMenuHighlight(step: number): void {
    const items = this.getEnabledBookmarksSubMenuItems();
    if (items.length === 0) {
      this.bookmarksSubMenuActiveItemId = '';
      return;
    }

    const currentIndex = items.findIndex((item: BrowserMenuItem) => item.id === this.bookmarksSubMenuActiveItemId);
    if (currentIndex === -1) {
      this.bookmarksSubMenuActiveItemId = items[0].id;
      return;
    }

    const nextIndex = (currentIndex + step + items.length) % items.length;
    this.bookmarksSubMenuActiveItemId = items[nextIndex].id;
  }

  private updateBookmarksSubMenuHover(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }
    this.bookmarksSubMenuActiveItemId = item.id;
  }

  private handleBookmarksSubMenuSelect(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }

    if (item.id === 'bookmarks_manager') {
      // Open the bookmarks manager inside the Settings shell so the menu entry
      // uses the same layout and navigation as the Settings sidebar.
      this.settingsSectionId = 'bookmarks-manager';
      this.closeMainMenu();
      this.navigateToRoute(AppRouter.settings);
      return;
    }

    if (item.id === 'toggle_page_bookmark') {
      this.closeMainMenu();
      this.handleToggleCurrentPageBookmark();
      return;
    }

    if (item.id === 'show_bookmark_bar') {
      this.toggleBookmarkBar();
    }
  }

  private toggleBookmarkBar(): void {
    this.showBookmarkBar = !this.showBookmarkBar;
    if (this.showMainMenu) {
      this.closeMainMenu();
    }
  }

  private getEnabledUaSubMenuItems(): BrowserMenuItem[] {
    return this.getResolvedUaSubMenuItems().filter((item: BrowserMenuItem) => !item.disabled);
  }

  private getActiveUaSubMenuItem(): BrowserMenuItem | null {
    const item = this.getResolvedUaSubMenuItems().find(
      (entry: BrowserMenuItem) => entry.id === this.uaSubMenuActiveItemId
    );
    return item ? item : null;
  }

  private openUaSubMenu(): void {
    this.showUaSubMenu = true;
    this.updateUaSubMenuAnchor();
    const items = this.getEnabledUaSubMenuItems();
    if (!this.uaSubMenuActiveItemId && items.length > 0) {
      this.uaSubMenuActiveItemId = items[0].id;
    }
  }

  private closeUaSubMenu(): void {
    this.showUaSubMenu = false;
    this.uaSubMenuActiveItemId = '';
  }

  private moveUaSubMenuHighlight(step: number): void {
    const items = this.getEnabledUaSubMenuItems();
    if (items.length === 0) {
      this.uaSubMenuActiveItemId = '';
      return;
    }
    const currentIndex = items.findIndex((item: BrowserMenuItem) => item.id === this.uaSubMenuActiveItemId);
    if (currentIndex === -1) {
      this.uaSubMenuActiveItemId = items[0].id;
      return;
    }
    const nextIndex = (currentIndex + step + items.length) % items.length;
    this.uaSubMenuActiveItemId = items[nextIndex].id;
  }

  private updateUaSubMenuHover(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }
    this.uaSubMenuActiveItemId = item.id;
  }

  private handleUaSubMenuSelect(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }
    const nextMode = this.uaManager.normalizeMode(item.id);
    if (nextMode !== this.selectedUaMode) {
      this.selectedUaMode = nextMode;
      // 持久化 UA 选择，重启后由 settingsListener 同步回来（见 applyBrowserSettingsChange）。
      SettingsManager.getInstance().updateSettings({ uaMode: nextMode });
      hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
        'UA_SWITCH mode=%{public}s action=recreate_web_context', nextMode);
      this.restartWebRuntimesForUaMode();
    }
    this.closeMainMenu();
  }

  private restartWebRuntimesForUaMode(): void {
    const activeTab = this.findTab(this.viewState.activeTabId);
    if (activeTab && activeTab.loadState !== 'home' && activeTab.url.trim().length > 0) {
      this.applyViewState(this.viewModel.reloadActiveTab(), false, false);
    }

    // setCustomUserAgent is scoped to a Web context. Recreate the contexts so
    // the very first request after switching UA is guaranteed to carry the
    // selected value; this also resets servers' responsive negotiation.
    this.viewState.tabs.forEach((tab: Tab) => {
      this.cancelPendingNativeNavigation(tab.id, 'ua_runtime_recreate');
      this.navigationStateSettlingUntilByTabId.delete(String(tab.id));
      const state = this.getTabWebRuntimeState(tab.id);
      state.controllerAttached = false;
      state.pendingUrl = tab.loadState === 'home' ? '' : tab.url.trim();
      state.requestedUrl = state.pendingUrl;
      state.committedUrl = '';
      state.loadedUrl = '';
      state.lastError = '';
      if (state.pendingUrl.length > 0) {
        this.markTabLoadRequested(tab.id, state.pendingUrl);
        state.pendingUrl = tab.url.trim();
      }
    });
    this.webViewManager.destroyAll();
    this.uaRenderRevision += 1;
  }

  private applyUserAgentToAllRuntimes(): number {
    let appliedCount = 0;
    this.viewState.tabs.forEach((tab: Tab) => {
      const runtime = this.webViewManager.get(tab.id);
      if (runtime) {
        const applied = this.uaManager.apply(runtime.controller, this.selectedUaMode);
        let effectiveUa = '';
        try {
          effectiveUa = runtime.controller.getCustomUserAgent();
        } catch (_) {
        }
        hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
          'UA_APPLY tab=%{public}s mode=%{public}s applied=%{public}s effective=%{public}s',
          String(tab.id), this.selectedUaMode, String(applied),
          effectiveUa.length > 0 ? `${effectiveUa.slice(0, 96)}(${effectiveUa.length})` : 'empty');
        if (applied) {
          appliedCount += 1;
        }
      }
    });
    return appliedCount;
  }

  private reapplyPageRuntimeVisualState(): void {
    if (!this.showHome) {
      this.applyPageZoom();
      if (this.showFindPanel && this.findText.trim().length > 0) {
        this.applyPageFindHighlights();
      }
    }
  }

  private applyPageZoom(): void {
    const controller = this.getActiveController();
    if (!controller || this.showHome) {
      return;
    }
    try {
      const pageFactor = this.resolveCurrentPageFactor();
      const targetPercent = this.resolveTargetZoomPercent();
      const zoomFactor = targetPercent / pageFactor;
      if (!Number.isFinite(zoomFactor) || zoomFactor <= 0 || Math.abs(zoomFactor - 1) < 0.001) {
        return;
      }
      controller.zoom(zoomFactor);
      this.currentPageScalePercent = this.clampPageZoomPercent(this.pageZoomPercent);
    } catch (_) {
    }
  }

  private adjustPageZoom(step: number): void {
    const nextZoom = this.clampPageZoomPercent(this.pageZoomPercent + step);
    if (nextZoom === this.pageZoomPercent) {
      return;
    }
    this.pageZoomPercent = nextZoom;
    this.applyPageZoom();
  }

  private resetPageZoom(): void {
    const defaultZoomPercent = this.clampPageZoomPercent(
      SettingsManager.getInstance().getSettings().defaultZoomPercent,
    );
    if (this.pageZoomPercent === defaultZoomPercent) {
      return;
    }
    this.pageZoomPercent = defaultZoomPercent;
    this.applyPageZoom();
  }

  private clampPageZoomPercent(scale: number): number {
    const normalizedScale = this.normalizePageScalePercent(scale);
    return Math.max(25, Math.min(200, Math.round(normalizedScale)));
  }

  private normalizePageScalePercent(scale: number): number {
    if (scale <= 0) {
      return 100;
    }
    if (scale > 0 && scale <= 10) {
      return scale * 100;
    }
    return scale;
  }

  private resolveCurrentPageFactor(): number {
    const scale = this.normalizePageScalePercent(this.currentPageScalePercent);
    return scale > 0 ? scale : 100;
  }

  private resolveTargetZoomPercent(): number {
    return this.clampPageZoomPercent(this.pageZoomPercent);
  }

  private openFindPanel(): void {
    this.closeMainMenu();
    if (this.showAddressSuggestions || this.isAddressEditing) {
      this.cancelAddressEditing();
    }
    if (!this.findText.trim()) {
      const activeTabId = this.viewModel.getActiveTabId();
      const previousText = activeTabId ? this.lastFindTextByTabId.get(String(activeTabId)) : undefined;
      if (previousText) {
        this.findText = previousText;
      }
    }
    this.showFindPanel = true;
    if (this.findText.trim().length > 0) {
      this.applyPageFindHighlights();
    }
  }

  private closeFindPanel(): void {
    const activeTabId = this.viewModel.getActiveTabId();
    if (activeTabId && this.findText.trim()) {
      this.lastFindTextByTabId.set(String(activeTabId), this.findText.trim());
    }
    this.pendingFindNavigationDirection = 0;
    this.showFindPanel = false;
    this.findText = '';
    this.findMatchCount = 0;
    this.findActiveIndex = 0;
    this.findIsCounting = false;
    this.clearPageFindHighlights();
  }

  private updateFindText(value: string): void {
    this.findText = value;
    const activeTabId = this.viewModel.getActiveTabId();
    if (activeTabId) {
      if (value.trim()) {
        this.lastFindTextByTabId.set(String(activeTabId), value.trim());
      } else {
        this.lastFindTextByTabId.delete(String(activeTabId));
      }
    }
    this.applyPageFindHighlights();
  }

  private applyPageFindHighlights(): void {
    const controller = this.getActiveController();
    if (!controller || this.showHome) {
      this.findMatchCount = 0;
      this.findActiveIndex = 0;
      this.findIsCounting = false;
      return;
    }

    const keyword = this.findText.trim();
    if (!keyword) {
      this.findMatchCount = 0;
      this.findActiveIndex = 0;
      this.findIsCounting = false;
      this.clearPageFindHighlights();
      return;
    }

    this.findMatchCount = 0;
    this.findActiveIndex = 0;
    this.findIsCounting = true;

    try {
      controller.searchAllAsync(keyword);
    } catch (_) {
      this.findIsCounting = false;
    }

    /* Legacy DOM-injection find implementation kept disabled after switching to ArkWeb searchAllAsync.
    const keywordJson = JSON.stringify(keyword);
    const script = `(() => {
      try {
        const markClass = '__oh_browser_find_mark__';
        const activeClass = '__oh_browser_find_mark_active__';
        const stateKey = '__OH_BROWSER_FIND_STATE__';
        const styleId = '__oh_browser_find_style__';
        let styleNode = document.getElementById(styleId);
        if (!styleNode) {
          styleNode = document.createElement('style');
          styleNode.id = styleId;
          styleNode.textContent =
            '.' + markClass + '{background:#fde68a;color:#111827;padding:0;border-radius:2px;}' +
            '.' + activeClass + '{background:#f59e0b;color:#111827;}';
          document.head && document.head.appendChild(styleNode);
        }

        const unwrap = (root) => {
          const marks = Array.from(root.querySelectorAll('span.' + markClass));
          marks.forEach((mark) => {
            const parent = mark.parentNode;
            if (!parent) {
              return;
            }
            const textNode = document.createTextNode(mark.textContent || '');
            parent.replaceChild(textNode, mark);
            parent.normalize();
          });
        };

        unwrap(document.body);

        const keyword = ${keywordJson};
        if (!keyword) {
          window[stateKey] = { keyword: '', count: 0, activeIndex: 0 };
          return;
        }

        const lowerKeyword = keyword.toLowerCase();
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
          acceptNode(node) {
            if (!node || !node.nodeValue || !node.nodeValue.trim()) {
              return NodeFilter.FILTER_REJECT;
            }
            const parent = node.parentElement;
            if (!parent) {
              return NodeFilter.FILTER_REJECT;
            }
            const tagName = parent.tagName;
            if (tagName === 'SCRIPT' || tagName === 'STYLE' || tagName === 'NOSCRIPT') {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        });

        const textNodes = [];
        let current = walker.nextNode();
        while (current) {
          textNodes.push(current);
          current = walker.nextNode();
        }

        let firstMark = null;
        let totalCount = 0;
        textNodes.forEach((node) => {
          const text = node.nodeValue || '';
          const lowerText = text.toLowerCase();
          let start = lowerText.indexOf(lowerKeyword);
          if (start === -1) {
            return;
          }

          const fragment = document.createDocumentFragment();
          let lastIndex = 0;
          while (start !== -1) {
            if (start > lastIndex) {
              fragment.appendChild(document.createTextNode(text.slice(lastIndex, start)));
            }
            const mark = document.createElement('span');
            mark.className = markClass;
            mark.textContent = text.slice(start, start + keyword.length);
            totalCount += 1;
            if (!firstMark) {
              mark.classList.add(activeClass);
              firstMark = mark;
            }
            fragment.appendChild(mark);
            lastIndex = start + keyword.length;
            start = lowerText.indexOf(lowerKeyword, lastIndex);
          }
          if (lastIndex < text.length) {
            fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
          }
          const parent = node.parentNode;
          if (parent) {
            parent.replaceChild(fragment, node);
          }
        });

        if (firstMark && typeof firstMark.scrollIntoView === 'function') {
          firstMark.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
        }

        window[stateKey] = {
          keyword: keyword,
          count: totalCount,
          activeIndex: totalCount > 0 ? 1 : 0,
        };
      } catch (_) {}
    })();`;

    try {
      controller.runJavaScript(script);
    } catch (_) {
    }

    this.findMatchCount = this.countFindMatches(keyword);
    this.findActiveIndex = this.findMatchCount > 0 ? 1 : 0;
    */
  }

  private countFindMatches(keyword: string): number {
    const lowerKeyword = keyword.trim().toLowerCase();
    if (!lowerKeyword) {
      return 0;
    }

    const activeTab = this.viewState.tabs.find((tab) => String(tab.id) === this.viewState.activeTabId);
    const samples: string[] = [];
    if (activeTab?.title) {
      samples.push(activeTab.title.toLowerCase());
    }
    if (this.viewState.currentUrl) {
      samples.push(this.viewState.currentUrl.toLowerCase());
    }
    if (this.addressText) {
      samples.push(this.addressText.toLowerCase());
    }

    let count = 0;
    samples.forEach((sample) => {
      let startIndex = sample.indexOf(lowerKeyword);
      while (startIndex !== -1) {
        count += 1;
        startIndex = sample.indexOf(lowerKeyword, startIndex + lowerKeyword.length);
      }
    });
    return count;
  }

  private focusPageFindResult(nextIndex: number, forward: boolean): void {
    const controller = this.getActiveController();
    if (!controller || this.showHome || this.findMatchCount <= 0) {
      return;
    }

    // Direction must follow the requested next/previous action, not be inferred from
    // index comparison: at the boundary the wrapped target index (e.g. count when
    // going prev from 1) is larger than the current one, which used to flip the
    // searchNext direction and caused 1<->2 / last<->second-to-last oscillation.
    try {
      controller.searchNext(forward);
    } catch (_) {
    }

    this.findActiveIndex = Math.max(1, Math.min(this.findMatchCount, nextIndex));
  }

  private focusNextFindResult(): void {
    if (this.findMatchCount <= 0) {
      return;
    }
    const nextIndex = this.findActiveIndex >= this.findMatchCount ? 1 : this.findActiveIndex + 1;
    this.focusPageFindResult(nextIndex, true);
  }

  private focusPrevFindResult(): void {
    if (this.findMatchCount <= 0) {
      return;
    }
    const nextIndex = this.findActiveIndex <= 1 ? this.findMatchCount : this.findActiveIndex - 1;
    this.focusPageFindResult(nextIndex, false);
  }

  private openFindDirection(forward: boolean): void {
    if (!this.showFindPanel) {
      const activeTabId = this.viewModel.getActiveTabId();
      const previousText = activeTabId ? this.lastFindTextByTabId.get(String(activeTabId)) : undefined;
      if (previousText) {
        this.findText = previousText;
        this.pendingFindNavigationDirection = forward ? 1 : -1;
      }
      this.openFindPanel();
      return;
    }
    if (!this.findText.trim()) {
      return;
    }
    if (forward) {
      this.focusNextFindResult();
    } else {
      this.focusPrevFindResult();
    }
  }

  private getFilteredTabSearchTabs(): Tab[] {
    const query = this.tabSearchQuery.trim().toLowerCase();
    if (!query) {
      return this.viewState.tabs;
    }
    return this.viewState.tabs.filter((tab: Tab): boolean => {
      return tab.title.toLowerCase().includes(query) || tab.url.toLowerCase().includes(query);
    });
  }

  private openTabSearch(): void {
    this.closeTransientOverlays();
    this.tabSearchQuery = '';
    const activeIndex = this.viewState.tabs.findIndex((tab: Tab): boolean => {
      return String(tab.id) === this.viewState.activeTabId;
    });
    this.tabSearchActiveIndex = Math.max(0, activeIndex);
    this.showTabSearch = true;
    Promise.resolve().then(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(TAB_SEARCH_INPUT_ID);
      } catch (_) {
      }
    });
  }

  private closeTabSearch(): void {
    this.showTabSearch = false;
    this.tabSearchQuery = '';
    this.tabSearchActiveIndex = 0;
  }

  private updateTabSearchQuery(value: string): void {
    this.tabSearchQuery = value;
    this.tabSearchActiveIndex = 0;
  }

  private moveTabSearchHighlight(step: number): void {
    const tabs = this.getFilteredTabSearchTabs();
    if (tabs.length === 0) {
      this.tabSearchActiveIndex = 0;
      return;
    }
    this.tabSearchActiveIndex = (this.tabSearchActiveIndex + step + tabs.length) % tabs.length;
  }

  private selectTabSearchResult(tab: Tab): void {
    this.closeTabSearch();
    this.handleTabSelect(tab.id);
  }

  private selectActiveTabSearchResult(): void {
    const tabs = this.getFilteredTabSearchTabs();
    if (tabs.length === 0) {
      return;
    }
    const index = Math.max(0, Math.min(this.tabSearchActiveIndex, tabs.length - 1));
    this.selectTabSearchResult(tabs[index]);
  }

  private handleTabSearchKeyEvent(event: KeyEvent): boolean {
    if (!this.showTabSearch || event.type !== KeyType.Down) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeTabSearch();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveTabSearchHighlight(1);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.moveTabSearchHighlight(-1);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      this.selectActiveTabSearchResult();
      return true;
    }
    return false;
  }

  private getTabSearchWidth(): number {
    return Math.min(520, Math.max(280, this.viewportWidth - 32));
  }

  @Builder
  private TabSearchPanel() {
    Column() {
      TextInput({ text: this.tabSearchQuery, placeholder: '搜索标签页' })
        .id(TAB_SEARCH_INPUT_ID)
        .width('100%')
        .height(42)
        .fontSize(14)
        .backgroundColor('#f5f7fa')
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => this.updateTabSearchQuery(value))
        .onSubmit(() => this.selectActiveTabSearchResult());

      Scroll() {
        Column() {
          ForEach(this.getFilteredTabSearchTabs(), (tab: Tab, index: number) => {
            Row({ space: 10 }) {
              Text(tab.isLoading ? '◌' : '●')
                .width(18)
                .fontSize(tab.isLoading ? 16 : 10)
                .fontColor(tab.isLoading ? '#1a73e8' : '#8a94a3')
                .textAlign(TextAlign.Center);
              Column({ space: 2 }) {
                Text(tab.title || '新标签页')
                  .width('100%')
                  .fontSize(13)
                  .fontColor('#202124')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(tab.url === 'about:blank' ? '新标签页' : tab.url)
                  .width('100%')
                  .fontSize(11)
                  .fontColor('#6b7280')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start);
            }
            .width('100%')
            .height(54)
            .padding({ left: 12, right: 12 })
            .backgroundColor(index === this.tabSearchActiveIndex ? '#e8f0fe' : '#ffffff')
            .onHover((hovered: boolean) => {
              if (hovered) {
                this.tabSearchActiveIndex = index;
              }
            })
            .onClick(() => this.selectTabSearchResult(tab));
          }, (tab: Tab) => String(tab.id));

          if (this.getFilteredTabSearchTabs().length === 0) {
            Text('没有匹配的标签页')
              .width('100%')
              .height(72)
              .fontSize(13)
              .fontColor('#6b7280')
              .textAlign(TextAlign.Center);
          }
        }
        .width('100%');
      }
      .width('100%')
      .constraintSize({ maxHeight: Math.max(108, Math.min(360, this.viewportHeight - 140)) });
    }
    .width(this.getTabSearchWidth())
    .padding(10)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .border({ width: 1, color: '#d9dee8' });
  }

  private handleFindSearchResult(tabId: TabId, runtime: WebRuntime, event: OnSearchResultReceiveEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime) || !this.isActiveTabId(tabId) ||
      !this.showFindPanel || !this.findText.trim()) {
      return;
    }

    this.findMatchCount = Math.max(0, event.numberOfMatches);
    this.findActiveIndex = this.findMatchCount > 0 ? Math.max(1, event.activeMatchOrdinal + 1) : 0;
    this.findIsCounting = !event.isDoneCounting;
    if (event.isDoneCounting && this.pendingFindNavigationDirection !== 0) {
      const direction = this.pendingFindNavigationDirection;
      this.pendingFindNavigationDirection = 0;
      if (this.findMatchCount > 0) {
        if (direction > 0) {
          this.focusNextFindResult();
        } else {
          this.focusPrevFindResult();
        }
      }
    }
  }

  private getFindCountText(): string {
    if (!this.findText.trim()) {
      return '0/0';
    }
    if (this.findIsCounting) {
      return '查找中';
    }
    if (this.findMatchCount <= 0) {
      return '未找到';
    }
    return `${this.findActiveIndex}/${this.findMatchCount}`;
  }

  private updateFindCaseSensitive(value: boolean): void {
    this.findCaseSensitive = value;
    this.applyPageFindHighlights();
  }

  private clearPageFindHighlights(): void {
    const controller = this.getActiveController();
    if (!controller || this.showHome) {
      return;
    }

    try {
      controller.clearMatches();
    } catch (_) {
    }
  }

  @Builder
  private FindPanel() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('页内查找')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827');

        Blank();

        Button('关闭')
          .height(28)
          .fontSize(12)
          .backgroundColor('#f3f4f6')
          .fontColor('#4b5563')
          .borderRadius(14)
          .onClick(() => this.closeFindPanel());
      }
      .width('100%');

      TextInput({ text: this.findText, placeholder: '输入页面内关键词' })
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor('#f8fafc')
        .borderRadius(10)
        .border({ width: 1, color: '#e5e7eb' })
        .onChange((value: string) => this.updateFindText(value));

      Row({ space: 10 }) {
        Text(this.getFindCountText())
          .fontSize(12)
          .fontColor('#6b7280');

        Blank();

        Button('上一项')
          .height(30)
          .fontSize(12)
          .backgroundColor('#ffffff')
          .fontColor(this.findMatchCount > 0 ? '#374151' : '#c7cdd8')
          .borderRadius(15)
          .border({ width: 1, color: '#e5e7eb' })
          .enabled(this.findMatchCount > 0)
          .onClick(() => this.focusPrevFindResult());

        Button('下一项')
          .height(30)
          .fontSize(12)
          .backgroundColor('#ffffff')
          .fontColor(this.findMatchCount > 0 ? '#374151' : '#c7cdd8')
          .borderRadius(15)
          .border({ width: 1, color: '#e5e7eb' })
          .enabled(this.findMatchCount > 0)
          .onClick(() => this.focusNextFindResult());
      }
      .width('100%');

      Text(
        '会高亮当前页面中的匹配文本，并自动滚动到第一个结果；' +
        '当前计数为轻量实现。'
      )
        .fontSize(12)
        .fontColor('#6b7280');
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.getFindPanelWidth())
    .padding(14)
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .border({ width: 1, color: '#dbe3f0' });
  }

  private showOperationToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  private stopActiveLoading(): void {
    if (this.showHome) {
      return;
    }
    const activeTabId = this.viewModel.getActiveTabId();
    const controller = this.getActiveController();
    if (!activeTabId || !controller) {
      return;
    }
    const activeTab = this.findTab(activeTabId);
    if (!activeTab?.isLoading) {
      return;
    }
    try {
      controller.stop();
    } catch (_) {
    }
    const runtimeState = this.getTabWebRuntimeState(activeTabId);
    stopWebNavigation(runtimeState.navigationLifecycle);
    runtimeState.pendingUrl = '';
    runtimeState.requestedUrl = '';
    runtimeState.updatedAt = Date.now();
    this.applyViewState(this.viewModel.updateTabLoadStopped(activeTabId), false);
  }

  private toggleFullScreen(): void {
    const nextValue = !this.isFullScreen;
    this.closeTransientOverlays();
    this.windowManager.setFullScreen(this.getUIContext(), nextValue)
      .then(() => {
        this.isFullScreen = nextValue;
      })
      .catch(() => this.showOperationToast('无法切换全屏模式'));
  }

  private openClearBrowsingData(): void {
    this.settingsSectionId = 'clear-data';
    this.navigateToRoute(AppRouter.settings);
  }

  private getActivePageTitle(fallback: string): string {
    const activeTab = this.viewState.tabs.find((tab: Tab): boolean => {
      return String(tab.id) === this.viewState.activeTabId;
    });
    const title = activeTab?.title.trim() ?? '';
    return title || fallback;
  }

  private sanitizeFileName(value: string, fallback: string): string {
    const sanitized = value.trim().replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').replace(/\.+$/g, '');
    return (sanitized || fallback).slice(0, 80);
  }

  private printCurrentPage(): void {
    const controller = this.getActiveController();
    if (!controller || this.showHome) {
      this.showOperationToast('当前页面无法打印');
      return;
    }
    if (!canIUse('SystemCapability.Print.PrintFramework')) {
      this.showOperationToast('当前设备不支持网页打印');
      return;
    }
    try {
      const jobName = this.sanitizeFileName(this.getActivePageTitle('网页'), '网页');
      const adapter = controller.createWebPrintDocumentAdapter(jobName);
      const attributes: print.PrintAttributes = {};
      print.print(jobName, adapter, attributes, this.getUIContext().getHostContext())
        .catch(() => this.showOperationToast('无法打开打印服务'));
    } catch (_) {
      this.showOperationToast('当前设备不支持网页打印');
    }
  }

  private saveCurrentPage(): void {
    const controller = this.getActiveController();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!controller || this.showHome) {
      this.showOperationToast('当前页面无法保存');
      return;
    }
    const fileName = `${this.sanitizeFileName(this.getActivePageTitle('网页'), '网页')}.mht`;
    const baseName = `${context.cacheDir}/saved_page_${Date.now()}`;
    controller.storeWebArchive(baseName, true)
      .then((archivePath: string) => this.choosePageArchiveDestination(context, archivePath, fileName))
      .then(() => this.showOperationToast('网页已保存'))
      .catch(() => this.showOperationToast('未能保存网页'));
  }

  private async choosePageArchiveDestination(
    context: common.UIAbilityContext,
    archivePath: string,
    fileName: string,
  ): Promise<void> {
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      options.fileSuffixChoices = ['网页归档|.mht'];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (!uris || uris.length === 0) {
        throw new Error('未选择保存位置');
      }
      try {
        await fs.copyFile(archivePath, uris[0]);
      } catch (error) {
        const copyError = error as Error;
        throw new Error(copyError.message || '复制网页归档失败');
      }
    } finally {
      try {
        await fs.unlink(archivePath);
      } catch (_) {
      }
    }
  }

  private viewCurrentPageSource(): void {
    const controller = this.getActiveController();
    if (!controller || this.showHome) {
      this.showOperationToast('当前页面没有可查看的源码');
      return;
    }
    const pageUrl = this.viewState.currentUrl;
    controller.runJavaScript('document.documentElement ? document.documentElement.outerHTML : ""')
      .then((source: string) => {
        const sourceDocument = this.buildSourceViewerDocument(pageUrl, source);
        const historyUrl = `view-source:${pageUrl}`;
        const nextState = this.viewModel.newTabWithUrl(historyUrl);
        this.pendingSourceViewerByTabId.set(nextState.activeTabId, {
          document: sourceDocument,
          baseUrl: pageUrl,
          historyUrl: historyUrl,
        });
        this.applyViewState(nextState, false);
      })
      .catch(() => this.showOperationToast('无法读取当前页面源码'));
  }

  private buildSourceViewerDocument(pageUrl: string, source: string): string {
    const escapedSource = source
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    const escapedTitle = pageUrl
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    return `<!doctype html><html><head><meta charset="utf-8"><title>view-source:${escapedTitle}</title>` +
      '<style>body{margin:0;padding:16px;background:#fff;color:#202124;' +
      'font:13px/1.55 monospace;white-space:pre-wrap;word-break:break-word}</style>' +
      `</head><body>${escapedSource}</body></html>`;
  }

  private openLocalFile(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['所有文件|.*'];
    new picker.DocumentViewPicker(context).select(options)
      .then((uris: string[]) => {
        if (uris && uris.length > 0) {
          this.applyViewState(this.viewModel.newTabWithUrl(uris[0]), true);
        }
      })
      .catch(() => {
      });
  }

  private applyShortcutAction(action: BrowserShortcutAction): void {
    if (action.command === 'new_tab') {
      this.handleNewTab();
      return;
    }

    if (action.command === 'new_window') {
      this.handleNewWindow();
      return;
    }

    // 暂时预留，后期完善：无痕窗口快捷键命令当前不会由 ShortcutManager 产生。

    if (action.command === 'close_tab') {
      const activeTabId = this.viewModel.getActiveTabId();
      if (activeTabId) {
        this.handleTabClose(activeTabId);
      }
      return;
    }

    if (action.command === 'close_window') {
      this.onCloseWindow();
      return;
    }

    if (action.command === 'restore_tab') {
      this.handleRestoreClosedTab();
      return;
    }

    if (action.command === 'open_dev_launcher') {
      this.openDevLauncher();
      return;
    }

    if (action.command === 'open_find_in_page') {
      this.openFindPanel();
      return;
    }

    if (action.command === 'find_next' || action.command === 'find_previous') {
      this.openFindDirection(action.command === 'find_next');
      return;
    }

    if (action.command === 'stop_loading') {
      this.stopActiveLoading();
      return;
    }

    if (action.command === 'toggle_fullscreen') {
      this.toggleFullScreen();
      return;
    }

    if (action.command === 'open_clear_browsing_data') {
      this.openClearBrowsingData();
      return;
    }

    if (action.command === 'print_page') {
      this.printCurrentPage();
      return;
    }

    if (action.command === 'save_page') {
      this.saveCurrentPage();
      return;
    }

    if (action.command === 'view_source') {
      this.viewCurrentPageSource();
      return;
    }

    if (action.command === 'open_file') {
      this.openLocalFile();
      return;
    }

    if (action.command === 'open_tab_search') {
      this.openTabSearch();
      return;
    }

    if (action.command === 'focus_address_bar') {
      this.focusAddressBar();
      return;
    }

    if (action.command === 'reload_tab' || action.command === 'reload_tab_ignore_cache') {
      this.closeTransientOverlays();
      this.reload(action.command === 'reload_tab_ignore_cache');
      return;
    }

    if (action.command === 'go_back') {
      this.handleBack();
      return;
    }

    if (action.command === 'go_forward') {
      this.handleForward();
      return;
    }

    if (action.command === 'go_home') {
      this.handleHome();
      return;
    }

    if (action.command === 'zoom_in') {
      this.adjustPageZoom(10);
      return;
    }

    if (action.command === 'zoom_out') {
      this.adjustPageZoom(-10);
      return;
    }

    if (action.command === 'zoom_reset') {
      this.resetPageZoom();
      return;
    }

    if (action.command === 'toggle_bookmark') {
      this.handleToggleCurrentPageBookmark();
      return;
    }

    if (action.command === 'toggle_bookmark_bar') {
      this.toggleBookmarkBar();
      return;
    }

    if (action.command === 'open_bookmarks') {
      this.openBookmarksManager();
      return;
    }

    if (action.command === 'open_history') {
      this.openHistoryManager();
      return;
    }

    if (action.command === 'open_downloads') {
      this.openDownloadsManager();
      return;
    }

    if ((action.command === 'next_tab' || action.command === 'prev_tab' || action.command === 'select_tab') &&
      action.targetTabId) {
      this.handleTabSelect(action.targetTabId);
    }
  }

  private applyViewState(
    state: BrowserPageViewState,
    loadWeb: boolean,
    refreshNavigationState: boolean = true,
    persistSession: boolean = true,
  ): void {
    const nextPrivateTabCount = this.countPrivateTabs(state.tabs);
    const navigationChanged = this.navCanGoBack !== state.canGoBack ||
      this.navCanGoForward !== state.canGoForward ||
      this.viewState.activeTabId !== state.activeTabId;
    if (navigationChanged) {
      hilog.info(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG,
        'NAV_UI_STATE tab=%{public}s back=%{public}s forward=%{public}s ' +
        'loadState=%{public}s loading=%{public}s url=%{public}s loadWeb=%{public}s refresh=%{public}s',
        state.activeTabId, String(state.canGoBack), String(state.canGoForward),
        state.tabs.find((item: Tab) => String(item.id) === state.activeTabId)?.loadState ?? 'none',
        String(state.tabs.find((item: Tab) => String(item.id) === state.activeTabId)?.isLoading ?? false),
        state.currentUrl, String(loadWeb), String(refreshNavigationState));
    }
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
      'NAV_UI_SNAPSHOT tab=%{public}s back=%{public}s forward=%{public}s ' +
      'url=%{public}s loadState=%{public}s loading=%{public}s changed=%{public}s',
      state.activeTabId, String(state.canGoBack), String(state.canGoForward), state.currentUrl,
      state.tabs.find((item: Tab) => String(item.id) === state.activeTabId)?.loadState ?? 'none',
      String(state.tabs.find((item: Tab) => String(item.id) === state.activeTabId)?.isLoading ?? false),
      String(navigationChanged));

    if (this.viewState.activeTabId !== state.activeTabId || state.showHome) {
      this.findText = '';
      this.showFindPanel = false;
      this.findMatchCount = 0;
      this.findActiveIndex = 0;
      this.currentPageScalePercent = 100;
    }

    this.viewState = state;
    // 编辑期间禁止外部状态回写地址栏：后台事件（onPageEnd/onPageBegin 等）会经
    // updateTabLoadState 清掉 tab.pendingUrl（编辑草稿），无守卫回写会把用户正在
    // 输入/粘贴的内容整体回滚成旧 URL，表现为“粘贴不生效”（非必现竞态）。
    if (!this.isAddressEditing) {
      this.addressText = state.addressText;
    }
    this.showHome = state.showHome;
    this.webSrc = state.showHome ? 'about:blank' : state.currentUrl;
    this.navCanGoBack = state.canGoBack;
    this.navCanGoForward = state.canGoForward;
    this.syncCurrentBookmarkState(state.currentUrl);
    if (state.showHome && state.activeTabId) {
      this.clearTabBrowserWebError(state.activeTabId);
    }
    this.syncPrivateSessionOwner(nextPrivateTabCount);

    if (!state.showHome) {
      this.ensureActiveRuntime();
      this.applyPageZoom();
      if (refreshNavigationState) {
        this.scheduleActiveNavigationStateRefresh();
      }
    }

    if (persistSession) {
      this.persistSession();
    }

    if (!loadWeb || state.showHome || !state.currentUrl) {
      return;
    }

    const activeTabId = this.viewModel.getActiveTabId();
    if (!activeTabId) {
      return;
    }

    this.loadTabUrl(activeTabId, state.currentUrl);
  }

  private loadTabUrl(tabId: TabId, url: string, force: boolean = false): void {
    if (!url || url === 'about:blank') {
      return;
    }

    const runtimeState = this.getTabWebRuntimeState(tabId);
    if (!runtimeState.controllerAttached) {
      if (runtimeState.requestedUrl !== url) {
        this.clearTabBrowserWebError(tabId);
        this.markTabLoadRequested(tabId, url);
      }
      runtimeState.pendingUrl = url;
      runtimeState.updatedAt = Date.now();
      return;
    }

    if (!force && this.shouldSkipTabUrlLoad(tabId, url)) {
      return;
    }

    const isQueuedRequest = force && runtimeState.pendingUrl === url && runtimeState.requestedUrl === url;
    this.performTabUrlLoad(tabId, url, isQueuedRequest);
  }

  private performTabUrlLoad(tabId: TabId, url: string, reuseCurrentRequest: boolean): void {
    const runtime = this.webViewManager.get(tabId);
    if (!runtime) {
      return;
    }
    const runtimeState = this.getTabWebRuntimeState(tabId);
    runtimeState.pendingUrl = '';
    this.clearTabBrowserWebError(tabId);
    if (!reuseCurrentRequest) {
      this.markTabLoadRequested(tabId, url);
    }
    try {
      const headers = this.webSettingsAdapter.buildInitialRequestHeaders();
      if (headers.length > 0) {
        runtime.controller.loadUrl(url, headers);
      } else {
        runtime.controller.loadUrl(url);
      }
    } catch (_) {
      this.invalidateTabFavicon(tabId);
      this.markTabLoadFailed(tabId, url);
      this.setTabBrowserWebError(createBrowserWebError({
        tabId: String(tabId),
        kind: 'network',
        url,
        errorCode: 'LOAD_URL_FAILED',
      }));
    }
  }

  private flushPendingTabLoad(tabId: TabId): void {
    const tab = this.findTab(tabId);
    const runtimeState = this.getTabWebRuntimeState(tabId);
    const pendingUrl = runtimeState.pendingUrl;
    if (!tab || tab.loadState === 'home' || pendingUrl.length === 0 || !this.webViewManager.get(tabId)) {
      return;
    }
    this.performTabUrlLoad(tabId, pendingUrl, runtimeState.requestedUrl === pendingUrl);
  }

  private handleTabControllerAttached(tabId: TabId, runtime: WebRuntime): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    this.syncTabRuntimeRevision(tabId, runtime);
    const tab = this.findTab(tabId);
    if (!tab) {
      return;
    }
    this.attachTabDownloadDelegate(tabId, runtime);
    this.uaManager.apply(runtime.controller, this.selectedUaMode);
    this.markTabControllerAttached(tabId);
    const pendingSource = this.pendingSourceViewerByTabId.get(String(tabId));
    if (pendingSource) {
      this.pendingSourceViewerByTabId.delete(String(tabId));
      this.markTabLoadRequested(tabId, pendingSource.historyUrl);
      try {
        runtime.controller.loadData(
          pendingSource.document,
          'text/html',
          'UTF-8',
          pendingSource.baseUrl,
          pendingSource.historyUrl,
        );
      } catch (_) {
        this.invalidateTabFavicon(tabId);
        this.markTabLoadFailed(tabId, pendingSource.historyUrl);
        this.applyViewState(
          this.viewModel.updateTabLoadFailed(tabId, pendingSource.historyUrl, pendingSource.historyUrl),
          false,
        );
      }
      return;
    }
    const pendingUrl = this.getTabWebRuntimeState(tabId).pendingUrl;
    if (pendingUrl.length > 0) {
      this.flushPendingTabLoad(tabId);
    } else {
      this.loadTabUrl(tabId, tab.url);
    }
    if (this.isActiveTabId(tabId)) {
      this.scheduleActiveNavigationStateRefresh();
    }
  }

  private attachTabDownloadDelegate(tabId: TabId, runtime: WebRuntime): void {
    if (!runtime.downloadDelegate) {
      runtime.downloadDelegate = this.downloadManager.createArkWebDownloadDelegate(
        (item: webview.WebDownloadItem) => {
          void this.handleArkWebDownload(tabId, runtime, item);
        });
    }
    try {
      runtime.controller.setDownloadDelegate(runtime.downloadDelegate);
      hilog.info(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'ARKWEB_DELEGATE_ATTACHED tab=%{public}s runtime=%{public}d', String(tabId), runtime.revision);
    } catch (error) {
      hilog.error(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'ARKWEB_DELEGATE_ATTACH_FAILED tab=%{public}s error=%{public}s', String(tabId), String(error));
    }
  }

  private async handleArkWebDownload(tabId: TabId, runtime: WebRuntime,
    item: webview.WebDownloadItem): Promise<void> {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      try {
        item.cancel();
      } catch (_) {
      }
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab) {
      try {
        item.cancel();
      } catch (_) {
      }
      return;
    }
    try {
      const hostContext = this.getUIContext().getHostContext();
      if (!hostContext) {
        item.cancel();
        return;
      }
      const fileName = item.getSuggestedFileName() || 'download';
      const fileUri = await this.downloadSettingsService.chooseDownloadFile(
        hostContext, fileName, item.getMimeType());
      if (fileUri.trim().length === 0) {
        item.cancel();
        return;
      }
      this.downloadManager.startArkWebDownload(item, {
        sourceUrl: item.getUrl(),
        suggestedFileName: fileName,
        mimeType: item.getMimeType(),
        pageUrl: tab.url,
        pageTitle: tab.title,
        userAgent: this.uaManager.getUserAgent(this.selectedUaMode),
        contentLength: item.getTotalBytes(),
        isPrivate: tab.isPrivate,
        downloadFileUri: fileUri,
      }, hostContext);
    } catch (error) {
      hilog.error(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'ARKWEB_BEFORE_DOWNLOAD_FAILED tab=%{public}s error=%{public}s', String(tabId), String(error));
      try {
        item.cancel();
      } catch (_) {
      }
    }
  }

  private handleTabWebDisappear(tabId: TabId, runtime: WebRuntime): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    this.cancelPendingNativeNavigation(tabId, 'runtime_disappeared');
    this.navigationStateSettlingUntilByTabId.delete(String(tabId));
    const state = this.syncTabRuntimeRevision(tabId, runtime);
    state.controllerAttached = false;
    state.pendingUrl = '';
    state.requestedUrl = '';
    state.updatedAt = Date.now();
  }

  private shouldSkipTabUrlLoad(tabId: TabId, url: string): boolean {
    return this.getTabWebRuntimeState(tabId).requestedUrl === url;
  }

  private markTabControllerAttached(tabId: TabId): void {
    const state = this.getTabWebRuntimeState(tabId);
    if (!state.controllerAttached && state.pendingUrl.length === 0) {
      state.requestedUrl = '';
    }
    state.controllerAttached = true;
    state.lastError = '';
    state.updatedAt = Date.now();
  }

  private markTabLoadRequested(tabId: TabId, url: string): void {
    const state = this.getTabWebRuntimeState(tabId);
    const navigationRevision = this.beginTabNavigationRevision(tabId, url);
    startWebNavigation(state.navigationLifecycle, url);
    this.beginFaviconGeneration(tabId, url);
    this.clearRuntimeTabFavicon(tabId);
    state.requestedUrl = url;
    state.lastError = '';
    state.updatedAt = Date.now();
    this.traceNavigationState('NAVIGATION_REVISION_BEGIN', tabId, null,
      `runtimeRevision=${state.runtimeRevision} navigationRevision=${navigationRevision} expectedUrl=${url}`);
  }

  private markTabLoadCommitted(tabId: TabId, url: string): void {
    const state = this.getTabWebRuntimeState(tabId);
    const navigationRevision = this.adoptTabNavigationRevision(tabId, url);
    state.requestedUrl = url;
    state.committedUrl = url;
    state.lastError = '';
    state.updatedAt = Date.now();
    this.traceNavigationState('NAVIGATION_REVISION_COMMIT', tabId, null,
      `runtimeRevision=${state.runtimeRevision} navigationRevision=${navigationRevision} ` +
      `committedHost=${this.describeNavigationUrl(url)}`
    );
  }

  private markTabLoadCompleted(tabId: TabId, url: string): void {
    const state = this.getTabWebRuntimeState(tabId);
    const navigationRevision = this.adoptTabNavigationRevision(tabId, url);
    completeWebNavigation(state.navigationLifecycle);
    state.pendingUrl = '';
    state.requestedUrl = url;
    state.committedUrl = url;
    state.loadedUrl = url;
    state.lastError = '';
    state.updatedAt = Date.now();
    this.traceNavigationState('NAVIGATION_REVISION_COMPLETE', tabId, null,
      `runtimeRevision=${state.runtimeRevision} navigationRevision=${navigationRevision} loadedUrl=${url}`);
  }

  private markTabLoadFailed(tabId: TabId, url: string): void {
    const state = this.getTabWebRuntimeState(tabId);
    this.cancelPendingNativeNavigation(tabId, 'navigation_failed');
    const navigationRevision = this.adoptTabNavigationRevision(tabId, url);
    failWebNavigation(state.navigationLifecycle);
    state.pendingUrl = '';
    state.requestedUrl = '';
    state.lastError = url;
    state.updatedAt = Date.now();
    this.traceNavigationState('NAVIGATION_REVISION_FAILED', tabId, null,
      `runtimeRevision=${state.runtimeRevision} navigationRevision=${navigationRevision} failedUrl=${url}`);
  }

  private beginTabControllerNavigation(tabId: TabId, expectedUrl: string = ''): void {
    const state = this.getTabWebRuntimeState(tabId);
    const navigationRevision = this.beginTabNavigationRevision(tabId, expectedUrl);
    startWebNavigation(state.navigationLifecycle);
    this.beginFaviconGeneration(tabId);
    this.clearRuntimeTabFavicon(tabId);
    state.requestedUrl = '';
    state.lastError = '';
    state.updatedAt = Date.now();
    this.traceNavigationState('NAVIGATION_REVISION_CONTROLLER_BEGIN', tabId, null,
      `runtimeRevision=${state.runtimeRevision} navigationRevision=${navigationRevision} ` +
      `expectedUrl=${expectedUrl || 'none'}`);
  }

  private enterTabHome(tabId: TabId): void {
    const state = this.getTabWebRuntimeState(tabId);
    enterWebNavigationHome(state.navigationLifecycle);
    state.pendingUrl = '';
    state.requestedUrl = '';
    state.committedUrl = '';
    state.loadedUrl = '';
    state.lastError = '';
    state.updatedAt = Date.now();
    const runtime = this.webViewManager.get(tabId);
    if (!runtime) {
      return;
    }
    try {
      runtime.controller.loadUrl('about:blank');
    } catch (_) {
    }
  }

  private clearRequestedUrlsForAllTabs(): void {
    this.webRuntimeStateByTabId.forEach((state: TabWebRuntimeState) => {
      state.pendingUrl = '';
      state.requestedUrl = '';
      state.updatedAt = Date.now();
    });
  }

  private clearTabWebRuntimeState(tabId: TabId): void {
    this.webRuntimeStateByTabId.delete(String(tabId));
    this.pendingSourceViewerByTabId.delete(String(tabId));
  }

  private currentRuntimeRevision(tabId: TabId): number {
    return this.webViewManager.get(tabId)?.revision ?? 0;
  }

  /**
   * Adopt the currently bound WebView runtime and invalidate state left by a
   * destroyed/recreated controller. Old callbacks are still rejected by the
   * object identity check, while the revision is also logged and checked by
   * delayed work such as title/favicon capture.
   */
  private syncTabRuntimeRevision(tabId: TabId, runtime?: WebRuntime): TabWebRuntimeState {
    const state = this.getTabWebRuntimeState(tabId);
    const revision = runtime?.revision ?? this.currentRuntimeRevision(tabId);
    if (revision > 0 && state.runtimeRevision !== revision) {
      const previousRevision = state.runtimeRevision;
      state.runtimeRevision = revision;
      state.navigationRevision += 1;
      state.navigationUrl = '';
      // A zero revision means the tab state was created before ArkUI attached
      // its first WebView. Preserve a queued URL in that case; only a real
      // runtime replacement invalidates the previous document state.
      if (previousRevision > 0) {
        state.pendingUrl = '';
        state.requestedUrl = '';
        state.committedUrl = '';
        state.loadedUrl = '';
        state.lastError = '';
      }
      state.controllerAttached = false;
      if (previousRevision > 0) {
        state.navigationLifecycle = createWebNavigationLifecycleState();
      }
      state.updatedAt = Date.now();
      this.traceNavigationState('RUNTIME_REVISION_SYNC', tabId, null,
        `previousRuntimeRevision=${previousRevision} runtimeRevision=${revision} ` +
        'navigationRevisionReset=true');
    }
    return state;
  }

  private getTabNavigationRevision(tabId: TabId): number {
    return this.getTabWebRuntimeState(tabId).navigationRevision;
  }

  private isCurrentTabNavigation(tabId: TabId, runtime: WebRuntime, navigationRevision: number,
    url: string = ''): boolean {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return false;
    }
    const state = this.syncTabRuntimeRevision(tabId, runtime);
    if (state.runtimeRevision !== runtime.revision || state.navigationRevision !== navigationRevision) {
      return false;
    }
    return url.length === 0 || state.navigationUrl.length === 0 || isSameHttpDocumentUrl(state.navigationUrl, url);
  }

  private beginTabNavigationRevision(tabId: TabId, expectedUrl: string = ''): number {
    const state = this.syncTabRuntimeRevision(tabId);
    state.navigationRevision += 1;
    state.navigationUrl = expectedUrl.trim();
    state.updatedAt = Date.now();
    return state.navigationRevision;
  }

  private adoptTabNavigationRevision(tabId: TabId, url: string): number {
    const state = this.syncTabRuntimeRevision(tabId);
    const normalizedUrl = url.trim();
    if (state.navigationRevision <= 0 ||
      (state.navigationUrl.length > 0 && !isSameHttpDocumentUrl(state.navigationUrl, normalizedUrl))) {
      state.navigationRevision += 1;
    }
    state.navigationUrl = normalizedUrl;
    state.updatedAt = Date.now();
    return state.navigationRevision;
  }

  private getTabWebRuntimeState(tabId: TabId): TabWebRuntimeState {
    const key = String(tabId);
    const existing = this.webRuntimeStateByTabId.get(key);
    if (existing) {
      return existing;
    }
    const state: TabWebRuntimeState = {
      runtimeRevision: this.currentRuntimeRevision(tabId),
      navigationRevision: 0,
      navigationUrl: '',
      controllerAttached: false,
      pendingUrl: '',
      requestedUrl: '',
      committedUrl: '',
      loadedUrl: '',
      lastError: '',
      navigationLifecycle: createWebNavigationLifecycleState(),
      updatedAt: Date.now(),
    };
    this.webRuntimeStateByTabId.set(key, state);
    return state;
  }

  private ensureActiveRuntime(): WebRuntime | null {
    const activeTabId = this.viewModel.getActiveTabId();
    if (!activeTabId) {
      return null;
    }
    return this.webViewManager.getOrCreate(
      activeTabId,
      this.jsBridgeOptions,
      this.getRuntimeProtectionIds(activeTabId),
    );
  }

  private ensureRuntimeForTab(tabId: TabId): WebRuntime {
    return this.webViewManager.getOrCreate(
      tabId,
      this.jsBridgeOptions,
      this.getRuntimeProtectionIds(tabId),
    );
  }

  private getRuntimeProtectionIds(preferredTabId?: TabId): string[] {
    const protectedIds: string[] = [];
    const add = (tabId: TabId | string | null): void => {
      if (tabId === null) {
        return;
      }
      const key = String(tabId);
      if (protectedIds.indexOf(key) < 0) {
        protectedIds.push(key);
      }
    };

    add(preferredTabId ?? this.viewModel.getActiveTabId());
    this.viewState.tabs.forEach((tab: Tab) => {
      if (tab.isLoading || tab.audible) {
        add(tab.id);
      }
    });
    if (this.pendingJavaScriptDialog) {
      add(this.pendingJavaScriptDialog.tabId);
    }
    if (this.showPermissionDialog) {
      add(this.permissionRequest.metadata?.tabId ?? null);
    }
    return protectedIds;
  }

  private updateWebContentLayout(width: number, height: number): void {
    if (width > 0) {
      this.webContentWidth = width;
    }
    if (height > 0) {
      this.webContentHeight = height;
    }
    if (this.showContextMenu) {
      this.repositionContextMenu();
    }
  }

  private readContextMenuString(reader: () => string): string {
    try {
      const value = reader();
      return value ? String(value).trim() : '';
    } catch (_) {
      return '';
    }
  }

  private readContextMenuBoolean(reader: () => boolean): boolean {
    try {
      return reader();
    } catch (_) {
      return false;
    }
  }

  private readContextMenuNumber(reader: () => number): number {
    try {
      const value = Number(reader());
      return Number.isFinite(value) ? value : 0;
    } catch (_) {
      return 0;
    }
  }

  private buildContextMenuItems(
    tabId: TabId,
    param: WebContextMenuParam,
  ): ContextMenuResolution {
    const linkUrl = this.readContextMenuString(() => param.getLinkUrl());
    const sourceUrl = this.readContextMenuString(() => param.getSourceUrl());
    const selectionText = this.readContextMenuString(() => param.getSelectionText());
    const editable = this.readContextMenuBoolean(() => param.isEditable());
    const editFlags = this.readContextMenuNumber(() => param.getEditStateFlags());
    const mediaType = this.readContextMenuNumber(() => param.getMediaType());
    const hasImage = this.readContextMenuBoolean(() => param.existsImageContents()) || mediaType === 1;
    const items: BrowserContextMenuItem[] = [];

    if (editable) {
      if ((editFlags & 1) !== 0) {
        items.push({ id: 'cut', label: '剪切', leadingIcon: '✂' });
      }
      if ((editFlags & 2) !== 0) {
        items.push({ id: 'copy', label: '复制', leadingIcon: '▣' });
      }
      if ((editFlags & 4) !== 0) {
        items.push({ id: 'paste', label: '粘贴', leadingIcon: '▤' });
      }
      if ((editFlags & 8) !== 0) {
        items.push({ id: 'select_all', label: '全选', leadingIcon: '▧' });
      }
    }

    if (linkUrl.length > 0) {
      const dividerBefore = items.length > 0;
      items.push({ id: 'open_link_new_tab', label: '在新标签页打开链接', leadingIcon: '+', dividerBefore });
      items.push({ id: 'open_link_current_tab', label: '在当前标签页打开链接', leadingIcon: '↗' });
      items.push({ id: 'copy_link', label: '复制链接地址', leadingIcon: '▣' });
    }

    if (hasImage) {
      const imageUrl = sourceUrl.length > 0 ? sourceUrl : linkUrl;
      const dividerBefore = items.length > 0;
      if (imageUrl.length > 0) {
        items.push({ id: 'open_image', label: '打开图片', leadingIcon: '◫', dividerBefore });
        items.push({ id: 'save_image', label: '保存图片', leadingIcon: '↓' });
        items.push({ id: 'copy_image_url', label: '复制图片地址', leadingIcon: '▣' });
      }
      items.push({
        id: 'copy_image',
        label: '复制图片',
        leadingIcon: '▧',
        dividerBefore: imageUrl.length === 0 && items.length > 0
      });
    }

    if (selectionText.length > 0 && !editable) {
      const dividerBefore = items.length > 0;
      items.push({ id: 'copy', label: '复制', leadingIcon: '▣', dividerBefore });
      items.push({ id: 'search_selection', label: '搜索选中文本', leadingIcon: '⌕' });
    }

    if (items.length === 0) {
      const tab = this.findTab(tabId);
      const controller = this.webViewManager.get(tabId)?.controller;
      let canGoBack = tab?.canGoBack ?? false;
      let canGoForward = tab?.canGoForward ?? false;
      if (controller) {
        const navigation = this.readControllerNavigationState(controller);
        // Keep an app-confirmed positive state even when the native list is
        // temporarily missing the new entry. Native `true` remains a useful
        // recovery hint for restored controllers.
        canGoBack = canGoBack || navigation.canGoBack;
        canGoForward = canGoForward || navigation.canGoForward;
      }
      items.push({ id: 'back', label: '后退', leadingIcon: '‹', disabled: !canGoBack });
      items.push({ id: 'forward', label: '前进', leadingIcon: '›', disabled: !canGoForward });
      items.push({ id: 'reload', label: '重新加载', leadingIcon: '↻', dividerBefore: true });
      if (tab && tab.url.length > 0 && tab.url !== 'about:blank') {
        items.push({ id: 'copy_page_address', label: '复制网页地址', leadingIcon: '▣' });
      }
    }

    return {
      items,
      linkUrl,
      sourceUrl,
      selectionText,
    };
  }

  private repositionContextMenu(): void {
    const position = this.resolveContextMenuPosition(
      this.contextMenuTriggerX,
      this.contextMenuTriggerY,
      this.contextMenuItems.length,
    );
    this.contextMenuX = position.x;
    this.contextMenuY = position.y;
  }

  private resolveContextMenuPosition(rawX: number, rawY: number, itemCount: number): ContextMenuPosition {
    const menuWidth = this.getContextMenuWidth();
    const maxMenuHeight = this.getContextMenuMaxHeight();
    const menuHeight = Math.min(maxMenuHeight, itemCount * 40 + 16);
    const width = Math.max(1, this.webContentWidth);
    const height = Math.max(1, this.webContentHeight);
    const maxX = Math.max(8, width - menuWidth - 8);
    const maxY = Math.max(8, height - menuHeight - 8);
    const preferredX = rawX + menuWidth <= width - 8 ? rawX : rawX - menuWidth;
    const preferredY = rawY + menuHeight <= height - 8 ? rawY : rawY - menuHeight;
    return {
      x: Math.max(8, Math.min(preferredX, maxX)),
      y: Math.max(8, Math.min(preferredY, maxY)),
    };
  }

  private getContextMenuWidth(): number {
    return Math.max(1, Math.min(248, this.webContentWidth - 16));
  }

  private getContextMenuMaxHeight(): number {
    return Math.max(1, Math.min(420, this.webContentHeight - 16));
  }

  private clearContextMenuState(): void {
    this.pendingContextMenu = null;
    this.contextMenuItems = [];
    this.showContextMenu = false;
  }

  private closeContextMenu(closeKernel: boolean = true): void {
    const pending = this.pendingContextMenu;
    this.clearContextMenuState();
    if (closeKernel && pending) {
      try {
        pending.result.closeContextMenu();
      } catch (_) {
      }
    }
  }

  private executeContextMenuResult(operation: (result: WebContextMenuResult) => void): void {
    const pending = this.pendingContextMenu;
    this.clearContextMenuState();
    if (!pending) {
      return;
    }
    try {
      operation(pending.result);
    } catch (_) {
      try {
        pending.result.closeContextMenu();
      } catch (_) {
      }
    }
  }

  private executeContextMenuPaste(): void {
    const pending = this.pendingContextMenu;
    this.clearContextMenuState();
    if (!pending) {
      return;
    }
    this.permissionService.ensureForPasteboard(this.getUIContext().getHostContext())
      .then((granted: boolean) => {
        try {
          if (granted) {
            pending.result.paste();
          } else {
            pending.result.closeContextMenu();
          }
        } catch (_) {
        }
      })
      .catch(() => {
        try {
          pending.result.closeContextMenu();
        } catch (_) {
        }
      });
  }

  private createTabContextMenuHandler(tabId: TabId): (event: OnContextMenuShowEvent) => boolean {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnContextMenuShowEvent): boolean => {
      if (!runtime) {
        return false;
      }
      return this.handleTabContextMenuShow(tabId, runtime, event);
    };
  }

  private createTabContextMenuHideHandler(tabId: TabId): () => void {
    const runtime = this.webViewManager.get(tabId);
    return (): void => {
      if (runtime && this.isCurrentTabRuntime(tabId, runtime)) {
        this.closeContextMenu(false);
      }
    };
  }

  private handleTabContextMenuShow(tabId: TabId, runtime: WebRuntime, event: OnContextMenuShowEvent): boolean {
    if (!this.isCurrentTabRuntime(tabId, runtime) || !this.isActiveTabId(tabId) || this.showHome) {
      return false;
    }
    const sourceType = this.readContextMenuNumber(() => event.param.getSourceType());
    const pointerPosition = sourceType === 1 ? this.webPointerPositionByTabId.get(String(tabId)) : undefined;
    const rawX = pointerPosition?.x ?? this.readContextMenuNumber(() => event.param.x());
    const rawY = pointerPosition?.y ?? this.readContextMenuNumber(() => event.param.y());
    if (rawX < 0 || rawY < 0) {
      return false;
    }
    const currentContextMenu = this.pendingContextMenu;
    if (this.showContextMenu && currentContextMenu &&
      currentContextMenu.tabId === String(tabId) && currentContextMenu.result === event.result) {
      return true;
    }

    this.closeContextMenu();
    const resolved = this.buildContextMenuItems(tabId, event.param);
    if (resolved.items.length === 0) {
      return false;
    }
    this.pendingContextMenu = {
      tabId: String(tabId),
      // The result belongs to the current native context-menu invocation and
      // must stay paired with the tab that created it.
      result: event.result,
      linkUrl: resolved.linkUrl,
      sourceUrl: resolved.sourceUrl,
      selectionText: resolved.selectionText,
    };
    this.contextMenuTriggerX = rawX;
    this.contextMenuTriggerY = rawY;
    const position = this.resolveContextMenuPosition(rawX, rawY, resolved.items.length);
    this.contextMenuItems = resolved.items;
    this.contextMenuX = position.x;
    this.contextMenuY = position.y;
    this.showContextMenu = true;
    return true;
  }

  private handleContextMenuDismiss(): void {
    this.closeContextMenu();
  }

  private navigateContextLinkInNewTab(url: string): void {
    if (url.length === 0) {
      return;
    }
    const nextState = this.viewModel.newTab(this.viewState.isPrivate);
    this.applyViewState(nextState, false);
    this.handleAddressSubmit(url);
  }

  private handleContextMenuSelect(item: BrowserContextMenuItem): void {
    const pending = this.pendingContextMenu;
    if (!pending || !this.isActiveTabId(pending.tabId as TabId)) {
      this.closeContextMenu();
      return;
    }

    switch (item.id) {
      case 'cut':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.cut());
        return;
      case 'copy':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.copy());
        return;
      case 'paste':
        this.executeContextMenuPaste();
        return;
      case 'select_all':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.selectAll());
        return;
      case 'copy_image':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.copyImage());
        return;
      case 'save_image': {
        const imageUrl = pending.sourceUrl || pending.linkUrl;
        const tab = this.findTab(pending.tabId as TabId);
        hilog.info(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
          'IMAGE_MENU_SELECTED tab=%{public}s sourceLength=%{public}d linkLength=%{public}d pageLength=%{public}d',
          String(pending.tabId), pending.sourceUrl.length, pending.linkUrl.length,
          tab?.url.length ?? 0);
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        if (imageUrl.length > 0 && tab) {
          // Keep image saving on the managed HTTP path. Calling ArkWeb
          // startDownload() loses the page request context and its async
          // failures bypass the image fallback service.
          void this.startImageDownload(imageUrl, tab).catch(() => {
          });
        }
        return;
      }
      case 'copy_link':
        this.executeContextMenuResult((result: WebContextMenuResult) => {
          this.clipboardService.copyText(pending.linkUrl);
          result.closeContextMenu();
        });
        return;
      case 'copy_image_url':
        this.executeContextMenuResult((result: WebContextMenuResult) => {
          this.clipboardService.copyText(pending.sourceUrl || pending.linkUrl);
          result.closeContextMenu();
        });
        return;
      case 'copy_page_address':
        this.executeContextMenuResult((result: WebContextMenuResult) => {
          const tab = this.findTab(pending.tabId as TabId);
          if (tab) {
            this.clipboardService.copyText(tab.url);
          }
          result.closeContextMenu();
        });
        return;
      case 'open_link_new_tab': {
        const url = pending.linkUrl;
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.navigateContextLinkInNewTab(url);
        return;
      }
      case 'open_link_current_tab':
      case 'open_image': {
        const url = item.id === 'open_image' ? (pending.sourceUrl || pending.linkUrl) : pending.linkUrl;
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.handleAddressSubmit(url);
        return;
      }
      case 'search_selection': {
        const text = pending.selectionText;
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.handleAddressSubmit(text);
        return;
      }
      case 'back':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.handleBack();
        return;
      case 'forward':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.handleForward();
        return;
      case 'reload':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.handleReload();
        return;
      default:
        this.closeContextMenu();
    }
  }

  private isActiveTabId(tabId: TabId): boolean {
    return this.viewState.activeTabId === String(tabId);
  }

  private getControllerForTab(tabId: TabId): webview.WebviewController {
    return this.ensureRuntimeForTab(tabId).controller;
  }

  private isCurrentTabRuntime(tabId: TabId, runtime: WebRuntime): boolean {
    return this.findTab(tabId) !== null && this.webViewManager.get(tabId) === runtime;
  }

  private createTabScaleChangeHandler(tabId: TabId): (event: OnScaleChangeEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnScaleChangeEvent): void => {
      if (runtime) {
        this.handleTabScaleChange(tabId, runtime, event);
      }
    };
  }

  private createTabMouseHandler(tabId: TabId): (event: MouseEvent) => void {
    return (event: MouseEvent): void => {
      if (event.button !== MouseButton.Right) {
        return;
      }
      const x = Number(event.x);
      const y = Number(event.y);
      if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0) {
        return;
      }
      this.webPointerPositionByTabId.set(String(tabId), { x, y });
    };
  }

  private createTabDownloadHandler(tabId: TabId): (event: OnDownloadStartEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnDownloadStartEvent): void => {
      if (runtime) {
        void this.handleDownloadStart(tabId, runtime, event);
      }
    };
  }

  private createTabLoadInterceptHandler(tabId: TabId): (event: OnLoadInterceptEvent) => boolean {
    return (event: OnLoadInterceptEvent): boolean => {
      let requestUrl = '';
      try {
        requestUrl = event.data.getRequestUrl();
      } catch (_) {
        return false;
      }
      if (!isExternalAppSchemeUrl(requestUrl)) {
        return false;
      }
      hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG,
        'EXTERNAL_SCHEME_BLOCKED tab=%{public}s scheme=%{public}s',
        String(tabId), extractUrlScheme(requestUrl));
      return true;
    };
  }

  private createTabGeolocationHandler(tabId: TabId): (event: OnGeolocationShowEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnGeolocationShowEvent): void => {
      if (!runtime) {
        event.geolocation.invoke(event.origin, false, false);
        return;
      }
      this.handleGeolocationShow(tabId, runtime, event).catch(() => {
        event.geolocation.invoke(event.origin, false, false);
      });
    };
  }

  private createTabPermissionHandler(tabId: TabId): (event: OnPermissionRequestEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnPermissionRequestEvent): void => {
      if (!runtime) {
        event.request.deny();
        return;
      }
      this.handleProtectedPermissionRequest(tabId, runtime, event).catch(() => {
        event.request.deny();
      });
    };
  }

  private createTabControllerAttachedHandler(tabId: TabId): () => void {
    const runtime = this.webViewManager.get(tabId);
    return (): void => {
      if (runtime) {
        this.handleTabControllerAttached(tabId, runtime);
      }
    };
  }

  private createTabDisappearHandler(tabId: TabId): () => void {
    const runtime = this.webViewManager.get(tabId);
    return (): void => {
      if (runtime) {
        this.handleTabWebDisappear(tabId, runtime);
      }
    };
  }

  private createTabPageBeginHandler(tabId: TabId): (event: OnPageBeginEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnPageBeginEvent): void => {
      if (runtime) {
        this.handleTabPageBegin(tabId, runtime, event);
      }
    };
  }

  private createTabPageEndHandler(tabId: TabId): (event: OnPageEndEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnPageEndEvent): void => {
      if (runtime) {
        this.handleTabPageEnd(tabId, runtime, event);
      }
    };
  }

  private createTabAudioStateChangedHandler(tabId: TabId): (event: OnAudioStateChangedEvent) => void {
    return (event: OnAudioStateChangedEvent): void => {
      this.handleTabAudioStateChanged(tabId, event);
    };
  }

  private createTabHistoryUpdateHandler(tabId: TabId): (details: LoadCommittedDetails) => void {
    const runtime = this.webViewManager.get(tabId);
    return (details: LoadCommittedDetails): void => {
      if (runtime) {
        this.handleTabHistoryUpdate(tabId, runtime, details);
      }
    };
  }

  private createTabTitleHandler(tabId: TabId): (event: OnTitleReceiveEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnTitleReceiveEvent): void => {
      if (runtime) {
        this.handleTabTitleReceive(tabId, runtime, event);
      }
    };
  }

  private createTabFaviconHandler(tabId: TabId): (event: OnFaviconReceivedEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnFaviconReceivedEvent): void => {
      if (runtime) {
        this.handleTabFaviconReceived(tabId, runtime, event);
      }
    };
  }

  private createTabAlertHandler(tabId: TabId): (event: OnAlertEvent) => boolean {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnAlertEvent): boolean => {
      if (!runtime) {
        event.result.handleCancel();
        return false;
      }
      return this.openJavaScriptDialog(tabId, runtime, 'alert', event.url, event.message, '', event.result);
    };
  }

  private createTabConfirmHandler(tabId: TabId): (event: OnConfirmEvent) => boolean {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnConfirmEvent): boolean => {
      if (!runtime) {
        event.result.handleCancel();
        return false;
      }
      return this.openJavaScriptDialog(tabId, runtime, 'confirm', event.url, event.message, '', event.result);
    };
  }

  private createTabPromptHandler(tabId: TabId): (event: OnPromptEvent) => boolean {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnPromptEvent): boolean => {
      if (!runtime) {
        event.result.handleCancel();
        return false;
      }
      return this.openJavaScriptDialog(tabId, runtime, 'prompt', event.url, event.message, event.value, event.result);
    };
  }

  private createTabBeforeUnloadHandler(tabId: TabId): (event: OnBeforeUnloadEvent) => boolean {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnBeforeUnloadEvent): boolean => {
      if (!runtime) {
        event.result.handleCancel();
        return false;
      }
      return this.openJavaScriptDialog(tabId, runtime, 'beforeunload', event.url, event.message, '', event.result);
    };
  }

  private createTabConsoleHandler(tabId: TabId): (event: OnConsoleEvent) => boolean {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnConsoleEvent): boolean => {
      if (!runtime || !this.isCurrentTabRuntime(tabId, runtime)) {
        return false;
      }
      try {
        const message = event.message;
        hilog.info(FAVICON_LOG_DOMAIN, 'WebConsole',
          'tab=%{public}s level=%{public}s source=%{public}s line=%{public}d message=%{public}s',
          String(tabId), String(message.getMessageLevel()), message.getSourceId(),
          message.getLineNumber(), message.getMessage());
      } catch (_) {
        hilog.info(FAVICON_LOG_DOMAIN, 'WebConsole', 'tab=%{public}s message=unavailable', String(tabId));
      }
      // false keeps the platform's normal console handling; this callback is
      // observational and must never suppress page diagnostics.
      return false;
    };
  }

  /**
   * Handles window.open()/target=_blank without letting ArkWeb block the
   * renderer. User-triggered non-dialog requests become a real browser tab;
   * dialog-style requests (window.open with width/height features) become a
   * chrome-less popup window whose Web binds to the pending ArkWeb handler.
   * Requests with no user gesture are blocked by default to match
   * popup-blocking UX.
   */
  private createTabWindowNewHandler(tabId: TabId): (event: OnWindowNewEvent) => void {
    return (event: OnWindowNewEvent): void => {
      this.handleTabWindowNewRequest(tabId, event);
    };
  }

  private handleTabWindowNewRequest(tabId: TabId, event: OnWindowNewEvent): void {
    const runtime = this.webViewManager.get(tabId);
    const sourceTab = this.findTab(tabId);
    const targetUrl = (event.targetUrl || '').trim();
    const resolvedTargetUrl = targetUrl.length > 0 ? targetUrl : 'about:blank';
    const runtimeValid = runtime !== null && this.isCurrentTabRuntime(tabId, runtime);
    hilog.info(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG,
      'REQUEST tab=%{public}s target=%{public}s isAlert=%{public}s user=%{public}s runtime=%{public}s',
      String(tabId), resolvedTargetUrl, String(event.isAlert), String(event.isUserTrigger), String(runtimeValid));

    if (!runtimeValid || !sourceTab) {
      this.cancelWebWindow(event.handler, 'invalid_request');
      return;
    }
    if (!event.isUserTrigger) {
      this.cancelWebWindow(event.handler, 'popup_blocked_no_user_gesture');
      return;
    }
    if (event.isAlert) {
      // 对话框式 window.open（带 width/height 特征，如微信扫码登录）。
      // 官方模式：在回调内同步创建全新 controller 并交给内核（此时弹窗 Web
      // 还不存在），随后把 controller 经 WindowService 注册表交给弹窗窗口的
      // Web 组件挂载，内核随组件挂载完成 window.open 的导航转移。
      const popupController = new webview.WebviewController();
      try {
        event.handler.setWebController(popupController);
      } catch (_) {
        this.cancelWebWindow(event.handler, 'popup_bind_failed');
        return;
      }
      const popupTitle = this.getPopupWindowTitle(resolvedTargetUrl);
      this.windowManager.openPopupWindow(this.getUIContext(), resolvedTargetUrl, popupTitle,
        popupController, this.uaManager.getUserAgent(this.selectedUaMode))
        .then(() => hilog.info(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG,
          'OPENED_POPUP_WINDOW sourceTab=%{public}s target=%{public}s', String(tabId), resolvedTargetUrl))
        .catch(() => {
          // 弹窗窗口创建失败：handler 已消费无法取消，退回普通窗口直接加载
          // 目标 URL，保证登录类流程不至于完全不可用。
          this.windowManager.openNormalWindow(this.getUIContext(), resolvedTargetUrl)
            .then(() => hilog.info(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG,
              'OPENED_NORMAL_WINDOW sourceTab=%{public}s target=%{public}s', String(tabId), resolvedTargetUrl))
            .catch(() => {
              this.showOperationToast('无法打开网页弹窗');
              hilog.error(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG,
                'OPEN_NORMAL_WINDOW_FAILED sourceTab=%{public}s target=%{public}s', String(tabId), resolvedTargetUrl);
            });
        });
      return;
    }

    const nextState = this.viewModel.newTabWithUrl(resolvedTargetUrl, sourceTab.isPrivate);
    this.closeTransientOverlays();
    this.applyViewState(nextState, true);
    const newTabId = nextState.activeTabId as TabId;
    const newRuntime = this.ensureRuntimeForTab(newTabId);
    try {
      event.handler.setWebController(newRuntime.controller);
      this.webOpenedTabIds.add(String(newTabId));
        hilog.info(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG,
          'OPENED_NEW_TAB sourceTab=%{public}s newTab=%{public}s target=%{public}s runtimeRevision=%{public}d',
        String(tabId), String(newTabId), resolvedTargetUrl, newRuntime.revision);
    } catch (_) {
      this.webViewManager.destroy(newTabId);
      this.showOperationToast('无法打开新标签页');
      this.cancelWebWindow(event.handler, 'set_controller_failed');
      hilog.error(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG,
        'SET_CONTROLLER_FAILED sourceTab=%{public}s newTab=%{public}s target=%{public}s',
        String(tabId), String(newTabId), resolvedTargetUrl);
    }
  }

  private createTabWindowExitHandler(tabId: TabId): () => void {
    return (): void => {
      const key = String(tabId);
      if (!this.webOpenedTabIds.has(key)) {
        return;
      }
      this.webOpenedTabIds.delete(key);
      hilog.info(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG, 'WINDOW_EXIT_CLOSE_TAB tab=%{public}s', key);
      this.handleTabClose(tabId);
    };
  }

  private cancelWebWindow(handler: ControllerHandler, reason: string): void {
    try {
      // ArkWeb documents null as the cancellation signal. The current ArkTS
      // declaration is non-nullable, so use the bottom type to preserve the
      // native null value without introducing an any/unknown cast.
      handler.setWebController(null as never);
      hilog.info(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG, 'CANCEL reason=%{public}s', reason);
    } catch (_) {
      hilog.error(FAVICON_LOG_DOMAIN, WEB_WINDOW_LOG_TAG, 'CANCEL_FAILED reason=%{public}s', reason);
    }
  }

  private getPopupWindowTitle(targetUrl: string): string {
    const url = targetUrl.trim();
    if (url.length === 0 || url === 'about:blank') {
      return '网页弹窗';
    }
    try {
      const hostPattern = new RegExp('^[a-z][a-z0-9+.-]*://([^/?#]+)', 'i');
      const match = hostPattern.exec(url);
      if (match && match.length > 1 && match[1]) {
        return match[1];
      }
    } catch (_) {
    }
    return '网页弹窗';
  }

  private openJavaScriptDialog(tabId: TabId, runtime: WebRuntime, kind: JavaScriptDialogKind,
    url: string, message: string, defaultValue: string, result: JsResult): boolean {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      result.handleCancel();
      return false;
    }
    // ArkWeb expects the callback to synchronously opt into application UI.
    // If a page races two dialogs, resolve the previous one conservatively.
    if (this.pendingJavaScriptDialog) {
      this.pendingJavaScriptDialog.result.handleCancel();
    }
    this.pendingJavaScriptDialog = {
      tabId: String(tabId),
      runtimeRevision: runtime.revision,
      kind: kind,
      url: url || this.findTab(tabId)?.url || '',
      message: message || '',
      defaultValue: defaultValue || '',
      result: result,
    };
    this.javaScriptDialogKind = kind;
    this.javaScriptDialogMessage = message || '';
    this.javaScriptDialogDefaultValue = defaultValue || '';
    this.javaScriptDialogInputValue = defaultValue || '';
    this.javaScriptDialogUrl = url || this.findTab(tabId)?.url || '';
    this.showJavaScriptDialog = true;
    hilog.info(FAVICON_LOG_DOMAIN, WEB_DIALOG_LOG_TAG, 'OPEN kind=%{public}s tab=%{public}s url=%{public}s',
      kind, String(tabId), this.javaScriptDialogUrl);
    return true;
  }

  private resolveJavaScriptDialog(confirmed: boolean): void {
    const pending = this.pendingJavaScriptDialog;
    if (!pending) {
      this.showJavaScriptDialog = false;
      return;
    }
    this.pendingJavaScriptDialog = null;
    this.showJavaScriptDialog = false;
    const currentRuntime = this.webViewManager.get(pending.tabId);
    const currentTab = this.findTab(pending.tabId);
    const stillCurrent = currentTab !== null && currentRuntime !== null &&
      currentRuntime.revision === pending.runtimeRevision;
    if (!stillCurrent) {
      pending.result.handleCancel();
      return;
    }
    try {
      if (!confirmed) {
        pending.result.handleCancel();
      } else if (pending.kind === 'prompt') {
        pending.result.handlePromptConfirm(this.javaScriptDialogInputValue);
      } else {
        pending.result.handleConfirm();
      }
      hilog.info(FAVICON_LOG_DOMAIN, WEB_DIALOG_LOG_TAG,
        'RESOLVE kind=%{public}s tab=%{public}s confirmed=%{public}s',
        pending.kind, pending.tabId, String(confirmed));
    } catch (error) {
      hilog.error(FAVICON_LOG_DOMAIN, WEB_DIALOG_LOG_TAG, 'RESOLVE_FAILED kind=%{public}s tab=%{public}s',
        pending.kind, pending.tabId);
      try {
        pending.result.handleCancel();
      } catch (_) {
      }
    }
  }

  private createTabErrorHandler(tabId: TabId): (event: OnErrorReceiveEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnErrorReceiveEvent): void => {
      if (runtime) {
        this.handleTabLoadError(tabId, runtime, event);
      }
    };
  }

  private createTabHttpErrorHandler(tabId: TabId): (event: OnHttpErrorReceiveEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnHttpErrorReceiveEvent): void => {
      if (runtime) {
        this.handleTabHttpError(tabId, runtime, event);
      }
    };
  }

  private createTabSslErrorHandler(): (event: OnSslErrorEventReceiveEvent) => void {
    return (event: OnSslErrorEventReceiveEvent): void => {
      // 证书错误（过期/自签/域不匹配等）直接放行，便于验证异常证书页面。
      try {
        event.handler.handleConfirm();
      } catch (_) {
      }
    };
  }

  private createTabRenderProcessNotRespondingHandler(tabId: TabId): (data: RenderProcessNotRespondingData) => void {
    const runtime = this.webViewManager.get(tabId);
    return (data: RenderProcessNotRespondingData): void => {
      if (runtime) {
        this.handleTabRenderProcessNotResponding(tabId, runtime, data);
      }
    };
  }

  private createTabRenderProcessRespondingHandler(tabId: TabId): () => void {
    const runtime = this.webViewManager.get(tabId);
    return (): void => {
      if (runtime) {
        this.handleTabRenderProcessResponding(tabId, runtime);
      }
    };
  }

  private createTabRenderExitedHandler(tabId: TabId): (event: OnRenderExitedEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnRenderExitedEvent): void => {
      if (runtime) {
        this.handleTabRenderExited(tabId, runtime, event);
      }
    };
  }

  private createTabSearchResultHandler(tabId: TabId): (event: OnSearchResultReceiveEvent) => void {
    const runtime = this.webViewManager.get(tabId);
    return (event: OnSearchResultReceiveEvent): void => {
      if (runtime) {
        this.handleFindSearchResult(tabId, runtime, event);
      }
    };
  }

  private handleTabScaleChange(tabId: TabId, runtime: WebRuntime, event: OnScaleChangeEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime) || !this.isActiveTabId(tabId)) {
      return;
    }
    const nextScale = this.clampPageZoomPercent(event.newScale);
    this.currentPageScalePercent = nextScale;
    if (!this.showMainMenu) {
      this.pageZoomPercent = nextScale;
    }
  }

  private handleTabPageBegin(tabId: TabId, runtime: WebRuntime, event: OnPageBeginEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const runtimeState = this.syncTabRuntimeRevision(tabId, runtime);
    if (this.showContextMenu && this.pendingContextMenu?.tabId === String(tabId)) {
      this.closeContextMenu();
    }
    const tab = this.findTab(tabId);
    if (tab?.loadState === 'home' && this.isAboutBlankUrl(event.url)) {
      return;
    }
    this.traceNavigationState('NAV_PAGE_BEGIN', tabId, null,
      `eventHost=${this.describeNavigationUrl(event.url)} ` +
      `tabHost=${this.describeNavigationUrl(this.findTab(tabId)?.url ?? '')} ` +
      `requestedHost=${this.describeNavigationUrl(runtimeState.requestedUrl)} ` +
      `committedHost=${this.describeNavigationUrl(runtimeState.committedUrl)} ` +
      `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${runtimeState.navigationRevision} ` +
      `loadState=${this.findTab(tabId)?.loadState ?? 'none'} ` +
      `isLoading=${String(this.findTab(tabId)?.isLoading ?? false)}`);
    if (!acceptWebPageBegin(runtimeState.navigationLifecycle, event.url)) {
      this.traceNavigationState('NAV_PAGE_BEGIN_IGNORED', tabId, null,
        `eventHost=${this.describeNavigationUrl(event.url)} ` +
        `lifecycle=${this.describeNavigationLifecycle(runtimeState.navigationLifecycle)}`);
      return;
    }
    this.clearTabBrowserWebError(tabId);
    const navigationRevision = this.adoptTabNavigationRevision(tabId, event.url);
    const hasCurrentNavigationFavicon = this.hasRuntimeTabFaviconForUrl(tabId, event.url) ||
      this.hasPendingFaviconForUrl(tabId, event.url);
    this.traceFavicon('PAGE_BEGIN', tabId, event.url,
      `hasCurrent=${hasCurrentNavigationFavicon} generation=${this.getFaviconGeneration(tabId)} ` +
      `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${navigationRevision} ` +
      `requested=${runtimeState.requestedUrl} committed=${runtimeState.committedUrl} ` +
      `tabHost=${this.describeNavigationUrl(tab?.url ?? '')} hasFavicon=${String((tab?.faviconUrl ?? '').length > 0)}`);
    this.markTabLoadCommitted(tabId, event.url);
    if (!hasCurrentNavigationFavicon) {
      const key = String(tabId);
      const expectedUrl = this.faviconGenerationExpectedUrlByTabId.get(key) ?? '';
      const awaitingPageBegin = this.faviconGenerationAwaitingPageBeginByTabId.get(key) === true;
      const matchesExistingGeneration = awaitingPageBegin &&
        (expectedUrl.length === 0 || isSameHttpDocumentUrl(expectedUrl, event.url));
      if (!matchesExistingGeneration) {
        this.beginFaviconGeneration(tabId, event.url);
        this.clearRuntimeTabFavicon(tabId);
      }
      this.faviconGenerationAwaitingPageBeginByTabId.set(key, false);
    }
    this.faviconGenerationExpectedUrlByTabId.set(String(tabId), event.url.trim());
    this.faviconGenerationAwaitingPageBeginByTabId.set(String(tabId), false);
    // The URL event is the authoritative navigation transition. Avoid a
    // controller refresh while loading because ArkWeb may still expose the
    // previous history entry at this point.
    this.applyViewState(this.viewModel.updateTabFromPageBegin(tabId, event.url), false, false);
    this.reapplyTabMuteToRuntime(tabId, runtime);
    this.invalidateTabDomMediaState(tabId);
    this.navigationStateSettlingUntilByTabId.set(
      String(tabId),
      Date.now() + NAVIGATION_STATE_SETTLE_MS,
    );
    const policy: JSBridgePolicy = this.jsBridgePolicy.resolve(event.url);
    const jsBridge = runtime.jsBridge;
    jsBridge.setEnabled(policy.enabled);
    jsBridge.setAllowedHosts(policy.allowedHosts);
    jsBridge.setCapabilityGateEnabled(policy.capabilityGateEnabled);
    jsBridge.setCapabilities(policy.capabilities);
    jsBridge.onPageBegin(event.url);
  }

  private handleTabPageEnd(tabId: TabId, runtime: WebRuntime, event: OnPageEndEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const runtimeState = this.syncTabRuntimeRevision(tabId, runtime);
    const navigationRevision = runtimeState.navigationRevision;
    const controllerUrl = this.readControllerUrl(runtime.controller);
    const tabUrl = this.findTab(tabId)?.url ?? '';
    const expectedUrls: string[] = [runtimeState.requestedUrl, runtimeState.committedUrl,
      tabUrl].filter((url: string) => this.isHttpUrl(url));
    this.traceNavigationState('NAV_PAGE_END', tabId, null,
      `eventHost=${this.describeNavigationUrl(event.url)} ` +
      `controllerHost=${this.describeNavigationUrl(controllerUrl)} ` +
      `tabHost=${this.describeNavigationUrl(tabUrl)} ` +
      `requestedHost=${this.describeNavigationUrl(runtimeState.requestedUrl)} ` +
      `committedHost=${this.describeNavigationUrl(runtimeState.committedUrl)} ` +
      `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${navigationRevision} ` +
      `loadState=${this.findTab(tabId)?.loadState ?? 'none'} ` +
      `isLoading=${String(this.findTab(tabId)?.isLoading ?? false)}`);
    const pageEndMatchesExpected = this.isHttpUrl(event.url) &&
      (expectedUrls.length === 0 || expectedUrls.some((url: string) =>
        isSameHttpDocumentUrl(url, event.url))) &&
      (!this.isHttpUrl(tabUrl) || isSameHttpDocumentUrl(tabUrl, event.url)) &&
      (controllerUrl.length === 0 || !this.isHttpUrl(controllerUrl) ||
        isSameHttpDocumentUrl(controllerUrl, event.url));
    if (!pageEndMatchesExpected) {
      this.traceFavicon('PAGE_END_IGNORED', tabId, event.url,
        `reason=url_mismatch requested=${runtimeState.requestedUrl} ` +
        `committedHost=${this.describeNavigationUrl(runtimeState.committedUrl)} ` +
        `tabHost=${this.describeNavigationUrl(tabUrl)} ` +
        `controllerHost=${this.describeNavigationUrl(controllerUrl)}`);
      this.syncTabNavigationStateFromController(tabId);
      return;
    }
    if (runtimeState.lastError.length > 0 ||
      !canCompleteWebNavigation(runtimeState.navigationLifecycle)) {
      this.traceNavigationState('NAV_PAGE_END_IGNORED', tabId, null,
        `reason=${runtimeState.lastError.length > 0 ? 'runtime_error' : 'invalid_lifecycle'} ` +
        `lifecycle=${this.describeNavigationLifecycle(runtimeState.navigationLifecycle)} ` +
        `lastError=${runtimeState.lastError}`);
      this.syncTabNavigationStateFromController(tabId);
      return;
    }
    this.clearTabBrowserWebError(tabId);
    this.markTabLoadCompleted(tabId, event.url);
    let pageTitle: string | undefined = undefined;
    const controller = runtime.controller;
    try {
      pageTitle = controller.getTitle();
    } catch (_) {
    }
    const normalizedPageTitle = pageTitle?.trim() ?? '';
    this.traceNavigationState('NAV_TITLE_PAGE_END', tabId, null,
      `eventHost=${this.describeNavigationUrl(event.url)} ` +
      `title=${normalizedPageTitle.length > 0 ? normalizedPageTitle : 'empty'}`);
    this.applyViewState(this.viewModel.updateTabFromPageEnd(
      tabId,
      event.url,
      normalizedPageTitle.length > 0 ? normalizedPageTitle : undefined,
    ), false);
    this.navigationStateSettlingUntilByTabId.set(
      String(tabId),
      Date.now() + NAVIGATION_STATE_SETTLE_MS,
    );
    this.traceFavicon('PAGE_END', tabId, event.url);
    // getFavicon() can still expose the previous document at PageEnd. Use it
    // only from the delayed fallback below, after the new document settles.
    this.scheduleTabFaviconCapture(tabId, runtime, navigationRevision);
    this.scheduleTabTitleCapture(tabId, runtime, event.url, navigationRevision);
    this.syncTabMediaState(tabId, runtime);
    this.scheduleTabMediaProbe(tabId, runtime);
    this.recordTabPageHistory(tabId, event.url, pageTitle);
    // applyViewState() already schedules a delayed native history refresh.
    // Reading here as well is prone to observing the pre-navigation list and
    // briefly reverting the state just committed by PageBegin/PageEnd.

    const jsBridge = runtime.jsBridge;
    jsBridge.onPageEnd(event.url);

    if (this.isActiveTabId(tabId)) {
      this.reapplyPageRuntimeVisualState();
    }
  }

  private handleTabHistoryUpdate(tabId: TabId, runtime: WebRuntime, details: LoadCommittedDetails): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    // Same-document navigations (fragment jumps, pushState/replaceState,
    // same-page history moves) never trigger onPageBegin/onPageEnd, so the
    // app-side NavigationController would otherwise never learn about them.
    // Document navigations are owned by the PageBegin/PageEnd handlers, with
    // one exception below.
    if (details.isMainFrame && !details.isSameDocument) {
      // A server-side redirect (e.g. baidu.com 301 -> www.baidu.com) may
      // trigger onPageBegin only once with the original request URL, while
      // onNavigationEntryCommitted/onPageEnd carry the final redirected URL.
      // Without adopting the committed URL here, the PageEnd pairing check
      // rejects the final URL as url_mismatch, markTabLoadCompleted never
      // runs and the tab stays loading until a manual refresh. Adopting the
      // URL produces exactly the state the normal timing (a second
      // onPageBegin with the final URL) would have produced.
      const redirectCommitUrl = details.url?.trim() ?? '';
      if (redirectCommitUrl && this.isHttpUrl(redirectCommitUrl)) {
        const redirectTab = this.findTab(tabId);
        const redirectRuntimeState = this.getTabWebRuntimeState(tabId);
        if (redirectTab && redirectTab.isLoading &&
          !isSameHttpDocumentUrl(redirectRuntimeState.committedUrl, redirectCommitUrl)) {
          this.traceNavigationState('NAV_REDIRECT_COMMIT', tabId, null,
            `eventHost=${this.describeNavigationUrl(redirectCommitUrl)} ` +
            `committedHost=${this.describeNavigationUrl(redirectRuntimeState.committedUrl)} ` +
            `tabHost=${this.describeNavigationUrl(redirectTab.url)}`);
          this.markTabLoadCommitted(tabId, redirectCommitUrl);
          this.applyViewState(this.viewModel.updateTabFromPageBegin(tabId, redirectCommitUrl), false, false);
        }
      }
      return;
    }
    if (!details.isMainFrame || !details.isSameDocument) {
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab || tab.loadState === 'home') {
      return;
    }
    const controllerUrl = this.readControllerUrl(runtime.controller);
    const url = details.url?.trim() || controllerUrl;
    this.traceNavigationState('NAV_HISTORY_UPDATE', tabId, null,
      `eventHost=${this.describeNavigationUrl(url)} controllerHost=${this.describeNavigationUrl(controllerUrl)} ` +
      `tabHost=${this.describeNavigationUrl(tab.url)} loading=${String(tab.isLoading)} ` +
      `didReplaceEntry=${String(details.didReplaceEntry)}`);
    if (!url || !this.isHttpUrl(url)) {
      return;
    }
    const key = String(tabId);
    const pendingDirection = this.pendingNativeNavigationByTabId.get(key);
    if (pendingDirection) {
      // A toolbar back/forward over same-document history entries never
      // triggers onPageBegin/onPageEnd; this commit event is the completion
      // signal that would otherwise only be recovered by the command timeout.
      // Settle only after the observed URL has actually left the command's
      // initial URL, otherwise the move has not happened yet.
      const initialUrl = this.nativeNavigationInitialUrlByTabId.get(key) ?? '';
      if (initialUrl.length > 0 && isSameHttpNavigationUrl(initialUrl, url)) {
        this.traceNavigationState('NAV_HISTORY_UPDATE_IGNORED', tabId, null,
          'reason=native_navigation_not_moved_yet');
        return;
      }
      const token = this.nativeNavigationCommandTokenByTabId.get(key) ?? 0;
      this.clearNativeNavigationCommand(tabId, pendingDirection, token, false);
      this.reconcileNativeNavigationWithoutCallbacks(tabId, runtime, url, pendingDirection);
      return;
    }
    if (tab.isLoading) {
      // A document navigation is in flight; onPageBegin/onPageEnd own the
      // model update. A same-document commit during load belongs to the
      // loading document (e.g. its initial history seeding).
      return;
    }
    if (isSameHttpNavigationUrl(tab.url, url)) {
      // The URL did not change: refresh the native flags only.
      if (this.isActiveTabId(tabId)) {
        this.scheduleActiveNavigationStateRefresh();
      }
      return;
    }
    // Same-document navigation committed (e.g. Baidu SERP pagination, SPA
    // routers): reconcile the app-side history and tab state now. A commit
    // that replaced the existing entry (replaceState) must overwrite the
    // current history entry instead of appending a new one.
    this.markTabLoadCommitted(tabId, url);
    this.markTabLoadCompleted(tabId, url);
    let title = '';
    try {
      title = runtime.controller.getTitle()?.trim() ?? '';
    } catch (_) {
    }
    this.applyViewState(details.didReplaceEntry
      ? this.viewModel.updateTabFromHistoryReplace(
        tabId,
        url,
        title.length > 0 ? title : undefined,
      )
      : this.viewModel.updateTabFromPageEnd(
        tabId,
        url,
        title.length > 0 ? title : undefined,
      ), false, false);
    this.navigationStateSettlingUntilByTabId.set(String(tabId), Date.now() + NAVIGATION_STATE_SETTLE_MS);
    if (this.isActiveTabId(tabId)) {
      this.scheduleActiveNavigationStateRefresh();
    }
  }

  private handleTabTitleReceive(tabId: TabId, runtime: WebRuntime, event: OnTitleReceiveEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const runtimeState = this.syncTabRuntimeRevision(tabId, runtime);
    const controllerUrl = this.readControllerUrl(runtime.controller);
    const tab = this.findTab(tabId);
    const tabUrl = tab?.url ?? '';
    if (controllerUrl.length > 0 && tabUrl.length > 0 && this.isHttpUrl(tabUrl) &&
      !isSameHttpDocumentUrl(controllerUrl, tabUrl)) {
      this.traceNavigationState('NAV_TITLE_RECEIVED_IGNORED', tabId, null,
        `reason=controller_url_mismatch ` +
        `controllerHost=${this.describeNavigationUrl(controllerUrl)} ` +
        `tabHost=${this.describeNavigationUrl(tabUrl)} ` +
        `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${runtimeState.navigationRevision}`);
      return;
    }
    const title = event.title?.trim() ?? '';
    this.traceNavigationState('NAV_TITLE_RECEIVED', tabId, null,
      `eventTitle=${title.length > 0 ? title : 'empty'} tabHost=${this.describeNavigationUrl(tabUrl)} ` +
      `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${runtimeState.navigationRevision}`);
    if (title.length === 0) {
      return;
    }
    // Title callbacks do not carry a URL and may arrive from the previous
    // document while a new navigation is loading. Delay committing the
    // ambiguous event until PageEnd's version-bound capture reads the title
    // from the current controller.
    if (tab?.isLoading === true) {
      this.traceNavigationState('NAV_TITLE_RECEIVED_DEFERRED', tabId, null,
        `reason=tab_loading title=${title} navigationRevision=${runtimeState.navigationRevision}`);
      return;
    }
    const key = String(tabId);
    const sequence = (this.titleReceiveSequenceByTabId.get(key) ?? 0) + 1;
    this.titleReceiveSequenceByTabId.set(key, sequence);
    const lifecycleGeneration = this.pageLifecycleGeneration;
    const runtimeRevision = runtime.revision;
    const navigationRevision = runtimeState.navigationRevision;
    setTimeout(() => {
      if (!this.isPageLifecycleCurrent(lifecycleGeneration) ||
        this.titleReceiveSequenceByTabId.get(key) !== sequence ||
        !this.isCurrentTabNavigation(tabId, runtime, navigationRevision)) {
        return;
      }
      const currentTab = this.findTab(tabId);
      if (!currentTab || currentTab.isLoading || currentTab.loadState === 'home') {
        return;
      }
      const currentControllerUrl = this.readControllerUrl(runtime.controller);
      if (this.isHttpUrl(currentTab.url) && this.isHttpUrl(currentControllerUrl) &&
        !isSameHttpDocumentUrl(currentTab.url, currentControllerUrl)) {
        this.traceNavigationState('NAV_TITLE_RECEIVED_IGNORED', tabId, null,
          `reason=delayed_controller_url_mismatch controllerHost=${this.describeNavigationUrl(currentControllerUrl)} ` +
          `tabHost=${this.describeNavigationUrl(currentTab.url)} ` +
          `runtimeRevision=${runtimeRevision} navigationRevision=${navigationRevision}`);
        return;
      }
      let currentControllerTitle = '';
      try {
        currentControllerTitle = runtime.controller.getTitle()?.trim() ?? '';
      } catch (_) {
        return;
      }
      if (currentControllerTitle.length === 0 || currentControllerTitle !== title) {
        this.traceNavigationState('NAV_TITLE_RECEIVED_IGNORED', tabId, null,
          `reason=delayed_controller_title_mismatch eventTitle=${title} ` +
          `controllerTitle=${currentControllerTitle || 'empty'} runtimeRevision=${runtimeRevision} ` +
          `navigationRevision=${navigationRevision}`);
        return;
      }
      this.applyViewState(this.viewModel.updateTabTitle(tabId, title), false, false);
    }, 80);
  }

  private scheduleTabTitleCapture(tabId: TabId, runtime: WebRuntime, url: string, navigationRevision: number): void {
    const delays: number[] = [80, 260, 700];
    delays.forEach((delay: number) => {
      setTimeout(() => this.captureTabTitle(tabId, runtime, url, delay, navigationRevision), delay);
    });
  }

  private captureTabTitle(tabId: TabId, runtime: WebRuntime, url: string, delay: number,
    navigationRevision: number): void {
    if (!this.isCurrentTabNavigation(tabId, runtime, navigationRevision, url)) {
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab || !this.isHttpUrl(tab.url) || !isSameHttpDocumentUrl(tab.url, url)) {
      return;
    }
    let title = '';
    try {
      title = runtime.controller.getTitle()?.trim() ?? '';
    } catch (_) {
      return;
    }
    this.traceNavigationState('NAV_TITLE_CAPTURE', tabId, null,
      `delay=${delay} url=${url} title=${title.length > 0 ? title : 'empty'} ` +
      `runtimeRevision=${runtime.revision} navigationRevision=${navigationRevision}`);
    if (title.length > 0 && title !== tab.title) {
      this.applyViewState(this.viewModel.updateTabTitle(tabId, title), false, false);
    }
  }

  private handleTabFaviconReceived(tabId: TabId, runtime: WebRuntime, event: OnFaviconReceivedEvent): void {
    const tab = this.findTab(tabId);
    if (!tab || tab.loadState === 'home' || !this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const navigationUrl = this.resolveFaviconNavigationUrl(tabId, runtime, tab.url);
    if (!navigationUrl) {
      this.traceFavicon('CALLBACK_IGNORED', tabId, tab.url, 'reason=no_navigation_url');
      return;
    }
    const runtimeState = this.syncTabRuntimeRevision(tabId, runtime);
    const navigationRevision = runtimeState.navigationRevision;
    const generationUrl = this.faviconGenerationExpectedUrlByTabId.get(String(tabId)) ?? '';
    if (generationUrl.length > 0 && !isSameHttpDocumentUrl(generationUrl, navigationUrl)) {
      this.traceFavicon('CALLBACK_IGNORED', tabId, navigationUrl,
        `reason=generation_url_mismatch generationUrl=${generationUrl}`);
      return;
    }
    const currentDocumentUrl = runtimeState.committedUrl || runtimeState.requestedUrl || tab.url;
    if (currentDocumentUrl.length > 0 && !isSameHttpDocumentUrl(currentDocumentUrl, navigationUrl)) {
      this.traceFavicon('CALLBACK_IGNORED', tabId, navigationUrl,
        `reason=document_url_mismatch currentDocument=${currentDocumentUrl}`);
      return;
    }
    this.traceFavicon('CALLBACK_RECEIVED', tabId, navigationUrl,
      `${this.describePixelMap(event.favicon)} generation=${this.getFaviconGeneration(tabId)} ` +
      `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${navigationRevision} ` +
      `requested=${runtimeState.requestedUrl} committed=${runtimeState.committedUrl} ` +
      `tabHost=${this.describeNavigationUrl(tab.url)} loading=${tab.isLoading}`);
    this.persistTabFavicon(tabId, runtime, event.favicon, navigationUrl, true, navigationRevision);
  }

  private captureTabFavicon(tabId: TabId, runtime: WebRuntime, navigationRevision: number): void {
    const tab = this.findTab(tabId);
    if (!tab || tab.loadState === 'home' || tab.isLoading || !this.isHttpUrl(tab.url) ||
      !this.isCurrentTabNavigation(tabId, runtime, navigationRevision, tab.url)) {
      return;
    }

    // A favicon callback is the authoritative source for this navigation.
    // ArkWeb's getFavicon() can temporarily return an empty/stale PixelMap at
    // PageEnd; replacing the callback result here makes the tab icon flash and
    // then turn blank. Keep this fallback only for pages that emitted no icon.
    if (this.hasRuntimeTabFaviconForUrl(tabId, tab.url) ||
      this.faviconDataUriByTabId.has(String(tabId))) {
      this.traceFavicon('CAPTURE_SKIPPED', tabId, tab.url, 'reason=already_present');
      return;
    }

    let favicon: PixelMap;
    try {
      const controllerUrl = this.readControllerUrl(runtime.controller);
      if (controllerUrl && !isSameHttpDocumentUrl(controllerUrl, tab.url)) {
        return;
      }
      favicon = runtime.controller.getFavicon();
    } catch (_) {
      this.traceFavicon('CAPTURE_IGNORED', tabId, tab.url, 'reason=get_favicon_failed');
      return;
    }
    if (!favicon) {
      this.traceFavicon('CAPTURE_IGNORED', tabId, tab.url, 'reason=empty_favicon');
      return;
    }
    this.traceFavicon('CAPTURED', tabId, tab.url, this.describePixelMap(favicon));
    this.persistTabFavicon(tabId, runtime, favicon, tab.url, false, navigationRevision);
  }

  private scheduleTabFaviconCapture(tabId: TabId, runtime: WebRuntime, navigationRevision: number): void {
    const generation = this.getFaviconGeneration(tabId);
    const runtimeRevision = runtime.revision;
    this.traceFavicon('CAPTURE_SCHEDULED', tabId, this.findTab(tabId)?.url ?? '',
      `generation=${generation} runtimeRevision=${runtimeRevision} ` +
      `navigationRevision=${navigationRevision} delays=250,1000`);
    [250, 1000].forEach((delay: number) => {
      setTimeout(() => {
        const currentUrl = this.findTab(tabId)?.url ?? '';
        this.traceFavicon('CAPTURE_TIMER', tabId, currentUrl,
          `delay=${delay} expectedGeneration=${generation} actualGeneration=${this.getFaviconGeneration(tabId)} ` +
          `expectedRuntimeRevision=${runtimeRevision} actualRuntimeRevision=${this.currentRuntimeRevision(tabId)} ` +
          `expectedNavigationRevision=${navigationRevision} ` +
          `actualNavigationRevision=${this.getTabNavigationRevision(tabId)} ` +
          `runtimeCurrent=${this.isCurrentTabRuntime(tabId, runtime)} ` +
          `data=${this.faviconDataUriByTabId.has(String(tabId))} ` +
          `runtimeFavicon=${this.hasRuntimeTabFaviconForCurrentTab(tabId)} ` +
          `pending=${this.hasPendingFaviconForUrl(tabId, currentUrl)}`);
        if (this.getFaviconGeneration(tabId) !== generation ||
          !this.isCurrentTabNavigation(tabId, runtime, navigationRevision, currentUrl) ||
          this.faviconDataUriByTabId.has(String(tabId)) ||
          this.hasRuntimeTabFaviconForCurrentTab(tabId) ||
          this.hasPendingFaviconForUrl(tabId, this.findTab(tabId)?.url ?? '')) {
          return;
        }
        this.captureTabFavicon(tabId, runtime, navigationRevision);
      }, delay);
    });
  }

  private persistTabFavicon(
    tabId: TabId,
    runtime: WebRuntime,
    favicon: PixelMap,
    navigationUrl: string,
    authoritative: boolean = true,
    navigationRevision: number = 0,
  ): void {
    const tab = this.findTab(tabId);
    if (!tab || tab.loadState === 'home' || !this.isHttpUrl(navigationUrl) ||
      !this.isCurrentTabRuntime(tabId, runtime)) {
      this.traceFavicon('PERSIST_IGNORED', tabId, navigationUrl, 'reason=invalid_tab_or_runtime');
      return;
    }
    // A single document can produce several favicon callbacks. The first
    // usable icon is authoritative; ArkWeb may send an empty/stale bitmap as
    // its last callback near PageEnd, which must not erase this tab's icon.
    const key = String(tabId);
    const runtimeState = this.syncTabRuntimeRevision(tabId, runtime);
    const effectiveNavigationRevision = navigationRevision > 0 ? navigationRevision : runtimeState.navigationRevision;
    if (runtimeState.runtimeRevision !== runtime.revision ||
      runtimeState.navigationRevision !== effectiveNavigationRevision ||
      (runtimeState.navigationUrl.length > 0 && !isSameHttpDocumentUrl(runtimeState.navigationUrl, navigationUrl))) {
      this.traceFavicon('PERSIST_IGNORED', tabId, navigationUrl,
        `reason=revision_mismatch runtimeRevision=${runtime.revision}/${runtimeState.runtimeRevision} ` +
        `navigationRevision=${effectiveNavigationRevision}/${runtimeState.navigationRevision} ` +
        `navigationUrl=${runtimeState.navigationUrl || 'none'}`);
      return;
    }
    const generationUrl = this.faviconGenerationExpectedUrlByTabId.get(key) ?? '';
    if (generationUrl.length > 0 && !isSameHttpDocumentUrl(generationUrl, navigationUrl)) {
      this.traceFavicon('PERSIST_IGNORED', tabId, navigationUrl,
        `reason=generation_url_mismatch generationUrl=${generationUrl}`);
      return;
    }
    const currentDocumentUrl = runtimeState.committedUrl || runtimeState.requestedUrl || tab.url;
    if (currentDocumentUrl.length > 0 && !isSameHttpDocumentUrl(currentDocumentUrl, navigationUrl)) {
      this.traceFavicon('PERSIST_IGNORED', tabId, navigationUrl,
        `reason=document_url_mismatch currentDocument=${currentDocumentUrl}`);
      return;
    }
    this.traceFavicon('PERSIST_CHECK', tabId, navigationUrl,
      `generation=${this.getFaviconGeneration(tabId)} requested=${runtimeState.requestedUrl} ` +
      `committedHost=${this.describeNavigationUrl(runtimeState.committedUrl)} ` +
      `tabHost=${this.describeNavigationUrl(tab.url)} ` +
      `runtimeRevision=${runtimeState.runtimeRevision} navigationRevision=${effectiveNavigationRevision} ` +
      `existingRuntime=${this.runtimeFaviconUrlByTabId.get(key) ?? 'none'} ` +
      `existingPending=${this.pendingFaviconUrlByTabId.get(key) ?? 'none'} ` +
      `existingData=${this.faviconDataUriByTabId.has(key)} ` +
      `incomingSource=${authoritative ? 'callback' : 'fallback'} ` +
      `existingSource=${this.runtimeFaviconSourceByTabId.get(key) ?? 'none'}`);
    const existingSource = this.runtimeFaviconSourceByTabId.get(key);
    const existingForUrl = this.hasRuntimeTabFaviconForUrl(tabId, navigationUrl);
    const existingData = this.faviconDataUriByTabId.has(key);
    if ((!authoritative && (existingForUrl || existingData)) ||
      (authoritative && existingSource === 'callback' && (existingForUrl || existingData))) {
      this.traceFavicon('PERSIST_IGNORED', tabId, navigationUrl,
        `reason=already_present incomingSource=${authoritative ? 'callback' : 'fallback'} ` +
        `existingSource=${existingSource ?? 'none'} existingForUrl=${existingForUrl} existingData=${existingData}`);
      return;
    }
    if (authoritative) {
      this.faviconDataUriByTabId.delete(key);
    }
    const capturedUrl = navigationUrl;
    const captureSequence = (this.faviconCaptureSequenceByTabId.get(key) ?? 0) + 1;
    this.faviconCaptureSequenceByTabId.set(key, captureSequence);
    // ArkWeb owns the callback PixelMap and may recycle it at PageEnd. Make a
    // private copy solely for PNG encoding. The tab strip intentionally does
    // not retain a PixelMap: its UI source is the stable favicon URL until the
    // encoded data URI is ready. This keeps an unrelated new-tab render from
    // invalidating an existing tab's icon.
    const encodingPixelMap = cloneFaviconPixelMap(favicon);
    this.traceFavicon('PERSIST_CLONED', tabId, capturedUrl,
      `encoding=${encodingPixelMap ? this.describePixelMap(encodingPixelMap) : 'none'} ` +
      `generation=${this.getFaviconGeneration(tabId)} sequence=${captureSequence}`);
    if (!encodingPixelMap) {
      this.pendingFaviconUrlByTabId.delete(key);
      this.traceFavicon('ENCODE_FAILED', tabId, capturedUrl, 'reason=encoding_clone_failed');
      return;
    }
    this.pendingFaviconUrlByTabId.set(key, capturedUrl);
    this.runtimeFaviconSourceByTabId.set(key, authoritative ? 'callback' : 'fallback');
    // Register the navigation without retaining a native PixelMap. This entry
    // prevents a stale delayed capture from replacing the current document.
    this.updateRuntimeTabFavicon(tabId, null, capturedUrl, false);
    this.traceFavicon('RUNTIME_SET', tabId, capturedUrl, 'presentationSource=url_or_data_uri');

    // Reuse an already encoded favicon immediately. This keeps the tab strip
    // on a local, stable image when a new tab is opened or an old tab is
    // rebound by ArkUI, instead of starting another remote Image load.
    const faviconCacheKey = normalizeFaviconCacheKey(tab.faviconUrl);
    const cachedDataUri = faviconCacheKey.length > 0 ? this.faviconDataUriByUrl.get(faviconCacheKey) ?? '' : '';
    if (cachedDataUri.length > 0) {
      this.pendingFaviconUrlByTabId.delete(key);
      this.faviconDataUriByTabId.set(key, cachedDataUri);
      this.updateRuntimeTabFaviconDataUri(tabId, capturedUrl, cachedDataUri);
      this.traceFavicon('CACHE_HIT', tabId, capturedUrl,
        `cacheKey=${faviconCacheKey} dataUriLength=${cachedDataUri.length}`);
      this.bookmarkManager.refreshBookmark(tab.url, tab.title, cachedDataUri);
      // The encoding copy is unnecessary on a cache hit. Release it here
      // rather than waiting for the async encode path, which is skipped.
      if (encodingPixelMap) {
        this.releaseFaviconPixelMap(encodingPixelMap);
      }
      return;
    }

    this.traceFavicon('ENCODE_BEGIN', tabId, capturedUrl, this.describePixelMap(encodingPixelMap));
    const generation = this.getFaviconGeneration(tabId);
    encodeFaviconDataUri(encodingPixelMap).then((dataUri) => {
      const currentTab = this.findTab(tabId);
      const currentRuntimeState = this.getTabWebRuntimeState(tabId);
      const pendingUrl = this.pendingFaviconUrlByTabId.get(key) ?? '';
      if (!dataUri || !currentTab || !isSameHttpDocumentUrl(currentTab.url, capturedUrl) ||
        !this.isCurrentTabRuntime(tabId, runtime) ||
        currentRuntimeState.runtimeRevision !== runtime.revision ||
        currentRuntimeState.navigationRevision !== effectiveNavigationRevision ||
        (currentRuntimeState.navigationUrl.length > 0 &&
          !isSameHttpDocumentUrl(currentRuntimeState.navigationUrl, capturedUrl)) ||
        this.getFaviconGeneration(tabId) !== generation ||
        this.faviconCaptureSequenceByTabId.get(key) !== captureSequence ||
        !isSameHttpDocumentUrl(pendingUrl, capturedUrl) ||
        (faviconCacheKey.length > 0 && normalizeFaviconCacheKey(currentTab?.faviconUrl) !== faviconCacheKey)) {
        if (isSameHttpDocumentUrl(pendingUrl, capturedUrl)) {
          this.pendingFaviconUrlByTabId.delete(key);
        }
        this.traceFavicon('ENCODE_IGNORED', tabId, capturedUrl,
          `hasData=${!!dataUri} generation=${this.getFaviconGeneration(tabId)}/${generation} ` +
          `sequence=${this.faviconCaptureSequenceByTabId.get(key) ?? 0}/${captureSequence}`);
        return;
      }
      this.pendingFaviconUrlByTabId.delete(key);
      this.faviconDataUriByTabId.set(key, dataUri);
      if (faviconCacheKey.length > 0) {
        this.faviconDataUriByUrl.set(faviconCacheKey, dataUri);
      }
      this.updateRuntimeTabFaviconDataUri(tabId, capturedUrl, dataUri);
      this.traceFavicon('ENCODE_APPLIED', tabId, capturedUrl,
        `dataUriLength=${dataUri.length} runtime=retained`);
      this.bookmarkManager.refreshBookmark(currentTab.url, currentTab.title, dataUri);
    }).catch(() => {
      if (isSameHttpDocumentUrl(this.pendingFaviconUrlByTabId.get(key) ?? '', capturedUrl)) {
        this.pendingFaviconUrlByTabId.delete(key);
      }
      this.traceFavicon('ENCODE_FAILED', tabId, capturedUrl);
    }).finally(() => {
      this.releaseFaviconPixelMap(encodingPixelMap);
    });
  }

  private hasRuntimeTabFaviconForCurrentTab(tabId: TabId): boolean {
    const tab = this.findTab(tabId);
    return !!tab && this.hasRuntimeTabFaviconForUrl(tabId, tab.url);
  }

  /**
   * onFaviconReceived does not include a URL. The controller URL is normally
   * the best signal, but it can advance before the tab model receives
   * onPageBegin. Accept the callback when it matches any URL belonging to the
   * active navigation generation, and use that URL for async validation.
   */
  private resolveFaviconNavigationUrl(tabId: TabId, runtime: WebRuntime, tabUrl: string): string {
    const controllerUrl = this.readControllerUrl(runtime.controller);

    const runtimeState = this.getTabWebRuntimeState(tabId);
    const candidates: string[] = [
      runtimeState.requestedUrl,
      runtimeState.committedUrl,
      tabUrl,
    ].filter((url: string) => this.isHttpUrl(url));

    if (controllerUrl.length > 0) {
      if (!this.isHttpUrl(controllerUrl)) {
        return '';
      }
      if (candidates.length > 0 && !candidates.some((url: string) =>
        isSameHttpDocumentUrl(controllerUrl, url))) {
        return '';
      }
      return controllerUrl;
    }

    return candidates.length > 0 ? candidates[0] : '';
  }

  private readControllerUrl(controller: webview.WebviewController): string {
    try {
      return controller.getUrl().trim();
    } catch (_) {
      return '';
    }
  }

  private beginFaviconGeneration(tabId: TabId, expectedUrl: string = ''): void {
    const key = String(tabId);
    const oldGeneration = this.faviconGenerationByTabId.get(key) ?? 0;
    this.traceFavicon('GENERATION_BEGIN', tabId, this.findTab(tabId)?.url ?? '',
      `oldGeneration=${oldGeneration} oldRuntime=${this.runtimeFaviconUrlByTabId.get(key) ?? 'none'} ` +
      `oldPending=${this.pendingFaviconUrlByTabId.get(key) ?? 'none'} ` +
      `oldData=${this.faviconDataUriByTabId.has(key)}`);
    const generation = (this.faviconGenerationByTabId.get(key) ?? 0) + 1;
    this.faviconGenerationByTabId.set(key, generation);
    this.faviconGenerationExpectedUrlByTabId.set(key, expectedUrl.trim());
    this.faviconGenerationAwaitingPageBeginByTabId.set(key, true);
    this.faviconDataUriByTabId.delete(key);
    this.pendingFaviconUrlByTabId.delete(key);
  }

  private getFaviconGeneration(tabId: TabId): number {
    return this.faviconGenerationByTabId.get(String(tabId)) ?? 0;
  }

  private updateRuntimeTabFavicon(
    tabId: TabId,
    favicon: PixelMap | null,
    navigationUrl: string,
    ownedByApp: boolean = false,
  ): void {
    const key = String(tabId);
    const removedEntries = this.runtimeTabFavicons.filter((item: TabFaviconPresentation) => item.tabId === key);
    const nextEntries = this.runtimeTabFavicons.filter((item: TabFaviconPresentation) => item.tabId !== key);
    this.runtimeFaviconRevision += 1;
    nextEntries.push({
      tabId: key,
      favicon: favicon,
      revision: this.runtimeFaviconRevision,
      ownedByApp,
      source: this.runtimeFaviconSourceByTabId.get(key) ?? 'callback',
    });
    this.runtimeTabFavicons = nextEntries;
    this.runtimeFaviconUrlByTabId.set(key, navigationUrl);
    this.releaseOwnedRuntimeFavicons(removedEntries);
    this.traceFavicon('RUNTIME_LIST_UPDATED', tabId, navigationUrl,
      `revision=${this.runtimeFaviconRevision} entries=${this.runtimeTabFavicons.length} ` +
      `removed=${removedEntries.map((item: TabFaviconPresentation) =>
        `${item.revision}:${item.ownedByApp ? 'owned' : 'native'}`).join(',') || 'none'} ` +
      `ownedByApp=${ownedByApp}`);
  }

  private updateRuntimeTabFaviconDataUri(tabId: TabId, navigationUrl: string, dataUri: string): void {
    const key = String(tabId);
    const entry = this.runtimeTabFavicons.find((item: TabFaviconPresentation) => item.tabId === key);
    if (!entry || !isSameHttpDocumentUrl(this.runtimeFaviconUrlByTabId.get(key) ?? '', navigationUrl)) {
      return;
    }
    this.runtimeFaviconRevision += 1;
    this.runtimeTabFavicons = this.runtimeTabFavicons.map((item: TabFaviconPresentation) => {
      if (item.tabId !== key) {
        return item;
      }
      return {
        tabId: item.tabId,
        favicon: item.favicon,
        revision: this.runtimeFaviconRevision,
        dataUri: dataUri,
        ownedByApp: item.ownedByApp,
        source: item.source,
      };
    });
    this.traceFavicon('DATA_URI_SET', tabId, navigationUrl,
      `revision=${this.runtimeFaviconRevision} dataUriLength=${dataUri.length}`);
  }

  private handleTabLoadError(tabId: TabId, runtime: WebRuntime, event: OnErrorReceiveEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    if (this.showContextMenu && this.pendingContextMenu?.tabId === String(tabId)) {
      this.closeContextMenu();
    }
    const url = event.request.getRequestUrl();
    if (!this.isCurrentMainFrameRequest(tabId, event.request.isMainFrame(), url)) {
      return;
    }
    if (!canFailWebNavigation(this.getTabWebRuntimeState(tabId).navigationLifecycle)) {
      return;
    }
    const errorInfo = this.readWebResourceErrorInfo(event.error);
    this.markTabLoadFailed(tabId, url);
    this.invalidateTabFavicon(tabId);
    this.applyViewState(this.viewModel.updateTabLoadFailed(tabId, url), false, false);
    this.setTabBrowserWebError(createBrowserWebError({
      tabId: String(tabId),
      kind: 'network',
      url,
      errorCode: errorInfo.code,
      detail: errorInfo.info,
    }));
  }

  private handleTabHttpError(tabId: TabId, runtime: WebRuntime, event: OnHttpErrorReceiveEvent): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const url = event.request.getRequestUrl();
    if (!this.isCurrentMainFrameRequest(tabId, event.request.isMainFrame(), url)) {
      return;
    }
    if (!canFailWebNavigation(this.getTabWebRuntimeState(tabId).navigationLifecycle)) {
      return;
    }

    let responseCode = 0;
    let responseReason = '';
    let responseData = '';
    let responseHeaders: BrowserResponseHeader[] = [];
    try {
      responseCode = event.response.getResponseCode();
      responseReason = event.response.getReasonMessage();
      responseData = event.response.getResponseData();
      responseHeaders = event.response.getResponseHeader();
    } catch (_) {
    }

    // ArkWeb still renders a server supplied 4xx/5xx document. Only provide
    // the native fallback when the response has no body to render.
    if (hasHttpResponseBody(responseData, responseHeaders)) {
      return;
    }
    this.markTabLoadFailed(tabId, url);
    this.invalidateTabFavicon(tabId);
    this.applyViewState(this.viewModel.updateTabLoadFailed(tabId, url), false, false);
    this.setTabBrowserWebError(createBrowserWebError({
      tabId: String(tabId),
      kind: 'http',
      url,
      statusCode: responseCode,
      errorCode: responseCode > 0 ? `HTTP ${String(responseCode)}` : 'HTTP_ERROR',
      detail: responseReason,
    }));
  }

  private handleTabRenderProcessNotResponding(
    tabId: TabId,
    runtime: WebRuntime,
    data: RenderProcessNotRespondingData,
  ): void {
    const tab = this.findTab(tabId);
    if (!tab || tab.loadState === 'home' || !this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    this.setTabBrowserWebError(createBrowserWebError({
      tabId: String(tabId),
      kind: 'renderer',
      url: this.getTabErrorUrl(tabId),
      errorCode: 'RENDERER_UNRESPONSIVE',
      detail: data.reason === RenderProcessNotRespondingReason.NAVIGATION_COMMIT_TIMEOUT
        ? '网页加载超时，可以重新加载页面。'
        : '网页进程没有及时响应，可以重新加载页面。',
    }));
  }

  private handleTabRenderProcessResponding(tabId: TabId, runtime: WebRuntime): void {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const current = findBrowserWebError(this.browserWebErrors, String(tabId));
    if (current?.kind === 'renderer' && current.errorCode === 'RENDERER_UNRESPONSIVE') {
      this.clearTabBrowserWebError(tabId, 'renderer');
    }
  }

  private handleTabRenderExited(tabId: TabId, runtime: WebRuntime, event: OnRenderExitedEvent): void {
    const tab = this.findTab(tabId);
    if (!tab || tab.loadState === 'home' || !this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const url = this.getTabErrorUrl(tabId);
    this.markTabLoadFailed(tabId, url);
    this.invalidateTabFavicon(tabId);
    this.applyViewState(this.viewModel.updateTabLoadFailed(tabId, url), false, false);
    this.setTabBrowserWebError(createBrowserWebError({
      tabId: String(tabId),
      kind: 'renderer',
      url,
      errorCode: `RENDERER_EXIT_${String(event.renderExitReason)}`,
      detail: '网页进程异常退出，可以重新加载页面。',
    }));
  }

  private readWebResourceErrorInfo(error: WebResourceError): WebResourceErrorInfo {
    let code = '';
    let info = '';
    try {
      code = String(error.getErrorCode());
    } catch (_) {
    }
    try {
      info = error.getErrorInfo();
    } catch (_) {
    }
    return { code, info };
  }

  private getTabErrorUrl(tabId: TabId): string {
    const runtimeState = this.getTabWebRuntimeState(tabId);
    if (runtimeState.requestedUrl.length > 0) {
      return runtimeState.requestedUrl;
    }
    if (runtimeState.committedUrl.length > 0) {
      return runtimeState.committedUrl;
    }
    return this.findTab(tabId)?.url ?? '';
  }

  private isCurrentMainFrameRequest(tabId: TabId, isMainFrame: boolean, url: string): boolean {
    const runtimeState = this.getTabWebRuntimeState(tabId);
    const tab = this.findTab(tabId);
    return isCurrentMainFrameNavigation(isMainFrame, url, [
      runtimeState.requestedUrl,
      runtimeState.committedUrl,
      tab?.url ?? '',
    ]);
  }

  private setTabBrowserWebError(error: BrowserWebErrorState): void {
    this.browserWebErrors = upsertBrowserWebError(this.browserWebErrors, error);
  }

  private clearTabBrowserWebError(tabId: TabId, kind?: BrowserWebErrorKind): void {
    this.browserWebErrors = clearBrowserWebError(this.browserWebErrors, String(tabId), kind);
  }

  private clearRuntimeTabFavicon(tabId: TabId): void {
    const key = String(tabId);
    const removedEntries = this.runtimeTabFavicons.filter((item: TabFaviconPresentation) => item.tabId === key);
    const nextEntries = this.runtimeTabFavicons.filter((item: TabFaviconPresentation) => item.tabId !== key);
    if (nextEntries.length !== this.runtimeTabFavicons.length) {
      this.runtimeTabFavicons = nextEntries;
    }
    this.runtimeFaviconUrlByTabId.delete(key);
    this.runtimeFaviconSourceByTabId.delete(key);
    this.releaseOwnedRuntimeFavicons(removedEntries);
    this.traceFavicon('RUNTIME_CLEARED', tabId, '',
      `removed=${removedEntries.length} ` +
      `entries=${removedEntries.map((item: TabFaviconPresentation) =>
        `${item.revision}:${item.ownedByApp ? 'owned' : 'native'}`).join(',') || 'none'}`);
  }

  private releaseOwnedRuntimeFavicons(entries: TabFaviconPresentation[]): void {
    entries.forEach((entry: TabFaviconPresentation) => {
      if (entry.ownedByApp && entry.favicon) {
        this.releaseFaviconPixelMap(entry.favicon);
      }
    });
  }

  private releaseFaviconPixelMap(favicon: PixelMap): void {
    // Let ArkUI finish the frame that detached the old Image before releasing
    // its backing store. This matters when a TabItem is recreated by the
    // favicon revision at the same time as PageEnd updates the tab model.
    setTimeout(() => {
      const pixelInfo = this.describePixelMap(favicon);
      favicon.release().catch(() => {
        hilog.warn(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG,
          'PIXELMAP_RELEASE_FAILED %{public}s', pixelInfo);
      });
    }, FAVICON_RELEASE_DELAY_MS);
  }

  private describePixelMap(favicon: PixelMap): string {
    try {
      const info = favicon.getImageInfoSync();
      return `size=${info.size.width}x${info.size.height} bytes=${favicon.getPixelBytesNumber()}`;
    } catch (_) {
      return 'pixelMapInfo=unavailable';
    }
  }

  private traceFavicon(stage: string, tabId: TabId, url: string = '', detail: string = ''): void {
    const key = String(tabId);
    const tab = this.findTab(tabId);
    const runtimeEntry = this.runtimeTabFavicons.find((item: TabFaviconPresentation) => item.tabId === key);
    const faviconUrl = tab?.faviconUrl ?? '';
    const cachedDataUri = this.faviconDataUriByTabId.get(key) ?? '';
    const runtimeState = this.getTabWebRuntimeState(tabId);
    hilog.info(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG,
      '%{public}s tab=%{public}s url=%{public}s loading=%{public}s runtime=%{public}s runtimeRev=%{public}d ' +
      'stateRuntimeRev=%{public}d navigationRev=%{public}d modelIcon=%{public}s cache=%{public}s %{public}s',
      stage, key, url, String(tab?.isLoading ?? false), String(runtimeEntry !== undefined),
      runtimeEntry?.revision ?? 0, runtimeState.runtimeRevision, runtimeState.navigationRevision,
      faviconUrl.length > 0 ? `${faviconUrl.slice(0, 24)}(${faviconUrl.length})` : 'none',
      cachedDataUri.length > 0 ? `data(${cachedDataUri.length})` : 'none', detail);
  }

  private tracePermission(stage: string, detail: string): void {
    const message = `PermissionTrace ${stage} ${detail}`;
    hilog.info(FAVICON_LOG_DOMAIN, 'PermissionTrace', '%{public}s', message);
    // Keep permission diagnostics visible in the same stream currently used
    // by the device test procedure.
    hilog.info(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG, '%{public}s', message);
  }

  private traceNavigationState(
    stage: string,
    tabId: TabId | null,
    state: ControllerNavigationState | null,
    detail: string = '',
  ): void {
    // Navigation state may contain URLs, history entries and runtime identifiers.
    // Keep this diagnostic event constant so no page or runtime data reaches logs.
    hilog.info(FAVICON_LOG_DOMAIN, NAVIGATION_LOG_TAG, 'NAV_STATE_UPDATED');
  }

  /** Keep navigation diagnostics useful without exposing full paths/query strings. */
  private describeNavigationUrl(url: string): string {
    const value = url.trim();
    if (value.length === 0) {
      return 'none';
    }
    try {
      const match = /^(?:[a-z][a-z0-9+.-]*:)?\/\/([^/?#]+)/i.exec(value);
      if (match && match[1]) {
        return match[1];
      }
    } catch (_) {
    }
    return value.split(/[/?#]/, 1)[0] || 'present';
  }

  private describeNavigationLifecycle(state: WebNavigationLifecycleState): string {
    return `generation=${state.generation},began=${state.beganGeneration},` +
      `completed=${state.completedGeneration},suppressed=${String(state.suppressPageCallbacks)}`;
  }

  private hasRuntimeTabFaviconForUrl(tabId: TabId, url: string): boolean {
    const key = String(tabId);
    const faviconUrl = this.runtimeFaviconUrlByTabId.get(key);
    if (!faviconUrl || !isSameHttpDocumentUrl(faviconUrl, url)) {
      return false;
    }
    return this.runtimeTabFavicons.some((item: TabFaviconPresentation) => item.tabId === key);
  }

  private hasPendingFaviconForUrl(tabId: TabId, url: string): boolean {
    const pendingUrl = this.pendingFaviconUrlByTabId.get(String(tabId));
    return !!pendingUrl && isSameHttpDocumentUrl(pendingUrl, url);
  }

  private invalidateTabFavicon(tabId: TabId): void {
    this.beginFaviconGeneration(tabId);
    this.clearRuntimeTabFavicon(tabId);
  }

  private getActiveRuntime(): WebRuntime | null {
    const activeTabId = this.viewModel.getActiveTabId();
    if (!activeTabId) {
      return null;
    }
    return this.webViewManager.get(activeTabId);
  }

  private getActiveController(): webview.WebviewController | null {
    return this.getActiveRuntime()?.controller ?? null;
  }

  private getActiveJsBridge(): JSBridgeFacade | null {
    return this.getActiveRuntime()?.jsBridge ?? null;
  }

  private shouldRenderTabWeb(tab: Tab): boolean {
    // Read the revision so an LRU eviction invalidates this render decision and
    // unmounts the native Web view whose runtime was released.
    const mountRevision = this.runtimeMountRevision;
    if (mountRevision < 0) {
      return false;
    }
    // Keep already-live runtimes mounted for session continuity. A tab whose
    // runtime was evicted is recreated only when it becomes active and is
    // needed for a real web document; home tabs do not allocate a WebView.
    return this.webViewManager.has(tab.id) ||
      (!this.showHome && this.isActiveTabId(tab.id));
  }

  private getTabWebWidth(tabId: TabId): Length {
    // ArkWeb uses a native rendering layer. Opacity alone does not reliably stop an
    // inactive Web from covering the ArkUI new-tab home page.
    const tab = this.findTab(tabId);
    return this.isActiveTabId(tabId) && tab?.loadState !== 'home' ? '100%' : 1;
  }

  private getTabWebHeight(tabId: TabId): Length {
    const tab = this.findTab(tabId);
    return this.isActiveTabId(tabId) && tab?.loadState !== 'home' ? '100%' : 1;
  }

  private getTabWebOpacity(tabId: TabId): number {
    const tab = this.findTab(tabId);
    return this.isActiveTabId(tabId) && tab?.loadState !== 'home' ? 1 : 0;
  }

  private onZoomOutWindow(): void {
    this.windowManager.zoomOut(this.getUIContext()).catch(() => {
    });
  }

  private onZoomInWindow(): void {
    this.windowManager.zoomIn(this.getUIContext()).catch(() => {
    });
  }

  private onMinimizeWindow(): void {
    this.windowManager.minimize(this.getUIContext()).catch(() => {
    });
  }

  private onMaximizeWindow(): void {
    this.windowManager.maximize(this.getUIContext()).catch(() => {
    });
  }

  private onCloseWindow(): void {
    this.windowManager.close(this.getUIContext()).catch(() => {
    });
  }

  private openBookmarkBarItem(bookmark: BookmarkItem): void {
    if (bookmark.isFolder) {
      this.openBookmarksManager();
      return;
    }
    this.handleAddressSubmit(bookmark.url);
  }

  private async handleDownloadStart(tabId: TabId, runtime: WebRuntime,
    event: OnDownloadStartEvent): Promise<void> {
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab) {
      return;
    }
    const currentPageUrl = tab.url;
    let currentPageTitle: string | undefined = undefined;
    const controller = runtime.controller;
    if (controller) {
      try {
        currentPageTitle = controller.getTitle();
      } catch (_) {
      }
    }

    const fileName = extractFileNameFromContentDisposition(event.contentDisposition) ||
      event.url.split(/[\\/?#]/).pop() || 'download';
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      return;
    }
    const fileUri = await this.downloadSettingsService.chooseDownloadFile(
      hostContext, fileName, event.mimetype);
    if (fileUri.trim().length === 0) {
      return;
    }
    this.downloadManager.startWebDownload({
      sourceUrl: event.url,
      contentDisposition: event.contentDisposition,
      mimeType: event.mimetype,
      pageUrl: currentPageUrl,
      pageTitle: currentPageTitle || tab.title,
      userAgent: event.userAgent,
      contentLength: event.contentLength,
      isPrivate: tab.isPrivate,
      downloadFileUri: fileUri,
    }, hostContext).catch(() => {
    });
  }

  private async startImageDownload(imageUrl: string, tab: Tab): Promise<void> {
    const imageMimeType = inferImageMimeType(imageUrl, 'image/*');
    const fileName = buildImageDownloadFileName(imageUrl);
    hilog.info(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
      'IMAGE_SAVE_BEGIN sourceLength=%{public}d fileNameLength=%{public}d pageLength=%{public}d private=%{public}s',
      imageUrl.length, fileName.length, tab.url.length, String(tab.isPrivate));
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      hilog.error(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'IMAGE_SAVE_ABORT reason=no_host_context');
      return;
    }
    const fileUri = await this.downloadSettingsService.chooseDownloadFile(
      hostContext, fileName, imageMimeType);
    hilog.info(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
      'IMAGE_SAVE_PICKER_RESULT fileUriPresent=%{public}s fileNameLength=%{public}d',
      String(fileUri.trim().length > 0), fileName.length);
    if (fileUri.trim().length === 0) {
      hilog.info(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'IMAGE_SAVE_ABORT reason=picker_cancelled');
      return;
    }
    const task = await this.downloadManager.startWebDownload({
      sourceUrl: imageUrl,
      suggestedFileName: fileName,
      mimeType: imageMimeType,
      pageUrl: tab.url,
      pageTitle: tab.title,
      userAgent: this.uaManager.getUserAgent(this.selectedUaMode),
      isPrivate: tab.isPrivate,
      downloadFileUri: fileUri,
    }, hostContext);
    hilog.info(FAVICON_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
      'IMAGE_SAVE_TASK_CREATED task=%{public}s fileUriPresent=%{public}s',
      task.id, String(fileUri.trim().length > 0));
  }

  private handlePermissionDialogDecision(): void {
    if (this.permissionDecisionPending) {
      return;
    }
    const activeRequest = this.permissionManager.getActiveRequest();
    if (!activeRequest) {
      return;
    }

    this.permissionDecisionPending = true;
    this.tracePermission('BROWSER_PERMISSION_PROMPT_DECISION',
      `type=${activeRequest.permissionType} decision=allow prompt=custom`);
    this.ensureSystemPermission(activeRequest.permissionType)
      .then((granted: boolean) => {
        this.permissionManager.resolveActiveRequest(
          granted ? 'allow' : 'deny',
          granted ? this.permissionRememberChoice : false
        );
      })
      .catch(() => {
        this.tracePermission('SYSTEM_PERMISSION_GATE_ERROR', `type=${activeRequest.permissionType}`);
        this.permissionManager.resolveActiveRequest('deny', false);
      });
  }

  private handlePermissionDialogCancel(): void {
    if (this.permissionDecisionPending) {
      return;
    }
    const activeRequest = this.permissionManager.getActiveRequest();
    if (!activeRequest) {
      return;
    }
    this.tracePermission('BROWSER_PERMISSION_PROMPT_DECISION',
      `type=${activeRequest.permissionType} decision=deny prompt=custom`);
    this.permissionManager.resolveActiveRequest('deny', this.permissionRememberChoice);
  }

  private async ensureSystemPermission(permissionType: SitePermissionType): Promise<boolean> {
    this.tracePermission('SYSTEM_PERMISSION_GATE_BEGIN',
      `type=${permissionType} context=${String(this.getUIContext().getHostContext() !== undefined)}`);
    const granted = await this.permissionService.ensureForSitePermission(
      this.getUIContext().getHostContext(), permissionType);
    this.tracePermission('SYSTEM_PERMISSION_GATE_END',
      `type=${permissionType} granted=${String(granted)}`);
    return granted;
  }

  private async handleGeolocationShow(tabId: TabId, runtime: WebRuntime, event: OnGeolocationShowEvent): Promise<void> {
    this.tracePermission('GEOLOCATION_REQUEST_RECEIVED',
      `tab=${String(tabId)} origin=${event.origin} currentRuntime=${String(this.isCurrentTabRuntime(tabId, runtime))}`);
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      event.geolocation.invoke(event.origin, false, false);
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab) {
      event.geolocation.invoke(event.origin, false, false);
      return;
    }
    const origin = event.origin && event.origin.trim().length > 0
      ? event.origin
      : extractSiteOriginFromUrl(tab.url);

    try {
      if (!SITE_PERMISSION_PROMPT_ENABLED) {
        const systemGranted = await this.ensureSystemPermission('location');
        this.tracePermission('SITE_PERMISSION_BYPASS',
          `tab=${String(tabId)} origin=${origin} type=location systemGranted=${String(systemGranted)}`);
        event.geolocation.invoke(origin, systemGranted, false);
        return;
      }

      const result = await this.permissionManager.requestPermission({
        origin: origin,
        permissionType: 'location',
        title: getSitePermissionTitle('location'),
        message: getSitePermissionMessage(origin, 'location'),
        allowRememberChoice: true,
        rememberChoiceDefault: false,
        metadata: {
          pageUrl: tab.url,
          tabId: String(tabId),
          isPrivate: tab.isPrivate,
        },
      });

      if (!this.isCurrentTabRuntime(tabId, runtime)) {
        event.geolocation.invoke(origin, false, false);
        return;
      }

      // A stored browser decision does not guarantee that the OS permission
      // is still granted. Always reconcile the user decision with the current
      // platform permission before allowing the web origin.
      let allow = result.decision === 'allow';
      if (allow) {
        allow = await this.ensureSystemPermission('location');
      }
      this.tracePermission('GEOLOCATION_RESULT',
        `tab=${String(tabId)} origin=${origin} decision=${result.decision} ` +
        `source=${result.source} systemGranted=${String(allow)}`);
      const shouldPersistKernelDecision = allow && !tab.isPrivate ? result.rememberChoice : false;
      event.geolocation.invoke(origin, allow, shouldPersistKernelDecision);
    } catch (_) {
      event.geolocation.invoke(origin, false, false);
    }
  }

  private async handleProtectedPermissionRequest(
    tabId: TabId,
    runtime: WebRuntime,
    event: OnPermissionRequestEvent
  ): Promise<void> {
    this.tracePermission('PROTECTED_PERMISSION_RECEIVED',
      `tab=${String(tabId)} currentRuntime=${String(this.isCurrentTabRuntime(tabId, runtime))}`);
    if (!this.isCurrentTabRuntime(tabId, runtime)) {
      event.request.deny();
      return;
    }
    const tab = this.findTab(tabId);
    if (!tab) {
      event.request.deny();
      return;
    }
    const request = event.request;
    const origin = request.getOrigin() || extractSiteOriginFromUrl(tab.url);
    const resources = request.getAccessibleResource();
    const grantedResources: string[] = [];
    this.tracePermission('PROTECTED_PERMISSION_REQUEST',
      `tab=${String(tabId)} origin=${origin} resources=${resources.join(',')} prompt=browser`);

    try {
      for (let index = 0; index < resources.length; index++) {
        const resource = resources[index];
        const permissionType = mapProtectedResourceToSitePermissionType(resource);

        // During the temporary bypass, skip the browser's per-site prompt.
        // Keep the OS-level permission gate for camera/microphone, and allow
        // other ArkWeb resources so resource-name variations do not block a
        // page unnecessarily.
        if (!SITE_PERMISSION_PROMPT_ENABLED) {
          let allow = true;
          if (permissionType) {
            allow = await this.ensureSystemPermission(permissionType);
          }
          this.tracePermission('SITE_PERMISSION_BYPASS',
            `tab=${String(tabId)} origin=${origin} resource=${resource} ` +
            `type=${permissionType ?? 'unmapped'} systemGranted=${String(allow)}`);
          if (allow) {
            grantedResources.push(resource);
          }
          continue;
        }

        if (!permissionType) {
          continue;
        }

        const result = await this.permissionManager.requestPermission({
          origin: origin,
          permissionType: permissionType,
          title: getSitePermissionTitle(permissionType),
          message: getSitePermissionMessage(origin, permissionType),
          allowRememberChoice: true,
          rememberChoiceDefault: false,
          metadata: {
            pageUrl: tab.url,
            tabId: String(tabId),
            isPrivate: tab.isPrivate,
          },
        });

        if (!this.isCurrentTabRuntime(tabId, runtime)) {
          request.deny();
          return;
        }

        // ArkWeb only receives a grant after both the browser prompt and the
        // corresponding system CAMERA/MICROPHONE permission succeed. This
        // check is required for prompt and stored decisions alike.
        let allow = result.decision === 'allow';
        if (allow) {
          allow = await this.ensureSystemPermission(permissionType);
        }
        this.tracePermission('PROTECTED_PERMISSION_RESULT',
          `tab=${String(tabId)} origin=${origin} resource=${resource} type=${permissionType} ` +
          `decision=${result.decision} source=${result.source} systemGranted=${String(allow)}`);
        if (allow) {
          grantedResources.push(resource);
        }
      }

      if (grantedResources.length > 0) {
        this.tracePermission('RESOURCE_GRANT',
          `tab=${String(tabId)} origin=${origin} resources=${grantedResources.join(',')}`);
        request.grant(grantedResources);
        return;
      }
    } catch (_) {
      this.tracePermission('RESOURCE_GRANT_FAILED', `tab=${String(tabId)} origin=${origin}`);
    }

    this.tracePermission('RESOURCE_DENY',
      `tab=${String(tabId)} origin=${origin} requested=${resources.join(',')}`);
    request.deny();
  }

  @Builder
  private ActionIcon(icon: Resource, onPress: () => void) {
    Row() {
      Image(icon)
        .width(16)
        .height(16)
        .opacity(0.74);
    }
    .width(32)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor('#00000000')
    .onClick(() => onPress());
  }

  @Builder
  private MainMenuTriggerIcon() {
    Row() {
      Image($r('app.media.home_more'))
        .width(16)
        .height(16)
        .opacity(0.74);
    }
    .width(32)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.showMainMenu ? '#e9edf5' : '#00000000')
    .onClick(() => {
      if (this.showMainMenu) {
        this.closeMainMenu();
        return;
      }
      this.openMainMenu();
    });
  }

  @Builder
  private MainMenuOverlay() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onClick(() => this.closeMainMenu());

    BrowserMenu({
      items: this.getResolvedMainMenuItems(),
      activeItemId: this.mainMenuActiveItemId,
      anchorX: this.getMainMenuAnchorX(),
      anchorY: this.getMainMenuAnchorY(),
      menuWidth: this.getResolvedMainMenuWidth(),
      maxMenuHeight: this.getMainMenuMaxHeight(),
      maxSubMenuHeight: this.getSubMenuMaxHeight(),
      zoomPercent: this.pageZoomPercent,
      useAbsolutePosition: true,
      subMenuState: this.getActiveMainMenuSubMenuState(),
      onSelectItem: (item: BrowserMenuItem) => this.handleMainMenuSelect(item),
      onHoverItem: (item: BrowserMenuItem) => this.updateMainMenuHover(item),
      onSelectSubMenuItem: (item: BrowserMenuItem) => {
        if (this.showUaSubMenu) {
          this.handleUaSubMenuSelect(item);
          return;
        }
        this.handleBookmarksSubMenuSelect(item);
      },
      onHoverSubMenuItem: (item: BrowserMenuItem) => {
        if (this.showUaSubMenu) {
          this.updateUaSubMenuHover(item);
          return;
        }
        this.updateBookmarksSubMenuHover(item);
      },
      onZoomOut: () => this.adjustPageZoom(-10),
      onZoomIn: () => this.adjustPageZoom(10),
      onZoomReset: () => this.resetPageZoom(),
      onRequestClose: () => this.closeMainMenu(),
      canZoomOut: this.pageZoomPercent > 25,
      canZoomIn: this.pageZoomPercent < 200,
    });
  }

  @Builder
  private ContextMenuOverlay() {
    BrowserContextMenu({
      items: this.contextMenuItems,
      anchorX: this.contextMenuX,
      anchorY: this.contextMenuY,
      menuWidth: this.getContextMenuWidth(),
      maxMenuHeight: this.getContextMenuMaxHeight(),
      onSelectItem: (item: BrowserContextMenuItem) => this.handleContextMenuSelect(item),
      onDismiss: () => this.handleContextMenuDismiss(),
    });
  }

  @Builder
  private TabContextMenuOverlay() {
    BrowserContextMenu({
      items: this.tabContextMenuItems,
      anchorX: this.tabContextMenuX,
      anchorY: this.tabContextMenuY,
      menuWidth: 248,
      maxMenuHeight: 360,
      onSelectItem: (item: BrowserContextMenuItem) => this.handleTabContextMenuSelect(item),
      onDismiss: () => this.closeTabContextMenu(),
    });
  }

  @Builder
  private BookmarkBarContextMenuOverlay() {
    BrowserContextMenu({
      items: this.bookmarkContextMenuItems,
      anchorX: this.bookmarkContextMenuX,
      anchorY: this.bookmarkContextMenuY,
      menuWidth: Math.min(280, Math.max(220, this.viewportWidth - 24)),
      maxMenuHeight: Math.min(420, Math.max(160, this.viewportHeight - 24)),
      onSelectItem: (item: BrowserContextMenuItem) => this.handleBookmarkContextMenuSelect(item),
      onDismiss: () => this.closeBookmarkContextMenu(),
    });
  }

  @Builder
  private BookmarkFolderMenuOverlay() {
    BrowserContextMenu({
      items: this.bookmarkFolderMenuItems,
      anchorX: this.bookmarkFolderMenuX,
      anchorY: this.bookmarkFolderMenuY,
      menuWidth: Math.min(280, Math.max(220, this.viewportWidth - 24)),
      maxMenuHeight: Math.min(420, Math.max(160, this.viewportHeight - 24)),
      reorderEnabled: true,
      onSelectItem: (item: BrowserContextMenuItem) => this.handleBookmarkFolderMenuSelect(item),
      onReorderItem: (sourceItemId: string, targetItemId: string) =>
        this.handleBookmarkFolderMenuReorder(sourceItemId, targetItemId),
      onReorderDragStart: (itemId: string) => this.handleBookmarkFolderDragStart(itemId),
      onReorderDragEnd: () => this.handleBookmarkFolderDragEnd(),
      onDismiss: () => this.closeBookmarkFolderMenu(),
    });
  }

  @Builder
  private BookmarkRenameOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => this.cancelBookmarkRename());
      Column({ space: 12 }) {
        Text('修改书签名称')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#20252d');
        TextInput({ text: this.bookmarkRenameTitle, placeholder: '请输入名称' })
          .width(320)
          .height(40)
          .onChange((value: string) => this.bookmarkRenameTitle = value);
        Row({ space: 10 }) {
          Button('取消')
            .height(34)
            .onClick(() => this.cancelBookmarkRename());
          Button('保存')
            .height(34)
            .fontColor('#ffffff')
            .backgroundColor('#1976d2')
            .enabled(this.bookmarkRenameTitle.trim().length > 0)
            .onClick(() => this.confirmBookmarkRename());
        }
        .width(320)
        .justifyContent(FlexAlign.End);
      }
      .padding(24)
      .backgroundColor('#ffffff')
      .borderRadius(8)
      .onClick(() => {});
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private BookmarkDeleteOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => this.cancelBookmarkDelete());
      Column({ space: 14 }) {
        Text('删除书签')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#20252d');
        Text(
          `确定要删除“${this.bookmarkDeleteTitle}”吗？` +
          this.bookmarkManager.getBookmarkById(this.bookmarkDeleteId)?.isFolder
            ? '文件夹中的内容也会被删除。'
            : ''
        )
          .fontSize(14)
          .fontColor('#555b66')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 10 }) {
          Button('取消')
            .height(34)
            .onClick(() => this.cancelBookmarkDelete());
          Button('删除')
            .height(34)
            .fontColor('#ffffff')
            .backgroundColor('#d32f2f')
            .onClick(() => this.confirmBookmarkDelete());
        }
        .width('100%')
        .justifyContent(FlexAlign.End);
      }
      .width(360)
      .constraintSize({ maxWidth: '88%' })
      .padding(24)
      .backgroundColor('#ffffff')
      .borderRadius(8)
      .onClick(() => {});
    }
    .width('100%')
    .height('100%');
  }

  /**
   * Chrome-style add/edit bookmark popover anchored under the address-bar
   * star. No dim backdrop (click-through catcher is fully transparent) and
   * an outer drop shadow, matching the native context-menu styling. The
   * bookmark is already added when the dialog appears in "已添加书签" mode,
   * so closing the dialog keeps it — only 移除 deletes it.
   */
  @Builder
  private BookmarkEditOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick(() => this.closeBookmarkEditDialog());
      Column({ space: 16 }) {
        Text(this.bookmarkEditDialogTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#20252d');

        Row({ space: 12 }) {
          Text('名称')
            .width(44)
            .fontSize(14)
            .fontColor('#5f6368');
          TextInput({ text: this.bookmarkEditName, placeholder: '请输入名称' })
            .width(0)
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .backgroundColor('#f1f3f4')
            .borderRadius(4)
            .onChange((value: string) => this.bookmarkEditName = value);
        }
        .width('100%');

        Row({ space: 12 }) {
          Text('文件夹')
            .width(44)
            .fontSize(14)
            .fontColor('#5f6368');
          Select(this.bookmarkEditFolderOptions.map((option: BookmarkEditFolderOption): SelectOption =>
            ({ value: option.label } as SelectOption)))
            .width(0)
            .layoutWeight(1)
            .height(36)
            .selected(this.bookmarkEditFolderIndex)
            .value(this.bookmarkEditFolderOptions[this.bookmarkEditFolderIndex]?.label ?? '')
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.bookmarkEditFolderIndex = index;
              this.bookmarkEditFolderId = this.bookmarkEditFolderOptions[index]?.id ??
                BookmarkManager.ROOT_FOLDER_ID;
            })
        }
        .width('100%');

        Row() {
          Button('移除')
            .height(36)
            .backgroundColor(Color.Transparent)
            .fontColor('#1a73e8')
            .fontSize(14)
            .onClick(() => this.removeBookmarkFromEditDialog());

          Blank();

          Button('完成')
            .width(132)
            .height(36)
            .fontColor('#ffffff')
            .backgroundColor('#1a73e8')
            .fontSize(14)
            .enabled(this.bookmarkEditName.trim().length > 0)
            .onClick(() => this.confirmBookmarkEditDialog());
        }
        .width('100%');
      }
      .width(this.getBookmarkEditDialogWidth())
      .padding(20)
      .backgroundColor('#ffffff')
      .borderRadius(12)
      .border({ width: 1, color: '#e3e7ee' })
      .shadow({ radius: 24, color: '#28000000', offsetX: 0, offsetY: 8 })
      .position({ x: this.bookmarkEditAnchorX, y: this.bookmarkEditAnchorY })
      .onClick(() => {});
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private JavaScriptDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        // JavaScript dialogs are modal like Chrome's native dialogs: clicking
        // outside must not implicitly cancel a confirm/prompt/beforeunload.
        .onClick(() => {});
      Column({ space: 14 }) {
        Text(this.javaScriptDialogKind === 'alert' ? '提示' :
          this.javaScriptDialogKind === 'beforeunload' ? '确认离开页面' :
          this.javaScriptDialogKind === 'prompt' ? '输入' : '确认')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#20252d');
        if (this.javaScriptDialogMessage.length > 0) {
          Text(this.javaScriptDialogMessage)
            .fontSize(14)
            .fontColor('#3c424c')
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        if (this.javaScriptDialogKind === 'prompt') {
          TextInput({ text: this.javaScriptDialogInputValue, placeholder: this.javaScriptDialogDefaultValue })
            .width('100%')
            .height(40)
            .onChange((value: string) => this.javaScriptDialogInputValue = value);
        }
        Row({ space: 10 }) {
          Button('取消')
            .height(36)
            .onClick(() => this.resolveJavaScriptDialog(false));
          Button(this.javaScriptDialogKind === 'alert' ? '确定' : '确定')
            .height(36)
            .fontColor('#ffffff')
            .backgroundColor('#1976d2')
            .onClick(() => this.resolveJavaScriptDialog(true));
        }
        .width('100%')
        .justifyContent(FlexAlign.End);
      }
      .width(360)
      .constraintSize({ maxWidth: '88%' })
      .padding(24)
      .backgroundColor('#ffffff')
      .borderRadius(10)
      .onClick(() => {});
    }
    .width('100%')
    .height('100%');
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (!this.isFullScreen) {
          Column() {
          Row() {
            TabBar({
              tabs: this.viewState.tabs,
              activeTabId: this.viewState.activeTabId,
              runtimeFavicons: this.runtimeTabFavicons,
              onTabSelect: (tabId: TabId) => this.handleTabSelect(tabId),
              onTabClose: (tabId: TabId) => this.handleTabClose(tabId),
              onTabContextMenu: (tabId: TabId, index: number, position: TabContextMenuPosition) =>
                this.handleTabContextMenu(tabId, index, position),
              onTabToggleMute: (tabId: TabId) => this.handleTabMuteIconClick(tabId),
              onNewTab: () => this.handleNewTab(),
            })
            .layoutWeight(1);
          }
          .width('100%')
          .height(40)
          .padding({ left: 4, right: this.titleButtonAreaWidth > 0 ? this.titleButtonAreaWidth + 6 : 10 })
          .backgroundColor(this.getTabStripBackgroundColor());

          Row({ space: 8 }) {
            NavigationBar({
              canGoBack: $navCanGoBack,
              canGoForward: $navCanGoForward,
              onBack: () => this.handleBack(),
              onForward: () => this.handleForward(),
              onReload: () => this.handleReload(),
              onHome: () => this.handleHome(),
            });

            Row() {
              AddressBar({
                text: $addressText,
                placeholder: '搜索或输入网址',
                displayText: this.getAddressDisplayText(),
                editing: this.isAddressEditing,
                selectionRevision: this.addressSelectionRevision,
                favoriteEnabled: this.canToggleCurrentPageBookmark(),
                favoriteActive: this.currentPageBookmarked,
                onChangeValue: (value: string) => this.handleAddressDraftChange(value),
                onSubmitValue: (value: string) => this.handleAddressSubmit(value),
                onStartEditing: () => this.startAddressEditing(),
                onToggleFavorite: () => this.openBookmarkEditDialogForCurrentPage(),
                onFavoriteAreaChanged: (rightX: number, bottomY: number) => {
                  this.starAnchorRight = rightX;
                  this.starAnchorBottom = bottomY;
                },
              })
              .width('100%')
              .height('100%');
            }
            .width(0)
            .layoutWeight(1)
            .constraintSize({ minWidth: 160 })
            .height(34);

            Row({ space: 6 }) {
              if (this.downloadIndicator.primaryState !== 'idle') {
                DownloadStatusButton({
                  icon: $r('app.media.home_download'),
                  snapshot: this.downloadIndicator,
                  onClickAction: () => this.openDownloadsManager(),
                });
              }
              this.ActionIcon($r('app.media.settings_menu_bookmarks'), () => {
                this.openBookmarksManager();
              });
              this.MainMenuTriggerIcon();
            }
            .padding({ right: 4 });
          }
          .width('100%')
          .height(46)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.getToolbarBackgroundColor())
          .border({ width: { bottom: 1 }, color: this.getToolbarBorderColor() });

          if (this.viewState.isPrivate) {
            Row({ space: 10 }) {
              Text('◐')
                .fontSize(14)
                .fontColor('#c4b5fd');

              Text(
                '无痕模式：不会保存浏览历史、Cookie、站点数据或表单输入；' +
                '下载的文件和创建的书签仍会保留。'
              )
                .layoutWeight(1)
                .fontSize(12)
                .fontColor('#d7dce5')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .width('100%')
            .height(42)
            .padding({ left: 18, right: 18, top: 7, bottom: 7 })
            .backgroundColor('#1b1f27')
            .border({ width: { bottom: 1 }, color: '#343b48' });
          }

          if (this.showAddressSuggestions && this.addressSuggestions.length > 0) {
            Row() {
              AddressSuggestionPanel({
                suggestions: this.addressSuggestions,
                selectedSuggestionId: this.getSelectedAddressSuggestionId(),
                maxPanelHeight: this.getAddressSuggestionMaxHeight(),
                onSelectSuggestion: (suggestion: AddressSuggestion) => this.handleAddressSuggestionSelect(suggestion),
              });
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#ffffff')
            .border({ width: { bottom: 1 }, color: '#edf0f4' });
          } else if (this.showBookmarkBar) {
            BookmarkBar({
              bookmarks: this.bookmarkBarItems,
              availableWidth: Math.max(0, this.viewportWidth - this.titleButtonAreaWidth - 20),
              isPrivate: this.viewState.isPrivate,
              resolveExternalDragSource: (): BookmarkItem | null => this.bookmarkFolderMenuDraggingItem,
              onOpenBookmark: (bookmark: BookmarkItem) => this.openBookmarkBarItem(bookmark),
              onOpenFolder: (folder: BookmarkItem, x: number, y: number) => this.showBookmarkFolderMenu(folder, x, y),
              onBookmarkContextMenu: (bookmark: BookmarkItem, x: number, y: number) =>
                this.showBookmarkBarContextMenu(bookmark, x, y),
              onBookmarkBarContextMenu: (x: number, y: number) => this.showBookmarkBarContextMenu(null, x, y),
              onBookmarkDrop: (source: BookmarkItem, target: BookmarkItem | null, targetIndex: number) =>
                this.handleBookmarkBarDrop(source, target, targetIndex),
            })
            .width('100%')
            .height(36)
            .backgroundColor(this.getBookmarkBarBackgroundColor())
            .border({ width: { bottom: 1 }, color: '#edf0f4' });
          }
          }
          .width('100%');
        }

        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.viewState.tabs, (tab: Tab) => {
            if (this.shouldRenderTabWeb(tab)) {
              Column() {
              Web({
                src: '',
                controller: this.ensureRuntimeForTab(tab.id).controller,
                incognitoMode: tab.isPrivate
              })
                .zoomAccess(true)
                  // The tab strip needs to know when a page starts or stops
                  // playing media even while the page keeps itself muted, so the
                  // monitor is injected before the document runs and reports
                  // back through a per-tab proxy.
                  .javaScriptProxy({
                    object: this.ensureTabMediaBridge(tab.id),
                    name: TAB_MEDIA_BRIDGE_NAME,
                    methodList: [TAB_MEDIA_PLAYING_METHOD],
                    controller: this.ensureRuntimeForTab(tab.id).controller,
                  })
                  .runJavaScriptOnDocumentStart(this.mediaMonitorScripts)
                  .forceEnableZoom(true)
                  .javaScriptAccess(this.appliedWebSettings.javaScriptAccess)
                  .imageAccess(this.appliedWebSettings.imageAccess)
                  .onlineImageAccess(this.appliedWebSettings.onlineImageAccess)
                  .domStorageAccess(this.appliedWebSettings.domStorageAccess)
                  .databaseAccess(this.appliedWebSettings.databaseAccess)
                  // Keep viewport meta parsing enabled for all UA modes. In
                  // mobile mode overview fitting is enabled so pages that do
                  // not provide a viewport meta tag still scale as phones do.
                  .metaViewport(true)
                  .overviewModeAccess(this.selectedUaMode === 'mobile')
                  .userAgent(this.uaManager.getUserAgent(this.selectedUaMode))
                  .width('100%')
                  .height('100%')
                  .opacity(this.getTabWebOpacity(tab.id))
                  .onMouse(this.createTabMouseHandler(tab.id))
                  .onScaleChange(this.createTabScaleChangeHandler(tab.id))
                  .onLoadIntercept(this.createTabLoadInterceptHandler(tab.id))
                  .onGeolocationShow(this.createTabGeolocationHandler(tab.id))
                  .onPermissionRequest(this.createTabPermissionHandler(tab.id))
                  .onControllerAttached(this.createTabControllerAttachedHandler(tab.id))
                  .onDisAppear(this.createTabDisappearHandler(tab.id))
                  .onPageBegin(this.createTabPageBeginHandler(tab.id))
                  .onPageEnd(this.createTabPageEndHandler(tab.id))
                  .onAudioStateChanged(this.createTabAudioStateChangedHandler(tab.id))
                  .onNavigationEntryCommitted(this.createTabHistoryUpdateHandler(tab.id))
                  .onTitleReceive(this.createTabTitleHandler(tab.id))
                  .onFaviconReceived(this.createTabFaviconHandler(tab.id))
                  .onAlert(this.createTabAlertHandler(tab.id))
                  .onConfirm(this.createTabConfirmHandler(tab.id))
                  .onPrompt(this.createTabPromptHandler(tab.id))
                  .onBeforeUnload(this.createTabBeforeUnloadHandler(tab.id))
                  .onConsole(this.createTabConsoleHandler(tab.id))
                  .multiWindowAccess(true)
                  .onWindowNew(this.createTabWindowNewHandler(tab.id))
                  .onWindowExit(this.createTabWindowExitHandler(tab.id))
                  .onContextMenuShow(this.createTabContextMenuHandler(tab.id))
                  .onContextMenuHide(this.createTabContextMenuHideHandler(tab.id))
                  .onErrorReceive(this.createTabErrorHandler(tab.id))
                  .onHttpErrorReceive(this.createTabHttpErrorHandler(tab.id))
                  .onSslErrorEventReceive(this.createTabSslErrorHandler())
                  .onRenderProcessNotResponding(this.createTabRenderProcessNotRespondingHandler(tab.id))
                  .onRenderProcessResponding(this.createTabRenderProcessRespondingHandler(tab.id))
                  .onRenderExited(this.createTabRenderExitedHandler(tab.id))
                  .onSearchResultReceive(this.createTabSearchResultHandler(tab.id));
              }
              .width(this.getTabWebWidth(tab.id))
              .height(this.getTabWebHeight(tab.id))
              .zIndex(this.isActiveTabId(tab.id) ? 2 : 1);
            }
          }, (tab: Tab) => `${String(tab.id)}:${this.uaRenderRevision}`);

          if (this.showHome) {
            BrowserHome({
              isPrivate: this.viewState.isPrivate,
              onSubmit: (value: string) => this.navigateFromHome(value)
            })
            .width('100%')
            .height('100%')
            .zIndex(3);
          }

          if (!this.showHome && this.browserWebErrors.length > 0) {
            ForEach(this.browserWebErrors.filter((error: BrowserWebErrorState) => {
              return error.tabId === this.viewState.activeTabId;
            }), (error: BrowserWebErrorState) => {
              BrowserErrorPage({
                error: error,
                isPrivate: this.viewState.isPrivate,
                canGoBack: this.navCanGoBack,
                contentWidth: Math.max(280, Math.min(620, this.viewportWidth - 56)),
                onRetry: () => this.reload(),
                onBack: () => this.handleBack(),
              })
              .width('100%')
              .height('100%')
              .zIndex(4);
            }, (error: BrowserWebErrorState) => `${error.tabId}:${error.occurredAt}`);
          }

          if (this.showContextMenu) {
            this.ContextMenuOverlay();
          }

          if (this.isSettingsRouteActive()) {
            // 设置页占用内容区，而不是覆盖整个窗口：
            // 顶部壳（标签栏 / 地址栏 / 联想面板）与菜单浮层都保持在设置页之上，
            // 因此设置页顶边正好落在地址栏底边，地址栏及其以上区域始终可见可用。
            SettingsShellPage({
              initialSectionId: this.getSettingsSectionForRoute(),
              onBack: () => (this.route = AppRouter.browser),
              onOpenUrl: (url: string) => {
                this.pendingUrl = url;
                this.route = AppRouter.browser;
              },
              onOpenUrlInNewTab: (url: string) => {
                this.pendingNewTabUrl = url;
                this.route = AppRouter.browser;
              },
              onOpenUrlInNewWindow: (url: string) => {
                this.pendingNewWindowUrl = url;
                this.route = AppRouter.browser;
              },
              onOpenUrlInPrivateWindow: (url: string) => {
                this.pendingPrivateWindowUrl = url;
                this.route = AppRouter.browser;
              },
            })
              .width('100%')
              .height('100%')
              .backgroundColor('#ffffff')
              .zIndex(6);
          }
        }
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.updateWebContentLayout(Number(newValue.width), Number(newValue.height));
        })
        .onClick(() => {
          if (this.isAddressEditing || this.hasAddressSuggestions()) {
            this.cancelAddressEditing();
          }
        });
      }
      .width('100%')
      .height('100%');

      if (this.showFindPanel) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000000')
          .onClick(() => this.closeFindPanel());

        Column() {
          this.FindPanel();
        }
        .position({ x: this.getFindPanelAnchorX(), y: this.getFindPanelAnchorY() })
        .onClick(() => {});
      }

      if (this.showTabSearch) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#22000000')
          .onClick(() => this.closeTabSearch());

        Column() {
          this.TabSearchPanel();
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: this.isFullScreen ? 20 : 52 })
        .onClick(() => {
        });
      }

      if (this.showMainMenu) {
        this.MainMenuOverlay();
      }

      if (this.showTabContextMenu) {
        this.TabContextMenuOverlay();
      }

      if (this.showBookmarkContextMenu) {
        this.BookmarkBarContextMenuOverlay();
      }

      if (this.bookmarkFolderMenuItems.length > 0) {
        this.BookmarkFolderMenuOverlay();
      }

      if (this.showBookmarkEditDialog) {
        this.BookmarkEditOverlay();
      }

      if (this.showBookmarkRenameDialog) {
        this.BookmarkRenameOverlay();
      }

      if (this.showBookmarkDeleteDialog) {
        this.BookmarkDeleteOverlay();
      }

      if (this.showPermissionDialog) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#33000000')
          .onClick(() => {
            if (!this.permissionDecisionPending) {
              this.permissionManager.dismissActiveRequest();
            }
          });

        Column() {
          PermissionDialog({
            request: this.permissionRequest,
            pending: this.permissionDecisionPending,
            dialogWidth: this.getPermissionDialogWidth(),
            rememberChoice: $permissionRememberChoice,
            onDecision: (result) => {
              if (result.decision === 'allow') {
                this.handlePermissionDialogDecision();
              } else {
                this.handlePermissionDialogCancel();
              }
            },
          });
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {});
      }

      if (this.showJavaScriptDialog) {
        this.JavaScriptDialogOverlay();
      }

    }
    .backgroundColor(this.getPageBackgroundColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateMainMenuLayout(Number(newValue.width), Number(newValue.height));
    })
    .focusable(true)
    .defaultFocus(!this.isAddressEditing)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event))
    .width('100%')
    .height('100%');
  }
}
