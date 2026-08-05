import { AppStorageKeys } from 'common'
import {
  ShortcutCatalogEntry,
  ShortcutCatalogMeta,
  ShortcutItem,
  CreateShortcutItemInput,
  createShortcutItem
} from 'common'
import { BookmarkItem } from 'common'
import { HistoryEntry } from 'common'
import { ShortcutRepository } from 'common'
import { BrowserStrings } from 'common'
import { getBrowserContext } from 'common'
import { BrowserUtils } from 'common'
import { AppStateSync } from './AppStateSync'

/** 预置与用户快捷方式持久化 */
export class ShortcutManager {
  private static instance: ShortcutManager | null = null

  /** 首页快捷方式数量上限（动态，默认 24） */
  static getMaxHomeShortcuts(): number {
    return AppStorage.get<number>(AppStorageKeys.SHORTCUT_MAX_COUNT) ?? ShortcutManager.MAX_HOME_SHORTCUTS_FALLBACK
  }

  static readonly MAX_HOME_SHORTCUTS_FALLBACK: number = 24

  /** 目录元数据（title 运行时从 BrowserStrings 解析） */
  private static readonly FEATURE_CATALOG_META: ShortcutCatalogMeta[] = [
    { id: 'bookmarks', kind: 'feature', tile: 'bookmark' },
    { id: 'history', kind: 'feature', tile: 'history' },
    { id: 'downloads', kind: 'feature', tile: 'download' },
    { id: 'baidu', kind: 'site', iconText: 'du', iconMedia: 'baidu', url: 'https://www.baidu.com' },
    { id: 'quark', kind: 'site', iconText: '夸', iconMedia: 'quark', url: 'https://www.quark.cn' },
    { id: 'bing', kind: 'site', iconText: 'b', url: 'https://www.bing.com' },
    { id: 'sogou', kind: 'site', iconText: 'S', url: 'https://m.sogou.com' },
    { id: '360', kind: 'site', iconText: '360', iconMedia: '360', url: 'https://m.so.com' }
  ]

  static readonly DEFAULT_ORDER: string[] = [
    'downloads', 'bookmarks', 'history', 'baidu', 'quark', 'sogou', '360', 'bing'
  ]

  /** 构建带本地化标题的快捷方式目录（运行时调用，避免 static getter 在模块加载期触发） */
  static buildFeatureCatalog(): ShortcutCatalogEntry[] {
    const result: ShortcutCatalogEntry[] = []
    const canLocalize = getBrowserContext() !== null
    for (const item of ShortcutManager.FEATURE_CATALOG_META) {
      const entry: ShortcutCatalogEntry = {
        id: item.id,
        kind: item.kind,
        tile: item.tile,
        iconText: item.iconText,
        iconMedia: item.iconMedia,
        url: item.url,
        title: canLocalize ? BrowserStrings.shortcutTitle(item.id) : item.id
      }
      result.push(entry)
    }
    return result
  }

  /** 获取 ShortcutManager 单例 */
  static getInstance(): ShortcutManager {
    if (ShortcutManager.instance === null) {
      ShortcutManager.instance = new ShortcutManager()
    }
    return ShortcutManager.instance
  }

  /** 按 ID 查找目录中的快捷方式条目 */
  static getCatalogEntry(id: string): ShortcutCatalogEntry | undefined {
    return ShortcutManager.buildFeatureCatalog().find((c) => c.id === id)
  }

  /** 解析首页展示条目（预置目录 + 持久化自定义项） */
  static resolveDisplayEntry(id: string): ShortcutCatalogEntry | undefined {
    const catalog = ShortcutManager.getCatalogEntry(id)
    if (catalog) {
      return catalog
    }
    const items = AppStorage.get<ShortcutItem[]>(AppStorageKeys.SHORTCUTS) ?? []
    const item = items.find((s) => s.id === id)
    if (!item) {
      return undefined
    }
    return ShortcutManager.itemToCatalogEntry(item)
  }

  /** 将持久化快捷方式转为 UI 目录条目 */
  static itemToCatalogEntry(item: ShortcutItem): ShortcutCatalogEntry {
    if (item.url.startsWith('feature://')) {
      const featureId = item.url.substring('feature://'.length)
      const catalog = ShortcutManager.getCatalogEntry(featureId)
      if (catalog) {
        return catalog
      }
      return {
        id: item.id,
        title: item.title,
        kind: 'feature',
        tile: 'bookmark'
      }
    }
    const host = BrowserUtils.tabHostname(item.url)
    const iconChar = host.length > 0 ? host.charAt(0).toUpperCase() : '?'
    return {
      id: item.id,
      title: item.title,
      kind: 'site',
      iconText: iconChar,
      url: item.url
    }
  }

  /** 书签来源快捷方式 ID */
  static bookmarkShortcutId(bookmarkId: string): string {
    return `bm_${bookmarkId}`
  }

  /** 历史来源快捷方式 ID */
  static historyShortcutId(historyId: number): string {
    return `hist_${historyId}`
  }

  /** 实例方法：按 ID 查找目录条目 */
  getCatalogEntry(id: string): ShortcutCatalogEntry | undefined {
    return ShortcutManager.getCatalogEntry(id)
  }

  /** 首次启动时导入预置快捷方式 */
  async importPresetsIfNeeded(): Promise<void> {
    const existing = await ShortcutRepository.getInstance().findAll()
    if (existing.length > 0) {
      return
    }
    for (let i = 0; i < ShortcutManager.DEFAULT_ORDER.length; i++) {
      const id = ShortcutManager.DEFAULT_ORDER[i]
      const catalog: ShortcutCatalogEntry | undefined = ShortcutManager.getCatalogEntry(id)
      if (!catalog) {
        continue
      }
      const url = catalog.url ?? `feature://${catalog.id}`
      const shortcutInput: CreateShortcutItemInput = {
        id: catalog.id,
        title: catalog.title,
        url: url,
        sortOrder: i,
        isPreset: true
      }
      await ShortcutRepository.getInstance().upsert(createShortcutItem(shortcutInput))
    }
  }

  /** 获取当前快捷方式排序后的 ID 列表 */
  async getOrderedIds(): Promise<string[]> {
    const items = await ShortcutRepository.getInstance().findAll()
    return items.map((s) => s.id)
  }

  /** 通用添加快捷方式 */
  async addShortcutItem(input: CreateShortcutItemInput): Promise<boolean> {
    const items = await ShortcutRepository.getInstance().findAll()
    if (items.some((s) => s.id === input.id)) {
      return false
    }
    if (items.length >= ShortcutManager.getMaxHomeShortcuts()) {
      return false
    }
    const addInput: CreateShortcutItemInput = {
      id: input.id,
      title: input.title,
      url: input.url,
      iconUrl: input.iconUrl,
      sortOrder: items.length,
      isPreset: input.isPreset ?? false
    }
    await ShortcutRepository.getInstance().upsert(createShortcutItem(addInput))
    await AppStateSync.refreshShortcuts()
    return true
  }

  /** 从目录添加快捷方式到首页 */
  async addShortcut(id: string): Promise<boolean> {
    const catalog = this.getCatalogEntry(id)
    if (!catalog) {
      return false
    }
    return this.addShortcutItem({
      id: catalog.id,
      title: catalog.title,
      url: catalog.url ?? `feature://${catalog.id}`,
      isPreset: catalog.kind === 'site'
    })
  }

  /** 添加自定义网址快捷方式 */
  async addCustomShortcut(title: string, url: string): Promise<boolean> {
    const id = `custom_${Date.now()}`
    return this.addShortcutItem({
      id: id,
      title: title,
      url: url,
      isPreset: false
    })
  }

  /** 从书签添加快捷方式 */
  async addBookmarkShortcut(bookmark: BookmarkItem): Promise<boolean> {
    return this.addShortcutItem({
      id: ShortcutManager.bookmarkShortcutId(bookmark.id),
      title: bookmark.title,
      url: bookmark.url,
      iconUrl: bookmark.iconUrl,
      isPreset: false
    })
  }

  /** 从历史记录添加快捷方式 */
  async addHistoryShortcut(entry: HistoryEntry): Promise<boolean> {
    const title = entry.title.length > 0 ? entry.title : BrowserUtils.tabHostname(entry.url)
    return this.addShortcutItem({
      id: ShortcutManager.historyShortcutId(entry.id),
      title: title,
      url: entry.url,
      iconUrl: entry.iconUrl,
      isPreset: false
    })
  }

  /** 移除指定快捷方式 */
  async removeShortcut(id: string): Promise<void> {
    await ShortcutRepository.getInstance().deleteById(id)
    await AppStateSync.refreshShortcuts()
  }

  /** 更新快捷方式标题与网址 */
  async updateShortcut(id: string, title: string, url?: string): Promise<boolean> {
    const item = await ShortcutRepository.getInstance().findById(id)
    if (!item) {
      return false
    }
    item.title = title
    if (url !== undefined && url.length > 0) {
      item.url = url
    }
    await ShortcutRepository.getInstance().upsert(item)
    await AppStateSync.refreshShortcuts()
    return true
  }

  /** 调整快捷方式在列表中的顺序 */
  async reorder(fromIndex: number, toIndex: number): Promise<void> {
    const ids = await this.getOrderedIds()
    if (fromIndex < 0 || toIndex < 0 || fromIndex >= ids.length || toIndex >= ids.length) {
      return
    }
    const item = ids.splice(fromIndex, 1)[0]
    ids.splice(toIndex, 0, item)
    await ShortcutRepository.getInstance().reorder(ids)
    await AppStateSync.refreshShortcuts()
  }

  /** 按方向移动快捷方式位置 */
  async moveShortcut(index: number, direction: 'left' | 'right' | 'up' | 'down'): Promise<void> {
    const cols = 4
    let to = index
    if (direction === 'left') {
      to = index - 1
    } else if (direction === 'right') {
      to = index + 1
    } else if (direction === 'up') {
      to = index - cols
    } else if (direction === 'down') {
      to = index + cols
    }
    await this.reorder(index, to)
  }
}
