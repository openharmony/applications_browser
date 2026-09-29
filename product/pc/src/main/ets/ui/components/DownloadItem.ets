import { DownloadTask, formatDownloadBytes, getDownloadTaskStateText } from '../../core/downloadTypes';

@Component
export struct DownloadItem {
  @Prop task: DownloadTask;

  onRetry: (id: string) => void = () => {};
  onCancel: (id: string) => void = () => {};
  onPause: (id: string) => void = () => {};
  onResume: (id: string) => void = () => {};
  onRemove: (id: string) => void = () => {};
  onOpenTarget: (id: string) => void = () => {};

  private getProgressText(): string {
    const received = formatDownloadBytes(this.task.receivedBytes);
    const total = formatDownloadBytes(this.task.totalBytes);
    if (this.task.totalBytes && this.task.totalBytes > 0) {
      return `${received} / ${total}`;
    }
    return received;
  }

  private showRetryAction(): boolean {
    return (this.task.state === 'failed' || this.task.state === 'canceled') && this.task.canRetry;
  }

  private isActionBusy(): boolean {
    return this.task.actionBusy === true;
  }

  private showCancelAction(): boolean {
    return this.task.state === 'created' || this.task.state === 'pending' ||
      this.task.state === 'downloading' || this.task.state === 'paused';
  }

  private showPauseAction(): boolean {
    return this.task.state === 'created' || this.task.state === 'pending' || this.task.state === 'downloading';
  }

  private showResumeAction(): boolean {
    return this.task.state === 'paused' || this.task.canResume;
  }

  private getSourceText(): string {
    if (this.task.pageTitle && this.task.pageTitle.trim().length > 0) {
      return this.task.pageTitle;
    }
    if (this.task.pageUrl && this.task.pageUrl.trim().length > 0) {
      return this.task.pageUrl;
    }
    return this.task.sourceUrl;
  }

  private getOpenActionLabel(): string {
    if (this.task.pageUrl && this.task.pageUrl.trim().length > 0) {
      return '打开来源';
    }
    return '打开链接';
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.task.fileName)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Text(getDownloadTaskStateText(this.task.state))
            .fontSize(12)
            .fontColor(this.task.state === 'failed' ? '#dc2626' : '#6b7280');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Text(`${this.task.progress}%`)
          .fontSize(12)
          .fontColor('#2563eb');
      }
      .width('100%');

      Text(this.getProgressText())
        .fontSize(12)
        .fontColor('#6b7280')
        .width('100%');

      Text(this.getSourceText())
        .fontSize(12)
        .fontColor('#6b7280')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      Row() {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(6)
            .backgroundColor('#e5e7eb')
            .borderRadius(3);

          Row()
            .width(`${Math.max(4, this.task.progress)}%`)
            .height(6)
            .backgroundColor(this.task.state === 'failed' ? '#dc2626' : '#2563eb')
            .borderRadius(3);
        }
      }
      .width('100%');

      Row({ space: 8 }) {
        if (this.showPauseAction()) {
          Button('暂停')
            .fontSize(12)
            .height(32)
            .backgroundColor('#f3f4f6')
            .fontColor('#374151')
            .borderRadius(16)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .onClick(() => this.onPause(this.task.id));
        }

        if (this.showResumeAction()) {
          Button('继续')
            .fontSize(12)
            .height(32)
            .backgroundColor('#dbeafe')
            .fontColor('#2563eb')
            .borderRadius(16)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .onClick(() => this.onResume(this.task.id));
        }

        if (this.showCancelAction()) {
          Button('取消')
            .fontSize(12)
            .height(32)
            .backgroundColor('#f3f4f6')
            .fontColor('#374151')
            .borderRadius(16)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .onClick(() => this.onCancel(this.task.id));
        }

        if (this.showRetryAction()) {
          Button('重试')
            .fontSize(12)
            .height(32)
            .backgroundColor('#dbeafe')
            .fontColor('#2563eb')
            .borderRadius(16)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .onClick(() => this.onRetry(this.task.id));
        }

        Button(this.getOpenActionLabel())
          .fontSize(12)
          .height(32)
          .backgroundColor('#dbeafe')
          .fontColor('#2563eb')
          .borderRadius(16)
          .enabled(!this.isActionBusy())
          .opacity(this.isActionBusy() ? 0.55 : 1)
          .onClick(() => this.onOpenTarget(this.task.id));

        Button('删除')
          .fontSize(12)
          .height(32)
          .backgroundColor('#f3f4f6')
          .fontColor('#374151')
          .borderRadius(16)
          .enabled(!this.isActionBusy())
          .opacity(this.isActionBusy() ? 0.55 : 1)
          .onClick(() => this.onRemove(this.task.id));
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .border({ width: 1, color: '#e5e7eb' });
  }
}
