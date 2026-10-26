// BrowserCore：浏览器核心门面，用于聚合与编排各核心管理器。

import { TabManager } from './tabManager';
import { NavigationController } from './navigationController';
import { SettingsManager } from './settingsManager';
import { DownloadManager } from './downloadManager';

export class BrowserCore {
  public readonly tabs: TabManager;
  public readonly navigation: NavigationController;
  public readonly settings: SettingsManager;
  public readonly downloads: DownloadManager;

  constructor() {
    this.tabs = new TabManager();
    this.navigation = new NavigationController();
    this.settings = SettingsManager.getInstance();
    this.downloads = DownloadManager.getInstance();
  }
}
