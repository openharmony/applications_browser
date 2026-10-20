// SearchEngineConfig：PC 产品默认搜索引擎配置。
// 搜索引擎地址保存在 rawfile/search_engines.json，运行时注入管理器。

import { util } from '@kit.ArkTS';

export interface SearchEngineConfigEntry {
  id: string;
  name: string;
  searchUrlTemplate: string;
}

export interface SearchEngineConfig {
  builtInEngines: SearchEngineConfigEntry[];
  fallbackEngineId: string;
}

interface RawResourceManagerLike {
  getRawFileContent(path: string): Promise<Uint8Array>;
}

interface HostContextLike {
  resourceManager?: RawResourceManagerLike;
}

export class SearchEngineConfigProvider {
  private static readonly CONFIG_FILE: string = 'search_engines.json';
  private static config: SearchEngineConfig = {
    builtInEngines: [],
    fallbackEngineId: '',
  };
  private static loadPromise: Promise<void> | null = null;

  static getDefault(): SearchEngineConfig {
    return {
      builtInEngines: SearchEngineConfigProvider.config.builtInEngines.map(
        (engine: SearchEngineConfigEntry): SearchEngineConfigEntry => ({
          id: engine.id,
          name: engine.name,
          searchUrlTemplate: engine.searchUrlTemplate,
        })
      ),
      fallbackEngineId: SearchEngineConfigProvider.config.fallbackEngineId,
    };
  }

  static async load(context: object): Promise<void> {
    if (SearchEngineConfigProvider.config.builtInEngines.length > 0) {
      return;
    }
    if (SearchEngineConfigProvider.loadPromise) {
      return SearchEngineConfigProvider.loadPromise;
    }
    SearchEngineConfigProvider.loadPromise = SearchEngineConfigProvider.readConfig(context)
      .finally(() => {
        SearchEngineConfigProvider.loadPromise = null;
      });
    return SearchEngineConfigProvider.loadPromise;
  }

  private static async readConfig(context: object): Promise<void> {
    const hostContext = context as HostContextLike;
    if (!hostContext.resourceManager) {
      throw new Error('search_engine_config_resource_manager_missing');
    }
    const data = await hostContext.resourceManager.getRawFileContent(SearchEngineConfigProvider.CONFIG_FILE);
    const parsed = JSON.parse(SearchEngineConfigProvider.decodeUtf8(data)) as SearchEngineConfig;
    const entries = Array.isArray(parsed.builtInEngines) ? parsed.builtInEngines : [];
    const validEntries: SearchEngineConfigEntry[] = entries.filter((entry: SearchEngineConfigEntry) => {
      return typeof entry.id === 'string' && entry.id.trim().length > 0 &&
        typeof entry.name === 'string' && entry.name.trim().length > 0 &&
        typeof entry.searchUrlTemplate === 'string' && entry.searchUrlTemplate.trim().length > 0;
    }).map((entry: SearchEngineConfigEntry): SearchEngineConfigEntry => ({
      id: entry.id.trim(),
      name: entry.name.trim(),
      searchUrlTemplate: entry.searchUrlTemplate.trim(),
    }));
    if (validEntries.length === 0) {
      throw new Error('search_engine_config_empty');
    }
    const configuredFallback = typeof parsed.fallbackEngineId === 'string' ? parsed.fallbackEngineId.trim() : '';
    const fallbackEngineId = validEntries.some((entry: SearchEngineConfigEntry) => entry.id === configuredFallback) ?
      configuredFallback : validEntries[0].id;
    SearchEngineConfigProvider.config = {
      builtInEngines: validEntries,
      fallbackEngineId: fallbackEngineId,
    };
  }

  // rawfile 内容按 UTF-8 解码：json 内含中文搜索引擎名（如“百度”），
  // 逐字节 String.fromCharCode 会把多字节 UTF-8 序列解码成乱码。
  private static decodeUtf8(data: Uint8Array): string {
    return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(data);
  }
}
