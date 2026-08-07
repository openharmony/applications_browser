import { AppInitGate } from 'common'

import { BrowserLog } from 'common'

import { BrowserStrings } from 'common'
import { BrowserStore } from '../BrowserStore'

import { AddTabOptions, AppStorageKeys, BrowseTabPatch, TAB_LIMIT } from 'common'

import { TabSession, createTabSession, CreateTabSessionInput } from 'common'

import { TabRepository } from 'common'

import { SettingsRepository } from 'common'

import { AppStateSync } from '../AppStateSync'

import { IncognitoPolicy } from '../security/IncognitoPolicy'

import { IncognitoWebDataCleaner } from '../security/IncognitoWebDataCleaner'

import { reorderArrayIds } from 'common'



/** 标签 CRUD、活跃标签、无痕标志、状态快照 */

export class TabManager {

  private static instance: TabManager | null = null
  /** 标签 ID 序号，避免同毫秒连点导致 ID 碰撞 */
  private static tabIdSeq: number = 0
  /** 批量新增标签时合并 DB/UI 同步，避免连点风暴 */
  private tabListBatchDepth: number = 0

  /** 内存中的无痕标签（不持久化） */

  private incognitoTabs: TabSession[] = []



  /** 获取 TabManager 单例 */

  static getInstance(): TabManager {

    if (TabManager.instance === null) {

      TabManager.instance = new TabManager()

    }

    return TabManager.instance

  }



  /** 从 DB 同步普通标签到 AppStorage（合并内存中的 isHome，因库表未持久化该字段） */
  private async syncPersistedFromDb(): Promise<void> {
    const prev = AppStorage.get<TabSession[]>(AppStorageKeys.TABS_PERSISTED) ?? []
    const persisted = await TabRepository.getInstance().findAll(false)
    const merged: TabSession[] = persisted.map((p) => {
      const old = prev.find((x) => x.id === p.id)
      // 仅空 URL 的主页占位保留 isHome；已有网址的标签不得再标为 home
      if (old?.isHome === true && !p.url.trim()) {
        return {
          id: p.id,
          title: p.title,
          url: p.url,
          isIncognito: p.isIncognito,
          webState: p.webState,
          thumbnailPath: p.thumbnailPath,
          sortOrder: p.sortOrder,
          isActive: p.isActive,
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
          isHome: true,
          hideDesc: old.hideDesc ?? p.hideDesc
        }
      }
      return p
    })
    AppStorage.setOrCreate(AppStorageKeys.TABS_PERSISTED, merged)
    BrowserLog.info(`syncPersistedFromDb count=${merged.length}`)
  }



  /** 从仓库加载持久化标签到 AppStorage，并恢复最后活跃页签 */
  async loadFromRepository(): Promise<void> {
    await this.syncPersistedFromDb()
    const last = await SettingsRepository.getInstance().getLastActiveTab()
    if (last?.id) {
      AppStorage.setOrCreate(AppStorageKeys.ACTIVE_TAB, last.id)
      await SettingsRepository.getInstance().saveSettings({ incognitoMode: last.incognito })
      BrowserLog.info(`loadFromRepository restore lastActive=${last.id} incognito=${last.incognito}`)
    }
  }



  /** 获取全部标签（含无痕标签） */

  getAllTabs(): TabSession[] {

    const persisted = AppStorage.get<TabSession[]>(AppStorageKeys.TABS_PERSISTED) ?? []

    return [...persisted, ...this.incognitoTabs]

  }



  /** 获取普通模式标签数量 */

  getNormalTabCount(): number {

    return this.getAllTabs().filter((t) => !t.isIncognito).length

  }



  /** 获取无痕模式标签数量 */

  getIncognitoTabCount(): number {

    return this.getAllTabs().filter((t) => t.isIncognito).length

  }



  /** 生成唯一标签 ID */
  private static nextTabId(): string {
    TabManager.tabIdSeq++
    return `t${Date.now()}_${TabManager.tabIdSeq}`
  }

  /** 开始批量新增标签（期间 defer 全量 sync/refresh） */
  beginTabListBatch(): void {
    this.tabListBatchDepth++
    BrowserLog.info(`beginTabListBatch depth=${this.tabListBatchDepth}`)
  }

  /** 结束批量新增并一次性刷新标签列表 */
  async endTabListBatch(): Promise<void> {
    if (this.tabListBatchDepth <= 0) {
      return
    }
    this.tabListBatchDepth--
    BrowserLog.info(`endTabListBatch depth=${this.tabListBatchDepth}`)
    if (this.tabListBatchDepth === 0) {
      await this.syncPersistedFromDb()
      await AppStateSync.refreshTabs(this.getAllTabs())
    }
  }

  /** 批量模式下将新标签追加到内存列表，避免每次全表 reload */
  private appendPersistedTabInBatch(tab: TabSession): void {
    const prev = AppStorage.get<TabSession[]>(AppStorageKeys.TABS_PERSISTED) ?? []
    AppStorage.set(AppStorageKeys.TABS_PERSISTED, [...prev, tab])
  }

  /** 新增标签并同步到 AppStorage 与仓库 */

  async addTab(opts: AddTabOptions): Promise<TabSession | null> {

    await AppInitGate.whenReady()

    const incognitoFlag = opts.incognito !== undefined ?

      opts.incognito :

      IncognitoPolicy.getInstance().isIncognito()

    const partitionCount = this.getAllTabs().filter((t) => t.isIncognito === incognitoFlag).length
    if (partitionCount >= TAB_LIMIT) {
      BrowserLog.warn(`addTab rejected: incognito=${incognitoFlag} count=${partitionCount} limit=${TAB_LIMIT}`)
      BrowserStore.showTabLimitReachedToast()
      return null
    }

    BrowserLog.info(`addTab begin incognito=${incognitoFlag} allBefore=${this.getAllTabs().length}`)

    const tabInput: CreateTabSessionInput = {

      id: TabManager.nextTabId(),

      title: opts.title ?? BrowserStrings.newTab(),

      url: opts.url ?? '',

      isHome: opts.isHome ?? false,

      isIncognito: incognitoFlag,

      sortOrder: this.getAllTabs().length

    }

    const tab = createTabSession(tabInput)

    if (tab.isIncognito) {

      this.incognitoTabs = [...this.incognitoTabs, tab]

    } else {

      await TabRepository.getInstance().upsert(tab)

      if (this.tabListBatchDepth > 0) {
        this.appendPersistedTabInBatch(tab)
      } else {
        await this.syncPersistedFromDb()
      }

    }

    if (this.tabListBatchDepth === 0) {
      await AppStateSync.refreshTabs(this.getAllTabs())
    }

    const memLen = (AppStorage.get<TabSession[]>(AppStorageKeys.TABS_PERSISTED) ?? []).length

    BrowserLog.info(`addTab done id=${tab.id} allAfter=${this.getAllTabs().length} persistedMem=${memLen}`)

    return tab

  }



  /** 删除指定 ID 的标签 */
  async removeTab(id: string): Promise<void> {

    await AppInitGate.whenReady()

    const tab = this.getAllTabs().find((t) => t.id === id)

    if (!tab) {

      return

    }

    const activeId = AppStorage.get<string>(AppStorageKeys.ACTIVE_TAB) ?? ''
    const wasActive = tab.isActive || activeId === id
    const partition = this.getAllTabs()
      .filter((t) => t.isIncognito === tab.isIncognito)
      .sort((a, b) => a.sortOrder - b.sortOrder)
    const closedIndex = partition.findIndex((t) => t.id === id)
    let nextActiveId = ''
    if (wasActive && partition.length > 1 && closedIndex >= 0) {
      if (closedIndex < partition.length - 1) {
        nextActiveId = partition[closedIndex + 1].id
      } else {
        nextActiveId = partition[closedIndex - 1].id
      }
    }

    if (tab.isIncognito) {

      this.incognitoTabs = this.incognitoTabs.filter((t) => t.id !== id)
      this.purgeIncognitoWebDataIfNoTabs()

    } else {

      await TabRepository.getInstance().deleteById(id)

      await this.syncPersistedFromDb()

    }

    if (nextActiveId.length > 0) {
      BrowserLog.info(`removeTab reassign active closed=${id} next=${nextActiveId}`)
      await this.markActiveTab(nextActiveId)
      AppStorage.setOrCreate(AppStorageKeys.TABS_RETURN_TAB_ID, nextActiveId)
    } else {
      await this.clearLastActiveIfMatches(id)
    }

    await AppStateSync.refreshTabs(this.getAllTabs())

  }



  /** 关闭全部普通或无痕标签 */

  async closeAllTabs(incognito: boolean): Promise<void> {

    await AppInitGate.whenReady()

    const last = await SettingsRepository.getInstance().getLastActiveTab()

    if (incognito) {

      if (last?.incognito && this.incognitoTabs.some((t) => t.id === last.id)) {

        await this.clearLastActiveRecord()

      }

      this.incognitoTabs = []
      IncognitoWebDataCleaner.getInstance().purgeIncognitoWebData()

    } else {

      if (last && !last.incognito) {

        await this.clearLastActiveRecord()

      }

      await TabRepository.getInstance().clearNonIncognito()

      AppStorage.setOrCreate(AppStorageKeys.TABS_PERSISTED, [])

    }

    await AppStateSync.refreshTabs(this.getAllTabs())

  }



  /** 同一分区内调整标签顺序 */
  async reorderTabsInPartition(incognito: boolean, fromIndex: number, toIndex: number): Promise<void> {
    await AppInitGate.whenReady()
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0) {
      return
    }
    if (incognito) {
      const sorted = [...this.incognitoTabs].sort((a, b) => a.sortOrder - b.sortOrder)
      if (fromIndex >= sorted.length || toIndex >= sorted.length) {
        return
      }
      const ids = sorted.map((t) => t.id)
      const reordered = reorderArrayIds(ids, fromIndex, toIndex)
      const map = new Map(sorted.map((t) => [t.id, t]))
      this.incognitoTabs = reordered.map((id, i) => {
        const tab = map.get(id)!
        const updated = createTabSession({
          id: tab.id,
          title: tab.title,
          url: tab.url,
          isIncognito: tab.isIncognito,
          webState: tab.webState,
          thumbnailPath: tab.thumbnailPath,
          sortOrder: i,
          isActive: tab.isActive,
          createdAt: tab.createdAt,
          updatedAt: tab.updatedAt,
          isHome: tab.isHome,
          hideDesc: tab.hideDesc
        })
        return updated
      })
    } else {
      const sorted = (AppStorage.get<TabSession[]>(AppStorageKeys.TABS_PERSISTED) ?? [])
        .slice()
        .sort((a, b) => a.sortOrder - b.sortOrder)
      if (fromIndex >= sorted.length || toIndex >= sorted.length) {
        return
      }
      const ids = sorted.map((t) => t.id)
      const reordered = reorderArrayIds(ids, fromIndex, toIndex)
      await TabRepository.getInstance().reorderByIds(reordered)
      const map = new Map(sorted.map((t) => [t.id, t]))
      const merged = reordered.map((id, i) => {
        const tab = map.get(id)!
        return createTabSession({
          id: tab.id,
          title: tab.title,
          url: tab.url,
          isIncognito: tab.isIncognito,
          webState: tab.webState,
          thumbnailPath: tab.thumbnailPath,
          sortOrder: i,
          isActive: tab.isActive,
          createdAt: tab.createdAt,
          updatedAt: tab.updatedAt,
          isHome: tab.isHome,
          hideDesc: tab.hideDesc
        })
      })
      AppStorage.setOrCreate(AppStorageKeys.TABS_PERSISTED, merged)
    }
    AppStateSync.patchTabsQuiet(this.getAllTabs())
    BrowserLog.info(`reorderTabsInPartition incognito=${incognito} from=${fromIndex} to=${toIndex}`)
  }



  /** 当前模式下若无标签页，则新建一个主页占位标签（可指定分区，默认读持久化模式） */

  async ensureDefaultTabForCurrentMode(incognito?: boolean): Promise<void> {

    const mode = incognito !== undefined ?

      incognito :

      (AppStorage.get<boolean>(AppStorageKeys.INCOGNITO) ?? false)

    BrowserLog.info(`ensureDefaultTab mode=${mode} normal=${this.getNormalTabCount()} incognito=${this.getIncognitoTabCount()}`)

    if (mode) {

      if (this.getIncognitoTabCount() === 0) {

        const tabInput: CreateTabSessionInput = {

          id: `t${Date.now()}`,

          title: BrowserStrings.newTab(),

          url: '',

          isHome: true,

          isIncognito: true,

          sortOrder: 0

        }

        this.incognitoTabs = [...this.incognitoTabs, createTabSession(tabInput)]

        await AppStateSync.refreshTabs(this.getAllTabs())

      }

      return

    }

    if (this.getNormalTabCount() === 0) {

      await this.addTab({

        isHome: true,

        incognito: false,

        title: BrowserStrings.newTab()

      })

    }

  }



  /** 将标签页迁移到普通/无痕分区（用于浏览页切换无痕模式） */
  async migrateTabPartition(
    tabId: string,
    targetIncognito: boolean,
    patch?: BrowseTabPatch
  ): Promise<TabSession> {
    await AppInitGate.whenReady()
    const all = this.getAllTabs()
    const found = all.find((t) => t.id === tabId)
    if (!found) {
      const created = await this.addTab({
        url: patch?.url ?? '',
        title: patch?.title ?? BrowserStrings.newTab(),
        incognito: targetIncognito,
        isHome: false
      })
      if (!created) {
        throw new Error('migrateTabPartition: tab limit reached')
      }
      return created
    }
    const tab = found
    if (tab.isIncognito === targetIncognito) {
      if (patch) {
        const updated: TabSession = {
          id: tab.id,
          title: patch.title ?? tab.title,
          url: patch.url ?? tab.url,
          isIncognito: tab.isIncognito,
          webState: tab.webState,
          thumbnailPath: tab.thumbnailPath,
          sortOrder: tab.sortOrder,
          isActive: true,
          createdAt: tab.createdAt,
          updatedAt: Date.now(),
          isHome: false,
          hideDesc: tab.hideDesc
        }
        await this.updateTab(updated)
        return updated
      }
      return tab
    }
    const targetPartition = all.filter((t) => t.isIncognito === targetIncognito)
    if (tab.isIncognito !== targetIncognito && targetPartition.length >= TAB_LIMIT) {
      BrowserStore.showTabLimitReachedToast()
      return tab
    }
    let nextSort = 0
    if (targetPartition.length > 0) {
      nextSort = Math.max(...targetPartition.map((t) => t.sortOrder)) + 1
    }
    const migrated: TabSession = {
      id: tab.id,
      title: patch?.title ?? tab.title,
      url: patch?.url ?? tab.url,
      isIncognito: targetIncognito,
      webState: tab.webState,
      thumbnailPath: tab.thumbnailPath,
      sortOrder: nextSort,
      isActive: true,
      createdAt: tab.createdAt,
      updatedAt: Date.now(),
      isHome: false,
      hideDesc: tab.hideDesc
    }
    if (targetIncognito) {
      if (!tab.isIncognito) {
        await TabRepository.getInstance().deleteById(tab.id)
        await this.syncPersistedFromDb()
      }
      this.incognitoTabs = [...this.incognitoTabs.filter((t) => t.id !== tab.id), migrated]
    } else {
      this.incognitoTabs = this.incognitoTabs.filter((t) => t.id !== tab.id)
      await TabRepository.getInstance().upsert(migrated)
      await this.syncPersistedFromDb()
    }
    await AppStateSync.refreshTabs(this.getAllTabs())
    if (!targetIncognito) {
      this.purgeIncognitoWebDataIfNoTabs()
    }
    BrowserLog.info(`migrateTabPartition id=${tab.id} -> incognito=${targetIncognito} sort=${nextSort}`)
    return migrated
  }

  /** 最后一个无痕标签关闭或迁出后，清理无痕 Web 缓存 */
  private purgeIncognitoWebDataIfNoTabs(): void {
    if (this.getIncognitoTabCount() === 0) {
      IncognitoWebDataCleaner.getInstance().purgeIncognitoWebData()
    }
  }

  /** 更新标签会话信息并持久化 */

  async updateTab(session: TabSession): Promise<void> {

    await AppInitGate.whenReady()

    if (session.isIncognito) {

      this.incognitoTabs = this.incognitoTabs.map((t) => t.id === session.id ? session : t)

    } else {

      await TabRepository.getInstance().upsert(session)

      await this.syncPersistedFromDb()

    }

    await AppStateSync.refreshTabs(this.getAllTabs())

  }

  /** 记录并持久化最后活跃页签（同步 is_active 标记） */
  async markActiveTab(tabId: string): Promise<void> {
    await AppInitGate.whenReady()
    const tab = this.getAllTabs().find((t) => t.id === tabId)
    if (!tab) {
      return
    }
    BrowserLog.info(`markActiveTab id=${tabId} incognito=${tab.isIncognito}`)
    this.incognitoTabs = this.incognitoTabs.map((t) => {
      const active = t.id === tabId
      if (t.isActive === active) {
        return t
      }
      return TabManager.withActiveFlag(t, active)
    })
    if (!tab.isIncognito) {
      await TabRepository.getInstance().resetActiveFlags()
      await TabRepository.getInstance().setActiveFlag(tabId)
      await this.syncPersistedFromDb()
    }
    await SettingsRepository.getInstance().setLastActiveTab({ id: tabId, incognito: tab.isIncognito })
    AppStorage.set(AppStorageKeys.ACTIVE_TAB, tabId)
    AppStateSync.patchTabsQuiet(this.getAllTabs())
  }

  private static withActiveFlag(tab: TabSession, isActive: boolean): TabSession {
    return {
      id: tab.id,
      title: tab.title,
      url: tab.url,
      isIncognito: tab.isIncognito,
      webState: tab.webState,
      thumbnailPath: tab.thumbnailPath,
      sortOrder: tab.sortOrder,
      isActive: isActive,
      createdAt: tab.createdAt,
      updatedAt: tab.updatedAt,
      isHome: tab.isHome,
      hideDesc: tab.hideDesc
    }
  }

  private async clearLastActiveIfMatches(tabId: string): Promise<void> {
    const last = await SettingsRepository.getInstance().getLastActiveTab()
    if (last?.id === tabId) {
      await this.clearLastActiveRecord()
    }
  }

  private async clearLastActiveRecord(): Promise<void> {
    await SettingsRepository.getInstance().clearLastActiveTab()
    AppStorage.set(AppStorageKeys.ACTIVE_TAB, '')
  }

  /** 更新标签缩略图：持久化并通知 UI 刷新 */
  async applyTabThumbnail(tabId: string, thumbnailPath: string): Promise<void> {
    await AppInitGate.whenReady()
    const tab = this.getAllTabs().find((t) => t.id === tabId)
    if (!tab || !thumbnailPath) {
      return
    }
    const updated: TabSession = {
      id: tab.id,
      title: tab.title,
      url: tab.url,
      isIncognito: tab.isIncognito,
      webState: tab.webState,
      thumbnailPath: thumbnailPath,
      sortOrder: tab.sortOrder,
      isActive: tab.isActive,
      createdAt: tab.createdAt,
      updatedAt: Date.now(),
      isHome: tab.isHome,
      hideDesc: tab.hideDesc
    }
    if (updated.isIncognito) {
      this.incognitoTabs = this.incognitoTabs.map((t) => t.id === tabId ? updated : t)
    } else {
      await TabRepository.getInstance().upsert(updated)
      const persisted = AppStorage.get<TabSession[]>(AppStorageKeys.TABS_PERSISTED) ?? []
      AppStorage.setOrCreate(AppStorageKeys.TABS_PERSISTED,
        persisted.map((t) => t.id === tabId ? updated : t))
    }
    AppStateSync.notifyTabsChanged(this.getAllTabs())
    BrowserLog.info(`applyTabThumbnail tab=${tabId} path=${thumbnailPath.slice(-48)}`)
  }

}

