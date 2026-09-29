// SettingsSection：设置页中的分组区块（标题 + 内容）。

@Component
export struct SettingsSection {
  @Prop title: string = '';
  @Prop description: string = '';
  @BuilderParam content: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827');

      if (this.description.trim().length > 0) {
        Text(this.description)
          .fontSize(12)
          .fontColor('#6b7280');
      }

      Column() {
        this.content()
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .border({ width: 1, color: '#e5e7eb' });
  }
}
