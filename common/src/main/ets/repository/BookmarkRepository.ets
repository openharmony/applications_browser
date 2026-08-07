import { relationalStore } from '@kit.ArkData'
import { BrowserDatabase } from './BrowserDatabase'
import { BookmarkItem, BOOKMARK_ROOT_ID, createBookmarkItem, CreateBookmarkItemInput } from '../model/BookmarkItem'

/** 书签树形 CRUD，对应 bookmarks 表 */
export class BookmarkRepository {
  private static instance: BookmarkRepository | null = null

  /** 旧版内置示例书签/文件夹 ID（启动时清理，不再写入） */
  private static readonly LEGACY_SEED_IDS: string[] = ['bf1', 'bf2', 'bf3', 'bf4', 'b0', 'b1', 'b2', 'b3', 'b4']

  /** 获取书签仓库单例实例 */
  static getInstance(): BookmarkRepository {
    if (BookmarkRepository.instance === null) {
      BookmarkRepository.instance = new BookmarkRepository()
    }
    return BookmarkRepository.instance
  }

  /** 清理旧版内置示例书签，不再写入测试数据 */
  async seedDefaultsIfEmpty(): Promise<void> {
    await this.removeLegacySeedBookmarks()
  }

  /** 删除旧版 seedDefaultsIfEmpty 写入的示例书签与文件夹 */
  async removeLegacySeedBookmarks(): Promise<void> {
    for (let i = 0; i < BookmarkRepository.LEGACY_SEED_IDS.length; i++) {
      const id = BookmarkRepository.LEGACY_SEED_IDS[i]
      const existing = await this.findById(id)
      if (existing !== null) {
        await this.deleteById(id)
      }
    }
  }

  /** 查询全部书签并按排序字段升序返回 */
  async findAll(): Promise<BookmarkItem[]> {
    const store = BrowserDatabase.getInstance().getStore()
    const rs = await store.querySql('SELECT * FROM bookmarks ORDER BY sort_order ASC')
    const list: BookmarkItem[] = []
    try {
      while (rs.goToNextRow()) {
        list.push(this.rowToItem(rs))
      }
    } finally {
      rs.close()
    }
    return list
  }

  /** 按父节点 ID 查询直接子书签 */
  async findByParentId(parentId: string): Promise<BookmarkItem[]> {
    const normalized = parentId || BOOKMARK_ROOT_ID
    const all = await this.findAll()
    return all.filter((b) => (b.parentId || BOOKMARK_ROOT_ID) === normalized)
      .sort((a, b) => a.sortOrder - b.sortOrder)
  }

  /** 按 ID 查询单个书签，不存在则返回 null */
  async findById(id: string): Promise<BookmarkItem | null> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('bookmarks')
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

  /** 按 URL 查询书签，不存在则返回 null */
  async findByUrl(url: string): Promise<BookmarkItem | null> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('bookmarks')
    predicates.equalTo('url', url)
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

  /** 插入新书签记录 */
  async insert(item: BookmarkItem): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    await store.insert('bookmarks', this.itemToBucket(item))
  }

  /** 更新已有书签并刷新更新时间 */
  async update(item: BookmarkItem): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    item.updatedAt = Date.now()
    const predicates = new relationalStore.RdbPredicates('bookmarks')
    predicates.equalTo('id', item.id)
    await store.update(this.itemToBucket(item), predicates)
  }

  /** 递归删除指定节点及其全部子节点 */
  async deleteById(id: string): Promise<void> {
    const doomed = new Set<string>()
    const walk = async (nodeId: string): Promise<void> => {
      if (doomed.has(nodeId)) {
        return
      }
      doomed.add(nodeId)
      const children = await this.findByParentId(nodeId)
      for (const child of children) {
        await walk(child.id)
      }
    }
    await walk(id)
    const store = BrowserDatabase.getInstance().getStore()
    for (const nodeId of doomed) {
      const predicates = new relationalStore.RdbPredicates('bookmarks')
      predicates.equalTo('id', nodeId)
      await store.delete(predicates)
    }
  }

  /** 批量删除多个书签节点 */
  async deleteByIds(ids: string[]): Promise<void> {
    for (const id of ids) {
      await this.deleteById(id)
    }
  }

  /** 统计非文件夹类型的书签数量 */
  async countBookmarks(): Promise<number> {
    const all = await this.findAll()
    return all.filter((b) => !b.isFolder).length
  }

  /** 将多个书签移动到指定父节点下 */
  async moveToParent(ids: string[], parentId: string): Promise<void> {
    for (const id of ids) {
      const item = await this.findById(id)
      if (item) {
        item.parentId = parentId || BOOKMARK_ROOT_ID
        await this.update(item)
      }
    }
  }

  /** 按给定顺序重写同层书签的 sort_order */
  async reorderByIds(orderedIds: string[]): Promise<void> {
    const now = Date.now()
    for (let i = 0; i < orderedIds.length; i++) {
      const item = await this.findById(orderedIds[i])
      if (item === null) {
        continue
      }
      if (item.sortOrder === i) {
        continue
      }
      item.sortOrder = i
      item.updatedAt = now
      await this.update(item)
    }
  }

  /** 将书签模型转换为数据库写入字段 */
  private itemToBucket(item: BookmarkItem): relationalStore.ValuesBucket {
    return {
      id: item.id,
      parent_id: item.parentId || null,
      title: item.title,
      url: item.isFolder ? null : item.url,
      icon_url: item.iconUrl || null,
      sort_order: item.sortOrder,
      is_folder: item.isFolder ? 1 : 0,
      created_at: item.createdAt,
      updated_at: item.updatedAt
    }
  }

  /** 将查询结果行映射为书签模型 */
  private rowToItem(rs: relationalStore.ResultSet): BookmarkItem {
    const parentRaw = rs.getString(rs.getColumnIndex('parent_id'))
    const itemInput: CreateBookmarkItemInput = {
      id: rs.getString(rs.getColumnIndex('id')),
      parentId: parentRaw ?? BOOKMARK_ROOT_ID,
      title: rs.getString(rs.getColumnIndex('title')),
      url: rs.getString(rs.getColumnIndex('url')) ?? '',
      iconUrl: rs.getString(rs.getColumnIndex('icon_url')) ?? '',
      sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
      isFolder: rs.getLong(rs.getColumnIndex('is_folder')) === 1,
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
    }
    return createBookmarkItem(itemInput)
  }
}
