// WindowControls：最小化/最大化(还原)/关闭按钮区域。

@Component
export struct WindowControls {
  onMinimize: () => void = () => {};
  onMaximize: () => void = () => {};
  onClose: () => void = () => {};

  @Builder
  private IconButton(icon: Resource, onPress: () => void) {
    Row() {
      Image(icon)
        .width(12)
        .height(12)
        .opacity(0.74);
    }
    .width(34)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .borderRadius(6)
    .backgroundColor('#00000000')
    .onClick(() => onPress());
  }

  build() {
    Row({ space: 2 }) {
      this.IconButton($r('app.media.app_minimum'), () => this.onMinimize());
      this.IconButton($r('app.media.app_zoom'), () => this.onMaximize());
      this.IconButton($r('app.media.app_close'), () => this.onClose());
    }
    .padding({ right: 2 })
  }
}
