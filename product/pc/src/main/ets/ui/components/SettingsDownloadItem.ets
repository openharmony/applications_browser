import {
  DownloadTask,
  formatDownloadBytes,
  getDownloadTaskStateText,
  isActiveDownloadState,
} from '../../core/downloadTypes';

@Component
export struct SettingsDownloadItem {
  @Prop task: DownloadTask;
  @Link renderRevision: number;
  @Prop compact: boolean = false;
  @Prop showDivider: boolean = true;
  @Prop extraActionBusy: boolean = false;
  onCancel: (id: string) => void = (_: string): void => {};
  onPause: (id: string) => void = (_: string): void => {};
  onResume: (id: string) => void = (_: string): void => {};
  onRetry: (id: string) => void = (_: string): void => {};
  onRemove: (id: string) => void = (_: string): void => {};
  onCopy: (id: string) => void = (_: string): void => {};
  onOpenFolder: (id: string) => void = (_: string): void => {};

  /**
   * DownloadTask is a plain interface rather than an @Observed object. The
   * parent therefore advances renderRevision when the manager publishes a new
   * snapshot; resolve the latest immutable snapshot here without rebuilding
   * the row or changing its ForEach identity.
   */
  getTask: (id: string) => DownloadTask | null = (_: string): DownloadTask | null => null;

  private currentTask(): DownloadTask {
    // Reading the @Link makes this component reactive to download updates.
    const revision = this.renderRevision;
    return this.getTask(this.task.id) ?? this.task;
  }

  private getStatusBackground(): string {
    const task = this.currentTask();
    if (task.state === 'completed') {
      return '#e8f5e9';
    }
    if (task.state === 'downloading' || task.state === 'pending') {
      return '#e3f2fd';
    }
    if (task.state === 'failed') {
      return '#ffebee';
    }
    return '#f0f2f5';
  }

  private getStatusColor(): string {
    const task = this.currentTask();
    if (task.state === 'completed') {
      return '#388e3c';
    }
    if (task.state === 'downloading' || task.state === 'pending') {
      return '#1976d2';
    }
    if (task.state === 'failed') {
      return '#d32f2f';
    }
    return '#666666';
  }

  private showPauseAction(): boolean {
    const task = this.currentTask();
    return isActiveDownloadState(task.state) && task.state !== 'paused';
  }

  private showResumeAction(): boolean {
    const task = this.currentTask();
    return task.state === 'paused' && task.canResume;
  }

  private showCancelAction(): boolean {
    return isActiveDownloadState(this.currentTask().state);
  }

  private showRetryAction(): boolean {
    const task = this.currentTask();
    return (task.state === 'failed' || task.state === 'canceled') && task.canRetry;
  }

  private isActionBusy(): boolean {
    return this.currentTask().actionBusy === true || this.extraActionBusy;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 14 }) {
        Text(this.currentTask().fileName)
          .layoutWeight(1)
          .fontSize(15)
          .fontColor('#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        if (!this.compact) {
          Text(formatDownloadBytes(this.currentTask().totalBytes))
            .fontSize(12)
            .fontColor('#666666');

          Text(this.currentTask().actionLabel || getDownloadTaskStateText(this.currentTask().state))
            .fontSize(11)
            .fontColor(this.isActionBusy() ? '#1976d2' : this.getStatusColor())
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.getStatusBackground())
            .borderRadius(4);
        }

        Button() {
          Image($r('app.media.download_manager_copy'))
            // 设计切图为 32x32 @2x，按 16x16 dp 渲染。
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain);
        }
          .width(34)
          .height(34)
          .padding(0)
          .backgroundColor('#00000000')
          .enabled(!this.isActionBusy())
          .opacity(this.isActionBusy() ? 0.45 : 1)
          .accessibilityText('复制下载链接')
          .onClick(() => this.onCopy(this.currentTask().id));

        // 单条删除必须保持明确且易点击；“清除已结束”不会替代该操作。
        // 这里只删除下载记录，不删除本地文件；进行中的任务会由 DownloadManager 负责取消。
        Button() {
          Image($r('app.media.download_manager_delete'))
            // 设计切图为 32x32 @2x，按 16x16 dp 渲染。
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain);
        }
          .width(34)
          .height(34)
          .padding(0)
          .backgroundColor('#00000000')
          .enabled(!this.isActionBusy())
          .opacity(this.isActionBusy() ? 0.45 : 1)
          .accessibilityText('删除下载记录')
          .onClick(() => this.onRemove(this.currentTask().id));
      }
      .width('100%');

      if (this.compact) {
        Row({ space: 10 }) {
          Text(formatDownloadBytes(this.currentTask().totalBytes))
            .fontSize(12)
            .fontColor('#666666');
          Text(this.currentTask().actionLabel || getDownloadTaskStateText(this.currentTask().state))
            .fontSize(11)
            .fontColor(this.isActionBusy() ? '#1976d2' : this.getStatusColor())
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.getStatusBackground())
            .borderRadius(4);
        }
        .width('100%');
      }

      Text(this.currentTask().sourceUrl)
        .width('100%')
        .fontSize(12)
        .fontColor('#666666')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      if (isActiveDownloadState(this.currentTask().state)) {
        Row({ space: 12 }) {
          Progress({ value: this.currentTask().progress, total: 100, type: ProgressType.Linear })
            .layoutWeight(1)
            .height(4)
            .color('#1976d2')
            .backgroundColor('#e0e0e0');
          Text(`${this.currentTask().progress}%`)
            .width(40)
            .fontSize(12)
            .fontColor('#666666')
            .textAlign(TextAlign.End);
        }
        .width('100%');
      }

      Row({ space: 8 }) {
        if (this.showPauseAction()) {
          Button() {
            Row({ space: 4 }) {
              Image($r('app.media.download_manager_pause'))
                // 设计切图为 28x28 @2x，按 14x14 dp 渲染。
                .width(14)
                .height(14)
                .objectFit(ImageFit.Contain);
              Text('暂停')
                .fontSize(12)
                .fontColor('#333333');
            }
          }
            .width(66)
            .height(34)
            .padding(0)
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .accessibilityText('暂停下载')
            .onClick(() => this.onPause(this.currentTask().id));
        }
        if (this.showResumeAction()) {
          Button('继续')
            .height(30)
            .fontSize(12)
            .fontColor('#333333')
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .onClick(() => this.onResume(this.currentTask().id));
        }
        if (this.showCancelAction()) {
          Button() {
            Row({ space: 4 }) {
              Image($r('app.media.download_manager_cancel'))
                // 设计切图为 28x28 @2x，按 14x14 dp 渲染。
                .width(14)
                .height(14)
                .objectFit(ImageFit.Contain);
              Text('取消')
                .fontSize(12)
                .fontColor('#333333');
            }
          }
            .width(66)
            .height(34)
            .padding(0)
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .accessibilityText('取消下载')
            .onClick(() => this.onCancel(this.currentTask().id));
        }
        if (this.showRetryAction()) {
          Button('重试')
            .height(30)
            .fontSize(12)
            .fontColor('#1976d2')
            .backgroundColor('#e3f2fd')
            .borderRadius(4)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .onClick(() => this.onRetry(this.currentTask().id));
        }
        if (this.currentTask().state === 'completed' && (this.currentTask().filePath?.trim() ?? '').length > 0) {
          Button() {
            Row({ space: 5 }) {
              Image($r('app.media.download_manager_open_folder'))
                .width(18)
                .height(18)
                .objectFit(ImageFit.Contain);
              Text('在文件夹中打开')
                .fontSize(12)
                .fontColor('#333333');
            }
          }
            .height(32)
            .padding({ left: 10, right: 10 })
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .enabled(!this.isActionBusy())
            .opacity(this.isActionBusy() ? 0.55 : 1)
            .accessibilityText('在文件夹中打开')
            .onClick(() => this.onOpenFolder(this.currentTask().id));
        }
      }
      .width('100%')
      .justifyContent(isActiveDownloadState(this.currentTask().state) ? FlexAlign.End : FlexAlign.Start);
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .alignItems(HorizontalAlign.Start)
    .border({ width: { bottom: this.showDivider ? 1 : 0 }, color: '#f0f2f5' });
  }
}
