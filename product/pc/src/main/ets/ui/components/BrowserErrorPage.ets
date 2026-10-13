import { BrowserWebErrorState } from '../../core/browserWebError';

@Component
export struct BrowserErrorPage {
  @Prop error: BrowserWebErrorState;
  @Prop isPrivate: boolean = false;
  @Prop canGoBack: boolean = false;
  @Prop contentWidth: number = 620;

  onRetry: () => void = () => {};
  onBack: () => void = () => {};

  @Builder
  private ErrorMark() {
    Stack({ alignContent: Alignment.Center }) {
      Text('!')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isPrivate ? '#d8b4fe' : '#64748b');
    }
    .width(64)
    .height(64)
    .borderRadius(32)
    .backgroundColor(this.isPrivate ? '#312e81' : '#eef2f7');
  }

  @Builder
  private ActionButton(label: string, icon: Resource, primary: boolean, onClick: () => void) {
    Button() {
      Row({ space: 8 }) {
        Image(icon)
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .opacity(primary ? 1 : 0.72);
        Text(label)
          .fontSize(13)
          .fontColor(primary ? '#ffffff' : (this.isPrivate ? '#e5e7eb' : '#374151'));
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%');
    }
    .type(ButtonType.Normal)
    .height(38)
    .padding({ left: 16, right: 16 })
    .borderRadius(6)
    .backgroundColor(primary ? (this.isPrivate ? '#6d28d9' : '#2563eb') :
      (this.isPrivate ? '#252936' : '#ffffff'))
    .border({ width: primary ? 0 : 1, color: this.isPrivate ? '#4b5563' : '#d5dbe5' })
    .onClick(onClick);
  }

  build() {
    Column() {
      this.ErrorMark();

      Text(this.error.title)
        .margin({ top: 22 })
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isPrivate ? '#f3f4f6' : '#202124')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Text(this.error.message)
        .margin({ top: 10 })
        .fontSize(14)
        .lineHeight(22)
        .fontColor(this.isPrivate ? '#cbd5e1' : '#5f6368')
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Text(this.error.url)
        .margin({ top: 16 })
        .fontSize(12)
        .fontColor(this.isPrivate ? '#9ca3af' : '#7b8491')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      if (this.error.errorCode.length > 0) {
        Text(this.error.errorCode)
          .margin({ top: 8 })
          .fontSize(11)
          .fontColor(this.isPrivate ? '#9ca3af' : '#8b95a3');
      }

      Row({ space: 10 }) {
        if (this.canGoBack) {
          this.ActionButton('返回上一页', $r('app.media.home_backward'), false, () => this.onBack());
        }
        if (this.error.retryable) {
          this.ActionButton('重新加载', $r('app.media.home_refresh'), true, () => this.onRetry());
        }
      }
      .margin({ top: 26 })
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .constraintSize({ maxWidth: this.contentWidth });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, top: 32, bottom: 32 })
    .backgroundColor(this.isPrivate ? '#171a21' : '#ffffff');
  }
}
