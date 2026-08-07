import { relationalStore } from '@kit.ArkData'
import { BrowserDatabase } from './BrowserDatabase'
import { TabSession, createTabSession, CreateTabSessionInput } from '../model/TabSession'

/** 标签页会话持久化，对应 tab_sessions 表；无痕标签跳过写入 */
export class TabRepository {
  private static instance: TabRepository | null = null

  /** 获取标签页仓库单例实例 */
  static getInstance(): TabRepository {
    if (TabRepository.instance === null) {
      TabRepository.instance = new TabRepository()
    }
    return TabRepository.instance
  }

  /** 标签页为空时不写入示例数据，由 TabManager.ensureDefaultTabForCurrentMode 按当前模式补建 */
  async seedDefaultsIfEmpty(): Promise<void> {
  }

  /** 查询标签页列表，可选是否包含无痕标签 */
  async findAll(includeIncognito: boolean): Promise<TabSession[]> {
    const store = BrowserDatabase.getInstance().getStore()
    let sql = 'SELECT * FROM tab_sessions'
    if (!includeIncognito) {
      sql += ' WHERE is_incognito = 0'
    }
    sql += ' ORDER BY sort_order ASC'
    const rs = await store.querySql(sql)
    const list: TabSession[] = []
    try {
      while (rs.goToNextRow()) {
        list.push(this.rowToSession(rs))
      }
    } finally {
      rs.close()
    }
    return list
  }

  /** 插入或更新标签页，无痕标签跳过持久化 */
  async upsert(session: TabSession): Promise<void> {
    if (session.isIncognito) {
      return
    }
    const store = BrowserDatabase.getInstance().getStore()
    const existing = await this.findById(session.id)
    session.updatedAt = Date.now()
    const bucket: relationalStore.ValuesBucket = {
      id: session.id,
      title: session.title,
      url: session.url,
      is_incognito: session.isIncognito ? 1 : 0,
      web_state: session.webState || null,
      thumbnail_path: session.thumbnailPath || null,
      sort_order: session.sortOrder,
      is_active: session.isActive ? 1 : 0,
      created_at: session.createdAt,
      updated_at: session.updatedAt
    }
    if (existing) {
      const predicates = new relationalStore.RdbPredicates('tab_sessions')
      predicates.equalTo('id', session.id)
      await store.update(bucket, predicates)
    } else {
      await store.insert('tab_sessions', bucket)
    }
  }

  /** 清除全部普通标签的活跃标记 */
  async resetActiveFlags(): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('tab_sessions')
    predicates.equalTo('is_incognito', 0)
    await store.update({ is_active: 0 }, predicates)
  }

  /** 将指定标签设为活跃 */
  async setActiveFlag(id: string): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('tab_sessions')
    predicates.equalTo('id', id)
    await store.update({ is_active: 1 }, predicates)
  }

  /** 按给定顺序批量更新 sort_order（不触碰 updated_at，避免 ForEach 全量重建） */
  async reorderByIds(ids: string[]): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    for (let i = 0; i < ids.length; i++) {
      const predicates = new relationalStore.RdbPredicates('tab_sessions')
      predicates.equalTo('id', ids[i])
      await store.update({ sort_order: i }, predicates)
    }
  }

  /** 按 ID 删除标签页 */
  async deleteById(id: string): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('tab_sessions')
    predicates.equalTo('id', id)
    await store.delete(predicates)
  }

  /** 清除全部非无痕标签页 */
  async clearNonIncognito(): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('tab_sessions')
    predicates.equalTo('is_incognito', 0)
    await store.delete(predicates)
  }

  /** 按 ID 查询标签页，不存在则返回 null */
  async findById(id: string): Promise<TabSession | null> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('tab_sessions')
    predicates.equalTo('id', id)
    const rs = await store.query(predicates)
    try {
      if (rs.goToFirstRow()) {
        return this.rowToSession(rs)
      }
      return null
    } finally {
      rs.close()
    }
  }

  /** 将查询结果行映射为标签页会话模型 */
  private rowToSession(rs: relationalStore.ResultSet): TabSession {
    const sessionInput: CreateTabSessionInput = {
      id: rs.getString(rs.getColumnIndex('id')),
      title: rs.getString(rs.getColumnIndex('title')),
      url: rs.getString(rs.getColumnIndex('url')),
      isIncognito: rs.getLong(rs.getColumnIndex('is_incognito')) === 1,
      webState: rs.getString(rs.getColumnIndex('web_state')) ?? '',
      thumbnailPath: rs.getString(rs.getColumnIndex('thumbnail_path')) ?? '',
      sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
      isActive: rs.getLong(rs.getColumnIndex('is_active')) === 1,
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
    }
    return createTabSession(sessionInput)
  }
}
