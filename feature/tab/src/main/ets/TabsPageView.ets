import { BrowserLog } from 'common'
import { BrowserStrings } from 'common'
import { bindBrowserPageContext } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { TabEntry } from 'browser_core'
import { AppStorageKeys, cloneTab } from 'common'
import {
  HistorySiteIcon,
  IncognitoFootIcon,
  TAB_SWITCH_ACTIVE_COLOR,
  TAB_SWITCH_INACTIVE_COLOR,
  TabSwitchCountBadge,
  TabsBottomBackIcon,
  TabsBottomPlusIcon,
  TabsBottomTrashIcon
} from 'commons'
import { ShareSheet } from 'settings'
import { PanelConfirmDialog } from 'commons'
import { ToastBar } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'
import {
  gridPointCenterX,
  gridPointCenterY,
  GridLayoutMetrics,
  GridSqueezePath,
  GridTranslate,
  previewIndexOfId
} from 'home'
import { reorderArrayIds } from 'common'
import { TabManagementViewModel } from './TabManagementViewModel'

/** 标签管理页 View：网格、拖动排序与底部操作栏 */
@Component
export struct TabsPageView {
  @State vm: TabManagementViewModel = new TabManagementViewModel()
  @State gridEpoch: number = 0
  /** 首帧仅渲染壳层，下一帧再挂载网格，避免 pushUrl 同步阶段阻塞 */
  @State gridContentReady: boolean = false
  /** 缩略图异步写入后强制刷新 Image（配合 tabsRev 递增） */
  @State thumbRenderRev: number = 0
  private lastWithThumbCount: number = 0
  private static readonly THUMB_RETRY_DELAY_MS: number = 120
  /** 当前分区标签缓存，避免 build 中反复 filter 全量列表 */
  @State partitionTabList: TabEntry[] = []
  @State normalTabCount: number = 0
  @State incognitoTabCount: number = 0
  private lastTabsCount: number = 0
  private prepareRunning: boolean = false
  private prepareScheduled: boolean = false
  /** 左滑关闭：当前跟手的页签 id */
  @State swipingTabId: string = ''
  /** 整张标签卡片跟手位移（左滑为负） */
  @State tabCardDragX: number = 0
  private tabSwipeMoved: boolean = false
  private static readonly TAB_SWIPE_CLOSE_PX: number = 72
  private static readonly TAB_SWIPE_MAX_PX: number = 160
  private static readonly TAB_GRID_COLS: number = 2
  private static readonly TAB_COL_GAP: number = 12
  private static readonly TAB_ROW_GAP: number = 12
  private static readonly TAB_GRID_PADDING_H: number = 16
  private static readonly TAB_CELL_HEIGHT: number = 162
  private static readonly LONG_PRESS_MS: number = 300
  private static readonly DRAG_MOVE_THRESHOLD: number = 8
  private static readonly EDGE_SCROLL_ZONE: number = 72
  private static readonly EDGE_SCROLL_STEP: number = 18
  private static readonly EDGE_SCROLL_INTERVAL: number = 48
  /** 长按拖动排序 */
  @State draggingTabId: string = ''
  @State dragFromIndex: number = -1
  @State dragHoverIndex: number = -1
  @State dragSqueezeIndex: number = -1
  @State dragOffsetX: number = 0
  @State dragOffsetY: number = 0
  @State dragLiftVisible: boolean = false
  private tabScrollScroller: Scroller = new Scroller()
  private tabGridWidth: number = 0
  private gridOriginGlobalX: number = 0
  private gridOriginGlobalY: number = 0
  private scrollViewportTop: number = 0
  private scrollViewportHeight: number = 0
  private cellLayoutX: number[] = []
  private cellLayoutY: number[] = []
  private cellLayoutHeights: number[] = []
  /** 空闲时从首屏格实测的步长（仅作辅助，拖动期间用 frozen） */
  private tabColStepMeasured: number = 0
  private tabRowStepMeasured: number = 0
  private tabCellHeightMeasured: number = 0
  /** 拖动开始时冻结的槽位几何（公式推算，避免 63 标签 onAreaChange 污染） */
  private frozenColStep: number = 0
  private frozenRowStep: number = 0
  private frozenCellWidth: number = 0
  private frozenCellHeight: number = 0
  private frozenSlotTopX: number[] = []
  private frozenSlotTopY: number[] = []
  private frozenSlotCenterX: number[] = []
  private frozenSlotCenterY: number[] = []
  private gridMetricsSynced: boolean = false
  private tabPressTimer: number = -1
  private edgeScrollTimer: number = -1
  private edgeScrollDirection: number = 0
  private activeTabTouchId: string = ''
  private tabLongPressStarted: boolean = false
  private tabTouchOriginX: number = 0
  private tabTouchOriginY: number = 0
  /** 拖动开始时跟手层锚点（视口坐标，不随边缘滚动补偿） */
  private dragLiftBaseLeft: number = 0
  private dragLiftBaseTop: number = 0
  /** 拖动开始时 scroll 偏移，用于悬停槽位计算 */
  private dragStartScrollY: number = 0
  private suppressTabClick: boolean = false
  @StorageLink('browser_tabs') @Watch('onTabsStorageChanged') tabs: TabEntry[] = []
  @StorageLink('browser_tabs_rev') @Watch('onTabsStorageChanged') tabsRev: number = 0
  @StorageLink(AppStorageKeys.ACTIVE_TAB) activeTabId: string = ''
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  /** 无痕分区表面为专用深色，前景色按深色处理（含浅色主题） */
  private tabsUiDark(): boolean {
    return this.isDark() || this.vm.isIncognitoMode
  }

  private tabsPageBg(): string {
    return this.vm.isIncognitoMode ? BrowserTheme.INCOGNITO_NAV_BG : BrowserTheme.bg(this.isDark())
  }

  private tabsSurfaceBg(): string {
    return this.vm.isIncognitoMode ? BrowserTheme.INCOGNITO_ADDRESS_BG : BrowserTheme.surface(this.isDark())
  }

  private onTabsStorageChanged(): void {
    const count = this.tabs.length
    const withThumb = this.tabs.filter((t) => (t.thumbnailPath ?? '').length > 0).length
    const prevPartition = this.partitionTabList.map((t) => cloneTab(t))
    if (count !== this.lastTabsCount) {
      this.lastTabsCount = count
      this.gridEpoch++
    }
    this.rebuildPartitionCache()
    const displayChanged = this.hasTabDisplayChanged(this.partitionTabList, prevPartition)
    if (displayChanged || withThumb !== this.lastWithThumbCount) {
      this.thumbRenderRev++
      this.gridEpoch++
      this.lastWithThumbCount = withThumb
      BrowserLog.info(`TabsPage thumb/display changed withThumb=${withThumb}/${count} rev=${this.thumbRenderRev}`)
    }
    BrowserLog.info(`TabsPage tabs storage rev=${this.tabsRev} withThumb=${withThumb}/${count}`)
  }

  /** 单次遍历更新分区缓存与计数 */
  private rebuildPartitionCache(): void {
    let normalCount = 0
    let incognitoCount = 0
    const normal: TabEntry[] = []
    const incognito: TabEntry[] = []
    for (const tab of this.tabs) {
      if (tab.isIncognito) {
        incognitoCount++
        incognito.push(tab)
      } else {
        normalCount++
        normal.push(tab)
      }
    }
    this.normalTabCount = normalCount
    this.incognitoTabCount = incognitoCount
    const list = this.vm.isIncognitoMode ? incognito : normal
    list.sort((a, b) => a.sortOrder - b.sortOrder)
    this.normalTabCount = normalCount
    this.incognitoTabCount = incognitoCount
    const displayChanged = this.hasTabDisplayChanged(list, this.partitionTabList)
    if (this.isSameTabIdOrder(list, this.partitionTabList) && !displayChanged) {
      return
    }
    // 缩略图等字段变化时须克隆新数组，触发 ForEach 与 @Prop 下发
    this.partitionTabList = list.map((t) => cloneTab(t))
    if (displayChanged) {
      const thumbSummary = list.map((t) =>
        `${t.id.slice(-6)}:${(t.thumbnailPath ?? '').length}`).join(',')
      BrowserLog.info(`TabsPage partition refresh count=${this.partitionTabList.length} thumbs=${thumbSummary}`)
    }
  }

  /** 标签顺序不变时，缩略图/标题等局部字段是否变化 */
  private hasTabDisplayChanged(next: TabEntry[], current: TabEntry[]): boolean {
    if (next.length !== current.length) {
      return true
    }
    for (let i = 0; i < next.length; i++) {
      const a = next[i]
      const b = current[i]
      if (a.thumbnailPath !== b.thumbnailPath ||
        a.updatedAt !== b.updatedAt ||
        a.title !== b.title ||
        a.url !== b.url ||
        a.isHome !== b.isHome) {
        return true
      }
    }
    return false
  }

  private isSameTabIdOrder(next: TabEntry[], current: TabEntry[]): boolean {
    if (next.length !== current.length) {
      return false
    }
    for (let i = 0; i < next.length; i++) {
      if (next[i].id !== current[i].id) {
        return false
      }
    }
    return true
  }

  private isTabDragging(): boolean {
    return this.draggingTabId.length > 0
  }

  private currentScrollYOffset(): number {
    return this.tabScrollScroller.currentOffset()?.yOffset ?? 0
  }

  private tabColStep(): number {
    if (this.isTabDragging() && this.frozenColStep > 0) {
      return this.frozenColStep
    }
    if (this.tabColStepMeasured > 0) {
      return this.tabColStepMeasured
    }
    return this.formulaColStep()
  }

  private tabRowStep(): number {
    if (this.isTabDragging() && this.frozenRowStep > 0) {
      return this.frozenRowStep
    }
    if (this.tabRowStepMeasured > 0) {
      return this.tabRowStepMeasured
    }
    return this.formulaRowStep()
  }

  private formulaCellWidth(): number {
    if (this.tabGridWidth <= 0) {
      return 160
    }
    return (this.tabGridWidth - TabsPageView.TAB_GRID_PADDING_H * 2 - TabsPageView.TAB_COL_GAP) /
      TabsPageView.TAB_GRID_COLS
  }

  private formulaColStep(): number {
    return this.formulaCellWidth() + TabsPageView.TAB_COL_GAP
  }

  private formulaRowStep(): number {
    return this.tabCellHeight() + TabsPageView.TAB_ROW_GAP
  }

  private tabCellHeight(): number {
    if (this.tabCellHeightMeasured > 0) {
      return this.tabCellHeightMeasured
    }
    return TabsPageView.TAB_CELL_HEIGHT
  }

  private tabGridMetrics(): GridLayoutMetrics {
    return {
      cols: TabsPageView.TAB_GRID_COLS,
      colStep: this.tabColStep(),
      rowStep: this.tabRowStep(),
      colGap: TabsPageView.TAB_COL_GAP,
      paddingLeft: TabsPageView.TAB_GRID_PADDING_H,
      paddingTop: 0,
      cellContentHeight: this.tabCellHeight()
    }
  }

  /** 从首屏相邻格推断步长（仅接受接近公式值的实测，防止 63 标签布局污染） */
  private syncTabGridMetricsOnce(): void {
    if (this.gridMetricsSynced && !this.isTabDragging()) {
      return
    }
    const formulaCol = this.formulaColStep()
    const formulaRow = this.formulaRowStep()
    const measuredCol = this.inferTabColStepFromLayout()
    const measuredRow = this.inferTabRowStepFromLayout()
    this.tabColStepMeasured = measuredCol > 0 && Math.abs(measuredCol - formulaCol) < 20 ?
      measuredCol : formulaCol
    this.tabRowStepMeasured = measuredRow > 0 && Math.abs(measuredRow - formulaRow) < 24 ?
      measuredRow : formulaRow
    if (this.cellLayoutHeights.length > 0 && this.cellLayoutHeights[0] > 0) {
      this.tabCellHeightMeasured = this.cellLayoutHeights[0]
    }
    this.gridMetricsSynced = true
  }

  /** 拖动开始：冻结全部分区槽位的 top-left / center（公式 + 首行实测校准） */
  private freezeDragSlotLayout(fromIndex: number): void {
    this.syncTabGridMetricsOnce()
    let colStep = this.tabColStepMeasured > 0 ? this.tabColStepMeasured : this.formulaColStep()
    let rowStep = this.tabRowStepMeasured > 0 ? this.tabRowStepMeasured : this.formulaRowStep()
    const cellH = this.tabCellHeight()
    const cellW = colStep - TabsPageView.TAB_COL_GAP

    // 用首列 row0→row1 实测校准 rowStep（仅当与公式接近）
    const y0 = this.cellLayoutY[0]
    const yRow1 = this.cellLayoutY[TabsPageView.TAB_GRID_COLS]
    if (!Number.isNaN(y0) && !Number.isNaN(yRow1) && yRow1 > y0) {
      const dy = yRow1 - y0
      if (dy >= 130 && dy <= 220) {
        rowStep = dy
      }
    }
    const x0 = this.cellLayoutX[0]
    const x1 = this.cellLayoutX[1]
    if (!Number.isNaN(x0) && !Number.isNaN(x1)) {
      const dx = Math.abs(x1 - x0)
      if (dx >= 80 && Math.abs(dx - colStep) < 24) {
        colStep = dx
      }
    }

    this.frozenColStep = colStep
    this.frozenRowStep = rowStep
    this.frozenCellWidth = cellW
    this.frozenCellHeight = cellH
    this.frozenSlotTopX = []
    this.frozenSlotTopY = []
    this.frozenSlotCenterX = []
    this.frozenSlotCenterY = []
    const count = this.partitionTabList.length
    for (let i = 0; i < count; i++) {
      const col = i % TabsPageView.TAB_GRID_COLS
      const row = Math.floor(i / TabsPageView.TAB_GRID_COLS)
      const topX = TabsPageView.TAB_GRID_PADDING_H + col * colStep
      const topY = row * rowStep
      this.frozenSlotTopX.push(topX)
      this.frozenSlotTopY.push(topY)
      this.frozenSlotCenterX.push(topX + cellW * 0.5)
      this.frozenSlotCenterY.push(topY + cellH * 0.5)
    }
    BrowserLog.info(`[TabsPage] freeze layout count=${count} colStep=${colStep.toFixed(1)} ` +
      `rowStep=${rowStep.toFixed(1)} cell=${cellW.toFixed(0)}x${cellH} from=${fromIndex}`)
  }

  private clearFrozenDragLayout(): void {
    this.frozenColStep = 0
    this.frozenRowStep = 0
    this.frozenCellWidth = 0
    this.frozenCellHeight = 0
    this.frozenSlotTopX = []
    this.frozenSlotTopY = []
    this.frozenSlotCenterX = []
    this.frozenSlotCenterY = []
  }

  private frozenSlotCenter(index: number): GridTranslate {
    if (index >= 0 && index < this.frozenSlotCenterX.length) {
      return { x: this.frozenSlotCenterX[index], y: this.frozenSlotCenterY[index] }
    }
    const col = index % TabsPageView.TAB_GRID_COLS
    const row = Math.floor(index / TabsPageView.TAB_GRID_COLS)
    const cellW = this.frozenCellWidth > 0 ? this.frozenCellWidth : this.formulaCellWidth()
    const colStep = this.frozenColStep > 0 ? this.frozenColStep : this.formulaColStep()
    const rowStep = this.frozenRowStep > 0 ? this.frozenRowStep : this.formulaRowStep()
    const cellH = this.frozenCellHeight > 0 ? this.frozenCellHeight : this.tabCellHeight()
    const topX = TabsPageView.TAB_GRID_PADDING_H + col * colStep
    const topY = row * rowStep
    return { x: topX + cellW * 0.5, y: topY + cellH * 0.5 }
  }

  private frozenSlotTopLeft(index: number): GridTranslate {
    if (index >= 0 && index < this.frozenSlotTopX.length) {
      return { x: this.frozenSlotTopX[index], y: this.frozenSlotTopY[index] }
    }
    const c = this.frozenSlotCenter(index)
    const cellW = this.frozenCellWidth > 0 ? this.frozenCellWidth : this.formulaCellWidth()
    const cellH = this.frozenCellHeight > 0 ? this.frozenCellHeight : this.tabCellHeight()
    return { x: c.x - cellW * 0.5, y: c.y - cellH * 0.5 }
  }

  private inferTabColStepFromLayout(): number {
    const cols = TabsPageView.TAB_GRID_COLS
    for (let i = 0; i < this.cellLayoutX.length; i++) {
      const j = i + 1
      if (j >= this.cellLayoutX.length || j % cols === 0) {
        continue
      }
      const x0 = this.cellLayoutX[i]
      const x1 = this.cellLayoutX[j]
      if (Number.isNaN(x0) || Number.isNaN(x1)) {
        continue
      }
      const dx = Math.abs(x1 - x0)
      if (dx >= 80 && dx < 600) {
        return dx
      }
    }
    return 0
  }

  private inferTabRowStepFromLayout(): number {
    const cols = TabsPageView.TAB_GRID_COLS
    const y0 = this.cellLayoutY[0]
    const yRow1 = this.cellLayoutY[cols]
    if (!Number.isNaN(y0) && !Number.isNaN(yRow1) && yRow1 > y0) {
      const dy = yRow1 - y0
      if (dy >= 130 && dy <= 280) {
        return dy
      }
    }
    for (let r = 0; r + 1 < Math.ceil(this.cellLayoutY.length / cols); r++) {
      const top = this.cellLayoutY[r * cols]
      const bottom = this.cellLayoutY[(r + 1) * cols]
      if (Number.isNaN(top) || Number.isNaN(bottom) || bottom <= top) {
        continue
      }
      const dy = bottom - top
      if (dy >= 130 && dy <= 280) {
        return dy
      }
    }
    return 0
  }

  private isTabCellLayoutYValid(index: number): boolean {
    const y = this.cellLayoutY[index]
    if (Number.isNaN(y)) {
      return false
    }
    const cols = TabsPageView.TAB_GRID_COLS
    const row = Math.floor(index / cols)
    if (row === 0) {
      return true
    }
    const above = index - cols
    if (above >= 0 && !Number.isNaN(this.cellLayoutY[above])) {
      return y > this.cellLayoutY[above]
    }
    return true
  }

  /** 标签槽位中心 X：优先实测，同列按 colStep 外推 */
  private resolveTabSlotCenterX(index: number): number {
    if (index >= 0 && index < this.cellLayoutX.length && !Number.isNaN(this.cellLayoutX[index])) {
      return this.cellLayoutX[index]
    }
    const cols = TabsPageView.TAB_GRID_COLS
    const col = index % cols
    if (col < this.cellLayoutX.length && !Number.isNaN(this.cellLayoutX[col])) {
      return this.cellLayoutX[col] + col * this.tabColStep()
    }
    return gridPointCenterX(col, this.tabGridMetrics())
  }

  /** 标签槽位中心 Y：优先实测，同列按 rowStep 外推（禁用快捷方式 contentHalf 回退） */
  private resolveTabSlotCenterY(index: number): number {
    if (index >= 0 && index < this.cellLayoutY.length && this.isTabCellLayoutYValid(index)) {
      return this.cellLayoutY[index]
    }
    const cols = TabsPageView.TAB_GRID_COLS
    const col = index % cols
    const row = Math.floor(index / cols)
    if (col < this.cellLayoutY.length && this.isTabCellLayoutYValid(col)) {
      return this.cellLayoutY[col] + row * this.tabRowStep()
    }
    return gridPointCenterY(row, this.tabGridMetrics())
  }

  private tabSqueezePathForCell(cellIndex: number, dragFrom: number, dragHover: number): GridSqueezePath {
    const z: GridTranslate = { x: 0, y: 0 }
    const empty: GridSqueezePath = {
      outer: z,
      inner: z,
      crossRow: false
    }
    if (dragFrom < 0 || dragHover < 0 || dragFrom === dragHover || cellIndex === dragFrom) {
      return empty
    }
    const ids = this.partitionTabList.map((t) => t.id)
    const previewIds = reorderArrayIds(ids, dragFrom, dragHover)
    const targetIndex: number = previewIndexOfId(ids[cellIndex], previewIds)
    if (targetIndex < 0 || targetIndex === cellIndex) {
      return empty
    }
    const fromTL: GridTranslate = this.frozenSlotTopLeft(cellIndex)
    const toTL: GridTranslate = this.frozenSlotTopLeft(targetIndex)
    const row0: number = Math.floor(cellIndex / TabsPageView.TAB_GRID_COLS)
    const row1: number = Math.floor(targetIndex / TabsPageView.TAB_GRID_COLS)
    const outer: GridTranslate = { x: toTL.x - fromTL.x, y: toTL.y - fromTL.y }
    const inner: GridTranslate = { x: 0, y: 0 }
    return {
      outer: outer,
      inner: inner,
      crossRow: row0 !== row1
    }
  }

  private clearTabPressTimer(): void {
    if (this.tabPressTimer >= 0) {
      clearTimeout(this.tabPressTimer)
      this.tabPressTimer = -1
    }
  }

  private stopEdgeScroll(): void {
    if (this.edgeScrollTimer >= 0) {
      clearInterval(this.edgeScrollTimer)
      this.edgeScrollTimer = -1
    }
    this.edgeScrollDirection = 0
  }

  private updateEdgeAutoScroll(offsetY: number): void {
    if (!this.isTabDragging()) {
      this.stopEdgeScroll()
      return
    }
    const originY: number = this.frozenSlotCenter(this.dragFromIndex).y
    const fingerViewportY: number = originY + offsetY - this.currentScrollYOffset()
    const viewH: number = this.scrollViewportHeight
    const scrollY: number = this.currentScrollYOffset()
    if (fingerViewportY < TabsPageView.EDGE_SCROLL_ZONE) {
      if (scrollY > 1) {
        this.startEdgeScroll(-1)
      } else {
        this.stopEdgeScroll()
      }
    } else if (fingerViewportY > viewH - TabsPageView.EDGE_SCROLL_ZONE) {
      this.startEdgeScroll(1)
    } else {
      this.stopEdgeScroll()
    }
  }

  private startEdgeScroll(direction: number): void {
    if (this.edgeScrollTimer >= 0 && this.edgeScrollDirection === direction) {
      return
    }
    this.stopEdgeScroll()
    this.edgeScrollDirection = direction
    this.edgeScrollTimer = setInterval(() => {
      const current = this.currentScrollYOffset()
      if (direction < 0 && current <= 0) {
        this.stopEdgeScroll()
        return
      }
      const next = Math.max(0, current + direction * TabsPageView.EDGE_SCROLL_STEP)
      if (next === current) {
        this.stopEdgeScroll()
        return
      }
      this.tabScrollScroller.scrollTo({ xOffset: 0, yOffset: next, animation: false })
      // 仅通过 scroll 增量更新悬停槽位，不修改跟手 offset
      this.applyTabDragHover(this.dragOffsetX, this.dragOffsetY)
    }, TabsPageView.EDGE_SCROLL_INTERVAL) as number
  }

  private updateCellLayout(index: number, centerX: number, centerY: number, height: number): void {
    while (this.cellLayoutX.length <= index) {
      this.cellLayoutX.push(Number.NaN)
      this.cellLayoutY.push(Number.NaN)
      this.cellLayoutHeights.push(0)
    }
    this.cellLayoutX[index] = centerX
    this.cellLayoutY[index] = centerY
    if (height > 0) {
      this.cellLayoutHeights[index] = height
    }
  }

  private computeTabDropIndex(offsetX: number, offsetY: number): number {
    const scrollDelta = this.currentScrollYOffset() - this.dragStartScrollY
    const origin = this.frozenSlotCenter(this.dragFromIndex)
    const fingerX: number = origin.x + offsetX
    const fingerY: number = origin.y + offsetY + scrollDelta
    let bestIdx = 0
    let bestDist = Number.MAX_VALUE
    const count = this.partitionTabList.length
    for (let i = 0; i < count; i++) {
      const slot = this.frozenSlotCenter(i)
      const dx = fingerX - slot.x
      const dy = fingerY - slot.y
      const dist = dx * dx + dy * dy
      if (dist < bestDist) {
        bestDist = dist
        bestIdx = i
      }
    }
    return Math.min(bestIdx, Math.max(0, count - 1))
  }

  private applyTabDragHover(offsetX: number, offsetY: number): void {
    if (!this.isTabDragging() || this.dragFromIndex < 0) {
      return
    }
    const hover = this.computeTabDropIndex(offsetX, offsetY)
    if (hover !== this.dragHoverIndex) {
      this.dragHoverIndex = hover
    }
    if (hover !== this.dragSqueezeIndex) {
      this.dragSqueezeIndex = hover
    }
  }

  private syncDragLiftAnchor(index: number): void {
    this.freezeDragSlotLayout(index)
    this.dragStartScrollY = this.currentScrollYOffset()
    const topLeft = this.frozenSlotTopLeft(index)
    this.dragLiftBaseLeft = topLeft.x
    this.dragLiftBaseTop = topLeft.y - this.dragStartScrollY
    BrowserLog.info(`[TabsPage] lift anchor index=${index} base=(${this.dragLiftBaseLeft.toFixed(0)},` +
      `${this.dragLiftBaseTop.toFixed(0)}) scrollY=${this.dragStartScrollY}`)
  }

  private startTabDrag(index: number, tabId: string): void {
    this.resetTabSwipeState()
    this.stopEdgeScroll()
    this.clearFrozenDragLayout()
    this.dragFromIndex = index
    this.dragHoverIndex = index
    this.dragSqueezeIndex = index
    this.draggingTabId = tabId
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.syncDragLiftAnchor(index)
    this.dragLiftVisible = true
    this.suppressTabClick = true
    this.activeTabTouchId = tabId
    this.tabLongPressStarted = true
    BrowserLog.info(`[TabsPage] drag start tabId=${tabId} index=${index}`)
  }

  private endTabDrag(): void {
    this.clearTabPressTimer()
    this.stopEdgeScroll()
    this.dragFromIndex = -1
    this.dragHoverIndex = -1
    this.dragSqueezeIndex = -1
    this.draggingTabId = ''
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.dragLiftBaseLeft = 0
    this.dragLiftBaseTop = 0
    this.dragStartScrollY = 0
    this.clearFrozenDragLayout()
    this.dragLiftVisible = false
    this.activeTabTouchId = ''
    this.tabLongPressStarted = false
    setTimeout(() => {
      this.suppressTabClick = false
    }, 80)
  }

  /** 松手落位：先重排本地列表，再同一帧清空拖动/挤位（对齐首页，无异步落位动画，避免冻屏） */
  private commitTabReorder(from: number, to: number): void {
    const ids = this.partitionTabList.map((t) => t.id)
    const reordered = reorderArrayIds(ids, from, to)
    const map = new Map(this.partitionTabList.map((t) => [t.id, t]))
    this.partitionTabList = reordered.map((id) => map.get(id)!)
    this.endTabDrag()
    this.vm.reorderTabs(from, to)
  }

  private onTabDragPanUpdate(tabId: string, offsetX: number, offsetY: number): void {
    if (this.draggingTabId !== tabId) {
      return
    }
    this.dragOffsetX = offsetX
    this.dragOffsetY = offsetY
    this.applyTabDragHover(offsetX, offsetY)
    this.updateEdgeAutoScroll(offsetY)
  }

  private finishTabDragGesture(tabId: string, offsetX: number, offsetY: number): void {
    this.stopEdgeScroll()
    if (this.draggingTabId !== tabId) {
      return
    }
    this.applyTabDragHover(offsetX, offsetY)
    const from = this.dragFromIndex
    const to = this.dragHoverIndex
    if (from >= 0 && to >= 0 && from !== to &&
      (Math.abs(offsetX) > TabsPageView.DRAG_MOVE_THRESHOLD ||
        Math.abs(offsetY) > TabsPageView.DRAG_MOVE_THRESHOLD)) {
      this.commitTabReorder(from, to)
      return
    }
    this.endTabDrag()
  }

  private tabSqueezeTranslate(index: number, tabId: string): GridTranslate {
    if (!this.isTabDragging() || this.dragFromIndex < 0 || this.dragSqueezeIndex < 0) {
      return { x: 0, y: 0 }
    }
    if (tabId === this.draggingTabId) {
      return { x: 0, y: 0 }
    }
    const path = this.tabSqueezePathForCell(index, this.dragFromIndex, this.dragSqueezeIndex)
    return { x: path.outer.x + path.inner.x, y: path.outer.y + path.inner.y }
  }

  private isDraggedTabCell(tabId: string): boolean {
    return this.draggingTabId === tabId && this.dragLiftVisible
  }

  private onTabCardTouch(tab: TabEntry, index: number, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.activeTabTouchId = tab.id
      this.tabLongPressStarted = false
      const touch = event.touches[0]
      if (touch) {
        this.tabTouchOriginX = touch.x
        this.tabTouchOriginY = touch.y
      }
      this.clearTabPressTimer()
      this.tabPressTimer = setTimeout(() => {
        this.tabPressTimer = -1
        if (this.activeTabTouchId !== tab.id) {
          return
        }
        if (this.isTabDragging() && this.draggingTabId !== tab.id) {
          return
        }
        this.tabLongPressStarted = true
        this.startTabDrag(index, tab.id)
      }, TabsPageView.LONG_PRESS_MS)
      return
    }
    if (this.activeTabTouchId !== tab.id) {
      return
    }
    const touch = event.touches[0] ?? event.changedTouches[0]
    if (!touch) {
      return
    }
    const dx = touch.x - this.tabTouchOriginX
    const dy = touch.y - this.tabTouchOriginY
    if (event.type === TouchType.Move) {
      if (!this.tabLongPressStarted &&
        (Math.abs(dx) > TabsPageView.DRAG_MOVE_THRESHOLD || Math.abs(dy) > TabsPageView.DRAG_MOVE_THRESHOLD)) {
        this.clearTabPressTimer()
      }
      if (this.draggingTabId === tab.id) {
        this.onTabDragPanUpdate(tab.id, dx, dy)
        return
      }
      if (!this.tabLongPressStarted && dx < -6 && Math.abs(dx) > Math.abs(dy)) {
        this.onTabCardSwipeStart(tab.id)
        this.onTabCardSwipeUpdate(tab.id, dx)
      } else if (this.swipingTabId === tab.id) {
        this.onTabCardSwipeUpdate(tab.id, dx)
      }
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearTabPressTimer()
      if (this.draggingTabId === tab.id) {
        this.finishTabDragGesture(tab.id, dx, dy)
      } else if (this.swipingTabId === tab.id) {
        this.onTabCardSwipeEnd(tab.id)
      } else if (!this.tabLongPressStarted) {
        const moved = Math.abs(dx) > TabsPageView.DRAG_MOVE_THRESHOLD ||
          Math.abs(dy) > TabsPageView.DRAG_MOVE_THRESHOLD
        if (!moved && !this.suppressTabClick) {
          this.vm.openTab(tab)
        }
      }
      this.activeTabTouchId = ''
      this.tabLongPressStarted = false
    }
  }

  /** 关闭标签并刷新网格 */
  private closeTab(tabId: string): void {
    this.resetTabSwipeState()
    void this.vm.closeTab(tabId).then(() => {
      this.gridEpoch++
    })
  }

  /** 是否为当前分区最新活跃页签（外边框选中） */
  private isActiveTab(tab: TabEntry): boolean {
    if (this.activeTabId.length > 0) {
      return tab.id === this.activeTabId
    }
    return tab.isActive
  }

  private activeTabBorderWidth(tab: TabEntry): number {
    return this.isActiveTab(tab) ? 2 : 1
  }

  private activeTabBorderColor(tab: TabEntry): ResourceColor {
    return this.isActiveTab(tab) ?
      BrowserTheme.primaryColor(this.tabsUiDark()) :
      BrowserTheme.borderColor(this.tabsUiDark())
  }

  private handleCloseTabClick(tabId: string): void {
    this.clearTabPressTimer()
    this.activeTabTouchId = ''
    this.tabLongPressStarted = false
    this.suppressTabClick = true
    this.closeTab(tabId)
    setTimeout(() => {
      this.suppressTabClick = false
    }, 80)
  }

  private bottomActionOpacity(enabled: boolean): number {
    return enabled ? 1 : 0.35
  }

  private bottomActionColor(enabled: boolean): ResourceColor {
    return enabled ?
      BrowserTheme.text(this.tabsUiDark()) :
      BrowserTheme.textMuted(this.tabsUiDark())
  }

  private bottomHitTest(enabled: boolean): HitTestMode {
    return enabled ? HitTestMode.Default : HitTestMode.None
  }

  private resetTabSwipeState(): void {
    this.swipingTabId = ''
    this.tabCardDragX = 0
    this.tabSwipeMoved = false
  }

  private tabCardDragOffset(tabId: string): number {
    return this.swipingTabId === tabId ? this.tabCardDragX : 0
  }

  private tabCardDragOpacity(tabId: string): number {
    if (this.swipingTabId !== tabId || this.tabCardDragX >= 0) {
      return 1
    }
    return Math.max(0.45, 1 + this.tabCardDragX / TabsPageView.TAB_SWIPE_MAX_PX * 0.55)
  }

  private onTabCardSwipeStart(tabId: string): void {
    this.swipingTabId = tabId
    this.tabCardDragX = 0
    this.tabSwipeMoved = false
  }

  private onTabCardSwipeUpdate(tabId: string, offsetX: number): void {
    if (this.swipingTabId !== tabId) {
      return
    }
    if (Math.abs(offsetX) > 6) {
      this.tabSwipeMoved = true
    }
    this.tabCardDragX = offsetX >= 0 ? 0 : Math.max(offsetX, -TabsPageView.TAB_SWIPE_MAX_PX)
  }

  private onTabCardSwipeEnd(tabId: string): void {
    if (this.swipingTabId !== tabId) {
      return
    }
    if (this.tabCardDragX < -TabsPageView.TAB_SWIPE_CLOSE_PX) {
      BrowserLog.info(`[TabsPage] swipe close tabId=${tabId} offset=${this.tabCardDragX.toFixed(0)}`)
      animateTo({
        duration: 180,
        curve: Curve.EaseOut,
        onFinish: () => {
          this.closeTab(tabId)
        }
      }, () => {
        this.tabCardDragX = -TabsPageView.TAB_SWIPE_MAX_PX
      })
      return
    }
    animateTo({
      duration: 220,
      curve: Curve.FastOutSlowIn,
      onFinish: () => {
        this.resetTabSwipeState()
      }
    }, () => {
      this.tabCardDragX = 0
    })
  }

  private onTabCardSwipeCancel(tabId: string): void {
    if (this.swipingTabId !== tabId) {
      return
    }
    animateTo({
      duration: 200,
      curve: Curve.FastOutSlowIn,
      onFinish: () => {
        this.resetTabSwipeState()
      }
    }, () => {
      this.tabCardDragX = 0
    })
  }

  private openTabIfNotSwiping(tab: TabEntry): void {
    if (this.tabSwipeMoved || this.suppressTabClick || this.isTabDragging()) {
      this.tabSwipeMoved = false
      return
    }
    this.vm.openTab(tab)
  }

  /** 切换普通/无痕分区并刷新本地缓存 */
  private onSwitchPartition(incognito: boolean): void {
    this.vm.switchTabPartition(incognito)
    this.rebuildPartitionCache()
    this.gridEpoch++
  }

  /** 延迟到下一帧再跑数据准备，不阻塞路由首帧 */
  private schedulePreparePageData(): void {
    if (this.prepareScheduled) {
      return
    }
    this.prepareScheduled = true
    setTimeout(() => {
      this.prepareScheduled = false
      void this.preparePageData()
    }, 0)
  }

  /** 分帧挂载网格，避免 pushUrl 同步阶段阻塞 */
  private scheduleGridContent(): void {
    if (this.gridContentReady) {
      return
    }
    setTimeout(() => {
      this.gridContentReady = true
      BrowserLog.info(`TabsPage grid ready count=${this.partitionTabList.length}`)
    }, 0)
  }

  /** 标签已由 StorageLink 注入；仅空列表时等待 init，缩略图补抓一律延后 */
  private async preparePageData(): Promise<void> {
    if (this.prepareRunning) {
      BrowserLog.info('preparePageData skip concurrent')
      return
    }
    this.prepareRunning = true
    BrowserLog.info('preparePageData begin')
    try {
      if (this.tabs.length === 0) {
        await BrowserStore.whenReady()
      }
      this.rebuildPartitionCache()
      setTimeout(() => {
        BrowserStore.requestMissingTabThumbnails(this.partitionTabList, 3)
      }, TabsPageView.THUMB_RETRY_DELAY_MS)
      BrowserLog.info(`preparePageData end storageTabs=${this.tabs.length} partition=${this.partitionTabList.length} rev=${this.tabsRev}`)
    } finally {
      this.prepareRunning = false
    }
  }

  aboutToAppear(): void {
    bindBrowserPageContext(this.getUIContext())
    this.vm.initPartitionFromRoute()
    this.lastWithThumbCount = 0
    this.rebuildPartitionCache()
    BrowserLog.info(`aboutToAppear incognitoMode=${this.vm.isIncognitoMode}`)
    if (!this.gridContentReady) {
      this.scheduleGridContent()
    }
    this.schedulePreparePageData()
  }

  onPageShow(): void {
    bindBrowserPageContext(this.getUIContext())
    BrowserLog.info('onPageShow')
    if (!this.gridContentReady) {
      this.scheduleGridContent()
    }
    this.schedulePreparePageData()
  }

  aboutToDisappear(): void {
    this.clearTabPressTimer()
    this.stopEdgeScroll()
    this.endTabDrag()
  }

  build() {
    Stack() {
      Column() {
        this.TabsSwitcher()
        this.TabsGrid()
        this.BottomBar()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.safeAreaTop })
      .backgroundColor(this.tabsPageBg())

      if (this.vm.showCloseAllDialog) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.close_all_tabs_confirm')),
          confirmLabel: BrowserStrings.txt($r('app.string.close_all')),
          cancelLabel: BrowserStrings.txt($r('app.string.cancel')),
          onCancel: () => {
            this.vm.showCloseAllDialog = false
          },
          onConfirm: () => {
            this.vm.handleCloseAll()
          }
        })
      }

      ShareSheet()
      ToastBar()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabsSwitcher() {
    Column() {
      Row({ space: 2 }) {
        Row() {
          TabSwitchCountBadge({
            count: this.vm.displayTabCount(this.normalTabCount),
            color: this.vm.isIncognitoMode ? TAB_SWITCH_INACTIVE_COLOR : TAB_SWITCH_ACTIVE_COLOR,
            boxSize: 18
          })
        }
        .layoutWeight(1)
        .padding({ top: 8, bottom: 8 })
        .justifyContent(FlexAlign.Center)
        .borderRadius(999)
        .backgroundColor(this.vm.isIncognitoMode ? Color.Transparent : BrowserTheme.surface(this.isDark()))
        .shadow(this.vm.isIncognitoMode ? undefined : {
          radius: 4,
          color: 'rgba(0, 0, 0, 0.08)',
          offsetX: 0,
          offsetY: 1
        })
        .onClick(() => {
          this.onSwitchPartition(false)
        })

        Row({ space: 4 }) {
          IncognitoFootIcon({
            color: this.vm.isIncognitoMode ? TAB_SWITCH_ACTIVE_COLOR : TAB_SWITCH_INACTIVE_COLOR
          })
          if (this.incognitoTabCount > 0) {
            Text(this.vm.displayTabCount(this.incognitoTabCount).toString())
              .fontSize(BrowserTheme.uiFontSize(13))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.vm.isIncognitoMode ? TAB_SWITCH_ACTIVE_COLOR : TAB_SWITCH_INACTIVE_COLOR)
              .height(18)
              .textAlign(TextAlign.Center)
              // 数字字形基线偏上，略下移以与 18 图标目测居中
              .translate({ y: 0.5 })
          }
        }
        .layoutWeight(1)
        .padding({ top: 8, bottom: 8 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(999)
        .backgroundColor(!this.vm.isIncognitoMode ? Color.Transparent : BrowserTheme.surface(this.isDark()))
        .shadow(!this.vm.isIncognitoMode ? undefined : {
          radius: 4,
          color: 'rgba(0, 0, 0, 0.08)',
          offsetX: 0,
          offsetY: 1
        })
        .onClick(() => {
          this.onSwitchPartition(true)
        })
      }
      .width('100%')
      .padding(4)
      .backgroundColor(this.tabsUiDark() ? 'rgba(255, 255, 255, 0.10)' : 'rgba(0, 0, 0, 0.06)')
      .borderRadius(999)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 12 })
  }

  @Builder
  TabsGrid() {
    if (!this.gridContentReady) {
      Column()
        .width('100%')
        .layoutWeight(1)
    } else if (this.vm.isIncognitoMode && this.incognitoTabCount === 0) {
      Column() {
        Text($r('app.string.incognito_mode_title'))
          .fontSize(BrowserTheme.uiFontSize(17))
          .fontWeight(FontWeight.Bold)
          .fontColor(BrowserTheme.text(this.tabsUiDark()))
          .margin({ top: 40 })

        Text($r('app.string.incognito_empty_hint'))
          .fontSize(BrowserTheme.uiFontSize(14))
          .fontColor(BrowserTheme.textMuted(this.tabsUiDark()))
          .margin({ top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll(this.tabScrollScroller) {
          Grid() {
            ForEach(this.partitionTabList, (tab: TabEntry, index: number) => {
              GridItem() {
                this.TabCard(tab, index)
              }
              .height(this.tabCellHeight())
            }, (tab: TabEntry) =>
              `${tab.id}_${tab.updatedAt}_${tab.thumbnailPath ?? ''}_${this.thumbRenderRev}`)
          }
          .key(`tabs-grid-${this.gridEpoch}-${this.thumbRenderRev}`)
          .columnsTemplate('1fr 1fr')
          .columnsGap(TabsPageView.TAB_COL_GAP)
          .rowsGap(TabsPageView.TAB_ROW_GAP)
          .width('100%')
          .padding({ left: TabsPageView.TAB_GRID_PADDING_H, right: TabsPageView.TAB_GRID_PADDING_H, bottom: 16 })
          .onAreaChange((_old, area) => {
            if (this.isTabDragging()) {
              return
            }
            const globalPos = area.globalPosition
            if (globalPos) {
              this.gridOriginGlobalX = globalPos.x as number
              this.gridOriginGlobalY = globalPos.y as number
            }
            const w = area.width as number
            if (w > 0 && Math.abs(w - this.tabGridWidth) > 1) {
              this.tabGridWidth = w
              this.gridMetricsSynced = false
            }
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .enableScrollInteraction(!this.isTabDragging())
        .onAreaChange((_old, area) => {
          const globalPos = area.globalPosition
          if (globalPos) {
            this.scrollViewportTop = globalPos.y as number
          }
          this.scrollViewportHeight = area.height as number
        })

        if (this.dragLiftVisible && this.draggingTabId.length > 0) {
          this.TabDragLiftOverlay()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
  }

  private dragLiftLeft(): number {
    return this.dragLiftBaseLeft + this.dragOffsetX
  }

  private dragLiftTop(): number {
    return this.dragLiftBaseTop + this.dragOffsetY
  }

  private liftedTabEntry(): TabEntry | undefined {
    return this.partitionTabList.find((t) => t.id === this.draggingTabId)
  }

  @Builder
  TabDragLiftOverlay() {
    if (this.liftedTabEntry()) {
      Column() {
        this.TabCardContent(this.liftedTabEntry()!, -1, true)
      }
      .width(this.frozenCellWidth > 0 ? this.frozenCellWidth : this.formulaCellWidth())
      .position({
        x: this.dragLiftLeft(),
        y: this.dragLiftTop()
      })
      .scale({ x: 1.04, y: 1.04 })
      .shadow({
        radius: 16,
        color: 'rgba(0, 0, 0, 0.22)',
        offsetX: 0,
        offsetY: 6
      })
      .zIndex(20)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  TabCard(tab: TabEntry, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        this.TabCardContent(tab, index, false)
      }
      .width('100%')
      .focusable(false)
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
          .onActionStart(() => {
            if (!this.isTabDragging()) {
              this.onTabCardSwipeStart(tab.id)
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.isTabDragging() && this.swipingTabId === tab.id) {
              this.onTabCardSwipeUpdate(tab.id, event.offsetX)
            }
          })
          .onActionEnd(() => {
            if (!this.isTabDragging() && this.swipingTabId === tab.id) {
              this.onTabCardSwipeEnd(tab.id)
            }
          })
          .onActionCancel(() => {
            if (!this.isTabDragging() && this.swipingTabId === tab.id) {
              this.onTabCardSwipeCancel(tab.id)
            }
          })
      )
      .onTouch((event: TouchEvent) => {
        this.onTabCardTouch(tab, index, event)
      })
      .onAreaChange((_old, area) => {
        if (this.isTabDragging()) {
          return
        }
        const globalPos = area.globalPosition
        if (!globalPos) {
          return
        }
        const w = area.width as number
        const h = area.height as number
        this.updateCellLayout(
          index,
          (globalPos.x as number) - this.gridOriginGlobalX + w * 0.5,
          (globalPos.y as number) - this.gridOriginGlobalY + h * 0.5,
          h
        )
        // 仅首屏前几格用于校准，不在每次 onAreaChange 重算 metrics（63 标签会刷屏抖动）
        if (index < TabsPageView.TAB_GRID_COLS * 2) {
          this.syncTabGridMetricsOnce()
        }
      })

      if (!this.isDraggedTabCell(tab.id)) {
        this.TabCloseButton(tab)
      }
    }
    .width('100%')
    .translate(this.tabSqueezeTranslate(index, tab.id))
    .opacity(this.isDraggedTabCell(tab.id) ? 0 : this.tabCardDragOpacity(tab.id))
  }

  /** 关闭按钮独立于卡片 onTouch，避免点 × 时误触 openTab */
  @Builder
  TabCloseButton(tab: TabEntry) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(14)
        .fontColor([BrowserTheme.textSecondary(this.tabsUiDark())])
        .fontWeight(FontWeight.Medium)
    }
    .width(28)
    .height(28)
    .borderRadius(14)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .margin({ top: 8, right: 8 })
    .translate({ x: this.tabCardDragOffset(tab.id), y: 0 })
    .zIndex(10)
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => {
      if (!this.isTabDragging()) {
        this.handleCloseTabClick(tab.id)
      }
    })
  }

  private tabPreviewInitialChar(tab: TabEntry): string {
    const t = tab.title.trim()
    if (t.length > 0) {
      return t.substring(0, 1)
    }
    const u = tab.url.trim()
    if (u.length > 0) {
      return u.substring(0, 1)
    }
    return '?'
  }

  @Builder
  TabThumbStack(tab: TabEntry) {
    Stack({ alignContent: Alignment.TopStart }) {
      if ((tab.thumbnailPath ?? '').length > 0) {
        Image(BrowserStore.tabThumbnailUri(tab.thumbnailPath ?? ''))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Low)
          .key(`tab-thumb-img-${tab.id}-${tab.thumbnailPath ?? ''}-${tab.updatedAt}-${this.thumbRenderRev}`)
      } else if (tab.isHome === true) {
        Column() {
          Text(tab.title.substring(0, 1))
            .fontSize(BrowserTheme.uiFontSize(24))
            .fontWeight(FontWeight.Medium)
            .fontColor(BrowserTheme.primaryColor(this.tabsUiDark()))
            .opacity(0.75)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#f3e5f5', 0], ['#ffffff', 1]]
        })
      } else {
        Column() {
          Text(this.tabPreviewInitialChar(tab))
            .fontSize(BrowserTheme.uiFontSize(22))
            .fontWeight(FontWeight.Medium)
            .fontColor(BrowserTheme.textSecondary(this.tabsUiDark()))
            .opacity(0.65)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#d6d6d6', 0], ['#ebebeb', 0.42], ['#f8f8f8', 1]]
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabCardContent(tab: TabEntry, index: number, lifted: boolean) {
    Column() {
      Row({ space: 6 }) {
        if (tab.isHome === true) {
          Image($r('app.media.ic_home'))
            .width(14)
            .height(14)
            .fillColor(BrowserTheme.primaryColor(this.tabsUiDark()))
            .objectFit(ImageFit.Contain)
            .flexShrink(0)
        } else {
          HistorySiteIcon({
            url: tab.url,
            iconUrl: '',
            boxSize: 18
          })
        }

        Text(tab.title)
          .fontSize(BrowserTheme.uiFontSize(13))
          .fontWeight(FontWeight.Medium)
          .fontColor(BrowserTheme.text(this.tabsUiDark()))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .onClick(() => {
            if (!lifted) {
              this.openTabIfNotSwiping(tab)
            }
          })
      }
      .width('100%')
      .padding({ left: 10, right: 36, top: 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Column() {
        this.TabThumbStack(tab)
      }
      .key(`tab-preview-${tab.id}-${tab.updatedAt}-${tab.thumbnailPath ?? ''}-${this.thumbRenderRev}`)
      .width('100%')
      .height(108)
      .borderRadius(10)
      .clip(true)
      .margin({ left: 8, right: 8, bottom: 8 })
      .onClick(() => {
        if (!lifted) {
          this.openTabIfNotSwiping(tab)
        }
      })
    }
    .width('100%')
    .backgroundColor(this.tabsSurfaceBg())
    .borderRadius(14)
    .translate(lifted ? { x: 0, y: 0 } : { x: this.tabCardDragOffset(tab.id) })
    .border({
      width: lifted ? 1 : this.activeTabBorderWidth(tab),
      color: lifted ?
        BrowserTheme.borderColor(this.tabsUiDark()) :
        this.activeTabBorderColor(tab)
    })
    .shadow(lifted ? {
      radius: 2,
      color: this.tabsUiDark() ? 'rgba(0, 0, 0, 0.35)' : 'rgba(17, 24, 39, 0.04)',
      offsetX: 0,
      offsetY: 1
    } : this.isActiveTab(tab) ? {
      radius: 8,
      color: 'rgba(0, 122, 255, 0.18)',
      offsetX: 0,
      offsetY: 2
    } : {
      radius: 2,
      color: this.tabsUiDark() ? 'rgba(0, 0, 0, 0.35)' : 'rgba(17, 24, 39, 0.04)',
      offsetX: 0,
      offsetY: 1
    })
  }

  @Builder
  BottomBar() {
    Column() {
      Row() {
        this.BottomItemClose()
        this.BottomItemNew()
        this.BottomItemBack()
      }
      .width('100%')
      .padding({ left: 36, right: 36, top: 8, bottom: 8 })
      .backgroundColor(this.tabsUiDark() ?
        BrowserTheme.navBgSolid(true) :
        BrowserTheme.navBgSolid(false))
      .borderRadius(999)
      .shadow({
        radius: 20,
        color: this.tabsUiDark() ? 'rgba(0, 0, 0, 0.40)' : 'rgba(17, 24, 39, 0.12)',
        offsetX: 0,
        offsetY: 6
      })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: BrowserSafeAreaInsets.bottom(8)
    })
  }

  private closeAllActionColor(canUse: boolean): ResourceColor {
    if (this.tabsUiDark()) {
      return canUse ? BrowserTheme.text(true) : BrowserTheme.textMuted(true)
    }
    return canUse ?
      $r('sys.color.ohos_id_color_text_primary') :
      $r('sys.color.ohos_id_color_text_tertiary')
  }

  @Builder
  BottomItemClose() {
    Column({ space: 4 }) {
      Column() {
        TabsBottomTrashIcon({
          canUse: this.vm.canCloseAllTabs(this.partitionTabList.length),
          darkSurface: this.tabsUiDark()
        })
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)

      Text($r('app.string.close_all'))
        .fontSize(BrowserTheme.uiFontSize(12))
        .fontColor(this.closeAllActionColor(this.vm.canCloseAllTabs(this.partitionTabList.length)))
    }
    .layoutWeight(1)
    .padding({ top: 4, bottom: 4 })
    .hitTestBehavior(this.bottomHitTest(this.vm.canCloseAllTabs(this.partitionTabList.length)))
    .onClick(() => {
      if (this.vm.canCloseAllTabs(this.partitionTabList.length)) {
        this.vm.showCloseAllDialog = true
      }
    })
  }

  @Builder
  BottomItemNew() {
    Column({ space: 4 }) {
      Column() {
        TabsBottomPlusIcon({ darkMode: this.tabsUiDark() })
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)

      Text(this.vm.newTabLabel())
        .fontSize(BrowserTheme.uiFontSize(12))
        .fontColor(this.bottomActionColor(this.vm.canNewTab()))
    }
    .layoutWeight(1)
    .padding({ top: 4, bottom: 4 })
    .opacity(this.bottomActionOpacity(this.vm.canNewTab()))
    .hitTestBehavior(this.bottomHitTest(this.vm.canNewTab()))
    .onClick(() => {
      void this.vm.handleNewTab()
    })
  }

  @Builder
  BottomItemBack() {
    Column({ space: 4 }) {
      Column() {
        TabsBottomBackIcon({ darkMode: this.tabsUiDark() })
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)

      Text($r('app.string.back'))
        .fontSize(BrowserTheme.uiFontSize(12))
        .fontColor(BrowserTheme.text(this.tabsUiDark()))
    }
    .layoutWeight(1)
    .padding({ top: 4, bottom: 4 })
    .onClick(() => {
      this.vm.handleBack()
    })
  }
}
