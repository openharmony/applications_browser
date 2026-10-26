// BrowserWebView：Web 内容区域容器（为标签页承载 Web 运行时实例）。

import webview from '@ohos.web.webview';

@Component
export struct BrowserWebView {
  @Prop src: string = 'about:blank';
  controller: webview.WebviewController = new webview.WebviewController();
  onUrlChange: (url: string) => void = (_: string) => {};

  build() {
    Web({ src: this.src, controller: this.controller })
      .width('100%')
      .height('100%')
      .onPageBegin((event: OnPageBeginEvent) => this.onUrlChange(event.url))
      .onPageEnd((event: OnPageEndEvent) => this.onUrlChange(event.url));
  }
}
