// SearchEngineManager：管理搜索引擎定义与搜索 URL 生成。

import { CustomSearchEngineSetting, SettingsManager } from './settingsManager';

export type SearchEngineId = string;

export interface SearchEngineDefinition {
  id: SearchEngineId;
  name: string;
  searchUrlTemplate: string;
  builtIn: boolean;
}

export class SearchEngineManager {
  private readonly settingsManager: SettingsManager;
  private readonly builtInEngines: Map<SearchEngineId, SearchEngineDefinition> = new Map();

  constructor(settingsManager?: SettingsManager) {
    this.settingsManager = settingsManager ?? SettingsManager.getInstance();
    this.registerBuiltInEngines();
  }

  getSupportedEngines(): SearchEngineDefinition[] {
    const engines: SearchEngineDefinition[] = [
      this.getEngineDefinition('baidu'),
      this.getEngineDefinition('so360'),
    ];
    this.settingsManager.getSettings().customSearchEngines.forEach((engine: CustomSearchEngineSetting) => {
      engines.push(this.toDefinition(engine));
    });
    return engines;
  }

  getDefaultEngineId(): SearchEngineId {
    const engineId = this.settingsManager.getSettings().defaultSearchEngineId;
    if (this.hasEngine(engineId)) {
      return engineId;
    }
    return 'baidu';
  }

  getDefaultEngine(): SearchEngineDefinition {
    return this.getEngineDefinition(this.getDefaultEngineId());
  }

  setDefaultEngine(engineId: SearchEngineId): void {
    if (!this.hasEngine(engineId)) {
      throw new Error('search_engine_not_found');
    }
    this.settingsManager.updateSettings({ defaultSearchEngineId: engineId });
  }

  getEngineDefinition(engineId: SearchEngineId): SearchEngineDefinition {
    const builtIn = this.builtInEngines.get(engineId);
    if (builtIn) {
      return builtIn;
    }
    const customEngine = this.settingsManager.getSettings().customSearchEngines
      .find((engine: CustomSearchEngineSetting) => engine.id === engineId);
    return customEngine ? this.toDefinition(customEngine) :
      this.builtInEngines.get('baidu') as SearchEngineDefinition;
  }

  hasEngine(engineId: SearchEngineId): boolean {
    if (this.builtInEngines.has(engineId)) {
      return true;
    }
    return this.settingsManager.getSettings().customSearchEngines
      .some((engine: CustomSearchEngineSetting) => engine.id === engineId);
  }

  addCustomEngine(name: string, searchUrlTemplate: string): SearchEngineDefinition {
    const normalizedName = name.trim();
    if (!normalizedName) {
      throw new Error('search_engine_name_required');
    }
    if (normalizedName.length > 40) {
      throw new Error('search_engine_name_too_long');
    }
    const normalizedTemplate = this.normalizeSearchUrlTemplate(searchUrlTemplate);
    const settings = this.settingsManager.getSettings();
    const duplicate = this.getSupportedEngines().some((engine: SearchEngineDefinition) => {
      return engine.name.toLowerCase() === normalizedName.toLowerCase() ||
        engine.searchUrlTemplate === normalizedTemplate;
    });
    if (duplicate) {
      throw new Error('search_engine_already_exists');
    }
    const customEngine: CustomSearchEngineSetting = {
      id: this.createCustomEngineId(settings.customSearchEngines),
      name: normalizedName,
      searchUrlTemplate: normalizedTemplate,
    };
    const nextEngines = settings.customSearchEngines.concat([customEngine]);
    this.settingsManager.updateSettings({ customSearchEngines: nextEngines });
    return this.toDefinition(customEngine);
  }

  deleteCustomEngine(engineId: SearchEngineId): boolean {
    if (this.builtInEngines.has(engineId)) {
      return false;
    }
    const settings = this.settingsManager.getSettings();
    const nextEngines = settings.customSearchEngines
      .filter((engine: CustomSearchEngineSetting) => engine.id !== engineId);
    if (nextEngines.length === settings.customSearchEngines.length) {
      return false;
    }
    this.settingsManager.updateSettings({
      customSearchEngines: nextEngines,
      defaultSearchEngineId: settings.defaultSearchEngineId === engineId ? 'baidu' : settings.defaultSearchEngineId,
    });
    return true;
  }

  buildSearchUrl(query: string, engineId?: SearchEngineId): string {
    const trimmed = query.trim();
    const effectiveEngineId = engineId ?? this.getDefaultEngineId();
    const engine = this.getEngineDefinition(effectiveEngineId);
    const encodedQuery = encodeURIComponent(trimmed);
    return engine.searchUrlTemplate.split('{query}').join(encodedQuery);
  }

  private registerBuiltInEngines(): void {
    this.builtInEngines.set('baidu', {
      id: 'baidu',
      name: '百度',
      searchUrlTemplate: 'https://www.baidu.com/s?wd={query}',
      builtIn: true,
    });
    this.builtInEngines.set('so360', {
      id: 'so360',
      name: '360 搜索',
      searchUrlTemplate: 'https://www.so.com/s?q={query}',
      builtIn: true,
    });
  }

  private normalizeSearchUrlTemplate(value: string): string {
    const normalized = value.trim().split('%s').join('{query}');
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      throw new Error('search_engine_url_must_be_http');
    }
    if (!normalized.includes('{query}')) {
      throw new Error('search_engine_url_requires_placeholder');
    }
    return normalized;
  }

  private createCustomEngineId(existing: CustomSearchEngineSetting[]): string {
    let suffix = Date.now();
    let candidate = `custom_${suffix}`;
    while (existing.some((engine: CustomSearchEngineSetting) => engine.id === candidate)) {
      suffix += 1;
      candidate = `custom_${suffix}`;
    }
    return candidate;
  }

  private toDefinition(engine: CustomSearchEngineSetting): SearchEngineDefinition {
    return {
      id: engine.id,
      name: engine.name,
      searchUrlTemplate: engine.searchUrlTemplate,
      builtIn: false,
    };
  }
}
