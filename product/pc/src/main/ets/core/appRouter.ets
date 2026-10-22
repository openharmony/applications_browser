// AppRouter：应用级路由常量与启动页收口。

export type AppRoute = 'browser' | 'settings' | 'downloads' | 'bookmarks' | 'history';

export class AppRouter {
  public static readonly browser: AppRoute = 'browser';
  public static readonly settings: AppRoute = 'settings';
  public static readonly downloads: AppRoute = 'downloads';
  public static readonly bookmarks: AppRoute = 'bookmarks';
  public static readonly history: AppRoute = 'history';
}
