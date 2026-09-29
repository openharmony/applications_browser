// AddressInputResolver：解析地址栏输入，区分 URL / 搜索词 / 空输入。

import { SearchEngineId, SearchEngineManager } from './searchEngineManager';

export type AddressInputKind = 'empty' | 'url' | 'search';

export interface AddressResolveResult {
  kind: AddressInputKind;
  rawInput: string;
  normalizedInput: string;
  targetUrl?: string;
  searchQuery?: string;
  searchEngineId?: SearchEngineId;
}

export class AddressInputResolver {
  private readonly searchEngineManager: SearchEngineManager;

  constructor(searchEngineManager?: SearchEngineManager) {
    this.searchEngineManager = searchEngineManager ?? new SearchEngineManager();
  }

  resolve(input: string): AddressResolveResult {
    const normalizedInput = input.trim();
    if (!normalizedInput) {
      return {
        kind: 'empty',
        rawInput: input,
        normalizedInput,
      };
    }

    const explicitScheme = this.getExplicitScheme(normalizedInput);
    if (explicitScheme === 'http' || explicitScheme === 'https' || this.isAllowedInternalUrl(normalizedInput)) {
      return {
        kind: 'url',
        rawInput: input,
        normalizedInput,
        targetUrl: normalizedInput,
      };
    }

    // Do not send arbitrary schemes (file/resource/custom protocol) directly to
    // ArkWeb. Treat them as search text until an explicit external-intent policy
    // is introduced.
    if (explicitScheme) {
      return this.resolveSearch(input, normalizedInput);
    }

    if (this.looksLikeUrl(normalizedInput)) {
      return {
        kind: 'url',
        rawInput: input,
        normalizedInput,
        targetUrl: `https://${normalizedInput}`,
      };
    }

    return this.resolveSearch(input, normalizedInput);
  }

  private resolveSearch(rawInput: string, normalizedInput: string): AddressResolveResult {
    const searchEngineId = this.searchEngineManager.getDefaultEngineId();
    return {
      kind: 'search',
      rawInput: rawInput,
      normalizedInput,
      searchQuery: normalizedInput,
      searchEngineId,
      targetUrl: this.searchEngineManager.buildSearchUrl(normalizedInput, searchEngineId),
    };
  }

  private getExplicitScheme(input: string): string {
    const matched = input.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\//);
    return matched && matched[1] ? matched[1].toLowerCase() : '';
  }

  private isAllowedInternalUrl(input: string): boolean {
    return /^about:blank(?:[?#].*)?$/i.test(input);
  }

  private looksLikeUrl(input: string): boolean {
    if (input.includes(' ')) {
      return false;
    }

    if (this.isLocalhost(input)) {
      return true;
    }

    if (this.isIpv4Host(input)) {
      return true;
    }

    return this.isDomainLike(input);
  }

  private isLocalhost(input: string): boolean {
    return /^localhost(:\d+)?([/?#].*)?$/i.test(input);
  }

  private isIpv4Host(input: string): boolean {
    const matched = input.match(/^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(:\d+)?([/?#].*)?$/);
    return matched !== null;
  }

  private isDomainLike(input: string): boolean {
    return /^(?:[a-zA-Z0-9-]+\.)+[a-zA-Z0-9-]{2,}(?::\d+)?(?:[/?#].*)?$/.test(input);
  }
}
