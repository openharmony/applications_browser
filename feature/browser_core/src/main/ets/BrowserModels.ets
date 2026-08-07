import { BrowserUtils } from 'common'
import { HistoryGrouper } from 'common'
import { HistoryEntry } from 'common'
import { DownloadTask } from 'common'
import { DateGroup } from 'common'
import { ShortcutCatalogEntry } from 'common'

export { TabSession, createTabSession } from 'common'
export type TabEntry = import('common').TabSession

export { BookmarkItem, BOOKMARK_ROOT_ID, createBookmarkItem, CreateBookmarkItemInput, BookmarkUpdateInput } from 'common'
/** 书签根目录 ID 别名（与 BOOKMARK_ROOT_ID 相同） */
export const BOOKMARK_ROOT_FOLDER: string = ''
export type BookmarkEntry = import('common').BookmarkItem

export { HistoryEntry, createHistoryEntry } from 'common'

export { DownloadTask, createDownloadTask, formatFileSizeText } from 'common'
export type DownloadEntry = import('common').DownloadTask
export type { DownloadStatus } from 'common'

export {
  ShortcutItem, createShortcutItem
} from 'common'
export type { ShortcutCatalogEntry, ShortcutKind } from 'common'
export type ShortcutFeature = ShortcutCatalogEntry

export {
  FeaturePanelType, DateGroup, ShareSheetParams, OpenShareOptions,
  DownloadRequest, AddTabOptions, OpenBrowseOptions, BrowseRouteParams,
  TabsRouteParams, ShortcutMoveDirection,
  BrowseTabPatch,
  BOOKMARK_LIMIT, TAB_LIMIT, TAB_LIMIT_DISPLAY, AppStorageKeys
} from 'common'

export { BrowserUtils }

/** 根据搜索引擎 ID 返回搜索 URL 前缀（委托 BrowserUtils） */
export function getSearchEngineBase(engine: string): string {
  return BrowserUtils.getSearchEngineBase(engine)
}

/** 从 URL 提取主机名（委托 BrowserUtils） */
export function tabHostname(url: string): string {
  return BrowserUtils.tabHostname(url)
}

/** 判断是否为图片文件（委托 BrowserUtils） */
export function isImageFile(name: string): boolean {
  return BrowserUtils.isImageFile(name)
}

/** 生成重名文件建议名（委托 BrowserUtils） */
export function suggestRename(name: string): string {
  return BrowserUtils.suggestRename(name)
}

/** 推断文件类型标签（委托 BrowserUtils） */
export function inferFileTypeLabel(name: string): string {
  return BrowserUtils.inferFileTypeLabel(name)
}

/** 将历史记录按日期分组 */
export function groupHistoryByDate(items: HistoryEntry[]): DateGroup<HistoryEntry>[] {
  return HistoryGrouper.groupHistoryByDate(items)
}

/** 将下载任务按日期分组 */
export function groupDownloadsByDate(items: DownloadTask[]): DateGroup<DownloadTask>[] {
  return HistoryGrouper.groupDownloadsByDate(items)
}

/** 根据 URL 生成历史站点图标字符 */
export function historySiteIconChar(url: string): string {
  return HistoryGrouper.historySiteIconChar(url)
}

/** 格式化历史记录分组日期标题 */
export function formatHistorySectionDate(time: number): string {
  return HistoryGrouper.formatHistorySectionDate(time)
}

/** 格式化下载分组日期标题，支持 today/yesterday 本地化替换 */
export function formatDownloadSectionDate(time: number, todayLabel?: string, yesterdayLabel?: string): string {
  const key = HistoryGrouper.formatDownloadSectionDate(time)
  if (key === 'today' && todayLabel) {
    return todayLabel
  }
  if (key === 'yesterday' && yesterdayLabel) {
    return yesterdayLabel
  }
  return key
}

