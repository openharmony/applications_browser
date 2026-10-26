import { ClearBrowsingDataOptions, ClearBrowsingDataResult, PrivacyManager } from './privacyManager';
import { SearchEngineDefinition, SearchEngineId, SearchEngineManager } from './searchEngineManager';
import { BrowserSettings, SettingsManager, StartupBehavior } from './settingsManager';

export interface SettingsSnapshot {
  settings: BrowserSettings;
  defaultSearchEngineId: SearchEngineId;
  defaultSearchEngineName: string;
  supportedSearchEngines: SearchEngineDefinition[];
}

export interface SettingsPatch {
  defaultSearchEngineId?: SearchEngineId;
  defaultZoomPercent?: number;
  downloadDirectoryUri?: string;
  showDownloadsWhenFinished?: boolean;
  homePageUrl?: string;
  startupBehavior?: StartupBehavior;
  javaScriptEnabled?: boolean;
  imagesEnabled?: boolean;
  doNotTrack?: boolean;
  cookiesEnabled?: boolean;
  blockThirdPartyCookies?: boolean;
  blockThirdPartyCookiesInPrivate?: boolean;
}

type SettingsSnapshotListener = (snapshot: SettingsSnapshot) => void;

export class SettingsCapability {
  private static instance: SettingsCapability = new SettingsCapability();
  private readonly settingsManager: SettingsManager;
  private readonly searchEngineManager: SearchEngineManager;
  private readonly privacyManager: PrivacyManager;
  private listeners: Set<SettingsSnapshotListener> = new Set();
  private readonly settingsListener: (_: BrowserSettings) => void = (_: BrowserSettings) => {
    this.notify();
  };

  constructor(settingsManager?: SettingsManager, privacyManager?: PrivacyManager) {
    this.settingsManager = settingsManager ?? SettingsManager.getInstance();
    this.privacyManager = privacyManager ?? PrivacyManager.getInstance();
    this.searchEngineManager = new SearchEngineManager(this.settingsManager);
    this.settingsManager.addListener(this.settingsListener);
  }

  static getInstance(): SettingsCapability {
    return SettingsCapability.instance;
  }

  getSnapshot(): SettingsSnapshot {
    const settings = this.settingsManager.getSettings();
    const defaultSearchEngineId = this.searchEngineManager.getDefaultEngineId();
    return {
      settings: settings,
      defaultSearchEngineId: defaultSearchEngineId,
      defaultSearchEngineName: this.searchEngineManager.getEngineDefinition(defaultSearchEngineId).name,
      supportedSearchEngines: this.searchEngineManager.getSupportedEngines(),
    };
  }

  updateSettings(patch: SettingsPatch): SettingsSnapshot {
    const nextPatch: Partial<BrowserSettings> = {};
    if (patch.defaultSearchEngineId !== undefined) {
      this.searchEngineManager.setDefaultEngine(patch.defaultSearchEngineId);
    }
    if (patch.defaultZoomPercent !== undefined) {
      nextPatch.defaultZoomPercent = patch.defaultZoomPercent;
    }
    if (patch.downloadDirectoryUri !== undefined) {
      nextPatch.downloadDirectoryUri = patch.downloadDirectoryUri;
    }
    if (patch.showDownloadsWhenFinished !== undefined) {
      nextPatch.showDownloadsWhenFinished = patch.showDownloadsWhenFinished;
    }
    if (patch.homePageUrl !== undefined) {
      nextPatch.homePageUrl = patch.homePageUrl.trim().length > 0 ? patch.homePageUrl.trim() : 'about:blank';
    }
    if (patch.startupBehavior !== undefined) {
      nextPatch.startupBehavior = patch.startupBehavior;
    }
    if (patch.javaScriptEnabled !== undefined) {
      nextPatch.javaScriptEnabled = patch.javaScriptEnabled;
    }
    if (patch.imagesEnabled !== undefined) {
      nextPatch.imagesEnabled = patch.imagesEnabled;
    }
    if (patch.doNotTrack !== undefined) {
      nextPatch.doNotTrack = patch.doNotTrack;
    }
    if (patch.cookiesEnabled !== undefined) {
      nextPatch.cookiesEnabled = patch.cookiesEnabled;
    }
    if (patch.blockThirdPartyCookies !== undefined) {
      nextPatch.blockThirdPartyCookies = patch.blockThirdPartyCookies;
    }
    if (patch.blockThirdPartyCookiesInPrivate !== undefined) {
      nextPatch.blockThirdPartyCookiesInPrivate = patch.blockThirdPartyCookiesInPrivate;
    }
    this.settingsManager.updateSettings(nextPatch);
    return this.getSnapshot();
  }

  setDefaultSearchEngine(engineId: SearchEngineId): SettingsSnapshot {
    this.searchEngineManager.setDefaultEngine(engineId);
    return this.getSnapshot();
  }

  addSearchEngine(name: string, searchUrlTemplate: string): SettingsSnapshot {
    this.searchEngineManager.addCustomEngine(name, searchUrlTemplate);
    return this.getSnapshot();
  }

  deleteSearchEngine(engineId: SearchEngineId): SettingsSnapshot {
    this.searchEngineManager.deleteCustomEngine(engineId);
    return this.getSnapshot();
  }

  clearBrowsingData(options: ClearBrowsingDataOptions): Promise<ClearBrowsingDataResult> {
    return this.privacyManager.clearBrowsingData(options);
  }

  addListener(listener: SettingsSnapshotListener): void {
    this.listeners.add(listener);
  }

  removeListener(listener: SettingsSnapshotListener): void {
    this.listeners.delete(listener);
  }

  private notify(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: SettingsSnapshotListener) => {
      try {
        listener(snapshot);
      } catch (_) {
      }
    });
  }
}
