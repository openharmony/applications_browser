import { BrowserStore } from 'browser_core'
import { BrowserStrings } from 'common'
import { HistoryEntry } from 'browser_core'

/** 批量滑动手势在可见列表中的索引区间 */
interface GestureRangeIndices {
  lo: number
  hi: number
}

/** 批量滑动主方向：未确定 / 向上 / 向下 */
export class HistoryBatchDragDirection {
  static readonly NONE: number = 0
  static readonly UP: number = -1
  static readonly DOWN: number = 1
}

/** 历史记录 ViewModel：批量选择与删除 */
@Observed
export class HistoryViewModel {
  batchMode: boolean = false
  selectedIds: number[] = []
  selectionRevision: number = 0
  deleteTargetIds: number[] = []

  headerTitle(): string {
    if (this.batchMode) {
      return this.selectedIds.length > 0 ?
        BrowserStrings.selectedCount(this.selectedIds.length) :
        BrowserStrings.txt($r('app.string.none_selected'))
    }
    return BrowserStrings.txt($r('app.string.history_title'))
  }

  batchDeleteEnabled(): boolean {
    return this.selectedIds.length >= 1
  }

  isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0
  }

  toggleSelect(id: number): void {
    const next = this.selectedIds.slice()
    const idx = next.indexOf(id)
    if (idx >= 0) {
      next.splice(idx, 1)
    } else {
      next.push(id)
    }
    this.selectedIds = [...next]
    this.selectionRevision++
  }

  /** 计算手势区间：先向下再回拖时排除锚点；先向上拖（如从底部起始）则包含锚点 */
  private computeGestureRangeIndices(
    anchorIdx: number,
    currentIdx: number,
    selectMode: boolean,
    primaryDirection: number
  ): GestureRangeIndices {
    if (selectMode) {
      if (currentIdx >= anchorIdx) {
        const downRange: GestureRangeIndices = { lo: anchorIdx, hi: currentIdx }
        return downRange
      }
      if (primaryDirection === HistoryBatchDragDirection.DOWN) {
        const contractUpRange: GestureRangeIndices = { lo: currentIdx, hi: anchorIdx - 1 }
        return contractUpRange
      }
      const upFromAnchorRange: GestureRangeIndices = { lo: currentIdx, hi: anchorIdx }
      return upFromAnchorRange
    }
    const symmetricRange: GestureRangeIndices = {
      lo: Math.min(anchorIdx, currentIdx),
      hi: Math.max(anchorIdx, currentIdx)
    }
    return symmetricRange
  }

  /** 批量滑动：基于手势起始快照 + 当前区间动态更新（回拖可缩小选中范围） */
  applyGestureRangeSelection(
    anchorId: number,
    currentId: number,
    selectMode: boolean,
    gestureSnapshot: number[],
    visible: HistoryEntry[],
    primaryDirection: number
  ): void {
    const anchorIdx = visible.findIndex((h) => h.id === anchorId)
    const currentIdx = visible.findIndex((h) => h.id === currentId)
    if (anchorIdx < 0 || currentIdx < 0) {
      return
    }
    const range = this.computeGestureRangeIndices(anchorIdx, currentIdx, selectMode, primaryDirection)
    if (range.hi < range.lo) {
      if (selectMode) {
        this.selectedIds = [...gestureSnapshot]
        this.selectionRevision++
      }
      return
    }
    const rangeIds = visible.slice(range.lo, range.hi + 1).map((h) => h.id)
    let next: number[]
    if (selectMode) {
      const merged = new Set<number>(gestureSnapshot)
      rangeIds.forEach((id) => merged.add(id))
      next = Array.from(merged)
    } else {
      const removeSet = new Set<number>(rangeIds)
      next = gestureSnapshot.filter((id) => !removeSet.has(id))
    }
    this.selectedIds = [...next]
    this.selectionRevision++
  }

  toggleSelectAll(visible: HistoryEntry[]): void {
    const all = visible.length > 0 && visible.every((h) => this.selectedIds.includes(h.id))
    this.selectedIds = all ? [] : visible.map((h) => h.id)
    this.selectionRevision++
  }

  enterBatchMode(): void {
    this.batchMode = true
    this.selectionRevision++
  }

  enterBatchWithItem(id: number): void {
    this.batchMode = true
    this.toggleSelect(id)
  }

  openDeleteConfirm(ids: number[]): void {
    this.deleteTargetIds = ids.slice()
  }

  prepareBatchDeleteConfirm(): void {
    this.deleteTargetIds = []
  }

  resolveDeleteIds(): number[] {
    return this.deleteTargetIds.length > 0 ? this.deleteTargetIds.slice() : this.selectedIds.slice()
  }

  /** 确认删除（批量 / 左滑 / 长按） */
  confirmDelete(): void {
    const ids = this.resolveDeleteIds()
    if (ids.length === 0) {
      this.deleteTargetIds = []
      return
    }
    const clearedBatchSelection = this.deleteTargetIds.length === 0
    void BrowserStore.deleteHistory(ids).then(() => {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.deleted')))
    })
    if (clearedBatchSelection) {
      this.selectedIds = []
    }
    this.deleteTargetIds = []
  }

  exitBatchMode(): void {
    this.batchMode = false
    this.selectedIds = []
    this.selectionRevision++
  }
}
