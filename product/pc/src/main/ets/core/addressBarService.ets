// AddressBarService：负责地址栏输入解析与联想建议的编排。

import { BookmarkItem, BookmarkManager } from './bookmarkManager';
import { HistoryItem, HistoryManager } from './historyManager';
import { SuggestionService } from './suggestionService';
import { AddressSuggestion } from './addressSuggestionTypes';
import { Tab } from './types';
import { normalizeHttpUrlForStorage } from './urlNormalizer';

export class AddressBarService {
  private readonly bookmarkManager: BookmarkManager = BookmarkManager.getInstance();
  private readonly historyManager: HistoryManager = HistoryManager.getInstance();
  private readonly suggestionService: SuggestionService = new SuggestionService();

  async querySuggestions(
    input: string,
    tabs: Tab[],
    limit: number = 6,
    isPrivate: boolean = false
  ): Promise<AddressSuggestion[]> {
    const trimmedInput = input.trim();
    if (!trimmedInput) {
      return [];
    }

    const bookmarkPromise = this.loadBookmarkSuggestions(trimmedInput, limit);
    const historyPromise = isPrivate
      ? Promise.resolve([] as HistoryItem[])
      : this.loadHistorySuggestions(trimmedInput, limit);
    const bookmarkItems = await bookmarkPromise;
    const historyItems = await historyPromise;
    return this.suggestionService.buildSuggestions(trimmedInput, bookmarkItems, historyItems, {
      tabs: tabs,
      limit: limit,
    });
  }

  async recordVisit(url: string, title?: string, isPrivate: boolean = false): Promise<void> {
    if (isPrivate || !this.shouldRecordHistory(url)) {
      return;
    }

    const normalizedUrl = normalizeHttpUrlForStorage(url);
    const historyItem: HistoryItem = {
      url: normalizedUrl,
      title: title && title.trim().length > 0 ? title : normalizedUrl,
      visitTime: Date.now(),
    };
    try {
      await this.historyManager.addHistory(historyItem);
    } catch (_) {
    }
  }

  private async loadHistorySuggestions(input: string, limit: number): Promise<HistoryItem[]> {
    try {
      return await this.historyManager.searchHistory(input, limit);
    } catch (_) {
      return [];
    }
  }

  private async loadBookmarkSuggestions(input: string, limit: number): Promise<BookmarkItem[]> {
    const keyword = input.trim().toLowerCase();
    if (!keyword) {
      return [];
    }

    try {
      const bookmarkItems = await this.bookmarkManager.searchBookmarks(keyword, limit * 2);
      return bookmarkItems
        .filter((bookmark: BookmarkItem): boolean => !bookmark.isFolder)
        .slice(0, limit);
    } catch (_) {
      return [];
    }
  }

  private shouldRecordHistory(url: string): boolean {
    const normalizedUrl = url.trim().toLowerCase();
    if (!normalizedUrl) {
      return false;
    }
    if (normalizedUrl === 'about:blank') {
      return false;
    }
    return normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://');
  }

}
