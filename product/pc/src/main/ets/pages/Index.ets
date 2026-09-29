import { BrowserPage } from '../ui/pages/BrowserPage';
import { DevLauncherPage } from '../ui/pages/DevLauncherPage';
import { OverlayPlaygroundPage } from '../ui/pages/OverlayPlaygroundPage';
import { AppRoute, AppRouter } from '../core/appRouter';
import { DebugGate } from '../core/debugGate';

@Entry
@Component
struct Index {
  @StorageLink('browserRoute') route: AppRoute = AppRouter.getStartupRoute(DebugGate.getInstance().shouldLaunchToDevLauncher());
  // 启动时默认进入首页（新标签页），不预置要打开的 URL。
  @StorageLink('browserPendingUrl') pendingUrl: string = '';
  @StorageLink('browserPendingNewTabUrl') pendingNewTabUrl: string = '';
  @StorageLink('browserPendingNewWindowUrl') pendingNewWindowUrl: string = '';
  @StorageLink('browserPendingPrivateWindowUrl') pendingPrivateWindowUrl: string = '';
  @State private settingsSectionId: string = 'search-engine';

  build() {
    Stack() {
      // Keep the browser runtime mounted while secondary pages are shown above it.
      // This preserves WebView state, media, forms, and native page history.
      BrowserPage({
        route: $route,
        pendingUrl: $pendingUrl,
        pendingNewTabUrl: $pendingNewTabUrl,
        pendingNewWindowUrl: $pendingNewWindowUrl,
        pendingPrivateWindowUrl: $pendingPrivateWindowUrl,
        settingsSectionId: $settingsSectionId,
      })
        .width('100%')
        .height('100%')
        .zIndex(0);

      if (this.route === AppRouter.DevLauncher) {
        DevLauncherPage({ route: $route, pendingUrl: $pendingUrl })
          .width('100%')
          .height('100%')
          .zIndex(1);
      } else if (this.route === AppRouter.OverlayPlayground) {
        OverlayPlaygroundPage({ route: $route })
          .width('100%')
          .height('100%')
          .zIndex(1);
      }
    }
    .height('100%')
    .width('100%');
  }
}
