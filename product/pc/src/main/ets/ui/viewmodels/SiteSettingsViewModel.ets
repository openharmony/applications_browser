import {
  getSitePermissionLabel,
  SitePermissionSetting,
  SitePermissionSettingDecision,
  SitePermissionType,
} from '../../core/permissionTypes';
import { SiteSettingsManager } from '../../core/siteSettingsManager';

export interface SiteSettingsSiteSummary {
  origin: string;
  displayName: string;
  permissionCount: number;
  permissionSummary: string;
  updatedAt: number;
}

export interface SiteSettingsPageState {
  sites: SiteSettingsSiteSummary[];
  totalSiteCount: number;
  totalPermissionCount: number;
}

export class SiteSettingsViewModel {
  private readonly siteSettingsManager: SiteSettingsManager;

  constructor(siteSettingsManager?: SiteSettingsManager) {
    this.siteSettingsManager = siteSettingsManager ?? SiteSettingsManager.getInstance();
  }

  getState(permissionType?: SitePermissionType): SiteSettingsPageState {
    const settings = this.siteSettingsManager.listPermissionSettings();
    const settingsByOrigin: Map<string, SitePermissionSetting[]> = new Map();
    settings.forEach((setting: SitePermissionSetting) => {
      if (permissionType !== undefined && setting.permissionType !== permissionType) {
        return;
      }
      const existing = settingsByOrigin.get(setting.origin) ?? [];
      existing.push(setting);
      settingsByOrigin.set(setting.origin, existing);
    });

    const sites: SiteSettingsSiteSummary[] = [];
    settingsByOrigin.forEach((originSettings: SitePermissionSetting[], origin: string) => {
      originSettings.sort((left: SitePermissionSetting, right: SitePermissionSetting) =>
        right.updatedAt - left.updatedAt);
      sites.push({
        origin: origin,
        displayName: this.getOriginDisplayName(origin),
        permissionCount: originSettings.length,
        permissionSummary: originSettings
          .map((setting: SitePermissionSetting) => getSitePermissionLabel(setting.permissionType))
          .join('、'),
        updatedAt: originSettings.length > 0 ? originSettings[0].updatedAt : 0,
      });
    });
    sites.sort((left: SiteSettingsSiteSummary, right: SiteSettingsSiteSummary) => right.updatedAt - left.updatedAt);

    return {
      sites: sites,
      totalSiteCount: sites.length,
      totalPermissionCount: settings.length,
    };
  }

  getSiteSettings(origin: string): SitePermissionSetting[] {
    return this.siteSettingsManager.listPermissionSettings(origin);
  }

  setPermissionDecision(origin: string, permissionType: SitePermissionType,
    decision: SitePermissionSettingDecision): SitePermissionSetting[] {
    this.siteSettingsManager.setPermissionSetting(origin, permissionType, decision, 'user');
    return this.getSiteSettings(origin);
  }

  resetSite(origin: string): SiteSettingsPageState {
    this.siteSettingsManager.clearSiteSettings(origin);
    return this.getState();
  }

  getPermissionCount(permissionType: SitePermissionType): number {
    return this.siteSettingsManager.listPermissionSettings()
      .filter((setting: SitePermissionSetting) => setting.permissionType === permissionType)
      .length;
  }

  private getOriginDisplayName(origin: string): string {
    return origin.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '') || origin;
  }
}
