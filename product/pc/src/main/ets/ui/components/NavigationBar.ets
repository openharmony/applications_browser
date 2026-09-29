// NavigationBar：后退/前进/刷新/主页等导航控制按钮。
import { hilog } from '@kit.PerformanceAnalysisKit';

const NAVIGATION_LOG_DOMAIN: number = 0x0000;
const NAVIGATION_LOG_TAG: string = 'NavigationTrace';

@Component
export struct NavigationBar {
  @Link canGoBack: boolean;
  @Link canGoForward: boolean;

  onBack: () => void = () => {};
  onForward: () => void = () => {};
  onReload: () => void = () => {};
  onHome: () => void = () => {};

  private emitBack(): void {
    this.onBack();
  }

  private emitForward(): void {
    this.onForward();
  }

  private emitReload(): void {
    this.onReload();
  }

  private emitHome(): void {
    this.onHome();
  }

  private isActionEnabled(action: string): boolean {
    if (action === 'back') {
      return this.canGoBack;
    }
    if (action === 'forward') {
      return this.canGoForward;
    }
    return true;
  }

  @Builder
  private IconButton(action: string, icon: Resource, enabled: boolean, onPress: () => void) {
    Row() {
      Image(icon)
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .opacity(this.isActionEnabled(action) ? 1 : 0.24);
    }
    .width(32)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor('#00000000')
    .onClick(() => {
      // Read the @Link at click time. A builder callback can otherwise retain
      // the value from the render that created it while navigation state is
      // being updated asynchronously.
      const currentEnabled = this.isActionEnabled(action);
      hilog.info(NAVIGATION_LOG_DOMAIN, NAVIGATION_LOG_TAG,
        'NAV_BUTTON_CLICK action=%{public}s rendered=%{public}s current=%{public}s canBack=%{public}s canForward=%{public}s',
        action, String(enabled), String(currentEnabled), String(this.canGoBack), String(this.canGoForward));
      if (currentEnabled) {
        onPress();
      }
    });
  }

  build() {
    Row({ space: 4 }) {
      this.IconButton('back', $r('app.media.home_backward'), this.canGoBack, () => this.emitBack());
      this.IconButton('forward', $r('app.media.home_next'), this.canGoForward, () => this.emitForward());
      this.IconButton('reload', $r('app.media.home_refresh'), true, () => this.emitReload());
      this.IconButton('home', $r('app.media.home_home'), true, () => this.emitHome());
    }
    .padding({ left: 0, right: 0 })
  }
}
