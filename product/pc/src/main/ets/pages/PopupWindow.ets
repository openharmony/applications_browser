// PopupWindow：window.open(url, name, 'width=...,height=...') 对话框式弹窗页面。
// 不带标签栏与导航栏：页面只承载一个裸 Web。
//
// 时序（官方模式）：BrowserPage 在 onWindowNew 回调内同步创建全新 controller
// 并 event.handler.setWebController() 交给内核 → WindowService 在 setUIContent
// 前把该 controller 登记进注册表 → 本页面 aboutToAppear 取走并作为 Web 组件的
// controller → 组件挂载时内核完成 window.open 的导航转移。

import webview from '@ohos.web.webview';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UaManager } from '../core/uaManager';
import { DownloadManager } from '../core/downloadManager';
import { WindowManager } from '../core/windowManager';
import { extractUrlScheme, isExternalAppSchemeUrl } from '../core/urlNormalizer';

const DOMAIN = 0x0000;
const LOG_TAG = 'PopupWindow';
// 挂载后若内核迟迟没有推送 window.open 的导航，用初始 URL 兜底自救。
const NAVIGATION_RESCUE_DELAY_MS: number = 1500;

@Entry
@Component
struct PopupWindow {
  private controller: webview.WebviewController = new webview.WebviewController();
  private uaManager: UaManager = new UaManager();
  private downloadManager: DownloadManager = DownloadManager.getInstance();
  private downloadDelegate: webview.WebDownloadDelegate | null = null;
  private windowName: string = '';
  // 是否挂载的是内核已绑定的 controller（正常路径）。
  private tookBoundController: boolean = false;
  private isDestroyed: boolean = false;
  private pendingUrl: string = '';
  // 没取到 bound controller 时才手动加载初始 URL；正常路径下导航由内核完成。
  @State private manualUrl: string = '';
  @State private userAgent: string = '';

  aboutToAppear(): void {
    this.windowName = this.getUIContext().getWindowName() ?? '';
    const boundController = WindowManager.getInstance().takePopupController(this.windowName);
    if (boundController) {
      this.controller = boundController;
      this.tookBoundController = true;
    }
    const uaKey = `browserPopupUserAgent:${this.windowName}`;
    const storedUa = AppStorage.get<string>(uaKey) ?? '';
    AppStorage.delete(uaKey);
    this.userAgent = storedUa.length > 0 ? storedUa : this.uaManager.getUserAgent('desktop');
    const urlKey = `browserSubWindowPendingUrl:${this.windowName}`;
    this.pendingUrl = (AppStorage.get<string>(urlKey) ?? '').trim();
    AppStorage.delete(urlKey);
    this.manualUrl = this.tookBoundController ? '' : this.pendingUrl;
    hilog.info(DOMAIN, LOG_TAG,
      'Popup page ready window=%{public}s manualUrl=%{public}s boundController=%{public}s',
      this.windowName, this.manualUrl, String(this.tookBoundController));
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
  }

  private cancelHandler(handler: ControllerHandler): void {
    try {
      // null 是 ArkWeb 约定的取消信号（与 BrowserPage.cancelWebWindow 一致）。
      handler.setWebController(null as never);
    } catch (_) {
    }
  }

  /**
   * 兜底：正常路径下内核会在组件挂载后推送 window.open 的目标导航。若超过
   * 阈值仍停留在空白页（个别内核版本/路径不推送），用初始 URL 手动加载。
   * document.write 型弹窗（targetUrl 为 about:blank）不适用，保持跳过。
   */
  private rescuePendingNavigation(): void {
    if (!this.tookBoundController || this.isDestroyed) {
      return;
    }
    const url = this.pendingUrl;
    if (url.length === 0 || url === 'about:blank') {
      return;
    }
    let currentUrl: string;
    try {
      currentUrl = this.controller.getUrl() ?? '';
    } catch (_) {
      return;
    }
    if (currentUrl.length > 0 && currentUrl !== 'about:blank') {
      return;
    }
    try {
      this.controller.loadUrl(url);
      hilog.info(DOMAIN, LOG_TAG, 'Navigation rescue fired window=%{public}s url=%{public}s', this.windowName, url);
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, 'Navigation rescue failed: %{public}s', String(error));
    }
  }

  private closeSelf(): void {
    if (!this.windowName) {
      return;
    }
    try {
      window.findWindow(this.windowName).destroyWindow();
    } catch (error) {
      hilog.warn(DOMAIN, LOG_TAG, 'Close popup failed: %{public}s', String(error));
    }
  }

  private attachDownloadDelegate(): void {
    if (!this.downloadDelegate) {
      this.downloadDelegate = this.downloadManager.createArkWebDownloadDelegate(
        (item: webview.WebDownloadItem) => this.handleArkWebDownload(item));
    }
    try {
      this.controller.setDownloadDelegate(this.downloadDelegate);
      hilog.info(DOMAIN, 'DownloadTrace', 'ARKWEB_DELEGATE_ATTACHED popup=%{public}s', this.windowName);
    } catch (error) {
      hilog.error(DOMAIN, 'DownloadTrace',
        'ARKWEB_DELEGATE_ATTACH_FAILED popup=%{public}s error=%{public}s', this.windowName, String(error));
    }
  }

  private handleArkWebDownload(item: webview.WebDownloadItem): void {
    try {
      let pageUrl = this.pendingUrl;
      let pageTitle = this.windowName;
      try {
        pageUrl = this.controller.getUrl() || pageUrl;
        pageTitle = this.controller.getTitle() || pageTitle;
      } catch (_) {
      }
      this.downloadManager.startArkWebDownload(item, {
        sourceUrl: item.getUrl(),
        suggestedFileName: item.getSuggestedFileName(),
        mimeType: item.getMimeType(),
        pageUrl: pageUrl,
        pageTitle: pageTitle,
        userAgent: this.userAgent,
        contentLength: item.getTotalBytes(),
        isPrivate: false,
      }, this.getUIContext().getHostContext());
    } catch (error) {
      hilog.error(DOMAIN, 'DownloadTrace',
        'ARKWEB_BEFORE_DOWNLOAD_FAILED popup=%{public}s error=%{public}s', this.windowName, String(error));
      try {
        item.cancel();
      } catch (_) {
      }
    }
  }

  build() {
    Column() {
      Web({ src: this.manualUrl, controller: this.controller })
        .multiWindowAccess(true)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .zoomAccess(true)
        .forceEnableZoom(true)
        .userAgent(this.userAgent)
        .onLoadIntercept((event: OnLoadInterceptEvent) => {
          let requestUrl = '';
          try {
            requestUrl = event.data.getRequestUrl();
          } catch (_) {
            return false;
          }
          if (!isExternalAppSchemeUrl(requestUrl)) {
            return false;
          }
          hilog.info(DOMAIN, LOG_TAG, 'External scheme blocked scheme=%{public}s',
            extractUrlScheme(requestUrl));
          return true;
        })
        .onControllerAttached(() => {
          hilog.info(DOMAIN, LOG_TAG, 'Controller attached window=%{public}s', this.windowName);
          this.attachDownloadDelegate();
          if (this.tookBoundController) {
            setTimeout(() => this.rescuePendingNavigation(), NAVIGATION_RESCUE_DELAY_MS);
          }
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          hilog.info(DOMAIN, LOG_TAG, 'Page begin window=%{public}s url=%{public}s',
            this.windowName, event.url);
        })
        .onPageEnd((event: OnPageEndEvent) => {
          hilog.info(DOMAIN, LOG_TAG, 'Page end window=%{public}s url=%{public}s',
            this.windowName, event.url);
        })
        .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => {
          // 证书错误（过期/自签/域不匹配等）直接放行，便于验证异常证书页面。
          try {
            event.handler.handleConfirm();
          } catch (_) {
          }
        })
        .onErrorReceive((event) => {
          if (event && event.request.getRequestUrl().startsWith('http')) {
            hilog.error(DOMAIN, LOG_TAG, 'Page error window=%{public}s url=%{public}s error=%{public}s',
              this.windowName, event.request.getRequestUrl(), event.error.getErrorInfo());
          }
        })
        .onWindowNew((event: OnWindowNewEvent) => {
          if (!event.isUserTrigger) {
            this.cancelHandler(event.handler);
            return;
          }
          // 弹窗内再次 window.open：与顶层一致，同步 bind 全新 controller 后
          // 继续以弹窗承接。
          const nestedController = new webview.WebviewController();
          try {
            event.handler.setWebController(nestedController);
          } catch (_) {
            this.cancelHandler(event.handler);
            return;
          }
          WindowManager.getInstance().openPopupWindow(this.getUIContext(), event.targetUrl,
            '', nestedController, this.userAgent)
            .then(() => hilog.info(DOMAIN, LOG_TAG, 'Nested popup opened'))
            .catch(() => {
              hilog.error(DOMAIN, LOG_TAG, 'Nested popup open failed');
              this.cancelHandler(event.handler);
            });
        })
        .onWindowExit(() => {
          hilog.info(DOMAIN, LOG_TAG, 'Window exit requested');
          this.closeSelf();
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
