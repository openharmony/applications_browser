import { BrowserStore } from 'browser_core'
import { BrowserStrings } from 'common'
import { DownloadEntry } from 'browser_core'

/** 批量滑动手势在可见列表中的索引区间 */
interface GestureRangeIndices {
  lo: number
  hi: number
}

/** 批量滑动主方向：未确定 / 向上 / 向下（对齐历史/书签） */
export class DownloadBatchDragDirection {
  static readonly NONE: number = 0
  static readonly UP: number = -1
  static readonly DOWN: number = 1
}

/** 下载管理 ViewModel：批量选择、删除确认等业务状态 */
@Observed
export class DownloadsViewModel {
  batchMode: boolean = false
  selectedIds: string[] = []
  selectionRevision: number = 0
  deleteTargetIds: string[] = []

  headerTitle(): string {
    if (this.batchMode) {
      return this.selectedIds.length > 0 ?
        BrowserStrings.selectedCount(this.selectedIds.length) :
        BrowserStrings.txt($r('app.string.none_selected'))
    }
    return BrowserStrings.txt($r('app.string.download_manage'))
  }

  batchDeleteEnabled(): boolean {
    return this.selectedIds.length > 0
  }

  isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0
  }

  toggleSelect(id: string): void {
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

  toggleSelectAll(visible: DownloadEntry[]): void {
    const all = visible.length > 0 && visible.every((d) => this.selectedIds.includes(d.id))
    this.selectedIds = all ? [] : visible.map((d) => d.id)
    this.selectionRevision++
  }

  /** 计算手势区间：先向下再回拖时排除锚点；先向上拖则包含锚点 */
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
      if (primaryDirection === DownloadBatchDragDirection.DOWN) {
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
    anchorId: string,
    currentId: string,
    selectMode: boolean,
    gestureSnapshot: string[],
    visible: DownloadEntry[],
    primaryDirection: number
  ): void {
    const anchorIdx = visible.findIndex((d) => d.id === anchorId)
    const currentIdx = visible.findIndex((d) => d.id === currentId)
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
    const rangeIds = visible.slice(range.lo, range.hi + 1).map((d) => d.id)
    let next: string[]
    if (selectMode) {
      const merged = new Set<string>(gestureSnapshot)
      rangeIds.forEach((id) => merged.add(id))
      next = Array.from(merged)
    } else {
      const removeSet = new Set<string>(rangeIds)
      next = gestureSnapshot.filter((id) => !removeSet.has(id))
    }
    this.selectedIds = [...next]
    this.selectionRevision++
  }

  enterBatchMode(): void {
    this.batchMode = true
    this.selectionRevision++
  }

  enterBatchWithItem(id: string): void {
    this.batchMode = true
    this.toggleSelect(id)
  }

  openDeleteDialog(ids: string[]): void {
    this.deleteTargetIds = ids.slice()
  }

  prepareBatchDeleteConfirm(): void {
    this.deleteTargetIds = []
  }

  clearDeleteTargets(): void {
    this.deleteTargetIds = []
  }

  async finishDelete(deleteLocal: boolean): Promise<string> {
    const targets = this.deleteTargetIds.slice()
    await Promise.all(targets.map((id) => BrowserStore.removeDownload(id, deleteLocal)))
    this.selectedIds = this.selectedIds.filter((id) => !targets.includes(id))
    this.deleteTargetIds = []
    return deleteLocal ?
      BrowserStrings.txt($r('app.string.delete_download_local')) :
      BrowserStrings.txt($r('app.string.delete_download_task_only'))
  }

  exitBatchMode(): void {
    this.batchMode = false
    this.selectedIds = []
    this.selectionRevision++
  }
}
