/** FeaturePanel 子页（书签/历史等）与 @Entry 之间的系统返回键桥接 */
export class FeaturePanelBackBridge {
  private static handler: (() => boolean) | null = null

  static register(handler: () => boolean): void {
    FeaturePanelBackBridge.handler = handler
  }

  static unregister(): void {
    FeaturePanelBackBridge.handler = null
  }

  static handleBackPress(): boolean {
    if (FeaturePanelBackBridge.handler !== null) {
      return FeaturePanelBackBridge.handler()
    }
    return false
  }
}
