import { SettingsUiMode, UiSurfaceConfig } from '../../core/uiSurfaceConfig';
import { SettingsPage } from './SettingsPage';
import { WebSettingsPage } from './WebSettingsPage';

@Component
export struct SettingsShellPage {
  // @Prop：BrowserPage 在设置页已挂载时仍会通过 3 点菜单切换 section，
  // 普通字段只在创建时同步一次，会导致菜单点击后 tab 不切换。
  @Prop initialSectionId: string = 'search-engine';
  onBack: () => void = (): void => {};
  onOpenUrl: (url: string) => void = (_: string): void => {};
  onOpenUrlInNewTab: (url: string) => void = (_: string): void => {};
  onOpenUrlInNewWindow: (url: string) => void = (_: string): void => {};
  onOpenUrlInPrivateWindow: (url: string) => void = (_: string): void => {};

  @State private mode: SettingsUiMode = UiSurfaceConfig.getSettingsUiMode();
  @State private isBackHovered: boolean = false;

  private fallbackToNative(): void {
    if (UiSurfaceConfig.shouldFallbackToNativeWhenWebFailed()) {
      this.mode = 'native';
    }
  }

  build() {
    if (this.mode === 'html') {
      Stack({ alignContent: Alignment.TopStart }) {
        WebSettingsPage({
          onFallbackToNative: () => this.fallbackToNative(),
        });

        Button() {
          Text('‹')
            .fontSize(28)
            .fontColor('#5f6368')
            .margin({ bottom: 3 });
        }
          .type(ButtonType.Circle)
          .width(44)
          .height(44)
          .padding(0)
          .hoverEffect(HoverEffect.None)
          .backgroundColor(this.isBackHovered ? '#f1f3f4' : '#ffffff')
          .borderRadius(22)
          .accessibilityText('返回')
          .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
          .mouseResponseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
          .onHover((isHover: boolean) => {
            this.isBackHovered = isHover;
          })
          .margin({ left: 14, top: 14 })
          .onClick(() => this.onBack());
      }
      .width('100%')
      .height('100%');
    } else {
      SettingsPage({
        initialSectionId: this.initialSectionId,
        onBack: () => this.onBack(),
        onOpenUrl: (url: string) => this.onOpenUrl(url),
        onOpenUrlInNewTab: (url: string) => this.onOpenUrlInNewTab(url),
        onOpenUrlInNewWindow: (url: string) => this.onOpenUrlInNewWindow(url),
        onOpenUrlInPrivateWindow: (url: string) => this.onOpenUrlInPrivateWindow(url),
      });
    }
  }
}
