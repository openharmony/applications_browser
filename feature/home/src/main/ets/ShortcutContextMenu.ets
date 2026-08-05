import { BrowserTheme } from 'browser_core'



/** 快捷方式长按菜单（仅编辑/移除气泡，无标题） */

@Component

export struct ShortcutContextMenu {

  /** 菜单气泡左上角 X（相对 MainPage Stack） */

  @Prop posX: number = 0

  /** 菜单气泡左上角 Y（图标正下方） */

  @Prop posY: number = 0

  /** 是否深色主题 */

  @Prop darkMode: boolean = false

  /** 菜单气泡宽度 */

  @Prop menuWidth: number = 144

  /** 点击编辑 */

  onEdit?: () => void

  /** 点击移除 */

  onRemove?: () => void



  private menuBg(): string {

    return this.darkMode ? 'rgba(58, 58, 60, 0.72)' : 'rgba(255, 255, 255, 0.82)'

  }



  private menuTextColor(): string {

    return this.darkMode ? '#ffffff' : BrowserTheme.TEXT

  }



  build() {

    Column({ space: 0 }) {

      this.MenuAction($r('app.string.edit'), false, () => {

        this.onEdit?.()

      })

      Divider()
        .color(this.darkMode ? 'rgba(255, 255, 255, 0.14)' : 'rgba(0, 0, 0, 0.08)')
        .strokeWidth(0.5)
        .margin({ left: 16, right: 16 })

      this.MenuAction($r('app.string.shortcut_remove'), true, () => {

        this.onRemove?.()

      })

    }

    .width(this.menuWidth)

    .backgroundColor(this.menuBg())

    .backgroundBlurStyle(BlurStyle.Thin)

    .borderRadius(12)

    .border({

      width: 0.5,

      color: this.darkMode ? 'rgba(255, 255, 255, 0.14)' : 'rgba(0, 0, 0, 0.08)'

    })

    .alignItems(HorizontalAlign.Start)

    .clip(false)

    .position({ x: this.posX, y: this.posY })

    .hitTestBehavior(HitTestMode.Default)

  }



  @Builder

  MenuAction(label: ResourceStr, danger: boolean, onTap: () => void) {

    Text(label)

      .fontSize(15)

      .fontWeight(FontWeight.Regular)

      .fontColor(danger ? '#ef4444' : this.menuTextColor())

      .width('100%')

      .textAlign(TextAlign.Start)

      .padding({ left: 16, right: 16, top: 10, bottom: 10 })

      .onClick(() => onTap())

  }

}


