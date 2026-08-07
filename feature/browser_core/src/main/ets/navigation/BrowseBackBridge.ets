/** 浏览页 @Entry 与 BrowsePageView 之间的返回键桥接（系统导航条 / 侧滑触发 onBackPress） */
export class BrowseBackBridge {
  private static handler: (() => boolean) | null = null

  static register(handler: () => boolean): void {
    BrowseBackBridge.handler = handler
  }

  static unregister(): void {
    BrowseBackBridge.handler = null
  }

  static handleBackPress(): boolean {
    if (BrowseBackBridge.handler !== null) {
      return BrowseBackBridge.handler()
    }
    return false
  }
}
