import webview from '@ohos.web.webview';

@Component
export struct LocalHtmlWebView {
  @Prop src: string = 'about:blank';
  controller: webview.WebviewController = new webview.WebviewController();
  onPageBegin: (url: string) => void = (_: string) => {};
  onPageEnd: (url: string) => void = (_: string) => {};
  onLoadError: () => void = () => {};

  build() {
    Web({ src: this.src, controller: this.controller })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .onPageBegin((event: OnPageBeginEvent) => this.onPageBegin(event.url))
      .onPageEnd((event: OnPageEndEvent) => this.onPageEnd(event.url))
      .onErrorReceive(() => this.onLoadError());
  }
}
