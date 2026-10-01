import { DownloadManager, DownloadMutationResult } from '../../core/downloadManager';
import { DownloadTask, DownloadTaskFilter, DownloadTaskQuery, isActiveDownloadState } from '../../core/downloadTypes';

export interface DownloadsPageViewState {
  downloads: DownloadTask[];
  filter: DownloadTaskFilter;
  keyword: string;
  filteredCount: number;
  totalCount: number;
  activeCount: number;
  completedCount: number;
  failedCount: number;
  finishedCount: number;
}

export class DownloadsViewModel {
  private readonly downloadManager: DownloadManager;
  private filter: DownloadTaskFilter = 'all';
  private keyword: string = '';
  private readonly listenerMap: Map<
    (state: DownloadsPageViewState) => void,
    (downloads: DownloadTask[]) => void
  > = new Map();

  constructor(downloadManager?: DownloadManager) {
    this.downloadManager = downloadManager ?? DownloadManager.getInstance();
  }

  getInitialState(): DownloadsPageViewState {
    return this.getViewState();
  }

  markIndicatorSeen(): DownloadsPageViewState {
    this.downloadManager.markIndicatorNoticeSeen();
    return this.getViewState();
  }

  getViewState(): DownloadsPageViewState {
    const allDownloads = this.downloadManager.getDownloads();
    const filteredDownloads = this.downloadManager.getDownloads(this.getQuery());
    return {
      downloads: filteredDownloads,
      filter: this.filter,
      keyword: this.keyword,
      filteredCount: filteredDownloads.length,
      totalCount: allDownloads.length,
      activeCount: allDownloads.filter((task: DownloadTask) => isActiveDownloadState(task.state)).length,
      completedCount: allDownloads.filter(task => task.state === 'completed').length,
      failedCount: allDownloads.filter(task => task.state === 'failed').length,
      finishedCount: allDownloads.filter((task: DownloadTask) => !isActiveDownloadState(task.state)).length,
    };
  }

  setFilter(filter: DownloadTaskFilter): DownloadsPageViewState {
    this.filter = filter;
    return this.getViewState();
  }

  setKeyword(keyword: string): DownloadsPageViewState {
    this.keyword = keyword;
    return this.getViewState();
  }

  cancel(id: string): DownloadsPageViewState {
    this.downloadManager.cancelManagedDownload(id);
    return this.getViewState();
  }

  pause(id: string): DownloadsPageViewState {
    this.downloadManager.pauseManagedDownload(id);
    return this.getViewState();
  }

  resume(id: string): DownloadsPageViewState {
    this.downloadManager.resumeManagedDownload(id);
    return this.getViewState();
  }

  retry(id: string): DownloadsPageViewState {
    this.downloadManager.retryManagedDownload(id);
    return this.getViewState();
  }

  remove(id: string): DownloadsPageViewState {
    this.downloadManager.removeDownload(id);
    return this.getViewState();
  }

  clearFinished(): DownloadsPageViewState {
    this.downloadManager.clearFinishedDownloads(false);
    return this.getViewState();
  }

  async clearFinishedAsync(): Promise<DownloadMutationResult> {
    return await this.downloadManager.clearFinishedDownloadsAsync(false);
  }

  async removeAsync(id: string): Promise<DownloadMutationResult> {
    return await this.downloadManager.removeDownloadAsync(id);
  }

  getOpenTargetUrl(id: string): string {
    const task = this.downloadManager.getDownload(id);
    if (!task) {
      return '';
    }

    const pageUrl = task.pageUrl ? task.pageUrl.trim() : '';
    if (pageUrl.length > 0) {
      return pageUrl;
    }
    return task.sourceUrl.trim();
  }

  getDownload(id: string): DownloadTask | null {
    return this.downloadManager.getDownload(id);
  }

  addListener(listener: (state: DownloadsPageViewState) => void): void {
    const managerListener = (_: DownloadTask[]) => {
      listener(this.getViewState());
    };
    this.listenerMap.set(listener, managerListener);
    this.downloadManager.addListener(managerListener);
  }

  removeListener(listener: (state: DownloadsPageViewState) => void): void {
    const managerListener = this.listenerMap.get(listener);
    if (!managerListener) {
      return;
    }
    this.listenerMap.delete(listener);
    this.downloadManager.removeListener(managerListener);
  }

  private getQuery(): DownloadTaskQuery {
    return {
      filter: this.filter,
      keyword: this.keyword,
    };
  }
}
