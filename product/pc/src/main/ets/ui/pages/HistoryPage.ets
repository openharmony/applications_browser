// HistoryPage：浏览历史展示页（含搜索与清理）。

import { AppRoute, AppRouter } from '../../core/appRouter';
import { HistoryItem } from '../../core/historyManager';
import { HistoryListEntry, HistoryPageViewState, HistoryViewModel } from '../viewmodels/HistoryViewModel';

@Component
export struct HistoryPage {
  @Link route: AppRoute;
  @Link pendingUrl: string;

  private viewModel: HistoryViewModel = new HistoryViewModel();

  @State private viewState: HistoryPageViewState = {
    histories: [],
    listEntries: [],
    keyword: '',
    totalCount: 0,
    isLoading: false,
    errorMessage: '',
  };

  @State private keyword: string = '';

  aboutToAppear(): void {
    this.applyState(this.viewModel.getInitialState());
    this.reloadHistory();
  }

  private applyState(state: HistoryPageViewState): void {
    this.viewState = state;
    this.keyword = state.keyword;
  }

  private reloadHistory(): void {
    this.applyState({
      histories: this.viewState.histories,
      listEntries: this.viewState.listEntries,
      keyword: this.viewState.keyword,
      totalCount: this.viewState.totalCount,
      isLoading: true,
      errorMessage: '',
    });
    this.viewModel.load()
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private setKeyword(keyword: string): void {
    this.keyword = keyword;
    this.applyState({
      histories: this.viewState.histories,
      listEntries: this.viewState.listEntries,
      keyword: keyword,
      totalCount: this.viewState.totalCount,
      isLoading: true,
      errorMessage: '',
    });
    this.viewModel.setKeyword(keyword)
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private openHistory(url: string): void {
    this.pendingUrl = url;
    this.route = AppRouter.Browser;
  }

  private removeHistory(item: HistoryItem): void {
    this.applyState({
      histories: this.viewState.histories,
      listEntries: this.viewState.listEntries,
      keyword: this.viewState.keyword,
      totalCount: this.viewState.totalCount,
      isLoading: true,
      errorMessage: '',
    });
    this.viewModel.remove(item)
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private clearHistory(): void {
    this.applyState({
      histories: this.viewState.histories,
      listEntries: this.viewState.listEntries,
      keyword: this.viewState.keyword,
      totalCount: this.viewState.totalCount,
      isLoading: true,
      errorMessage: '',
    });
    this.viewModel.clear()
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private buildErrorState(error: Error): HistoryPageViewState {
    return {
      histories: [],
      listEntries: [],
      keyword: this.keyword,
      totalCount: 0,
      isLoading: false,
      errorMessage: error.message && error.message.length > 0 ? error.message : '历史记录操作失败',
    };
  }

  private formatVisitTime(visitTime: number): string {
    const date = new Date(visitTime);
    const month = this.padNumber(date.getMonth() + 1);
    const day = this.padNumber(date.getDate());
    const hour = this.padNumber(date.getHours());
    const minute = this.padNumber(date.getMinutes());
    return `${month}-${day} ${hour}:${minute}`;
  }

  private padNumber(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  @Builder
  private HistoryRow(item: HistoryItem) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(item.title && item.title.length > 0 ? item.title : item.url)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Text(item.url)
            .fontSize(12)
            .fontColor('#6b7280')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Text(`${this.formatVisitTime(item.visitTime)} · 访问 ${item.visitCount ?? 1} 次`)
            .fontSize(11)
            .fontColor('#9ca3af')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Button('打开')
          .fontSize(12)
          .height(30)
          .backgroundColor('#dbeafe')
          .fontColor('#2563eb')
          .borderRadius(15)
          .onClick(() => this.openHistory(item.url));

        Button('删除')
          .fontSize(12)
          .height(30)
          .backgroundColor('#f3f4f6')
          .fontColor('#374151')
          .borderRadius(15)
          .onClick(() => this.removeHistory(item));
      }
      .width('100%');
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .border({ width: 1, color: '#e5e7eb' })
    .onClick(() => this.openHistory(item.url));
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
            this.route = AppRouter.Browser;
          });

        Text(`历史 ${this.viewState.totalCount}`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .layoutWeight(1);

        if (this.viewState.totalCount > 0) {
          Button('清空')
            .height(34)
            .fontSize(12)
            .backgroundColor('#fee2e2')
            .fontColor('#dc2626')
            .borderRadius(17)
            .enabled(!this.viewState.isLoading)
            .onClick(() => this.clearHistory());
        }
      }
      .width('100%');

      TextInput({ text: this.keyword, placeholder: '搜索历史记录' })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor('#ffffff')
        .borderRadius(20)
        .padding({ left: 14, right: 14 })
        .border({ width: 1, color: '#dbe3f0' })
        .onChange((value: string) => this.setKeyword(value));

      if (this.viewState.errorMessage.length > 0) {
        Column({ space: 8 }) {
          Text('历史记录不可用')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text(this.viewState.errorMessage)
            .fontSize(13)
            .fontColor('#6b7280')
            .textAlign(TextAlign.Center);

          Button('重试')
            .height(34)
            .fontSize(13)
            .backgroundColor('#dbeafe')
            .fontColor('#2563eb')
            .borderRadius(17)
            .onClick(() => this.reloadHistory());
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else if (this.viewState.isLoading && this.viewState.histories.length === 0) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color('#2563eb');

          Text('正在加载历史记录')
            .fontSize(13)
            .fontColor('#6b7280');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else if (this.viewState.histories.length === 0) {
        Column({ space: 8 }) {
          Text(this.keyword.trim().length > 0 ? '没有匹配的历史记录' : '还没有历史记录')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text(this.keyword.trim().length > 0 ? '换一个关键词再试试。' : '访问网页后，会在这里显示浏览记录。')
            .fontSize(13)
            .fontColor('#6b7280');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        List({ space: 10 }) {
          ForEach(this.viewState.listEntries, (entry: HistoryListEntry) => {
            ListItem() {
              if (entry.type === 'section') {
                Text(entry.label)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#6b7280')
                  .padding({ left: 4, top: 4, bottom: 2 });
              } else if (entry.history) {
                this.HistoryRow(entry.history);
              }
            }
          }, (entry: HistoryListEntry) => entry.id);
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
