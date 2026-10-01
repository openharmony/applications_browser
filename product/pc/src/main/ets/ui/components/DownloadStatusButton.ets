import { DownloadIndicatorSnapshot } from '../../core/downloadTypes';

const IDLE_DOWNLOAD_INDICATOR: DownloadIndicatorSnapshot = {
  primaryState: 'idle',
  activeTaskCount: 0,
  failedTaskCount: 0,
  completedTaskCount: 0,
  aggregateProgress: 0,
  hasActiveTasks: false,
  hasSessionDownloadActivity: false,
};

@Component
export struct DownloadStatusButton {
  @Prop icon: Resource;
  @Prop snapshot: DownloadIndicatorSnapshot = IDLE_DOWNLOAD_INDICATOR;

  onClickAction: () => void = () => {};

  private getTintColor(): string {
    if (this.snapshot.primaryState === 'failed_notice') {
      return '#dc2626';
    }
    if (this.snapshot.primaryState === 'completed_notice') {
      return '#8bbcf2';
    }
    if (this.snapshot.primaryState === 'session_history') {
      return '#8bbcf2';
    }
    return '#4b5563';
  }

  private getBadgeText(): string {
    if (this.snapshot.activeTaskCount > 1) {
      return `${this.snapshot.activeTaskCount}`;
    }
    if (this.snapshot.primaryState === 'failed_notice' && this.snapshot.failedTaskCount > 0) {
      return '!';
    }
    return '';
  }

  private hasBadge(): boolean {
    return this.getBadgeText().length > 0;
  }

  private getBadgeFontSize(): number {
    return 9;
  }

  private getBadgeColor(): string {
    return this.snapshot.primaryState === 'failed_notice' ? '#dc2626' : '#2563eb';
  }

  private getBadgeWidth(): number {
    return 18;
  }

  private getProgressOverlayWidth(): string {
    const progress = this.snapshot.aggregateProgress < 4 ? 4 : this.snapshot.aggregateProgress;
    return `${progress}%`;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.snapshot.primaryState === 'downloading') {
        Progress({ value: this.snapshot.aggregateProgress, total: 100, type: ProgressType.Ring })
          .width(28)
          .height(28)
          .color('#2563eb')
          .backgroundColor('#dbeafe')
          .style({ strokeWidth: 2, shadow: false });
      }

      Row() {
        Image(this.icon)
          .width(16)
          .height(16)
          .fillColor(this.getTintColor())
          .opacity(this.snapshot.primaryState === 'idle' ? 0.74 :
            (this.snapshot.primaryState === 'completed_notice' ||
              this.snapshot.primaryState === 'session_history' ? 0.82 : 1));
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .borderRadius(14)
      .backgroundColor('#00000000');

      if (this.hasBadge()) {
        Row() {
          Text(this.getBadgeText())
            .fontSize(this.getBadgeFontSize())
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff');
        }
        .width(this.getBadgeWidth())
        .height(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.getBadgeColor())
        .borderRadius(7)
        .position({ x: 16, y: -2 });
      }
    }
    .width(28)
    .height(28)
    .onClick(() => this.onClickAction());
  }
}
