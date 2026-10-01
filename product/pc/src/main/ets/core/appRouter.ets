// AppRouter：应用级路由常量与启动页收口。

export type AppRoute = 'browser' | 'dev' | 'settings' | 'downloads' | 'bookmarks' | 'history' | 'overlay_playground';

export class AppRouter {
  public static readonly browser: AppRoute = 'browser';
  public static readonly devLauncher: AppRoute = 'dev';
  public static readonly settings: AppRoute = 'settings';
  public static readonly downloads: AppRoute = 'downloads';
  public static readonly bookmarks: AppRoute = 'bookmarks';
  public static readonly history: AppRoute = 'history';
  public static readonly overlayPlayground: AppRoute = 'overlay_playground';

  static getStartupRoute(shouldLaunchToDevLauncher: boolean): AppRoute {
    return shouldLaunchToDevLauncher ? AppRouter.devLauncher : AppRouter.browser;
  }
}
