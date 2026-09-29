// WebSettingsAdapter：将浏览器/站点设置应用到 Web 运行时。

import { SettingsManager } from '../core/settingsManager';

export interface AppliedWebSettings {
  javaScriptAccess: boolean;
  imageAccess: boolean;
  onlineImageAccess: boolean;
  domStorageAccess: boolean;
  databaseAccess: boolean;
}

export interface AppliedCookieSettings {
  acceptCookies: boolean;
  acceptThirdPartyCookies: boolean;
  supportsPrivateThirdPartyCookiePolicy: boolean;
}

export interface RequestHeaderDecision {
  headers: Header[];
  shouldBlockRequest: boolean;
}

export class WebSettingsAdapter {
  private readonly settingsManager: SettingsManager;

  constructor(settingsManager?: SettingsManager) {
    this.settingsManager = settingsManager ?? SettingsManager.getInstance();
  }

  getAppliedWebSettings(): AppliedWebSettings {
    const settings = this.settingsManager.getSettings();
    return {
      javaScriptAccess: settings.javaScriptEnabled,
      imageAccess: settings.imagesEnabled,
      onlineImageAccess: settings.imagesEnabled,
      // Cookies are controlled by WebCookieManager; they are independent of
      // DOM Storage and Web SQL/Database access.
      domStorageAccess: true,
      databaseAccess: true,
    };
  }

  getAppliedCookieSettings(): AppliedCookieSettings {
    const settings = this.settingsManager.getSettings();
    return {
      acceptCookies: settings.cookiesEnabled,
      // ArkWeb exposes this as a process-wide WebCookieManager setting. The
      // private-only preference must not silently change regular tab behavior.
      acceptThirdPartyCookies: settings.cookiesEnabled && !settings.blockThirdPartyCookies,
      supportsPrivateThirdPartyCookiePolicy: false,
    };
  }

  buildInitialRequestHeaders(): Header[] {
    const settings = this.settingsManager.getSettings();
    if (!settings.doNotTrack) {
      return [];
    }
    return [{ headerKey: 'DNT', headerValue: '1' }];
  }

  resolveRequestHeaders(_requestUrl: string, _pageUrl: string, _isPrivate: boolean, headers: Header[]): RequestHeaderDecision {
    const settings = this.settingsManager.getSettings();
    const nextHeaders: Header[] = [];
    const shouldBlockRequest = false;

    headers.forEach((header: Header) => {
      const key = header.headerKey.toLowerCase();
      if (key === 'dnt') {
        return;
      }
      nextHeaders.push({
        headerKey: header.headerKey,
        headerValue: header.headerValue,
      });
    });

    if (settings.doNotTrack) {
      nextHeaders.push({ headerKey: 'DNT', headerValue: '1' });
    }

    return {
      headers: nextHeaders,
      shouldBlockRequest,
    };
  }

}
