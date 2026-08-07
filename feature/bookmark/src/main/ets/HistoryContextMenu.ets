import { BrowserTheme } from 'browser_core'

/** 历史记录长按菜单气泡（样式对齐 ShortcutContextMenu） */
@Component
export struct HistoryContextMenu {
  @Prop posX: number = 0
  @Prop posY: number = 0
  @Prop darkMode: boolean = false
  @Prop menuWidth: number = 220

  onMultiSelect?: () => void
  onAddBookmark?: () => void
  onShare?: () => void
  onOpenNewTab?: () => void
  onDelete?: () => void

  private menuBg(): string {
    return this.darkMode ? 'rgba(58, 58, 60, 0.72)' : 'rgba(255, 255, 255, 0.82)'
  }

  private menuTextColor(): string {
    return this.darkMode ? '#ffffff' : BrowserTheme.TEXT
  }

  private dividerColor(): string {
    return this.darkMode ? 'rgba(255, 255, 255, 0.14)' : 'rgba(0, 0, 0, 0.08)'
  }

  build() {
    Column({ space: 0 }) {
      this.MenuAction($r('app.string.batch_multi_select'), false, () => {
        this.onMultiSelect?.()
      })
      this.MenuDivider()
      this.MenuAction($r('app.string.add_to_bookmarks'), false, () => {
        this.onAddBookmark?.()
      })
      this.MenuDivider()
      this.MenuAction($r('app.string.share_action'), false, () => {
        this.onShare?.()
      })
      this.MenuDivider()
      this.MenuAction($r('app.string.open_in_new_tab'), false, () => {
        this.onOpenNewTab?.()
      })
      this.MenuDivider()
      this.MenuAction($r('app.string.delete'), true, () => {
        this.onDelete?.()
      })
    }
    .width(this.menuWidth)
    .backgroundColor(this.menuBg())
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(12)
    .border({
      width: 0.5,
      color: this.dividerColor()
    })
    .alignItems(HorizontalAlign.Start)
    .clip(true)
    .position({ x: this.posX, y: this.posY })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  MenuDivider() {
    Divider()
      .color(this.dividerColor())
      .strokeWidth(0.5)
      .margin({ left: 16, right: 16 })
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
