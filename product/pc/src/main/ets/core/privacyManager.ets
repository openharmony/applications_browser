// PrivacyManager：隐私相关的统一入口与“清除浏览数据”等流程编排。

import { DownloadManager } from './downloadManager';
import { HistoryManager } from './historyManager';
import { PermissionManager } from './permissionManager';
import { ClearSiteDataResult, SiteDataManager } from './siteDataManager';
import { SiteSettingsManager } from './siteSettingsManager';

export interface ClearBrowsingDataOptions {
  history?: boolean;
  downloads?: boolean;
  siteData?: boolean;
  sitePermissions?: boolean;
}

export interface ClearBrowsingDataResult {
  historyCleared: boolean;
  downloadsCleared: boolean;
  siteDataCleared: boolean;
  sitePermissionsCleared: boolean;
  failedItems: string[];
  success: boolean;
}

export interface PrivacyHistoryDataSource {
  clearAllHistory(): Promise<void>;
}

export interface PrivacyDownloadDataSource {
  clearDownloads(includePrivate?: boolean): Promise<void>;
  clearPrivateDownloads(): void;
}

export interface PrivacySiteSettingsDataSource {
  clearAllSiteSettings(): Promise<void>;
}

export class PrivacyManager {
  private static instance: PrivacyManager = new PrivacyManager();
  private readonly historyManager: PrivacyHistoryDataSource;
  private readonly downloadManager: PrivacyDownloadDataSource;
  private readonly permissionManager: PermissionManager;
  private readonly siteDataManager: SiteDataManager;
  private readonly siteSettingsManager: PrivacySiteSettingsDataSource;

  constructor(
    historyManager?: PrivacyHistoryDataSource,
    downloadManager?: PrivacyDownloadDataSource,
    siteDataManager?: SiteDataManager,
    siteSettingsManager?: PrivacySiteSettingsDataSource,
    permissionManager?: PermissionManager,
  ) {
    this.historyManager = historyManager ?? HistoryManager.getInstance();
    this.downloadManager = downloadManager ?? DownloadManager.getInstance();
    this.permissionManager = permissionManager ?? PermissionManager.getInstance();
    this.siteDataManager = siteDataManager ?? SiteDataManager.getInstance();
    this.siteSettingsManager = siteSettingsManager ?? SiteSettingsManager.getInstance();
  }

  static getInstance(): PrivacyManager {
    return PrivacyManager.instance;
  }

  clearAllBrowsingData(): Promise<ClearBrowsingDataResult> {
    return this.clearBrowsingData({
      history: true,
      downloads: true,
      siteData: true,
      sitePermissions: true,
    });
  }

  clearPrivateSessionData(): ClearBrowsingDataResult {
    const result: ClearBrowsingDataResult = {
      historyCleared: true,
      downloadsCleared: false,
      siteDataCleared: false,
      sitePermissionsCleared: false,
      failedItems: [],
      success: true,
    };

    try {
      this.permissionManager.clearPrivateSessionSettings();
      result.sitePermissionsCleared = true;
    } catch (_) {
      result.failedItems.push('sitePermissions');
    }

    try {
      this.downloadManager.clearPrivateDownloads();
      result.downloadsCleared = true;
    } catch (_) {
      result.failedItems.push('downloads');
    }

    try {
      const siteDataResult = this.siteDataManager.clearPrivateSessionSiteData();
      result.siteDataCleared = siteDataResult.success;
      if (!siteDataResult.success) {
        result.failedItems.push('siteData');
      }
    } catch (_) {
      result.failedItems.push('siteData');
    }

    result.success = result.failedItems.length === 0;
    return result;
  }

  async clearBrowsingData(options: ClearBrowsingDataOptions): Promise<ClearBrowsingDataResult> {
    const result: ClearBrowsingDataResult = {
      historyCleared: false,
      downloadsCleared: false,
      siteDataCleared: false,
      sitePermissionsCleared: false,
      failedItems: [],
      success: true,
    };

    if (options.history === true) {
      try {
        await this.historyManager.clearAllHistory();
        result.historyCleared = true;
      } catch (_) {
        result.failedItems.push('history');
      }
    }

    if (options.downloads === true) {
      try {
        await this.downloadManager.clearDownloads(false);
        result.downloadsCleared = true;
      } catch (_) {
        result.failedItems.push('downloads');
      }
    }

    if (options.siteData === true) {
      try {
        const siteDataResult = this.siteDataManager.clearAllSiteData();
        result.siteDataCleared = siteDataResult.success;
        if (!siteDataResult.success) {
          result.failedItems.push('siteData');
        }
      } catch (_) {
        result.failedItems.push('siteData');
      }
    }

    if (options.sitePermissions === true) {
      try {
        await this.siteSettingsManager.clearAllSiteSettings();
        result.sitePermissionsCleared = true;
      } catch (_) {
        result.failedItems.push('sitePermissions');
      }
    }

    result.success = result.failedItems.length === 0;
    return result;
  }
}
