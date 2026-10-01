// SettingsManager：管理浏览器设置，并在变更时通知监听者。

import { preferences } from '@kit.ArkData';

export interface CustomSearchEngineSetting {
  id: string;
  name: string;
  searchUrlTemplate: string;
}

export interface BrowserSettings {
  defaultSearchEngineId: string;
  customSearchEngines: CustomSearchEngineSetting[];
  defaultZoomPercent: number;
  downloadDirectoryUri: string;
  showDownloadsWhenFinished: boolean;
  homePageUrl: string;
  startupBehavior: StartupBehavior;
  javaScriptEnabled: boolean;
  imagesEnabled: boolean;

  // 勿追踪（Do Not Track）请求头开关。
  doNotTrack: boolean;

  // Cookie 策略。
  cookiesEnabled: boolean;
  blockThirdPartyCookies: boolean;
  blockThirdPartyCookiesInPrivate: boolean;
}

export type StartupBehavior = 'restore_session' | 'new_tab' | 'home_page';

type SettingsListener = (settings: BrowserSettings) => void;

export class SettingsManager {
  private static instance: SettingsManager = new SettingsManager();
  private readonly STORE_NAME: string = 'browser_settings_store';
  private readonly SETTINGS_KEY: string = 'browser_settings';
  private settings: BrowserSettings;
  private listeners: Set<SettingsListener> = new Set();
  private store: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;
  private pendingSave: Promise<void> | null = null;
  private hasQueuedSave: boolean = false;

  static getInstance(): SettingsManager {
    return SettingsManager.instance;
  }

  constructor() {
    this.settings = this.getDefaultSettings();
  }

  async init(context: object): Promise<void> {
    if (this.store) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.openStore(context)
      .then(async (store: preferences.Preferences | null) => {
        if (!store) {
          return;
        }
        this.store = store;
        await this.loadSettingsFromStore();
      })
      .finally(() => {
        this.initPromise = null;
      });
    return this.initPromise;
  }

  private async openStore(context: object): Promise<preferences.Preferences | null> {
    try {
      return await preferences.getPreferences(context as never, this.STORE_NAME);
    } catch (_) {
      return null;
    }
  }

  async whenReady(): Promise<void> {
    if (this.initPromise) {
      return this.initPromise;
    }
    return Promise.resolve();
  }

  getSettings(): BrowserSettings {
    return this.cloneSettings(this.settings);
  }

  updateSettings(partial: Partial<BrowserSettings>): void {
    const nextSettings = this.cloneSettings(this.settings);
    if (partial.defaultSearchEngineId !== undefined) {
      nextSettings.defaultSearchEngineId = partial.defaultSearchEngineId;
    }
    if (partial.customSearchEngines !== undefined) {
      nextSettings.customSearchEngines = this.cloneCustomSearchEngines(partial.customSearchEngines);
    }
    if (partial.defaultZoomPercent !== undefined) {
      nextSettings.defaultZoomPercent = this.normalizeZoomPercent(partial.defaultZoomPercent);
    }
    if (partial.downloadDirectoryUri !== undefined) {
      nextSettings.downloadDirectoryUri = partial.downloadDirectoryUri.trim();
    }
    if (partial.showDownloadsWhenFinished !== undefined) {
      nextSettings.showDownloadsWhenFinished = partial.showDownloadsWhenFinished;
    }
    if (partial.homePageUrl !== undefined) {
      nextSettings.homePageUrl = partial.homePageUrl;
    }
    if (partial.startupBehavior !== undefined) {
      nextSettings.startupBehavior = partial.startupBehavior;
    }
    if (partial.javaScriptEnabled !== undefined) {
      nextSettings.javaScriptEnabled = partial.javaScriptEnabled;
    }
    if (partial.imagesEnabled !== undefined) {
      nextSettings.imagesEnabled = partial.imagesEnabled;
    }
    if (partial.doNotTrack !== undefined) {
      nextSettings.doNotTrack = partial.doNotTrack;
    }
    if (partial.cookiesEnabled !== undefined) {
      nextSettings.cookiesEnabled = partial.cookiesEnabled;
    }
    if (partial.blockThirdPartyCookies !== undefined) {
      nextSettings.blockThirdPartyCookies = partial.blockThirdPartyCookies;
    }
    if (partial.blockThirdPartyCookiesInPrivate !== undefined) {
      nextSettings.blockThirdPartyCookiesInPrivate = partial.blockThirdPartyCookiesInPrivate;
    }
    this.settings = nextSettings;
    this.notify();
    this.persistSettings();
  }

  addListener(listener: SettingsListener): void {
    this.listeners.add(listener);
  }

  removeListener(listener: SettingsListener): void {
    this.listeners.delete(listener);
  }

  private notify(): void {
    const snapshot = this.getSettings();
    this.listeners.forEach(listener => {
      try {
        listener(snapshot);
      } catch (_) {
      }
    });
  }

  private async loadSettingsFromStore(): Promise<void> {
    if (!this.store) {
      return;
    }

    try {
      const rawValue = await this.store.get(this.SETTINGS_KEY, '');
      if (typeof rawValue !== 'string' || rawValue.trim().length === 0) {
        return;
      }
      const parsed = JSON.parse(rawValue) as Partial<BrowserSettings>;
      this.settings = this.mergeWithDefaultSettings(parsed);
      this.notify();
    } catch (_) {
    }
  }

  private persistSettings(): void {
    if (!this.store) {
      if (this.initPromise) {
        this.initPromise
          .then(() => this.persistSettings())
          .catch(() => {
          });
      }
      return;
    }

    if (this.pendingSave) {
      this.hasQueuedSave = true;
      return;
    }

    const serialized = JSON.stringify(this.cloneSettings(this.settings));
    this.pendingSave = this.store.put(this.SETTINGS_KEY, serialized)
      .then(() => this.store ? this.store.flush() : Promise.resolve())
      .catch(() => {
      })
      .finally(() => {
        this.pendingSave = null;
        if (this.hasQueuedSave) {
          this.hasQueuedSave = false;
          this.persistSettings();
        }
      });
  }

  private getDefaultSettings(): BrowserSettings {
    return {
      defaultSearchEngineId: 'baidu',
      customSearchEngines: [],
      defaultZoomPercent: 100,
      downloadDirectoryUri: '',
      showDownloadsWhenFinished: true,
      homePageUrl: 'about:blank',
      startupBehavior: 'restore_session',
      javaScriptEnabled: true,
      imagesEnabled: true,
      doNotTrack: false,
      cookiesEnabled: true,
      blockThirdPartyCookies: false,
      blockThirdPartyCookiesInPrivate: false,
    };
  }

  private cloneSettings(settings: BrowserSettings): BrowserSettings {
    return {
      defaultSearchEngineId: settings.defaultSearchEngineId,
      customSearchEngines: this.cloneCustomSearchEngines(settings.customSearchEngines),
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

  private mergeWithDefaultSettings(storedSettings: Partial<BrowserSettings>): BrowserSettings {
    const defaultSettings = this.getDefaultSettings();
    return {
      defaultSearchEngineId: this.readSearchEngineId(
        storedSettings.defaultSearchEngineId,
        defaultSettings.defaultSearchEngineId
      ),
      customSearchEngines: this.readCustomSearchEngines(storedSettings.customSearchEngines),
      defaultZoomPercent: this.normalizeZoomPercent(
        storedSettings.defaultZoomPercent ?? defaultSettings.defaultZoomPercent
      ),
      downloadDirectoryUri: this.readOptionalString(storedSettings.downloadDirectoryUri),
      showDownloadsWhenFinished: this.readBoolean(
        storedSettings.showDownloadsWhenFinished,
        defaultSettings.showDownloadsWhenFinished,
      ),
      homePageUrl: this.readString(storedSettings.homePageUrl, defaultSettings.homePageUrl),
      startupBehavior: this.readStartupBehavior(storedSettings.startupBehavior, defaultSettings.startupBehavior),
      javaScriptEnabled: this.readBoolean(storedSettings.javaScriptEnabled, defaultSettings.javaScriptEnabled),
      imagesEnabled: this.readBoolean(storedSettings.imagesEnabled, defaultSettings.imagesEnabled),
      doNotTrack: this.readBoolean(storedSettings.doNotTrack, defaultSettings.doNotTrack),
      cookiesEnabled: this.readBoolean(storedSettings.cookiesEnabled, defaultSettings.cookiesEnabled),
      blockThirdPartyCookies: this.readBoolean(
        storedSettings.blockThirdPartyCookies,
        defaultSettings.blockThirdPartyCookies
      ),
      blockThirdPartyCookiesInPrivate: this.readBoolean(
        storedSettings.blockThirdPartyCookiesInPrivate,
        defaultSettings.blockThirdPartyCookiesInPrivate
      ),
    };
  }

  private readSearchEngineId(value: string | undefined, fallback: string): string {
    return value !== undefined && value.trim().length > 0 ? value.trim() : fallback;
  }

  private readCustomSearchEngines(value: CustomSearchEngineSetting[] | undefined): CustomSearchEngineSetting[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const engines: CustomSearchEngineSetting[] = [];
    const ids: Set<string> = new Set();
    value.forEach((engine: CustomSearchEngineSetting) => {
      if (!engine || typeof engine.id !== 'string' || typeof engine.name !== 'string' ||
        typeof engine.searchUrlTemplate !== 'string') {
        return;
      }
      const id = engine.id.trim();
      const name = engine.name.trim();
      const template = engine.searchUrlTemplate.trim().split('%s').join('{query}');
      const isHttpTemplate = template.startsWith('http://') || template.startsWith('https://');
      const isDuplicate = ids.has(id) || id === 'baidu' || id === 'so360';
      if (!id || !name || !isHttpTemplate || !template.includes('{query}') || isDuplicate) {
        return;
      }
      ids.add(id);
      engines.push({
        id: id,
        name: name,
        searchUrlTemplate: template,
      });
    });
    return engines;
  }

  private cloneCustomSearchEngines(value: CustomSearchEngineSetting[]): CustomSearchEngineSetting[] {
    const engines: CustomSearchEngineSetting[] = [];
    value.forEach((engine: CustomSearchEngineSetting) => {
      engines.push({
        id: engine.id,
        name: engine.name,
        searchUrlTemplate: engine.searchUrlTemplate,
      });
    });
    return engines;
  }

  private normalizeZoomPercent(value: number): number {
    if (!Number.isFinite(value)) {
      return 100;
    }
    return Math.max(25, Math.min(200, Math.round(value)));
  }

  private readStartupBehavior(value: StartupBehavior | undefined, fallback: StartupBehavior): StartupBehavior {
    return value === 'restore_session' || value === 'new_tab' || value === 'home_page' ? value : fallback;
  }

  private readString(value: string | undefined, fallback: string): string {
    return value !== undefined && value.trim().length > 0 ? value : fallback;
  }

  private readOptionalString(value: string | undefined): string {
    return value !== undefined ? value.trim() : '';
  }

  private readBoolean(value: boolean | undefined, fallback: boolean): boolean {
    return value !== undefined ? value : fallback;
  }
}
