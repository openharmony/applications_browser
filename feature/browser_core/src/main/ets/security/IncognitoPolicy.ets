import { BrowserLog } from 'common'
import { BrowserUtils } from 'common'
import { SettingsRepository } from 'common'
import { HistoryRepository } from 'common'
import { CreateHistoryEntryInput, createHistoryEntry } from 'common'
import { AppStateSync } from '../AppStateSync'

/** 无痕写入拦截；Web 缓存/cookie 清理由 IncognitoWebDataCleaner 在标签关闭与应用退出时执行 */
export class IncognitoPolicy {
  private static instance: IncognitoPolicy | null = null

  /** 获取 IncognitoPolicy 单例 */
  static getInstance(): IncognitoPolicy {
    if (IncognitoPolicy.instance === null) {
      IncognitoPolicy.instance = new IncognitoPolicy()
    }
    return IncognitoPolicy.instance
  }

  /** 判断当前是否为无痕浏览模式 */
  isIncognito(): boolean {
    return AppStorage.get<boolean>('browser_incognito') ?? false
  }

  /** 切换无痕模式并持久化设置 */
  async setIncognito(on: boolean): Promise<void> {
    await SettingsRepository.getInstance().saveSettings({ incognitoMode: on })
    await AppStateSync.refreshSettings()
  }

  /** 无痕模式下跳过历史写入 */
  async recordHistoryIfAllowed(title: string, url: string): Promise<void> {
    if (this.isIncognito()) {
      BrowserLog.info(`[History] skip incognito url=${url}`)
      return
    }
    if (!BrowserUtils.isRecordableHistoryUrl(url)) {
      BrowserLog.warn(`[History] skip invalid url=${url}`)
      return
    }
    try {
      const safeTitle = BrowserUtils.historyDisplayTitle(title || url, url)
      const historyInput: CreateHistoryEntryInput = { title: safeTitle, url }
      await HistoryRepository.getInstance().insert(createHistoryEntry(historyInput))
      await AppStateSync.refreshHistory()
      BrowserLog.info(`[History] recorded url=${url} title=${safeTitle}`)
    } catch (err) {
      BrowserLog.error(`[History] record failed url=${url}: ${JSON.stringify(err)}`)
    }
  }

  /** 无痕模式下跳过；仅更新当天记录的标题，不新增、不改访问时间 */
  async updateHistoryTitleIfAllowed(url: string, title: string): Promise<void> {
    if (this.isIncognito() || !BrowserUtils.isRecordableHistoryUrl(url)) {
      return
    }
    try {
      await HistoryRepository.getInstance().updateTitleForUrl(url, title)
      await AppStateSync.refreshHistory()
    } catch (err) {
      BrowserLog.error(`[History] update title failed url=${url}: ${JSON.stringify(err)}`)
    }
  }

  /** 无痕模式下跳过；更新当天记录的站点图标 */
  async updateHistoryIconIfAllowed(url: string, iconUrl: string): Promise<void> {
    if (this.isIncognito() || !BrowserUtils.isRecordableHistoryUrl(url)) {
      return
    }
    try {
      await HistoryRepository.getInstance().updateIconForUrl(url, iconUrl)
      await AppStateSync.refreshHistory()
      BrowserLog.info(`[History] icon updated url=${url}`)
    } catch (err) {
      BrowserLog.error(`[History] update icon failed url=${url}: ${JSON.stringify(err)}`)
    }
  }

  /** 无痕模式下跳过搜索历史 */
  async recordSearchIfAllowed(keyword: string): Promise<void> {
    if (this.isIncognito()) {
      return
    }
    const q = keyword.trim()
    if (!q) {
      return
    }
    const repo = SettingsRepository.getInstance()
    const list = (await repo.getSearchHistory()).filter((x) => x !== q)
    list.unshift(q)
    await repo.setSearchHistory(list.slice(0, 20))
    await AppStateSync.refreshSettings()
  }

  /** 无痕模式下禁用 Web 自动填充（密码保险箱、选择账号等） */
  allowsWebAutoFill(): boolean {
    return !this.isIncognito()
  }
}
