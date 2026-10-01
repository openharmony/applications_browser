// SettingsViewModel：SettingsPage 的数据与操作封装。

import { SearchEngineDefinition, SearchEngineId } from '../../core/searchEngineManager';
import { BrowserSettings, SettingsManager, StartupBehavior } from '../../core/settingsManager';
import { ClearBrowsingDataOptions, ClearBrowsingDataResult, PrivacyManager } from '../../core/privacyManager';
import { SettingsCapability, SettingsSnapshot } from '../../core/settingsCapability';

export interface SettingsPageState {
  defaultSearchEngineId: SearchEngineId;
  defaultSearchEngineName: string;
  supportedSearchEngines: SearchEngineDefinition[];
  defaultZoomPercent: number;
  downloadDirectoryUri: string;
  showDownloadsWhenFinished: boolean;
  homePageUrl: string;
  startupBehavior: StartupBehavior;
  javaScriptEnabled: boolean;
  imagesEnabled: boolean;
  doNotTrack: boolean;
  cookiesEnabled: boolean;
  blockThirdPartyCookies: boolean;
  blockThirdPartyCookiesInPrivate: boolean;
}

export class SettingsViewModel {
  private readonly settingsCapability: SettingsCapability;
  private readonly listenerMap: Map<
    (settings: BrowserSettings) => void,
    (snapshot: SettingsSnapshot) => void
  > = new Map();

  constructor(
    settingsManager?: SettingsManager,
    privacyManager?: PrivacyManager,
    settingsCapability?: SettingsCapability,
  ) {
    this.settingsCapability = settingsCapability ?? (settingsManager || privacyManager ?
      new SettingsCapability(settingsManager, privacyManager) :
      SettingsCapability.getInstance());
  }

  getState(): SettingsPageState {
    const snapshot = this.settingsCapability.getSnapshot();
    const settings = snapshot.settings;
    return {
      defaultSearchEngineId: snapshot.defaultSearchEngineId,
      defaultSearchEngineName: snapshot.defaultSearchEngineName,
      supportedSearchEngines: snapshot.supportedSearchEngines,
      defaultZoomPercent: settings.defaultZoomPercent,
      downloadDirectoryUri: settings.downloadDirectoryUri,
      showDownloadsWhenFinished: settings.showDownloadsWhenFinished,
      homePageUrl: settings.homePageUrl,
      startupBehavior: settings.startupBehavior,
      javaScriptEnabled: settings.javaScriptEnabled,
      imagesEnabled: settings.imagesEnabled,
      doNotTrack: settings.doNotTrack,
      cookiesEnabled: settings.cookiesEnabled,
      blockThirdPartyCookies: settings.blockThirdPartyCookies,
      blockThirdPartyCookiesInPrivate: settings.blockThirdPartyCookiesInPrivate,
    };
  }

  setDefaultSearchEngine(engineId: SearchEngineId): SettingsPageState {
    this.settingsCapability.setDefaultSearchEngine(engineId);
    return this.getState();
  }

  addSearchEngine(name: string, searchUrlTemplate: string): SettingsPageState {
    this.settingsCapability.addSearchEngine(name, searchUrlTemplate);
    return this.getState();
  }

  deleteSearchEngine(engineId: SearchEngineId): SettingsPageState {
    this.settingsCapability.deleteSearchEngine(engineId);
    return this.getState();
  }

  setDefaultZoomPercent(percent: number): SettingsPageState {
    this.settingsCapability.updateSettings({ defaultZoomPercent: percent });
    return this.getState();
  }

  setDownloadDirectoryUri(uri: string): SettingsPageState {
    this.settingsCapability.updateSettings({ downloadDirectoryUri: uri });
    return this.getState();
  }

  setShowDownloadsWhenFinished(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ showDownloadsWhenFinished: enabled });
    return this.getState();
  }

  setHomePageUrl(url: string): SettingsPageState {
    const normalizedUrl = url.trim().length > 0 ? url.trim() : 'about:blank';
    this.settingsCapability.updateSettings({ homePageUrl: normalizedUrl });
    return this.getState();
  }

  setStartupBehavior(behavior: StartupBehavior): SettingsPageState {
    this.settingsCapability.updateSettings({ startupBehavior: behavior });
    return this.getState();
  }

  setJavaScriptEnabled(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ javaScriptEnabled: enabled });
    return this.getState();
  }

  setImagesEnabled(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ imagesEnabled: enabled });
    return this.getState();
  }

  setDoNotTrack(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ doNotTrack: enabled });
    return this.getState();
  }

  setCookiesEnabled(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ cookiesEnabled: enabled });
    return this.getState();
  }

  setBlockThirdPartyCookies(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ blockThirdPartyCookies: enabled });
    return this.getState();
  }

  setBlockThirdPartyCookiesInPrivate(enabled: boolean): SettingsPageState {
    this.settingsCapability.updateSettings({ blockThirdPartyCookiesInPrivate: enabled });
    return this.getState();
  }

  clearBrowsingData(options: ClearBrowsingDataOptions): Promise<ClearBrowsingDataResult> {
    return this.settingsCapability.clearBrowsingData(options)
      .then((result: ClearBrowsingDataResult) => {
        // 仅站点数据被清理时才需要刷新存活标签页（cookie/存储已清，页面需重新
        // 请求才会退出登录）；仅清历史/下载/权限时无需动标签页。
        if (result.siteDataCleared) {
          // 跨窗口广播：BrowserPage 各实例通过 @StorageLink 监听该时间戳，
          // 立即硬加载刷新存活标签页使清理生效，无需重启应用。
          AppStorage.setOrCreate('browsingDataClearedAt', Date.now());
        }
        return result;
      });
  }

  addSettingsListener(listener: (settings: BrowserSettings) => void): void {
    const capabilityListener = (snapshot: SettingsSnapshot) => {
      listener(snapshot.settings);
    };
    this.listenerMap.set(listener, capabilityListener);
    this.settingsCapability.addListener(capabilityListener);
  }

  removeSettingsListener(listener: (settings: BrowserSettings) => void): void {
    const capabilityListener = this.listenerMap.get(listener);
    if (!capabilityListener) {
      return;
    }
    this.listenerMap.delete(listener);
    this.settingsCapability.removeListener(capabilityListener);
  }
}
