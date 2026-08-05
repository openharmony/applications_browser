import { BrowserStrings } from 'common'
import { BrowserLog } from 'common'
import { getBrowserUIContext } from 'common'
import { BrowserNavigation } from 'browser_core'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import {
  BOOKMARK_LIMIT,
  BOOKMARK_ROOT_FOLDER,
  BookmarkEntry,
  createBookmarkItem,
  CreateBookmarkItemInput
} from 'browser_core'
import { AppStorageKeys } from 'common'
import { PanelConfirmDialog } from 'commons'
import { PanelBatchCheck } from 'commons'
import { PanelMenuItem, PanelPopoverMenu, PanelSubpageHeader, PanelCircleIconButton, PanelHeaderStyle } from 'commons'
import { PanelSwipeDeleteRow } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'
import { BookmarksViewModel, BookmarkBatchDragDirection } from './BookmarksViewModel'
import { FeaturePanelBackBridge } from 'browser_core'
import { BookmarkFolderPickRow, BookmarkFolderTree } from 'common'
import { FolderExpandChevron, NavChevronRight, HistorySiteIcon } from 'commons'

/** ???????????????????vp? */
interface BookmarkRowHitArea {
  topVp: number
  bottomVp: number
}

/** 书签批量底栏按钮：图标 + 文案，@Prop 驱动 disabled 即时刷新 */
@Component
struct BookmarkBatchBtn {
  @Prop label: string = ''
  /** move / delete / select_all / edit */
  @Prop iconKind: string = 'select_all'
  @Prop disabled: boolean = false
  @Prop danger: boolean = false
  onTap?: () => void

  private iconRes(): Resource {
    if (this.iconKind === 'move') {
      return $r('sys.symbol.arrow_right_folder_circle')
    }
    if (this.iconKind === 'edit') {
      return $r('sys.symbol.square_and_pencil')
    }
    if (this.iconKind === 'delete') {
      return $r('sys.symbol.trash')
    }
    return $r('sys.symbol.checkmark_square_on_square')
  }

  private tint(): ResourceColor {
    if (this.disabled) {
      return $r('sys.color.ohos_id_color_text_tertiary')
    }
    if (this.danger) {
      return $r('sys.color.ohos_id_color_warning')
    }
    return $r('sys.color.ohos_id_color_text_primary')
  }

  build() {
    Column({ space: 4 }) {
      SymbolGlyph(this.iconRes())
        .fontSize(22)
        .fontColor([this.tint()])
        .fontWeight(FontWeight.Medium)
        .width(24)
        .height(24)
      Text(this.label)
        .fontSize(11)
        .fontColor(this.tint())
        .maxLines(1)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.disabled ? 0.45 : 1)
    .enabled(!this.disabled)
    .onClick(() => {
      if (!this.disabled) {
        this.onTap?.()
      }
    })
  }
}

@Component
export struct BookmarksPanel {
  @StorageLink('browser_bookmarks') bookmarks: BookmarkEntry[] = []
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  @StorageProp(AppStorageKeys.SAFE_AREA_BOTTOM) safeAreaBottom: number = 0
  @State currentFolderId: string = ''
  @State vm: BookmarksViewModel = new BookmarksViewModel()
  @State searchVisible: boolean = false
  @State searchFilter: string = ''
  @State showPlusMenu: boolean = false
  @State showNewBookmark: boolean = false
  @State showNewFolder: boolean = false
  @State showMovePicker: boolean = false
  @State showDeleteConfirm: boolean = false
  @State showLimitDialog: boolean = false
  @State newBookmarkName: string = ''
  @State newBookmarkUrl: string = 'https://'
  @State newFolderName: string = ''
  @State newFolderParent: string = BOOKMARK_ROOT_FOLDER
  @State editingBookmarkId: string = ''
  @State showRenameFolder: boolean = false
  @State editingFolderId: string = ''
  @State renameFolderName: string = ''
  @State renameFolderParent: string = BOOKMARK_ROOT_FOLDER
  @State showLocationPicker: boolean = false
  @State movePickFolder: string = BOOKMARK_ROOT_FOLDER
  @State locationPickFolder: string = BOOKMARK_ROOT_FOLDER
  @State moveCollapsedFolderIds: string[] = []
  @State locationCollapsedFolderIds: string[] = []
  @State moveSourceIds: string[] = []
  @State swipeOpenRowId: string = ''
  @State swipeDragRowId: string = ''
  @State swipeDragOffsetX: number = 0
  @State batchDragActive: boolean = false
  onClose?: () => void
  private static readonly BATCH_CHECK_HIT: number = 44
  private static readonly EDGE_SCROLL_ZONE: number = 72
  private static readonly EDGE_SCROLL_STEP: number = 18
  private static readonly EDGE_SCROLL_INTERVAL: number = 48
  /** 列表卡片相对屏边的左右外间隙 */
  private static readonly LIST_OUTER: number = 8
  /** 列表行左右内边距（分割线右缘与此对齐） */
  private static readonly LIST_H_PAD: number = 12
  private batchDragAnchorId: string = ''
  private batchDragLastId: string = ''
  private batchDragMoved: boolean = false
  private batchDragSelectMode: boolean = true
  private batchDragSnapshot: string[] = []
  private batchDragPrimaryDirection: number = BookmarkBatchDragDirection.NONE
  private bookmarkRowHitAreas: Map<string, BookmarkRowHitArea> = new Map()
  private bookmarkScrollScroller: Scroller = new Scroller()
  private scrollViewportTopVp: number = 0
  private scrollViewportHeightVp: number = 0
  private edgeScrollTimer: number = -1
  private edgeScrollDirection: number = 0
  private batchDragLastTouchY: number = 0

  private closeSwipeRows(): void {
    this.swipeOpenRowId = ''
    this.swipeDragRowId = ''
    this.swipeDragOffsetX = 0
  }

  /** TextInput ????? Toast */
  private applyInputChange(value: string, prev: string, setter: (text: string) => void, isUrl: boolean = false): void {
    BrowserNavigation.applyTextInputChange(value, prev.length, setter, isUrl)
  }

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  /** 点击列表区域时结束搜索输入焦点（键盘收起由系统处理） */
  private exitSearchInput(): void {
    if (!this.searchVisible) {
      return
    }
  }

  private closeSearchMode(): void {
    this.searchVisible = false
    this.searchFilter = ''
  }

  private plusMenuItems(): PanelMenuItem[] {
    return [
      {
        label: $r('app.string.edit'),
        iconKind: 'edit',
        onTap: () => {
          this.showPlusMenu = false
          this.enterBatchMode('more-menu-edit')
        }
      },
      {
        label: $r('app.string.new_folder'),
        iconKind: 'folder',
        onTap: () => {
          this.showPlusMenu = false
          this.newFolderName = BrowserStrings.newFolder()
          this.newFolderParent = this.isRoot() ? BOOKMARK_ROOT_FOLDER : this.currentFolderId
          this.showNewFolder = true
        }
      }
    ]
  }

  aboutToAppear(): void {
    if (this.newBookmarkName === '') {
      this.newBookmarkName = BrowserStrings.newBookmark()
    }
    if (this.newFolderName === '') {
      this.newFolderName = BrowserStrings.newFolder()
    }
    FeaturePanelBackBridge.register((): boolean => {
      this.handleBack()
      return true
    })
  }

  aboutToDisappear(): void {
    FeaturePanelBackBridge.unregister()
  }

  private isRoot(): boolean {
    return this.currentFolderId === ''
  }

  private folderKey(id: string): string {
    return id
  }

  private handleBack(): void {
    this.closeSwipeRows()
    if (this.showRenameFolder) {
      this.closeRenameFolderForm()
      return
    }
    if (this.vm.batchMode) {
      this.resetBatchDragState()
      this.clearBookmarkRowHitAreas()
      this.vm.exitBatchMode()
      return
    }
    if (this.searchVisible) {
      this.closeSearchMode()
      return
    }
    if (!this.isRoot()) {
      this.currentFolderId = BrowserStore.getFolderParentId(this.currentFolderId)
      this.searchFilter = ''
      this.searchVisible = false
      this.vm.selectedIds = []
      return
    }
    this.onClose?.()
  }

  private headerTitle(): string {
    if (this.vm.batchMode) {
      if (this.vm.selectedIds.length === 0) {
        return BrowserStrings.txt($r('app.string.none_selected'))
      }
      return BrowserStrings.selectedCount(this.vm.selectedIds.length)
    }
    if (!this.isRoot()) {
      return BrowserStore.getFolderTitle(this.currentFolderId)
    }
    return BrowserStrings.bookmarkRoot()
  }

  private isSelected(id: string): boolean {
    return this.vm.isSelected(id)
  }

  private toggleSelect(id: string): void {
    this.vm.toggleSelect(id)
    this.logBatchButtonState('toggle')
  }

  private logBatchButtonState(source: string): void {
    if (!this.vm.batchMode) {
      return
    }
    BrowserLog.info(`[BookmarkBatch] ${source} sel=${this.vm.selectedIds.length} ` +
      `move=${this.batchMoveEnabled()} edit=${this.batchEditEnabled()} delete=${this.batchDeleteEnabled()}`)
  }

  private enterBatchMode(source: string): void {
    this.vm.enterBatchMode()
    this.logBatchButtonState(`enter:${source}`)
  }

  private resetBatchDragState(): void {
    this.stopBatchEdgeScroll()
    this.batchDragActive = false
    this.batchDragAnchorId = ''
    this.batchDragLastId = ''
    this.batchDragMoved = false
    this.batchDragSelectMode = true
    this.batchDragSnapshot = []
    this.batchDragPrimaryDirection = BookmarkBatchDragDirection.NONE
    this.batchDragLastTouchY = 0
  }

  private stopBatchEdgeScroll(): void {
    if (this.edgeScrollTimer >= 0) {
      clearInterval(this.edgeScrollTimer)
      this.edgeScrollTimer = -1
    }
    this.edgeScrollDirection = 0
  }

  private clearBookmarkRowHitAreas(): void {
    this.bookmarkRowHitAreas.clear()
  }

  private bookmarkRowMeasureId(id: string): string {
    return `bookmark_batch_row_${id}`
  }

  /** ???????????? id???? + ??? */
  private flatVisibleBatchIds(): string[] {
    const ids: string[] = []
    if (!this.searchFilter.trim()) {
      for (const folderId of this.getFolderRows()) {
        ids.push(this.folderKey(folderId))
      }
    }
    for (const item of this.visibleBookmarks()) {
      ids.push(item.id)
    }
    return ids
  }

  private currentBookmarkScrollY(): number {
    return this.bookmarkScrollScroller.currentOffset()?.yOffset ?? 0
  }

  private touchViewportYVp(touch: TouchObject): number {
    return this.touchGlobalYVp(touch) - this.scrollViewportTopVp
  }

  /** ????? Y?vp??? onAreaChange.globalPosition ????? */
  private touchGlobalYVp(touch: TouchObject): number {
    const displayY = touch.displayY as number | undefined
    if (displayY !== undefined && displayY > 0) {
      return displayY
    }
    const uiCtx = getBrowserUIContext()
    const screenY = touch.screenY as number
    if (uiCtx && screenY > 0) {
      return uiCtx.px2vp(screenY)
    }
    return touch.y as number
  }

  private updateBookmarkRowHitArea(itemId: string, area: Area): void {
    if (!this.vm.batchMode) {
      return
    }
    const globalPos = area.globalPosition
    if (!globalPos) {
      return
    }
    const topVp = globalPos.y as number
    const heightVp = area.height as number
    if (heightVp <= 0) {
      return
    }
    this.bookmarkRowHitAreas.set(itemId, {
      topVp,
      bottomVp: topVp + heightVp
    })
  }

  private findBookmarkRowAtTouchY(touchY: number): string | null {
    let bestId: string | null = null
    let bestHeight = Number.MAX_VALUE
    for (const id of this.flatVisibleBatchIds()) {
      const hit = this.bookmarkRowHitAreas.get(id)
      if (!hit) {
        continue
      }
      if (touchY >= hit.topVp && touchY < hit.bottomVp) {
        const heightVp = hit.bottomVp - hit.topVp
        if (heightVp < bestHeight) {
          bestHeight = heightVp
          bestId = id
        }
      }
    }
    return bestId
  }

  /** ??????????????????/???? */
  private findBookmarkRowForBatchDrag(touch: TouchObject): string | null {
    const touchY = this.touchGlobalYVp(touch)
    this.batchDragLastTouchY = touchY
    const direct = this.findBookmarkRowAtTouchY(touchY)
    if (direct || !this.batchDragActive) {
      return direct
    }
    const fingerVp = touchY - this.scrollViewportTopVp
    const viewH = this.scrollViewportHeightVp
    const ids = this.flatVisibleBatchIds()
    if (fingerVp < BookmarksPanel.EDGE_SCROLL_ZONE) {
      for (const id of ids) {
        const hit = this.bookmarkRowHitAreas.get(id)
        if (hit && hit.bottomVp > this.scrollViewportTopVp) {
          return id
        }
      }
    } else if (fingerVp > viewH - BookmarksPanel.EDGE_SCROLL_ZONE) {
      for (let i = ids.length - 1; i >= 0; i--) {
        const hit = this.bookmarkRowHitAreas.get(ids[i])
        if (hit && hit.topVp < this.scrollViewportTopVp + viewH) {
          return ids[i]
        }
      }
    }
    return null
  }

  private extendBatchDragAtTouchY(touchY: number): void {
    const rowId = this.findBookmarkRowAtTouchY(touchY)
    if (rowId) {
      this.extendBatchDragToRow(rowId)
    }
  }

  private updateBatchEdgeAutoScroll(touch: TouchObject): void {
    if (!this.batchDragActive) {
      this.stopBatchEdgeScroll()
      return
    }
    const fingerVp = this.touchViewportYVp(touch)
    const viewH = this.scrollViewportHeightVp
    const scrollY = this.currentBookmarkScrollY()
    if (fingerVp < BookmarksPanel.EDGE_SCROLL_ZONE) {
      if (scrollY > 1) {
        this.startBatchEdgeScroll(-1)
      } else {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
      }
      return
    }
    if (fingerVp > viewH - BookmarksPanel.EDGE_SCROLL_ZONE) {
      this.startBatchEdgeScroll(1)
      return
    }
    this.stopBatchEdgeScroll()
  }

  private startBatchEdgeScroll(direction: number): void {
    if (this.edgeScrollTimer >= 0 && this.edgeScrollDirection === direction) {
      return
    }
    this.stopBatchEdgeScroll()
    this.edgeScrollDirection = direction
    this.edgeScrollTimer = setInterval(() => {
      const current = this.currentBookmarkScrollY()
      if (direction < 0 && current <= 0) {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
        return
      }
      const next = Math.max(0, current + direction * BookmarksPanel.EDGE_SCROLL_STEP)
      if (next === current) {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
        return
      }
      this.bookmarkScrollScroller.scrollTo({ xOffset: 0, yOffset: next, animation: false })
      this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
    }, BookmarksPanel.EDGE_SCROLL_INTERVAL) as number
  }

  private beginBatchDragOnRow(rowId: string): void {
    this.batchDragActive = true
    this.batchDragMoved = false
    this.batchDragAnchorId = rowId
    this.batchDragLastId = rowId
    this.batchDragSnapshot = this.vm.selectedIds.slice()
    this.batchDragSelectMode = !this.isSelected(rowId)
  }

  private updateBatchDragPrimaryDirection(rowId: string): void {
    if (this.batchDragPrimaryDirection !== BookmarkBatchDragDirection.NONE) {
      return
    }
    const items = this.flatVisibleBatchIds()
    const anchorIdx = items.indexOf(this.batchDragAnchorId)
    const currentIdx = items.indexOf(rowId)
    if (anchorIdx < 0 || currentIdx < 0 || currentIdx === anchorIdx) {
      return
    }
    if (currentIdx > anchorIdx) {
      this.batchDragPrimaryDirection = BookmarkBatchDragDirection.DOWN
    } else {
      this.batchDragPrimaryDirection = BookmarkBatchDragDirection.UP
    }
  }

  private extendBatchDragToRow(rowId: string): void {
    if (rowId === this.batchDragLastId) {
      return
    }
    this.batchDragMoved = true
    this.updateBatchDragPrimaryDirection(rowId)
    this.batchDragLastId = rowId
    this.vm.applyGestureRangeSelection(
      this.batchDragAnchorId,
      rowId,
      this.batchDragSelectMode,
      this.batchDragSnapshot,
      this.flatVisibleBatchIds(),
      this.batchDragPrimaryDirection
    )
  }

  /** ?????????????????????/????????????? */
  private onBatchCheckTouch(rowId: string, event: TouchEvent): void {
    if (!this.vm.batchMode) {
      return
    }
    const touch = event.touches[0] ?? event.changedTouches[0]
    if (!touch) {
      return
    }
    if (event.type === TouchType.Down) {
      this.beginBatchDragOnRow(rowId)
      this.batchDragLastTouchY = this.touchGlobalYVp(touch)
      return
    }
    if (!this.batchDragActive) {
      return
    }
    if (event.type === TouchType.Move) {
      this.updateBatchEdgeAutoScroll(touch)
      const hitId = this.findBookmarkRowForBatchDrag(touch)
      if (!hitId) {
        return
      }
      this.extendBatchDragToRow(hitId)
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (!this.batchDragMoved && this.batchDragAnchorId.length > 0) {
        this.toggleSelect(this.batchDragAnchorId)
      }
      this.resetBatchDragState()
    }
  }

  private isFolderRowLast(index: number): boolean {
    const folderCount = this.getFolderRows().length
    return index === folderCount - 1 && this.visibleBookmarks().length === 0
  }

  private isBookmarkRowLast(index: number): boolean {
    return index === this.visibleBookmarks().length - 1
  }

  private bookmarksInFolderLocal(parentId: string): BookmarkEntry[] {
    const pid = parentId || BOOKMARK_ROOT_FOLDER
    return this.bookmarks
      .filter((b) => (b.parentId || BOOKMARK_ROOT_FOLDER) === pid)
      .sort((a, b) => a.sortOrder - b.sortOrder)
  }

  private visibleBookmarks(): BookmarkEntry[] {
    let items = this.bookmarksInFolderLocal(this.currentFolderId).filter((b) => !b.isFolder)
    const q = this.searchFilter.trim().toLowerCase()
    if (q) {
      items = items.filter((b) => b.title.toLowerCase().includes(q) || b.url.toLowerCase().includes(q))
    }
    return items
  }

  private selectableIds(): string[] {
    const ids: string[] = []
    if (this.searchFilter.trim()) {
      return this.visibleBookmarks().map((b) => b.id)
    }
    if (!this.isRoot()) {
      this.bookmarksInFolderLocal(this.currentFolderId).forEach((b) => ids.push(b.id))
      return ids
    }
    this.bookmarksInFolderLocal(BOOKMARK_ROOT_FOLDER).forEach((b) => ids.push(b.id))
    if (this.vm.batchMode) {
      this.bookmarks.filter((b) => b.isFolder).forEach((f) => ids.push(this.folderKey(f.id)))
    }
    return ids
  }

  private getFolderRows(): string[] {
    if (this.searchFilter.trim()) {
      return []
    }
    if (this.isRoot()) {
      return this.bookmarksInFolderLocal(BOOKMARK_ROOT_FOLDER)
        .filter((b) => b.isFolder)
        .map((f) => f.id)
    }
    return this.bookmarksInFolderLocal(this.currentFolderId)
      .filter((b) => b.isFolder)
      .map((e) => e.id)
  }

  private isCurrentFolderEmpty(): boolean {
    return this.getFolderRows().length === 0 && this.visibleBookmarks().length === 0
  }

  /** 编辑态可拖拽排序的同层条目（按 sortOrder） */
  private batchReorderItems(): BookmarkEntry[] {
    if (this.searchFilter.trim()) {
      return this.visibleBookmarks()
    }
    return this.bookmarksInFolderLocal(this.currentFolderId)
  }

  private onBatchListReorder(from: number, to: number): void {
    if (from === to) {
      return
    }
    void BrowserStore.reorderBookmarksInFolder(this.currentFolderId, from, to)
  }

  build() {
    Stack() {
      Column() {
        this.PanelHeader()

        if (this.vm.batchMode && !this.searchFilter.trim()) {
          this.BatchReorderList()
        } else {
          this.NormalScrollList()
        }

        if (this.vm.batchMode) {
          this.BatchBar()
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .backgroundColor(BrowserTheme.SURFACE)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.showPlusMenu) {
        PanelPopoverMenu({
          visible: this.showPlusMenu,
          darkMode: this.isDark(),
          items: this.plusMenuItems(),
          onDismiss: () => {
            this.showPlusMenu = false
          }
        })
      }
      if (this.showNewBookmark) {
        this.NewBookmarkForm()
      }
      if (this.showNewFolder) {
        this.NewFolderForm()
      }
      if (this.showRenameFolder) {
        this.RenameFolderForm()
      }
      if (this.showMovePicker) {
        this.MovePickerPanel()
      }
      if (this.showLocationPicker) {
        this.LocationPickerPanel()
      }
      if (this.showDeleteConfirm) {
        PanelConfirmDialog({
          message: this.deleteConfirmTitle(),
          subtitle: this.deleteConfirmSubtitle(),
          confirmLabel: BrowserStrings.txt($r('app.string.delete')),
          confirmDanger: true,
          onCancel: () => {
            this.showDeleteConfirm = false
            this.vm.deleteTargetIds = []
          },
          onConfirm: () => this.confirmDelete()
        })
      }
      if (this.showLimitDialog) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.bookmark_limit_title')),
          subtitle: BrowserStrings.bookmarkLimitMessage(BOOKMARK_LIMIT),
          confirmLabel: BrowserStrings.txt($r('app.string.got_it')),
          hideCancel: true,
          confirmDanger: false,
          onConfirm: () => {
            this.showLimitDialog = false
          },
          onCancel: () => {
            this.showLimitDialog = false
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BrowserTheme.SURFACE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  PanelHeader() {
    PanelSubpageHeader({
      title: this.headerTitle(),
      batchMode: this.vm.batchMode,
      darkMode: this.isDark(),
      showSearch: !this.vm.batchMode,
      showMore: !this.vm.batchMode,
      searchExpanded: this.searchVisible && !this.vm.batchMode,
      searchText: this.searchFilter,
      searchPlaceholder: $r('app.string.bookmark_search_placeholder'),
      onBack: () => {
        this.handleBack()
      },
      onSearch: () => {
        if (this.searchVisible) {
          this.closeSearchMode()
        } else {
          this.searchVisible = true
        }
      },
      onSearchChange: (v: string) => {
        this.applyInputChange(v, this.searchFilter, (text: string) => {
          this.searchFilter = text
        })
      },
      onSearchClear: () => {
        this.closeSearchMode()
      },
      onMore: () => {
        this.showPlusMenu = true
      }
    })
  }

  private batchMoveEnabled(): boolean {
    return this.vm.batchMoveEnabled()
  }

  private batchEditEnabled(): boolean {
    return this.vm.batchEditEnabled()
  }

  private batchDeleteEnabled(): boolean {
    return this.vm.batchDeleteEnabled(this.bookmarks)
  }

  /** ????????????? */
  private isInvalidMoveTarget(targetFolderId: string): boolean {
    const candidates = BrowserStore.filterMoveRootCandidates(this.moveSourceIds, this.bookmarks)
    for (const id of candidates) {
      const item = this.bookmarks.find((b) => b.id === id)
      if (item?.isFolder && BrowserStore.isDescendantOf(targetFolderId, id)) {
        return true
      }
    }
    return false
  }

  /** ????????????? */
  private isAlreadyAtMoveTarget(targetFolderId: string): boolean {
    return BrowserStore.isAlreadyAtTarget(this.moveSourceIds, targetFolderId)
  }

  private canConfirmMove(): boolean {
    return !this.isInvalidMoveTarget(this.movePickFolder) &&
      !this.isAlreadyAtMoveTarget(this.movePickFolder)
  }

  private moveTargetFolderIds(): string[] {
    const ids: string[] = [BOOKMARK_ROOT_FOLDER]
    this.bookmarks.filter((b) => b.isFolder).forEach((f) => ids.push(f.id))
    return ids
  }

  private movePickRows(): BookmarkFolderPickRow[] {
    return BookmarkFolderTree.folderPickRows(
      this.bookmarks,
      true,
      BrowserStrings.txt($r('app.string.bookmark_root_dir')),
      this.moveCollapsedFolderIds
    )
  }

  private locationPickRows(): BookmarkFolderPickRow[] {
    return BookmarkFolderTree.folderPickRows(
      this.bookmarks,
      true,
      BrowserStrings.txt($r('app.string.bookmark_root_dir')),
      this.locationCollapsedFolderIds
    )
  }

  private openLocationPickerSheet(): void {
    this.locationPickFolder = this.showRenameFolder ? this.renameFolderParent : this.newFolderParent
    this.locationCollapsedFolderIds = []
    this.showLocationPicker = true
  }

  private confirmLocationPicker(): void {
    if (this.showRenameFolder && this.isInvalidRenameLocation(this.locationPickFolder)) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
      return
    }
    if (this.showRenameFolder) {
      this.renameFolderParent = this.locationPickFolder
    } else {
      this.newFolderParent = this.locationPickFolder
    }
    this.showLocationPicker = false
    this.locationCollapsedFolderIds = []
  }

  private defaultMoveTarget(): string {
    for (const folderId of this.moveTargetFolderIds()) {
      if (!this.isInvalidMoveTarget(folderId) && !BrowserStore.isAlreadyAtTarget(this.moveSourceIds, folderId)) {
        return folderId
      }
    }
    for (const folderId of this.moveTargetFolderIds()) {
      if (!this.isInvalidMoveTarget(folderId)) {
        return folderId
      }
    }
    return BOOKMARK_ROOT_FOLDER
  }

  private openMovePicker(): void {
    this.moveSourceIds = this.vm.selectedIds.slice()
    this.movePickFolder = this.defaultMoveTarget()
    this.moveCollapsedFolderIds = []
    this.showMovePicker = true
  }

  @Builder
  NormalScrollList() {
    Scroll(this.bookmarkScrollScroller) {
      Column() {
        if (this.searchFilter.trim() && this.visibleBookmarks().length === 0) {
          Text($r('app.string.no_search_results'))
            .fontSize(14)
            .fontColor(BrowserTheme.TEXT_MUTED)
            .padding(24)
        } else if (this.isCurrentFolderEmpty()) {
          this.EmptyState()
        } else {
          Column() {
            if (!this.searchFilter.trim()) {
              ForEach(this.getFolderRows(), (folderId: string, index: number) => {
                this.FolderRow(folderId, this.isFolderRowLast(index))
              }, (folderId: string) => {
                const folder = this.bookmarks.find((b) => b.id === folderId)
                return `${folderId}_normal_${this.bookmarks.length}_${folder?.title ?? ''}`
              })
            }
            ForEach(this.visibleBookmarks(), (item: BookmarkEntry, index: number) => {
              this.BookmarkRow(item, this.isBookmarkRowLast(index))
            }, (item: BookmarkEntry) => {
              return `${item.id}_normal_${this.bookmarks.length}_${item.title}`
            })
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .backgroundColor(BrowserTheme.SURFACE)
          .borderRadius(12)
          .clip(true)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: BookmarksPanel.LIST_OUTER,
        right: BookmarksPanel.LIST_OUTER,
        top: 12,
        bottom: BrowserSafeAreaInsets.bottom(0)
      })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(BrowserTheme.SURFACE)
    .onAreaChange((_old, area) => {
      const globalPos = area.globalPosition
      if (globalPos) {
        this.scrollViewportTopVp = globalPos.y as number
      }
      const h = area.height as number
      if (h > 0) {
        this.scrollViewportHeightVp = h
      }
    })
    .onClick(() => {
      this.exitSearchInput()
    })
  }

  /** 编辑态：List + onMove，拖动手柄所在行可拖拽重排 */
  @Builder
  BatchReorderList() {
    if (this.isCurrentFolderEmpty()) {
      Column() {
        this.EmptyState()
      }
      .layoutWeight(1)
      .width('100%')
    } else {
      List({ scroller: this.bookmarkScrollScroller, space: 0 }) {
        ForEach(this.batchReorderItems(), (item: BookmarkEntry, index: number) => {
          ListItem() {
            if (item.isFolder) {
              this.FolderBatchRow(item.id, index === this.batchReorderItems().length - 1)
            } else {
              this.BookmarkBatchRow(item, index === this.batchReorderItems().length - 1)
            }
          }
          .editable(true)
        }, (item: BookmarkEntry) => {
          return `${item.id}_batch_${item.sortOrder}_${item.title}`
        })
          .onMove((from: number, to: number) => {
            this.onBatchListReorder(from, to)
          })
      }
      .layoutWeight(1)
      .width('100%')
      .editMode(true)
      .scrollBar(BarState.Off)
      .backgroundColor(BrowserTheme.SURFACE)
      .borderRadius(12)
      .clip(true)
      .margin({
        left: BookmarksPanel.LIST_OUTER,
        right: BookmarksPanel.LIST_OUTER,
        top: 12
      })
      .padding({ bottom: BrowserSafeAreaInsets.batchBarScrollClearance() })
      .onAreaChange((_old, area) => {
        const globalPos = area.globalPosition
        if (globalPos) {
          this.scrollViewportTopVp = globalPos.y as number
        }
        const h = area.height as number
        if (h > 0) {
          this.scrollViewportHeightVp = h
        }
      })
    }
  }

  @Builder
  EmptyState() {
    Column({ space: 12 }) {
      Image($r('app.media.ic_bookmark'))
        .width(100)
        .height(100)
        .opacity(0.35)
        .objectFit(ImageFit.Contain)
      Text(this.isRoot() ? $r('app.string.no_content') : $r('app.string.shortcut_empty_bookmarks'))
        .fontSize(14)
        .fontColor(BrowserTheme.TEXT_MUTED)
    }
    .width('100%')
    .padding(48)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  FolderRow(folderId: string, isLast: boolean) {
    if (this.vm.batchMode) {
      this.FolderBatchRow(folderId, isLast)
    } else {
      this.FolderNormalRow(folderId, isLast)
    }
  }

  @Builder
  FolderBatchRow(folderId: string, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(20)
          .fontColor([$r('sys.color.ohos_id_color_text_tertiary')])
          .fontWeight(FontWeight.Medium)
          .width(28)
          .height(36)
          .margin({ right: 6 })

        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(BookmarkFolderTree.ICON_SIZE)
          .fontColor([BrowserTheme.PRIMARY_COLOR])
          .margin({ right: BookmarkFolderTree.ICON_GAP })

        Column({ space: 2 }) {
          Text(BrowserStore.getFolderTitle(folderId))
            .fontSize(15)
            .fontColor(BrowserTheme.TEXT)
          Text(BrowserStore.folderItemCountLabel(folderId))
            .fontSize(12)
            .fontColor(BrowserTheme.TEXT_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          PanelBatchCheck({ selected: this.isSelected(this.folderKey(folderId)) })
        }
        .width(BookmarksPanel.BATCH_CHECK_HIT)
        .height(BookmarksPanel.BATCH_CHECK_HIT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.onBatchCheckTouch(this.folderKey(folderId), event)
        })
      }
      .width('100%')
      .padding({
        left: BookmarksPanel.LIST_H_PAD,
        right: BookmarksPanel.LIST_H_PAD,
        top: 14,
        bottom: 14
      })

      if (!isLast) {
        Divider()
          .color(BrowserTheme.BORDER)
          .strokeWidth(1)
          .margin({
            left: BookmarkFolderTree.dividerStartBatchFolder(BookmarksPanel.LIST_H_PAD),
            right: BookmarksPanel.LIST_H_PAD
          })
      }
    }
    .width('100%')
    .backgroundColor(this.isSelected(this.folderKey(folderId)) ?
      BrowserTheme.PRIMARY_LIGHT : BrowserTheme.SURFACE)
    .id(this.bookmarkRowMeasureId(this.folderKey(folderId)))
    .onAreaChange((_old, area) => {
      this.updateBookmarkRowHitArea(this.folderKey(folderId), area)
    })
  }

  @Builder
  FolderNormalRow(folderId: string, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(BookmarkFolderTree.ICON_SIZE)
          .fontColor([BrowserTheme.PRIMARY_COLOR])
          .margin({ right: BookmarkFolderTree.ICON_GAP })

        Column({ space: 2 }) {
          Text(BrowserStore.getFolderTitle(folderId))
            .fontSize(15)
            .fontColor(BrowserTheme.TEXT)
          Text(BrowserStore.folderItemCountLabel(folderId))
            .fontSize(12)
            .fontColor(BrowserTheme.TEXT_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        NavChevronRight({ color: BrowserTheme.TEXT_MUTED, iconSize: 16 })
      }
      .width('100%')
      .padding({
        left: BookmarksPanel.LIST_H_PAD,
        right: BookmarksPanel.LIST_H_PAD,
        top: 14,
        bottom: 14
      })

      if (!isLast) {
        Divider()
          .color(BrowserTheme.BORDER)
          .strokeWidth(1)
          .margin({
            left: BookmarkFolderTree.dividerStart(0, BookmarksPanel.LIST_H_PAD),
            right: BookmarksPanel.LIST_H_PAD
          })
      }
    }
    .width('100%')
    .backgroundColor(BrowserTheme.SURFACE)
    .onClick(() => {
      this.currentFolderId = folderId
    })
    .gesture(
      LongPressGesture().onAction(() => {
        this.enterBatchMode('folder-long-press')
        this.toggleSelect(this.folderKey(folderId))
      })
    )
  }

  @Builder
  BookmarkRow(item: BookmarkEntry, isLast: boolean) {
    if (this.vm.batchMode) {
      this.BookmarkBatchRow(item, isLast)
    } else {
      this.BookmarkNormalRow(item, isLast)
    }
  }

  @Builder
  BookmarkBatchRow(item: BookmarkEntry, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(20)
          .fontColor([$r('sys.color.ohos_id_color_text_tertiary')])
          .fontWeight(FontWeight.Medium)
          .width(28)
          .height(36)
          .margin({ right: 6 })

        HistorySiteIcon({ url: item.url, iconUrl: item.iconUrl })
          .margin({ right: BookmarkFolderTree.ICON_GAP })

        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontColor(this.isSelected(item.id) ? BrowserTheme.PRIMARY_COLOR : BrowserTheme.TEXT)
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

        Column() {
          PanelBatchCheck({ selected: this.isSelected(item.id) })
        }
        .width(BookmarksPanel.BATCH_CHECK_HIT)
        .height(BookmarksPanel.BATCH_CHECK_HIT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.onBatchCheckTouch(item.id, event)
        })
      }
      .width('100%')
      .padding({
        left: BookmarksPanel.LIST_H_PAD,
        right: BookmarksPanel.LIST_H_PAD,
        top: 14,
        bottom: 14
      })

      if (!isLast) {
        Divider()
          .color(BrowserTheme.BORDER)
          .strokeWidth(1)
          .margin({
            left: BookmarkFolderTree.dividerStartBatchSite(BookmarksPanel.LIST_H_PAD),
            right: BookmarksPanel.LIST_H_PAD
          })
      }
    }
    .width('100%')
    .backgroundColor(this.isSelected(item.id) ? BrowserTheme.PRIMARY_LIGHT : BrowserTheme.SURFACE)
    .id(this.bookmarkRowMeasureId(item.id))
    .onAreaChange((_old, area) => {
      this.updateBookmarkRowHitArea(item.id, area)
    })
  }

  @Builder
  BookmarkNormalRow(item: BookmarkEntry, isLast: boolean) {
    PanelSwipeDeleteRow({
      itemId: item.id,
      isLast: isLast,
      dividerLeft: BookmarkFolderTree.dividerStartSite(BookmarksPanel.LIST_H_PAD),
      dividerRight: BookmarksPanel.LIST_H_PAD,
      openRowId: $swipeOpenRowId,
      dragRowId: $swipeDragRowId,
      dragOffsetX: $swipeDragOffsetX,
      onDelete: (id: string) => this.deleteBookmarkById(id),
      onRowClick: () => {
        BrowserNavigation.openBrowse(item.url)
        this.onClose?.()
      },
      onLongPress: () => {
        this.closeSwipeRows()
        this.enterBatchMode('bookmark-long-press')
        this.toggleSelect(item.id)
      },
      row: () => {
        this.BookmarkNormalRowContent(item)
      }
    })
  }

  @Builder
  BookmarkNormalRowContent(item: BookmarkEntry) {
    Row() {
      HistorySiteIcon({ url: item.url, iconUrl: item.iconUrl })
        .margin({ right: BookmarkFolderTree.ICON_GAP })

      Column({ space: 2 }) {
        Text(item.title)
          .fontSize(15)
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
    .width('100%')
    .padding({
      left: BookmarksPanel.LIST_H_PAD,
      right: BookmarksPanel.LIST_H_PAD,
      top: 14,
      bottom: 14
    })
    .backgroundColor(BrowserTheme.SURFACE)
  }

  private openDeleteConfirm(ids: string[]): void {
    if (ids.length === 0) {
      return
    }
    this.closeSwipeRows()
    this.vm.openDeleteConfirm(ids)
    this.showDeleteConfirm = true
  }

  /** 删除确认标题：单文件夹时用专属文案 */
  private deleteConfirmTitle(): string {
    const ids = this.vm.deleteTargetIds.length > 0 ? this.vm.deleteTargetIds : this.vm.selectedIds
    if (ids.length === 1) {
      const item = this.bookmarks.find((b) => b.id === ids[0])
      if (item?.isFolder) {
        return BrowserStrings.txt($r('app.string.delete_folder_confirm'))
      }
    }
    return BrowserStrings.txt($r('app.string.delete_selected_confirm'))
  }

  private deleteConfirmSubtitle(): string {
    const ids = this.vm.deleteTargetIds.length > 0 ? this.vm.deleteTargetIds : this.vm.selectedIds
    if (ids.length === 1) {
      const item = this.bookmarks.find((b) => b.id === ids[0])
      if (item?.isFolder) {
        return BrowserStrings.txt($r('app.string.delete_folder_confirm_hint'))
      }
    }
    return ''
  }

  private deleteBookmarkById(id: string): void {
    if (!id) {
      return
    }
    this.openDeleteConfirm([id])
  }

  @Builder
  BatchBar() {
    // 与浏览页底栏一致：内容行固定高度，底边避让写在外层，避免 padding 挤占图标/文字
    Column() {
      Row() {
        BookmarkBatchBtn({
          label: BrowserStrings.batchActionLabel('move'),
          iconKind: 'move',
          disabled: !this.batchMoveEnabled(),
          onTap: () => {
            this.openMovePicker()
          }
        })
        BookmarkBatchBtn({
          label: BrowserStrings.batchActionLabel('delete'),
          iconKind: 'delete',
          disabled: !this.batchDeleteEnabled(),
          onTap: () => {
            this.vm.deleteTargetIds = []
            this.showDeleteConfirm = true
          }
        })
        BookmarkBatchBtn({
          label: BrowserStrings.batchActionLabel('select_all'),
          iconKind: 'select_all',
          disabled: false,
          onTap: () => {
            this.vm.toggleSelectAll(this.selectableIds())
            this.logBatchButtonState('select_all')
          }
        })
        BookmarkBatchBtn({
          label: BrowserStrings.batchActionLabel('edit'),
          iconKind: 'edit',
          disabled: !this.batchEditEnabled(),
          onTap: () => {
            this.openBookmarkEditForSelection()
          }
        })
      }
      .width('100%')
      .height(BrowserSafeAreaInsets.BATCH_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ bottom: BrowserSafeAreaInsets.batchBarBottomPadding() })
    .backgroundColor(BrowserTheme.SURFACE)
    .border({ width: { top: 1 }, color: BrowserTheme.BORDER })
    .onAppear(() => {
      this.logBatchButtonState('bar-appear')
    })
  }

  private confirmDelete(): void {
    const ids = this.vm.deleteTargetIds.length > 0 ? this.vm.deleteTargetIds.slice() : this.vm.selectedIds.slice()
    if (ids.length === 0) {
      this.showDeleteConfirm = false
      this.vm.deleteTargetIds = []
      return
    }
    const fromBatchToolbar = this.vm.deleteTargetIds.length === 0
    void BrowserStore.deleteBookmarks(ids).then(() => {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.deleted')))
    })
    if (fromBatchToolbar) {
      this.vm.selectedIds = []
      this.vm.batchMode = false
    }
    this.vm.deleteTargetIds = []
    this.showDeleteConfirm = false
  }

  /** ????????? 1 ??????????????? */
  private openBookmarkEditForSelection(): void {
    if (this.vm.selectedIds.length !== 1) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.select_one_to_rename')))
      return
    }
    const picked = this.bookmarks.find((b) => b.id === this.vm.selectedIds[0])
    if (!picked) {
      return
    }
    if (picked.isFolder) {
      this.editingFolderId = picked.id
      this.renameFolderName = picked.title
      this.renameFolderParent = BrowserStore.getFolderParentId(picked.id)
      this.showRenameFolder = true
      return
    }
    this.editingBookmarkId = picked.id
    this.newBookmarkName = picked.title
    this.newBookmarkUrl = picked.url
    this.showNewBookmark = true
  }

  private closeRenameFolderForm(): void {
    this.showRenameFolder = false
    this.editingFolderId = ''
    this.renameFolderName = ''
    this.renameFolderParent = BOOKMARK_ROOT_FOLDER
  }

  /** 编辑文件夹时不可选自身或其子文件夹作为存放位置 */
  private isInvalidRenameLocation(targetFolderId: string): boolean {
    if (!this.editingFolderId) {
      return false
    }
    return BrowserStore.isDescendantOf(targetFolderId, this.editingFolderId)
  }

  private saveRenameFolder(): void {
    const name = this.renameFolderName.trim()
    if (!name) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_name_required')))
      return
    }
    const folderId = this.editingFolderId
    if (!folderId) {
      return
    }
    const targetParent = this.renameFolderParent || BOOKMARK_ROOT_FOLDER
    if (this.isInvalidRenameLocation(targetParent)) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
      return
    }
    const currentParent = BrowserStore.getFolderParentId(folderId)
    void BrowserStore.tryRenameBookmark(folderId, name).then((ok) => {
      if (!ok) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_exists')))
        return
      }
      const needMove = (currentParent || BOOKMARK_ROOT_FOLDER) !== (targetParent || BOOKMARK_ROOT_FOLDER)
      if (!needMove) {
        this.closeRenameFolderForm()
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.renamed')))
        return
      }
      void BrowserStore.moveItemsToFolder([folderId], targetParent).then((result) => {
        if (result === 'invalid') {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
          return
        }
        if (result === 'failed') {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_failed_retry')))
          return
        }
        this.closeRenameFolderForm()
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.renamed')))
      })
    })
  }

  @Builder
  RenameFolderForm() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.closeRenameFolderForm()
        })

      Column() {
        Row() {
          PanelCircleIconButton({
            iconKind: 'close',
            darkMode: this.isDark(),
            onTap: () => {
              this.closeRenameFolderForm()
            }
          })
          Text($r('app.string.edit_folder'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(BrowserTheme.TEXT)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          PanelCircleIconButton({
            iconKind: 'confirm',
            darkMode: this.isDark(),
            onTap: () => {
              this.saveRenameFolder()
            }
          })
        }
        .width('100%')
        .padding({
          left: PanelHeaderStyle.H_PADDING,
          right: PanelHeaderStyle.H_PADDING,
          top: PanelHeaderStyle.V_PADDING,
          bottom: PanelHeaderStyle.V_PADDING
        })
        .alignItems(VerticalAlign.Center)

        Divider().color(BrowserTheme.BORDER).strokeWidth(0.5).margin({ left: 16, right: 16 })

        Row() {
          TextInput({ text: this.renameFolderName, placeholder: $r('app.string.new_folder') })
            .layoutWeight(1)
            .fontSize(16)
            .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
            .backgroundColor(Color.Transparent)
            .padding({ left: 16, right: 8, top: 14, bottom: 14 })
            .onChange((v: string) => {
              this.applyInputChange(v, this.renameFolderName, (text: string) => {
                this.renameFolderName = text
              })
            })
          if (this.renameFolderName.length > 0) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([BrowserTheme.TEXT_MUTED])
              .fontWeight(FontWeight.Medium)
              .width(36)
              .height(36)
              .margin({ right: 8 })
              .onClick(() => {
                this.renameFolderName = ''
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider().color(BrowserTheme.BORDER).strokeWidth(0.5).margin({ left: 16, right: 16 })

        Row() {
          Text($r('app.string.location_label'))
            .fontSize(15)
            .fontColor(BrowserTheme.TEXT)
          Blank().layoutWeight(1)
          Text(BrowserStore.folderLocationLabel(this.renameFolderParent))
            .fontSize(15)
            .fontColor(BrowserTheme.TEXT_MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '55%' })
          NavChevronRight({ color: BrowserTheme.TEXT_MUTED, iconSize: 16 })
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => {
          this.openLocationPickerSheet()
        })
      }
      .width('100%')
      .backgroundColor(BrowserTheme.SURFACE)
      .borderRadius({ topLeft: 16, topRight: 16 })
      .padding({ bottom: 12 + this.safeAreaBottom })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(4600)
  }

  @Builder
  NewBookmarkForm() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.showNewBookmark = false
        })

      Column({ space: 16 }) {
        Text(this.editingBookmarkId ? $r('app.string.rename') : $r('app.string.new_bookmark'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
        TextInput({ text: this.newBookmarkName, placeholder: $r('app.string.bookmark_name_label') })
          .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
          .onChange((v: string) => {
            this.applyInputChange(v, this.newBookmarkName, (text: string) => {
              this.newBookmarkName = text
            })
          })
        TextInput({ text: this.newBookmarkUrl, placeholder: $r('app.string.bookmark_url_label') })
          .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
          .onChange((v: string) => {
            this.applyInputChange(v, this.newBookmarkUrl, (text: string) => {
              this.newBookmarkUrl = text
            }, true)
          })
        Row({ space: 12 }) {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .fontColor(BrowserTheme.TEXT)
            .onClick(() => {
              this.showNewBookmark = false
            })
          Button($r('app.string.save'))
            .layoutWeight(1)
            .onClick(() => this.saveNewBookmark())
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .backgroundColor(BrowserTheme.SURFACE)
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .zIndex(4500)
  }

  private saveNewBookmark(): void {
    if (this.editingBookmarkId) {
      const editId = this.editingBookmarkId
      const editTitle = this.newBookmarkName
      const editUrl = this.newBookmarkUrl.trim() || undefined
      this.editingBookmarkId = ''
      this.showNewBookmark = false
      void BrowserStore.updateBookmark(editId, {
        title: editTitle,
        url: editUrl
      }).then(() => {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.renamed')))
      })
      return
    }
    const entryInput: CreateBookmarkItemInput = {
      id: `b${Date.now()}`,
      title: this.newBookmarkName.trim() || BrowserStrings.newBookmark(),
      url: this.newBookmarkUrl.trim() || 'https://',
      parentId: this.isRoot() ? BOOKMARK_ROOT_FOLDER : this.currentFolderId,
    }
    const entry = createBookmarkItem(entryInput)
    this.showNewBookmark = false
    void BrowserStore.tryAddBookmark(entry).then((ok) => {
      if (ok) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.bookmark_added')))
      } else {
        this.showLimitDialog = true
      }
    })
  }

  @Builder
  NewFolderForm() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.showNewFolder = false
        })

      Column({ space: 16 }) {
        Text($r('app.string.new_folder'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
        Text($r('app.string.folder_name_label'))
          .fontSize(13)
          .fontColor(BrowserTheme.TEXT_MUTED)
          .width('100%')
        TextInput({ text: this.newFolderName, placeholder: $r('app.string.new_folder') })
          .fontSize(15)
          .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
          .onChange((v: string) => {
            this.applyInputChange(v, this.newFolderName, (text: string) => {
              this.newFolderName = text
            })
          })
        Row() {
          Text($r('app.string.location_label'))
            .fontSize(15)
            .fontColor(BrowserTheme.TEXT_MUTED)
          Blank().layoutWeight(1)
          Text(BrowserStore.folderLocationLabel(this.newFolderParent))
            .fontSize(15)
            .fontColor(BrowserTheme.TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '50%' })
          NavChevronRight({ color: BrowserTheme.TEXT_MUTED, iconSize: 16 })
            .margin({ left: 6 })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.openLocationPickerSheet()
        })
        Row({ space: 12 }) {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .fontColor(BrowserTheme.TEXT)
            .onClick(() => {
              this.showNewFolder = false
            })
          Button($r('app.string.save'))
            .layoutWeight(1)
            .onClick(() => this.saveNewFolder())
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .backgroundColor(BrowserTheme.SURFACE)
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .zIndex(4500)
  }

  private saveNewFolder(): void {
    const name = this.newFolderName.trim()
    if (!name) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_name_required')))
      return
    }
    this.showNewFolder = false
    void BrowserStore.addFolderEntry(name, this.newFolderParent).then((ok) => {
      if (ok) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_created')))
        this.newFolderName = BrowserStrings.newFolder()
      } else {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_exists')))
        this.showNewFolder = true
      }
    })
  }

  @Builder
  MovePickerPanel() {
    Column() {
      Row() {
        PanelCircleIconButton({
          iconKind: 'back',
          darkMode: this.isDark(),
          onTap: () => {
            this.showMovePicker = false
            this.moveSourceIds = []
            this.moveCollapsedFolderIds = []
          }
        })
        Text($r('app.string.select_target_folder'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(BrowserTheme.TEXT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: PanelHeaderStyle.TITLE_GAP })
      }
      .width('100%')
      .padding({
        left: PanelHeaderStyle.H_PADDING,
        right: PanelHeaderStyle.H_PADDING,
        top: PanelHeaderStyle.V_PADDING + this.safeAreaTop,
        bottom: PanelHeaderStyle.V_PADDING
      })
      .backgroundColor(BrowserTheme.SURFACE)
      .border({ width: { bottom: 1 }, color: BrowserTheme.BORDER })

      Scroll() {
        Column() {
          ForEach(this.movePickRows(), (row: BookmarkFolderPickRow, index: number) => {
            this.MoveTreeFolderRow(row, index === this.movePickRows().length - 1)
          }, (row: BookmarkFolderPickRow) =>
            `${row.id}_${this.moveCollapsedFolderIds.length}_${this.moveSourceIds.length}_${this.movePickFolder}`)
        }
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor(BrowserTheme.TEXT)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            this.showMovePicker = false
            this.moveSourceIds = []
            this.moveCollapsedFolderIds = []
          })
        Button($r('app.string.move_here'))
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(this.canConfirmMove() ?
            BrowserTheme.PRIMARY_COLOR : BrowserTheme.TEXT_MUTED)
          .enabled(this.canConfirmMove())
          .opacity(this.canConfirmMove() ? 1 : 0.55)
          .onClick(() => {
            this.confirmMovePick()
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + this.safeAreaBottom
      })
      .backgroundColor(BrowserTheme.SURFACE)
      .border({ width: { top: 1 }, color: BrowserTheme.BORDER })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BrowserTheme.BG)
    .zIndex(4000)
  }

  @Builder
  MoveTreeFolderRow(row: BookmarkFolderPickRow, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(BookmarkFolderTree.ICON_SIZE)
          .fontColor([this.isInvalidMoveTarget(row.id) ? BrowserTheme.TEXT_MUTED : BrowserTheme.PRIMARY_COLOR])
          .margin({ right: BookmarkFolderTree.ICON_GAP })
          .opacity(this.isInvalidMoveTarget(row.id) ? 0.35 : 1)

        Text(row.title)
          .fontSize(15)
          .fontColor(this.isInvalidMoveTarget(row.id) ? BrowserTheme.TEXT_MUTED : BrowserTheme.TEXT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (row.hasChildren) {
          FolderExpandChevron({
            expanded: BookmarkFolderTree.isExpanded(row.id, this.moveCollapsedFolderIds),
            color: BrowserTheme.TEXT_MUTED,
            iconSize: BookmarkFolderTree.CHEVRON_SIZE
          })
            .padding({ left: 8, right: 8 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.moveCollapsedFolderIds =
                BookmarkFolderTree.toggleCollapsed(row.id, this.moveCollapsedFolderIds)
            })
        }
      }
      .width('100%')
      .padding({
        left: BookmarkFolderTree.indentLeft(row.depth, 16),
        right: 16,
        top: 14,
        bottom: 14
      })

      if (!isLast) {
        Divider()
          .color(BrowserTheme.BORDER)
          .strokeWidth(1)
          .margin({ left: BookmarkFolderTree.dividerStart(row.depth, 16), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.movePickFolder === row.id && !this.isInvalidMoveTarget(row.id) ?
      BrowserTheme.PRIMARY_LIGHT : BrowserTheme.SURFACE)
    .opacity(this.isInvalidMoveTarget(row.id) ? 0.55 : 1)
    .onClick(() => {
      if (this.isInvalidMoveTarget(row.id)) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
        return
      }
      this.movePickFolder = row.id
    })
  }

  private confirmMovePick(): void {
    if (this.isInvalidMoveTarget(this.movePickFolder)) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
      return
    }
    if (this.isAlreadyAtMoveTarget(this.movePickFolder)) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_already_at_target')))
      return
    }
    this.doMove(this.movePickFolder)
  }

  private doMove(parentId: string): void {
    if (this.isInvalidMoveTarget(parentId)) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
      return
    }
    if (this.isAlreadyAtMoveTarget(parentId)) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_already_at_target')))
      return
    }
    const sourceIds = this.moveSourceIds.slice()
    // parentId === '' ????????
    void BrowserStore.moveItemsToFolder(sourceIds, parentId || BOOKMARK_ROOT_FOLDER).then((result) => {
      if (result === 'invalid') {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
        return
      }
      if (result === 'failed') {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_failed_retry')))
        return
      }
      this.vm.selectedIds = []
      this.moveSourceIds = []
      this.showMovePicker = false
      this.moveCollapsedFolderIds = []
      BrowserStore.showToast(BrowserStrings.movedTo(BrowserStore.folderLocationLabel(parentId)))
    })
  }

  @Builder
  LocationPickerPanel() {
    Column() {
      Row() {
        PanelCircleIconButton({
          iconKind: 'back',
          darkMode: this.isDark(),
          onTap: () => {
            this.showLocationPicker = false
            this.locationCollapsedFolderIds = []
          }
        })
        Text($r('app.string.select_target_folder'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(BrowserTheme.TEXT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: PanelHeaderStyle.TITLE_GAP })
      }
      .width('100%')
      .padding({
        left: PanelHeaderStyle.H_PADDING,
        right: PanelHeaderStyle.H_PADDING,
        top: PanelHeaderStyle.V_PADDING + this.safeAreaTop,
        bottom: PanelHeaderStyle.V_PADDING
      })
      .backgroundColor(BrowserTheme.SURFACE)
      .border({ width: { bottom: 1 }, color: BrowserTheme.BORDER })

      Scroll() {
        Column() {
          ForEach(this.locationPickRows(), (row: BookmarkFolderPickRow, index: number) => {
            this.LocationTreeFolderRow(row, index === this.locationPickRows().length - 1)
          }, (row: BookmarkFolderPickRow) =>
            `${row.id}_${this.locationCollapsedFolderIds.length}_${this.locationPickFolder}`)
        }
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor(BrowserTheme.TEXT)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            this.showLocationPicker = false
            this.locationCollapsedFolderIds = []
          })
        Button($r('app.string.confirm'))
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(BrowserTheme.PRIMARY_COLOR)
          .onClick(() => {
            this.confirmLocationPicker()
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + this.safeAreaBottom
      })
      .backgroundColor(BrowserTheme.SURFACE)
      .border({ width: { top: 1 }, color: BrowserTheme.BORDER })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BrowserTheme.BG)
    .zIndex(4700)
  }

  @Builder
  LocationTreeFolderRow(row: BookmarkFolderPickRow, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(BookmarkFolderTree.ICON_SIZE)
          .fontColor([BrowserTheme.PRIMARY_COLOR])
          .margin({ right: BookmarkFolderTree.ICON_GAP })

        Text(row.title)
          .fontSize(15)
          .fontColor(BrowserTheme.TEXT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (row.hasChildren) {
          FolderExpandChevron({
            expanded: BookmarkFolderTree.isExpanded(row.id, this.locationCollapsedFolderIds),
            color: BrowserTheme.TEXT_MUTED,
            iconSize: BookmarkFolderTree.CHEVRON_SIZE
          })
            .padding({ left: 8, right: 8 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.locationCollapsedFolderIds =
                BookmarkFolderTree.toggleCollapsed(row.id, this.locationCollapsedFolderIds)
            })
        }
      }
      .width('100%')
      .padding({
        left: BookmarkFolderTree.indentLeft(row.depth, 16),
        right: 16,
        top: 14,
        bottom: 14
      })

      if (!isLast) {
        Divider()
          .color(BrowserTheme.BORDER)
          .strokeWidth(1)
          .margin({ left: BookmarkFolderTree.dividerStart(row.depth, 16), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.locationPickFolder === row.id && !this.isInvalidRenameLocation(row.id) ?
      BrowserTheme.PRIMARY_LIGHT : BrowserTheme.SURFACE)
    .opacity(this.isInvalidRenameLocation(row.id) ? 0.55 : 1)
    .onClick(() => {
      if (this.isInvalidRenameLocation(row.id)) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.move_target_invalid')))
        return
      }
      this.locationPickFolder = row.id
    })
  }

}
