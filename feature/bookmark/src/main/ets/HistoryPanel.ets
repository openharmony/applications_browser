import { BrowserStrings } from 'common'
import { BrowserNavigation } from 'browser_core'
import { getBrowserUIContext } from 'common'
import { BrowserLog } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { BookmarkFolderTree } from 'common'
import {
  DateGroup,
  groupHistoryByDate,
  HistoryEntry,
  OpenShareOptions,
  tabHostname
} from 'browser_core'
import { PanelConfirmDialog } from 'commons'
import { AddBookmarkDialog } from 'commons'
import { PanelBatchCheck } from 'commons'
import { PanelMenuItem, PanelPopoverMenu, PanelSubpageHeader } from 'commons'
import { PanelSwipeDeleteRow } from 'commons'
import { HistorySiteIcon } from 'commons'
import { HistoryContextMenuLayer } from './HistoryContextMenuLayer'
import { BrowserSafeAreaInsets } from 'commons'
import { HistoryViewModel, HistoryBatchDragDirection } from './HistoryViewModel'
import { FeaturePanelBackBridge } from 'browser_core'

interface HistoryRowArea {
  left: number
  top: number
  width: number
  height: number
}

interface HistoryMenuPoint {
  x: number
  y: number
}

/** 批量滑动多选：单行在屏幕上的命中区域（vp） */
interface HistoryRowHitArea {
  topVp: number
  bottomVp: number
}

/** 历史批量底栏按钮：图标 + 文案（@Prop 保证 disabled 随勾选状态刷新） */
@Component
struct HistoryBatchBtn {
  @Prop label: string = ''
  /** select_all / delete */
  @Prop iconKind: string = 'select_all'
  @Prop disabled: boolean = false
  @Prop danger: boolean = false
  onTap?: () => void

  private iconRes(): Resource {
    if (this.iconKind === 'delete') {
      return $r('sys.symbol.trash')
    }
    return $r('sys.symbol.checkmark_square_on_square')
  }

  private tint(): string {
    if (this.disabled) {
      return BrowserTheme.TEXT_MUTED
    }
    return this.danger ? '#ef4444' : BrowserTheme.PRIMARY_COLOR
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

/** 浏览历史面板：列表、搜索、批量操作与长按上下文菜单 */
@Component
export struct HistoryPanel {
  /** 历史记录列表（AppStorage 同步） */
  @StorageLink('browser_history') @Watch('onHistoryListChanged') historyList: HistoryEntry[] = []
  /** 当前主题 */
  @StorageLink('browser_theme') theme: string = 'light'
  @State vm: HistoryViewModel = new HistoryViewModel()
  @State searchVisible: boolean = false
  @State searchFilter: string = ''
  @State searchGroups: DateGroup<HistoryEntry>[] = []
  @State showMoreMenu: boolean = false
  @State showClearConfirm: boolean = false
  @State showDeleteConfirm: boolean = false
  @State showRowContextMenu: boolean = false
  @State contextHistoryItem: HistoryEntry | null = null
  @State ctxRowLeft: number = 0
  @State ctxRowTop: number = 0
  @State ctxRowWidth: number = 0
  @State ctxRowHeight: number = 56
  @State ctxMenuPosX: number = 0
  @State ctxMenuPosY: number = 0
  @State swipeOpenRowId: string = ''
  @State swipeDragRowId: string = ''
  @State swipeDragOffsetX: number = 0
  @State showAddBookmarkDialog: boolean = false
  @State addBookmarkDefaultTitle: string = ''
  @State addBookmarkTargetUrl: string = ''
  @State batchDragActive: boolean = false
  private batchDragAnchorId: number = -1
  private batchDragLastId: number = -1
  private batchDragMoved: boolean = false
  private batchDragSelectMode: boolean = true
  private batchDragSnapshot: number[] = []
  private batchDragPrimaryDirection: number = HistoryBatchDragDirection.NONE
  private historyRowHitAreas: Map<number, HistoryRowHitArea> = new Map()
  onClose?: () => void

  aboutToAppear(): void {
    this.refreshHistorySearch()
    // 注册侧滑返回/系统返回键监听，优先退出编辑模式而非关闭面板
    FeaturePanelBackBridge.register((): boolean => {
      this.handleBack()
      return true
    })
  }

  aboutToDisappear(): void {
    FeaturePanelBackBridge.unregister()
  }

  /** 历史列表变更时同步刷新搜索结果；列表清空则退出多选 */
  private onHistoryListChanged(): void {
    this.refreshHistorySearch()
    if (this.vm.batchMode && this.historyList.length === 0) {
      this.resetBatchDragState()
      this.clearHistoryRowHitAreas()
      this.vm.exitBatchMode()
    }
  }

  /** 搜索词变化时立即过滤并刷新列表 */
  private applySearchInput(value: string): void {
    BrowserNavigation.applyTextInputChange(value, this.searchFilter.length, (text: string) => {
      this.searchFilter = text
      this.refreshHistorySearch()
    })
  }

  /** 按当前搜索词重建分组列表 */
  private refreshHistorySearch(): void {
    this.searchGroups = groupHistoryByDate(this.buildFilteredItems())
  }

  private static readonly MENU_WIDTH: number = 220
  private static readonly MENU_BLOCK_HEIGHT: number = 210
  private static readonly LIFT_SCALE: number = 1.02
  private static readonly MENU_GAP: number = 6
  private static readonly ROW_FALLBACK_HEIGHT: number = 60
  private static readonly CTX_HOST_ID: string = 'history_ctx_host'
  private static readonly EDGE_SCROLL_ZONE: number = 72
  private static readonly EDGE_SCROLL_STEP: number = 18
  private static readonly EDGE_SCROLL_INTERVAL: number = 48
  /** 多选勾选热区（大于 22vp 图标，便于按下拖拽） */
  private static readonly BATCH_CHECK_HIT: number = 44

  private panelWidth: number = 360
  private panelHeight: number = 800
  private historyScrollScroller: Scroller = new Scroller()
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

  /** 是否深色主题 */
  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private moreMenuItems(): PanelMenuItem[] {
    return [
      {
        label: $r('app.string.edit'),
        iconKind: 'edit',
        onTap: () => {
          this.showMoreMenu = false
          this.vm.enterBatchMode()
        }
      },
      {
        label: $r('app.string.clear_all'),
        iconKind: 'trash',
        danger: true,
        onTap: () => {
          this.showMoreMenu = false
          this.showClearConfirm = true
        }
      }
    ]
  }

  /** 顶部返回：批量模式/搜索模式/关闭面板 */
  private handleBack(): void {
    this.closeSwipeRows()
    if (this.vm.batchMode) {
      this.resetBatchDragState()
      this.clearHistoryRowHitAreas()
      this.vm.exitBatchMode()
      return
    }
    if (this.searchVisible) {
      this.searchVisible = false
      this.searchFilter = ''
      this.refreshHistorySearch()
      return
    }
    this.onClose?.()
  }

  /** 按搜索词过滤历史列表（含空格时视为无结果） */
  private buildFilteredItems(): HistoryEntry[] {
    let items = this.historyList.slice()
    const q = this.searchFilter.trim().toLowerCase()
    if (q) {
      if (this.searchQueryHasInternalSpace()) {
        return []
      }
      items = items.filter((h) => h.title.toLowerCase().includes(q) || h.url.toLowerCase().includes(q))
    }
    return items
  }

  private filteredItems(): HistoryEntry[] {
    return this.buildFilteredItems()
  }

  private hasSearchQuery(): boolean {
    return this.searchFilter.trim().length > 0
  }

  /** 裁剪首尾空格后是否仍含空格（无效多词搜索） */
  private searchQueryHasInternalSpace(): boolean {
    return this.searchFilter.trim().includes(' ')
  }

  private headerTitle(): string {
    return this.vm.headerTitle()
  }

  private isSelected(id: number): boolean {
    return this.vm.isSelected(id)
  }

  private toggleSelect(id: number): void {
    this.vm.toggleSelect(id)
  }

  private resetBatchDragState(): void {
    this.stopBatchEdgeScroll()
    this.batchDragActive = false
    this.batchDragAnchorId = -1
    this.batchDragLastId = -1
    this.batchDragMoved = false
    this.batchDragSelectMode = true
    this.batchDragSnapshot = []
    this.batchDragPrimaryDirection = HistoryBatchDragDirection.NONE
    this.batchDragLastTouchY = 0
  }

  private stopBatchEdgeScroll(): void {
    if (this.edgeScrollTimer >= 0) {
      clearInterval(this.edgeScrollTimer)
      this.edgeScrollTimer = -1
    }
    this.edgeScrollDirection = 0
  }

  private currentHistoryScrollY(): number {
    return this.historyScrollScroller.currentOffset()?.yOffset ?? 0
  }

  private touchViewportYVp(touch: TouchObject): number {
    return this.touchGlobalYVp(touch) - this.scrollViewportTopVp
  }

  private findHistoryRowAtTouchY(touchY: number): HistoryEntry | null {
    let bestItem: HistoryEntry | null = null
    let bestHeight = Number.MAX_VALUE
    for (const item of this.flatVisibleItems()) {
      const hit = this.historyRowHitAreas.get(item.id)
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

  /** 拖拽多选命中行；边缘区域无命中时取首/末可见行 */
  private findHistoryRowForBatchDrag(touch: TouchObject): HistoryEntry | null {
    const touchY = this.touchGlobalYVp(touch)
    this.batchDragLastTouchY = touchY
    const direct = this.findHistoryRowAtTouchY(touchY)
    if (direct || !this.batchDragActive) {
      return direct
    }
    const fingerVp = touchY - this.scrollViewportTopVp
    const viewH = this.scrollViewportHeightVp
    const items = this.flatVisibleItems()
    if (fingerVp < HistoryPanel.EDGE_SCROLL_ZONE) {
      for (const item of items) {
        const hit = this.historyRowHitAreas.get(item.id)
        if (hit && hit.bottomVp > this.scrollViewportTopVp) {
          return item
        }
      }
    } else if (fingerVp > viewH - HistoryPanel.EDGE_SCROLL_ZONE) {
      for (let i = items.length - 1; i >= 0; i--) {
        const hit = this.historyRowHitAreas.get(items[i].id)
        if (hit && hit.topVp < this.scrollViewportTopVp + viewH) {
          return items[i]
        }
      }
    }
    return null
  }

  private extendBatchDragAtTouchY(touchY: number): void {
    const row = this.findHistoryRowAtTouchY(touchY)
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
    const scrollY = this.currentHistoryScrollY()
    if (fingerVp < HistoryPanel.EDGE_SCROLL_ZONE) {
      if (scrollY > 1) {
        this.startBatchEdgeScroll(-1)
      } else {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
      }
      return
    }
    if (fingerVp > viewH - HistoryPanel.EDGE_SCROLL_ZONE) {
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
      const current = this.currentHistoryScrollY()
      if (direction < 0 && current <= 0) {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
        return
      }
      const next = Math.max(0, current + direction * HistoryPanel.EDGE_SCROLL_STEP)
      if (next === current) {
        this.stopBatchEdgeScroll()
        this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
        return
      }
      this.historyScrollScroller.scrollTo({ xOffset: 0, yOffset: next, animation: false })
      this.extendBatchDragAtTouchY(this.batchDragLastTouchY)
    }, HistoryPanel.EDGE_SCROLL_INTERVAL) as number
  }

  private clearHistoryRowHitAreas(): void {
    this.historyRowHitAreas.clear()
  }

  /** 缓存批量行在屏幕上的真实位置（getRectangleById 在 Scroll 内返回整屏，不可用） */
  private updateHistoryRowHitArea(itemId: number, area: Area): void {
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
    this.historyRowHitAreas.set(itemId, {
      topVp,
      bottomVp: topVp + heightVp
    })
  }

  /** 触摸点屏幕 Y（vp），与 onAreaChange.globalPosition 同一坐标系 */
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

  /** 当前搜索过滤后的扁平历史列表（与列表展示顺序一致） */
  private flatVisibleItems(): HistoryEntry[] {
    const items: HistoryEntry[] = []
    for (const group of this.searchGroups) {
      for (const item of group.items) {
        items.push(item)
      }
    }
    return items
  }

  private beginBatchDragOnRow(rowId: number): void {
    this.batchDragActive = true
    this.batchDragMoved = false
    this.batchDragAnchorId = rowId
    this.batchDragLastId = rowId
    this.batchDragSnapshot = this.vm.selectedIds.slice()
    this.batchDragSelectMode = !this.isSelected(rowId)
  }

  private updateBatchDragPrimaryDirection(rowId: number): void {
    if (this.batchDragPrimaryDirection !== HistoryBatchDragDirection.NONE) {
      return
    }
    const items = this.flatVisibleItems()
    const anchorIdx = items.findIndex((h) => h.id === this.batchDragAnchorId)
    const currentIdx = items.findIndex((h) => h.id === rowId)
    if (anchorIdx < 0 || currentIdx < 0 || currentIdx === anchorIdx) {
      return
    }
    if (currentIdx > anchorIdx) {
      this.batchDragPrimaryDirection = HistoryBatchDragDirection.DOWN
    } else {
      this.batchDragPrimaryDirection = HistoryBatchDragDirection.UP
    }
  }

  private extendBatchDragToRow(rowId: number): void {
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

  /** 勾选区触摸：短按切换单项；按住滑动连续选中/取消（列表其他区域仅滚动） */
  private onBatchCheckTouch(rowId: number, event: TouchEvent): void {
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
      const row = this.findHistoryRowForBatchDrag(touch)
      if (!row) {
        return
      }
      this.extendBatchDragToRow(row.id)
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (!this.batchDragMoved && this.batchDragAnchorId >= 0) {
        this.toggleSelect(this.batchDragAnchorId)
      }
      this.resetBatchDragState()
    }
  }

  private batchDeleteEnabled(): boolean {
    return this.vm.batchDeleteEnabled()
  }

  private isHistoryRowLast(group: DateGroup<HistoryEntry>, item: HistoryEntry): boolean {
    const items = group.items
    return items.length > 0 && items[items.length - 1].id === item.id
  }

  private isContextMenuRow(id: number): boolean {
    return this.showRowContextMenu && this.contextHistoryItem?.id === id
  }

  private historyRowMeasureId(id: number): string {
    return `history_row_${id}`
  }

  /** 长按时实时测量条目相对 overlay 容器的 vp 坐标 */
  private measureHistoryRowArea(itemId: number): HistoryRowArea | null {
    const uiCtx = getBrowserUIContext()
    if (!uiCtx) {
      return null
    }
    try {
      const utils = uiCtx.getComponentUtils()
      const rowInfo = utils.getRectangleById(this.historyRowMeasureId(itemId))
      const hostInfo = utils.getRectangleById(HistoryPanel.CTX_HOST_ID)
      const rowWx = rowInfo.windowOffset.x as number
      const rowWy = rowInfo.windowOffset.y as number
      const hostWx = hostInfo.windowOffset.x as number
      const hostWy = hostInfo.windowOffset.y as number
      return {
        left: uiCtx.px2vp(rowWx - hostWx),
        top: uiCtx.px2vp(rowWy - hostWy),
        width: uiCtx.px2vp(rowInfo.size.width as number),
        height: uiCtx.px2vp(rowInfo.size.height as number)
      }
    } catch (err) {
      BrowserLog.warn(`[HistoryPanel] measureRowArea failed id=${itemId}: ${JSON.stringify(err)}`)
      return null
    }
  }

  /** 菜单锚点：紧贴浮起条目底边；底部空间不足时改在上方 */
  private computeHistoryMenuPos(rowLeft: number, rowTop: number, rowWidth: number, rowHeight: number): HistoryMenuPoint {
    const liftedH = rowHeight * HistoryPanel.LIFT_SCALE
    let menuX = rowLeft
    let menuY = rowTop + liftedH + HistoryPanel.MENU_GAP
    menuX = Math.max(16, Math.min(menuX, this.panelWidth - HistoryPanel.MENU_WIDTH - 16))
    const spaceBelow = this.panelHeight - menuY - HistoryPanel.MENU_BLOCK_HEIGHT - 16
    if (spaceBelow < 0) {
      menuY = rowTop - HistoryPanel.MENU_BLOCK_HEIGHT - HistoryPanel.MENU_GAP
    }
    menuY = Math.max(16, Math.min(menuY, this.panelHeight - HistoryPanel.MENU_BLOCK_HEIGHT - 16))
    return { x: menuX, y: menuY }
  }

  private openHistoryContextMenu(item: HistoryEntry): void {
    this.closeSwipeRows()
    const area = this.measureHistoryRowArea(item.id)
    const rowLeft = area?.left ?? 16
    const rowTop = area?.top ?? 120
    const rowWidth = area?.width ?? (this.panelWidth - 32)
    const rowHeight = area?.height ?? HistoryPanel.ROW_FALLBACK_HEIGHT
    const menuPos = this.computeHistoryMenuPos(rowLeft, rowTop, rowWidth, rowHeight)
    this.ctxRowLeft = rowLeft
    this.ctxRowTop = rowTop
    this.ctxRowWidth = rowWidth
    this.ctxRowHeight = rowHeight
    this.ctxMenuPosX = menuPos.x
    this.ctxMenuPosY = menuPos.y
    this.contextHistoryItem = item
    this.showRowContextMenu = true
  }

  private dismissHistoryContextMenu(): void {
    this.showRowContextMenu = false
    this.contextHistoryItem = null
  }

  /** 打开添加书签编辑弹窗（历史记录入口） */
  private openAddBookmarkDialog(item: HistoryEntry): void {
    if (BrowserStore.isPageBookmarked(item.url)) {
      return
    }
    this.addBookmarkDefaultTitle = item.title.trim() || tabHostname(item.url)
    this.addBookmarkTargetUrl = item.url
    this.showAddBookmarkDialog = true
  }

  private confirmAddBookmark(name: string, parentId: string): void {
    const url = this.addBookmarkTargetUrl
    this.showAddBookmarkDialog = false
    this.addBookmarkTargetUrl = ''
    if (url.length > 0) {
      void BrowserStore.addPageBookmark(name, url, parentId)
    }
  }

  build() {
    Stack() {
      // history_ctx_host：长按浮层坐标系锚点
      Column() {
        this.PanelHeader()

        Scroll(this.historyScrollScroller) {
          Column() {
            if (this.searchQueryHasInternalSpace()) {
              Text($r('app.string.no_search_results'))
                .fontSize(14)
                .fontColor(BrowserTheme.TEXT_MUTED)
                .padding(24)
            } else if (this.hasSearchQuery() && this.searchGroups.length === 0) {
              Text($r('app.string.no_search_results'))
                .fontSize(14)
                .fontColor(BrowserTheme.TEXT_MUTED)
                .padding(24)
            } else if (this.searchGroups.length === 0) {
              Text($r('app.string.history_empty'))
                .fontSize(14)
                .fontColor(BrowserTheme.TEXT_MUTED)
                .padding(24)
            } else {
              ForEach(this.searchGroups, (group: DateGroup<HistoryEntry>) => {
                this.HistorySection(group)
              }, (group: DateGroup<HistoryEntry>) => `${group.label}_${this.searchFilter}_${this.historyList.length}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: this.vm.batchMode ? BrowserSafeAreaInsets.batchBarScrollClearance() :
              BrowserSafeAreaInsets.bottom(0)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .enableScrollInteraction(!this.batchDragActive)
        .backgroundColor(BrowserTheme.PANEL_BG)
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
      .backgroundColor(BrowserTheme.PANEL_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.showMoreMenu) {
        PanelPopoverMenu({
          visible: this.showMoreMenu,
          darkMode: this.isDark(),
          items: this.moreMenuItems(),
          onDismiss: () => {
            this.showMoreMenu = false
          }
        })
      }
      if (this.showClearConfirm) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.clear_history_confirm')),
          confirmLabel: BrowserStrings.txt($r('app.string.clear')),
          onCancel: () => {
            this.showClearConfirm = false
          },
          onConfirm: () => {
            BrowserStore.clearHistory()
            this.showClearConfirm = false
            BrowserStore.showToast(BrowserStrings.txt($r('app.string.cleared')))
          }
        })
      }
      if (this.showDeleteConfirm) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.delete_history_confirm')),
          confirmLabel: BrowserStrings.txt($r('app.string.delete')),
          onCancel: () => {
            this.showDeleteConfirm = false
            this.vm.deleteTargetIds = []
          },
          onConfirm: () => this.confirmDelete()
        })
      }
      if (this.showRowContextMenu) {
        Column()
          .width('100%')
          .height('100%')
          .backdropBlur(24)
          .backgroundColor(Color.Transparent)
          .zIndex(4190)
          .hitTestBehavior(HitTestMode.Default)
          .onClick(() => {
            this.dismissHistoryContextMenu()
          })

        HistoryContextMenuLayer({
          visible: this.showRowContextMenu,
          darkMode: this.isDark(),
          item: this.contextHistoryItem,
          rowLeft: this.ctxRowLeft,
          rowTop: this.ctxRowTop,
          rowWidth: this.ctxRowWidth,
          rowHeight: this.ctxRowHeight,
          menuPosX: this.ctxMenuPosX,
          menuPosY: this.ctxMenuPosY,
          onDismiss: () => {
            this.dismissHistoryContextMenu()
          },
          onMultiSelect: () => {
            const item = this.contextHistoryItem
            this.dismissHistoryContextMenu()
            if (item) {
              this.vm.enterBatchWithItem(item.id)
            }
          },
          onAddBookmark: () => {
            const item = this.contextHistoryItem
            this.dismissHistoryContextMenu()
            if (item) {
              this.openAddBookmarkDialog(item)
            }
          },
          onShare: () => {
            const item = this.contextHistoryItem
            this.dismissHistoryContextMenu()
            if (item) {
              const shareOpts: OpenShareOptions = { title: item.title, url: item.url }
              BrowserStore.openShare(shareOpts)
            }
          },
          onOpenNewTab: () => {
            const item = this.contextHistoryItem
            this.dismissHistoryContextMenu()
            if (item) {
              // 对齐网页链接「在新标签页打开」：建签 + 跳转 BrowsePage，仅 addTab 不会打开目标页
              BrowserNavigation.openBrowse(item.url, {
                newTab: true,
                title: item.title.trim() || tabHostname(item.url)
              })
              this.onClose?.()
            }
          },
          onDelete: () => {
            const item = this.contextHistoryItem
            this.dismissHistoryContextMenu()
            if (item) {
              this.openDeleteConfirm([item.id])
            }
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(4200)
      }
      if (this.showAddBookmarkDialog) {
        AddBookmarkDialog({
          visible: true,
          defaultTitle: this.addBookmarkDefaultTitle,
          halfModal: true,
          url: this.addBookmarkTargetUrl,
          onCancel: (): void => {
            this.showAddBookmarkDialog = false
            this.addBookmarkTargetUrl = ''
          },
          onConfirm: (name: string, parentId: string): void => {
            this.confirmAddBookmark(name, parentId)
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BrowserTheme.PANEL_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .id(HistoryPanel.CTX_HOST_ID)
    .onAreaChange((_old, area) => {
      const w = area.width as number
      const h = area.height as number
      if (w > 0) {
        this.panelWidth = w
      }
      if (h > 0) {
        this.panelHeight = h
      }
    })
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
      searchPlaceholder: $r('app.string.history_search_placeholder'),
      onBack: () => {
        this.handleBack()
      },
      onSearch: () => {
        this.searchVisible = !this.searchVisible
        if (!this.searchVisible) {
          this.searchFilter = ''
        }
        this.refreshHistorySearch()
      },
      onSearchChange: (v: string) => {
        this.applySearchInput(v)
      },
      onSearchClear: () => {
        this.searchVisible = false
        this.searchFilter = ''
        this.refreshHistorySearch()
      },
      onMore: () => {
        this.showMoreMenu = true
      }
    })
  }

  @Builder
  HistorySection(group: DateGroup<HistoryEntry>) {
    Column() {
      Text(group.label)
        .fontSize(13)
        .fontColor('#9ca3af')
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 4, bottom: 8 })

      Column() {
        ForEach(group.items, (item: HistoryEntry) => {
          this.HistoryRow(item, this.isHistoryRowLast(group, item))
        }, (item: HistoryEntry) => {
          // 不含选中态/selectionRevision，避免滑动多选时整行重建导致图标闪烁
          return `${item.id}_${this.vm.batchMode ? 'batch' : 'normal'}_${this.searchFilter}_${item.iconUrl}`
        })
      }
      .width('100%')
      .backgroundColor(BrowserTheme.PANEL_BG)
      .borderRadius(12)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 16 })
  }

  @Builder
  HistoryRow(item: HistoryEntry, isLast: boolean) {
    if (this.vm.batchMode) {
      this.HistoryBatchRow(item, isLast)
    } else {
      this.HistoryNormalRow(item, isLast)
    }
  }

  @Builder
  HistoryBatchRow(item: HistoryEntry, isLast: boolean) {
    Column() {
      Row() {
        HistorySiteIcon({ url: item.url, iconUrl: item.iconUrl })
          .margin({ right: 10 })

        Column({ space: 2 }) {
          Text(item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
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
        .width(HistoryPanel.BATCH_CHECK_HIT)
        .height(HistoryPanel.BATCH_CHECK_HIT)
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
          .margin({ left: BookmarkFolderTree.dividerStartSite(), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.isSelected(item.id) ? BrowserTheme.PRIMARY_LIGHT : BrowserTheme.PANEL_BG)
    .id(this.historyRowMeasureId(item.id))
    .onAreaChange((_old, area) => {
      this.updateHistoryRowHitArea(item.id, area)
    })
  }

  @Builder
  HistoryNormalRow(item: HistoryEntry, isLast: boolean) {
    Column() {
      PanelSwipeDeleteRow({
        itemId: `${item.id}`,
        isLast: isLast,
        dividerLeft: BookmarkFolderTree.dividerStartSite(),
        rowMeasureId: this.historyRowMeasureId(item.id),
        openRowId: $swipeOpenRowId,
        dragRowId: $swipeDragRowId,
        dragOffsetX: $swipeDragOffsetX,
        onDelete: (id: string) => this.deleteHistoryById(Number(id)),
        onRowClick: () => {
          BrowserNavigation.openBrowse(item.url)
          this.onClose?.()
        },
        onLongPress: () => {
          this.openHistoryContextMenu(item)
        },
        row: () => {
          this.HistoryNormalRowContent(item)
        }
      })
    }
    .width('100%')
    .opacity(this.isContextMenuRow(item.id) ? 0 : 1)
  }

  @Builder
  HistoryNormalRowContent(item: HistoryEntry) {
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
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(BrowserTheme.PANEL_BG)
  }

  @Builder
  BatchBar() {
    // 与浏览页底栏一致：内容行固定高度，底边避让写在外层，避免 padding 挤占图标/文字
    Column() {
      Row() {
        HistoryBatchBtn({
          label: BrowserStrings.batchActionLabel('select_all'),
          iconKind: 'select_all',
          disabled: false,
          onTap: () => {
            this.vm.toggleSelectAll(this.filteredItems())
          }
        })
        HistoryBatchBtn({
          label: BrowserStrings.batchActionLabel('delete'),
          iconKind: 'delete',
          disabled: !this.batchDeleteEnabled(),
          danger: true,
          onTap: () => {
            this.vm.prepareBatchDeleteConfirm()
            this.showDeleteConfirm = true
          }
        })
      }
      .width('100%')
      .height(BrowserSafeAreaInsets.BATCH_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ bottom: BrowserSafeAreaInsets.batchBarBottomPadding() })
    .backgroundColor(BrowserTheme.PANEL_BG)
    .border({ width: { top: 1 }, color: BrowserTheme.BORDER })
  }

  private openDeleteConfirm(ids: number[]): void {
    if (ids.length === 0) {
      return
    }
    this.closeSwipeRows()
    this.vm.openDeleteConfirm(ids)
    this.showDeleteConfirm = true
  }

  private deleteHistoryById(id: number): void {
    if (!id) {
      return
    }
    this.openDeleteConfirm([id])
  }

  /** 确认删除历史记录（批量 / 左滑 / 长按菜单） */
  private confirmDelete(): void {
    const ids = this.vm.resolveDeleteIds()
    if (ids.length === 0) {
      this.showDeleteConfirm = false
      this.vm.deleteTargetIds = []
      return
    }
    this.vm.confirmDelete()
    this.showDeleteConfirm = false
  }

}
