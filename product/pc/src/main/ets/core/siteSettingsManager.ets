import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';
import {
  buildSitePermissionRequestKey,
  normalizeSiteOrigin,
  SitePermissionSetting,
  SitePermissionSettingDecision,
  SitePermissionSettingSource,
  SitePermissionType,
} from './permissionTypes';

export class SiteSettingsManager {
  private static instance: SiteSettingsManager = new SiteSettingsManager();
  private permissionSettings: Map<string, SitePermissionSetting> = new Map();
  private rdbStore: relationalStore.RdbStore | null = null;
  private readonly DB_NAME = 'browser_site_settings.db';
  private readonly TABLE_NAME = 'site_permission_settings';
  private isInitialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private pendingSettings: Map<string, SitePermissionSetting> = new Map();
  private pendingDeletedSettings: Set<string> = new Set();
  private pendingDeletedOrigins: Set<string> = new Set();

  static getInstance(): SiteSettingsManager {
    return SiteSettingsManager.instance;
  }

  async init(context: object): Promise<void> {
    if (this.isInitialized && this.rdbStore) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.initInternal(context)
      .then(() => {
        this.isInitialized = true;
      })
      .finally(() => {
        this.initPromise = null;
      });
    return this.initPromise;
  }

  getPermissionSetting(origin: string, permissionType: SitePermissionType): SitePermissionSetting | null {
    const key = buildSitePermissionRequestKey(origin, permissionType);
    const setting = this.permissionSettings.get(key);
    if (!setting) {
      return null;
    }
    return this.clonePermissionSetting(setting);
  }

  setPermissionSetting(
    origin: string,
    permissionType: SitePermissionType,
    decision: SitePermissionSettingDecision,
    source: SitePermissionSettingSource = 'user'
  ): SitePermissionSetting {
    const setting: SitePermissionSetting = {
      origin: normalizeSiteOrigin(origin),
      permissionType: permissionType,
      decision: decision,
      updatedAt: Date.now(),
      source: source,
    };
    const key = buildSitePermissionRequestKey(setting.origin, setting.permissionType);
    this.permissionSettings.set(key, setting);
    if (this.rdbStore && this.isInitialized) {
      this.persistPermissionSetting(setting).catch(() => {
      });
    } else {
      this.pendingSettings.set(key, this.clonePermissionSetting(setting));
    }
    return this.clonePermissionSetting(setting);
  }

  clearPermissionSetting(origin: string, permissionType: SitePermissionType): void {
    const key = buildSitePermissionRequestKey(origin, permissionType);
    this.permissionSettings.delete(key);
    this.pendingSettings.delete(key);
    if (this.rdbStore && this.isInitialized) {
      this.deletePermissionSetting(normalizeSiteOrigin(origin), permissionType).catch(() => {
      });
    } else {
      this.pendingDeletedSettings.add(key);
    }
  }

  clearSiteSettings(origin: string): void {
    const normalizedOrigin = normalizeSiteOrigin(origin);
    const keys: string[] = [];
    this.permissionSettings.forEach((_, key: string) => {
      if (key.startsWith(`${normalizedOrigin}::`)) {
        keys.push(key);
      }
    });
    keys.forEach((key: string) => this.permissionSettings.delete(key));
    this.pendingSettings.forEach((_, key: string) => {
      if (key.startsWith(`${normalizedOrigin}::`)) {
        this.pendingSettings.delete(key);
      }
    });
    if (this.rdbStore && this.isInitialized) {
      this.deleteSiteSettings(normalizedOrigin).catch(() => {
      });
    } else {
      this.pendingDeletedOrigins.add(normalizedOrigin);
    }
  }

  async clearAllSiteSettings(): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
    this.permissionSettings.clear();
    await this.deleteAllSiteSettings();
  }

  listPermissionSettings(origin?: string): SitePermissionSetting[] {
    const normalizedOrigin = origin !== undefined ? normalizeSiteOrigin(origin) : '';
    const settings: SitePermissionSetting[] = [];
    this.permissionSettings.forEach((setting: SitePermissionSetting) => {
      if (normalizedOrigin.length > 0 && setting.origin !== normalizedOrigin) {
        return;
      }
      settings.push(this.clonePermissionSetting(setting));
    });
    settings.sort((left: SitePermissionSetting, right: SitePermissionSetting) => right.updatedAt - left.updatedAt);
    return settings;
  }

  private clonePermissionSetting(setting: SitePermissionSetting): SitePermissionSetting {
    return {
      origin: setting.origin,
      permissionType: setting.permissionType,
      decision: setting.decision,
      updatedAt: setting.updatedAt,
      source: setting.source,
    };
  }

  private async initInternal(context: object): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: this.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };

      this.rdbStore = await new Promise((resolve, reject) => {
        relationalStore.getRdbStore(context as never, config, (err: BusinessError | null, store: relationalStore.RdbStore | null) => {
          if (err || !store) {
            reject(err || new Error('Failed to get site settings store'));
          } else {
            resolve(store);
          }
        });
      });

      await this.createTable();
      await this.loadPermissionSettings();
      await this.flushPendingDeletes();
      await this.flushPendingSettings();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to initialize SiteSettingsManager: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async createTable(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    const createTableSql = `
      CREATE TABLE IF NOT EXISTS ${this.TABLE_NAME} (
        origin TEXT NOT NULL,
        permissionType TEXT NOT NULL,
        decision TEXT NOT NULL,
        updatedAt INTEGER NOT NULL,
        source TEXT NOT NULL,
        PRIMARY KEY (origin, permissionType)
      );
    `;
    try {
      await this.rdbStore.executeSql(createTableSql);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create site settings table: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async loadPermissionSettings(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      const resultSet = await this.rdbStore.query(predicates);
      const settings = this.resultSetToPermissionSettings(resultSet);
      settings.forEach((setting: SitePermissionSetting) => {
        const key = buildSitePermissionRequestKey(setting.origin, setting.permissionType);
        const existing = this.permissionSettings.get(key);
        if (!existing || existing.updatedAt <= setting.updatedAt) {
          this.permissionSettings.set(key, setting);
        }
      });
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to load site permission settings: ${errorMessage}`);
    }
  }

  private async persistPermissionSetting(setting: SitePermissionSetting): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('origin', setting.origin);
      predicates.and();
      predicates.equalTo('permissionType', setting.permissionType);
      resultSet = await this.rdbStore.query(predicates, ['origin']);
      const valuesBucket: relationalStore.ValuesBucket = {
        origin: setting.origin,
        permissionType: setting.permissionType,
        decision: setting.decision,
        updatedAt: setting.updatedAt,
        source: setting.source,
      };

      if (resultSet.rowCount > 0) {
        await this.rdbStore.update(valuesBucket, predicates);
      } else {
        await this.rdbStore.insert(this.TABLE_NAME, valuesBucket);
      }
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to persist site permission setting: ${errorMessage}`);
    } finally {
      if (resultSet) {
        this.closeResultSetSafely(resultSet);
      }
    }
  }

  private async flushPendingSettings(): Promise<void> {
    if (!this.rdbStore || this.pendingSettings.size === 0) {
      return;
    }
    const pending: SitePermissionSetting[] = [];
    this.pendingSettings.forEach((setting: SitePermissionSetting) => pending.push(this.clonePermissionSetting(setting)));
    this.pendingSettings.clear();
    for (let index = 0; index < pending.length; index++) {
      await this.persistPermissionSetting(pending[index]);
    }
  }

  private async flushPendingDeletes(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    const deletedKeys: string[] = [];
    this.pendingDeletedSettings.forEach((key: string) => deletedKeys.push(key));
    this.pendingDeletedSettings.clear();
    for (let index = 0; index < deletedKeys.length; index++) {
      const separator = deletedKeys[index].indexOf('::');
      if (separator <= 0) {
        continue;
      }
      const origin = deletedKeys[index].substring(0, separator);
      const permissionType = deletedKeys[index].substring(separator + 2) as SitePermissionType;
      await this.deletePermissionSetting(origin, permissionType);
    }

    const deletedOrigins: string[] = [];
    this.pendingDeletedOrigins.forEach((origin: string) => deletedOrigins.push(origin));
    this.pendingDeletedOrigins.clear();
    for (let index = 0; index < deletedOrigins.length; index++) {
      await this.deleteSiteSettings(deletedOrigins[index]);
    }
  }

  private async deletePermissionSetting(origin: string, permissionType: SitePermissionType): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
    predicates.equalTo('origin', origin);
    predicates.and();
    predicates.equalTo('permissionType', permissionType);
    try {
      await this.rdbStore.delete(predicates);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete site permission setting: ${errorMessage}`);
    }
  }

  private async deleteSiteSettings(origin: string): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
    predicates.equalTo('origin', origin);
    try {
      await this.rdbStore.delete(predicates);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete site settings: ${errorMessage}`);
    }
  }

  private async deleteAllSiteSettings(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    try {
      await this.rdbStore.executeSql(`DELETE FROM ${this.TABLE_NAME}`);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete all site settings: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private resultSetToPermissionSettings(resultSet: relationalStore.ResultSet): SitePermissionSetting[] {
    const settings: SitePermissionSetting[] = [];

    try {
      if (resultSet.rowCount > 0) {
        resultSet.goToFirstRow();
        do {
          settings.push({
            origin: resultSet.getString(resultSet.getColumnIndex('origin')),
            permissionType: resultSet.getString(resultSet.getColumnIndex('permissionType')) as SitePermissionType,
            decision: resultSet.getString(resultSet.getColumnIndex('decision')) as SitePermissionSettingDecision,
            updatedAt: resultSet.getLong(resultSet.getColumnIndex('updatedAt')),
            source: resultSet.getString(resultSet.getColumnIndex('source')) as SitePermissionSettingSource,
          });
        } while (resultSet.goToNextRow());
      }
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to convert site permission settings resultSet: ${errorMessage}`);
    } finally {
      this.closeResultSetSafely(resultSet);
    }

    return settings;
  }

  private closeResultSetSafely(resultSet: relationalStore.ResultSet): void {
    try {
      resultSet.close();
    } catch (_) {
    }
  }
}
