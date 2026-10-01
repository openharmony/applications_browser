// WindowService：系统窗口管理 API 适配层。

import { window } from '@kit.ArkUI';
import webview from '@ohos.web.webview';
import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// Keep subwindows consistent with the window that launched them. These values
// are only a fallback for the short period before the source window exposes a
// valid rect (or on device forms that do not report one).
const SUBWINDOW_FALLBACK_WIDTH: number = 1280;
const SUBWINDOW_FALLBACK_HEIGHT: number = 800;
const SUBWINDOW_MIN_WIDTH: number = 720;
const SUBWINDOW_MIN_HEIGHT: number = 480;
const SUBWINDOW_CASCADE_OFFSET: number = 32;

// 对话框式 window.open 弹窗（如微信扫码登录）使用固定小尺寸并居中于来源窗口。
// ArkWeb 的 OnWindowNewEvent 不携带 width/height 特征值，只能给定合理默认值。
const POPUP_FALLBACK_WIDTH: number = 860;
const POPUP_FALLBACK_HEIGHT: number = 1000;
const POPUP_MIN_WIDTH: number = 480;
const POPUP_MIN_HEIGHT: number = 420;

export interface WindowTitleButtonRectInfo {
  width: number;
  height: number;
}

export class WindowService {
  private static instance: WindowService = new WindowService();
  private mainWindow: window.Window | null = null;
  private subWindowIndex: number = 0;
  private titleButtonRectListener: ((rect: window.TitleButtonRect) => void) | null = null;
  // 待弹窗窗口 Web 组件挂载的 ArkWeb controller。按官方模式，onWindowNew 回调里
  // 同步创建全新 controller 并 setWebController 交给内核，这里在 setUIContent 之前
  // 登记，PopupWindow 页面 aboutToAppear 时取走并作为 Web 组件的 controller，
  // 内核随组件挂载完成 window.open 的导航转移。
  private pendingPopupControllers: Map<string, webview.WebviewController> = new Map();

  static getInstance(): WindowService {
    return WindowService.instance;
  }

  async bind(hostContext: common.BaseContext): Promise<void> {
    if (this.mainWindow) {
      return;
    }
    try {
      this.mainWindow = await window.getLastWindow(hostContext);
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  private async resolveWindow(hostContext: common.BaseContext, windowName?: string): Promise<window.Window> {
    if (windowName) {
      try {
        return window.findWindow(windowName);
      } catch (_) {
      }
    }
    if (this.mainWindow) {
      return this.mainWindow;
    }
    try {
      const mainWindow = await window.getLastWindow(hostContext);
      this.mainWindow = mainWindow;
      return mainWindow;
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async minimize(hostContext: common.BaseContext, windowName?: string): Promise<void> {
    try {
      const mainWindow = await this.resolveWindow(hostContext, windowName);
      await mainWindow.minimize();
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async maximize(hostContext: common.BaseContext, windowName?: string): Promise<void> {
    try {
      const mainWindow = await this.resolveWindow(hostContext, windowName);
      await mainWindow.maximize();
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async close(hostContext: common.BaseContext, windowName?: string): Promise<void> {
    try {
      const mainWindow = await this.resolveWindow(hostContext, windowName);
      await mainWindow.destroyWindow();
      if (this.mainWindow === mainWindow) {
        this.mainWindow = null;
      }
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async resizeBy(
    hostContext: common.BaseContext,
    widthDelta: number,
    heightDelta: number,
    windowName?: string
  ): Promise<void> {
    try {
      const mainWindow = await this.resolveWindow(hostContext, windowName);
      const rect = mainWindow.getWindowProperties().windowRect;
      const nextWidth = this.normalizeSize(rect.width + widthDelta, 320);
      const nextHeight = this.normalizeSize(rect.height + heightDelta, 240);
      await mainWindow.resize(nextWidth, nextHeight);
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async openNormalWindow(sourceWindowName?: string, initialUrl: string = ''): Promise<void> {
    await this.openBrowserSubWindow('normal', 'pages/NormalWindow', sourceWindowName, initialUrl);
  }

  async openPrivateWindow(sourceWindowName?: string, initialUrl: string = ''): Promise<void> {
    await this.openBrowserSubWindow('private', 'pages/IncognitoWindow', sourceWindowName, initialUrl);
  }

  async openClearDataWindow(sourceWindowName?: string): Promise<void> {
    await this.openBrowserSubWindow('settings', 'pages/ClearDataWindow', sourceWindowName);
  }

  async openPopupWindow(sourceWindowName?: string, initialUrl: string = '', title: string = '',
    controller?: webview.WebviewController, userAgent: string = ''): Promise<void> {
    await this.openBrowserSubWindow('popup', 'pages/PopupWindow', sourceWindowName, initialUrl,
      title, controller, userAgent);
  }

  takePopupController(windowName: string): webview.WebviewController | null {
    const controller = this.pendingPopupControllers.get(windowName);
    if (controller) {
      this.pendingPopupControllers.delete(windowName);
      return controller;
    }
    return null;
  }

  private async openBrowserSubWindow(kind: string, pagePath: string, sourceWindowName?: string,
    initialUrl: string = '', title: string = '', controller?: webview.WebviewController,
    userAgent: string = ''): Promise<void> {
    const windowStage = AppStorage.get<window.WindowStage>('browserWindowStage');
    if (!windowStage) {
      throw new Error('WindowStage is not available');
    }

    const name = `oh_browser_${kind}_${Date.now()}_${this.subWindowIndex++}`;
    const initialRect = this.getSubWindowRect(sourceWindowName, kind);
    let browserWindow: window.Window | null = null;
    try {
      hilog.info(DOMAIN, 'WindowService', 'Opening subwindow %{public}s', name);
      // Explicit options are important for child windows: without decorEnabled
      // a subwindow has no system title controls and cannot be moved by its
      // title bar. The rect mirrors the source window so a new window does not
      // unexpectedly open as a tiny floating child window.
      try {
        browserWindow = await windowStage.createSubWindowWithOptions(name, {
          title: title.length > 0 ? title : this.getSubWindowTitle(kind),
          decorEnabled: true,
          windowRect: initialRect,
          maximizeSupported: kind !== 'popup',
        });
      } catch (error) {
        // Older device images may expose createSubWindow but not its options
        // overload. Fall back to the legacy API and apply geometry below.
        hilog.warn(
          DOMAIN, 'WindowService', 'createSubWindowWithOptions failed: %{public}s', this.getErrorMessage(error)
        );
        browserWindow = await windowStage.createSubWindow(name);
      }
      hilog.info(DOMAIN, 'WindowService', 'Subwindow created %{public}s', name);
      // Subwindow decoration is provided by the system. Geometry and interaction
      // settings are optional on some device forms, so they must not block content loading.
      try {
        await browserWindow.setWindowTouchable(true);
      } catch (error) {
        hilog.warn(DOMAIN, 'WindowService', 'setWindowTouchable failed: %{public}s', this.getErrorMessage(error));
      }
      try {
        await browserWindow.setWindowFocusable(true);
      } catch (error) {
        hilog.warn(DOMAIN, 'WindowService', 'setWindowFocusable failed: %{public}s', this.getErrorMessage(error));
      }
      // The options overload already applies the rect. Applying it again is
      // harmless and makes the fallback path behave identically.
      try {
        await browserWindow.resize(initialRect.width, initialRect.height);
      } catch (error) {
        hilog.warn(DOMAIN, 'WindowService', 'resize failed: %{public}s', this.getErrorMessage(error));
      }
      try {
        await browserWindow.moveWindowTo(initialRect.left, initialRect.top);
      } catch (error) {
        hilog.warn(DOMAIN, 'WindowService', 'moveWindowTo failed: %{public}s', this.getErrorMessage(error));
      }
      try {
        browserWindow.setWindowTitleMoveEnabled(true);
      } catch (error) {
        hilog.warn(
          DOMAIN, 'WindowService', 'setWindowTitleMoveEnabled failed: %{public}s', this.getErrorMessage(error)
        );
      }
      try {
        await browserWindow.setResizeByDragEnabled(true);
      } catch (error) {
        hilog.warn(DOMAIN, 'WindowService', 'setResizeByDragEnabled failed: %{public}s', this.getErrorMessage(error));
      }
      hilog.info(DOMAIN, 'WindowService', 'Loading subwindow content %{public}s', pagePath);
      if (initialUrl.trim().length > 0) {
        AppStorage.setOrCreate(`browserSubWindowPendingUrl:${name}`, initialUrl.trim());
      }
      if (userAgent.length > 0) {
        AppStorage.setOrCreate(`browserPopupUserAgent:${name}`, userAgent);
      }
      // controller 必须在 setUIContent 之前登记：PopupWindow 的 aboutToAppear 会在
      // setUIContent 过程中执行，晚于此时机写入会导致弹窗取不到 controller。
      if (controller) {
        this.pendingPopupControllers.set(name, controller);
      }
      await browserWindow.setUIContent(pagePath);
      hilog.info(DOMAIN, 'WindowService', 'Subwindow content loaded %{public}s', name);
      await browserWindow.showWindow();
      hilog.info(DOMAIN, 'WindowService', 'Subwindow shown %{public}s', name);
      await this.focusSubWindow(browserWindow, sourceWindowName);
    } catch (error) {
      hilog.error(
        DOMAIN, 'WindowService', 'Open subwindow failed at %{public}s: %{public}s',
        name, this.getErrorMessage(error)
      );
      this.pendingPopupControllers.delete(name);
      AppStorage.delete(`browserPopupUserAgent:${name}`);
      if (browserWindow) {
        await this.destroyWindowSafely(browserWindow);
      }
      throw new Error(this.getErrorMessage(error));
    }
  }

  private getSubWindowTitle(kind: string): string {
    if (kind === 'private') {
      return '无痕窗口';
    }
    if (kind === 'settings') {
      return '浏览器设置';
    }
    if (kind === 'popup') {
      return '网页弹窗';
    }
    return '新窗口';
  }

  private getSubWindowRect(sourceWindowName?: string, kind: string = 'normal'): window.Rect {
    let sourceRect: window.Rect | null = null;
    try {
      const sourceWindow = sourceWindowName ? window.findWindow(sourceWindowName) : this.mainWindow;
      if (sourceWindow) {
        sourceRect = sourceWindow.getWindowProperties().windowRect;
      }
    } catch (error) {
      hilog.warn(DOMAIN, 'WindowService', 'Read source window rect failed: %{public}s', this.getErrorMessage(error));
    }

    if (kind === 'popup') {
      // 对话框式弹窗固定小尺寸并居中于来源窗口，模仿桌面浏览器弹窗形态。
      const width = this.normalizeSize(POPUP_FALLBACK_WIDTH, POPUP_MIN_WIDTH);
      const height = this.normalizeSize(POPUP_FALLBACK_HEIGHT, POPUP_MIN_HEIGHT);
      const sourceWidth = sourceRect?.width ?? SUBWINDOW_FALLBACK_WIDTH;
      const sourceHeight = sourceRect?.height ?? SUBWINDOW_FALLBACK_HEIGHT;
      const sourceLeft = sourceRect?.left ?? 80;
      const sourceTop = sourceRect?.top ?? 60;
      const left = Math.max(0, Math.floor(sourceLeft + (sourceWidth - width) / 2));
      const top = Math.max(0, Math.floor(sourceTop + (sourceHeight - height) / 2));
      return { left, top, width, height };
    }

    const width = this.normalizeSize(sourceRect?.width ?? SUBWINDOW_FALLBACK_WIDTH, SUBWINDOW_MIN_WIDTH);
    const height = this.normalizeSize(sourceRect?.height ?? SUBWINDOW_FALLBACK_HEIGHT, SUBWINDOW_MIN_HEIGHT);
    const left = Math.max(0, Math.floor((sourceRect?.left ?? 80) + SUBWINDOW_CASCADE_OFFSET));
    const top = Math.max(0, Math.floor((sourceRect?.top ?? 80) + SUBWINDOW_CASCADE_OFFSET));
    return { left, top, width, height };
  }

  private async focusSubWindow(targetWindow: window.Window, sourceWindowName?: string): Promise<void> {
    try {
      const sourceWindow = sourceWindowName ? window.findWindow(sourceWindowName) : this.mainWindow;
      if (!sourceWindow) {
        return;
      }
      const sourceId = sourceWindow.getWindowProperties().id;
      const targetId = targetWindow.getWindowProperties().id;
      await window.shiftAppWindowFocus(sourceId, targetId);
    } catch (_) {
    }
  }

  async enableImmersiveTitleBar(hostContext: common.BaseContext, windowName?: string): Promise<void> {
    try {
      const mainWindow = await this.resolveWindow(hostContext, windowName);
      mainWindow.setWindowDecorVisible(false);
      mainWindow.setWindowDecorHeight(56);
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async subscribeTitleButtonRectChange(
    hostContext: common.BaseContext,
    listener: (info: WindowTitleButtonRectInfo) => void,
    windowName?: string,
  ): Promise<void> {
    try {
      const mainWindow = await this.resolveWindow(hostContext, windowName);
      this.titleButtonRectListener = (rect: window.TitleButtonRect): void => {
        try {
          listener({
            width: Number(rect.width),
            height: Number(rect.height),
          });
        } catch (_) {
        }
      };
      mainWindow.on('windowTitleButtonRectChange', this.titleButtonRectListener);
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  async setFullScreen(hostContext: common.BaseContext, enabled: boolean, windowName?: string): Promise<void> {
    try {
      const targetWindow = await this.resolveWindow(hostContext, windowName);
      await targetWindow.setWindowLayoutFullScreen(enabled);
      await targetWindow.setWindowSystemBarEnable(enabled ? [] : ['status', 'navigation']);
    } catch (error) {
      throw new Error(this.getErrorMessage(error));
    }
  }

  private normalizeSize(size: number, min: number): number {
    const value = Math.floor(size);
    return value < min ? min : value;
  }

  private async destroyWindowSafely(targetWindow: window.Window): Promise<void> {
    try {
      await targetWindow.destroyWindow();
    } catch (_) {
    }
  }

  private getErrorMessage(error: Object): string {
    const maybeError = error as Error;
    if (maybeError && maybeError.message && maybeError.message.length > 0) {
      return maybeError.message;
    }
    return String(error);
  }
}
