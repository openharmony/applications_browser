// BrowserHome：主页/新标签页（常用站点、常访问等）。
// 当前实现聚焦于原型中的「居中搜索框」，用于输入网址或搜索词。

@Component
export struct BrowserHome {
  // 提交搜索/网址时的回调，由父组件（如 BrowserPage）注入。
  // 注意：这里不用装饰器（@Prop/@State），以便安全地接收函数类型。
  onSubmit?: (text: string) => void;
  @Prop isPrivate: boolean = false;

  @State private searchText: string = '';

  private handleSubmit(): void {
    const value = this.searchText.trim();
    if (!value) {
      return;
    }
    if (this.onSubmit) {
      this.onSubmit(value);
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.isPrivate ? '#202227' : '#eff4ff');

      Image($r('app.media.home_wallpaper'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        // .opacity(this.isPrivate ? 0.10 : 0.12);

      Column({ space: 18 }) {
        if (this.isPrivate) {
          Column({ space: 8 }) {
            Text('无痕浏览')
              .fontSize(20)
              .fontColor('#ffffff');

            Text('不会保存浏览历史、Cookie、站点数据或表单输入。下载的文件和创建的书签仍会保留。')
              .fontSize(13)
              .fontColor('#d7dce5')
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .width('80%')
          .constraintSize({ maxWidth: 560 });
        }

        Row() {
          Image($r('app.media.home_search'))
            .width(18)
            .height(18)
            .margin({ right: 12 })
            .opacity(this.isPrivate ? 0.82 : 0.68);

          TextInput({ text: this.searchText, placeholder: this.isPrivate ? '无痕搜索或输入网址' : '搜索或输入网址' })
            .layoutWeight(1)
            .fontSize(15)
            .backgroundColor('#00000000')
            .onChange((value: string) => (this.searchText = value))
            .onSubmit(() => this.handleSubmit());
        }
        .width(488)
        .height(38)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.isPrivate ? '#2b2f37' : '#ffffff')
        .borderRadius(19)
        .border({ width: 1, color: this.isPrivate ? '#484f5b' : '#e4e8f0' });
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .height('100%');
    }
    .width('100%')
    .height('100%');
  }
}
