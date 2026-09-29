import { SitePermissionPromptDecision, SitePermissionPromptResult, SitePermissionRequest } from '../../core/permissionTypes';

const EMPTY_PERMISSION_REQUEST: SitePermissionRequest = {
  requestId: '',
  origin: '',
  permissionType: 'location',
  title: '站点权限请求',
  message: '',
  allowRememberChoice: true,
  rememberChoiceDefault: false,
  isSecureContext: true,
  requestedAt: 0,
};

@Component
export struct PermissionDialog {
  @Prop request: SitePermissionRequest = EMPTY_PERMISSION_REQUEST;
  @Prop confirmText: string = '允许';
  @Prop cancelText: string = '拒绝';
  @Prop pending: boolean = false;
  @Prop dialogWidth: number = 360;
  @Link rememberChoice: boolean;

  onDecision: (result: SitePermissionPromptResult) => void = () => {};

  private emitDecision(decision: SitePermissionPromptDecision): void {
    if (this.pending) {
      return;
    }
    this.onDecision({
      requestId: this.request.requestId,
      origin: this.request.origin,
      permissionType: this.request.permissionType,
      decision: decision,
      rememberChoice: this.rememberChoice,
      decidedAt: Date.now(),
      source: 'prompt',
    });
  }

  build() {
    Column({ space: 14 }) {
      Text(this.request.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827');

      Text(this.request.message)
        .fontSize(13)
        .fontColor('#4b5563');

      if (this.request.origin.length > 0) {
        Text(this.request.origin)
          .fontSize(12)
          .fontColor('#6b7280');
      }

      if (this.request.allowRememberChoice) {
        Row({ space: 10 }) {
          Row() {
            if (this.rememberChoice) {
              Text('✓')
                .fontSize(12)
                .fontColor('#2563eb');
            }
          }
          .width(18)
          .height(18)
          .justifyContent(FlexAlign.Center)
          .borderRadius(9)
          .border({ width: 1, color: this.rememberChoice ? '#2563eb' : '#cbd5e1' })
          .backgroundColor(this.rememberChoice ? '#dbeafe' : '#ffffff');

          Text('记住此次选择')
            .fontSize(12)
            .fontColor('#374151');
        }
        .onClick(() => {
          if (!this.pending) {
            this.rememberChoice = !this.rememberChoice;
          }
        });
      }

      Row({ space: 10 }) {
        Button(this.cancelText)
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#f3f4f6')
          .fontColor(this.pending ? '#9ca3af' : '#374151')
          .borderRadius(18)
          .enabled(!this.pending)
          .onClick(() => this.emitDecision('deny'));

        Button(this.pending ? '处理中' : this.confirmText)
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#2563eb')
          .fontColor('#ffffff')
          .borderRadius(18)
          .enabled(!this.pending)
          .onClick(() => this.emitDecision('allow'));
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.dialogWidth)
    .padding(20)
    .backgroundColor('#ffffff')
    .borderRadius(20);
  }
}
