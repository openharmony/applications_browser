// HistoryViewModel：HistoryPage 的数据与操作封装。

import { HistoryItem, HistoryManager } from '../../core/historyManager';

export interface HistoryPageViewState {
  histories: HistoryItem[];
  listEntries: HistoryListEntry[];
  keyword: string;
  totalCount: number;
  isLoading: boolean;
  errorMessage: string;
}

export type HistoryListEntryType = 'section' | 'history';

export interface HistoryListEntry {
  id: string;
  type: HistoryListEntryType;
  label: string;
  history?: HistoryItem;
}

export interface HistoryDataSource {
  queryAllHistory(): Promise<HistoryItem[]>;
  searchHistory(keyword: string, limit?: number): Promise<HistoryItem[]>;
  deleteHistoryById(id: number): Promise<void>;
  deleteHistoryByUrl(url: string): Promise<void>;
  clearAllHistory(): Promise<void>;
}

export class HistoryViewModel {
  private readonly historyManager: HistoryDataSource;
  private readonly nowProvider: () => number;
  private keyword: string = '';
  private histories: HistoryItem[] = [];
  private totalCount: number = 0;
  private isLoading: boolean = false;
  private errorMessage: string = '';

  constructor(historyManager?: HistoryDataSource, nowProvider?: () => number) {
    this.historyManager = historyManager ?? HistoryManager.getInstance();
    this.nowProvider = nowProvider ?? (() => Date.now());
  }

  getInitialState(): HistoryPageViewState {
    return this.getViewState();
  }

  getViewState(): HistoryPageViewState {
    return {
      histories: this.histories,
      listEntries: this.buildListEntries(this.histories),
      keyword: this.keyword,
      totalCount: this.totalCount,
      isLoading: this.isLoading,
      errorMessage: this.errorMessage,
    };
  }

  async load(): Promise<HistoryPageViewState> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const allHistories = await this.historyManager.queryAllHistory();
      const keyword = this.keyword.trim();
      this.totalCount = allHistories.length;
      this.histories = keyword.length > 0 ? await this.historyManager.searchHistory(keyword) : allHistories;
    } catch (error) {
      this.histories = [];
      this.totalCount = 0;
      this.errorMessage = this.getErrorMessage(error);
    } finally {
      this.isLoading = false;
    }

    return this.getViewState();
  }

  async setKeyword(keyword: string): Promise<HistoryPageViewState> {
    this.keyword = keyword;
    return this.load();
  }

  async remove(item: HistoryItem): Promise<HistoryPageViewState> {
    if (item.id !== undefined && item.id !== null) {
      await this.historyManager.deleteHistoryById(item.id);
    } else {
      await this.historyManager.deleteHistoryByUrl(item.url);
    }
    return this.load();
  }

  async clear(): Promise<HistoryPageViewState> {
    await this.historyManager.clearAllHistory();
    return this.load();
  }

  private getErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '历史记录加载失败';
  }

  private buildListEntries(histories: HistoryItem[]): HistoryListEntry[] {
    const entries: HistoryListEntry[] = [];
    let lastSectionId = '';

    histories.forEach((history: HistoryItem) => {
      const section = this.resolveSection(history.visitTime);
      if (section.id !== lastSectionId) {
        entries.push({
          id: `section_${section.id}`,
          type: 'section',
          label: section.label,
        });
        lastSectionId = section.id;
      }

      entries.push({
        id: this.resolveHistoryEntryId(history),
        type: 'history',
        label: '',
        history: history,
      });
    });

    return entries;
  }

  private resolveSection(visitTime: number): HistorySectionInfo {
    const currentDate = new Date(this.nowProvider());
    const visitDate = new Date(visitTime);
    const todayStart = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate()).getTime();
    const visitStart = new Date(visitDate.getFullYear(), visitDate.getMonth(), visitDate.getDate()).getTime();
    const dayDiff = Math.floor((todayStart - visitStart) / 86400000);

    if (dayDiff === 0) {
      return {
        id: 'today',
        label: '今天',
      };
    }
    if (dayDiff === 1) {
      return {
        id: 'yesterday',
        label: '昨天',
      };
    }
    return {
      id: 'earlier',
      label: '更早',
    };
  }

  private resolveHistoryEntryId(history: HistoryItem): string {
    if (history.id !== undefined && history.id !== null) {
      return `history_${history.id}`;
    }
    return `history_${history.url}_${history.visitTime}`;
  }
}

interface HistorySectionInfo {
  id: string;
  label: string;
}
