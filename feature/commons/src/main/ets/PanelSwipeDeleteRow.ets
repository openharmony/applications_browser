import { BrowserTheme } from 'browser_core'
import { TrashClearIcon } from './BrowserIcons'

/** 左滑删除阈值（vp） */
export class PanelSwipeDeleteConfig {
  /** 触发跟手判定的最小左滑距离 */
  static readonly ACTIVATE_PX: number = 5
  /** 垃圾桶完全露出时的条目位移 */
  static readonly REVEAL_PX: number = 72
  /** 继续左滑至该位移松手直接删除 */
  static readonly DELETE_PX: number = 128
  /** 最大跟手位移 */
  static readonly MAX_DRAG_PX: number = 140
}

/**
 * 列表行左滑删除容器：
 * 1. 左滑 5vp 起跟手，垃圾桶随位移渐显；
 * 2. 垃圾桶完全露出后右滑松手 → 回弹取消；
 * 3. 垃圾桶完全露出后直接松手 → 停住可点垃圾桶或继续左滑删除；
 * 4. 继续左滑条目变淡，超过 DELETE_PX 松手直接删除，否则停住（反悔）。
 */
@Component
export struct PanelSwipeDeleteRow {
  @Prop itemId: string = ''
  @Prop isLast: boolean = false
  /** >=0 时底部分割线从该左偏移起画（对齐文字）；<0 时整行底边框 */
  @Prop dividerLeft: number = -1
  /** 分割线右侧外边距，默认与常见列表行右内边距一致 */
  @Prop dividerRight: number = 16
  @Prop rowBg: ResourceColor = BrowserTheme.PANEL_BG
  @Link openRowId: string
  @Link dragRowId: string
  @Link dragOffsetX: number
  onDelete?: (id: string) => void
  onRowClick?: () => void
  onLongPress?: () => void
  /** 可选：供长按菜单测量前景行位置 */
  rowMeasureId: string = ''
  @BuilderParam row: () => void

  private gestureStartOffset: number = 0
  private lastPanOffsetX: number = 0
  private reachedReveal: boolean = false
  private wasClosingRight: boolean = false
  private suppressRowClick: boolean = false

  private isDragging(): boolean {
    return this.dragRowId === this.itemId
  }

  private isOpen(): boolean {
    return this.openRowId === this.itemId
  }

  private rowOffset(): number {
    if (this.isDragging()) {
      return this.dragOffsetX
    }
    if (this.isOpen()) {
      return -PanelSwipeDeleteConfig.REVEAL_PX
    }
    return 0
  }

  private trashReveal(): number {
    const abs = Math.min(PanelSwipeDeleteConfig.REVEAL_PX, Math.abs(this.rowOffset()))
    return abs / PanelSwipeDeleteConfig.REVEAL_PX
  }

  private foregroundOpacity(): number {
    const abs = Math.abs(this.rowOffset())
    if (abs <= PanelSwipeDeleteConfig.REVEAL_PX) {
      return 1
    }
    const span = PanelSwipeDeleteConfig.DELETE_PX - PanelSwipeDeleteConfig.REVEAL_PX
    const t = Math.min(1, (abs - PanelSwipeDeleteConfig.REVEAL_PX) / span)
    return Math.max(0.42, 1 - t * 0.58)
  }

  private resetSwipeState(): void {
    this.openRowId = ''
    this.dragRowId = ''
    this.dragOffsetX = 0
  }

  private closeOtherRows(): void {
    if (this.openRowId.length > 0 && this.openRowId !== this.itemId) {
      this.openRowId = ''
    }
    if (this.dragRowId.length > 0 && this.dragRowId !== this.itemId) {
      this.dragRowId = ''
      this.dragOffsetX = 0
    }
  }

  private springClose(): void {
    animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
      this.resetSwipeState()
    })
  }

  private snapOpen(): void {
    animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.openRowId = this.itemId
      this.dragRowId = ''
      this.dragOffsetX = 0
    })
  }

  private settleGestureEnd(): void {
    if (this.dragRowId !== this.itemId) {
      return
    }
    const off = this.dragOffsetX
    const cfg = PanelSwipeDeleteConfig

    if (off <= -cfg.DELETE_PX) {
      this.resetSwipeState()
      this.onDelete?.(this.itemId)
      return
    }

    if (this.wasClosingRight && this.reachedReveal && off > -cfg.REVEAL_PX) {
      this.springClose()
      return
    }

    if (off <= -cfg.REVEAL_PX) {
      this.snapOpen()
      return
    }

    this.springClose()
  }

  private onTrashTap(): void {
    if (!this.isOpen() && Math.abs(this.rowOffset()) < PanelSwipeDeleteConfig.REVEAL_PX * 0.85) {
      return
    }
    this.resetSwipeState()
    this.onDelete?.(this.itemId)
  }

  @Builder
  TrashAction() {
    Column() {
      TrashClearIcon({ color: '#0A59F7' })
    }
    .width(20)
    .height(20)
    .justifyContent(FlexAlign.Center)
    .opacity(this.trashReveal())
    .scale({
      x: 0.55 + this.trashReveal() * 0.45,
      y: 0.55 + this.trashReveal() * 0.45
    })
    .onClick(() => this.onTrashTap())
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Blank().layoutWeight(1)
        Row()
          .width(PanelSwipeDeleteConfig.REVEAL_PX)
          .backgroundColor(this.rowBg)
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.None)

      Row() {
        Column() {
          this.row()
          if (!this.isLast && this.dividerLeft >= 0) {
            Divider()
              .color(BrowserTheme.BORDER)
              .strokeWidth(1)
              .margin({ left: this.dividerLeft, right: this.dividerRight })
          }
        }
        .width('100%')
      }
      .id(this.rowMeasureId.length > 0 ? this.rowMeasureId : `swipe_row_${this.itemId}`)
      .width('100%')
      .backgroundColor(this.rowBg)
      .opacity(this.foregroundOpacity())
      .border(this.isLast || this.dividerLeft >= 0 ? undefined : { width: { bottom: 1 }, color: BrowserTheme.BORDER })
      .offset({ x: this.rowOffset() })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture({
            direction: PanDirection.Horizontal,
            distance: PanelSwipeDeleteConfig.ACTIVATE_PX
          })
            .onActionStart(() => {
              this.closeOtherRows()
              this.suppressRowClick = false
              this.reachedReveal = this.isOpen()
              this.wasClosingRight = false
              this.lastPanOffsetX = 0
              this.dragRowId = this.itemId
              this.gestureStartOffset = this.isOpen() ? -PanelSwipeDeleteConfig.REVEAL_PX : 0
              if (!this.isOpen()) {
                this.openRowId = ''
              }
              this.dragOffsetX = this.gestureStartOffset
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.dragRowId !== this.itemId) {
                return
              }
              if (Math.abs(event.offsetX) > PanelSwipeDeleteConfig.ACTIVATE_PX) {
                this.suppressRowClick = true
              }
              if (event.offsetX > this.lastPanOffsetX + 0.5) {
                this.wasClosingRight = true
              }
              this.lastPanOffsetX = event.offsetX
              let next = this.gestureStartOffset + event.offsetX
              if (next > 0) {
                next = 0
              }
              if (next < -PanelSwipeDeleteConfig.MAX_DRAG_PX) {
                next = -PanelSwipeDeleteConfig.MAX_DRAG_PX
              }
              if (Math.abs(next) >= PanelSwipeDeleteConfig.REVEAL_PX) {
                this.reachedReveal = true
              }
              this.dragOffsetX = next
            })
            .onActionEnd(() => {
              this.settleGestureEnd()
            })
            .onActionCancel(() => {
              if (this.dragRowId === this.itemId) {
                this.springClose()
              }
            }),
          LongPressGesture({ repeat: false, duration: 400 })
            .onAction(() => {
              this.resetSwipeState()
              this.onLongPress?.()
            })
        )
      )
      .onClick(() => {
        if (this.suppressRowClick) {
          this.suppressRowClick = false
          return
        }
        if (this.isOpen()) {
          animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.openRowId = ''
          })
          return
        }
        if (this.openRowId.length > 0 && this.openRowId !== this.itemId) {
          this.openRowId = ''
          return
        }
        this.onRowClick?.()
      })

      Row() {
        Blank()
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)
        Row() {
          this.TrashAction()
        }
        .width(PanelSwipeDeleteConfig.REVEAL_PX)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .clip(true)
  }
}
