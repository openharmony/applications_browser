import { HistoryItem } from '../../core/historyManager';
import { HistoryListEntry, HistoryPageViewState, HistoryViewModel } from '../viewmodels/HistoryViewModel';

const EMPTY_HISTORY_STATE: HistoryPageViewState = {
  histories: [],
  listEntries: [],
  keyword: '',
  totalCount: 0,
  isLoading: false,
  errorMessage: '',
};

@Component
export struct SettingsHistoryManager {
  @Prop compact: boolean = false;
  onOpenUrl: (url: string) => void = (_: string): void => {};

  private readonly viewModel: HistoryViewModel = new HistoryViewModel();
  @State private viewState: HistoryPageViewState = EMPTY_HISTORY_STATE;
  @State private keyword: string = '';
  @State private statusMessage: string = '';
  @State private showClearDialog: boolean = false;

  aboutToAppear(): void {
    this.applyState(this.viewModel.getInitialState());
    this.reloadHistory();
  }

  private applyState(state: HistoryPageViewState): void {
    this.viewState = state;
    this.keyword = state.keyword;
  }

  private buildPendingState(keyword: string = this.viewState.keyword): HistoryPageViewState {
    return {
      histories: this.viewState.histories,
      listEntries: this.viewState.listEntries,
      keyword: keyword,
      totalCount: this.viewState.totalCount,
      isLoading: true,
      errorMessage: '',
    };
  }

  private buildErrorState(error: Error): HistoryPageViewState {
    return {
      histories: [],
      listEntries: [],
      keyword: this.keyword,
      totalCount: 0,
      isLoading: false,
      errorMessage: error.message || '历史记录操作失败',
    };
  }

  private reloadHistory(): void {
    this.applyState(this.buildPendingState());
    this.viewModel.load()
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private setKeyword(keyword: string): void {
    this.keyword = keyword;
    this.applyState(this.buildPendingState(keyword));
    this.viewModel.setKeyword(keyword)
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private openHistory(item: HistoryItem): void {
    this.onOpenUrl(item.url);
  }

  private removeHistory(item: HistoryItem): void {
    this.applyState(this.buildPendingState());
    this.viewModel.remove(item)
      .then((state: HistoryPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private openClearDialog(): void {
    this.showClearDialog = true;
  }

  private closeClearDialog(): void {
    this.showClearDialog = false;
  }

  private clearHistory(): void {
    this.closeClearDialog();
    this.statusMessage = '正在清除历史记录...';
    this.applyState(this.buildPendingState());
    this.viewModel.clear()
      .then((state: HistoryPageViewState) => {
        this.applyState(state);
        this.statusMessage = '历史记录已清除';
      })
      .catch((error: Error) => {
        this.applyState(this.buildErrorState(error));
        this.statusMessage = error.message || '历史记录清除失败';
      });
  }

  private formatVisitTime(visitTime: number): string {
    const date = new Date(visitTime);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const hour = date.getHours();
    const minute = date.getMinutes();
    return `${month < 10 ? '0' : ''}${month}-${day < 10 ? '0' : ''}${day} ${hour < 10 ? '0' : ''}${hour}:${minute < 10 ? '0' : ''}${minute}`;
  }

  @Builder
  private HistoryRow(item: HistoryItem, showDivider: boolean) {
    Column({ space: this.compact ? 8 : 0 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(item.title && item.title.length > 0 ? item.title : item.url)
            .fontSize(14)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(item.url)
            .fontSize(12)
            .fontColor('#666666')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (!this.compact) {
          Text(this.formatVisitTime(item.visitTime))
            .fontSize(12)
            .fontColor('#999999');
          Button('×')
            .width(30)
            .height(30)
            .fontSize(18)
            .fontColor('#666666')
            .backgroundColor('#00000000')
            .borderRadius(15)
            .onClick(() => this.removeHistory(item));
        }
      }
      .width('100%');

      if (this.compact) {
        Row() {
          Text(this.formatVisitTime(item.visitTime))
            .layoutWeight(1)
            .fontSize(12)
            .fontColor('#999999');
          Button('删除')
            .height(30)
            .fontSize(12)
            .fontColor('#d32f2f')
            .backgroundColor('#00000000')
            .borderRadius(4)
            .onClick(() => this.removeHistory(item));
        }
        .width('100%');
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' })
    .onClick(() => this.openHistory(item));
  }

  @Builder
  private ClearDialog() {
    Column() {
      Text('清除历史记录')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333');
      Text('确定要清除全部历史记录吗？此操作无法撤销。')
        .width('100%')
        .fontSize(14)
        .fontColor('#555555')
        .margin({ top: 18 });
      Row({ space: 10 }) {
        Button('取消')
          .height(36)
          .fontSize(13)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .onClick(() => this.closeClearDialog());
        Button('清除')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#d32f2f')
          .borderRadius(4)
          .onClick(() => this.clearHistory());
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 24 });
    }
    .width(420)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private HistoryDialogCover() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => this.closeClearDialog());
      this.ClearDialog();
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#00000000');
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 12 }) {
          Text('历史记录')
            .layoutWeight(1)
            .fontSize(28)
            .fontWeight(FontWeight.Regular)
            .fontColor('#333333');
          if (this.viewState.totalCount > 0) {
            Button('清除历史记录')
              .height(34)
              .fontSize(12)
              .fontColor('#d32f2f')
              .backgroundColor('#ffffff')
              .border({ width: 1, color: '#dddddd' })
              .borderRadius(4)
              .enabled(!this.viewState.isLoading)
              .onClick(() => this.openClearDialog());
          }
        }
        .width('100%')
        .margin({ bottom: 24 });

        Column() {
          TextInput({ text: this.keyword, placeholder: '搜索历史记录...' })
            .width('100%')
            .height(40)
            .fontSize(13)
            .backgroundColor('#ffffff')
            .padding({ left: 12, right: 12 })
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .onChange((value: string) => this.setKeyword(value));

          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .width('100%')
              .fontSize(12)
              .fontColor('#666666')
              .margin({ top: 12 });
          }

          Column() {
            if (this.viewState.errorMessage.length > 0) {
              Column({ space: 10 }) {
                Text('历史记录不可用')
                  .fontSize(16)
                  .fontColor('#333333');
                Text(this.viewState.errorMessage)
                  .fontSize(12)
                  .fontColor('#666666');
                Button('重试')
                  .height(32)
                  .fontSize(12)
                  .onClick(() => this.reloadHistory());
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            } else if (this.viewState.isLoading && this.viewState.histories.length === 0) {
              Column() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color('#1976d2');
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            } else if (this.viewState.histories.length === 0) {
              Column() {
                Text(this.keyword.trim().length > 0 ? '没有匹配的历史记录' : '暂无历史记录')
                  .fontSize(14)
                  .fontColor('#666666');
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            } else {
              List() {
                ForEach(this.viewState.listEntries, (entry: HistoryListEntry, index: number) => {
                  ListItem() {
                    if (entry.type === 'section') {
                      Text(entry.label)
                        .width('100%')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#666666')
                        .padding({ left: 16, top: 16, bottom: 8 });
                    } else if (entry.history) {
                      this.HistoryRow(entry.history, index < this.viewState.listEntries.length - 1);
                    }
                  }
                }, (entry: HistoryListEntry) => entry.id);
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
              .divider({ strokeWidth: 0, color: '#00000000' });
            }
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 16 })
          .border({ width: 1, color: '#e0e0e0' })
          .borderRadius(8);
        }
        .width('100%')
        .layoutWeight(1)
        .padding(24)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#ffffff')
        .borderRadius(8)
        .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start);

    }
    .width('100%')
    .height('100%')
    .bindContentCover(this.showClearDialog, this.HistoryDialogCover, ModalTransition.NONE);
  }
}
