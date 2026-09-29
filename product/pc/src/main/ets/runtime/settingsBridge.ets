import { ClearBrowsingDataOptions } from '../core/privacyManager';
import { SearchEngineId } from '../core/searchEngineManager';
import { SettingsCapability, SettingsPatch } from '../core/settingsCapability';
import { StartupBehavior } from '../core/settingsManager';
import { DispatchResult, JSBridgeDispatcher, MethodHandler } from './jsBridgeDispatcher';
import { JSBridgeFacade } from './jsBridgeFacade';

interface SettingsUpdateParams {
  defaultSearchEngineId?: string;
  defaultZoomPercent?: number;
  downloadDirectoryUri?: string;
  showDownloadsWhenFinished?: boolean;
  homePageUrl?: string;
  startupBehavior?: string;
  javaScriptEnabled?: boolean;
  imagesEnabled?: boolean;
  doNotTrack?: boolean;
  cookiesEnabled?: boolean;
  blockThirdPartyCookies?: boolean;
  blockThirdPartyCookiesInPrivate?: boolean;
}

interface SearchEngineParams {
  engineId?: string;
}

interface ClearBrowsingDataParams {
  history?: boolean;
  downloads?: boolean;
  siteData?: boolean;
  sitePermissions?: boolean;
}

export const SETTINGS_BRIDGE_CAPABILITIES: string[] = [
  'settings.getSnapshot',
  'settings.update',
  'settings.setDefaultSearchEngine',
  'privacy.clearBrowsingData',
];

export function registerSettingsBridgeHandlers(jsBridge: JSBridgeFacade, capability?: SettingsCapability): void {
  const bridge = new SettingsBridgeHandlers(capability);
  jsBridge.registerMethod('settings.getSnapshot', bridge.requireTrusted(async (_paramsJson: string) => {
    return JSBridgeDispatcher.ok(JSON.stringify(bridge.getCapability().getSnapshot()));
  }));
  jsBridge.registerMethod('settings.update', bridge.requireTrusted(async (paramsJson: string) => {
    const params = bridge.parseUpdateParams(paramsJson);
    return JSBridgeDispatcher.ok(JSON.stringify(bridge.getCapability().updateSettings(params)));
  }));
  jsBridge.registerMethod('settings.setDefaultSearchEngine', bridge.requireTrusted(async (paramsJson: string) => {
    const params = bridge.parseSearchEngineParams(paramsJson);
    return JSBridgeDispatcher.ok(JSON.stringify(bridge.getCapability().setDefaultSearchEngine(params)));
  }));
  jsBridge.registerMethod('privacy.clearBrowsingData', bridge.requireTrusted(async (paramsJson: string) => {
    const options = bridge.parseClearBrowsingDataOptions(paramsJson);
    const result = await bridge.getCapability().clearBrowsingData(options);
    return JSBridgeDispatcher.ok(JSON.stringify(result));
  }));
}

class SettingsBridgeHandlers {
  private readonly capability: SettingsCapability;

  constructor(capability?: SettingsCapability) {
    this.capability = capability ?? SettingsCapability.getInstance();
  }

  getCapability(): SettingsCapability {
    return this.capability;
  }

  requireTrusted(handler: (paramsJson: string, url: string) => Promise<DispatchResult>): MethodHandler {
    return async (paramsJson: string, url: string) => {
      if (!this.isTrustedSettingsUrl(url)) {
        return JSBridgeDispatcher.fail(-32003, 'forbidden_origin');
      }
      return handler(paramsJson, url);
    };
  }

  parseUpdateParams(paramsJson: string): SettingsPatch {
    const params = this.parseJson(paramsJson) as SettingsUpdateParams;
    const patch: SettingsPatch = {};
    const searchEngineId = this.readSearchEngineId(params.defaultSearchEngineId);
    const startupBehavior = this.readStartupBehavior(params.startupBehavior);
    if (searchEngineId) patch.defaultSearchEngineId = searchEngineId;
    if (typeof params.defaultZoomPercent === 'number') patch.defaultZoomPercent = params.defaultZoomPercent;
    if (typeof params.downloadDirectoryUri === 'string') patch.downloadDirectoryUri = params.downloadDirectoryUri;
    if (typeof params.showDownloadsWhenFinished === 'boolean') {
      patch.showDownloadsWhenFinished = params.showDownloadsWhenFinished;
    }
    if (typeof params.homePageUrl === 'string') patch.homePageUrl = params.homePageUrl;
    if (startupBehavior) patch.startupBehavior = startupBehavior;
    if (typeof params.javaScriptEnabled === 'boolean') patch.javaScriptEnabled = params.javaScriptEnabled;
    if (typeof params.imagesEnabled === 'boolean') patch.imagesEnabled = params.imagesEnabled;
    if (typeof params.doNotTrack === 'boolean') patch.doNotTrack = params.doNotTrack;
    if (typeof params.cookiesEnabled === 'boolean') patch.cookiesEnabled = params.cookiesEnabled;
    if (typeof params.blockThirdPartyCookies === 'boolean') patch.blockThirdPartyCookies = params.blockThirdPartyCookies;
    if (typeof params.blockThirdPartyCookiesInPrivate === 'boolean') patch.blockThirdPartyCookiesInPrivate = params.blockThirdPartyCookiesInPrivate;
    return patch;
  }

  parseSearchEngineParams(paramsJson: string): SearchEngineId {
    const params = this.parseJson(paramsJson) as SearchEngineParams;
    const engineId = this.readSearchEngineId(params.engineId);
    if (!engineId) {
      throw new Error('invalid_search_engine');
    }
    return engineId;
  }

  parseClearBrowsingDataOptions(paramsJson: string): ClearBrowsingDataOptions {
    const params = this.parseJson(paramsJson) as ClearBrowsingDataParams;
    return {
      history: params.history === true,
      downloads: params.downloads === true,
      siteData: params.siteData === true,
      sitePermissions: params.sitePermissions === true,
    };
  }

  private parseJson(paramsJson: string): Object {
    try {
      return JSON.parse(paramsJson && paramsJson.trim().length > 0 ? paramsJson : '{}') as Object;
    } catch (_) {
      throw new Error('invalid_json');
    }
  }

  private isTrustedSettingsUrl(url: string): boolean {
    return String(url || '').startsWith('resource://rawfile/settings/');
  }

  private readSearchEngineId(value?: string): SearchEngineId | undefined {
    if (typeof value !== 'string') {
      return undefined;
    }
    const engineId = value.trim();
    return engineId.length > 0 && engineId.length <= 128 ? engineId : undefined;
  }

  private readStartupBehavior(value?: string): StartupBehavior | undefined {
    if (value === 'restore_session' || value === 'new_tab' || value === 'home_page') {
      return value;
    }
    return undefined;
  }
}
