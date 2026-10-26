import { AppRoute, AppRouter } from '../../core/appRouter';
import { DownloadTask, DownloadTaskFilter } from '../../core/downloadTypes';
import { DownloadItem } from '../components/DownloadItem';
import { DownloadsPageViewState, DownloadsViewModel } from '../viewmodels/DownloadsViewModel';

@Component
export struct DownloadsPage {
  @Link route: AppRoute;
  @Link pendingUrl: string;

  private viewModel: DownloadsViewModel = new DownloadsViewModel();
  private downloadsListener: (state: DownloadsPageViewState) => void = (state: DownloadsPageViewState) => {
    this.applyState(state);
  };

  @State private viewState: DownloadsPageViewState = {
    downloads: [],
    filter: 'all',
    keyword: '',
    filteredCount: 0,
    totalCount: 0,
    activeCount: 0,
    completedCount: 0,
    failedCount: 0,
    finishedCount: 0,
  };

  @State private keyword: string = '';
  @State private isClearingFinished: boolean = false;
  @State private actionMessage: string = '';
  @State private actionMessageIsError: boolean = false;

  aboutToAppear(): void {
    this.viewState = this.viewModel.markIndicatorSeen();
    this.keyword = this.viewState.keyword;
    this.viewModel.addListener(this.downloadsListener);
  }

  aboutToDisappear(): void {
    this.viewModel.removeListener(this.downloadsListener);
  }

  private applyState(state: DownloadsPageViewState): void {
    this.viewState = state;
    this.keyword = state.keyword;
  }

  private setFilter(filter: DownloadTaskFilter): void {
    this.applyState(this.viewModel.setFilter(filter));
  }

  private setKeyword(keyword: string): void {
    this.applyState(this.viewModel.setKeyword(keyword));
  }

  private openDownloadTarget(id: string): void {
    const targetUrl = this.viewModel.getOpenTargetUrl(id);
    if (targetUrl.length === 0) {
      return;
    }
    this.pendingUrl = targetUrl;
    this.route = AppRouter.browser;
  }

  private async clearFinishedDownloads(): Promise<void> {
    if (this.isClearingFinished) {
      return;
    }
    this.isClearingFinished = true;
    this.actionMessage = '';
    this.actionMessageIsError = false;
    try {
      const result = await this.viewModel.clearFinishedAsync();
      this.applyState(this.viewModel.getViewState());
      if (!result.success) {
        this.actionMessage = result.errorMessage || '清除已结束任务失败，请重试';
        this.actionMessageIsError = true;
      }
    } finally {
      this.isClearingFinished = false;
      this.applyState(this.viewModel.getViewState());
    }
  }

  private async removeDownload(id: string): Promise<void> {
    const result = await this.viewModel.removeAsync(id);
    this.applyState(this.viewModel.getViewState());
    if (!result.success) {
      this.actionMessage = result.errorMessage || '删除下载记录失败，请重试';
      this.actionMessageIsError = true;
    }
  }

  private isFilterActive(filter: DownloadTaskFilter): boolean {
    return this.viewState.filter === filter;
  }

  private getFilterLabel(filter: DownloadTaskFilter): string {
    if (filter === 'active') {
      return '进行中';
    }
    if (filter === 'completed') {
      return '已完成';
    }
    if (filter === 'failed') {
      return '失败';
    }
    return '全部';
  }

  private getEmptyTitle(): string {
    if (this.viewState.totalCount === 0) {
      return '暂无下载任务';
    }
    if (this.viewState.keyword.trim().length > 0) {
      return '没有匹配的下载任务';
    }
    return `${this.getFilterLabel(this.viewState.filter)}下载为空`;
  }

  private getEmptyDescription(): string {
    if (this.viewState.totalCount === 0) {
      return '后续可在这里展示来自 Web 的真实下载任务。';
    }
    if (this.viewState.keyword.trim().length > 0) {
      return '换一个文件名、来源页面或下载地址关键词再试。';
    }
    return '切换到其他筛选条件查看已有下载任务。';
  }

  @Builder
  private FilterChip(filter: DownloadTaskFilter, label: string, count: number) {
    Button(`${label} ${count}`)
      .fontSize(12)
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.isFilterActive(filter) ? '#dbeafe' : '#f3f4f6')
      .fontColor(this.isFilterActive(filter) ? '#2563eb' : '#4b5563')
      .borderRadius(16)
      .onClick(() => this.setFilter(filter));
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button('返回')
          .height(34)
          .backgroundColor('#f3f4f6')
          .fontColor('#374151')
          .borderRadius(17)
          .onClick(() => {
            this.route = AppRouter.browser;
          });

        Text(`下载 ${this.viewState.totalCount}`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .layoutWeight(1);

        if (this.viewState.finishedCount > 0) {
          Button(this.isClearingFinished ? '正在清除...' : '清除已结束')
            .height(34)
            .fontSize(13)
            .backgroundColor('#f3f4f6')
            .fontColor('#374151')
            .borderRadius(17)
            .enabled(!this.isClearingFinished)
            .opacity(this.isClearingFinished ? 0.55 : 1)
            .onClick(() => {
              this.clearFinishedDownloads();
            });
        }
      }
      .width('100%');

      if (this.actionMessage.length > 0) {
        Text(this.actionMessage)
          .fontSize(12)
          .fontColor(this.actionMessageIsError ? '#dc2626' : '#15803d')
          .width('100%');
      }

      TextInput({ text: this.keyword, placeholder: '搜索下载任务' })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor('#ffffff')
        .borderRadius(20)
        .padding({ left: 14, right: 14 })
        .border({ width: 1, color: '#dbe3f0' })
        .onChange((value: string) => this.setKeyword(value));

      Row({ space: 8 }) {
        this.FilterChip('all', '全部', this.viewState.totalCount);
        this.FilterChip('active', '进行中', this.viewState.activeCount);
        this.FilterChip('completed', '已完成', this.viewState.completedCount);
        this.FilterChip('failed', '失败', this.viewState.failedCount);
      }
      .width('100%');

      if (this.viewState.totalCount > 0) {
        Text(`当前显示 ${this.viewState.filteredCount} 项，共 ${this.viewState.totalCount} 项`)
          .fontSize(12)
          .fontColor('#6b7280')
          .width('100%');
      }

      if (this.viewState.downloads.length === 0) {
        Column({ space: 8 }) {
          Text(this.getEmptyTitle())
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text(this.getEmptyDescription())
            .fontSize(13)
            .fontColor('#6b7280');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        List({ space: 10 }) {
          ForEach(this.viewState.downloads, (task: DownloadTask) => {
            ListItem() {
              DownloadItem({
                task: task,
                onCancel: (id: string) => this.applyState(this.viewModel.cancel(id)),
                onPause: (id: string) => this.applyState(this.viewModel.pause(id)),
                onResume: (id: string) => this.applyState(this.viewModel.resume(id)),
                onRetry: (id: string) => this.applyState(this.viewModel.retry(id)),
                onRemove: (id: string) => {
                  this.removeDownload(id);
                },
                onOpenTarget: (id: string) => this.openDownloadTarget(id),
              });
            }
          }, (task: DownloadTask) => task.id);
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0, color: '#00000000' });
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#f7f8fa');
  }
}
