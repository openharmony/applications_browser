import { BrowserStrings } from 'common'
import { BrowserNavigation } from 'browser_core'
import { getBrowserUIContext } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { FeaturePanelBackBridge } from 'browser_core'
import { BookmarkFolderTree } from 'common'
import {
  DateGroup,
  DownloadEntry,
  formatFileSizeText,
  groupDownloadsByDate,
  isImageFile,
  OpenShareOptions
} from 'browser_core'
import { DownloadDeleteDialog } from './DownloadDeleteDialog'
import { DownloadFileIcon } from './DownloadFileIcon'
import { PanelBatchCheck } from 'commons'
import { PanelConfirmDialog } from 'commons'
import { PanelDownloadAction } from './PanelDownloadAction'
import { PanelSubpageHeader } from 'commons'
import { PanelSwipeDeleteRow } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'
import { DownloadsViewModel, DownloadBatchDragDirection } from './DownloadsViewModel'

/** 批量滑动多选：单行在屏幕上的命中区域（vp） */
interface DownloadRowHitArea {
  topVp: number
  bottomVp: number
}

/** 下载批量底栏按钮：图标 + 文案（@Prop 保证 disabled 随勾选状态刷新） */
@Component
struct DownloadsBatchBtn {
  @Prop label: string = ''
  /** select_all / delete */
  @Prop iconKind: string = 'select_all'
  @Prop disabled: boolean = false
  @Prop danger: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'
  onTap?: () => void

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private iconRes(): Resource {
    if (this.iconKind === 'delete') {
      return $r('sys.symbol.trash')
    }
    return $r('sys.symbol.checkmark_square_on_square')
  }

  private tint(): ResourceColor {
    if (this.disabled) {
      return BrowserTheme.TEXT_MUTED
    }
    return this.danger ? '#ef4444' : BrowserTheme.primaryColor(this.isDark())
  }

  build() {
    Column({ space: 4 }) {
      SymbolGlyph(this.iconRes())
        .fontSize(22)
        .fontColor([this.tint()])
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
export struct DownloadsPanel {
  @StorageLink('browser_downloads') @Watch('onDownloadsChanged') downloads: DownloadEntry[] = []
  @StorageLink('browser_downloads_rev') @Watch('onDownloadsChanged') downloadsRev: number = 0
  @StorageLink('browser_theme') theme: string = 'light'
  @State vm: DownloadsViewModel = new DownloadsViewModel()
  @State searchVisible: boolean = false
  @State searchFilter: string = ''
  /** 按日分组缓存：避免 ForEach 仅用 label 作 key 时删除后不刷新 */
  @State downloadGroups: DateGroup<DownloadEntry>[] = []
  @State showDeleteConfirm: boolean = false
  @State renameText: string = ''
  @State showRename: boolean = false
  @State showCtxMenu: boolean = false
  @State ctxItemId: string = ''
  @State ctxMenuTop: number = 108
  @State swipeOpenRowId: string = ''
  @State swipeDragRowId: string = ''
  @State swipeDragOffsetX: number = 0
  @State showRedownloadConfirm: boolean = false
  @State redownloadTargetId: string = ''
  @State redownloadTargetName: string = ''
  @State showFailedRetryConfirm: boolean = false
  @State failedRetryTargetId: string = ''
  @State failedRetryTargetName: string = ''
  @State batchDragActive: boolean = false
  onClose?: () => void
  private static readonly BATCH_CHECK_HIT: number = 44
  private static readonly EDGE_SCROLL_ZONE: number = 72
  private static readonly EDGE_SCROLL_STEP: number = 18
  private static readonly EDGE_SCROLL_INTERVAL: number = 48
  private batchDragAnchorId: string = ''
  private batchDragLastId: string = ''
  private batchDragMoved: boolean = false
  private batchDragSelectMode: boolean = true
  private batchDragSnapshot: string[] = []
  private batchDragPrimaryDirection: number = DownloadBatchDragDirection.NONE
  private downloadRowHitAreas: Map<string, DownloadRowHitArea> = new Map()
  private downloadScrollScroller: Scroller = new Scroller()
  private scrollViewportTopVp: number = 0
  private scrollViewportHeightVp: number = 0
  private edgeScrollTimer: number = -1
  private edgeScrollDirection: number = 0
  private batchDragLastTouchY: number = 0

  aboutToAppear(): void {
    this.rebuildDownloadGroups()
    // 注册侧滑返回/系统返回键监听，优先退出编辑模式而非关闭面板
    FeaturePanelBackBridge.register((): boolean => {
      this.handleBack()
      return true
    })
  }

  aboutToDisappear(): void {
    FeaturePanelBackBridge.unregister()
  }

  private onDownloadsChanged(): void {
    this.rebuildDownloadGroups()
  }

  private rebuildDownloadGroups(): void {
    this.downloadGroups = groupDownloadsByDate(this.filteredItems())
  }

  private closeSwipeRows(): void {
    this.swipeOpenRowId = ''
    this.swipeDragRowId = ''
    this.swipeDragOffsetX = 0
  }

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private batchDeleteEnabled(): boolean {
    return this.vm.batchDeleteEnabled()
  }

  private handleBack(): void {
    this.closeSwipeRows()
    if (this.vm.batchMode) {
      this.resetBatchDragState()
      this.clearDownloadRowHitAreas()
      this.vm.exitBatchMode()
      return
    }
    if (this.searchVisible) {
      this.searchVisible = false
      this.searchFilter = ''
      this.rebuildDownloadGroups()
      return
    }
    this.onClose?.()
  }

  private filteredItems(): DownloadEntry[] {
    let items = this.downloads.slice()
    const q = this.searchFilter.trim().toLowerCase()
    if (q) {
      items = items.filter((d) => d.fileName.toLowerCase().includes(q))
    }
    return items
  }

  /** 与分组列表展示顺序一致的扁平列表 */
  private flatVisibleItems(): DownloadEntry[] {
    const items: DownloadEntry[] = []
    for (const group of this.downloadGroups) {
      for (const item of group.items) {
        items.push(item)
      }
    }
    return items
  }

  private headerTitle(): string {
    return this.vm.headerTitle()
  }

  private isSelected(id: string): boolean {
    return this.vm.isSelected(id)
  }

  /** 文件大小行：失败时在大小后追加失败原因 */
  private downloadMetaText(item: DownloadEntry): string {
    const sizeText = formatFileSizeText(item.fileSize)
    if (item.status === 'failed') {
      const reason = item.errorMessage.trim()
      if (reason.length > 0) {
        return sizeText.length > 0 ? `${sizeText} · ${reason}` : reason
      }
    }
    return sizeText
  }

  private toggleSelect(id: string): void {
    this.vm.toggleSelect(id)
  }

  private resetBatchDragState(): void {
    this.stopBatchEdgeScroll()
    this.batchDragActive = false
    this.batchDragAnchorId = ''
    this.batchDragLastId = ''
    this.batchDragMoved = false
    this.batchDragSelectMode = true
    this.batchDragSnapshot = []
    this.batchDragPrimaryDirection = DownloadBatchDragDirection.NONE
    this.batchDragLastTouchY = 0
  }

  private stopBatchEdgeScroll(): void {
    if (this.edgeScrollTimer >= 0) {
      clearInterval(this.edgeScrollTimer)
      this.edgeScrollTimer = -1
    }
    this.edgeScrollDirection = 0
  }

  private clearDownloadRowHitAreas(): void {
    this.downloadRowHitAreas.clear()
  }

  private downloadRowMeasureId(id: string): string {
    return `download_batch_row_${id}`
  }

  private currentDownloadScrollY(): number {
    return this.downloadScrollScroller.currentOffset()?.yOffset ?? 0
  }

  private touchViewportYVp(touch: TouchObject): number {
    return this.touchGlobalYVp(touch) - this.scrollViewportTopVp
  }

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

  private updateDownloadRowHitArea(itemId: string, area: Area): void {
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
    this.downloadRowHitAreas.set(itemId, {
      topVp,
      bottomVp: topVp + heightVp
    })
  }

  private findDownloadRowAtTouchY(touchY: number): DownloadEntry | null {
    let bestItem: DownloadEntry | null = null
    let bestHeight = Number.MAX_VALUE
    for (const item of this.flatVisibleItems()) {
      const hit = this.downloadRowHitAreas.get(item.id)
      if (!hit) {
        continue
      }
      if (touchY >= hit.topVp && touchY < hit.bottomVp) {
        const heightVp = hit.bottomVp - hit.topVp
        if (heightVp < bestHeight) {
          bestHeight = heightVp
          bestItem = item
        }
      }
    }
    return bestItem
  }

  private findDownloadRowForBatchDrag(touch: TouchObject): DownloadEntry | null {
    const touchY = this.touchGlobalYVp(touch)
    this.batchDragLastTouchY = touchY
    const direct = this.findDownloadRowAtTouchY(touchY)
    if (direct || !this.batchDragActive) {
      return direct
    }
    const fingerVp = touchY - this.scrollViewportTopVp
    const viewH = this.scrollViewportHeightVp
    const items = this.flatVisibleItems()
    if (fingerVp < DownloadsPanel.EDGE_SCROLL_ZONE) {
      for (const item of items) {
        const hit = this.downloadRowHitAreas.get(item.id)
        if (hit && hit.bottomVp > this.scrollViewportTopVp) {
          return item
        }
      }
    } else if (fingerVp > viewH - DownloadsPanel.EDGE_SCROLL_ZONE) {
      for (let i = items.length - 1; i >= 0; i--) {
        const hit = this.downloadRowHitAreas.get(items[i].id)
        if (hit && hit.topVp < this.scrollViewportTopVp + viewH) {
          return items[i]
        }
      }
    }
    return null
  }

  private extendBatchDragAtTouchY(touchY: number): void {
    const row = this.findDownloadRowAtTouchY(touchY)
    if (row) {
      this.extendBatchDragToRow(row.id)
    }
  }

  private updateBatchEdgeAutoScroll(touch: TouchObject): void {
    if (!this.batchDragActive) {
      this.stopBatchEdgeScroll()
      return
    }
    const fingerVp = this.touchViewportYVp(touch)
    const viewH = this.scrollViewportHeightVp
    const scrollY = this.currentDownloadScrollY()
    if (fingerVp < DownloadsPanel.EDGE_SCROLL_ZONE) {
      if (scrollY > 1) {
        this.startBatchEdgeScroll(-1)
      } else {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
      }
      return
    }
    if (fingerVp > viewH - DownloadsPanel.EDGE_SCROLL_ZONE) {
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
      const current = this.currentDownloadScrollY()
      if (direction < 0 && current <= 0) {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
        return
      }
      const next = Math.max(0, current + direction * DownloadsPanel.EDGE_SCROLL_STEP)
      if (next === current) {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
        return
      }
      this.downloadScrollScroller.scrollTo({ xOffset: 0, yOffset: next, animation: false })
      this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
    }, DownloadsPanel.EDGE_SCROLL_INTERVAL) as number
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
    if (this.batchDragPrimaryDirection !== DownloadBatchDragDirection.NONE) {
      return
    }
    const items = this.flatVisibleItems()
    const anchorIdx = items.findIndex((d) => d.id === this.batchDragAnchorId)
    const currentIdx = items.findIndex((d) => d.id === rowId)
    if (anchorIdx < 0 || currentIdx < 0 || currentIdx === anchorIdx) {
      return
    }
    if (currentIdx > anchorIdx) {
      this.batchDragPrimaryDirection = DownloadBatchDragDirection.DOWN
    } else {
      this.batchDragPrimaryDirection = DownloadBatchDragDirection.UP
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
      this.flatVisibleItems(),
      this.batchDragPrimaryDirection
    )
  }

  /** 勾选区触摸：短按切换单项；按住滑动连续选中/取消 */
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
      const row = this.findDownloadRowForBatchDrag(touch)
      if (!row) {
        return
      }
      this.extendBatchDragToRow(row.id)
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (!this.batchDragMoved && this.batchDragAnchorId.length > 0) {
        this.toggleSelect(this.batchDragAnchorId)
      }
      this.resetBatchDragState()
    }
  }

  private openDeleteDialog(ids: string[]): void {
    this.vm.openDeleteDialog(ids)
    this.showDeleteConfirm = true
  }

  private finishDelete(deleteLocal: boolean): void {
    void this.vm.finishDelete(deleteLocal).then((msg) => {
      // AppStorage 同步后 @Watch 会重建分组；此处再刷一次避免时序空窗
      this.rebuildDownloadGroups()
      if (this.downloads.length === 0) {
        this.vm.batchMode = false
      }
      this.showDeleteConfirm = false
      this.closeSwipeRows()
      BrowserStore.showToast(msg)
    })
  }

  private estimateCtxTop(itemId: string): number {
    let offset = 52 + 12
    for (let gi = 0; gi < this.downloadGroups.length; gi++) {
      offset += 30
      const group = this.downloadGroups[gi]
      for (let ii = 0; ii < group.items.length; ii++) {
        if (group.items[ii].id === itemId) {
          return Math.max(12, offset)
        }
        offset += 64
      }
      offset += 16
    }
    return 108
  }

  private isLastInGroup(group: DateGroup<DownloadEntry>, item: DownloadEntry): boolean {
    const items = group.items
    return items.length > 0 && items[items.length - 1].id === item.id
  }

  private requestRedownload(id: string, name: string): void {
    this.redownloadTargetId = id
    this.redownloadTargetName = name
    this.showRedownloadConfirm = true
  }

  private tryOpenDownload(id: string): void {
    void BrowserStore.openDownload(id).then((result) => {
      if (result === 'missing') {
        const item = this.downloads.find((d) => d.id === id)
        this.redownloadTargetId = id
        this.redownloadTargetName = item?.fileName ?? ''
        this.showRedownloadConfirm = true
      }
    })
  }

  private confirmRedownload(): void {
    const id = this.redownloadTargetId
    this.showRedownloadConfirm = false
    this.redownloadTargetId = ''
    this.redownloadTargetName = ''
    if (id.length > 0) {
      void BrowserStore.redownloadMissingFile(id)
    }
  }

  private requestFailedRetry(id: string, name: string): void {
    this.failedRetryTargetId = id
    this.failedRetryTargetName = name
    this.showFailedRetryConfirm = true
  }

  private confirmFailedRetry(): void {
    const id = this.failedRetryTargetId
    this.showFailedRetryConfirm = false
    this.failedRetryTargetId = ''
    this.failedRetryTargetName = ''
    if (id.length > 0) {
      void BrowserStore.retryDownload(id)
    }
  }

  build() {
    Stack() {
      Column() {
        this.PanelHeader()

        Scroll(this.downloadScrollScroller) {
          Column() {
            if (this.downloadGroups.length === 0) {
              this.EmptyState()
            } else {
              ForEach(this.downloadGroups, (group: DateGroup<DownloadEntry>) => {
                this.DownloadSection(group)
              }, (group: DateGroup<DownloadEntry>) =>
                `${group.label}_${this.searchFilter}_${this.downloads.length}_${this.downloadsRev}_${group.items.length}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: this.vm.batchMode ? BrowserSafeAreaInsets.batchBarScrollClearance() : 24
          })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .enableScrollInteraction(!this.batchDragActive)
        .backgroundColor(BrowserTheme.BG)
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

        if (this.vm.batchMode) {
          this.BatchBar()
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .backgroundColor(BrowserTheme.BG)
      .opacity(this.showCtxMenu ? 0.55 : 1)
      .blur(this.showCtxMenu ? 3 : 0)

      if (this.showDeleteConfirm) {
        DownloadDeleteDialog({
          onCancel: () => {
            this.showDeleteConfirm = false
            this.vm.clearDeleteTargets()
          },
          onDeleteBoth: () => this.finishDelete(true),
          onDeleteTaskOnly: () => this.finishDelete(false)
        })
      }

      if (this.showFailedRetryConfirm) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.download_failed_retry_confirm')),
          subtitle: this.failedRetryTargetName,
          confirmLabel: BrowserStrings.txt($r('app.string.retry_download')),
          cancelLabel: BrowserStrings.txt($r('app.string.cancel')),
          onCancel: () => {
            this.showFailedRetryConfirm = false
            this.failedRetryTargetId = ''
            this.failedRetryTargetName = ''
          },
          onConfirm: () => {
            this.confirmFailedRetry()
          }
        })
      }

      if (this.showRedownloadConfirm) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.download_file_missing_redownload')),
          subtitle: this.redownloadTargetName,
          confirmLabel: BrowserStrings.txt($r('app.string.retry_download')),
          cancelLabel: BrowserStrings.txt($r('app.string.cancel')),
          onCancel: () => {
            this.showRedownloadConfirm = false
            this.redownloadTargetId = ''
            this.redownloadTargetName = ''
          },
          onConfirm: () => {
            this.confirmRedownload()
          }
        })
      }
      if (this.showRename) {
        this.RenameForm()
      }
      if (this.showCtxMenu && this.ctxItemId) {
        this.ContextMenuOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BrowserTheme.BG)
    .onAppear(() => {
      void BrowserStore.syncDownloadFileStates()
    })
  }

  @Builder
  PanelHeader() {
    PanelSubpageHeader({
      title: this.headerTitle(),
      batchMode: this.vm.batchMode,
      darkMode: this.isDark(),
      showSearch: !this.vm.batchMode,
      showMore: false,
      searchExpanded: this.searchVisible && !this.vm.batchMode,
      searchText: this.searchFilter,
      searchPlaceholder: $r('app.string.search_downloads_placeholder'),
      onBack: () => {
        this.handleBack()
      },
      onSearch: () => {
        this.searchVisible = !this.searchVisible
        if (!this.searchVisible) {
          this.searchFilter = ''
          this.rebuildDownloadGroups()
        }
      },
      onSearchChange: (v: string) => {
        BrowserNavigation.applyTextInputChange(v, this.searchFilter.length, (text: string) => {
          this.searchFilter = text
          this.rebuildDownloadGroups()
        })
      },
      onSearchClear: () => {
        this.searchVisible = false
        this.searchFilter = ''
        this.rebuildDownloadGroups()
      },
      onMore: () => {
      }
    })
  }

  @Builder
  EmptyState() {
    Column({ space: 16 }) {
      Text('📥')
        .fontSize(56)
        .opacity(0.28)
      Text(this.searchFilter ? $r('app.string.no_search_results') : $r('app.string.no_downloads'))
        .fontSize(14)
        .fontColor(BrowserTheme.TEXT_MUTED)
    }
    .width('100%')
    .padding({ top: 100, bottom: 48 })
    .alignItems(HorizontalAlign.Center)
  }

  private downloadRowKey(item: DownloadEntry): string {
    // 不含选中态/selectionRevision，避免滑动多选时整行重建导致图标闪烁
    const batch = this.vm.batchMode ? '1' : '0'
    return `${item.id}_${item.status}_${batch}_${item.fileName}`
  }

  @Builder
  DownloadSection(group: DateGroup<DownloadEntry>) {
    Column() {
      Text(group.label)
        .fontSize(13)
        .fontColor('#9ca3af')
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 4, bottom: 8 })

      Column() {
        ForEach(group.items, (item: DownloadEntry) => {
          this.DownloadSwipeRow(item, this.isLastInGroup(group, item))
        }, (item: DownloadEntry) => this.downloadRowKey(item))
      }
      .width('100%')
      .backgroundColor(BrowserTheme.SURFACE)
      .borderRadius(12)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 16 })
  }

  @Builder
  DownloadItemIcon(item: DownloadEntry) {
    DownloadFileIcon({
      fileName: item.fileName,
      galleryUri: item.galleryUri,
      localPath: item.localPath,
      status: item.status
    })
  }

  @Builder
  DownloadSwipeRow(item: DownloadEntry, isLast: boolean) {
    if (this.vm.batchMode) {
      this.DownloadBatchRow(item, isLast)
    } else {
      this.DownloadNormalRow(item, isLast)
    }
  }

  @Builder
  DownloadBatchRow(item: DownloadEntry, isLast: boolean) {
    Column() {
      Row() {
        this.DownloadItemIcon(item)

        Column({ space: 2 }) {
          Text(item.fileName)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isSelected(item.id) ? BrowserTheme.primaryColor(this.isDark()) : BrowserTheme.text(this.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.downloadMetaText(item))
            .fontSize(12)
            .fontColor(item.status === 'failed' ? '#ef4444' : '#9ca3af')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          PanelBatchCheck({ selected: this.isSelected(item.id) })
        }
        .width(DownloadsPanel.BATCH_CHECK_HIT)
        .height(DownloadsPanel.BATCH_CHECK_HIT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.onBatchCheckTouch(item.id, event)
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (!isLast) {
        Divider()
          .color(BrowserTheme.BORDER)
          .strokeWidth(1)
          .margin({ left: BookmarkFolderTree.dividerStartDownload(), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.isSelected(item.id) ? BrowserTheme.PRIMARY_LIGHT : BrowserTheme.SURFACE)
    .id(this.downloadRowMeasureId(item.id))
    .onAreaChange((_old, area) => {
      this.updateDownloadRowHitArea(item.id, area)
    })
  }

  @Builder
  DownloadNormalRow(item: DownloadEntry, isLast: boolean) {
    PanelSwipeDeleteRow({
      itemId: item.id,
      isLast: isLast,
      dividerLeft: BookmarkFolderTree.dividerStartDownload(),
      rowBg: BrowserTheme.SURFACE,
      openRowId: $swipeOpenRowId,
      dragRowId: $swipeDragRowId,
      dragOffsetX: $swipeDragOffsetX,
      onDelete: (id: string) => {
        this.closeSwipeRows()
        this.openDeleteDialog([id])
      },
      onRowClick: () => {
        if (item.status === 'done') {
          this.tryOpenDownload(item.id)
        } else if (item.status === 'deleted') {
          this.requestRedownload(item.id, item.fileName)
        }
      },
      onLongPress: () => {
        this.closeSwipeRows()
        this.ctxItemId = item.id
        this.ctxMenuTop = this.estimateCtxTop(item.id)
        this.showCtxMenu = true
      },
      row: () => {
        this.DownloadNormalRowContent(item)
      }
    })
  }

  @Builder
  DownloadNormalRowContent(item: DownloadEntry) {
    Row() {
      Row() {
        this.DownloadItemIcon(item)

        Column({ space: 2 }) {
          Text(item.fileName)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(BrowserTheme.text(this.isDark()))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.downloadMetaText(item))
            .fontSize(12)
            .fontColor(item.status === 'failed' ? '#ef4444' : '#9ca3af')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)

      PanelDownloadAction({
        itemId: item.id,
        itemName: item.fileName,
        status: item.status,
        progress: item.progress,
        onOpenItem: (id: string) => {
          this.tryOpenDownload(id)
        },
        onRetryRequest: (id: string, name: string) => {
          this.requestFailedRetry(id, name)
        },
        onRedownloadRequest: (id: string, name: string) => {
          this.requestRedownload(id, name)
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(BrowserTheme.SURFACE)
  }

  @Builder
  BatchBar() {
    // 与浏览页底栏一致：内容行固定高度，底边避让写在外层，避免 padding 挤占图标/文字
    Column() {
      Row() {
        DownloadsBatchBtn({
          label: BrowserStrings.batchActionLabel('select_all'),
          iconKind: 'select_all',
          disabled: false,
          onTap: () => {
            this.vm.toggleSelectAll(this.flatVisibleItems())
          }
        })
        DownloadsBatchBtn({
          label: BrowserStrings.batchActionLabel('delete'),
          iconKind: 'delete',
          disabled: !this.batchDeleteEnabled(),
          danger: true,
          onTap: () => {
            this.openDeleteDialog(this.vm.selectedIds.slice())
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
  }

  private ctxItem(): DownloadEntry | undefined {
    return this.downloads.find((d) => d.id === this.ctxItemId)
  }

  @Builder
  ContextMenuOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.28)')
        .backgroundBlurStyle(BlurStyle.Thin)
        .onClick(() => {
          this.showCtxMenu = false
        })

      if (this.ctxItem()) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            DownloadFileIcon({
              fileName: this.ctxItem()?.fileName ?? '',
              galleryUri: this.ctxItem()?.galleryUri ?? '',
              localPath: this.ctxItem()?.localPath ?? '',
              status: this.ctxItem()?.status ?? 'pending'
            })

            Column({ space: 2 }) {
              Text((this.ctxItem()?.fileName ?? '').length > 18 ?
                `${(this.ctxItem()?.fileName ?? '').slice(0, 18)}...` : (this.ctxItem()?.fileName ?? ''))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(BrowserTheme.text(this.isDark()))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(formatFileSizeText(this.ctxItem()?.fileSize ?? 0))
                .fontSize(12)
                .fontColor('#9ca3af')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .shadow({ radius: 24, color: 'rgba(0, 0, 0, 0.1)', offsetX: 0, offsetY: 4 })

          Column() {
            this.CtxBtn('multi_select', () => {
              this.vm.enterBatchWithItem(this.ctxItemId)
              this.showCtxMenu = false
            })
            this.CtxMenuDivider()
            this.CtxBtn('share', () => {
              const item = this.ctxItem()
              if (item) {
                const shareOpts: OpenShareOptions = {
                  title: item.fileName,
                  url: `file:///${item.fileName}`,
                  size: formatFileSizeText(item.fileSize),
                  previewImage: isImageFile(item.fileName),
                }
                BrowserStore.openShare(shareOpts)
              }
              this.showCtxMenu = false
            })
            this.CtxMenuDivider()
            this.CtxBtn('rename', () => {
              this.vm.selectedIds = [this.ctxItemId]
              this.renameText = this.ctxItem()?.fileName ?? ''
              this.showRename = true
              this.showCtxMenu = false
            })
            this.CtxMenuDivider()
            this.CtxBtn('delete', () => {
              this.openDeleteDialog([this.ctxItemId])
              this.showCtxMenu = false
            })
          }
          .constraintSize({ minWidth: 132, maxWidth: 200 })
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .border({ width: 1, color: BrowserTheme.BORDER })
          .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: this.ctxMenuTop })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(4200)
  }

  @Builder
  CtxMenuDivider() {
    Divider()
      .color(BrowserTheme.BORDER)
      .strokeWidth(1)
      .margin({ left: 16, right: 16 })
  }

  @Builder
  CtxBtn(action: string, onTap: () => void) {
    Text(BrowserStrings.batchActionLabel(action))
      .fontSize(15)
      .fontColor(BrowserTheme.text(this.isDark()))
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(onTap)
  }

  @Builder
  RenameForm() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.showRename = false
        })

      Column({ space: 16 }) {
        Text($r('app.string.rename'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
        TextInput({ text: this.renameText })
          .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
          .onChange((v: string) => {
            BrowserNavigation.applyTextInputChange(v, this.renameText.length, (text: string) => {
              this.renameText = text
            })
          })
        Row({ space: 12 }) {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .fontColor(BrowserTheme.TEXT)
            .onClick(() => {
              this.showRename = false
            })
          Button($r('app.string.save'))
            .layoutWeight(1)
            .onClick(() => {
              const id = this.vm.selectedIds[0]
              BrowserStore.renameDownload(id, this.renameText)
              this.showRename = false
              BrowserStore.showToast(BrowserStrings.txt($r('app.string.renamed')))
            })
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
}
