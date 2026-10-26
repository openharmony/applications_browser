// SiteDataManager：管理站点数据（Cookie、存储等）。

import webview from '@ohos.web.webview';

export interface ClearSiteDataOptions {
  cookies?: boolean;
  storage?: boolean;
}

export interface ClearSiteDataResult {
  cookiesCleared: boolean;
  storageCleared: boolean;
  failedItems: string[];
  success: boolean;
}

export class SiteDataManager {
  private static instance: SiteDataManager = new SiteDataManager();

  static getInstance(): SiteDataManager {
    return SiteDataManager.instance;
  }

  clearCookies(): boolean {
    // ArkWeb 的 incognito 参数是 profile 选择器：false 清普通（非隐私）模式的持久
    // cookie，true 清无痕（隐私）模式的内存 cookie。普通窗口的“清除数据”必须以
    // false 为主目标；true 一并调用，兜底设备 ROM 行为差异并清理无痕残留。
    let cleared = true;
    try {
      webview.WebCookieManager.clearAllCookiesSync(false);
    } catch (_) {
      cleared = false;
    }
    try {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } catch (_) {
      cleared = false;
    }
    return cleared;
  }

  clearStorage(): boolean {
    // deleteAllData 的 incognito 参数语义与 clearAllCookiesSync 一致。
    let cleared = true;
    try {
      webview.WebStorage.deleteAllData(false);
    } catch (_) {
      cleared = false;
    }
    try {
      webview.WebStorage.deleteAllData(true);
    } catch (_) {
      cleared = false;
    }
    return cleared;
  }

  clearPrivateSessionSiteData(): ClearSiteDataResult {
    // ArkWeb's incognito Web instances use an isolated ephemeral profile.
    // The global cleanup APIs below would also erase regular-window data, so
    // never call them when the private profile is being discarded.
    return {
      cookiesCleared: true,
      storageCleared: true,
      failedItems: [],
      success: true,
    };
  }

  clearAllSiteData(options: ClearSiteDataOptions = { cookies: true, storage: true }): ClearSiteDataResult {
    const result: ClearSiteDataResult = {
      cookiesCleared: false,
      storageCleared: false,
      failedItems: [],
      success: true,
    };

    if (options.cookies !== false) {
      if (this.clearCookies()) {
        result.cookiesCleared = true;
      } else {
        result.failedItems.push('cookies');
      }
    }

    if (options.storage !== false) {
      if (this.clearStorage()) {
        result.storageCleared = true;
      } else {
        result.failedItems.push('storage');
      }
    }

    result.success = result.failedItems.length === 0;
    return result;
  }
}
