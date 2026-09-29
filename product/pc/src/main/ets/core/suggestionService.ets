// SuggestionService：聚合地址栏联想所需的多个数据源。

import { BookmarkItem } from './bookmarkManager';
import { HistoryItem } from './historyManager';
import { AddressResolveResult, AddressInputResolver } from './addressInputResolver';
import { AddressSuggestion, AddressSuggestionContext } from './addressSuggestionTypes';
import { Tab } from './types';
import { normalizeHttpUrlForStorage } from './urlNormalizer';

export class SuggestionService {
  private readonly addressInputResolver: AddressInputResolver;

  constructor(addressInputResolver?: AddressInputResolver) {
    this.addressInputResolver = addressInputResolver ?? new AddressInputResolver();
  }

  buildSuggestions(input: string, bookmarkItems: BookmarkItem[], historyItems: HistoryItem[], context: AddressSuggestionContext): AddressSuggestion[] {
    const trimmedInput = input.trim();
    if (!trimmedInput) {
      return [];
    }

    const suggestions: AddressSuggestion[] = [];
    const resolved = this.addressInputResolver.resolve(trimmedInput);
    this.pushPrimarySuggestion(suggestions, resolved);
    this.pushBookmarkSuggestions(suggestions, trimmedInput, bookmarkItems);
    this.pushTabSuggestions(suggestions, trimmedInput, context.tabs);
    this.pushHistorySuggestions(suggestions, trimmedInput, historyItems);
    this.applyMembershipIcons(suggestions, bookmarkItems, historyItems);
    return this.limitSuggestions(this.deduplicateSuggestions(suggestions), context.limit);
  }

  /**
   * 去重会保留先 push 的行：直接输入一个已收藏/已访问的网址时，幸存的是
   * primary 'url' 行而不是 bookmark/history 行。这里按归一化 URL 补判归属，
   * 让这类行仍能显示收藏夹/历史记录图标。收藏优先于历史，与去重时书签行
   * 先于历史行的既定顺序保持一致。
   */
  private applyMembershipIcons(suggestions: AddressSuggestion[], bookmarkItems: BookmarkItem[], historyItems: HistoryItem[]): void {
    const bookmarkUrls: Set<string> = new Set();
    bookmarkItems.forEach((bookmark: BookmarkItem): void => {
      const key = normalizeHttpUrlForStorage(bookmark.url);
      if (key) {
        bookmarkUrls.add(key);
      }
    });
    const historyUrls: Set<string> = new Set();
    historyItems.forEach((item: HistoryItem): void => {
      const key = normalizeHttpUrlForStorage(item.url);
      if (key) {
        historyUrls.add(key);
      }
    });

    suggestions.forEach((suggestion: AddressSuggestion): void => {
      if (suggestion.type !== 'url' && suggestion.type !== 'tab') {
        return;
      }
      const key = normalizeHttpUrlForStorage(suggestion.targetUrl);
      if (!key) {
        return;
      }
      if (bookmarkUrls.has(key)) {
        suggestion.iconKind = 'bookmark';
      } else if (historyUrls.has(key)) {
        suggestion.iconKind = 'history';
      }
    });
  }

  private pushPrimarySuggestion(suggestions: AddressSuggestion[], resolved: AddressResolveResult): void {
    if (!resolved.targetUrl) {
      return;
    }

    if (resolved.kind === 'search') {
      const searchSuggestion: AddressSuggestion = {
        id: `search:${resolved.targetUrl}`,
        type: 'search',
        title: `搜索 “${resolved.searchQuery ?? resolved.normalizedInput}”`,
        subtitle: resolved.targetUrl,
        targetUrl: resolved.targetUrl,
      };
      suggestions.push(searchSuggestion);
      return;
    }

    if (resolved.kind === 'url') {
      const urlSuggestion: AddressSuggestion = {
        id: `url:${resolved.targetUrl}`,
        type: 'url',
        title: `访问 ${resolved.normalizedInput}`,
        subtitle: resolved.targetUrl,
        targetUrl: resolved.targetUrl,
      };
      suggestions.push(urlSuggestion);
    }
  }

  private pushTabSuggestions(suggestions: AddressSuggestion[], input: string, tabs: Tab[]): void {
    const keyword = input.toLowerCase();
    tabs.forEach((tab: Tab) => {
      if (!tab.url || tab.loadState === 'home') {
        return;
      }

      const title = tab.title ? tab.title : tab.url;
      const titleMatched = title.toLowerCase().includes(keyword);
      const urlMatched = tab.url.toLowerCase().includes(keyword);
      if (!titleMatched && !urlMatched) {
        return;
      }

      const suggestion: AddressSuggestion = {
        id: `tab:${String(tab.id)}`,
        type: 'tab',
        title: title,
        subtitle: tab.url,
        targetUrl: tab.url,
        targetTabId: String(tab.id),
      };
      if (tab.faviconUrl) {
        suggestion.iconUrl = tab.faviconUrl;
      }
      suggestions.push(suggestion);
    });
  }

  private pushBookmarkSuggestions(suggestions: AddressSuggestion[], input: string, bookmarkItems: BookmarkItem[]): void {
    const matchedBookmarks = bookmarkItems
      .filter((bookmark: BookmarkItem): boolean => this.matchesInput(input, bookmark.title, bookmark.url))
      .sort((left: BookmarkItem, right: BookmarkItem): number => {
        return this.getMatchScore(input, right.title, right.url) - this.getMatchScore(input, left.title, left.url);
      });

    matchedBookmarks.forEach((bookmark: BookmarkItem) => {
      const suggestion: AddressSuggestion = {
        id: `bookmark:${bookmark.id}`,
        type: 'bookmark',
        title: bookmark.title ? bookmark.title : bookmark.url,
        subtitle: bookmark.url,
        targetUrl: bookmark.url,
      };
      suggestions.push(suggestion);
    });
  }

  private pushHistorySuggestions(suggestions: AddressSuggestion[], input: string, historyItems: HistoryItem[]): void {
    const matchedHistoryItems = historyItems
      .filter((item: HistoryItem): boolean => this.matchesInput(input, item.title, item.url))
      .sort((left: HistoryItem, right: HistoryItem): number => {
        return this.getMatchScore(input, right.title, right.url) - this.getMatchScore(input, left.title, left.url);
      });

    matchedHistoryItems.forEach((item: HistoryItem) => {
      const suggestion: AddressSuggestion = {
        id: `history:${item.id ?? item.url}`,
        type: 'history',
        title: item.title ? item.title : item.url,
        subtitle: item.url,
        targetUrl: item.url,
      };
      suggestions.push(suggestion);
    });
  }

  private matchesInput(input: string, title: string, url: string): boolean {
    return this.getMatchScore(input, title, url) > 0;
  }

  private getMatchScore(input: string, title: string, url: string): number {
    const keyword = input.trim().toLowerCase();
    if (!keyword) {
      return 0;
    }

    const normalizedTitle = title.toLowerCase();
    const normalizedUrl = url.toLowerCase();
    if (normalizedUrl === keyword || normalizedTitle === keyword) {
      return 100;
    }
    if (normalizedUrl.startsWith(keyword)) {
      return 80;
    }
    if (normalizedTitle.startsWith(keyword)) {
      return 70;
    }
    if (normalizedUrl.includes(keyword)) {
      return 50;
    }
    if (normalizedTitle.includes(keyword)) {
      return 40;
    }
    return 0;
  }

  private deduplicateSuggestions(suggestions: AddressSuggestion[]): AddressSuggestion[] {
    const result: AddressSuggestion[] = [];
    const seen: Set<string> = new Set();
    suggestions.forEach((suggestion: AddressSuggestion) => {
      const key = normalizeHttpUrlForStorage(suggestion.targetUrl);
      if (seen.has(key)) {
        return;
      }
      seen.add(key);
      result.push(suggestion);
    });
    return result;
  }

  private limitSuggestions(suggestions: AddressSuggestion[], limit: number): AddressSuggestion[] {
    if (limit <= 0 || suggestions.length <= limit) {
      return suggestions;
    }
    return suggestions.slice(0, limit);
  }
}
