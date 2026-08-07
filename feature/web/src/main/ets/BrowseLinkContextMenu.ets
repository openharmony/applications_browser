import { getBrowserUIContext } from 'common'
import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'
import { BrowserWindowService } from 'browser_core'

/** 链接长按菜单定位结果（position 始终使用左上角坐标） */
export interface LinkMenuPlacement {
  leftX: number
  topY: number
  mode: string
}

interface ViewportVp {
  width: number
  height: number
}

/** 网页超链接长按菜单（URL 气泡 + 操作列表，参考系统浏览器样式） */
@Component
export struct BrowseLinkContextMenu {
  @Prop visible: boolean = false
  @Prop linkUrl: string = ''
  /** 长按锚点 X（vp，相对窗口） */
  @Prop anchorX: number = 0
  /** 长按锚点 Y（vp，相对窗口） */
  @Prop anchorY: number = 0
  onClose?: () => void
  onOpenInNewWindow?: () => void
  onCopyLink?: () => void
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageLink(AppStorageKeys.WINDOW_WIDTH) windowWidthPx: number = 360
  @StorageLink(AppStorageKeys.WINDOW_HEIGHT) windowHeightPx: number = 780

  static readonly MENU_WIDTH: number = 220
  private static readonly BLOCK_EST_HEIGHT: number = 168
  /** 默认展示在手指右上方时的偏移 */
  private static readonly FINGER_GAP_X: number = 24
  private static readonly FINGER_GAP_Y: number = 20
  /** 右上角锚定在手指左侧时的间距 */
  private static readonly FINGER_LEFT_GAP: number = 8
  private static readonly EDGE_MARGIN: number = 16

  /**
   * 计算菜单左上角坐标。
   * 默认：左上角在手指右上方；右侧不足：右上角在手指左侧、顶边平行。
   */
  /** 解析窗口可视区域（vp），AppStorage 未同步时从主窗口读取 */
  private static resolveViewportVp(windowWidthPx: number, windowHeightPx: number): ViewportVp {
    let widthPx = windowWidthPx
    let heightPx = windowHeightPx
    if (widthPx <= 0 || heightPx <= 0) {
      const resolved = BrowserWindowService.getInstance().resolveWindowSizePx()
      if (widthPx <= 0) {
        widthPx = resolved.width
      }
      if (heightPx <= 0) {
        heightPx = resolved.height
      }
    }
    const ui = getBrowserUIContext()
    return {
      width: ui && widthPx > 0 ? ui.px2vp(widthPx) : 360,
      height: ui && heightPx > 0 ? ui.px2vp(heightPx) : 780,
    }
  }

  static computePlacement(
    anchorX: number,
    anchorY: number,
    windowWidthPx: number,
    windowHeightPx: number
  ): LinkMenuPlacement {
    const viewport = BrowseLinkContextMenu.resolveViewportVp(windowWidthPx, windowHeightPx)
    const width = viewport.width
    const height = viewport.height
    const menuW = BrowseLinkContextMenu.MENU_WIDTH
    const menuH = BrowseLinkContextMenu.BLOCK_EST_HEIGHT
    const margin = BrowseLinkContextMenu.EDGE_MARGIN
    const gapX = BrowseLinkContextMenu.FINGER_GAP_X
    const gapY = BrowseLinkContextMenu.FINGER_GAP_Y
    const leftGap = BrowseLinkContextMenu.FINGER_LEFT_GAP

    const preferLeftTopX = anchorX + gapX
    const fitsRight = preferLeftTopX + menuW <= width - margin

    if (fitsRight) {
      let mode = 'rightTop'
      let leftX = preferLeftTopX
      let topY = anchorY - gapY
      if (topY < margin) {
        mode = 'rightBottom'
        topY = anchorY + gapY
      }
      if (topY + menuH > height - margin) {
        mode = 'rightAbove'
        topY = anchorY - menuH - gapY
      }
      topY = Math.min(Math.max(topY, margin), Math.max(margin, height - menuH - margin))
      leftX = Math.min(Math.max(leftX, margin), Math.max(margin, width - menuW - margin))
      return { leftX, topY, mode }
    }

    // 右侧放不下：弹框右上角在手指左侧，顶边与按压点平行
    let mode = 'leftTopRightAnchor'
    let leftX = anchorX - leftGap - menuW
    let topY = anchorY

    if (leftX < margin) {
      leftX = margin
    }

    if (topY + menuH > height - margin) {
      mode = 'leftBottomRightAnchor'
      topY = anchorY - menuH
      if (topY < margin) {
        topY = margin
      }
    }

    if (topY < margin) {
      topY = margin
    }

    return { leftX, topY, mode }
  }

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private menuBg(): string {
    return this.isDark() ? 'rgba(58, 58, 60, 0.88)' : 'rgba(255, 255, 255, 0.92)'
  }

  private urlPillBg(): string {
    return this.isDark() ? 'rgba(72, 72, 74, 0.92)' : 'rgba(245, 245, 247, 0.95)'
  }

  private menuPosition(): LinkMenuPlacement {
    return BrowseLinkContextMenu.computePlacement(
      this.anchorX, this.anchorY, this.windowWidthPx, this.windowHeightPx)
  }

  @Builder
  MenuBlock() {
    Column({ space: 8 }) {
      Text(this.linkUrl)
        .fontSize(13)
        .fontColor(BrowserTheme.textSecondary(this.isDark()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(this.urlPillBg())
        .borderRadius(18)
        .constraintSize({ maxWidth: BrowseLinkContextMenu.MENU_WIDTH })

      Column() {
        Text($r('app.string.web_link_open_in_new_window'))
          .fontSize(16)
          .fontColor(BrowserTheme.text(this.isDark()))
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .onClick(() => {
            this.onOpenInNewWindow?.()
            this.onClose?.()
          })

        Divider()
          .strokeWidth(0.5)
          .color(this.isDark() ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.08)')
          .margin({ left: 16, right: 16 })

        Text($r('app.string.web_link_copy'))
          .fontSize(16)
          .fontColor(BrowserTheme.text(this.isDark()))
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .onClick(() => {
            this.onCopyLink?.()
            this.onClose?.()
          })
      }
      .width(BrowseLinkContextMenu.MENU_WIDTH)
      .backgroundColor(this.menuBg())
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(14)
      .clip(true)
      .border({
        width: 0.5,
        color: this.isDark() ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.06)'
      })
    }
    .width(BrowseLinkContextMenu.MENU_WIDTH)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.visible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.18)')
          .onClick(() => this.onClose?.())

        Stack({ alignContent: Alignment.TopStart }) {
          this.MenuBlock()
        }
        .position({
          x: this.menuPosition().leftX,
          y: this.menuPosition().topY
        })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
  }
}
