// AppRouter：应用级路由常量与启动页收口。

export type AppRoute = 'browser' | 'dev' | 'settings' | 'downloads' | 'bookmarks' | 'history' | 'overlay_playground';

export class AppRouter {
  static readonly Browser: AppRoute = 'browser';
  static readonly DevLauncher: AppRoute = 'dev';
  static readonly Settings: AppRoute = 'settings';
  static readonly Downloads: AppRoute = 'downloads';
  static readonly Bookmarks: AppRoute = 'bookmarks';
  static readonly History: AppRoute = 'history';
  static readonly OverlayPlayground: AppRoute = 'overlay_playground';

  static getStartupRoute(shouldLaunchToDevLauncher: boolean): AppRoute {
    return shouldLaunchToDevLauncher ? AppRouter.DevLauncher : AppRouter.Browser;
  }
}
