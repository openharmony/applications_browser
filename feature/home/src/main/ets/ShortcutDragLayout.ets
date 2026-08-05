/** 快捷方式网格挤位：线性数组重排 + 分行坐标映射 */

export interface GridPoint {
  row: number
  col: number
}

export interface GridTranslate {
  x: number
  y: number
}

/** 跨行挤位 L 形路径：先同行水平，再纵向换行 */
export interface GridSqueezePath {
  outer: GridTranslate
  inner: GridTranslate
  crossRow: boolean
}

/** Grid 布局度量（槽位几何，不依赖数组下标） */
export interface GridLayoutMetrics {
  cols: number
  colStep: number
  rowStep: number
  colGap: number
  paddingLeft: number
  paddingTop: number
  cellContentHeight: number
}

const EMPTY_TRANSLATE: GridTranslate = { x: 0, y: 0 }

const EMPTY_PATH: GridSqueezePath = {
  outer: EMPTY_TRANSLATE,
  inner: EMPTY_TRANSLATE,
  crossRow: false
}

/** 下标 → 网格行列 */
export function indexToGridPoint(index: number, cols: number): GridPoint {
  return {
    row: Math.floor(index / cols),
    col: index % cols
  }
}

/** 指定行列的槽位中心 X（几何坐标，可用于 pivot） */
export function gridPointCenterX(col: number, metrics: GridLayoutMetrics): number {
  const cellWidth = metrics.colStep - metrics.colGap
  return metrics.paddingLeft + col * metrics.colStep + cellWidth * 0.5
}

/** 指定行的槽位中心 Y（整格几何，仅作兜底） */
export function gridPointCenterY(row: number, metrics: GridLayoutMetrics): number {
  return metrics.paddingTop + row * metrics.rowStep + metrics.cellContentHeight * 0.5
}

/** 快捷方式内容区中心 Y（图标+标题，与 ShortcutItem 实测一致） */
export function gridSlotContentCenterY(row: number, metrics: GridLayoutMetrics): number {
  const itemPadding = 4
  const contentHalf = 36.5
  return metrics.paddingTop + row * metrics.rowStep + itemPadding + contentHalf
}

/** 格子下标对应槽位中心 Y */
export function slotCenterY(index: number, metrics: GridLayoutMetrics, measured: number[] = []): number {
  if (measured[index] !== undefined && !Number.isNaN(measured[index])) {
    return measured[index]
  }
  const cols = metrics.cols
  const col = index % cols
  const row = Math.floor(index / cols)
  if (col < measured.length && !Number.isNaN(measured[col])) {
    return measured[col] + row * metrics.rowStep
  }
  return gridSlotContentCenterY(row, metrics)
}

/** 格子下标对应槽位中心 X */
export function slotCenterX(index: number, metrics: GridLayoutMetrics, measured: number[] = []): number {
  if (measured[index] !== undefined && !Number.isNaN(measured[index])) {
    return measured[index]
  }
  const col = index % metrics.cols
  if (!Number.isNaN(measured[0])) {
    return measured[0] + col * metrics.colStep
  }
  return gridPointCenterX(col, metrics)
}

/** 线性数组重排：从 from 拔出插入 to（与 ShortcutManager.reorder 一致） */
export function reorderArrayIds(ids: string[], from: number, to: number): string[] {
  if (from < 0 || to < 0 || from >= ids.length || to >= ids.length || from === to) {
    return [...ids]
  }
  const next = [...ids]
  const item = next.splice(from, 1)[0]
  next.splice(to, 0, item)
  return next
}

/** 重排后 id 在数组中的下标 */
export function previewIndexOfId(id: string, previewIds: string[]): number {
  return previewIds.indexOf(id)
}

/** 跨行挤位：outer 为格心之间的斜线位移（inner 为空，单层动画） */
export function gridSqueezePath(
  fromIndex: number,
  toIndex: number,
  metrics: GridLayoutMetrics
): GridSqueezePath {
  if (fromIndex === toIndex) {
    return EMPTY_PATH
  }
  const from = indexToGridPoint(fromIndex, metrics.cols)
  const to = indexToGridPoint(toIndex, metrics.cols)
  const colDelta = to.col - from.col
  const rowDelta = to.row - from.row
  if (rowDelta !== 0) {
    return {
      outer: { x: colDelta * metrics.colStep, y: rowDelta * metrics.rowStep },
      inner: EMPTY_TRANSLATE,
      crossRow: true
    }
  }
  return {
    outer: { x: colDelta * metrics.colStep, y: 0 },
    inner: EMPTY_TRANSLATE,
    crossRow: false
  }
}

/**
 * 挤位位移：优先用实测格心坐标差，与 Grid 真实布局一致。
 */
export function gridSqueezePathWithMeasure(
  fromIndex: number,
  toIndex: number,
  metrics: GridLayoutMetrics,
  measuredX: number[] = [],
  measuredY: number[] = []
): GridSqueezePath {
  if (fromIndex === toIndex) {
    return EMPTY_PATH
  }
  const cx0 = slotCenterX(fromIndex, metrics, measuredX)
  const cy0 = slotCenterY(fromIndex, metrics, measuredY)
  const cx1 = slotCenterX(toIndex, metrics, measuredX)
  const cy1 = slotCenterY(toIndex, metrics, measuredY)
  const row0 = Math.floor(fromIndex / metrics.cols)
  const row1 = Math.floor(toIndex / metrics.cols)
  if (row0 === row1) {
    // 同行仅水平位移，Y 实测有 ±2vp 噪声会导致松手跳动
    return {
      outer: { x: cx1 - cx0, y: 0 },
      inner: EMPTY_TRANSLATE,
      crossRow: false
    }
  }
  // 跨行：格心斜线位移（优先 slotCenter 推算，保证起终点准确）
  return {
    outer: { x: cx1 - cx0, y: cy1 - cy0 },
    inner: EMPTY_TRANSLATE,
    crossRow: true
  }
}

/** 根据预览数组计算某固定格子 index 的挤位路径（ForEach 下标不变，仅 translate） */
export function squeezePathForCell(
  cellIndex: number,
  dragFrom: number,
  dragHover: number,
  ids: string[],
  metrics: GridLayoutMetrics,
  measuredX: number[] = [],
  measuredY: number[] = []
): GridSqueezePath {
  if (dragFrom < 0 || dragHover < 0 || dragFrom === dragHover) {
    return EMPTY_PATH
  }
  if (cellIndex === dragFrom) {
    return EMPTY_PATH
  }
  const previewIds = reorderArrayIds(ids, dragFrom, dragHover)
  const id = ids[cellIndex]
  const targetIndex = previewIndexOfId(id, previewIds)
  if (targetIndex < 0 || targetIndex === cellIndex) {
    return EMPTY_PATH
  }
  return gridSqueezePathWithMeasure(cellIndex, targetIndex, metrics, measuredX, measuredY)
}

/** 手指位置最近的槽位下标（行间切换以两排中心连线中点为界，避免第二行平移误判为第一行） */
function nearestSlotIndex(
  fingerX: number,
  fingerY: number,
  count: number,
  metrics: GridLayoutMetrics,
  measuredX: number[],
  measuredY: number[]
): number {
  let bestIdx = 0
  let bestDist = Number.MAX_VALUE
  for (let i = 0; i < count; i++) {
    const cx = slotCenterX(i, metrics, measuredX)
    const cy = slotCenterY(i, metrics, measuredY)
    const dx = fingerX - cx
    const dy = fingerY - cy
    const dist = dx * dx + dy * dy
    if (dist < bestDist) {
      bestDist = dist
      bestIdx = i
    }
  }
  return bestIdx
}

/** 由手指偏移估算悬停插入下标 */
export function computeHoverIndex(
  fromIndex: number,
  offsetX: number,
  offsetY: number,
  count: number,
  cols: number,
  colStep: number,
  rowStep: number,
  measuredX: number[] = [],
  measuredY: number[] = [],
  metrics?: GridLayoutMetrics
): number {
  const m: GridLayoutMetrics = metrics ?? {
    cols: cols,
    colStep: colStep,
    rowStep: rowStep,
    colGap: 12,
    paddingLeft: 24,
    paddingTop: 28,
    cellContentHeight: 183
  }
  const originX = slotCenterX(fromIndex, m, measuredX)
  const originY = slotCenterY(fromIndex, m, measuredY)
  const fingerX = originX + offsetX
  const fingerY = originY + offsetY
  let to = nearestSlotIndex(fingerX, fingerY, count, m, measuredX, measuredY)
  const max = Math.max(0, count - 1)
  if (to > max) {
    to = max
  }
  return to
}
