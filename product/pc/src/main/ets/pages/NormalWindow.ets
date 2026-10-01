import { BrowserPage } from '../ui/pages/BrowserPage';
import { AppRoute, AppRouter } from '../core/appRouter';

@Entry
@Component
struct NormalWindow {
  @State private route: AppRoute = AppRouter.browser;
  @State private pendingUrl: string = '';
  @State private pendingNewTabUrl: string = '';
  @State private pendingNewWindowUrl: string = '';
  @State private pendingPrivateWindowUrl: string = '';
  @State private settingsSectionId: string = 'search-engine';

  aboutToAppear(): void {
    const windowName = this.getUIContext().getWindowName();
    const key = `browserSubWindowPendingUrl:${windowName}`;
    const initialUrl = AppStorage.get<string>(key) ?? '';
    if (initialUrl.trim().length > 0) {
      this.pendingUrl = initialUrl.trim();
      AppStorage.setOrCreate(key, '');
    }
  }

  build() {
    Stack() {
      BrowserPage({
        route: $route,
        pendingUrl: $pendingUrl,
        pendingNewTabUrl: $pendingNewTabUrl,
        pendingNewWindowUrl: $pendingNewWindowUrl,
        pendingPrivateWindowUrl: $pendingPrivateWindowUrl,
        settingsSectionId: $settingsSectionId,
        sessionPersistenceEnabled: false,
      })
        .width('100%')
        .height('100%');

    }
    .width('100%')
    .height('100%');
  }
}
