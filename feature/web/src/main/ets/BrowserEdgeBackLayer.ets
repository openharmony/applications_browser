import { AppStorageKeys } from 'common'
import { BrowserLog } from 'common'

/** 边缘侧滑方向 */
export type EdgeSwipeDirection = 'left' | 'right'

/** 边缘侧滑返回：5vp 起跟手，松手无回退即提交 */
@Component
export struct BrowserEdgeBackLayer {
  /** 有符号跟手位移（左缘右滑为正、右缘左滑为负） */
  @Link swipeOffsetX: number
  layerEnabled: boolean = true
  canSwipe: () => boolean = () => true
  onEdgeDragStart?: (direction: EdgeSwipeDirection) => void
  onEdgeDragUpdate?: (offsetX: number, progress: number) => void
  onEdgeDragCancel?: () => void
  onEdgeDragCommit?: (offsetX: number, direction: EdgeSwipeDirection) => void

  private static readonly EDGE_WIDTH: number = 88
  /** PanGesture 激活距离 5vp */
  private static readonly ACTIVATE_DISTANCE_VP: number = 5
  /** 最小有效侧滑（约 5vp 量级，松手判定用） */
  private static readonly MIN_SWIPE_COMMIT_PX: number = 18
  /** 峰值回缩低于该比例视为「手指回退」撤销 */
  private static readonly RETREAT_PEAK_RATIO: number = 0.55
  private static readonly MAX_DRAG_RATIO: number = 1

  @StorageLink(AppStorageKeys.WINDOW_WIDTH) windowWidth: number = 360
  private gestureLocked: boolean = false
  private activeDirection: EdgeSwipeDirection = 'left'
  private peakAbsOffset: number = 0
  private lastAbsOffset: number = 0

  private maxDrag(): number {
    return this.windowWidth * BrowserEdgeBackLayer.MAX_DRAG_RATIO
  }

  private dragProgress(absOffset: number): number {
    if (this.windowWidth <= 0) {
      return 0
    }
    return Math.min(1, absOffset / this.windowWidth)
  }

  private applyDrag(raw: number, direction: EdgeSwipeDirection): void {
    if (!this.layerEnabled || this.gestureLocked || !this.canSwipe()) {
      return
    }
    this.activeDirection = direction
    const max = this.maxDrag()
    const offset = direction === 'left' ?
      Math.max(0, Math.min(raw, max)) :
      Math.min(0, Math.max(raw, -max))
    this.swipeOffsetX = offset
    const abs = Math.abs(offset)
    this.peakAbsOffset = Math.max(this.peakAbsOffset, abs)
    this.lastAbsOffset = abs
    this.onEdgeDragUpdate?.(offset, this.dragProgress(abs))
  }

  private resetTracking(): void {
    this.peakAbsOffset = 0
    this.lastAbsOffset = 0
  }

  /** 松手：未达最小位移或相对峰值明显回缩 → 撤销；否则提交 */
  private finishDrag(offset: number, direction: EdgeSwipeDirection): void {
    if (!this.layerEnabled || this.gestureLocked) {
      return
    }
    const absOffset = Math.abs(offset)
    const retreated = this.peakAbsOffset >= BrowserEdgeBackLayer.MIN_SWIPE_COMMIT_PX &&
      absOffset < this.peakAbsOffset * BrowserEdgeBackLayer.RETREAT_PEAK_RATIO
    if (absOffset < BrowserEdgeBackLayer.MIN_SWIPE_COMMIT_PX || retreated) {
      BrowserLog.info(`[EdgeSwipe] cancel offset=${absOffset.toFixed(0)} peak=${this.peakAbsOffset.toFixed(0)} ` +
        `retreated=${retreated}`)
      this.onEdgeDragCancel?.()
      this.resetTracking()
      return
    }
    this.gestureLocked = true
    BrowserLog.info(`[EdgeSwipe] commit dir=${direction} offset=${absOffset.toFixed(0)} peak=${this.peakAbsOffset.toFixed(0)}`)
    this.onEdgeDragCommit?.(offset, direction)
    this.resetTracking()
  }

  @Link @Watch('onUnlockSignal') unlockRev: number

  private onUnlockSignal(): void {
    this.releaseGestureLock()
  }

  releaseGestureLock(): void {
    this.gestureLocked = false
    this.swipeOffsetX = 0
  }

  @Builder
  LeftEdgeZone() {
    Column()
      .width(BrowserEdgeBackLayer.EDGE_WIDTH)
      .height('100%')
      .hitTestBehavior(this.layerEnabled ? HitTestMode.Default : HitTestMode.None)
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: BrowserEdgeBackLayer.ACTIVATE_DISTANCE_VP })
          .onActionStart(() => {
            if (!this.canSwipe()) {
              return
            }
            this.activeDirection = 'left'
            this.resetTracking()
            this.onEdgeDragStart?.('left')
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event.offsetX > 0) {
              this.applyDrag(event.offsetX, 'left')
            }
          })
          .onActionEnd((event: GestureEvent) => {
            this.finishDrag(Math.max(0, event.offsetX), 'left')
          })
          .onActionCancel(() => {
            this.onEdgeDragCancel?.()
            this.resetTracking()
          })
      )
  }

  @Builder
  RightEdgeZone() {
    Column()
      .width(BrowserEdgeBackLayer.EDGE_WIDTH)
      .height('100%')
      .hitTestBehavior(this.layerEnabled ? HitTestMode.Default : HitTestMode.None)
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: BrowserEdgeBackLayer.ACTIVATE_DISTANCE_VP })
          .onActionStart(() => {
            if (!this.canSwipe()) {
              return
            }
            this.activeDirection = 'right'
            this.resetTracking()
            this.onEdgeDragStart?.('right')
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event.offsetX < 0) {
              this.applyDrag(event.offsetX, 'right')
            }
          })
          .onActionEnd((event: GestureEvent) => {
            this.finishDrag(Math.min(0, event.offsetX), 'right')
          })
          .onActionCancel(() => {
            this.onEdgeDragCancel?.()
            this.resetTracking()
          })
      )
  }

  build() {
    Stack() {
      Stack({ alignContent: Alignment.TopStart }) {
        this.LeftEdgeZone()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)

      Stack({ alignContent: Alignment.TopEnd }) {
        this.RightEdgeZone()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
