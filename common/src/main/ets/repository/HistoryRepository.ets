import { relationalStore } from '@kit.ArkData'
import { BrowserUtils } from '../utils/BrowserUtils'
import { BrowserDatabase } from './BrowserDatabase'
import { HistoryEntry, createHistoryEntry, CreateHistoryEntryInput } from '../model/HistoryEntry'
import { HistoryGrouper } from '../utils/HistoryGrouper'

/** 浏览历史持久化，对应 history_entries 表 */
export class HistoryRepository {
  private static instance: HistoryRepository | null = null

  /** 获取历史记录仓库单例实例 */
  static getInstance(): HistoryRepository {
    if (HistoryRepository.instance === null) {
      HistoryRepository.instance = new HistoryRepository()
    }
    return HistoryRepository.instance
  }

  /** 不再写入示例历史；清理旧版内置测试记录 */
  async seedDefaultsIfEmpty(): Promise<void> {
    await this.removeLegacySeedHistory()
  }

  /** 删除旧版 seedDefaultsIfEmpty 写入的示例记录（按 url + visitedAt 精确匹配） */
  async removeLegacySeedHistory(): Promise<void> {
    const legacySeeds: Array<CreateHistoryEntryInput> = [
      { url: 'https://www.example.com/files', title: '', visitedAt: new Date('2025-05-24T10:30:00').getTime() },
      { url: 'https://developer.huawei.com', title: '', visitedAt: new Date('2025-05-24T09:15:00').getTime() },
      { url: 'https://www.baidu.com', title: '', visitedAt: new Date('2025-05-21T14:20:00').getTime() },
      { url: 'https://docs.openharmony.cn', title: '', visitedAt: new Date('2025-05-21T11:00:00').getTime() }
    ]
    const all = await this.findAll()
    for (let i = 0; i < all.length; i++) {
      const entry = all[i]
      for (let j = 0; j < legacySeeds.length; j++) {
        const seed = legacySeeds[j]
        if (entry.url === seed.url && entry.visitedAt === seed.visitedAt) {
          await this.deleteById(entry.id)
          break
        }
      }
    }
  }

  /** 查询全部历史记录并按访问时间降序返回 */
  async findAll(): Promise<HistoryEntry[]> {
    const store = BrowserDatabase.getInstance().getStore()
    const rs = await store.querySql('SELECT * FROM history_entries ORDER BY visited_at DESC')
    const list: HistoryEntry[] = []
    try {
      while (rs.goToNextRow()) {
        list.push(this.rowToEntry(rs))
      }
    } finally {
      rs.close()
    }
    return list
  }

  /** 插入历史：同站点同一天仅更新访问时间与排序，跨日新增一条 */
  async insert(entry: HistoryEntry): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    entry.url = BrowserUtils.normalizeHistoryUrl(entry.url)
    const existing = await this.findBySiteOnDay(entry.url, entry.visitedAt)
    if (existing) {
      existing.url = entry.url
      if (entry.title.trim()) {
        existing.title = entry.title.trim()
      }
      if (entry.iconUrl.trim()) {
        existing.iconUrl = entry.iconUrl.trim()
      }
      existing.visitedAt = entry.visitedAt
      await this.update(existing)
      return
    }
    await store.insert('history_entries', {
      url: entry.url,
      title: entry.title,
      visited_at: entry.visitedAt,
      icon_url: entry.iconUrl || null,
      visit_count: entry.visitCount
    })
  }

  /** 更新当天已有记录的标题（不新增、不改动访问时间） */
  async updateTitleForUrl(url: string, title: string): Promise<void> {
    const trimmedTitle = title.trim()
    const normalizedUrl = BrowserUtils.normalizeHistoryUrl(url)
    if (!trimmedTitle || !normalizedUrl) {
      return
    }
    const existing = await this.findBySiteOnDay(normalizedUrl, Date.now())
    if (!existing || existing.title === trimmedTitle) {
      return
    }
    existing.title = trimmedTitle
    await this.update(existing)
  }

  /** 更新当天已有记录的站点图标（不新增、不改动访问时间） */
  async updateIconForUrl(url: string, iconUrl: string): Promise<void> {
    const normalizedIcon = iconUrl.trim()
    const normalizedUrl = BrowserUtils.normalizeHistoryUrl(url)
    if (!normalizedIcon || !normalizedUrl) {
      return
    }
    const existing = await this.findBySiteOnDay(normalizedUrl, Date.now())
    if (!existing || existing.iconUrl === normalizedIcon) {
      return
    }
    existing.iconUrl = normalizedIcon
    await this.update(existing)
  }

  /** 更新已有历史记录 */
  async update(entry: HistoryEntry): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('history_entries')
    predicates.equalTo('id', entry.id)
    await store.update({
      url: entry.url,
      title: entry.title,
      visited_at: entry.visitedAt,
      icon_url: entry.iconUrl || null,
      visit_count: entry.visitCount
    }, predicates)
  }

  /** 按 ID 删除单条历史记录 */
  async deleteById(id: number): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('history_entries')
    predicates.equalTo('id', id)
    await store.delete(predicates)
  }

  /** 批量删除多条历史记录 */
  async deleteByIds(ids: number[]): Promise<void> {
    for (const id of ids) {
      await this.deleteById(id)
    }
  }

  /** 清空全部浏览历史 */
  async clearAll(): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('history_entries')
    await store.delete(predicates)
  }

  /** 按标题或 URL 关键词搜索历史记录 */
  async search(keyword: string): Promise<HistoryEntry[]> {
    const q = keyword.trim().toLowerCase()
    if (!q) {
      return this.findAll()
    }
    const all = await this.findAll()
    return all.filter((h) =>
      h.title.toLowerCase().includes(q) || h.url.toLowerCase().includes(q)
    )
  }

  /** 按站点 + 自然日查询历史记录，不存在则返回 null */
  private async findBySiteOnDay(url: string, visitedAt: number): Promise<HistoryEntry | null> {
    const siteKey = BrowserUtils.historySiteKey(url)
    if (!siteKey) {
      return null
    }
    const dayStart = HistoryGrouper.historyDayStart(visitedAt)
    const dayEnd = HistoryGrouper.historyDayEnd(visitedAt)
    const store = BrowserDatabase.getInstance().getStore()
    const rs = await store.querySql(
      'SELECT * FROM history_entries WHERE visited_at >= ? AND visited_at < ? ORDER BY visited_at DESC',
      [dayStart, dayEnd]
    )
    try {
      while (rs.goToNextRow()) {
        const entry = this.rowToEntry(rs)
        if (BrowserUtils.historySiteKey(entry.url) === siteKey) {
          return entry
        }
      }
      return null
    } finally {
      rs.close()
    }
  }

  /** 将查询结果行映射为历史记录模型 */
  private rowToEntry(rs: relationalStore.ResultSet): HistoryEntry {
    const entryInput: CreateHistoryEntryInput = {
      id: rs.getLong(rs.getColumnIndex('id')),
      url: rs.getString(rs.getColumnIndex('url')),
      title: rs.getString(rs.getColumnIndex('title')),
      visitedAt: rs.getLong(rs.getColumnIndex('visited_at')),
      iconUrl: rs.getString(rs.getColumnIndex('icon_url')) ?? '',
      visitCount: rs.getLong(rs.getColumnIndex('visit_count'))
    }
    return createHistoryEntry(entryInput)
  }
}
