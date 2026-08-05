import { BrowserNavigation } from 'browser_core'
import { HarmonyDialogStyle } from 'commons'
import { BrowserStrings } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { ShortcutFeature, TabEntry } from 'browser_core'
import { ShortcutManager } from 'browser_core'
import { SearchSuggest, SearchSuggestion } from 'common'
import { HistoryEntry } from 'common'
import { BookmarkItem } from 'common'
import {
  computeHoverIndex,
  gridPointCenterX,
  gridSqueezePath,
  gridSqueezePathWithMeasure,
  GridLayoutMetrics,
  GridSqueezePath,
  GridTranslate,
  indexToGridPoint,
  previewIndexOfId,
  squeezePathForCell
} from './ShortcutDragLayout'
import { reorderArrayIds } from 'common'
import { BrowserLog } from 'common'
import { AppStorageKeys, ShortcutMenuOverlayState } from 'common'
import { ShortcutItem } from 'common'
import {
  ScanQrIcon,
  SearchLeadingIcon,
  ShortcutEngineIcon,
  ShortcutTileIcon,
  TabCountBadge,
  TrashClearIcon,
  UrlNavigateConfirmBtn
} from 'commons'
import { PanelConfirmDialog } from 'commons'
import { PanelCircleIconButton } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'
import { BrowserWindowService } from 'browser_core'

/** 快捷方式图标实测矩形（相对 Grid Stack） */
interface ShortcutIconRect {
  left: number
  top: number
  width: number
  height: number
}

/** 菜单锚点坐标 */
interface MenuAnchorPoint {
  x: number
  y: number
}

@Component
export struct HomeView {
  private static readonly SEARCH_ROW_HEIGHT: number = 52
  /** 首页搜索栏右侧页签入口尺寸（与 SEARCH_ROW_HEIGHT 同步） */
  private static readonly SEARCH_TAB_ENTRY_SIZE: number = 40
  private static readonly SEARCH_TAB_BADGE_SIZE: number = 25
  private static readonly SEARCH_TAB_BADGE_FONT: number = 12
  private static readonly SHORTCUT_COLS: number = 4
  private static readonly SHORTCUT_GRID_H_PADDING: number = 48
  private static readonly SHORTCUT_COL_GAP: number = 12
  private static readonly SHORTCUT_ROW_GAP: number = 22
  /** 压缩布局时行距下限（优先减行距，避免单元格过矮裁切第二行文案） */
  private static readonly MIN_SHORTCUT_ROW_GAP: number = 12
  /** 可用高度预算余量，避免 Grid clip 裁切末行底边 */
  private static readonly SHORTCUT_LAYOUT_SAFETY_PX: number = 4
  /** 快捷方式图标槽统一边长（功能 / 站点 / 添加） */
  private static readonly SHORTCUT_ICON_BOX: number = 48
  /** 单元可视高度：图标 48 + 间距 7 + 文字 14 + 内边距 8 */
  private static readonly SHORTCUT_CELL_CONTENT_HEIGHT: number = 77
  /** 压缩布局时单元格高度下限 */
  private static readonly MIN_SHORTCUT_CELL_HEIGHT: number = 60
  private static readonly LONG_PRESS_MS: number = 300
  /** 手指停顿后再切换挤位目标，与平移动画时长分离 */
  private static readonly HOVER_DWELL_MS: number = 50
  /** 同行挤位平移动画时长 */
  private static readonly SQUEEZE_SAME_ROW_MS: number = 220
  /** 跨行挤位动画时长（斜线移动） */
  private static readonly SQUEEZE_CROSS_ROW_MS: number = 320
  /** 小于该值的抖动不重置停顿计时，避免永远无法挤位 */
  private static readonly HOVER_MOVE_THRESHOLD: number = 4
  private static readonly SHORTCUT_GRID_PADDING_LEFT: number = 24
  private static readonly SHORTCUT_GRID_PADDING_RIGHT: number = 24
  /** 占位框可视高度一半（48 图标 + 7 间距 + 14 行高） */
  private static readonly PLACEHOLDER_HALF_HEIGHT: number = 34.5
  /** ShortcutItem 外层 padding，占位框需与之对齐 */
  private static readonly SHORTCUT_ITEM_PADDING: number = 4
  private static readonly SHORTCUT_GRID_PADDING_TOP: number = 12
  /** 首页搜索栏层级（须高于快捷方式网格，避免负 margin 重叠区被网格拦截点击） */
  private static readonly SEARCH_ROW_Z_INDEX: number = 40
  private static readonly SHORTCUT_GRID_Z_INDEX: number = 35
  /** 网格最少 / 最多行数（按视口动态计算） */
  private static readonly MIN_SHORTCUT_GRID_ROWS: number = 2
  private static readonly MAX_SHORTCUT_GRID_ROWS: number = 4
  /** 横屏时搜索栏距内容区顶部的间距 */
  private static readonly LANDSCAPE_SEARCH_TOP_PADDING: number = 12
  /** bg.svg 原始宽高比（184×276，不改资源文件） */
  private static readonly HOME_BG_ASPECT: number = 184 / 276
  /**
   * 是否绘制 bg.svg 水面装饰（含倒影/渐隐等）。
   * 临时关闭：浅色/深色均不展示；改为 true 即可恢复全部相关画面。
   */
  private static readonly HOME_BG_DECOR_ENABLED: boolean = false
  /**
   * bg.svg 上下交错线相对高度：上圆底边 y=184 / 总高 276。
   * 此线以上为天光区，以下为水面倒影区。
   */
  private static readonly HOME_BG_HORIZON_RATIO: number = 184 / 276
  /** 装饰图相对状态栏底边的留白 */
  private static readonly HOME_BG_STATUS_GAP: number = 24
  /** 搜索框上方可见区内整体下移（增大则图顶下移） */
  private static readonly HOME_BG_NUDGE_DOWN: number = 12
  /** 搜索框覆盖倒影区的比例（0.7 = 倒影区底部 70% 被搜索框盖住） */
  private static readonly HOME_BG_REFLECTION_COVER: number = 0.7
  /** 在不裁切水面以上内容的前提下微微放大 */
  private static readonly HOME_BG_SCALE_BOOST: number = 1.08
  /** 截断线附近短柔边高度（仅消除硬边，非整段渐隐） */
  private static readonly HOME_BG_CLIP_EDGE_FADE: number = 22
  /** 水面倒影区模糊强度 */
  private static readonly HOME_BG_REFLECTION_BLUR: number = 18
  /** 横屏搜索框上方过矮时不展示装饰图 */
  private static readonly HOME_BG_MIN_REGION: number = 72
  /** 长按抬起后未拖动则弹出菜单的等待时长 */
  private static readonly CONTEXT_MENU_DELAY_MS: number = 500
  /** 判定进入拖动模式的最小位移 */
  private static readonly DRAG_MOVE_THRESHOLD: number = 8
  /** 长按菜单气泡宽度（紧凑，左对齐文案） */
  private static readonly CONTEXT_MENU_WIDTH: number = 144
  private static readonly CONTEXT_MENU_EDGE_MARGIN: number = 12
  /** 添加快捷方式占位 id */
  private static readonly ADD_SHORTCUT_SLOT_ID: string = '__add_shortcut__'
  private static readonly DROP_SETTLE_MS: number = 300
  private static readonly DROP_SETTLE_FRAME_MS: number = 32

  @Link @Watch('onSearchModeChanged') isSearchMode: boolean
  @Link showAddSheet: boolean
  @Link shortcutMenuOverlay: ShortcutMenuOverlayState
  @Link mainPageGlobalX: number
  @Link mainPageGlobalY: number
  @StorageLink('browser_shortcut_ids') @Watch('onShortcutIdsChanged') shortcutIds: string[] = []
  @StorageLink('browser_search_history') searchHistory: string[] = []
  @StorageLink('browser_history') historyList: HistoryEntry[] = []
  @StorageLink('browser_bookmarks') bookmarks: BookmarkItem[] = []
  @StorageLink('browser_tabs') tabs: TabEntry[] = []
  @State searchText: string = ''
  @State showClearConfirm: boolean = false
  @State draggingId: string = ''
  @State dragFromIndex: number = -1
  @State dragHoverIndex: number = -1
  /** 挤位动效目标（停顿判定），与占位框即时索引分离 */
  @State dragSqueezeIndex: number = -1
  /** 最近一次非原位的挤位目标（用于拖回原位时的还原动效时长） */
  @State lastSqueezeTargetIndex: number = -1
  @State dragOffsetX: number = 0
  @State dragOffsetY: number = 0
  @State dragLiftVisible: boolean = false
  @State shortcutColStep: number = 0
  @State shortcutRowStep: number = 0
  @State shortcutGridWidth: number = 0
  @State homeViewportHeight: number = 0
  @State homeViewportWidth: number = 0
  /** HomeView 根节点全局 Y，用于把搜索栏全局坐标换算为本地坐标 */
  @State homeViewGlobalY: number = 0
  /** 搜索栏顶边实测本地 Y（<0 表示尚未测到，回退估算） */
  @State measuredSearchBarTop: number = -1
  @State homeWideWindow: boolean = false
  @State homeLayoutRev: number = 0
  @State shortcutGridRows: number = HomeView.MIN_SHORTCUT_GRID_ROWS
  @State shortcutCellHeight: number = HomeView.SHORTCUT_CELL_CONTENT_HEIGHT
  @State shortcutRowGapEffective: number = HomeView.SHORTCUT_ROW_GAP
  @State showShortcutContextMenu: boolean = false
  @State contextMenuFeatureId: string = ''
  @State contextMenuIndex: number = -1
  @State contextMenuPosX: number = 0
  @State contextMenuPosY: number = 0
  /** 菜单展示时手指仍按在 Grid 内（原 LongPress+Pan 序列未结束） */
  @State contextMenuGridPanActive: boolean = false
  /** 顶层交互层 Pan 进行中（关菜单后仍保持至松手） */
  @State dragLiftOverlayPanActive: boolean = false
  @State showShortcutEditDialog: boolean = false
  @State editShortcutName: string = ''
  @State editShortcutUrl: string = ''
  @State editShortcutId: string = ''
  @StorageLink('browser_shortcuts') storedShortcuts: ShortcutItem[] = []
  @State cellLayoutX: number[] = []
  @State cellLayoutY: number[] = []
  @State cellLayoutH: number[] = []
  @State cellIconLeft: number[] = []
  @State cellIconTop: number[] = []
  @State cellIconWidth: number[] = []
  @State cellIconHeight: number[] = []
  @State suppressShortcutClick: boolean = false
  @State dropSettling: boolean = false
  @State dropSettleById: Record<string, GridTranslate> = {}
  /** 松手落位动效中的拖项 id（用于时长与缩放） */
  @State dropSettleDraggedId: string = ''
  /** 落位起始缩放，与拖拽浮层 1.12 对齐后缓动回 1 */
  @State dropSettleScale: number = 1
  @State placeholderRect: ShortcutIconRect = {
    left: 0,
    top: 0,
    width: HomeView.SHORTCUT_ICON_BOX,
    height: HomeView.SHORTCUT_ICON_BOX
  }
  private gridOriginGlobalX: number = 0
  private gridOriginGlobalY: number = 0
  private hoverDwellTimer: number = -1
  private hoverCheckOffsetX: number = 0
  private hoverCheckOffsetY: number = 0
  private dropSettleStartTimer: number = -1
  private dropSettleEndTimer: number = -1
  private contextMenuTimer: number = -1
  /** 菜单松手后二次拖动：Pan 偏移基准（叠加到 event.offset） */
  private dragPanBaseOffsetX: number = 0
  private dragPanBaseOffsetY: number = 0
  /** 快捷方式单指触摸跟踪（替代 GestureGroup，避免 Grid 内点击被吞） */
  private activeShortcutTouchId: string = ''
  private activeShortcutTouchIndex: number = -1
  private shortcutTouchDownMs: number = 0
  private shortcutTouchOriginX: number = 0
  private shortcutTouchOriginY: number = 0
  private shortcutPressTimer: number = -1
  private searchFocusTimer: number = -1
  private suppressClickTimer: number = -1
  private shortcutLongPressStarted: boolean = false
  private lastShortcutTapMs: number = 0
  private lastShortcutTapId: string = ''
  @StorageLink('browser_incognito') isIncognito: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageLink(AppStorageKeys.SHORTCUT_MENU_ACTION) @Watch('onShortcutMenuAction') shortcutMenuAction: string = ''
  @StorageLink(AppStorageKeys.WINDOW_REV) @Watch('onWindowRevChanged') windowRev: number = 0
  @StorageLink(AppStorageKeys.WINDOW_LANDSCAPE) isLandscape: boolean = false
  @StorageLink(AppStorageKeys.WINDOW_WIDTH) @Watch('onWindowSizeStorageChanged') windowWidth: number = 0
  @StorageLink(AppStorageKeys.WINDOW_HEIGHT) @Watch('onWindowSizeStorageChanged') windowHeight: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_REV) @Watch('onFontUiRevChanged') fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageProp(AppStorageKeys.SAFE_AREA_BOTTOM) safeAreaBottom: number = 0
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  private searchInputController: TextInputController = new TextInputController()

  /** 底部首页/我的导航避让（系统导航条 + 底栏 + 留白） */
  private bottomNavClearance(): number {
    return BrowserSafeAreaInsets.homeContentBottomClearance()
  }

  private isDarkMode(): boolean {
    return this.theme === 'dark'
  }

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  private openSearchMode(): void {
    BrowserLog.info('[HomeView] openSearchMode')
    this.isSearchMode = true
  }

  private closeSearchMode(): void {
    this.isSearchMode = false
    this.searchText = ''
  }

  private onSearchModeChanged(): void {
    if (this.isSearchMode) {
      this.scheduleSearchInputFocus()
    } else {
      this.dismissSearchKeyboard()
    }
  }

  /** 进入搜索页后延迟获焦，确保 SearchOverlay 已挂载 */
  private scheduleSearchInputFocus(): void {
    this.clearSearchFocusTimer()
    this.searchFocusTimer = setTimeout((): void => {
      this.searchFocusTimer = -1
      if (!this.isSearchMode) {
        return
      }
      focusControl.requestFocus('home_search_input')
      try {
        this.searchInputController.caretPosition(this.searchText.length)
      } catch (_e) {
        // caretPosition 在部分版本不可用时不阻塞
      }
    }, 80) as number
  }

  private clearSearchFocusTimer(): void {
    if (this.searchFocusTimer >= 0) {
      clearTimeout(this.searchFocusTimer)
      this.searchFocusTimer = -1
    }
  }

  private clearSuppressClickTimer(): void {
    if (this.suppressClickTimer >= 0) {
      clearTimeout(this.suppressClickTimer)
      this.suppressClickTimer = -1
    }
  }

  private dismissSearchKeyboard(): void {
    try {
      this.searchInputController.stopEditing()
    } catch (_e) {
      // stopEditing 在部分版本不可用时不阻塞
    }
  }

  private isShortcutDragging(): boolean {
    return this.draggingId.length > 0
  }

  /** 长按抬起后：浮动图标 / 占位框应可见（含菜单等待、菜单展示、拖动排序） */
  private isShortcutLiftActive(): boolean {
    return this.dragLiftVisible && this.draggingId.length > 0
  }

  /** Grid 内坐标 → ShortcutGrid Stack 坐标（Column 顶部 padding 修正） */
  private shortcutGridOverlayTopOffset(): number {
    return HomeView.SHORTCUT_GRID_PADDING_TOP
  }

  private refreshShortcutGridMetrics(gridWidth: number, _gridHeight: number): void {
    if (gridWidth <= 0) {
      return
    }
    const cols = HomeView.SHORTCUT_COLS
    const gapTotal = HomeView.SHORTCUT_COL_GAP * (cols - 1)
    const contentWidth = gridWidth - HomeView.SHORTCUT_GRID_PADDING_LEFT - HomeView.SHORTCUT_GRID_PADDING_RIGHT
    const cellWidth = (contentWidth - gapTotal) / cols
    this.shortcutColStep = cellWidth + HomeView.SHORTCUT_COL_GAP
    this.shortcutRowStep = this.shortcutCellHeight + this.shortcutRowGapEffective
  }

  /** 记录格子中心相对 Grid 的坐标（用于挤位动效） */
  private updateCellLayout(index: number, x: number, y: number, height: number = 0): void {
    const xs = this.cellLayoutX.slice()
    const ys = this.cellLayoutY.slice()
    const hs = this.cellLayoutH.slice()
    while (xs.length <= index) {
      xs.push(Number.NaN)
    }
    while (ys.length <= index) {
      ys.push(Number.NaN)
    }
    while (hs.length <= index) {
      hs.push(Number.NaN)
    }
    xs[index] = x
    ys[index] = y
    if (height > 0) {
      hs[index] = height
    }
    this.cellLayoutX = xs
    this.cellLayoutY = ys
    this.cellLayoutH = hs
    this.applyLayoutInferredMetrics(xs, ys)
  }

  /** 记录图标方块相对 Grid 的实测位置与尺寸（用于占位框对齐） */
  private updateIconLayout(index: number, left: number, top: number, width: number, height: number): void {
    const ls = this.cellIconLeft.slice()
    const ts = this.cellIconTop.slice()
    const ws = this.cellIconWidth.slice()
    const hs = this.cellIconHeight.slice()
    while (ls.length <= index) {
      ls.push(Number.NaN)
    }
    while (ts.length <= index) {
      ts.push(Number.NaN)
    }
    while (ws.length <= index) {
      ws.push(0)
    }
    while (hs.length <= index) {
      hs.push(0)
    }
    ls[index] = left
    ts[index] = top
    ws[index] = width
    hs[index] = height
    this.cellIconLeft = ls
    this.cellIconTop = ts
    this.cellIconWidth = ws
    this.cellIconHeight = hs
  }

  /** 从相邻格实测中心距推断 colStep/rowStep（translate 必须与实测格距一致） */
  private inferColStepFromLayout(xs: number[] = this.cellLayoutX): number {
    const cols = HomeView.SHORTCUT_COLS
    for (let i = 0; i < xs.length; i++) {
      const j = i + 1
      if (j >= xs.length || j % cols === 0) {
        continue
      }
      const x0 = xs[i]
      const x1 = xs[j]
      if (Number.isNaN(x0) || Number.isNaN(x1)) {
        continue
      }
      const dx = Math.abs(x1 - x0)
      if (dx >= 50 && dx < 600) {
        return dx
      }
    }
    return 0
  }

  private inferRowStepFromLayout(ys: number[] = this.cellLayoutY): number {
    const cols = HomeView.SHORTCUT_COLS
    for (let r = 0; r + 1 < Math.ceil(ys.length / cols); r++) {
      const top = ys[r * cols]
      const bottom = ys[(r + 1) * cols]
      if (Number.isNaN(top) || Number.isNaN(bottom)) {
        continue
      }
      const dy = Math.abs(bottom - top)
      if (top >= bottom) {
        continue
      }
      if (dy >= 70 && dy <= 160) {
        return dy
      }
    }
    return 0
  }

  /** 用第 0 行与第 1 行同列格实测行距兜底 */
  private ensureRowStepFromAdjacentRows(): void {
    if (this.inferRowStepFromLayout() > 0) {
      this.shortcutRowStep = this.inferRowStepFromLayout()
      return
    }
    const cols = HomeView.SHORTCUT_COLS
    const y0 = this.cellLayoutY[0]
    const yRow1 = this.cellLayoutY[cols]
    if (Number.isNaN(y0) || Number.isNaN(yRow1) || y0 >= yRow1) {
      return
    }
    const dy = Math.abs(yRow1 - y0)
    if (dy >= 90 && dy <= 130) {
      this.shortcutRowStep = dy
    }
  }

  /** 校验格心 Y：下行必须低于上行 */
  private isCellLayoutYValid(index: number): boolean {
    const y = this.cellLayoutY[index]
    if (Number.isNaN(y)) {
      return false
    }
    const cols = HomeView.SHORTCUT_COLS
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

  /** 丢弃拖动前已污染的格心缓存 */
  private sanitizeCellLayoutCache(): void {
    const ys = this.cellLayoutY.slice()
    let dirty = false
    for (let i = 0; i < ys.length; i++) {
      if (!Number.isNaN(ys[i]) && !this.isCellLayoutYValid(i)) {
        ys[i] = Number.NaN
        dirty = true
      }
    }
    if (dirty) {
      this.cellLayoutY = ys
    }
  }

  /** 拖动前用已缓存的前两格中心距兜底（日志 cellX0/cellX1 差值） */
  private ensureColStepFromAdjacentCells(): void {
    if (this.inferColStepFromLayout() > 0) {
      this.shortcutColStep = this.inferColStepFromLayout()
      return
    }
    const x0 = this.cellLayoutX[0]
    const x1 = this.cellLayoutX[1]
    if (Number.isNaN(x0) || Number.isNaN(x1)) {
      return
    }
    const dx = Math.abs(x1 - x0)
    if (dx >= 50) {
      this.shortcutColStep = dx
    }
  }

  private applyLayoutInferredMetrics(xs: number[], ys: number[]): void {
    const col = this.inferColStepFromLayout(xs)
    if (col > 0) {
      this.shortcutColStep = col
    }
    const row = this.inferRowStepFromLayout(ys)
    if (row >= 90 && row <= 130) {
      this.shortcutRowStep = row
    }
  }

  private shortcutColStepValue(): number {
    if (this.shortcutColStep > 0) {
      return this.shortcutColStep
    }
    if (this.shortcutGridWidth > 0) {
      const cols = HomeView.SHORTCUT_COLS
      const gapTotal = HomeView.SHORTCUT_COL_GAP * (cols - 1)
      const contentWidth = this.shortcutGridWidth - HomeView.SHORTCUT_GRID_PADDING_LEFT -
        HomeView.SHORTCUT_GRID_PADDING_RIGHT
      const cellWidth = (contentWidth - gapTotal) / cols
      return cellWidth + HomeView.SHORTCUT_COL_GAP
    }
    return 0
  }

  private shortcutRowStepValue(): number {
    if (this.shortcutRowStep >= 78 && this.shortcutRowStep <= 180) {
      return this.shortcutRowStep
    }
    return this.shortcutCellHeight + this.shortcutRowGapEffective
  }

  private clearHoverDwellTimer(): void {
    if (this.hoverDwellTimer >= 0) {
      clearTimeout(this.hoverDwellTimer)
      this.hoverDwellTimer = -1
    }
  }

  private clearDropSettleTimers(): void {
    if (this.dropSettleStartTimer >= 0) {
      clearTimeout(this.dropSettleStartTimer)
      this.dropSettleStartTimer = -1
    }
    if (this.dropSettleEndTimer >= 0) {
      clearTimeout(this.dropSettleEndTimer)
      this.dropSettleEndTimer = -1
    }
  }

  private endShortcutDrag(): void {
    this.clearHoverDwellTimer()
    this.clearContextMenuTimer()
    this.clearShortcutPressTimer()
    this.showShortcutContextMenu = false
    this.contextMenuFeatureId = ''
    this.contextMenuIndex = -1
    this.contextMenuGridPanActive = false
    this.dragLiftOverlayPanActive = false
    this.dragFromIndex = -1
    this.dragHoverIndex = -1
    this.dragSqueezeIndex = -1
    this.lastSqueezeTargetIndex = -1
    this.draggingId = ''
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.dragLiftVisible = false
    this.suppressShortcutClick = true
    this.clearShortcutOverlayState()
    if (!this.dropSettling) {
      this.clearSuppressClickTimer()
      this.suppressClickTimer = setTimeout(() => {
        this.suppressClickTimer = -1
        this.suppressShortcutClick = false
      }, 80) as number
    }
  }

  private clearContextMenuTimer(): void {
    if (this.contextMenuTimer >= 0) {
      clearTimeout(this.contextMenuTimer)
      this.contextMenuTimer = -1
    }
  }

  private clearShortcutPressTimer(): void {
    if (this.shortcutPressTimer >= 0) {
      clearTimeout(this.shortcutPressTimer)
      this.shortcutPressTimer = -1
    }
  }

  /** 清理异常残留的拖动/菜单状态，避免拦截点击 */
  private resetShortcutInteractionStateIfNeeded(): void {
    if (this.draggingId.length === 0 && !this.showShortcutContextMenu && !this.dropSettling) {
      return
    }
    this.clearDropSettleTimers()
    this.clearHoverDwellTimer()
    this.clearContextMenuTimer()
    this.clearShortcutPressTimer()
    this.activeShortcutTouchId = ''
    this.activeShortcutTouchIndex = -1
    this.shortcutLongPressStarted = false
    this.showShortcutContextMenu = false
    this.contextMenuFeatureId = ''
    this.contextMenuIndex = -1
    this.contextMenuGridPanActive = false
    this.dragLiftOverlayPanActive = false
    this.dragFromIndex = -1
    this.dragHoverIndex = -1
    this.dragSqueezeIndex = -1
    this.lastSqueezeTargetIndex = -1
    this.draggingId = ''
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.dragLiftVisible = false
    this.dropSettling = false
    this.dropSettleDraggedId = ''
    this.suppressShortcutClick = false
    this.dropSettleById = {}
    this.clearShortcutOverlayState()
    BrowserLog.info('[ShortcutTap] reset interaction state')
  }

  /** 触摸分发：短按打开、长按拖动 */
  private onShortcutItemTouch(feature: ShortcutFeature, index: number, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      BrowserLog.info(`[ShortcutTap] touch down id=${feature.id} index=${index}`)
      if (this.dropSettling) {
        return
      }
      this.activeShortcutTouchId = feature.id
      this.activeShortcutTouchIndex = index
      this.shortcutTouchDownMs = Date.now()
      this.shortcutLongPressStarted = false
      const touch = event.touches[0]
      if (touch) {
        this.shortcutTouchOriginX = touch.x
        this.shortcutTouchOriginY = touch.y
      }
      this.clearShortcutPressTimer()
      this.shortcutPressTimer = setTimeout(() => {
        this.shortcutPressTimer = -1
        if (this.activeShortcutTouchId !== feature.id) {
          return
        }
        if (this.isShortcutDragging() && this.draggingId !== feature.id) {
          return
        }
        this.shortcutLongPressStarted = true
        this.startShortcutDrag(index, feature.id)
      }, HomeView.LONG_PRESS_MS)
      return
    }

    if (this.activeShortcutTouchId !== feature.id) {
      return
    }

    if (event.type === TouchType.Move) {
      const touch = event.touches[0]
      if (!touch) {
        return
      }
      const dx = touch.x - this.shortcutTouchOriginX
      const dy = touch.y - this.shortcutTouchOriginY
      if (!this.shortcutLongPressStarted &&
        (Math.abs(dx) > HomeView.DRAG_MOVE_THRESHOLD || Math.abs(dy) > HomeView.DRAG_MOVE_THRESHOLD)) {
        this.clearShortcutPressTimer()
      }
      if (this.draggingId === feature.id) {
        this.onShortcutPanUpdate(feature.id, dx, dy)
      }
      return
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearShortcutPressTimer()
      const elapsed = Date.now() - this.shortcutTouchDownMs
      let dx = this.dragOffsetX
      let dy = this.dragOffsetY
      const touch = event.touches[0] ?? event.changedTouches[0]
      if (touch) {
        dx = touch.x - this.shortcutTouchOriginX
        dy = touch.y - this.shortcutTouchOriginY
      }

      if (this.draggingId === feature.id) {
        this.finishShortcutDragGesture(feature.id, dx, dy)
      } else if (!this.shortcutLongPressStarted && elapsed < HomeView.LONG_PRESS_MS + 80) {
        const moved = Math.abs(dx) > HomeView.DRAG_MOVE_THRESHOLD ||
          Math.abs(dy) > HomeView.DRAG_MOVE_THRESHOLD
        if (!moved) {
          // onTouch 与 onClick 双通道，优先保证短按可达
          this.handleShortcutTap(feature)
        }
      }

      this.activeShortcutTouchId = ''
      this.activeShortcutTouchIndex = -1
      this.shortcutLongPressStarted = false
    }
  }

  private hasDragMovement(): boolean {
    return Math.abs(this.dragOffsetX) > HomeView.DRAG_MOVE_THRESHOLD ||
      Math.abs(this.dragOffsetY) > HomeView.DRAG_MOVE_THRESHOLD
  }

  private scheduleContextMenu(index: number, featureId: string): void {
    this.clearContextMenuTimer()
    this.contextMenuTimer = setTimeout(() => {
      this.contextMenuTimer = -1
      if (this.draggingId !== featureId || !this.dragLiftVisible || this.hasDragMovement()) {
        return
      }
      this.openShortcutContextMenu(index, featureId)
    }, HomeView.CONTEXT_MENU_DELAY_MS)
  }

  private openShortcutContextMenu(index: number, featureId: string): void {
    this.clearContextMenuTimer()
    this.contextMenuIndex = index
    this.contextMenuFeatureId = featureId
    // 沿用抬起阶段 overlay 上已有坐标，仅追加菜单（图标不动）
    this.syncShortcutOverlay()
    const menuPos = this.computeMenuPosFromLift(
      this.shortcutMenuOverlay.iconAnchorLeft,
      this.shortcutMenuOverlay.iconAnchorTop,
      this.shortcutMenuOverlay.offsetX,
      this.shortcutMenuOverlay.offsetY,
      featureId
    )
    this.contextMenuPosX = menuPos.x
    this.contextMenuPosY = menuPos.y
    this.shortcutMenuOverlay.menuPosX = menuPos.x
    this.shortcutMenuOverlay.menuPosY = menuPos.y
    this.shortcutMenuOverlay.positionFrozen = true
    this.showShortcutContextMenu = true
    this.syncShortcutOverlay()
    BrowserLog.info(`[ShortcutContextMenu] open id=${featureId} index=${index} ` +
      `icon=(${this.shortcutMenuOverlay.iconAnchorLeft.toFixed(1)},` +
      `${this.shortcutMenuOverlay.iconAnchorTop.toFixed(1)}) ` +
      `offset=(${this.shortcutMenuOverlay.offsetX.toFixed(1)},${this.shortcutMenuOverlay.offsetY.toFixed(1)}) ` +
      `menu=(${this.shortcutMenuOverlay.menuPosX.toFixed(1)},${this.shortcutMenuOverlay.menuPosY.toFixed(1)})`)
  }

  /** 菜单锚点：紧贴抬起图标底边，水平方向 clamp 避免右侧被裁切 */
  private computeMenuPosFromLift(
    anchorLeft: number,
    anchorTop: number,
    offsetX: number,
    offsetY: number,
    featureId: string
  ): MenuAnchorPoint {
    const scaledH = HomeView.SHORTCUT_ICON_BOX * 1.12
    return {
      x: this.clampMenuPosX(anchorLeft + offsetX),
      y: anchorTop + offsetY + scaledH + 6
    }
  }

  private clampMenuPosX(x: number): number {
    const pageW = this.homeViewportWidth
    if (pageW <= 0) {
      return x
    }
    const maxX = pageW - HomeView.CONTEXT_MENU_WIDTH - HomeView.CONTEXT_MENU_EDGE_MARGIN
    return Math.max(HomeView.CONTEXT_MENU_EDGE_MARGIN, Math.min(x, maxX))
  }

  /** 同步 MainPage overlay：抬起阶段实时跟手，菜单阶段冻结图标坐标 */
  private syncShortcutOverlay(): void {
    this.shortcutMenuOverlay.liftActive = this.isShortcutLiftActive()
    this.shortcutMenuOverlay.menuVisible = this.showShortcutContextMenu
    this.shortcutMenuOverlay.fingerOnGrid = this.contextMenuGridPanActive
    this.shortcutMenuOverlay.darkMode = this.isDarkMode()
    this.shortcutMenuOverlay.featureId = this.draggingId
    if (this.isShortcutLiftActive() && !this.shortcutMenuOverlay.positionFrozen) {
      const pos = this.overlayIconMainPagePos()
      this.shortcutMenuOverlay.iconAnchorLeft = pos.x
      this.shortcutMenuOverlay.iconAnchorTop = pos.y
      this.shortcutMenuOverlay.offsetX = this.dragOffsetX
      this.shortcutMenuOverlay.offsetY = this.dragOffsetY
    }
    if (!this.isShortcutLiftActive()) {
      this.clearShortcutOverlayState()
    }
  }

  private clearShortcutOverlayState(): void {
    this.shortcutMenuOverlay.liftActive = false
    this.shortcutMenuOverlay.menuVisible = false
    this.shortcutMenuOverlay.fingerOnGrid = false
    this.shortcutMenuOverlay.positionFrozen = false
    this.shortcutMenuOverlay.featureId = ''
    this.shortcutMenuOverlay.iconAnchorLeft = 0
    this.shortcutMenuOverlay.iconAnchorTop = 0
    this.shortcutMenuOverlay.offsetX = 0
    this.shortcutMenuOverlay.offsetY = 0
    this.shortcutMenuOverlay.menuPosX = 0
    this.shortcutMenuOverlay.menuPosY = 0
  }

  private onShortcutMenuAction(): void {
    const action = this.shortcutMenuAction
    if (action.length === 0) {
      return
    }
    AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, '')
    if (action === 'dismiss') {
      this.dismissShortcutContextMenuAndLift()
    } else if (action === 'edit') {
      this.openShortcutEditDialog()
    } else if (action === 'remove') {
      this.deleteContextShortcut()
    }
  }

  /** 图标实测全局坐标 → MainPage overlay 本地坐标（与原图标左上角对齐） */
  private overlayIconMainPagePos(): MenuAnchorPoint {
    const rect = this.resolveIconRect(this.dragFromIndex)
    const globalLeft = this.gridOriginGlobalX + rect.left
    const globalTop = this.gridOriginGlobalY + rect.top
    return {
      x: globalLeft - this.mainPageGlobalX,
      y: globalTop - this.mainPageGlobalY
    }
  }

  /** 跟手图标锚点 Y（相对 MainPage Stack） */
  private shortcutOverlayHomeTopBase(): number {
    return this.overlayIconMainPagePos().y
  }

  private dismissShortcutContextMenu(): void {
    this.showShortcutContextMenu = false
    this.contextMenuFeatureId = ''
    this.contextMenuIndex = -1
    this.shortcutMenuOverlay.positionFrozen = false
    this.syncShortcutOverlay()
  }

  /** 关闭菜单并将浮动图标落回原位 */
  private dismissShortcutContextMenuAndLift(): void {
    if (!this.showShortcutContextMenu) {
      return
    }
    const id = this.contextMenuFeatureId.length > 0 ? this.contextMenuFeatureId : this.draggingId
    const ox = this.dragOffsetX
    const oy = this.dragOffsetY
    this.dismissShortcutContextMenu()
    if (id.length > 0) {
      this.commitCancelWithSettle(id, ox, oy)
    } else {
      this.endShortcutDrag()
    }
  }

  private dismissContextMenuForDrag(): void {
    this.clearContextMenuTimer()
    if (this.showShortcutContextMenu) {
      this.shortcutMenuOverlay.positionFrozen = false
      this.dismissShortcutContextMenu()
    }
  }

  private isShortcutTitleOnly(id: string): boolean {
    const feat = ShortcutManager.resolveDisplayEntry(id)
    return feat?.kind === 'feature'
  }

  private resolveShortcutUrl(id: string): string {
    const item = this.storedShortcuts.find((s) => s.id === id)
    if (item && item.url.length > 0) {
      return item.url
    }
    return ShortcutManager.resolveDisplayEntry(id)?.url ?? ''
  }

  private openShortcutEditDialog(): void {
    const id = this.contextMenuFeatureId
    const feat = ShortcutManager.resolveDisplayEntry(id)
    if (!feat) {
      return
    }
    this.editShortcutId = id
    this.editShortcutName = feat.title
    this.editShortcutUrl = this.isShortcutTitleOnly(id) ? '' : this.resolveShortcutUrl(id)
    this.showShortcutEditDialog = true
    this.dismissShortcutContextMenuAndLift()
  }

  private saveShortcutEdit(): void {
    const editId = this.editShortcutId
    const name = this.editShortcutName.trim()
    if (!name || editId.length === 0) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.custom_shortcut_name_required')))
      return
    }
    if (this.isShortcutTitleOnly(editId)) {
      void BrowserStore.updateShortcut(editId, name).then((ok) => {
        if (ok) {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.renamed')))
          this.showShortcutEditDialog = false
          this.editShortcutId = ''
        }
      })
      return
    }
    const check = BrowserNavigation.validateUrlInput(this.editShortcutUrl.trim())
    if (!check.ok || !check.url) {
      BrowserStore.showToast(check.message ?? BrowserStrings.urlFormatInvalid())
      return
    }
    void BrowserStore.updateShortcut(editId, name, check.url).then((ok) => {
      if (ok) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.renamed')))
        this.showShortcutEditDialog = false
        this.editShortcutId = ''
      }
    })
  }

  private deleteContextShortcut(): void {
    const id = this.contextMenuFeatureId
    if (id.length === 0) {
      return
    }
    const idx = this.shortcutIds.indexOf(id)
    if (idx < 0) {
      return
    }
    const next = this.shortcutIds.slice()
    next.splice(idx, 1)
    this.shortcutIds = next
    void BrowserStore.removeShortcut(id).then(() => {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.shortcut_removed')))
    })
    this.dismissShortcutContextMenuAndLift()
  }

  private onShortcutPanUpdate(featureId: string, offsetX: number, offsetY: number): void {
    if (this.draggingId !== featureId) {
      return
    }
    this.dragOffsetX = offsetX
    this.dragOffsetY = offsetY
    if (this.showShortcutContextMenu) {
      // 菜单已开：跟手图与菜单冻结不动；大位移则关菜单进入拖排
      this.syncShortcutOverlay()
      if (!this.hasDragMovement()) {
        return
      }
      this.dismissContextMenuForDrag()
      this.hoverCheckOffsetX = offsetX
      this.hoverCheckOffsetY = offsetY
      this.clearHoverDwellTimer()
    } else if (Math.abs(offsetX) > HomeView.DRAG_MOVE_THRESHOLD ||
      Math.abs(offsetY) > HomeView.DRAG_MOVE_THRESHOLD) {
      this.dismissContextMenuForDrag()
    }
    this.updateDropTargetIndex()
    this.scheduleDragSqueeze(this.dragFromIndex, offsetX, offsetY)
    if (!this.showShortcutContextMenu) {
      this.syncShortcutOverlay()
    }
  }

  /** 优先用实测格距，其次用 Grid 宽度公式推算步长 */
  private syncShortcutGridMetrics(): void {
    this.ensureColStepFromAdjacentCells()
    this.ensureRowStepFromAdjacentRows()
    const inferredCol = this.inferColStepFromLayout()
    const inferredRow = this.inferRowStepFromLayout()
    if (inferredCol > 0) {
      this.shortcutColStep = inferredCol
    } else if (this.shortcutGridWidth > 0 && this.shortcutColStep <= 0) {
      this.refreshShortcutGridMetrics(this.shortcutGridWidth, 0)
    }
    if (inferredRow >= 90 && inferredRow <= 130) {
      this.shortcutRowStep = inferredRow
    }
  }

  private startShortcutDrag(index: number, featureId: string): void {
    if (this.dropSettling) {
      return
    }
    this.dismissContextMenuForDrag()
    this.sanitizeCellLayoutCache()
    this.syncShortcutGridMetrics()
    this.dragFromIndex = index
    this.dragHoverIndex = index
    this.dragSqueezeIndex = index
    this.lastSqueezeTargetIndex = -1
    this.draggingId = featureId
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.hoverCheckOffsetX = 0
    this.hoverCheckOffsetY = 0
    this.dragLiftVisible = true
    this.suppressShortcutClick = true
    this.contextMenuGridPanActive = true
    this.syncPlaceholderRect(index)
    this.scheduleContextMenu(index, featureId)
    this.syncShortcutOverlay()
    const x0 = this.cellLayoutX[0]
    const x1 = this.cellLayoutX[1]
    const cellDx = (!Number.isNaN(x0) && !Number.isNaN(x1)) ? Math.abs(x1 - x0) : 0
    const colSrc = this.inferColStepFromLayout() > 0 || cellDx >= 50 ? 'layout' : 'formula'
    BrowserLog.info(`[ShortcutDrag] start id=${featureId} index=${index} gridW=${this.shortcutGridWidth} ` +
      `colStep=${this.shortcutColStepValue()} rowStep=${this.shortcutRowStepValue()} src=${colSrc} ` +
      `cellX0=${Number.isNaN(x0) ? 'na' : x0.toFixed(1)} cellX1=${Number.isNaN(x1) ? 'na' : x1.toFixed(1)} ` +
      `cellDx=${cellDx.toFixed(1)} cellY0=${Number.isNaN(this.cellLayoutY[0]) ? 'na' : this.cellLayoutY[0].toFixed(1)} ` +
      `cellY4=${Number.isNaN(this.cellLayoutY[HomeView.SHORTCUT_COLS]) ? 'na' :
        this.cellLayoutY[HomeView.SHORTCUT_COLS].toFixed(1)}`)
  }

  private gridLayoutMetrics(): GridLayoutMetrics {
    return {
      cols: HomeView.SHORTCUT_COLS,
      colStep: this.shortcutColStepValue(),
      rowStep: this.shortcutRowStepValue(),
      colGap: HomeView.SHORTCUT_COL_GAP,
      paddingLeft: HomeView.SHORTCUT_GRID_PADDING_LEFT,
      paddingTop: HomeView.SHORTCUT_GRID_PADDING_TOP,
      cellContentHeight: this.shortcutCellHeight
    }
  }

  /** 全程显示占位框：指示松手后落位槽位（菜单展示时隐藏） */
  private shouldShowDropPlaceholderOverlay(): boolean {
    return this.isShortcutLiftActive()
      && this.dragHoverIndex >= 0
      && !this.showShortcutContextMenu
  }

  /** 跟手图标锚点（相对 ShortcutGrid Stack 左上角） */
  private dragFloatingAnchorLeft(): number {
    if (this.dragFromIndex >= 0) {
      const rect = this.resolveIconRect(this.dragFromIndex)
      if (!Number.isNaN(rect.left)) {
        return rect.left
      }
    }
    const halfW = HomeView.SHORTCUT_ICON_BOX * 0.5
    return this.resolveSlotCenterX(this.dragFromIndex) - halfW
  }

  private dragFloatingAnchorTop(): number {
    if (this.dragFromIndex >= 0) {
      const rect = this.resolveIconRect(this.dragFromIndex)
      if (!Number.isNaN(rect.top)) {
        return rect.top
      }
    }
    return this.formulaIconTop(this.dragFromIndex)
  }

  /** 根据手指偏移估算悬停插入下标 */
  private computeDropIndex(fromIndex: number, offsetX: number, offsetY: number): number {
    return computeHoverIndex(
      fromIndex,
      offsetX,
      offsetY,
      this.shortcutIds.length,
      HomeView.SHORTCUT_COLS,
      this.shortcutColStepValue(),
      this.shortcutRowStepValue(),
      this.cellLayoutX,
      this.cellLayoutY,
      this.gridLayoutMetrics()
    )
  }

  /** 占位框/落位：随手指即时更新，不等待挤位停顿 */
  private updateDropTargetIndex(): void {
    if (!this.draggingId || this.dragFromIndex < 0) {
      return
    }
    this.syncShortcutGridMetrics()
    const hover = this.computeDropIndex(this.dragFromIndex, this.dragOffsetX, this.dragOffsetY)
    if (hover !== this.dragHoverIndex) {
      this.dragHoverIndex = hover
      this.syncPlaceholderRect(hover)
      BrowserLog.info(`[ShortcutDrag] placeholder slot=${hover} from=${this.dragFromIndex}`)
    }
  }

  /** 挤位动效：停顿后再切换目标，避免拖动过程抖动 */
  private applyDragSqueeze(fromIndex: number, offsetX: number, offsetY: number): void {
    if (!this.draggingId) {
      return
    }
    this.syncShortcutGridMetrics()
    const hover = this.computeDropIndex(fromIndex, offsetX, offsetY)
    if (hover !== this.dragSqueezeIndex) {
      const restoring = hover === this.dragFromIndex
      if (!restoring) {
        this.lastSqueezeTargetIndex = hover
      }
      this.dragSqueezeIndex = hover
      this.syncPlaceholderRect(hover)
      this.logSqueezeHover(fromIndex, hover, restoring)
    }
  }

  /** 立即更新悬停目标并触发挤位动效（不重排 ForEach） */
  private applyDragHover(fromIndex: number, offsetX: number, offsetY: number): void {
    this.applyDragSqueeze(fromIndex, offsetX, offsetY)
  }

  private logSqueezeHover(fromIndex: number, hover: number, restoring: boolean): void {
    const animMs = this.resolveSqueezeTransitionDuration(hover, this.lastSqueezeTargetIndex, restoring)
    const crossRow = this.isCrossRowBetween(fromIndex, restoring ? this.lastSqueezeTargetIndex : hover)
    BrowserLog.info(`[ShortcutDrag] squeeze from=${fromIndex} to=${hover} restore=${restoring} ` +
      `lastTarget=${this.lastSqueezeTargetIndex} crossRow=${crossRow} animMs=${animMs}`)
    const bingIdx = this.shortcutIds.indexOf('bing')
    const metrics = this.gridLayoutMetrics()
    if (bingIdx >= 0) {
      const target = this.previewTargetIndex(bingIdx)
      const path = this.shortcutSqueezePath(bingIdx)
      const t = this.squeezeTranslate(bingIdx)
      const fromCol = bingIdx % HomeView.SHORTCUT_COLS
      const toCol = target % HomeView.SHORTCUT_COLS
      const colSrc = this.inferColStepFromLayout() > 0 ? 'layout' : 'formula'
      BrowserLog.info(`[ShortcutDrag] hover detail gridW=${this.shortcutGridWidth} ` +
        `colStep=${metrics.colStep} src=${colSrc} bing cell=${bingIdx} target=${target} col ${fromCol}->${toCol} ` +
        `translate=(${t.x.toFixed(1)},${t.y.toFixed(1)}) pathCrossRow=${path.crossRow}`)
    }
  }

  private isCrossRowBetween(indexA: number, indexB: number): boolean {
    if (indexA < 0 || indexB < 0) {
      return false
    }
    const cols = HomeView.SHORTCUT_COLS
    return Math.floor(indexA / cols) !== Math.floor(indexB / cols)
  }

  /** 挤位/还原动效时长：还原到原位时仍保留平移或跨行动画，避免 translate 瞬间归零 */
  private resolveSqueezeTransitionDuration(hover: number, lastTarget: number,
    restoring: boolean): number {
    if (restoring && lastTarget >= 0 && lastTarget !== hover) {
      return this.isCrossRowBetween(hover, lastTarget) ?
        HomeView.SQUEEZE_CROSS_ROW_MS : HomeView.SQUEEZE_SAME_ROW_MS
    }
    if (hover >= 0 && hover !== this.dragFromIndex) {
      return this.isCrossRowBetween(this.dragFromIndex, hover) ?
        HomeView.SQUEEZE_CROSS_ROW_MS : HomeView.SQUEEZE_SAME_ROW_MS
    }
    return 0
  }

  private isRestoringSqueezeToOrigin(): boolean {
    return this.isShortcutDragging()
      && this.dragSqueezeIndex === this.dragFromIndex
      && this.lastSqueezeTargetIndex >= 0
      && this.lastSqueezeTargetIndex !== this.dragFromIndex
  }

  /** 连续拖动时不挤位；停顿 HOVER_DWELL_MS 后再切换挤位目标 */
  private scheduleDragSqueeze(fromIndex: number, offsetX: number, offsetY: number): void {
    this.syncShortcutGridMetrics()
    const pendingHover = this.computeDropIndex(fromIndex, offsetX, offsetY)
    const atOriginSlot = this.dragSqueezeIndex === this.dragFromIndex
    const targetingOrigin = pendingHover === this.dragFromIndex
    if (pendingHover !== this.dragSqueezeIndex && (atOriginSlot || targetingOrigin)) {
      this.clearHoverDwellTimer()
      this.hoverCheckOffsetX = offsetX
      this.hoverCheckOffsetY = offsetY
      this.applyDragSqueeze(fromIndex, offsetX, offsetY)
      return
    }

    const dx = Math.abs(offsetX - this.hoverCheckOffsetX)
    const dy = Math.abs(offsetY - this.hoverCheckOffsetY)
    if (dx >= HomeView.HOVER_MOVE_THRESHOLD || dy >= HomeView.HOVER_MOVE_THRESHOLD) {
      this.hoverCheckOffsetX = offsetX
      this.hoverCheckOffsetY = offsetY
      this.clearHoverDwellTimer()
    }
    if (this.hoverDwellTimer >= 0) {
      return
    }
    this.hoverDwellTimer = setTimeout(() => {
      this.hoverDwellTimer = -1
      this.applyDragSqueeze(fromIndex, this.dragOffsetX, this.dragOffsetY)
    }, HomeView.HOVER_DWELL_MS)
  }

  private emptySqueezePath(): GridSqueezePath {
    return {
      outer: { x: 0, y: 0 },
      inner: { x: 0, y: 0 },
      crossRow: false
    }
  }

  /** 对比初始/预览线性数组，计算格子挤位 L 形路径 */
  private shortcutSqueezePath(index: number): GridSqueezePath {
    if (!this.isShortcutDragging() || this.dragFromIndex < 0 || this.dragSqueezeIndex < 0) {
      return this.emptySqueezePath()
    }
    if (index === this.dragFromIndex) {
      return this.emptySqueezePath()
    }
    if (this.dragFromIndex === this.dragSqueezeIndex) {
      return this.emptySqueezePath()
    }
    return squeezePathForCell(
      index,
      this.dragFromIndex,
      this.dragSqueezeIndex,
      this.shortcutIds,
      this.gridLayoutMetrics(),
      this.cellLayoutX,
      this.cellLayoutY
    )
  }

  /** 槽位内容区宽度（不含列间距） */
  private slotCellWidth(): number {
    return this.shortcutColStepValue() - HomeView.SHORTCUT_COL_GAP
  }

  /** 槽位内容中心 X：优先实测，同列按 colStep 外推 */
  private resolveSlotCenterX(index: number): number {
    if (index >= 0 && index < this.cellLayoutX.length && !Number.isNaN(this.cellLayoutX[index])) {
      return this.cellLayoutX[index]
    }
    const cols = HomeView.SHORTCUT_COLS
    const col = index % cols
    if (col < this.cellLayoutX.length && !Number.isNaN(this.cellLayoutX[col])) {
      return this.cellLayoutX[col]
    }
    if (!Number.isNaN(this.cellLayoutX[0])) {
      return this.cellLayoutX[0] + col * this.shortcutColStepValue()
    }
    return gridPointCenterX(col, this.gridLayoutMetrics())
  }

  /** 槽位内容中心 Y：优先实测，同行按 rowStep 外推（不用整格 183 高中点） */
  private resolveSlotCenterY(index: number): number {
    if (index >= 0 && index < this.cellLayoutY.length && this.isCellLayoutYValid(index)) {
      return this.cellLayoutY[index]
    }
    const cols = HomeView.SHORTCUT_COLS
    const col = index % cols
    const row = Math.floor(index / cols)
    if (col < this.cellLayoutY.length && this.isCellLayoutYValid(col)) {
      return this.cellLayoutY[col] + row * this.shortcutRowStepValue()
    }
    const m = this.gridLayoutMetrics()
    const contentHalf = HomeView.SHORTCUT_ITEM_PADDING + HomeView.PLACEHOLDER_HALF_HEIGHT
    return row * m.rowStep + contentHalf
  }

  private syncPlaceholderRect(slotIndex: number): void {
    if (slotIndex < 0) {
      return
    }
    this.placeholderRect = this.resolveIconRect(slotIndex)
  }

  /** 解析指定槽位图标方块矩形，优先实测，与弹起前图标对齐 */
  private resolveIconRect(index: number): ShortcutIconRect {
    if (index < 0) {
      return {
        left: 0,
        top: 0,
        width: HomeView.SHORTCUT_ICON_BOX,
        height: HomeView.SHORTCUT_ICON_BOX
      }
    }
    if (index < this.cellIconLeft.length && !Number.isNaN(this.cellIconLeft[index]) &&
      index < this.cellIconTop.length && !Number.isNaN(this.cellIconTop[index])) {
      const width = this.cellIconWidth[index] > 0 ? this.cellIconWidth[index] : HomeView.SHORTCUT_ICON_BOX
      const height = this.cellIconHeight[index] > 0 ? this.cellIconHeight[index] : width
      return {
        left: this.cellIconLeft[index],
        top: this.cellIconTop[index],
        width: width,
        height: height
      }
    }
    const width = HomeView.SHORTCUT_ICON_BOX
    const height = HomeView.SHORTCUT_ICON_BOX
    const cx = this.resolveSlotCenterX(index)
    let top = this.formulaIconTop(index)
    return {
      left: cx - width * 0.5,
      top: top,
      width: width,
      height: height
    }
  }

  /** 无图标实测时，由格子中心与高度推算图标顶边 */
  private formulaIconTop(index: number): number {
    const cols = HomeView.SHORTCUT_COLS
    const col = index % cols
    const row = Math.floor(index / cols)
    if (index < this.cellLayoutY.length && this.isCellLayoutYValid(index)) {
      const cy = this.cellLayoutY[index]
      const itemH = this.resolveItemHeight(index)
      return cy - itemH * 0.5 + HomeView.SHORTCUT_ITEM_PADDING
    }
    if (col < this.cellLayoutY.length && this.isCellLayoutYValid(col)) {
      const cy = this.cellLayoutY[col] + row * this.shortcutRowStepValue()
      const itemH = this.resolveItemHeight(index)
      return cy - itemH * 0.5 + HomeView.SHORTCUT_ITEM_PADDING
    }
    const m = this.gridLayoutMetrics()
    return row * m.rowStep + HomeView.SHORTCUT_ITEM_PADDING
  }

  private resolveItemHeight(index: number): number {
    if (index >= 0 && index < this.cellLayoutH.length && this.cellLayoutH[index] > 0) {
      return Math.min(this.cellLayoutH[index], this.shortcutCellHeight)
    }
    return this.shortcutCellHeight
  }

  /** 网格总槽位数（行 × 列） */
  private shortcutGridSlotCount(): number {
    return HomeView.SHORTCUT_COLS * this.shortcutGridRowsCount()
  }

  /** 允许添加的快捷方式数量上限（等于可视槽位总数；未满时「添加快捷方式」占最后一格） */
  private maxShortcutCount(): number {
    return Math.max(1, this.shortcutGridSlotCount())
  }

  private isShortcutAtLimit(): boolean {
    return this.shortcutIds.length >= this.maxShortcutCount()
  }

  private shortcutGridRowsCount(): number {
    return this.shortcutGridRows
  }

  /** 当前窗口是否横向（宽 > 高）：优先使用实测视口尺寸 */
  private isWideWindow(): boolean {
    return this.homeWideWindow
  }

  private resolveWideWindow(width: number, height: number): boolean {
    if (width > 0 && height > 0) {
      return width > height
    }
    if (this.windowWidth > 0 && this.windowHeight > 0) {
      return this.windowWidth > this.windowHeight
    }
    return this.isLandscape
  }

  /** 是否横屏主页布局（搜索栏置顶） */
  private isLandscapeLayout(): boolean {
    return this.isWideWindow()
  }

  /** 搜索栏顶边 Y：优先用 SearchRow 实测，避免估算偏差导致图底与搜索框脱节 */
  private estimatedSearchBarTop(): number {
    if (this.measuredSearchBarTop >= 0) {
      return this.measuredSearchBarTop
    }
    if (this.homeViewportHeight <= 0) {
      return 0
    }
    if (this.isLandscapeLayout()) {
      return this.safeAreaTop + HomeView.LANDSCAPE_SEARCH_TOP_PADDING
    }
    const contentH = Math.max(0, this.homeViewportHeight - this.safeAreaTop)
    return this.safeAreaTop + contentH * 0.5 - HomeView.SEARCH_ROW_HEIGHT / 2
  }

  /** 记录搜索栏顶边相对 HomeView 的本地 Y，供 bg 底对齐 */
  private onSearchBarAreaChange(area: Area): void {
    const globalPos = area.globalPosition
    if (!globalPos) {
      return
    }
    const top = (globalPos.y as number) - this.homeViewGlobalY
    if (top < 0 || !Number.isFinite(top)) {
      return
    }
    if (Math.abs(top - this.measuredSearchBarTop) <= 1 && this.measuredSearchBarTop >= 0) {
      return
    }
    this.measuredSearchBarTop = top
  }

  /** 搜索栏底边估算 Y（供网格容量与 bg 区域计算） */
  private estimatedSearchBarBottom(): number {
    return this.estimatedSearchBarTop() + HomeView.SEARCH_ROW_HEIGHT
  }

  /** 搜索框上方区域高度（仅此区域铺 bg，不延伸到搜索框及以下） */
  private homeBgRegionHeight(): number {
    return Math.max(0, this.estimatedSearchBarTop())
  }

  /** 是否展示首页装饰图（上方区域足够时浅色/深色均显示；由 HOME_BG_DECOR_ENABLED 总控） */
  private shouldShowHomeBgDecor(): boolean {
    if (!HomeView.HOME_BG_DECOR_ENABLED) {
      return false
    }
    return this.homeBgRegionHeight() >= HomeView.HOME_BG_MIN_REGION
  }

  /**
   * 装饰图顶边最低值：仅状态栏留白，保证水面以上不被裁切。
   */
  private homeBgMinTop(): number {
    return this.safeAreaTop + HomeView.HOME_BG_STATUS_GAP
  }

  /**
   * 装饰图顶边（状态栏留白 + 整体下移）。
   */
  private homeBgVisibleTop(): number {
    return this.homeBgMinTop() + HomeView.HOME_BG_NUDGE_DOWN
  }

  /**
   * 搜索框上方需露出的图高占比：天光区 + 倒影区未覆盖部分（30%）。
   * 倒影区 70% 落在搜索框下。
   */
  private homeBgVisibleFraction(): number {
    const horizon = HomeView.HOME_BG_HORIZON_RATIO
    const cover = HomeView.HOME_BG_REFLECTION_COVER
    return horizon + (1 - cover) * (1 - horizon)
  }

  /**
   * 搜索框上方可见高度（天光 + 30% 倒影），由留白/下移与实测搜索框顶决定。
   */
  private homeBgAvailableHeight(): number {
    const searchTop = this.estimatedSearchBarTop()
    if (searchTop <= 0) {
      return 0
    }
    return Math.max(0, searchTop - this.homeBgVisibleTop())
  }

  /**
   * 整图高度：倒影底部 70% 伸入搜索框；微微放大，但顶边不低于 minTop，水面以上完整。
   */
  private homeBgImageHeight(): number {
    const visibleH = this.homeBgAvailableHeight()
    const fraction = this.homeBgVisibleFraction()
    if (visibleH <= 0 || fraction <= 0) {
      return 0
    }
    let imageH = visibleH / fraction * HomeView.HOME_BG_SCALE_BOOST
    const searchTop = this.estimatedSearchBarTop()
    const minTop = this.homeBgMinTop()
    // 放大后若顶边会高于 minTop（裁切天光），则回退到刚好贴齐 minTop 的最大高度
    const maxHKeepSky = (searchTop - minTop) / fraction
    if (maxHKeepSky > 0) {
      imageH = Math.min(imageH, maxHKeepSky)
    }
    const width = this.homeViewportWidth
    if (width > 0) {
      const naturalH = width / HomeView.HOME_BG_ASPECT
      imageH = Math.min(imageH, naturalH)
    }
    return imageH
  }

  /** 倒影区被搜索框覆盖的高度（倒影区的 70%） */
  private homeBgSearchOverlap(): number {
    return this.homeBgReflectionHeight() * HomeView.HOME_BG_REFLECTION_COVER
  }

  /** bg 显示宽度：与高度保持原图比例 */
  private homeBgImageWidth(): number {
    const imageH = this.homeBgImageHeight()
    if (imageH <= 0) {
      return 0
    }
    return imageH * HomeView.HOME_BG_ASPECT
  }

  /**
   * 装饰图顶边：底对齐「搜索框顶 + 70% 倒影覆盖」；不低于 minTop，保证水面以上完整。
   */
  private homeBgImageTop(): number {
    const searchTop = this.estimatedSearchBarTop()
    const imageH = this.homeBgImageHeight()
    if (searchTop <= 0 || imageH <= 0) {
      return 0
    }
    const topByBottomAlign = searchTop + this.homeBgSearchOverlap() - imageH
    return Math.max(this.homeBgMinTop(), topByBottomAlign)
  }

  /** 装饰图水平偏移：相对视口居中 */
  private homeBgImageLeft(): number {
    const width = this.homeViewportWidth
    const displayW = this.homeBgImageWidth()
    if (width <= 0 || displayW <= 0) {
      return 0
    }
    return (width - displayW) * 0.5
  }

  /** 交错线（水面）在装饰图内的相对高度 */
  private homeBgHorizonHeight(): number {
    return this.homeBgImageHeight() * HomeView.HOME_BG_HORIZON_RATIO
  }

  /** 水面倒影区高度（交错线以下 → 图底） */
  private homeBgReflectionHeight(): number {
    const imageH = this.homeBgImageHeight()
    if (imageH <= 0) {
      return 0
    }
    return Math.max(0, imageH - this.homeBgHorizonHeight())
  }

  /** 快捷方式区域顶边（搜索框下方） */
  private shortcutGridStartOffset(): number {
    return this.estimatedSearchBarBottom()
  }

  /** 快捷方式可用高度（行区域，不含 top padding） */
  private shortcutGridAvailableHeight(): number {
    if (this.homeViewportHeight <= 0) {
      return 0
    }
    const available = this.homeViewportHeight - this.shortcutGridStartOffset() - this.bottomNavClearance()
    return Math.max(0, available - HomeView.SHORTCUT_GRID_PADDING_TOP)
  }

  private rowsFitInHeight(availableContentHeight: number): number {
    const cellH = HomeView.SHORTCUT_CELL_CONTENT_HEIGHT
    const rowStep = cellH + HomeView.SHORTCUT_ROW_GAP
    if (rowStep <= 0) {
      return HomeView.MIN_SHORTCUT_GRID_ROWS
    }
    return Math.floor(availableContentHeight / rowStep)
  }

  /** 竖屏至少 2 行；空间不足时优先压缩行距，尽量保持单元格高度避免末行被裁切 */
  private syncShortcutCellLayout(): void {
    const rows = this.shortcutGridRowsCount()
    const budget = Math.max(0, this.shortcutGridAvailableHeight() - HomeView.SHORTCUT_LAYOUT_SAFETY_PX)
    let cellH = HomeView.SHORTCUT_CELL_CONTENT_HEIGHT
    let rowGap = HomeView.SHORTCUT_ROW_GAP
    if (rows > 0 && budget > 0) {
      let needed = rows * cellH + (rows - 1) * rowGap
      if (needed > budget) {
        rowGap = HomeView.MIN_SHORTCUT_ROW_GAP
        cellH = Math.floor((budget - (rows - 1) * rowGap) / rows)
        cellH = Math.min(HomeView.SHORTCUT_CELL_CONTENT_HEIGHT,
          Math.max(HomeView.MIN_SHORTCUT_CELL_HEIGHT, cellH))
        needed = rows * cellH + (rows - 1) * rowGap
        if (needed > budget) {
          rowGap = Math.max(HomeView.MIN_SHORTCUT_ROW_GAP,
            Math.floor((budget - rows * HomeView.MIN_SHORTCUT_CELL_HEIGHT) / Math.max(1, rows - 1)))
          cellH = Math.max(HomeView.MIN_SHORTCUT_CELL_HEIGHT,
            Math.floor((budget - (rows - 1) * rowGap) / rows))
        }
      }
    }
    if (rows >= 2) {
      rowGap = Math.max(HomeView.MIN_SHORTCUT_ROW_GAP, rowGap)
      cellH = Math.max(HomeView.MIN_SHORTCUT_CELL_HEIGHT, cellH)
    }
    this.shortcutCellHeight = cellH
    this.shortcutRowGapEffective = rowGap
    this.shortcutRowStep = cellH + this.shortcutGridRowsGap()
  }

  /** 两行及以上时强制更大行距，避免视觉贴叠 */
  private shortcutGridRowsGap(): number {
    if (this.shortcutGridRowsCount() >= 2) {
      return Math.max(14, this.shortcutRowGapEffective)
    }
    return this.shortcutRowGapEffective
  }

  /** 优先使用布局实测单元高度（上限为当前网格单元高度，避免放大缩放后行数被算成 1） */
  private effectiveCellHeight(): number {
    if (this.cellLayoutH.length > 0 && this.cellLayoutH[0] > 0) {
      return Math.min(this.cellLayoutH[0], this.shortcutCellHeight)
    }
    return this.shortcutCellHeight
  }

  private onFontUiRevChanged(): void {
    this.cellLayoutX = []
    this.cellLayoutY = []
    this.cellLayoutH = []
    this.recomputeShortcutGridRows()
  }

  private syncShortcutCapacity(): void {
    AppStorage.setOrCreate(AppStorageKeys.SHORTCUT_MAX_COUNT, this.maxShortcutCount())
  }

  /** 根据视口高度动态计算快捷方式 Grid 行数与容量上限 */
  private recomputeShortcutGridRows(): void {
    if (this.homeViewportHeight <= 0) {
      this.shortcutGridRows = HomeView.MIN_SHORTCUT_GRID_ROWS
      this.syncShortcutCellLayout()
      this.syncShortcutCapacity()
      return
    }
    let rows = this.rowsFitInHeight(this.shortcutGridAvailableHeight())
    // 需求：快捷方式区域最低保持两行（横竖屏一致）
    rows = Math.max(HomeView.MIN_SHORTCUT_GRID_ROWS, rows)
    rows = Math.min(HomeView.MAX_SHORTCUT_GRID_ROWS, rows)
    if (rows !== this.shortcutGridRows) {
      this.shortcutGridRows = rows
    }
    this.syncShortcutCellLayout()
    this.syncShortcutCapacity()
    BrowserLog.info(
      `[ShortcutGrid] landscape=${this.isLandscapeLayout()} viewport=${this.homeViewportHeight.toFixed(0)} ` +
      `top=${this.shortcutGridStartOffset().toFixed(0)} ` +
      `rows=${rows} cellH=${this.shortcutCellHeight} rowGap=${this.shortcutRowGapEffective} ` +
      `max=${this.maxShortcutCount()} slots=${this.shortcutGridSlotCount()} ` +
      `avail=${this.shortcutGridAvailableHeight().toFixed(0)} outerH=${this.shortcutGridOuterHeight()}`
    )
  }

  private onShortcutWrapperAreaChange(area: Area): void {
    this.onShortcutAreaWidthChange(area.width as number)
  }

  private onHomeViewportChange(height: number): void {
    if (height <= 0 || Math.abs(height - this.homeViewportHeight) <= 8) {
      return
    }
    this.homeViewportHeight = height
    this.recomputeShortcutGridRows()
  }

  /** 视口宽度变化：用于横竖布局判定与网格重算 */
  private onHomeViewportWidthChange(width: number): void {
    if (width <= 0 || Math.abs(width - this.homeViewportWidth) <= 1) {
      return
    }
    this.homeViewportWidth = width
    this.recomputeShortcutGridRows()
  }

  /**
   * 根视口宽高必须成对更新，避免用旧宽高误判横竖屏布局。
   * 注意：不因 layoutFrozen 丢弃——HomeView 实测可见区是横竖布局唯一权威来源。
   */
  private onHomeViewportSizeChange(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return
    }
    const wasLandscape = this.homeWideWindow
    const widthChanged = Math.abs(width - this.homeViewportWidth) > 1
    const heightChanged = Math.abs(height - this.homeViewportHeight) > 8
    if (!widthChanged && !heightChanged) {
      // 尺寸未变但宽高比状态可能因冻结期间错过更新，仍强制对齐
      const aligned = this.resolveWideWindow(width, height)
      if (aligned !== this.homeWideWindow) {
        this.homeWideWindow = aligned
        this.homeLayoutRev++
        this.measuredSearchBarTop = -1
        this.resetShortcutGridMeasurements(aligned ? 'ratio_to_landscape' : 'ratio_to_portrait')
      }
      return
    }
    this.homeViewportWidth = width
    this.homeViewportHeight = height
    this.measuredSearchBarTop = -1
    const nowLandscape = this.resolveWideWindow(width, height)
    this.homeWideWindow = nowLandscape
    this.homeLayoutRev++
    BrowserLog.info(
      `[HomeView] viewport=${width.toFixed(0)}x${height.toFixed(0)} wide=${nowLandscape} rev=${this.homeLayoutRev}`
    )
    if (wasLandscape !== nowLandscape) {
      this.resetShortcutGridMeasurements(nowLandscape ? 'ratio_to_landscape' : 'ratio_to_portrait')
      return
    }
    this.recomputeShortcutGridRows()
  }

  /**
   * 窗口尺寸 Storage 变化：视口未测或与 Storage 宽高比冲突（旋转冻结导致视口过期）时同步布局。
   * 视口已测且宽高比一致时，仍以视口为准，不让 WINDOW_LANDSCAPE 覆盖。
   */
  private onWindowSizeStorageChanged(): void {
    if (this.windowWidth <= 0 || this.windowHeight <= 0) {
      return
    }
    const storageWide = this.windowWidth > this.windowHeight
    if (this.homeViewportWidth > 0 && this.homeViewportHeight > 0) {
      const viewportWide = this.homeViewportWidth > this.homeViewportHeight
      if (viewportWide === storageWide) {
        return
      }
      // 视口宽高比与窗口 Storage 冲突：视为旋转期间冻结导致的过期视口，先跟 Storage
      BrowserLog.info(
        `[HomeView] stale viewport ${this.homeViewportWidth.toFixed(0)}x${this.homeViewportHeight.toFixed(0)} ` +
        `vs storage ${this.windowWidth}x${this.windowHeight}, adopt storage`
      )
      this.homeViewportWidth = 0
      this.homeViewportHeight = 0
    }
    if (storageWide !== this.homeWideWindow) {
      this.homeWideWindow = storageWide
      this.homeLayoutRev++
      this.resetShortcutGridMeasurements(storageWide ? 'storage_to_landscape' : 'storage_to_portrait')
    }
  }

  /** 横竖屏切换时重算快捷方式网格容量（清除旧布局实测值） */
  private onWindowRevChanged(): void {
    let nextWide: boolean
    if (this.homeViewportWidth > 0 && this.homeViewportHeight > 0) {
      const viewportWide = this.homeViewportWidth > this.homeViewportHeight
      const storageWide = this.windowWidth > 0 && this.windowHeight > 0 ?
        this.windowWidth > this.windowHeight : viewportWide
      if (viewportWide !== storageWide && this.windowWidth > 0 && this.windowHeight > 0) {
        // 过期视口与窗口尺寸冲突时，丢弃视口并采用 Storage，等待下次 onAreaChange 校准
        BrowserLog.info(
          `[HomeView] rev stale viewport ${this.homeViewportWidth.toFixed(0)}x${this.homeViewportHeight.toFixed(0)} ` +
          `vs storage ${this.windowWidth}x${this.windowHeight}`
        )
        this.homeViewportWidth = 0
        this.homeViewportHeight = 0
        nextWide = storageWide
      } else {
        nextWide = viewportWide
      }
    } else {
      nextWide = this.resolveWideWindow(this.windowWidth, this.windowHeight)
    }
    if (nextWide !== this.homeWideWindow) {
      this.homeWideWindow = nextWide
    }
    this.homeLayoutRev++
    BrowserLog.info(`[Window] HomeView rev=${this.windowRev} landscape=${this.isLandscapeLayout()}`)
    this.shortcutGridWidth = 0
    this.shortcutColStep = 0
    this.shortcutRowStep = 0
    this.cellLayoutX = []
    this.cellLayoutY = []
    this.cellLayoutH = []
    this.cellIconLeft = []
    this.cellIconTop = []
    this.cellIconWidth = []
    this.cellIconHeight = []
    this.forceResetShortcutInteractionState('window_rev_changed')
    this.recomputeShortcutGridRows()
  }

  /** 宽高比切换（横/竖）时清空旧测量，避免网格沿用旧步长而堆叠 */
  private resetShortcutGridMeasurements(reason: string): void {
    this.homeLayoutRev++
    this.shortcutGridWidth = 0
    this.shortcutColStep = 0
    this.shortcutRowStep = 0
    this.cellLayoutX = []
    this.cellLayoutY = []
    this.cellLayoutH = []
    this.cellIconLeft = []
    this.cellIconTop = []
    this.cellIconWidth = []
    this.cellIconHeight = []
    this.forceResetShortcutInteractionState(`ratio_change_${reason}`)
    BrowserLog.info(`[Window] HomeView reset measurements reason=${reason}`)
    this.recomputeShortcutGridRows()
  }

  /** 横竖切换后强制重建 Grid，避免沿用旧布局缓存导致堆叠 */
  private shortcutGridRenderKey(): string {
    return `grid-${this.homeLayoutRev}-${this.windowRev}-${this.homeViewportWidth}x${this.homeViewportHeight}` +
      `-${this.shortcutGridRows}-${this.shortcutCellHeight}-${this.shortcutRowGapEffective}`
  }

  /** 网格行区域高度（不含 top padding） */
  private shortcutGridRowsHeight(): number {
    const rows = this.shortcutGridRowsCount()
    return rows * this.shortcutCellHeight + (rows - 1) * this.shortcutGridRowsGap()
  }

  /** 网格内容高度（含 top padding） */
  private shortcutGridContentHeight(): number {
    return HomeView.SHORTCUT_GRID_PADDING_TOP + this.shortcutGridRowsHeight()
  }

  /** 快捷方式区域总高度 */
  private shortcutGridOuterHeight(): number {
    return this.shortcutGridContentHeight()
  }

  private onShortcutIdsChanged(): void {
    this.recomputeShortcutGridRows()
  }

  private onShortcutAreaWidthChange(width: number): void {
    if (width > 0 && Math.abs(width - this.shortcutGridWidth) > 1) {
      this.shortcutGridWidth = width
      this.syncShortcutGridMetrics()
    }
  }

  /** 当前 Grid 要渲染的槽位 id 列表 */
  private gridSlotIds(): string[] {
    const result = this.shortcutIds.filter((id: string) => {
      return ShortcutManager.resolveDisplayEntry(id) !== undefined
    })
    if (this.shouldShowAddShortcut()) {
      result.push(HomeView.ADD_SHORTCUT_SLOT_ID)
    }
    return result
  }

  private shortcutRowsTemplate(): string {
    const rows = this.shortcutGridRowsCount()
    const parts: string[] = []
    for (let i = 0; i < rows; i++) {
      parts.push(`${this.shortcutCellHeight}vp`)
    }
    return parts.join(' ')
  }

  private shortcutItemBottomGap(index: number): number {
    const row = Math.floor(index / HomeView.SHORTCUT_COLS)
    if (row < this.shortcutGridRowsCount() - 1) {
      return this.shortcutGridRowsGap()
    }
    return 0
  }

  private shouldShowAddShortcut(): boolean {
    if (this.isAddShortcutSuppressed()) {
      return false
    }
    const visibleCount = this.shortcutIds.filter((id: string) => {
      return ShortcutManager.resolveDisplayEntry(id) !== undefined
    }).length
    return visibleCount < this.shortcutGridSlotCount()
  }

  private isAddShortcutSuppressed(): boolean {
    return this.isShortcutDragging()
  }

  /** 挤位/落位动效期间放宽 Grid 裁剪，避免斜线轨迹被截断 */
  private shouldClipShortcutGrid(): boolean {
    return !this.isShortcutDragging() && !this.dropSettling
  }

  /** 预览数组中某 id 的挤位目标下标 */
  private previewTargetIndex(cellIndex: number): number {
    if (!this.isShortcutDragging() || this.dragFromIndex < 0 || this.dragSqueezeIndex < 0) {
      return cellIndex
    }
    const previewIds = reorderArrayIds(this.shortcutIds, this.dragFromIndex, this.dragSqueezeIndex)
    return previewIndexOfId(this.shortcutIds[cellIndex], previewIds)
  }

  /** 挤位 / 落位 translate（单层斜线或水平） */
  private itemContentTranslate(index: number, featureId: string): GridTranslate {
    if (this.dropSettling) {
      const t = this.dropSettleById[featureId]
      if (t !== undefined) {
        return t
      }
      return { x: 0, y: 0 }
    }
    return this.squeezeTranslate(index)
  }

  /** 挤位 translate 合并（日志 / 落位计算） */
  private squeezeTranslate(index: number): GridTranslate {
    const path = this.shortcutSqueezePath(index)
    return {
      x: path.outer.x + path.inner.x,
      y: path.outer.y + path.inner.y
    }
  }

  /** 重排后各 id 的归位偏移：非拖项已在目标槽位应为 0，仅拖项从手指位置滑入 */
  private buildPostReorderSettleOffsets(
    from: number,
    to: number,
    draggedId: string,
    dragOffsetX: number,
    dragOffsetY: number
  ): Record<string, GridTranslate> {
    const offsets: Record<string, GridTranslate> = {}
    if (draggedId.length === 0) {
      return offsets
    }
    let slotShiftX = 0
    let slotShiftY = 0
    const xFrom = this.cellLayoutX[from]
    const xTo = this.cellLayoutX[to]
    const yFrom = this.cellLayoutY[from]
    const yTo = this.cellLayoutY[to]
    if (!Number.isNaN(xFrom) && !Number.isNaN(xTo) && !Number.isNaN(yFrom) && !Number.isNaN(yTo)) {
      slotShiftX = xFrom - xTo
      const cols = HomeView.SHORTCUT_COLS
      const fromRow = Math.floor(from / cols)
      const toRow = Math.floor(to / cols)
      slotShiftY = fromRow === toRow ? 0 : (yFrom - yTo)
    } else {
      const cols = HomeView.SHORTCUT_COLS
      const fromPt = indexToGridPoint(from, cols)
      const toPt = indexToGridPoint(to, cols)
      slotShiftX = (fromPt.col - toPt.col) * this.shortcutColStepValue()
      slotShiftY = (fromPt.row - toPt.row) * this.shortcutRowStepValue()
    }
    offsets[draggedId] = {
      x: dragOffsetX + slotShiftX,
      y: (dragOffsetY - 8) + slotShiftY
    }
    return offsets
  }

  /** 松手前记录跨行挤位与实测/公式偏差，便于 HiLog 对照 */
  private logDropSettle(from: number, to: number, draggedId: string,
    settle: Record<string, GridTranslate>): void {
    const cols = HomeView.SHORTCUT_COLS
    const y0 = this.cellLayoutY[0]
    const yRow1 = this.cellLayoutY[cols]
    const rowDy = (!Number.isNaN(y0) && !Number.isNaN(yRow1)) ? Math.abs(yRow1 - y0) : 0
    const draggedSettle = settle[draggedId]
    BrowserLog.info(`[ShortcutDrag] drop from=${from} to=${to} dragged=${draggedId} ` +
      `colStep=${this.shortcutColStepValue().toFixed(1)} rowStep=${this.shortcutRowStepValue().toFixed(1)} ` +
      `rawRowStep=${this.shortcutRowStep.toFixed(1)} cellY0=${Number.isNaN(y0) ? 'na' : y0.toFixed(1)} ` +
      `cellY4=${Number.isNaN(yRow1) ? 'na' : yRow1.toFixed(1)} rowDy=${rowDy.toFixed(1)} ` +
      `dragSettle=(${draggedSettle?.x.toFixed(1)},${draggedSettle?.y.toFixed(1)})`)
    for (let i = 0; i < this.shortcutIds.length; i++) {
      const id = this.shortcutIds[i]
      if (id === draggedId) {
        continue
      }
      const target = this.previewTargetIndex(i)
      if (target === i) {
        continue
      }
      const measured = gridSqueezePathWithMeasure(i, target, this.gridLayoutMetrics(),
        this.cellLayoutX, this.cellLayoutY)
      const formula = gridSqueezePath(i, target, this.gridLayoutMetrics())
      const t = measured.outer
      BrowserLog.info(`[ShortcutDrag] drop squeeze id=${id} cell=${i}->${target} ` +
        `measured=(${t.x.toFixed(1)},${t.y.toFixed(1)}) formula=(${formula.outer.x.toFixed(1)},` +
        `${formula.outer.y.toFixed(1)}) crossRow=${measured.crossRow}`)
    }
  }

  private squeezeAnimationDuration(index: number): number {
    if (!this.isShortcutDragging()) {
      return 0
    }
    const path = this.shortcutSqueezePath(index)
    const hasTranslate = path.outer.x !== 0 || path.outer.y !== 0 ||
      path.inner.x !== 0 || path.inner.y !== 0
    if (hasTranslate) {
      return path.crossRow ? HomeView.SQUEEZE_CROSS_ROW_MS : HomeView.SQUEEZE_SAME_ROW_MS
    }
    if (this.isRestoringSqueezeToOrigin()) {
      return this.resolveSqueezeTransitionDuration(
        this.dragFromIndex,
        this.lastSqueezeTargetIndex,
        true
      )
    }
    return 0
  }

  private placeholderAnimationDuration(): number {
    if (this.dragFromIndex < 0 || this.dragSqueezeIndex < 0) {
      return HomeView.SQUEEZE_SAME_ROW_MS
    }
    if (this.isRestoringSqueezeToOrigin()) {
      return this.resolveSqueezeTransitionDuration(
        this.dragFromIndex,
        this.lastSqueezeTargetIndex,
        true
      )
    }
    return this.resolveSqueezeTransitionDuration(
      this.dragSqueezeIndex,
      this.lastSqueezeTargetIndex,
      false
    )
  }

  private isDropSettleDragged(featureId: string): boolean {
    return this.dropSettling && this.dropSettleDraggedId === featureId
  }

  private itemContentScale(featureId: string): number {
    if (this.isDropSettleDragged(featureId)) {
      return this.dropSettleScale
    }
    return 1
  }

  /** 落位两阶段：首帧无动画贴手指位置，次帧起 300ms 滑入槽位 */
  private itemContentAnimationDuration(index: number, featureId: string): number {
    if (this.isDropSettleDragged(featureId)) {
      if (this.dropSettleById[featureId] !== undefined) {
        return 0
      }
      return HomeView.DROP_SETTLE_MS
    }
    return this.squeezeAnimationDuration(index)
  }

  /** 启动松手落位：先显示在手指偏移处，再动画归零 */
  private beginDropSettleAnimation(draggedId: string, settleOffsets: Record<string, GridTranslate>,
    onComplete?: () => void): void {
    this.clearDropSettleTimers()
    this.dropSettling = true
    this.dropSettleDraggedId = draggedId
    this.dropSettleScale = 1.12
    this.endShortcutDrag()
    this.dropSettleById = settleOffsets
    this.suppressShortcutClick = true
    BrowserLog.info(`[ShortcutDrag] drop settle start id=${draggedId} ` +
      `offset=(${settleOffsets[draggedId]?.x.toFixed(1)},${settleOffsets[draggedId]?.y.toFixed(1)}) ` +
      `animMs=${HomeView.DROP_SETTLE_MS}`)

    this.dropSettleStartTimer = setTimeout(() => {
      this.dropSettleStartTimer = -1
      this.dropSettleById = {}
      this.dropSettleScale = 1
    }, HomeView.DROP_SETTLE_FRAME_MS)

    this.dropSettleEndTimer = setTimeout(() => {
      this.dropSettleEndTimer = -1
      this.dropSettling = false
      this.dropSettleDraggedId = ''
      this.suppressShortcutClick = false
      if (onComplete !== undefined) {
        onComplete()
      }
    }, HomeView.DROP_SETTLE_FRAME_MS + HomeView.DROP_SETTLE_MS)
  }

  /** 统一处理拖动手势结束（Pan 抬起 / 取消） */
  private finishShortcutDragGesture(featureId: string, offsetX: number, offsetY: number): void {
    if (this.draggingId !== featureId || this.dropSettling) {
      return
    }
    this.clearContextMenuTimer()
    // 菜单已展示：松手不改动冻结的跟手图/菜单位置
    if (this.showShortcutContextMenu) {
      this.contextMenuGridPanActive = false
      this.dragLiftOverlayPanActive = false
      this.syncShortcutOverlay()
      return
    }
    this.clearHoverDwellTimer()
    this.dragOffsetX = offsetX
    this.dragOffsetY = offsetY
    if (!this.hasDragMovement()) {
      this.commitCancelWithSettle(featureId, offsetX, offsetY)
      return
    }
    this.updateDropTargetIndex()
    this.applyDragSqueeze(this.dragFromIndex, offsetX, offsetY)
    const from = this.dragFromIndex
    const to = this.dragHoverIndex
    if (from >= 0 && to >= 0 && from !== to) {
      this.commitDropWithSettle(from, to)
    } else {
      this.commitCancelWithSettle(featureId, offsetX, offsetY)
    }
  }

  /** 松手回原位：从手指位置落回槽位 */
  private commitCancelWithSettle(featureId: string, offsetX: number, offsetY: number): void {
    this.clearHoverDwellTimer()
    this.applyDragHover(this.dragFromIndex, offsetX, offsetY)
    const settleOffsets: Record<string, GridTranslate> = {}
    settleOffsets[featureId] = { x: offsetX, y: offsetY - 8 }
    BrowserLog.info(`[ShortcutDrag] cancel settle id=${featureId} ` +
      `offset=(${offsetX.toFixed(1)},${offsetY.toFixed(1)}) animMs=${HomeView.DROP_SETTLE_MS}`)
    this.beginDropSettleAnimation(featureId, settleOffsets)
  }

  /** 松手：重排数组后立即用正确归位偏移，再动画归零 */
  private commitDropWithSettle(from: number, to: number): void {
    this.clearHoverDwellTimer()
    this.applyDragHover(from, this.dragOffsetX, this.dragOffsetY)

    const draggedId = this.draggingId
    const releaseOffsetX = this.dragOffsetX
    const releaseOffsetY = this.dragOffsetY
    const settleOffsets = this.buildPostReorderSettleOffsets(
      from, to, draggedId, releaseOffsetX, releaseOffsetY)
    this.logDropSettle(from, to, draggedId, settleOffsets)
    this.shortcutIds = reorderArrayIds(this.shortcutIds, from, to)
    this.beginDropSettleAnimation(draggedId, settleOffsets, () => {
      void BrowserStore.reorderShortcut(from, to)
    })
  }

  private isDraggedCell(index: number, featureId: string): boolean {
    return this.draggingId === featureId && this.dragLiftVisible
  }

  /** 长按菜单展示时隐藏 Grid 内原标题（菜单上方单独显示） */
  private shouldHideShortcutItemTitle(index: number, featureId: string): boolean {
    if (this.isDraggedCell(index, featureId)) {
      return true
    }
    return this.showShortcutContextMenu
      && this.contextMenuFeatureId === featureId
      && this.contextMenuIndex === index
  }

  private shortcutIconAreaChange(index: number, area: Area): void {
    if (this.isShortcutDragging() || this.dropSettling) {
      return
    }
    const globalPos = area.globalPosition
    const w = area.width as number
    const h = area.height as number
    if (!globalPos || w <= 0 || h <= 0) {
      return
    }
    this.updateCellLayout(
      index,
      (globalPos.x as number) - this.gridOriginGlobalX + w * 0.5,
      (globalPos.y as number) - this.gridOriginGlobalY + h * 0.5,
      h
    )
  }

  private shortcutIconBoxAreaChange(index: number, area: Area): void {
    if (this.isShortcutDragging() || this.dropSettling) {
      return
    }
    const globalPos = area.globalPosition
    const w = area.width as number
    const h = area.height as number
    if (!globalPos || w <= 0 || h <= 0) {
      return
    }
    this.updateIconLayout(
      index,
      (globalPos.x as number) - this.gridOriginGlobalX,
      (globalPos.y as number) - this.gridOriginGlobalY,
      w,
      h
    )
  }

  private visibleSearchHistory(): string[] {
    if (this.isIncognito) {
      return []
    }
    return this.searchHistory
  }

  private searchSuggestions(): SearchSuggestion[] {
    if (!this.searchText.trim()) {
      return []
    }
    return SearchSuggest.build(
      this.searchText,
      this.visibleSearchHistory(),
      this.historyList,
      this.bookmarks,
      8
    )
  }

  private performSearch(keyword?: string): void {
    const query = BrowserNavigation.normalizeNavigateInput(keyword ?? this.searchText)
    if (!query) {
      return
    }
    BrowserNavigation.searchOrNavigate(query, { preferHomeTab: true })
    this.closeSearchMode()
  }

  /** 首页搜索/地址栏输入：超长自动截断并提示 */
  private applySearchTextChange(value: string): void {
    BrowserNavigation.applyTextInputChange(value, this.searchText.length, (text: string) => {
      this.searchText = text
    }, true)
  }

  /** 快捷方式点击入口：防抖、清理脏状态后分发到 onShortcutClick */
  private handleShortcutTap(feature: ShortcutFeature): void {
    const now = Date.now()
    if (this.lastShortcutTapId === feature.id && now - this.lastShortcutTapMs < 200) {
      return
    }
    this.lastShortcutTapMs = now
    this.lastShortcutTapId = feature.id
    BrowserLog.info(`[ShortcutTap] touch id=${feature.id}`)
    if (this.dropSettling) {
      return
    }
    // 残留拖动 id 但未抬起时视为脏状态，避免永久拦截点击
    if (this.draggingId.length > 0 && !this.dragLiftVisible && !this.showShortcutContextMenu) {
      this.resetShortcutInteractionStateIfNeeded()
    }
    if (this.isShortcutDragging() || this.dropSettling) {
      return
    }
    if (this.suppressShortcutClick) {
      this.suppressShortcutClick = false
      return
    }
    if (this.showShortcutContextMenu) {
      this.dismissShortcutContextMenuAndLift()
      return
    }
    this.onShortcutClick(feature)
  }

  /** 快捷方式业务跳转：站点 URL 或功能面板 */
  private onShortcutClick(feature: ShortcutFeature): void {
    BrowserLog.info(`[ShortcutTap] open id=${feature.id} kind=${feature.kind}`)
    if (feature.kind === 'site') {
      const url = feature.url ?? ''
      if (url.length > 0) {
        void BrowserStore.whenReady().then(() => {
          BrowserNavigation.openBrowse(url, { preferHomeTab: true })
        })
      }
      return
    }
    switch (feature.id) {
      case 'bookmarks':
        BrowserStore.openFeaturePanel('bookmarks')
        break
      case 'history':
        BrowserStore.openFeaturePanel('history')
        break
      case 'downloads':
        BrowserStore.openFeaturePanel('downloads')
        break
      case 'toolbox':
        BrowserStore.openFeaturePanel('toolbox')
        break
      default:
        BrowserLog.info(`[ShortcutTap] unknown feature id=${feature.id}`)
        break
    }
  }

  aboutToAppear(): void {
    this.homeWideWindow = this.resolveWideWindow(this.windowWidth, this.windowHeight)
    AppStorage.setOrCreate(AppStorageKeys.SHORTCUT_MENU_ACTION, '')
    this.forceResetShortcutInteractionState('aboutToAppear')
    void BrowserStore.whenReady().then(() => {
      void BrowserStore.refreshTabList()
    })
  }

  aboutToDisappear(): void {
    this.clearSearchFocusTimer()
    this.clearSuppressClickTimer()
    this.forceResetShortcutInteractionState('aboutToDisappear')
    this.dismissSearchKeyboard()
  }

  /** 无条件清理拖动/菜单残留，避免拦截点击 */
  private forceResetShortcutInteractionState(source: string): void {
    this.clearDropSettleTimers()
    this.clearHoverDwellTimer()
    this.clearContextMenuTimer()
    this.clearShortcutPressTimer()
    this.clearSearchFocusTimer()
    this.clearSuppressClickTimer()
    this.activeShortcutTouchId = ''
    this.activeShortcutTouchIndex = -1
    this.shortcutLongPressStarted = false
    this.showShortcutContextMenu = false
    this.contextMenuFeatureId = ''
    this.contextMenuIndex = -1
    this.contextMenuGridPanActive = false
    this.dragLiftOverlayPanActive = false
    this.dragFromIndex = -1
    this.dragHoverIndex = -1
    this.dragSqueezeIndex = -1
    this.lastSqueezeTargetIndex = -1
    this.draggingId = ''
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.dragLiftVisible = false
    this.dropSettling = false
    this.dropSettleDraggedId = ''
    this.suppressShortcutClick = false
    this.dropSettleById = {}
    this.clearShortcutOverlayState()
    BrowserLog.info(`[ShortcutTap] force reset source=${source}`)
  }

  /** 竖屏：搜索栏居中，快捷方式网格在其下方 */
  @Builder
  HomePortraitBody() {
    Column() {
      Blank().height('50%').hitTestBehavior(HitTestMode.None)
      Column() {
        this.SearchRow()
      }
      .width('100%')
      .height(HomeView.SEARCH_ROW_HEIGHT)
      .margin({ top: -HomeView.SEARCH_ROW_HEIGHT / 2 })
      .zIndex(HomeView.SEARCH_ROW_Z_INDEX)
      .onAreaChange((_old, area) => {
        this.onSearchBarAreaChange(area)
      })

      Column() {
        this.ShortcutGrid()
      }
      .width('100%')
      .height(this.shortcutGridOuterHeight())
      .alignItems(HorizontalAlign.Start)
      .zIndex(HomeView.SHORTCUT_GRID_Z_INDEX)
      .onAreaChange((_old, area) => {
        this.onShortcutWrapperAreaChange(area)
      })

      Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeAreaTop })
  }

  /** 横屏：搜索栏置顶，快捷方式网格按剩余高度重算行数 */
  @Builder
  HomeLandscapeBody() {
    Column() {
      Column() {
        this.SearchRow()
      }
      .width('100%')
      .height(HomeView.SEARCH_ROW_HEIGHT)
      .padding({ top: HomeView.LANDSCAPE_SEARCH_TOP_PADDING })
      .zIndex(HomeView.SEARCH_ROW_Z_INDEX)
      .onAreaChange((_old, area) => {
        this.onSearchBarAreaChange(area)
      })

      Column() {
        this.ShortcutGrid()
      }
      .width('100%')
      .height(this.shortcutGridOuterHeight())
      .alignItems(HorizontalAlign.Start)
      .zIndex(HomeView.SHORTCUT_GRID_Z_INDEX)
      .onAreaChange((_old, area) => {
        this.onShortcutWrapperAreaChange(area)
      })

      Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: this.safeAreaTop })
  }

  /** 拖动跟手浮层（HomeView 内渲染，不占用 MainPage 全屏命中层） */
  @Builder
  ShortcutDragLiftOverlay() {
    if (this.isShortcutLiftActive() && !this.showShortcutContextMenu && ShortcutManager.resolveDisplayEntry(this.draggingId)) {
      this.DragLiftIcon(ShortcutManager.resolveDisplayEntry(this.draggingId)!)
    }
  }

  @Builder
  DragLiftIcon(feature: ShortcutFeature) {
    Column() {
      if (feature.kind === 'feature') {
        ShortcutTileIcon({ tile: feature.tile ?? 'bookmark', iconSize: 28 })
      } else {
        ShortcutEngineIcon({ text: feature.iconText ?? '', iconMedia: feature.iconMedia ?? '', iconSize: 36 })
      }
    }
    .width(HomeView.SHORTCUT_ICON_BOX)
    .height(HomeView.SHORTCUT_ICON_BOX)
    .backgroundColor(BrowserTheme.shortcutIconBg(this.isDarkMode()))
    .borderRadius(14)
    .border({ width: 1, color: BrowserTheme.shortcutIconBorder(this.isDarkMode()) })
    .shadow({
      radius: 18,
      color: 'rgba(37, 99, 235, 0.35)',
      offsetX: 0,
      offsetY: 10
    })
    .justifyContent(FlexAlign.Center)
    .scale({ x: 1.12, y: 1.12 })
    .position({
      x: this.resolveIconRect(this.dragFromIndex).left + this.dragOffsetX,
      y: this.shortcutGridOverlayTopOffset() + this.resolveIconRect(this.dragFromIndex).top + this.dragOffsetY
    })
    .zIndex(15)
    .hitTestBehavior(HitTestMode.None)
  }

  /** 首页背景：淡蓝渐变 + bg.svg；以原图交错线为水面，下方作倒影处理 */
  @Builder
  HomePageBackground() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: BrowserTheme.homeGradientColors(this.isDarkMode())
        })

      if (this.shouldShowHomeBgDecor() && this.homeBgImageHeight() > 0) {
        // 在搜索框上边缘硬截断；底边短柔边溶入统一水色，避免左右硬边发灰
        Stack({ alignContent: Alignment.TopStart }) {
          this.HomeBgWaterMirror()

          Column()
            .width('100%')
            .height(HomeView.HOME_BG_CLIP_EDGE_FADE)
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: BrowserTheme.homeBgClipEdgeFadeColors(this.isDarkMode())
            })
            .position({
              x: 0,
              y: Math.max(0, this.estimatedSearchBarTop() - HomeView.HOME_BG_CLIP_EDGE_FADE)
            })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(this.estimatedSearchBarTop())
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /**
   * 水面倒影合成（不改 bg.svg）：
   * - 水面以上完整；微微放大；倒影伸入部分由外层在搜索框顶硬截断
   * - 倒影区水色渐变 + 模糊；深色在倒影区内左右渐隐到透明（不外扩）
   */
  @Builder
  HomeBgWaterMirror() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image($r('app.media.bg'))
        .width(this.homeBgImageWidth())
        .height(this.homeBgImageHeight())
        .objectFit(ImageFit.Fill)
        .opacity(this.isDarkMode() ? 0.42 : 1)
        .hitTestBehavior(HitTestMode.None)

      if (this.homeBgReflectionHeight() > 1) {
        // 倒影本体：轻水色罩，保留白色倒影透出
        Column()
          .width('100%')
          .height(this.homeBgReflectionHeight())
          .backgroundColor(this.isDarkMode() ?
            'rgba(26, 39, 68, 0.10)' : 'rgba(232, 242, 255, 0.06)')
          .backdropBlur(HomeView.HOME_BG_REFLECTION_BLUR)
          .position({ x: 0, y: this.homeBgHorizonHeight() })
          .hitTestBehavior(HitTestMode.None)

        // 水色渐变：近水面清透，向下溶入页底
        Column()
          .width('100%')
          .height(this.homeBgReflectionHeight())
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: BrowserTheme.homeBgReflectionColors(this.isDarkMode())
          })
          .position({ x: 0, y: this.homeBgHorizonHeight() })
          .hitTestBehavior(HitTestMode.None)

        // 近水面高光带
        Column()
          .width('100%')
          .height(Math.max(12, this.homeBgReflectionHeight() * 0.22))
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: BrowserTheme.homeBgReflectionSheenColors(this.isDarkMode())
          })
          .position({ x: 0, y: this.homeBgHorizonHeight() })
          .hitTestBehavior(HitTestMode.None)

        // 倒影下部加深
        Column()
          .width('100%')
          .height(this.homeBgReflectionHeight() * 0.55)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: BrowserTheme.homeBgReflectionDepthColors(this.isDarkMode())
          })
          .position({
            x: 0,
            y: this.homeBgHorizonHeight() + this.homeBgReflectionHeight() * 0.45
          })
          .hitTestBehavior(HitTestMode.None)

        // 深色：倒影区内左右 + 上下渐隐，加强硬白边溶合（不外扩）
        if (this.isDarkMode()) {
          Column()
            .width('100%')
            .height(this.homeBgReflectionHeight())
            .linearGradient({
              direction: GradientDirection.Right,
              colors: BrowserTheme.homeBgReflectionInAreaFadeColors()
            })
            .position({ x: 0, y: this.homeBgHorizonHeight() })
            .hitTestBehavior(HitTestMode.None)

          Column()
            .width('100%')
            .height(this.homeBgReflectionHeight())
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: BrowserTheme.homeBgReflectionInAreaVerticalFadeColors()
            })
            .position({ x: 0, y: this.homeBgHorizonHeight() })
            .hitTestBehavior(HitTestMode.None)
        }
      }

      // 水面柔光细线（左右淡出）
      Row() {
        Blank()
        Column()
          .width('68%')
          .height(2)
          .linearGradient({
            direction: GradientDirection.Right,
            colors: BrowserTheme.homeBgHorizonLineColors(this.isDarkMode())
          })
        Blank()
      }
      .width('100%')
      .position({ x: 0, y: this.homeBgHorizonHeight() - 1 })
      .opacity(this.isDarkMode() ? 0.32 : 0.9)
      .hitTestBehavior(HitTestMode.None)
    }
    .width(this.homeBgImageWidth())
    .height(this.homeBgImageHeight())
    .position({ x: this.homeBgImageLeft(), y: this.homeBgImageTop() })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.HomePageBackground()

      Column() {
        if (this.isLandscapeLayout()) {
          this.HomeLandscapeBody()
        } else {
          this.HomePortraitBody()
        }
      }
      .width('100%')
      .height('100%')
      .key(`home-body-${this.homeLayoutRev}-${this.windowRev}-${this.isLandscapeLayout()}-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}`)

      if (this.isSearchMode) {
        this.SearchOverlay()
      }

      if (this.showClearConfirm) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.clear_search_history_confirm')),
          confirmLabel: BrowserStrings.txt($r('app.string.confirm')),
          cancelLabel: BrowserStrings.txt($r('app.string.cancel')),
          onCancel: () => {
            this.showClearConfirm = false
          },
          onConfirm: () => {
            BrowserStore.clearSearchHistory()
            this.showClearConfirm = false
          }
        })
      }

      if (this.showShortcutEditDialog) {
        this.ShortcutEditDialog()
      }
    }
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        BrowserLog.info('[HomeView] root touch down')
      }
    })
    .onAreaChange((_old, area) => {
      const globalPos = area.globalPosition
      if (globalPos) {
        this.homeViewGlobalY = globalPos.y as number
      }
      this.onHomeViewportSizeChange(area.width as number, area.height as number)
    })
  }

  @Builder
  SearchRow() {
    Row({ space: 8 }) {
      Row({ space: 10 }) {
        SearchLeadingIcon({
          color: this.isDarkMode() ? '#8a8a8a' : '#9aa0a6',
          iconSize: 18
        })

        Text($r('app.string.search_placeholder'))
          .fontSize(this.uiFp(14))
          .fontColor(this.isDarkMode() ? '#666666' : '#b0b5bb')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Column() {
          ScanQrIcon({
            color: this.isDarkMode() ? '#8a8a8a' : '#9aa0a6',
            iconSize: 20
          })
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          BrowserStore.scanQrCode()
        })
      }
      .layoutWeight(1)
      .height(HomeView.SEARCH_ROW_HEIGHT)
      .backgroundColor(this.isDarkMode() ? 'rgba(20, 20, 20, 0.92)' : '#ffffff')
      .borderRadius(999)
      .border({
        width: 1,
        color: this.isDarkMode() ? 'rgba(255, 255, 255, 0.16)' : 'rgba(0, 0, 0, 0.14)'
      })
      .padding({ left: 14, right: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.openSearchMode())

      Column() {
        TabCountBadge({
          boxSize: HomeView.SEARCH_TAB_BADGE_SIZE,
          fontSize: HomeView.SEARCH_TAB_BADGE_FONT
        })
      }
      .width(HomeView.SEARCH_TAB_ENTRY_SIZE)
      .height(HomeView.SEARCH_TAB_ENTRY_SIZE)
      .flexShrink(0)
      .backgroundColor(this.isDarkMode() ? 'rgba(20, 20, 20, 0.72)' : '#ffffff')
      .borderRadius(11)
      .justifyContent(FlexAlign.Center)
      .onClick(() => BrowserStore.openTabsWithHomeThumbnail(this.getUIContext()))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ShortcutGrid() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.gridSlotIds(), (slotId: string, localIndex: number) => {
            Column() {
              if (slotId === HomeView.ADD_SHORTCUT_SLOT_ID) {
                this.AddShortcutItem()
              } else if (ShortcutManager.resolveDisplayEntry(slotId)) {
                this.ShortcutItem(ShortcutManager.resolveDisplayEntry(slotId)!, localIndex)
              } else {
                this.UnresolvedShortcutItem()
              }
            }
            .width(`${100 / HomeView.SHORTCUT_COLS}%`)
            .height(this.shortcutCellHeight)
            .margin({ bottom: this.shortcutItemBottomGap(localIndex) })
            .onClick(() => {
              if (slotId === HomeView.ADD_SHORTCUT_SLOT_ID) {
                return
              }
              const feature = ShortcutManager.resolveDisplayEntry(slotId)
              if (feature && !this.isShortcutDragging() && !this.dropSettling) {
                this.handleShortcutTap(feature)
              }
            })
            .onTouch((event: TouchEvent) => {
              if (slotId === HomeView.ADD_SHORTCUT_SLOT_ID) {
                return
              }
              if (this.shortcutIds.indexOf(slotId) < 0) {
                return
              }
              const feature = ShortcutManager.resolveDisplayEntry(slotId)
              if (feature) {
                this.onShortcutItemTouch(feature, localIndex, event)
              }
            })
          }, (slotId: string, localIndex: number) => {
            return `${slotId}_${localIndex}_${this.shortcutIds.length}_${this.shortcutGridRowsCount()}`
          })
        }
        .key(this.shortcutGridRenderKey())
        .width('100%')
        .height(this.shortcutGridRowsHeight())
        .padding({
          left: HomeView.SHORTCUT_GRID_PADDING_LEFT,
          right: HomeView.SHORTCUT_GRID_PADDING_RIGHT
        })
        .clip(this.shouldClipShortcutGrid())
        .zIndex(10)
        .onAreaChange((_old, area) => {
          const globalPos = area.globalPosition
          if (globalPos) {
            this.gridOriginGlobalX = globalPos.x as number
            this.gridOriginGlobalY = globalPos.y as number
          }
          const w = area.width as number
          if (w > 0 && Math.abs(w - this.shortcutGridWidth) > 1) {
            this.shortcutGridWidth = w
          }
          this.syncShortcutGridMetrics()
        })
      }
      .width('100%')
      .padding({ top: HomeView.SHORTCUT_GRID_PADDING_TOP })

      if (this.shouldShowDropPlaceholderOverlay()) {
        this.DropPlaceholderOverlay()
      }

      this.ShortcutDragLiftOverlay()
    }
    .width('100%')
    .height(this.shortcutGridContentHeight())
    .clip(false)
  }

  @Builder
  DropPlaceholderOverlay() {
    Column() {
      this.DragDropPlaceholder(this.placeholderRect.width, this.placeholderRect.height)
    }
    .position({
      x: this.placeholderRect.left,
      y: this.shortcutGridOverlayTopOffset() + this.placeholderRect.top
    })
    .animation({
      duration: this.placeholderAnimationDuration(),
      curve: Curve.EaseInOut
    })
    .zIndex(12)
  }

  @Builder
  DragDropPlaceholder(iconWidth: number, iconHeight: number) {
    Column()
      .width(iconWidth)
      .height(iconHeight)
      .borderRadius(14)
      .border({
        width: 1.5,
        color: this.isDarkMode() ? 'rgba(26, 122, 245, 0.55)' : 'rgba(26, 122, 245, 0.45)',
        style: BorderStyle.Dashed
      })
      .backgroundColor(this.isDarkMode() ? 'rgba(26, 122, 245, 0.08)' : 'rgba(230, 245, 255, 0.35)')
  }

  @Builder
  ShortcutItem(feature: ShortcutFeature, index: number) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          Column({ space: 7 }) {
            Stack({ alignContent: Alignment.TopEnd }) {
              if (feature.kind === 'feature') {
                Column() {
                  ShortcutTileIcon({ tile: feature.tile ?? 'bookmark', iconSize: 28 })
                }
                .width(HomeView.SHORTCUT_ICON_BOX)
                .height(HomeView.SHORTCUT_ICON_BOX)
                .backgroundColor(BrowserTheme.shortcutIconBg(this.isDarkMode()))
                .borderRadius(14)
                .border({ width: 1, color: BrowserTheme.shortcutIconBorder(this.isDarkMode()) })
                .shadow({
                  radius: 8,
                  color: 'rgba(37, 99, 235, 0.12)',
                  offsetX: 0,
                  offsetY: 2
                })
                .justifyContent(FlexAlign.Center)
                .onAreaChange((_old, area) => {
                  this.shortcutIconBoxAreaChange(index, area)
                })
              } else {
                Column() {
                  ShortcutEngineIcon({ text: feature.iconText ?? '', iconMedia: feature.iconMedia ?? '', iconSize: 36 })
                }
                .width(HomeView.SHORTCUT_ICON_BOX)
                .height(HomeView.SHORTCUT_ICON_BOX)
                .backgroundColor(BrowserTheme.shortcutIconBg(this.isDarkMode()))
                .borderRadius(14)
                .border({ width: 1, color: BrowserTheme.shortcutIconBorder(this.isDarkMode()) })
                .shadow({
                  radius: 2,
                  color: 'rgba(17, 24, 39, 0.04)',
                  offsetX: 0,
                  offsetY: 1
                })
                .justifyContent(FlexAlign.Center)
                .onAreaChange((_old, area) => {
                  this.shortcutIconBoxAreaChange(index, area)
                })
              }
            }

            Text(feature.title)
              .fontSize(this.uiFp(11))
              .fontColor(this.isDarkMode() ? '#a8a8a8' : '#6b7280')
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .lineHeight(14)
              .visibility(this.shouldHideShortcutItemTitle(index, feature.id) ?
                Visibility.None : Visibility.Visible)
          }
          .alignItems(HorizontalAlign.Center)
        }
        .translate(this.itemContentTranslate(index, feature.id))
        .scale({ x: this.itemContentScale(feature.id), y: this.itemContentScale(feature.id) })
        .animation({
          duration: this.itemContentAnimationDuration(index, feature.id),
          curve: Curve.EaseInOut
        })
        .opacity(this.isDraggedCell(index, feature.id) ? 0 : 1)
      }
    }
    .width('100%')
    .height(this.shortcutCellHeight)
    .zIndex(this.isShortcutDragging() ? 1 : 0)
    .borderRadius(12)
    .padding(4)
    .onAreaChange((_old, area) => {
      this.shortcutIconAreaChange(index, area)
    })
  }

  @Builder
  AddShortcutItem() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 7 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(this.uiFp(22))
              .fontWeight(FontWeight.Medium)
              .fontColor(['#1a7af5'])
          }
          .width(HomeView.SHORTCUT_ICON_BOX)
          .height(HomeView.SHORTCUT_ICON_BOX)
          .backgroundColor(this.isDarkMode() ? 'rgba(20, 20, 20, 0.92)' : 'rgba(230, 245, 255, 0.95)')
          .borderRadius(14)
          .border({
            width: 1,
            color: this.isDarkMode() ? 'rgba(26, 122, 245, 0.55)' : 'rgba(26, 122, 245, 0.45)',
            style: BorderStyle.Dashed
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Text($r('app.string.add_shortcut'))
            .fontSize(this.uiFp(11))
            .fontColor(this.isDarkMode() ? '#a8a8a8' : BrowserTheme.TEXT_SECONDARY)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .lineHeight(14)
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height(this.shortcutCellHeight)
    .padding(HomeView.SHORTCUT_ITEM_PADDING)
    .onClick(() => {
      if (this.isShortcutAtLimit()) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.shortcut_limit_reached')))
        return
      }
      this.showAddSheet = true
    })
  }

  @Builder
  UnresolvedShortcutItem() {
    Column({ space: 7 }) {
      Column() {
        Text('?')
          .fontSize(this.uiFp(20))
          .fontColor(this.isDarkMode() ? '#9ca3af' : '#6b7280')
      }
      .width(HomeView.SHORTCUT_ICON_BOX)
      .height(HomeView.SHORTCUT_ICON_BOX)
      .backgroundColor(this.isDarkMode() ? 'rgba(20, 20, 20, 0.92)' : 'rgba(243, 244, 246, 0.95)')
      .borderRadius(14)
      .border({
        width: 1,
        color: this.isDarkMode() ? 'rgba(255,255,255,0.18)' : 'rgba(0, 0, 0, 0.12)',
        style: BorderStyle.Dashed
      })
      .justifyContent(FlexAlign.Center)

      Text('快捷方式')
        .fontSize(this.uiFp(11))
        .fontColor(this.isDarkMode() ? '#a8a8a8' : BrowserTheme.TEXT_SECONDARY)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SearchOverlay() {
    Column() {
      Row({ space: 10 }) {
        PanelCircleIconButton({
          iconKind: 'back',
          darkMode: this.isDarkMode(),
          onTap: () => this.closeSearchMode()
        })

        Row({ space: 10 }) {
          SearchLeadingIcon({
            color: this.isDarkMode() ? '#8a8a8a' : '#9aa0a6',
            iconSize: 18
          })
          Column() {
            TextInput({
              text: this.searchText,
              placeholder: $r('app.string.search_placeholder'),
              controller: this.searchInputController
            })
              .id('home_search_input')
              .fontSize(this.uiFp(14))
              .fontColor(this.isDarkMode() ? '#f2f2f2' : '#111827')
              .placeholderColor(this.isDarkMode() ? '#666666' : '#b0b5bb')
              .backgroundColor(Color.Transparent)
              .width('100%')
              .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
              .defaultFocus(true)
              .enableKeyboardOnFocus(true)
              .onChange((value: string) => {
                this.applySearchTextChange(value)
              })
              .onSubmit(() => this.performSearch())
          }
          .layoutWeight(1)
          .onClick(() => {
            // 阻止冒泡，避免点击输入框时误触空白收起键盘
          })

          Column() {
            UrlNavigateConfirmBtn({
              color: this.isDarkMode() ? '#8ab4f8' : '#1a73e8',
              fontSize: this.uiFp(18)
            })
          }
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.performSearch())
        }
        .layoutWeight(1)
        .height(HomeView.SEARCH_ROW_HEIGHT)
        .backgroundColor(this.isDarkMode() ? 'rgba(20, 20, 20, 0.92)' : '#ffffff')
        .borderRadius(999)
        .border({
          width: 1,
          color: this.isDarkMode() ? 'rgba(255, 255, 255, 0.16)' : 'rgba(0, 0, 0, 0.14)'
        })
        .padding({ left: 14, right: 14 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 + this.safeAreaTop, bottom: 14 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          if (this.searchSuggestions().length > 0) {
            Column() {
              Text($r('app.string.search_suggestions'))
                .fontSize(this.uiFp(16))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode() ? '#f2f2f2' : '#111827')
                .width('100%')
                .padding({ bottom: 12 })

              ForEach(this.searchSuggestions(), (item: SearchSuggestion) => {
                Row({ space: 8 }) {
                  if (item.kind === 'url') {
                    Text('🔗')
                      .fontSize(this.uiFp(14))
                  } else {
                    SymbolGlyph($r('sys.symbol.magnifyingglass'))
                      .fontSize(this.uiFp(14))
                      .fontColor([this.isDarkMode() ? '#a8a8a8' : '#6b7280'])
                  }
                  Text(item.text)
                    .fontSize(this.uiFp(15))
                    .fontColor(this.isDarkMode() ? '#f2f2f2' : '#111827')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  this.searchText = item.text
                  this.performSearch(item.text)
                })
              }, (item: SearchSuggestion) => `${item.kind}_${item.text}`)
            }
            .width('100%')
            .backgroundColor(this.isDarkMode() ? '#1c1c1c' : '#ffffff')
            .borderRadius(18)
            .padding({ left: 16, right: 16, top: 16, bottom: 12 })
            .margin({ bottom: 12 })
          }

          Column() {
            Row() {
              Text($r('app.string.search_history'))
                .fontSize(this.uiFp(16))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode() ? '#f2f2f2' : '#111827')

              Blank()

              Column() {
                TrashClearIcon({ color: this.isDarkMode() ? '#9ca3af' : '#6b7280' })
              }
              .padding(4)
              .onClick(() => {
                this.showClearConfirm = true
              })
            }
            .width('100%')
            .padding({ bottom: 14 })

            if (this.visibleSearchHistory().length === 0) {
              Text($r('app.string.search_history_empty'))
                .fontSize(this.uiFp(14))
                .fontColor('#9ca3af')
                .width('100%')
            } else {
              Grid() {
                ForEach(this.visibleSearchHistory(), (item: string) => {
                  GridItem() {
                    Text(item)
                      .fontSize(this.uiFp(15))
                      .fontColor(this.isDarkMode() ? '#f2f2f2' : '#111827')
                      .lineHeight(21)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .onClick(() => {
                        this.searchText = item
                        this.performSearch(item)
                      })
                  }
                }, (item: string) => item)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(12)
              .rowsGap(14)
              .width('100%')
            }
          }
          .width('100%')
          .backgroundColor(this.isDarkMode() ? '#1c1c1c' : '#ffffff')
          .borderRadius(18)
          .padding({ left: 16, right: 16, top: 16, bottom: 18 })
          .shadow({
            radius: 3,
            color: this.isDarkMode() ? 'rgba(0,0,0,0)' : 'rgba(0, 0, 0, 0.04)',
            offsetX: 0,
            offsetY: 1
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
        .onClick(() => {
          this.dismissSearchKeyboard()
        })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .onClick(() => {
        this.dismissSearchKeyboard()
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(HomeView.SEARCH_ROW_Z_INDEX + 5)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: BrowserTheme.homeGradientColors(this.isDarkMode())
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  ShortcutEditDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())
        .onClick(() => {
          this.showShortcutEditDialog = false
          this.editShortcutId = ''
        })

      Column({ space: 12 }) {
        Text($r('app.string.edit'))
          .fontSize(this.uiFp(17))
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 4 })

        TextInput({ placeholder: BrowserStrings.txt($r('app.string.custom_shortcut_name_hint')), text: this.editShortcutName })
          .fontSize(this.uiFp(15))
          .height(44)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
          .onChange((v: string) => {
            BrowserNavigation.applyTextInputChange(v, this.editShortcutName.length, (text: string) => {
              this.editShortcutName = text
            })
          })

        if (!this.isShortcutTitleOnly(this.editShortcutId)) {
          TextInput({ placeholder: BrowserStrings.txt($r('app.string.custom_shortcut_url_hint')), text: this.editShortcutUrl })
            .fontSize(this.uiFp(15))
            .height(44)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
            .onChange((v: string) => {
              BrowserNavigation.applyTextInputChange(v, this.editShortcutUrl.length, (text: string) => {
                this.editShortcutUrl = text
              }, true)
            })
        }

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .width('100%')
          .margin({ top: 4, left: 16, right: 16 })

        Row() {
          Text($r('app.string.cancel'))
            .fontSize(this.uiFp(16))
            .fontColor(HarmonyDialogStyle.textPrimary())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
            .onClick(() => {
              this.showShortcutEditDialog = false
              this.editShortcutId = ''
            })

          Text($r('app.string.confirm'))
            .fontSize(this.uiFp(16))
            .fontColor(HarmonyDialogStyle.emphasize())
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
            .onClick(() => {
              this.saveShortcutEdit()
            })
        }
        .width('100%')
      }
      .width(HarmonyDialogStyle.CARD_WIDTH)
      .constraintSize({ maxWidth: HarmonyDialogStyle.CARD_MAX_WIDTH })
      .padding({ left: 16, right: 16, top: 4 })
      .backgroundColor(HarmonyDialogStyle.cardBg())
      .borderRadius(HarmonyDialogStyle.CARD_RADIUS)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(4700)
  }
}
