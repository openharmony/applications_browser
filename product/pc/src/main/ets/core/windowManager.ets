// WindowManager：管理浏览器窗口及窗口与标签页的映射。

import { WindowService, WindowTitleButtonRectInfo } from '../integration/windowService';
import common from '@ohos.app.ability.common';
import webview from '@ohos.web.webview';

export class WindowManager {
  private static instance: WindowManager = new WindowManager();
  private readonly windowService: WindowService = WindowService.getInstance();

  static getInstance(): WindowManager {
    return WindowManager.instance;
  }

  async bind(uiContext: UIContext): Promise<void> {
    await this.windowService.bind(uiContext.getHostContext() as common.BaseContext);
  }

  async enableImmersiveTitleBar(uiContext: UIContext): Promise<void> {
    await this.windowService.enableImmersiveTitleBar(
      uiContext.getHostContext() as common.BaseContext,
      uiContext.getWindowName(),
    );
  }

  async subscribeTitleButtonRectChange(
    uiContext: UIContext,
    listener: (info: WindowTitleButtonRectInfo) => void,
  ): Promise<void> {
    await this.windowService.subscribeTitleButtonRectChange(
      uiContext.getHostContext() as common.BaseContext,
      listener,
      uiContext.getWindowName(),
    );
  }

  async minimize(uiContext: UIContext): Promise<void> {
    await this.windowService.minimize(uiContext.getHostContext() as common.BaseContext, uiContext.getWindowName());
  }

  async maximize(uiContext: UIContext): Promise<void> {
    await this.windowService.maximize(uiContext.getHostContext() as common.BaseContext, uiContext.getWindowName());
  }

  async close(uiContext: UIContext): Promise<void> {
    await this.windowService.close(uiContext.getHostContext() as common.BaseContext, uiContext.getWindowName());
  }

  async openNormalWindow(uiContext: UIContext, initialUrl: string = ''): Promise<void> {
    await this.windowService.openNormalWindow(uiContext.getWindowName(), initialUrl);
  }

  async openPopupWindow(uiContext: UIContext, initialUrl: string = '', title: string = '',
    controller?: webview.WebviewController, userAgent: string = ''): Promise<void> {
    await this.windowService.openPopupWindow(uiContext.getWindowName(), initialUrl, title, controller, userAgent);
  }

  takePopupController(windowName: string): webview.WebviewController | null {
    return this.windowService.takePopupController(windowName);
  }

  async openPrivateWindow(uiContext: UIContext, initialUrl: string = ''): Promise<void> {
    await this.windowService.openPrivateWindow(uiContext.getWindowName(), initialUrl);
  }

  async openClearDataWindow(uiContext: UIContext): Promise<void> {
    await this.windowService.openClearDataWindow(uiContext.getWindowName());
  }

  async setFullScreen(uiContext: UIContext, enabled: boolean): Promise<void> {
    await this.windowService.setFullScreen(
      uiContext.getHostContext() as common.BaseContext,
      enabled,
      uiContext.getWindowName(),
    );
  }

  async zoomIn(uiContext: UIContext): Promise<void> {
    await this.windowService.resizeBy(
      uiContext.getHostContext() as common.BaseContext,
      120,
      80,
      uiContext.getWindowName(),
    );
  }

  async zoomOut(uiContext: UIContext): Promise<void> {
    await this.windowService.resizeBy(
      uiContext.getHostContext() as common.BaseContext,
      -120,
      -80,
      uiContext.getWindowName(),
    );
  }
}
