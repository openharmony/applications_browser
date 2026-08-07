import { relationalStore } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'BrowserDatabase'
const DB_NAME: string = 'browser.db'

/** 浏览器 RDB 单例，负责建表与连接 */
export class BrowserDatabase {
  private static instance: BrowserDatabase | null = null
  private store: relationalStore.RdbStore | null = null

  /** 获取数据库单例实例 */
  static getInstance(): BrowserDatabase {
    if (BrowserDatabase.instance === null) {
      BrowserDatabase.instance = new BrowserDatabase()
    }
    return BrowserDatabase.instance
  }

  /** 初始化 RDB 连接并创建业务表 */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    }
    this.store = await relationalStore.getRdbStore(context, config)
    await this.createTables()
    hilog.info(DOMAIN, TAG, 'Database initialized')
  }

  /** 获取已初始化的 RDB 存储实例 */
  getStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('BrowserDatabase not initialized')
    }
    return this.store
  }

  /** 创建浏览器各业务模块所需的数据表 */
  private async createTables(): Promise<void> {
    const store = this.getStore()
    const sqlList: string[] = [
      `CREATE TABLE IF NOT EXISTS browser_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        title TEXT NOT NULL,
        url TEXT,
        icon_url TEXT,
        sort_order INTEGER NOT NULL,
        is_folder INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS history_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        visited_at INTEGER NOT NULL,
        icon_url TEXT,
        visit_count INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS shortcuts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        icon_url TEXT,
        sort_order INTEGER NOT NULL,
        is_preset INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS tab_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        is_incognito INTEGER NOT NULL,
        web_state TEXT,
        thumbnail_path TEXT,
        sort_order INTEGER NOT NULL,
        is_active INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS download_tasks (
        id TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        source_url TEXT NOT NULL,
        local_path TEXT,
        status TEXT NOT NULL,
        progress INTEGER NOT NULL,
        file_size INTEGER,
        mime_type TEXT,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    ]
    for (const sql of sqlList) {
      await store.executeSql(sql)
    }
    await this.migrateDownloadTasksTable()
  }

  /** 增量迁移 download_tasks 表结构 */
  private async migrateDownloadTasksTable(): Promise<void> {
    const store = this.getStore()
    try {
      await store.executeSql('ALTER TABLE download_tasks ADD COLUMN gallery_uri TEXT')
      hilog.info(DOMAIN, TAG, 'Added gallery_uri column to download_tasks')
    } catch (_err) {
      // 列已存在则忽略
    }
  }
}
