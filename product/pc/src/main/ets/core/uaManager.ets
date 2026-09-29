// UaManager: resolves and applies the browser User-Agent modes.

import webview from '@ohos.web.webview';

export type UaMode = 'default' | 'desktop' | 'mobile';

const DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const MOBILE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

export class UaManager {
  normalizeMode(value: string): UaMode {
    if (value === 'desktop' || value === 'mobile') {
      return value;
    }
    return 'default';
  }

  getUserAgent(mode: UaMode): string {
    if (mode === 'desktop') {
      return DESKTOP_USER_AGENT;
    }
    if (mode === 'mobile') {
      return MOBILE_USER_AGENT;
    }
    try {
      return webview.WebviewController.getDefaultUserAgent();
    } catch (_) {
      return '';
    }
  }

  apply(controller: webview.WebviewController, mode: UaMode): boolean {
    const userAgent = this.getUserAgent(mode);
    if (!userAgent) {
      return false;
    }
    try {
      controller.setCustomUserAgent(userAgent);
      return true;
    } catch (_) {
      return false;
    }
  }
}
