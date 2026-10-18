import webview from '@ohos.web.webview';
import { KeyCode } from '@kit.InputKit';
import { common } from '@kit.AbilityKit';
import { print } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { AddressInputResolver } from '../core/addressInputResolver';
import { BookmarkManager } from '../core/bookmarkManager';
import { encodeFaviconDataUri } from '../core/faviconService';
import { extractUrlScheme, isExternalAppSchemeUrl, isSameHttpNavigationUrl } from '../core/urlNormalizer';
import { DownloadManager } from '../core/downloadManager';
import {
  buildImageDownloadFileName,
  extractFileNameFromContentDisposition,
  inferImageMimeType,
} from '../core/downloadTypes';
import { PrivateSessionCoordinator } from '../core/privateSessionCoordinator';
import {
  BrowserResponseHeader,
  BrowserWebErrorState,
  createBrowserWebError,
  hasHttpResponseBody,
  isCurrentMainFrameNavigation,
  upsertBrowserWebError,
} from '../core/browserWebError';
import { BrowserErrorPage } from '../ui/components/BrowserErrorPage';
import { BrowserContextMenu, BrowserContextMenuItem } from '../ui/components/BrowserContextMenu';
import { ClipboardService } from '../integration/clipboardService';
import { DownloadSettingsService } from '../integration/downloadSettingsService';
import { PermissionService } from '../integration/permissionService';
import {
  extractSiteOriginFromUrl,
  mapProtectedResourceToSitePermissionType,
  SitePermissionType,
} from '../core/permissionTypes';
import { BrowserShortcutAction, ShortcutManager } from '../core/shortcutManager';
import { WindowManager } from '../core/windowManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
} from '../core/webNavigationLifecycle';

const INCOGNITO_HOME_INPUT_ID: string = 'incognito_home_input';
const INCOGNITO_TOOLBAR_INPUT_ID: string = 'incognito_toolbar_input';
const INCOGNITO_FIND_INPUT_ID: string = 'incognito_find_input';

interface IncognitoWebResourceErrorInfo {
  code: string;
  info: string;
}

interface IncognitoContextMenuState {
  result: WebContextMenuResult;
  linkUrl: string;
  sourceUrl: string;
  selectionText: string;
}

interface IncognitoContextMenuPosition {
  x: number;
  y: number;
}

@Entry
@Component
struct IncognitoWindow {
  private controller: webview.WebviewController = new webview.WebviewController();
  private addressInputResolver: AddressInputResolver = new AddressInputResolver();
  private bookmarkManager: BookmarkManager = BookmarkManager.getInstance();
  private downloadManager: DownloadManager = DownloadManager.getInstance();
  private downloadSettingsService: DownloadSettingsService = new DownloadSettingsService();
  private downloadDelegate: webview.WebDownloadDelegate | null = null;
  private clipboardService: ClipboardService = new ClipboardService();
  private permissionService: PermissionService = new PermissionService();
  private shortcutManager: ShortcutManager = new ShortcutManager();
  private windowManager: WindowManager = WindowManager.getInstance();
  private privateSessionCoordinator: PrivateSessionCoordinator = PrivateSessionCoordinator.getInstance();
  private privateSessionOwnerId: string = this.privateSessionCoordinator.createOwnerId('incognito-window');
  private privateSessionOwnerActive: boolean = false;

  @State private addressText: string = '';
  @State private currentUrl: string = 'about:blank';
  @State private pageTitle: string = '无痕浏览';
  @State private showHome: boolean = true;
  @State private currentPageBookmarked: boolean = false;
  @State private canGoBack: boolean = false;
  @State private browserError: BrowserWebErrorState | null = null;
  @State private showContextMenu: boolean = false;
  @State private contextMenuItems: BrowserContextMenuItem[] = [];
  @State private contextMenuX: number = 0;
  @State private contextMenuY: number = 0;
  @State private webContentWidth: number = 1280;
  @State private webContentHeight: number = 600;
  @State private isLoading: boolean = false;
  @State private currentFaviconDataUri: string = '';
  @State private isFullScreen: boolean = false;
  @State private findText: string = '';
  @State private showFindPanel: boolean = false;

  private pendingContextMenu: IncognitoContextMenuState | null = null;
  private contextMenuTriggerX: number = 0;
  private contextMenuTriggerY: number = 0;
  private webPointerX: number = 0;
  private webPointerY: number = 0;
  private hasWebPointerPosition: boolean = false;

  private requestedUrl: string = '';
  private committedUrl: string = '';
  private lastErrorUrl: string = '';
  private controllerAttached: boolean = false;
  private pendingControllerLoadUrl: string = '';
  private navigationLifecycle: WebNavigationLifecycleState = createWebNavigationLifecycleState();
  private faviconGeneration: number = 0;
  private faviconCaptureSequence: number = 0;

  private toolbarInputController: TextInputController = new TextInputController();
  private homeInputController: TextInputController = new TextInputController();
  // 焦点状态追踪：点击未聚焦的地址输入框时全选文本，聚焦状态下点击保持默认光标行为。
  private toolbarInputFocused: boolean = false;
  private toolbarInputFocusedAtPress: boolean = false;
  private homeInputFocused: boolean = false;
  private homeInputFocusedAtPress: boolean = false;

  private selectAllAddressText(controller: TextInputController): void {
    Promise.resolve().then(() => {
      try {
        controller.setTextSelection(0, this.addressText.length);
      } catch (_) {
      }
    });
  }

  private handleToolbarInputTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.toolbarInputFocusedAtPress = this.toolbarInputFocused;
    }
  }

  private handleToolbarInputClick(): void {
    if (!this.toolbarInputFocusedAtPress) {
      this.selectAllAddressText(this.toolbarInputController);
    }
  }

  private handleHomeInputTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.homeInputFocusedAtPress = this.homeInputFocused;
    }
  }

  private handleHomeInputClick(): void {
    if (!this.homeInputFocusedAtPress) {
      this.selectAllAddressText(this.homeInputController);
    }
  }

  aboutToAppear(): void {
    this.windowManager.bind(this.getUIContext()).catch(() => {
    });
    this.privateSessionCoordinator.acquire(this.privateSessionOwnerId);
    this.privateSessionOwnerActive = true;
    this.downloadManager.setHostContext(this.getUIContext().getHostContext());
    const windowName = this.getUIContext().getWindowName();
    const key = `browserSubWindowPendingUrl:${windowName}`;
    const initialUrl = AppStorage.get<string>(key) ?? '';
    if (initialUrl.trim().length > 0) {
      this.currentUrl = initialUrl.trim();
      this.addressText = initialUrl.trim();
      this.pageTitle = initialUrl.trim();
      this.showHome = false;
      this.currentPageBookmarked = this.bookmarkManager.isBookmarked(initialUrl.trim());
      this.beginFaviconGeneration();
      this.clearBrowserError();
      startWebNavigation(this.navigationLifecycle, initialUrl.trim());
      this.requestedUrl = initialUrl.trim();
      this.isLoading = true;
      this.pendingControllerLoadUrl = initialUrl.trim();
      AppStorage.setOrCreate(key, '');
    }
    Promise.resolve().then(() => this.requestHomeInputFocus());
  }

  aboutToDisappear(): void {
    if (this.privateSessionOwnerActive) {
      this.privateSessionCoordinator.release(this.privateSessionOwnerId);
      this.privateSessionOwnerActive = false;
    }
  }

  private submitAddress(): void {
    this.closeContextMenu();
    const value = this.addressText.trim();
    if (!value) {
      return;
    }

    const resolved = this.addressInputResolver.resolve(value);
    if (!resolved.targetUrl) {
      return;
    }

    this.currentUrl = resolved.targetUrl;
    this.pageTitle = resolved.targetUrl;
    this.showHome = false;
    this.currentPageBookmarked = this.bookmarkManager.isBookmarked(resolved.targetUrl);
    this.beginFaviconGeneration();
    this.clearBrowserError();
    startWebNavigation(this.navigationLifecycle, resolved.targetUrl);
    this.requestedUrl = resolved.targetUrl;
    this.lastErrorUrl = '';
    this.isLoading = true;
    this.loadUrl(resolved.targetUrl);
  }

  private requestHomeInputFocus(): void {
    try {
      this.getUIContext().getFocusController().requestFocus(INCOGNITO_HOME_INPUT_ID);
    } catch (_) {
    }
  }

  private goBack(): void {
    this.closeContextMenu();
    this.clearBrowserError();
    this.beginFaviconGeneration();
    startWebNavigation(this.navigationLifecycle);
    this.requestedUrl = '';
    this.lastErrorUrl = '';
    this.isLoading = true;
    try {
      this.controller.backward();
    } catch (_) {
    }
  }

  private goForward(): void {
    this.closeContextMenu();
    this.clearBrowserError();
    this.beginFaviconGeneration();
    startWebNavigation(this.navigationLifecycle);
    this.requestedUrl = '';
    this.lastErrorUrl = '';
    this.isLoading = true;
    try {
      this.controller.forward();
    } catch (_) {
    }
  }

  private reload(): void {
    this.closeContextMenu();
    if (this.showHome || !this.currentUrl || this.currentUrl === 'about:blank') {
      return;
    }
    this.clearBrowserError();
    this.beginFaviconGeneration();
    startWebNavigation(this.navigationLifecycle, this.currentUrl);
    this.requestedUrl = this.currentUrl;
    this.lastErrorUrl = '';
    this.pageTitle = this.currentUrl;
    this.isLoading = true;
    try {
      this.controller.refresh();
    } catch (_) {
      this.handleLoadFailure(this.currentUrl, 'network', 'REFRESH_FAILED');
    }
  }

  private goHome(): void {
    this.closeContextMenu();
    enterWebNavigationHome(this.navigationLifecycle);
    this.loadHomeDocument();
    this.currentUrl = 'about:blank';
    this.addressText = '';
    this.pageTitle = '无痕浏览';
    this.showHome = true;
    this.currentPageBookmarked = false;
    this.canGoBack = false;
    this.requestedUrl = '';
    this.committedUrl = '';
    this.lastErrorUrl = '';
    this.pendingControllerLoadUrl = '';
    this.isLoading = false;
    this.beginFaviconGeneration();
    this.clearBrowserError();
  }

  private toggleBookmark(): void {
    if (!this.currentUrl.startsWith('http://') && !this.currentUrl.startsWith('https://')) {
      return;
    }
    const faviconUrl = this.currentFaviconDataUri || this.resolveFaviconFallbackUrl(this.currentUrl);
    this.currentPageBookmarked = this.bookmarkManager.toggleBookmark(this.currentUrl, this.pageTitle, faviconUrl);
    // Cached navigations are allowed to skip onFaviconReceived. Read the
    // controller's current favicon after loading so the bookmark can be
    // upgraded from the fallback URL to the actual image data.
    if (!this.isLoading) {
      this.captureCurrentFavicon();
    }
  }

  private handlePageBegin(url: string): void {
    if (this.showHome && this.isAboutBlankUrl(url)) {
      return;
    }
    if (!acceptWebPageBegin(this.navigationLifecycle, url)) {
      return;
    }
    this.closeContextMenu();
    this.clearBrowserError();
    this.requestedUrl = url;
    this.committedUrl = url;
    this.lastErrorUrl = '';
    this.currentUrl = url;
    this.addressText = url === 'about:blank' ? '' : url;
    this.pageTitle = url;
    this.showHome = false;
    this.currentPageBookmarked = this.bookmarkManager.isBookmarked(url);
    this.beginFaviconGeneration();
    this.isLoading = true;
    this.refreshNavigationState();
  }

  private handleControllerAttached(): void {
    this.controllerAttached = true;
    this.attachDownloadDelegate();
    const pendingUrl = this.pendingControllerLoadUrl;
    this.pendingControllerLoadUrl = '';
    if (!this.showHome && pendingUrl.length > 0 && this.lastErrorUrl.length === 0) {
      this.loadUrl(pendingUrl);
    }
  }

  private attachDownloadDelegate(): void {
    if (!this.downloadDelegate) {
      this.downloadDelegate = this.downloadManager.createArkWebDownloadDelegate(
        (item: webview.WebDownloadItem) => {
          void this.handleArkWebDownload(item);
        });
    }
    try {
      this.controller.setDownloadDelegate(this.downloadDelegate);
      hilog.info(0x0000, 'DownloadTrace', 'ARKWEB_DELEGATE_ATTACHED private=true');
    } catch (error) {
      hilog.error(0x0000, 'DownloadTrace',
        'ARKWEB_DELEGATE_ATTACH_FAILED private=true error=%{public}s', String(error));
    }
  }

  private async handleArkWebDownload(item: webview.WebDownloadItem): Promise<void> {
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
        pageUrl: this.currentUrl,
        pageTitle: this.pageTitle,
        userAgent: this.getCurrentUserAgent(),
        contentLength: item.getTotalBytes(),
        isPrivate: true,
        downloadFileUri: fileUri,
      }, hostContext);
    } catch (error) {
      hilog.error(0x0000, 'DownloadTrace',
        'ARKWEB_BEFORE_DOWNLOAD_FAILED private=true error=%{public}s', String(error));
      try {
        item.cancel();
      } catch (_) {
      }
    }
  }

  private loadUrl(url: string): void {
    if (!this.controllerAttached) {
      this.pendingControllerLoadUrl = url;
      return;
    }
    this.pendingControllerLoadUrl = '';
    try {
      this.controller.loadUrl(url);
    } catch (_) {
      this.handleLoadFailure(url, 'network', 'LOAD_URL_FAILED');
    }
  }

  private loadHomeDocument(): void {
    if (!this.controllerAttached) {
      return;
    }
    try {
      this.controller.loadUrl('about:blank');
    } catch (_) {
    }
  }

  private handlePageEnd(url: string): void {
    if (this.navigationLifecycle.suppressPageCallbacks) {
      return;
    }
    if (this.lastErrorUrl.length > 0 ||
      !canCompleteWebNavigation(this.navigationLifecycle)) {
      this.refreshNavigationState();
      return;
    }
    this.clearBrowserError();
    completeWebNavigation(this.navigationLifecycle);
    this.requestedUrl = url;
    this.committedUrl = url;
    this.currentUrl = url;
    this.addressText = url === 'about:blank' ? '' : url;
    try {
      const title = this.controller.getTitle();
      this.pageTitle = title && title.trim().length > 0 ? title : url;
    } catch (_) {
      this.pageTitle = url;
    }
    this.currentPageBookmarked = this.bookmarkManager.isBookmarked(url);
    this.isLoading = false;
    this.captureCurrentFavicon();
    this.scheduleFaviconCapture();
    this.refreshNavigationState();
  }

  private handleTitleReceive(event: OnTitleReceiveEvent): void {
    const title = event.title.trim();
    if (!this.showHome && title.length > 0) {
      this.pageTitle = title;
    }
  }

  private handleHistoryUpdate(details: LoadCommittedDetails): void {
    if (this.showHome || this.navigationLifecycle.suppressPageCallbacks) {
      return;
    }
    // Only same-document navigations (pushState/replaceState, fragment jumps,
    // same-page history moves) are handled here; they never trigger
    // PageBegin/PageEnd, so the back button would stay stale without this.
    if (!details.isMainFrame || !details.isSameDocument) {
      return;
    }
    const url = details.url ? details.url.trim() : '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    if (!this.isLoading && url !== this.currentUrl) {
      this.currentUrl = url;
      this.addressText = url;
      this.currentPageBookmarked = this.bookmarkManager.isBookmarked(url);
    }
    this.refreshNavigationState();
  }

  private handleFaviconReceived(event: OnFaviconReceivedEvent): void {
    if (this.showHome || !this.currentUrl.startsWith('http://') && !this.currentUrl.startsWith('https://')) {
      return;
    }
    try {
      const controllerUrl = this.controller.getUrl();
      if (controllerUrl && !isSameHttpNavigationUrl(controllerUrl, this.currentUrl)) {
        return;
      }
    } catch (_) {
      return;
    }
    this.persistFavicon(event.favicon);
  }

  private captureCurrentFavicon(): void {
    if (this.showHome || this.isLoading || !this.currentUrl.startsWith('http://') &&
      !this.currentUrl.startsWith('https://')) {
      return;
    }
    let favicon: PixelMap;
    try {
      const controllerUrl = this.controller.getUrl();
      if (controllerUrl && !isSameHttpNavigationUrl(controllerUrl, this.currentUrl)) {
        return;
      }
      favicon = this.controller.getFavicon();
    } catch (_) {
      return;
    }
    if (!favicon) {
      return;
    }
    this.persistFavicon(favicon);
  }

  private scheduleFaviconCapture(): void {
    const generation = this.faviconGeneration;
    [250, 1000].forEach((delay: number) => {
      setTimeout(() => {
        if (this.faviconGeneration !== generation || this.showHome || this.isLoading ||
          this.currentFaviconDataUri.length > 0) {
          return;
        }
        this.captureCurrentFavicon();
      }, delay);
    });
  }

  private persistFavicon(favicon: PixelMap): void {
    const generation = this.faviconGeneration;
    this.faviconCaptureSequence += 1;
    const captureSequence = this.faviconCaptureSequence;
    encodeFaviconDataUri(favicon).then((dataUri: string | undefined) => {
      if (!dataUri || this.showHome || this.faviconGeneration !== generation ||
        this.faviconCaptureSequence !== captureSequence) {
        return;
      }
      this.currentFaviconDataUri = dataUri;
      this.bookmarkManager.refreshBookmark(this.currentUrl, this.pageTitle, dataUri);
    }).catch(() => {
    });
  }

  private resolveFaviconFallbackUrl(url: string): string {
    const matched = url.trim().match(/^(https?:\/\/[^\/]+)/i);
    return matched && matched[1] ? `${matched[1]}/favicon.ico` : '';
  }

  private beginFaviconGeneration(): void {
    this.faviconGeneration += 1;
    this.currentFaviconDataUri = '';
  }

  private handleLoadError(event: OnErrorReceiveEvent): void {
    const url = event.request.getRequestUrl();
    if (!this.isCurrentMainFrameRequest(event.request.isMainFrame(), url)) {
      return;
    }
    if (!canFailWebNavigation(this.navigationLifecycle)) {
      return;
    }
    const error = this.readWebResourceErrorInfo(event.error);
    this.handleLoadFailure(url, 'network', error.code, error.info);
  }

  private handleHttpError(event: OnHttpErrorReceiveEvent): void {
    const url = event.request.getRequestUrl();
    if (!this.isCurrentMainFrameRequest(event.request.isMainFrame(), url)) {
      return;
    }
    if (!canFailWebNavigation(this.navigationLifecycle)) {
      return;
    }
    let statusCode = 0;
    let reason = '';
    let responseData = '';
    let headers: BrowserResponseHeader[] = [];
    try {
      statusCode = event.response.getResponseCode();
      reason = event.response.getReasonMessage();
      responseData = event.response.getResponseData();
      headers = event.response.getResponseHeader();
    } catch (_) {
    }
    if (hasHttpResponseBody(responseData, headers)) {
      return;
    }
    this.handleLoadFailure(
      url,
      'http',
      statusCode > 0 ? `HTTP ${String(statusCode)}` : 'HTTP_ERROR',
      reason,
      statusCode,
    );
  }

  private handleSslError(event: OnSslErrorEventReceiveEvent): void {
    // 证书错误（过期/自签/域不匹配等）直接放行，便于验证异常证书页面。
    try {
      event.handler.handleConfirm();
    } catch (_) {
    }
  }

  private handleRenderProcessNotResponding(data: RenderProcessNotRespondingData): void {
    if (this.showHome) {
      return;
    }
    this.setBrowserError(createBrowserWebError({
      tabId: 'incognito-window',
      kind: 'renderer',
      url: this.getCurrentRequestUrl(),
      errorCode: 'RENDERER_UNRESPONSIVE',
      detail: data.reason === RenderProcessNotRespondingReason.NAVIGATION_COMMIT_TIMEOUT ?
        '网页加载超时，可以重新加载页面。' :
          '网页进程没有及时响应，可以重新加载页面。',
    }));
  }

  private handleRenderProcessResponding(): void {
    if (this.browserError?.kind === 'renderer' && this.browserError.errorCode === 'RENDERER_UNRESPONSIVE') {
      this.clearBrowserError();
    }
  }

  private handleRenderExited(event: OnRenderExitedEvent): void {
    if (this.showHome) {
      return;
    }
    const url = this.getCurrentRequestUrl();
    failWebNavigation(this.navigationLifecycle);
    this.beginFaviconGeneration();
    this.lastErrorUrl = url;
    this.isLoading = false;
    this.setBrowserError(createBrowserWebError({
      tabId: 'incognito-window',
      kind: 'renderer',
      url,
      errorCode: `RENDERER_EXIT_${String(event.renderExitReason)}`,
      detail: '网页进程异常退出，可以重新加载页面。',
    }));
  }

  private handleLoadFailure(
    url: string,
    kind: 'network' | 'http' | 'ssl',
    errorCode: string,
    detail: string = '',
    statusCode: number = 0,
  ): void {
    failWebNavigation(this.navigationLifecycle);
    this.beginFaviconGeneration();
    this.requestedUrl = '';
    this.lastErrorUrl = url;
    this.currentUrl = url;
    this.addressText = url;
    this.pageTitle = url;
    this.showHome = false;
    this.currentPageBookmarked = false;
    this.isLoading = false;
    this.setBrowserError(createBrowserWebError({
      tabId: 'incognito-window',
      kind,
      url,
      errorCode,
      detail,
      statusCode,
    }));
    this.refreshNavigationState();
  }

  private setBrowserError(next: BrowserWebErrorState): void {
    const states = this.browserError ? [this.browserError] : [];
    this.browserError = upsertBrowserWebError(states, next)[0] ?? null;
  }

  private clearBrowserError(): void {
    this.browserError = null;
  }

  private getCurrentRequestUrl(): string {
    return this.requestedUrl || this.committedUrl || this.currentUrl;
  }

  private isCurrentMainFrameRequest(isMainFrame: boolean, url: string): boolean {
    return isCurrentMainFrameNavigation(isMainFrame, url, [
      this.requestedUrl,
      this.committedUrl,
      this.currentUrl,
    ]);
  }

  private isAboutBlankUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized === 'about:blank' || normalized.startsWith('about:blank?') ||
      normalized.startsWith('about:blank#');
  }

  private readWebResourceErrorInfo(error: WebResourceError): IncognitoWebResourceErrorInfo {
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

  private refreshNavigationState(): void {
    try {
      this.canGoBack = this.controller.accessBackward();
    } catch (_) {
      this.canGoBack = false;
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

  private buildContextMenuItems(param: WebContextMenuParam): BrowserContextMenuItem[] {
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
      items.push({ id: 'open_link', label: '打开链接', leadingIcon: '↗', dividerBefore: items.length > 0 });
      items.push({ id: 'copy_link', label: '复制链接地址', leadingIcon: '▣' });
    }

    if (hasImage) {
      const imageUrl = sourceUrl || linkUrl;
      if (imageUrl.length > 0) {
        items.push({ id: 'open_image', label: '打开图片', leadingIcon: '◫', dividerBefore: items.length > 0 });
        items.push({ id: 'save_image', label: '保存图片', leadingIcon: '↓' });
        items.push({ id: 'copy_image_url', label: '复制图片地址', leadingIcon: '▣' });
      }
      items.push({
        id: 'copy_image',
        label: '复制图片',
        leadingIcon: '▧',
        dividerBefore: imageUrl.length === 0 && items.length > 0,
      });
    }

    if (selectionText.length > 0 && !editable) {
      items.push({ id: 'copy', label: '复制', leadingIcon: '▣', dividerBefore: items.length > 0 });
      items.push({ id: 'search_selection', label: '搜索选中文本', leadingIcon: '⌕' });
    }

    if (items.length === 0) {
      items.push({ id: 'back', label: '后退', leadingIcon: '‹', disabled: !this.canGoBack });
      let canGoForward = false;
      try {
        canGoForward = this.controller.accessForward();
      } catch (_) {
      }
      items.push({ id: 'forward', label: '前进', leadingIcon: '›', disabled: !canGoForward });
      items.push({ id: 'reload', label: '重新加载', leadingIcon: '↻', dividerBefore: true });
      if (this.currentUrl.length > 0 && this.currentUrl !== 'about:blank') {
        items.push({ id: 'copy_page_address', label: '复制网页地址', leadingIcon: '▣' });
      }
    }
    return items;
  }

  private getContextMenuWidth(): number {
    return Math.max(1, Math.min(248, this.webContentWidth - 16));
  }

  private getContextMenuMaxHeight(): number {
    return Math.max(1, Math.min(420, this.webContentHeight - 16));
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

  private resolveContextMenuPosition(
    rawX: number,
    rawY: number,
    itemCount: number,
  ): IncognitoContextMenuPosition {
    const menuWidth = this.getContextMenuWidth();
    const menuHeight = Math.min(this.getContextMenuMaxHeight(), itemCount * 40 + 16);
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

  private handleContextMenuShow(event: OnContextMenuShowEvent): boolean {
    if (this.showHome) {
      return false;
    }
    const sourceType = this.readContextMenuNumber(() => event.param.getSourceType());
    const useWebPointer = sourceType === 1 && this.hasWebPointerPosition;
    const x = useWebPointer ? this.webPointerX : this.readContextMenuNumber(() => event.param.x());
    const y = useWebPointer ? this.webPointerY : this.readContextMenuNumber(() => event.param.y());
    if (x < 0 || y < 0) {
      return false;
    }
    if (this.showContextMenu && this.pendingContextMenu?.result === event.result) {
      return true;
    }
    this.closeContextMenu();
    const items = this.buildContextMenuItems(event.param);
    if (items.length === 0) {
      return false;
    }
    this.pendingContextMenu = {
      result: event.result,
      linkUrl: this.readContextMenuString(() => event.param.getLinkUrl()),
      sourceUrl: this.readContextMenuString(() => event.param.getSourceUrl()),
      selectionText: this.readContextMenuString(() => event.param.getSelectionText()),
    };
    this.contextMenuTriggerX = x;
    this.contextMenuTriggerY = y;
    const position = this.resolveContextMenuPosition(x, y, items.length);
    this.contextMenuItems = items;
    this.contextMenuX = position.x;
    this.contextMenuY = position.y;
    this.showContextMenu = true;
    return true;
  }

  private handleWebMouse(event: MouseEvent): void {
    if (event.button !== MouseButton.Right) {
      return;
    }
    const x = Number(event.x);
    const y = Number(event.y);
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0) {
      return;
    }
    this.webPointerX = x;
    this.webPointerY = y;
    this.hasWebPointerPosition = true;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_) {
    }
  }

  private stopLoading(): void {
    if (this.showHome || !this.isLoading) {
      return;
    }
    try {
      this.controller.stop();
    } catch (_) {
    }
    stopWebNavigation(this.navigationLifecycle);
    this.pendingControllerLoadUrl = '';
    this.requestedUrl = '';
    this.isLoading = false;
  }

  private toggleFullScreen(): void {
    const nextValue = !this.isFullScreen;
    this.closeContextMenu();
    this.windowManager.setFullScreen(this.getUIContext(), nextValue)
      .then(() => {
        this.isFullScreen = nextValue;
      })
      .catch(() => this.showToast('无法切换全屏模式'));
  }

  private openFindPanel(): void {
    this.closeContextMenu();
    this.showFindPanel = true;
    Promise.resolve().then(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(INCOGNITO_FIND_INPUT_ID);
      } catch (_) {
      }
    });
    if (this.findText.trim()) {
      try {
        this.controller.searchAllAsync(this.findText.trim());
      } catch (_) {
      }
    }
  }

  private closeFindPanel(): void {
    this.showFindPanel = false;
    this.findText = '';
    try {
      this.controller.clearMatches();
    } catch (_) {
    }
  }

  private updateFindText(value: string): void {
    this.findText = value;
    try {
      if (value.trim()) {
        this.controller.searchAllAsync(value.trim());
      } else {
        this.controller.clearMatches();
      }
    } catch (_) {
    }
  }

  private findNext(forward: boolean): void {
    if (!this.showFindPanel || !this.findText.trim()) {
      this.openFindPanel();
      return;
    }
    try {
      this.controller.searchNext(forward);
    } catch (_) {
    }
  }

  private sanitizeFileName(value: string): string {
    const sanitized = value.trim().replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').replace(/\.+$/g, '');
    return (sanitized || '网页').slice(0, 80);
  }

  private printPage(): void {
    if (this.showHome) {
      this.showToast('当前页面无法打印');
      return;
    }
    if (!canIUse('SystemCapability.Print.PrintFramework')) {
      this.showToast('当前设备不支持网页打印');
      return;
    }
    try {
      const jobName = this.sanitizeFileName(this.pageTitle);
      const adapter = this.controller.createWebPrintDocumentAdapter(jobName);
      const attributes: print.PrintAttributes = {};
      print.print(jobName, adapter, attributes, this.getUIContext().getHostContext())
        .catch(() => this.showToast('无法打开打印服务'));
    } catch (_) {
      this.showToast('当前设备不支持网页打印');
    }
  }

  private savePage(): void {
    if (this.showHome) {
      this.showToast('当前页面无法保存');
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const fileName = `${this.sanitizeFileName(this.pageTitle)}.mht`;
    this.controller.storeWebArchive(`${context.cacheDir}/private_saved_page_${Date.now()}`, true)
      .then((archivePath: string) => this.saveArchiveToPicker(context, archivePath, fileName))
      .then(() => this.showToast('网页已保存'))
      .catch(() => this.showToast('未能保存网页'));
  }

  private async saveArchiveToPicker(
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

  private viewSource(): void {
    if (this.showHome) {
      this.showToast('当前页面没有可查看的源码');
      return;
    }
    const pageUrl = this.currentUrl;
    this.controller.runJavaScript('document.documentElement ? document.documentElement.outerHTML : ""')
      .then((source: string) => {
        const escaped = source.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const html = '<!doctype html><meta charset="utf-8">' +
          '<style>body{padding:16px;font:13px/1.55 monospace;' +
          'white-space:pre-wrap;word-break:break-word}</style>' + escaped;
        startWebNavigation(this.navigationLifecycle);
        this.controller.loadData(html, 'text/html', 'UTF-8', pageUrl, `view-source:${pageUrl}`);
        this.pageTitle = `view-source:${pageUrl}`;
      })
      .catch(() => this.showToast('无法读取当前页面源码'));
  }

  private openLocalFile(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['所有文件|.*'];
    new picker.DocumentViewPicker(context).select(options)
      .then((uris: string[]) => {
        if (uris && uris.length > 0) {
          this.addressText = uris[0];
          this.currentUrl = uris[0];
          this.showHome = false;
          this.isLoading = true;
          startWebNavigation(this.navigationLifecycle, uris[0]);
          this.loadUrl(uris[0]);
        }
      })
      .catch(() => {
      });
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (this.showContextMenu && event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeContextMenu();
      return true;
    }
    if (this.showFindPanel && event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeFindPanel();
      return true;
    }
    const action = this.shortcutManager.resolve(event, [], '');
    if (!action) {
      return false;
    }
    return this.applyShortcutAction(action);
  }

  private applyShortcutAction(action: BrowserShortcutAction): boolean {
    if (action.command === 'new_window') {
      this.windowManager.openNormalWindow(this.getUIContext()).catch(() => {
      });
      return true;
    }
    if (action.command === 'new_private_tab') {
      this.windowManager.openPrivateWindow(this.getUIContext()).catch(() => {
      });
      return true;
    }
    if (action.command === 'close_window' || action.command === 'close_tab') {
      this.windowManager.close(this.getUIContext()).catch(() => {
      });
      return true;
    }
    if (action.command === 'focus_address_bar') {
      try {
        this.getUIContext().getFocusController().requestFocus(INCOGNITO_TOOLBAR_INPUT_ID);
      } catch (_) {
      }
      return true;
    }
    if (action.command === 'reload_tab' || action.command === 'reload_tab_ignore_cache') {
      this.reload();
      return true;
    }
    if (action.command === 'go_back') {
      this.goBack();
      return true;
    }
    if (action.command === 'go_forward') {
      this.goForward();
      return true;
    }
    if (action.command === 'go_home') {
      this.goHome();
      return true;
    }
    if (action.command === 'toggle_bookmark') {
      this.toggleBookmark();
      return true;
    }
    if (action.command === 'open_find_in_page') {
      this.openFindPanel();
      return true;
    }
    if (action.command === 'find_next' || action.command === 'find_previous') {
      this.findNext(action.command === 'find_next');
      return true;
    }
    if (action.command === 'stop_loading') {
      this.stopLoading();
      return true;
    }
    if (action.command === 'toggle_fullscreen') {
      this.toggleFullScreen();
      return true;
    }
    if (action.command === 'open_clear_browsing_data') {
      this.windowManager.openClearDataWindow(this.getUIContext()).catch(() => {
      });
      return true;
    }
    if (action.command === 'print_page') {
      this.printPage();
      return true;
    }
    if (action.command === 'save_page') {
      this.savePage();
      return true;
    }
    if (action.command === 'view_source') {
      this.viewSource();
      return true;
    }
    if (action.command === 'open_file') {
      this.openLocalFile();
      return true;
    }
    if (action.command === 'open_tab_search') {
      return true;
    }
    return false;
  }

  private handleContextMenuSelect(item: BrowserContextMenuItem): void {
    const pending = this.pendingContextMenu;
    if (!pending) {
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
        hilog.info(0x0000, 'DownloadTrace',
          'IMAGE_MENU_SELECTED private=true sourceLength=%{public}d linkLength=%{public}d pageLength=%{public}d',
          pending.sourceUrl.length, pending.linkUrl.length, this.currentUrl.length);
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        if (imageUrl.length > 0) {
          // Keep image saving on the managed HTTP path. Calling ArkWeb
          // startDownload() loses the page request context and its async
          // failures bypass the image fallback service.
          void this.startImageDownload(imageUrl).catch(() => {
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
          this.clipboardService.copyText(this.currentUrl);
          result.closeContextMenu();
        });
        return;
      case 'open_link':
      case 'open_image': {
        const url = item.id === 'open_image' ? (pending.sourceUrl || pending.linkUrl) : pending.linkUrl;
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.addressText = url;
        this.submitAddress();
        return;
      }
      case 'search_selection': {
        const text = pending.selectionText;
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.addressText = text;
        this.submitAddress();
        return;
      }
      case 'back':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.goBack();
        return;
      case 'forward':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.goForward();
        return;
      case 'reload':
        this.executeContextMenuResult((result: WebContextMenuResult) => result.closeContextMenu());
        this.reload();
        return;
      default:
        this.closeContextMenu();
    }
  }

  private getCurrentUserAgent(): string {
    try {
      return this.controller.getUserAgent();
    } catch (_) {
      try {
        return webview.WebviewController.getDefaultUserAgent();
      } catch (_) {
        return '';
      }
    }
  }

  private handleLoadIntercept(event: OnLoadInterceptEvent): boolean {
    let requestUrl = '';
    try {
      requestUrl = event.data.getRequestUrl();
    } catch (_) {
      return false;
    }
    if (!isExternalAppSchemeUrl(requestUrl)) {
      return false;
    }
    hilog.info(0x0000, 'NavigationTrace',
      'EXTERNAL_SCHEME_BLOCKED private=true scheme=%{public}s', extractUrlScheme(requestUrl));
    return true;
  }

  private async handleDownloadStart(event: OnDownloadStartEvent): Promise<void> {
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
      pageUrl: this.currentUrl,
      pageTitle: this.pageTitle,
      userAgent: event.userAgent,
      contentLength: event.contentLength,
      isPrivate: true,
      downloadFileUri: fileUri,
    }, hostContext).catch(() => {
    });
  }

  private async startImageDownload(imageUrl: string): Promise<void> {
    const imageMimeType = inferImageMimeType(imageUrl, 'image/*');
    const fileName = buildImageDownloadFileName(imageUrl);
    hilog.info(0x0000, 'DownloadTrace',
      'IMAGE_SAVE_BEGIN private=true sourceLength=%{public}d fileNameLength=%{public}d pageLength=%{public}d',
      imageUrl.length, fileName.length, this.currentUrl.length);
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      hilog.error(0x0000, 'DownloadTrace',
        'IMAGE_SAVE_ABORT private=true reason=no_host_context');
      return;
    }
    const fileUri = await this.downloadSettingsService.chooseDownloadFile(
      hostContext, fileName, imageMimeType);
    hilog.info(0x0000, 'DownloadTrace',
      'IMAGE_SAVE_PICKER_RESULT private=true fileUriPresent=%{public}s fileNameLength=%{public}d',
      String(fileUri.trim().length > 0), fileName.length);
    if (fileUri.trim().length === 0) {
      hilog.info(0x0000, 'DownloadTrace',
        'IMAGE_SAVE_ABORT private=true reason=picker_cancelled');
      return;
    }
    const task = await this.downloadManager.startWebDownload({
      sourceUrl: imageUrl,
      suggestedFileName: fileName,
      mimeType: imageMimeType,
      pageUrl: this.currentUrl,
      pageTitle: this.pageTitle,
      userAgent: this.getCurrentUserAgent(),
      isPrivate: true,
      downloadFileUri: fileUri,
    }, hostContext);
    hilog.info(0x0000, 'DownloadTrace',
      'IMAGE_SAVE_TASK_CREATED private=true task=%{public}s fileUriPresent=%{public}s',
      task.id, String(fileUri.trim().length > 0));
  }

  private async handleGeolocationShow(event: OnGeolocationShowEvent): Promise<void> {
    const origin = event.origin && event.origin.trim().length > 0
      ? event.origin
      : extractSiteOriginFromUrl(this.currentUrl);
    const granted = await this.permissionService.ensureForSitePermission(
      this.getUIContext().getHostContext(), 'location');
    event.geolocation.invoke(origin, granted, false);
  }

  private async handlePermissionRequest(event: OnPermissionRequestEvent): Promise<void> {
    const request = event.request;
    const origin = request.getOrigin() || extractSiteOriginFromUrl(this.currentUrl);
    const resources = request.getAccessibleResource();
    const grantedResources: string[] = [];
    for (let index = 0; index < resources.length; index++) {
      const resource = resources[index];
      const permissionType: SitePermissionType | null = mapProtectedResourceToSitePermissionType(resource);
      const granted = permissionType
        ? await this.permissionService.ensureForSitePermission(this.getUIContext().getHostContext(), permissionType)
        : true;
      if (granted) {
        grantedResources.push(resource);
      }
    }
    if (grantedResources.length > 0) {
      request.grant(grantedResources);
    } else {
      request.deny();
    }
  }

  @Builder
  private NavButton(label: string, onPress: () => void) {
    Button(label)
      .width(34)
      .height(32)
      .fontSize(14)
      .fontColor('#d7dce5')
      .padding(0)
      .backgroundColor('#303642')
      .borderRadius(6)
      .onClick(() => onPress());
  }

  @Builder
  private Toolbar() {
    Row({ space: 8 }) {
      Text('◐')
        .fontSize(18)
        .fontColor('#c4b5fd');

      Text('无痕窗口')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#ffffff');

      this.NavButton('←', () => this.goBack());
      this.NavButton('→', () => this.goForward());
      this.NavButton('⟳', () => this.reload());
      this.NavButton('⌂', () => this.goHome());

      TextInput({
        text: this.addressText,
        placeholder: '无痕搜索或输入网址',
        controller: this.toolbarInputController,
      })
        .id(INCOGNITO_TOOLBAR_INPUT_ID)
        .layoutWeight(1)
        .height(34)
        .fontSize(14)
        .fontColor('#f8fafc')
        .placeholderColor('#9ca3af')
        .backgroundColor('#2b2f37')
        .borderRadius(17)
        .padding({ left: 14, right: 14 })
        .border({ width: 1, color: '#484f5b' })
        .selectAll(true)
        .onChange((value: string) => (this.addressText = value))
        .onSubmit(() => this.submitAddress())
        .onFocus(() => {
          this.toolbarInputFocused = true;
        })
        .onBlur(() => {
          this.toolbarInputFocused = false;
        })
        .onTouch((event: TouchEvent) => this.handleToolbarInputTouch(event))
        .onClick(() => this.handleToolbarInputClick());

      Button(this.currentPageBookmarked ? '★' : '☆')
        .width(34)
        .height(32)
        .fontSize(16)
        .fontColor(this.currentPageBookmarked ? '#facc15' : '#d7dce5')
        .padding(0)
        .backgroundColor('#303642')
        .borderRadius(6)
        .onClick(() => this.toggleBookmark());
    }
    .width('100%')
    .height(50)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#252a33')
    .border({ width: { bottom: 1 }, color: '#343b48' });
  }

  @Builder
  private PrivacyNotice() {
    Row({ space: 10 }) {
      Text('◐')
        .fontSize(14)
        .fontColor('#c4b5fd');

      Text('不会保存浏览历史、Cookie、站点数据或表单输入。' +
        '下载的文件和创建的书签仍会保留。')
        .layoutWeight(1)
        .fontSize(12)
        .fontColor('#d7dce5')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .height(42)
    .padding({ left: 18, right: 18 })
    .backgroundColor('#1b1f27')
    .border({ width: { bottom: 1 }, color: '#343b48' });
  }

  @Builder
  private HomeOverlay() {
    Column({ space: 18 }) {
      Text('无痕浏览')
        .fontSize(22)
        .fontColor('#ffffff');

      Text('此窗口关闭后会清理隐私会话数据。下载文件和书签仍会保留。')
        .width('80%')
        .constraintSize({ maxWidth: 560 })
        .fontSize(13)
        .fontColor('#d7dce5')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      TextInput({
        text: this.addressText,
        placeholder: '无痕搜索或输入网址',
        controller: this.homeInputController,
      })
        .id(INCOGNITO_HOME_INPUT_ID)
        .width(520)
        .height(40)
        .fontSize(15)
        .fontColor('#f8fafc')
        .placeholderColor('#9ca3af')
        .backgroundColor('#2b2f37')
        .borderRadius(20)
        .padding({ left: 18, right: 18 })
        .border({ width: 1, color: '#484f5b' })
        .onChange((value: string) => (this.addressText = value))
        .onSubmit(() => this.submitAddress())
        .onFocus(() => {
          this.homeInputFocused = true;
        })
        .onBlur(() => {
          this.homeInputFocused = false;
        })
        .onTouch((event: TouchEvent) => this.handleHomeInputTouch(event))
        .onClick(() => this.handleHomeInputClick());
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#202227')
    .onClick(() => this.requestHomeInputFocus());
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
      onDismiss: () => this.closeContextMenu(),
    });
  }

  build() {
    Column() {
      if (!this.isFullScreen) {
        this.Toolbar();
        this.PrivacyNotice();
      }

      Stack() {
        Web({ src: '', controller: this.controller, incognitoMode: true })
          .width('100%')
          .height('100%')
          .opacity(this.showHome ? 0 : 1)
          .onMouse((event: MouseEvent) => this.handleWebMouse(event))
          .onLoadIntercept((event: OnLoadInterceptEvent) => this.handleLoadIntercept(event))
          .onControllerAttached(() => this.handleControllerAttached())
          .onPageBegin((event: OnPageBeginEvent) => this.handlePageBegin(event.url))
          .onPageEnd((event: OnPageEndEvent) => this.handlePageEnd(event.url))
          .onNavigationEntryCommitted((details: LoadCommittedDetails) => this.handleHistoryUpdate(details))
          .onTitleReceive((event: OnTitleReceiveEvent) => this.handleTitleReceive(event))
          .onFaviconReceived((event: OnFaviconReceivedEvent) => this.handleFaviconReceived(event))
          .onContextMenuShow((event: OnContextMenuShowEvent) => this.handleContextMenuShow(event))
          .onContextMenuHide(() => this.closeContextMenu(false))
          .onErrorReceive((event: OnErrorReceiveEvent) => this.handleLoadError(event))
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => this.handleHttpError(event))
          .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => this.handleSslError(event))
          .onGeolocationShow((event: OnGeolocationShowEvent) => {
            this.handleGeolocationShow(event).catch(() => {
              event.geolocation.invoke(event.origin, false, false);
            });
          })
          .onPermissionRequest((event: OnPermissionRequestEvent) => {
            this.handlePermissionRequest(event).catch(() => {
              event.request.deny();
            });
          })
          .onRenderProcessNotResponding(
            (data: RenderProcessNotRespondingData) => this.handleRenderProcessNotResponding(data)
          )
          .onRenderProcessResponding(() => this.handleRenderProcessResponding())
          .onRenderExited((event: OnRenderExitedEvent) => this.handleRenderExited(event));

        if (this.showHome) {
          this.HomeOverlay();
        }

        if (!this.showHome && this.browserError) {
          BrowserErrorPage({
            error: this.browserError,
            isPrivate: true,
            canGoBack: this.canGoBack,
            contentWidth: 620,
            onRetry: () => this.reload(),
            onBack: () => this.goBack(),
          })
          .width('100%')
          .height('100%')
          .zIndex(2);
        }

        if (this.showContextMenu) {
          this.ContextMenuOverlay();
        }

        if (this.showFindPanel) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#00000000')
            .onClick(() => this.closeFindPanel());

          TextInput({ text: this.findText, placeholder: '页内查找' })
            .id(INCOGNITO_FIND_INPUT_ID)
            .width(300)
            .height(40)
            .position({ x: Math.max(12, this.webContentWidth - 312), y: 12 })
            .padding({ left: 12, right: 12 })
            .backgroundColor('#ffffff')
            .fontColor('#202124')
            .borderRadius(6)
            .border({ width: 1, color: '#d9dee8' })
            .onChange((value: string) => this.updateFindText(value))
            .onSubmit(() => this.findNext(true));
        }
      }
      .layoutWeight(1)
      .width('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.updateWebContentLayout(Number(newValue.width), Number(newValue.height));
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#202227')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event));
  }
}
