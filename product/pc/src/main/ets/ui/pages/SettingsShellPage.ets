import { SettingsPage } from './SettingsPage';

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

  build() {
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
