import { BrowserTheme } from 'browser_core'
import { HistoryEntry } from 'browser_core'
import { HistorySiteIcon } from 'commons'
import { HistoryContextMenu } from './HistoryContextMenu'

/** 历史记录长按 overlay：原位置浮起条目 + 菜单（背板 blur 由调用方 backdropBlur 渲染） */
@Component
export struct HistoryContextMenuLayer {
  @Prop visible: boolean = false
  @Prop darkMode: boolean = false
  @Prop item: HistoryEntry | null = null
  @Prop rowLeft: number = 0
  @Prop rowTop: number = 0
  @Prop rowWidth: number = 0
  @Prop rowHeight: number = 56
  @Prop menuPosX: number = 0
  @Prop menuPosY: number = 0
  menuWidth: number = 220

  onDismiss?: () => void
  onMultiSelect?: () => void
  onAddBookmark?: () => void
  onShare?: () => void
  onOpenNewTab?: () => void
  onDelete?: () => void

  private static readonly LIFT_SCALE: number = 1.02

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.visible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Default)
          .onClick(() => {
            this.onDismiss?.()
          })
      }

      if (this.visible && this.item !== null) {
        this.LiftRow(this.item)
      }

      if (this.visible) {
        HistoryContextMenu({
          posX: this.menuPosX,
          posY: this.menuPosY,
          darkMode: this.darkMode,
          menuWidth: this.menuWidth,
          onMultiSelect: () => {
            this.onMultiSelect?.()
          },
          onAddBookmark: () => {
            this.onAddBookmark?.()
          },
          onShare: () => {
            this.onShare?.()
          },
          onOpenNewTab: () => {
            this.onOpenNewTab?.()
          },
          onDelete: () => {
            this.onDelete?.()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .clip(false)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  LiftRow(item: HistoryEntry) {
    Row() {
      HistorySiteIcon({ url: item.url, iconUrl: item.iconUrl })
        .margin({ right: 10 })

      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(BrowserTheme.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.url)
          .fontSize(12)
          .fontColor(BrowserTheme.TEXT_MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width(this.rowWidth)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(BrowserTheme.PANEL_BG)
    .borderRadius(12)
    .shadow({
      radius: 18,
      color: 'rgba(37, 99, 235, 0.28)',
      offsetX: 0,
      offsetY: 6
    })
    .scale({
      x: HistoryContextMenuLayer.LIFT_SCALE,
      y: HistoryContextMenuLayer.LIFT_SCALE,
      centerX: 0,
      centerY: 0
    })
    .position({ x: this.rowLeft, y: this.rowTop })
    .hitTestBehavior(HitTestMode.None)
  }
}
