import { BrowserStrings } from './BrowserStrings'
import { DateGroup } from '../model/BrowserTypes'
import { HistoryEntry } from '../model/HistoryEntry'
import { DownloadTask, formatFileSizeText } from '../model/DownloadTask'

/** 历史记录时间分组与批量删除辅助 */
export class HistoryGrouper {
  /** 生成历史记录按日分组的键 */
  static historyDayKey(time: number): string {
    const d = new Date(time)
    return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
  }

  /** 某时间戳所在自然日的起始毫秒（本地时区 0 点） */
  static historyDayStart(time: number): number {
    const d = new Date(time)
    d.setHours(0, 0, 0, 0)
    return d.getTime()
  }

  /** 某时间戳所在自然日的结束毫秒（不含，即次日 0 点） */
  static historyDayEnd(time: number): number {
    return HistoryGrouper.historyDayStart(time) + 86400000
  }

  /** 历史/下载共用：今天、昨天、今年内、跨年分组标题 */
  static formatDayGroupLabel(time: number): string {
    const d = new Date(time)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const dayStart = new Date(d)
    dayStart.setHours(0, 0, 0, 0)
    if (dayStart.getTime() === today.getTime()) {
      return BrowserStrings.todayLabel()
    }
    const yesterday = new Date(today)
    yesterday.setDate(yesterday.getDate() - 1)
    if (dayStart.getTime() === yesterday.getTime()) {
      return BrowserStrings.yesterdayLabel()
    }
    const month = d.getMonth() + 1
    const day = d.getDate()
    if (d.getFullYear() === today.getFullYear()) {
      return BrowserStrings.historySectionDate(month, day)
    }
    return BrowserStrings.historySectionFullDate(d.getFullYear(), month, day)
  }

  /** 格式化历史记录分组标题日期 */
  static formatHistorySectionDate(time: number): string {
    return HistoryGrouper.formatDayGroupLabel(time)
  }

  /** 格式化下载记录分组标题（规则与历史记录一致） */
  static formatDownloadSectionDate(time: number): string {
    return HistoryGrouper.formatDayGroupLabel(time)
  }

  /** 将历史记录按日期分组 */
  static groupHistoryByDate(items: HistoryEntry[]): DateGroup<HistoryEntry>[] {
    const map = new Map<string, DateGroup<HistoryEntry>>()
    items.forEach((h) => {
      const key = HistoryGrouper.historyDayKey(h.visitedAt)
      if (!map.has(key)) {
        map.set(key, { label: HistoryGrouper.formatHistorySectionDate(h.visitedAt), items: [] })
      }
      map.get(key)!.items.push(h)
    })
    const result: DateGroup<HistoryEntry>[] = []
    map.forEach((group) => result.push(group))
    return result
  }

  /** 将下载任务按日期分组 */
  static groupDownloadsByDate(items: DownloadTask[]): DateGroup<DownloadTask>[] {
    const map = new Map<string, DateGroup<DownloadTask>>()
    items.forEach((d) => {
      const key = HistoryGrouper.historyDayKey(d.createdAt)
      const label = HistoryGrouper.formatDownloadSectionDate(d.createdAt)
      if (!map.has(key)) {
        map.set(key, { label: label, items: [] })
      }
      map.get(key)!.items.push(d)
    })
    const result: DateGroup<DownloadTask>[] = []
    map.forEach((group) => result.push(group))
    return result
  }

  /** 从 URL 提取站点图标首字母 */
  static historySiteIconChar(url: string): string {
    try {
      const normalized = url.startsWith('http') ? url : `https://${url}`
      const host = normalized.replace(/^https?:\/\//, '').split('/')[0]
      return host.charAt(0).toUpperCase() || 'W'
    } catch {
      return 'W'
    }
  }

  /** 格式化下载任务的文件大小文本 */
  static downloadSizeText(task: DownloadTask): string {
    if (task.fileSize > 0) {
      return formatFileSizeText(task.fileSize)
    }
    return ''
  }
}
