import { relationalStore } from '@kit.ArkData'
import { BrowserDatabase } from './BrowserDatabase'
import { ShortcutItem, createShortcutItem, CreateShortcutItemInput } from '../model/ShortcutItem'

/** 快捷方式持久化，对应 shortcuts 表 */
export class ShortcutRepository {
  private static instance: ShortcutRepository | null = null

  /** 获取快捷方式仓库单例实例 */
  static getInstance(): ShortcutRepository {
    if (ShortcutRepository.instance === null) {
      ShortcutRepository.instance = new ShortcutRepository()
    }
    return ShortcutRepository.instance
  }

  /** 查询全部快捷方式并按排序字段升序返回 */
  async findAll(): Promise<ShortcutItem[]> {
    const store = BrowserDatabase.getInstance().getStore()
    const rs = await store.querySql('SELECT * FROM shortcuts ORDER BY sort_order ASC')
    const list: ShortcutItem[] = []
    try {
      while (rs.goToNextRow()) {
        list.push(this.rowToItem(rs))
      }
    } finally {
      rs.close()
    }
    return list
  }

  /** 插入或更新快捷方式记录 */
  async upsert(item: ShortcutItem): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    item.updatedAt = Date.now()
    const bucket: relationalStore.ValuesBucket = {
      id: item.id,
      title: item.title,
      url: item.url,
      icon_url: item.iconUrl || null,
      sort_order: item.sortOrder,
      is_preset: item.isPreset ? 1 : 0,
      created_at: item.createdAt,
      updated_at: item.updatedAt
    }
    const existing = await this.findById(item.id)
    if (existing) {
      const predicates = new relationalStore.RdbPredicates('shortcuts')
      predicates.equalTo('id', item.id)
      await store.update(bucket, predicates)
    } else {
      await store.insert('shortcuts', bucket)
    }
  }

  /** 按 ID 删除快捷方式 */
  async deleteById(id: string): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('shortcuts')
    predicates.equalTo('id', id)
    await store.delete(predicates)
  }

  /** 按 ID 查询快捷方式，不存在则返回 null */
  async findById(id: string): Promise<ShortcutItem | null> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('shortcuts')
    predicates.equalTo('id', id)
    const rs = await store.query(predicates)
    try {
      if (rs.goToFirstRow()) {
        return this.rowToItem(rs)
      }
      return null
    } finally {
      rs.close()
    }
  }

  /** 按给定 ID 顺序重排快捷方式 */
  async reorder(ids: string[]): Promise<void> {
    for (let i = 0; i < ids.length; i++) {
      const item = await this.findById(ids[i])
      if (item) {
        item.sortOrder = i
        await this.upsert(item)
      }
    }
  }

  /** 将查询结果行映射为快捷方式模型 */
  private rowToItem(rs: relationalStore.ResultSet): ShortcutItem {
    const itemInput: CreateShortcutItemInput = {
      id: rs.getString(rs.getColumnIndex('id')),
      title: rs.getString(rs.getColumnIndex('title')),
      url: rs.getString(rs.getColumnIndex('url')),
      iconUrl: rs.getString(rs.getColumnIndex('icon_url')) ?? '',
      sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
      isPreset: rs.getLong(rs.getColumnIndex('is_preset')) === 1,
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
    }
    return createShortcutItem(itemInput)
  }
}
