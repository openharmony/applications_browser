import { BrowserStore } from 'browser_core'
import { BrowserStrings } from 'common'
import { BookmarkEntry } from 'browser_core'

/** 批量滑动手势在可见列表中的索引区间 */
interface GestureRangeIndices {
  lo: number
  hi: number
}

/** 批量滑动主方向：未确定 / 向上 / 向下（对齐 HistoryBatchDragDirection） */
export class BookmarkBatchDragDirection {
  static readonly NONE: number = 0
  static readonly UP: number = -1
  static readonly DOWN: number = 1
}

/** 书签 ViewModel：批量选择、移动、删除 */
@Observed
export class BookmarksViewModel {
  batchMode: boolean = false
  selectedIds: string[] = []
  selectionRevision: number = 0
  deleteTargetIds: string[] = []

  headerTitle(currentFolderId: string, folderName: string): string {
    if (this.batchMode) {
      return this.selectedIds.length > 0 ?
        BrowserStrings.selectedCount(this.selectedIds.length) :
        BrowserStrings.txt($r('app.string.none_selected'))
    }
    if (currentFolderId.length > 0) {
      return folderName
    }
    return BrowserStrings.txt($r('app.string.bookmarks'))
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

  toggleSelectAll(visibleIds: string[]): void {
    const all = visibleIds.length > 0 && visibleIds.every((id) => this.selectedIds.includes(id))
    this.selectedIds = all ? [] : visibleIds.slice()
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
      if (primaryDirection === BookmarkBatchDragDirection.DOWN) {
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
    visibleIds: string[],
    primaryDirection: number
  ): void {
    const anchorIdx = visibleIds.indexOf(anchorId)
    const currentIdx = visibleIds.indexOf(currentId)
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
    const rangeIds = visibleIds.slice(range.lo, range.hi + 1)
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

  batchMoveEnabled(): boolean {
    return this.selectedIds.length >= 1
  }

  batchEditEnabled(): boolean {
    return this.selectedIds.length === 1
  }

  batchDeleteEnabled(_bookmarks: BookmarkEntry[]): boolean {
    return this.selectedIds.length >= 1
  }

  openDeleteConfirm(ids: string[]): void {
    this.deleteTargetIds = ids.slice()
  }

  async confirmDelete(bookmarksEmpty: boolean): Promise<void> {
    const ids = this.deleteTargetIds.slice()
    if (ids.length === 0) {
      return
    }
    await BrowserStore.deleteBookmarks(ids)
    this.selectedIds = this.selectedIds.filter((id) => !ids.includes(id))
    if (bookmarksEmpty) {
      this.batchMode = false
    }
    this.deleteTargetIds = []
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.deleted')))
  }

  exitBatchMode(): void {
    this.batchMode = false
    this.selectedIds = []
    this.selectionRevision++
  }
}
