import { BrowserTheme } from 'browser_core'
import { BrowserStrings } from 'common'

/** 网页内长按上下文菜单（图片保存/分享、链接新标签页等） */
@Component
export struct BrowseWebContextSheet {
  /** 是否显示菜单 */
  @Prop visible: boolean = false
  /** 菜单 actionId 列表，顺序即展示顺序 */
  @Prop actions: string[] = []
  /** 关闭菜单回调 */
  onClose?: () => void
  /** 点击菜单项回调，参数为 actionId */
  onAction?: (action: string) => void
  @StorageLink('browser_theme') theme: string = 'light'

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private dividerColor(): string {
    return BrowserTheme.borderColor(this.isDark())
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.visible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => this.onClose?.())

        Column() {
          ForEach(this.actions, (action: string, index: number) => {
            if (index > 0) {
              Divider()
                .color(this.dividerColor())
                .strokeWidth(1)
                .margin({ left: 16, right: 16 })
            }
            Text(BrowserStrings.webContextAction(action))
              .fontSize(16)
              .fontColor(BrowserTheme.text(this.isDark()))
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => {
                this.onAction?.(action)
              })
          }, (action: string) => action)

          Divider()
            .color(this.dividerColor())
            .strokeWidth(1)
            .margin({ left: 16, right: 16 })

          Text($r('app.string.cancel'))
            .fontSize(16)
            .fontColor(BrowserTheme.text(this.isDark()))
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 24 })
            .onClick(() => this.onClose?.())
        }
        .width('100%')
        .backgroundColor(BrowserTheme.panelBg(this.isDark()))
        .borderRadius({ topLeft: 16, topRight: 16 })
        .zIndex(1)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
  }
}
