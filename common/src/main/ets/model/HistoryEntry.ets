/** 浏览历史实体，对应 history_entries 表 */
export interface HistoryEntry {
  /** 历史记录自增 ID */
  id: number
  /** 访问的页面 URL */
  url: string
  /** 页面标题 */
  title: string
  /** 最后访问时间戳（毫秒） */
  visitedAt: number
  /** 站点图标 URL */
  iconUrl: string
  /** 累计访问次数 */
  visitCount: number
}

/** 创建或更新历史记录时的输入参数 */
export interface CreateHistoryEntryInput {
  /** 访问的页面 URL */
  url: string
  /** 页面标题 */
  title: string
  /** 历史记录 ID，新建时为 0 */
  id?: number
  /** 最后访问时间戳（毫秒） */
  visitedAt?: number
  /** 站点图标 URL */
  iconUrl?: string
  /** 累计访问次数 */
  visitCount?: number
}

/** 根据输入参数创建历史记录实体，并填充默认值 */
export function createHistoryEntry(input: CreateHistoryEntryInput): HistoryEntry {
  return {
    id: input.id ?? 0,
    visitedAt: input.visitedAt ?? Date.now(),
    iconUrl: input.iconUrl ?? '',
    visitCount: input.visitCount ?? 1,
    url: input.url,
    title: input.title
  }
}
