import { BrowserStrings } from 'common'
import { BrowserLog } from 'common'
import { getBrowserContext } from 'common'
import { BrowserRouterBridge } from 'common'
import {
  AddTabOptions,
  BrowseRouteParams,
  getSearchEngineBase,
  OpenBrowseOptions,
  TabsRouteParams,
  tabHostname,
  TabEntry,
  TAB_LIMIT
} from './BrowserModels'
import { BrowserStore } from './BrowserStore'
import { BrowserUtils } from 'common'
import { AppStorageKeys } from 'common'
import { IncognitoPolicy } from './security/IncognitoPolicy'
import { TabManager } from './tab/TabManager'

/** URL 输入校验结果 */
export interface UrlValidation {
  /** 是否通过校验 */
  ok: boolean
  /** 规范化后的 URL */
  url?: string
  /** 校验失败时的提示消息 */
  message?: string
}

/** 地址栏输入截断结果 */
export interface AddressInputClampResult {
  text: string
  /** 是否因超长被截断 */
  truncated: boolean
}

/** 页面路由与 URL 导航工具类（经 BrowserRouterBridge 调用 UIContext Router） */
export class BrowserNavigation {
  private static launchRestoreDone: boolean = false
  private static pendingExternalUrl: string = ''
  /** 外部本地文件预览时的展示标题 */
  private static pendingExternalTitle: string = ''
  /** pendingExternalUrl 是否为待复制的外部 file URI（尚未转沙箱） */
  private static pendingExternalIsFile: boolean = false
  /** 新建窗口串行锁，防止连点并发写库/路由 */
  private static windowTabCreating: boolean = false
  private static windowTabCreateQueue: boolean[] = []
  /** 标签管理页路由进行中 / 短冷却，防止底部导航连点叠两层 TabsPage */
  private static tabsPagePushing: boolean = false
  private static tabsPageOpenUntil: number = 0
  private static readonly TABS_PAGE_OPEN_COOLDOWN_MS: number = 450
  /** 全局 TextInput 最大输入长度 */
  static readonly INPUT_MAX_LENGTH: number = 2048
  /** 地址栏 URL 最大输入长度（与 INPUT_MAX_LENGTH 一致） */
  static readonly URL_MAX_LENGTH: number = BrowserNavigation.INPUT_MAX_LENGTH

  /** 搜索/网址跳转前规范化：删除全部空白字符（含首尾与中间） */
  static normalizeNavigateInput(input: string): string {
    return input.replace(/\s+/g, '')
  }

  /** 截断超长输入；粘贴或输入导致 length > max 时始终 truncated=true */
  static clampTextInput(value: string, _previousLength: number = 0): AddressInputClampResult {
    const max = BrowserNavigation.INPUT_MAX_LENGTH
    if (value.length <= max) {
      return { text: value, truncated: false }
    }
    return {
      text: value.slice(0, max),
      truncated: true,
    }
  }

  /** 截断超长地址栏输入（委托 clampTextInput） */
  static clampAddressInput(value: string, previousLength: number = 0): AddressInputClampResult {
    return BrowserNavigation.clampTextInput(value, previousLength)
  }

  /**
   * TextInput onChange 统一处理：截断超长并 Toast。
   * @param isUrlField true 时使用网址过长文案，否则使用通用输入过长文案
   */
  static applyTextInputChange(
    value: string,
    previousLength: number,
    apply: (text: string) => void,
    isUrlField: boolean = false
  ): void {
    const clamped = BrowserNavigation.clampTextInput(value, previousLength)
    if (clamped.truncated) {
      BrowserStore.showToast(isUrlField ? BrowserStrings.urlTooLong() : BrowserStrings.inputTooLong())
    }
    apply(clamped.text)
  }

  /** 页签管理「新建窗口」是否仍在处理（含队列中待创建数量） */
  static isWindowTabCreateBusy(): boolean {
    return BrowserNavigation.windowTabCreating || BrowserNavigation.windowTabCreateQueue.length > 0
  }

  /** 是否正在打开或刚打开标签管理页（用于 UI 禁用连点） */
  static isTabsPageNavBusy(): boolean {
    return BrowserNavigation.tabsPagePushing || Date.now() < BrowserNavigation.tabsPageOpenUntil
  }

  /** 当前分区是否还可继续入队新建窗口 */
  static canEnqueueWindowTab(incognito: boolean): boolean {
    const count = BrowserStore.getTabs().filter((t) => t.isIncognito === incognito).length
    const pending = BrowserNavigation.windowTabCreateQueue.filter((m) => m === incognito).length
    return count + pending < TAB_LIMIT
  }

  private static delayMs(ms: number): Promise<void> {
    return new Promise((resolve) => {
      setTimeout(() => resolve(), ms)
    })
  }
  private static router(): BrowserRouterBridge {
    return BrowserRouterBridge.getInstance()
  }

  /** 先离开页签管理页回到首页，再在后台新建主页占位页签（避免网格闪出新卡片） */
  static leaveTabsThenCreateWindowTab(incognito: boolean): void {
    if (!BrowserNavigation.canEnqueueWindowTab(incognito)) {
      if (BrowserStore.isTabPartitionFull(incognito)) {
        BrowserStore.showTabLimitReachedToast()
      }
      BrowserLog.warn(`leaveTabsThenCreateWindowTab rejected: incognito=${incognito} limit=${TAB_LIMIT}`)
      return
    }
    BrowserNavigation.windowTabCreateQueue.push(incognito)
    BrowserLog.info(`leaveTabsThenCreateWindowTab enqueue incognito=${incognito} pending=${BrowserNavigation.windowTabCreateQueue.length}`)
    void BrowserNavigation.drainWindowTabCreateQueue()
  }

  /** 串行消费新建窗口队列：只导航一次，批量写库后统一刷新列表 */
  private static async drainWindowTabCreateQueue(): Promise<void> {
    if (BrowserNavigation.windowTabCreating) {
      return
    }
    if (BrowserNavigation.windowTabCreateQueue.length === 0) {
      return
    }
    BrowserNavigation.windowTabCreating = true
    let lastTabId = ''
    let createdCount = 0
    try {
      await BrowserStore.whenReady()
      await BrowserNavigation.router().replaceUrl('pages/MainPage')
      await TabManager.getInstance().beginTabListBatch()
      try {
        while (BrowserNavigation.windowTabCreateQueue.length > 0) {
          const incognito = BrowserNavigation.windowTabCreateQueue.shift()!
          const partitionCount = BrowserStore.getTabs().filter((t) => t.isIncognito === incognito).length
          if (partitionCount >= TAB_LIMIT) {
            BrowserLog.warn(`drainWindowTabCreate skip: count=${partitionCount} limit=${TAB_LIMIT}`)
            continue
          }
          await BrowserStore.setIncognitoSilent(incognito)
          const tab = await BrowserStore.createWindowTab(incognito)
          lastTabId = tab.id
          createdCount++
          BrowserLog.info(`drainWindowTabCreate id=${tab.id} created=${createdCount} remaining=${BrowserNavigation.windowTabCreateQueue.length}`)
          // 连续大量创建时周期性让出主线程，降低 LIFECYCLE_TIMEOUT / OOM 风险
          if (createdCount % 8 === 0) {
            await BrowserNavigation.delayMs(16)
          }
        }
      } finally {
        await TabManager.getInstance().endTabListBatch()
      }
      if (lastTabId.length > 0) {
        void BrowserStore.markActiveTab(lastTabId)
      }
      BrowserLog.info(`drainWindowTabCreate done total=${createdCount} last=${lastTabId}`)
    } catch (err) {
      BrowserLog.error(`drainWindowTabCreate failed: ${JSON.stringify(err)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.new_tab_failed')))
    } finally {
      BrowserNavigation.windowTabCreating = false
      if (BrowserNavigation.windowTabCreateQueue.length > 0) {
        void BrowserNavigation.drainWindowTabCreateQueue()
      }
    }
  }

  /** 关闭当前分区全部标签 → 回主页并补建一个主页占位页签 */
  static closeAllTabsAndGoHome(incognito: boolean): void {
    BrowserLog.info(`closeAllTabsAndGoHome begin incognito=${incognito}`)
    void BrowserStore.closeAllTabs(incognito).then(() => {
      BrowserLog.info(`closeAllTabsAndGoHome closed partition incognito=${incognito}`)
      BrowserNavigation.leaveTabsThenCreateWindowTab(incognito)
    }).catch((err: Error) => {
      BrowserLog.error(`closeAllTabsAndGoHome failed: ${JSON.stringify(err)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.new_tab_failed')))
    })
  }

  /** 从页签管理页返回：先跳转，再后台持久化活跃页签 */
  static returnFromTabsManager(partitionIncognito: boolean): void {
    BrowserLog.info(`returnFromTabsManager partitionIncognito=${partitionIncognito}`)
    AppStorage.set(AppStorageKeys.INCOGNITO, partitionIncognito)
    AppStorage.set(AppStorageKeys.BROWSE_INCOGNITO, partitionIncognito)
    void IncognitoPolicy.getInstance().setIncognito(partitionIncognito)

    const partitionTabs = BrowserStore.getTabs().filter((t) => t.isIncognito === partitionIncognito)
    if (partitionTabs.length === 0) {
      BrowserLog.info('returnFromTabsManager empty partition -> leaveTabsThenCreateWindowTab')
      BrowserNavigation.leaveTabsThenCreateWindowTab(partitionIncognito)
      return
    }

    const returnId = AppStorage.get<string>(AppStorageKeys.TABS_RETURN_TAB_ID) ?? ''
    let target: TabEntry | undefined = undefined
    if (returnId.length > 0) {
      target = partitionTabs.find((t) => t.id === returnId)
    }
    if (!target) {
      const last = BrowserStore.resolveLastActiveTab()
      if (last && partitionTabs.some((t) => t.id === last.id)) {
        target = last
      }
    }
    if (!target) {
      target = partitionTabs.find((t) => t.isActive) ?? partitionTabs[partitionTabs.length - 1]
    }
    if (!target) {
      BrowserNavigation.leaveTabsThenCreateWindowTab(partitionIncognito)
      return
    }

    const resolvedTab = target
    const snapshotStillValid = returnId.length > 0 && returnId === resolvedTab.id
    if (snapshotStillValid) {
      BrowserLog.info(`returnFromTabsManager router.back tab=${resolvedTab.id}`)
      BrowserNavigation.router().back()
    } else {
      BrowserLog.info(`returnFromTabsManager replace navigate tab=${resolvedTab.id} home=${resolvedTab.isHome}`)
      BrowserNavigation.navigateToTabSession(resolvedTab)
    }

    void BrowserStore.whenReady().then(() => {
      void BrowserStore.setIncognitoSilent(resolvedTab.isIncognito)
      void BrowserStore.markActiveTab(resolvedTab.id)
    })
  }

  /** @deprecated 请使用 returnFromTabsManager */
  static openLastActiveTabOrHome(): void {
    BrowserNavigation.returnFromTabsManager(BrowserStore.isIncognito())
  }

  /** 按页签会话跳转（replace，避免重复压栈） */
  static navigateToTabSession(tab: TabEntry): void {
    if (tab.isHome || !tab.url.trim()) {
      BrowserNavigation.goHome()
      return
    }
    const routeParams: BrowseRouteParams = {
      url: tab.url,
      skipNav: '1',
      tabId: tab.id
    }
    BrowserNavigation.router().replaceUrl('pages/BrowsePage', routeParams)
  }

  /** 冷启动后首次进入主页：最后活跃为主页则保持；否则补建主页页签并打开主页 */
  static async restoreLastActiveTabOnLaunch(): Promise<void> {
    if (BrowserNavigation.launchRestoreDone) {
      return
    }
    BrowserNavigation.launchRestoreDone = true
    await BrowserStore.whenReady()
    const tab = BrowserStore.resolveLastActiveTab()
    if (!tab) {
      BrowserLog.info('restoreLastActiveTabOnLaunch no record, ensure home')
      await BrowserStore.setIncognitoSilent(false)
      const home = await BrowserStore.ensureHomeTab(false)
      if (home) {
        await BrowserStore.markActiveTab(home.id)
      }
    } else {
      await BrowserStore.setIncognitoSilent(tab.isIncognito)
      if (tab.isHome || !tab.url.trim()) {
        BrowserLog.info(`restoreLastActiveTabOnLaunch last is home tab=${tab.id}`)
        void BrowserStore.markActiveTab(tab.id)
      } else {
        BrowserLog.info(`restoreLastActiveTabOnLaunch last is browse tab=${tab.id}, ensure home and open`)
        const home = await BrowserStore.ensureHomeTab(tab.isIncognito)
        if (home) {
          await BrowserStore.markActiveTab(home.id)
        }
      }
    }
    BrowserNavigation.consumePendingExternalUrl()
  }

  /**
   * 登记外部 Want 带来的链接（http(s) 或本地 file://）。
   * 冷启动：等 restoreLastActiveTabOnLaunch 结束后打开；热启动：立即打开。
   */
  static queueExternalBrowseUrl(rawUri: string): void {
    const uri = rawUri.trim()
    if (!uri) {
      return
    }
    const lower = uri.toLowerCase()
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      BrowserNavigation.enqueueExternalUrl(uri, '', false)
      return
    }
    if (lower.startsWith('file://') || lower.startsWith('datashare://') || uri.startsWith('/')) {
      const fileName = BrowserUtils.localFileDisplayName(uri)
      if (!BrowserUtils.canPreviewInBrowser(fileName) && !BrowserUtils.canPreviewInBrowserUrl(uri)) {
        BrowserLog.warn(`[ExternalWant] unsupported local file uri=${uri.slice(0, 120)}`)
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
        return
      }
      BrowserNavigation.enqueueExternalUrl(uri, fileName, true)
      return
    }
    BrowserLog.warn(`[ExternalWant] ignore unsupported uri=${uri.slice(0, 80)}`)
  }

  private static enqueueExternalUrl(uri: string, title: string, isFile: boolean): void {
    BrowserNavigation.pendingExternalUrl = uri
    BrowserNavigation.pendingExternalTitle = title
    BrowserNavigation.pendingExternalIsFile = isFile
    BrowserLog.info(
      `[ExternalWant] queued uri=${uri.slice(0, 120)} file=${isFile} restoreDone=${BrowserNavigation.launchRestoreDone}`)
    if (BrowserNavigation.launchRestoreDone) {
      BrowserNavigation.consumePendingExternalUrl()
    }
  }

  /** 消费待打开的外部链接，打开浏览页 */
  static consumePendingExternalUrl(): void {
    const uri = BrowserNavigation.pendingExternalUrl.trim()
    if (!uri) {
      return
    }
    const title = BrowserNavigation.pendingExternalTitle.trim()
    const isFile = BrowserNavigation.pendingExternalIsFile
    BrowserNavigation.pendingExternalUrl = ''
    BrowserNavigation.pendingExternalTitle = ''
    BrowserNavigation.pendingExternalIsFile = false
    BrowserLog.info(`[ExternalWant] open uri=${uri.slice(0, 120)} title=${title} file=${isFile}`)
    if (isFile) {
      void BrowserStore.openExternalLocalFile(uri, title)
      return
    }
    BrowserNavigation.openBrowse(uri, {
      preferHomeTab: true,
      title: title.length > 0 ? title : undefined
    })
  }

  /** 校验用户输入的 URL 格式，并规范化为 https 前缀 */
  static validateUrlInput(input: string): UrlValidation {
    let q = BrowserNavigation.normalizeNavigateInput(input)
    if (!q) {
      return { ok: false, message: BrowserStrings.urlInputRequired() }
    }
    if (!/^(https?:\/\/|www\.)/i.test(q) && !/^[\w.-]+\.(com|cn|net|org|io|gov|edu)/i.test(q)) {
      return { ok: false, message: BrowserStrings.urlFormatInvalid() }
    }
    if (!/^https?:\/\//i.test(q)) {
      q = `https://${q}`
    }
    if (q.length > BrowserNavigation.URL_MAX_LENGTH) {
      return { ok: false, message: BrowserStrings.urlTooLong() }
    }
    return { ok: true, url: q }
  }

  /** 根据输入判断为 URL 或搜索词，分别跳转浏览页或搜索结果页 */
  static searchOrNavigate(input: string, opts?: OpenBrowseOptions): void {
    const q = BrowserNavigation.normalizeNavigateInput(input)
    if (!q) {
      return
    }
    const isUrl = /^(https?:\/\/|www\.)/i.test(q) || /^[\w.-]+\.(com|cn|net|org|io|gov|edu)/i.test(q)
    if (isUrl) {
      const check = BrowserNavigation.validateUrlInput(q)
      if (!check.ok || !check.url) {
        BrowserStore.showToast(check.message ?? BrowserStrings.urlFormatInvalid())
        return
      }
      BrowserNavigation.openBrowse(check.url, opts)
    } else {
      BrowserStore.addSearchHistory(q)
      BrowserNavigation.openSearchResults(q, opts)
    }
  }

  /** 打开浏览页，可选记录导航栈、新建标签并写入历史 */
  static openBrowse(url: string, opts?: OpenBrowseOptions): void {
    if (opts?.preferHomeTab) {
      BrowserNavigation.openBrowseFromHome(url, opts)
      return
    }
    const u = BrowserUtils.resolveBrowseUrl(url || 'https://www.baidu.com')
    if (!opts?.skipNav) {
      BrowserStore.pushNavStack(u)
    }
    if (opts?.newTab) {
      const tabOpts: AddTabOptions = {
        url: u,
        title: opts.title ?? tabHostname(u),
      }
      void BrowserStore.addTabEntry(tabOpts).then((tab) => {
        if (!tab) {
          return
        }
        BrowserNavigation.navigateBrowse(u, tab.id, opts)
      })
      return
    }
    void BrowserStore.resolveBrowseTabId(u, BrowserStore.isIncognito(), false, opts?.tabId).then((tabId) => {
      BrowserNavigation.navigateBrowse(u, tabId, opts)
    })
  }

  /** 携带标签 ID 跳转浏览页（历史在页面加载完成后写入） */
  static navigateBrowse(url: string, tabId: string, opts?: OpenBrowseOptions): void {
    const routeParams: BrowseRouteParams = {
      url: url,
      skipNav: opts?.skipNav ? '1' : '0',
      tabId: tabId
    }
    BrowserNavigation.router().pushUrl('pages/BrowsePage', routeParams)
  }

  /** 从首页快捷方式/搜索栏打开：绑定主页占位标签，不新建网页标签 */
  static openBrowseFromHome(url: string, opts?: OpenBrowseOptions): void {
    const u = BrowserUtils.resolveBrowseUrl(url || 'https://www.baidu.com')
    if (!opts?.skipNav) {
      BrowserStore.pushNavStack(u)
    }
    void BrowserStore.whenReady().then(async () => {
      const incognito = BrowserStore.isIncognito()
      const tabId = await BrowserStore.resolveHomeBrowseTabId(incognito)
      if (!tabId) {
        BrowserLog.warn('openBrowseFromHome no tabId')
        return
      }
      BrowserLog.info(`openBrowseFromHome tabId=${tabId} url=${u.slice(0, 80)}`)
      const navOpts: OpenBrowseOptions = {
        skipNav: true,
        title: opts?.title,
        tabId: opts?.tabId
      }
      BrowserNavigation.navigateBrowse(u, tabId, navOpts)
    })
  }

  /** 使用当前搜索引擎打开关键词搜索结果（对齐测试用例 Search_002） */
  static openSearchResults(query: string, opts?: OpenBrowseOptions): void {
    const q = BrowserNavigation.normalizeNavigateInput(query)
    if (!q) {
      return
    }
    BrowserNavigation.openBrowse(BrowserNavigation.getSearchEngineUrl(q), opts)
  }

  /** 跳转到标签管理页：立即 push，不等待 init/截图 */
  static openTabs(incognitoMode?: boolean): void {
    if (BrowserNavigation.isTabsPageNavBusy()) {
      BrowserLog.info('openTabs skip duplicate')
      return
    }
    BrowserNavigation.tabsPagePushing = true
    const activeId = AppStorage.get<string>(AppStorageKeys.ACTIVE_TAB) ?? ''
    AppStorage.setOrCreate(AppStorageKeys.TABS_RETURN_TAB_ID, activeId)
    BrowserNavigation.pushTabsPage(incognitoMode)
  }

  private static finishTabsPagePush(): void {
    BrowserNavigation.tabsPagePushing = false
    BrowserNavigation.tabsPageOpenUntil = Date.now() + BrowserNavigation.TABS_PAGE_OPEN_COOLDOWN_MS
  }

  private static pushTabsPage(incognitoMode?: boolean): void {
    if (incognitoMode === undefined) {
      BrowserNavigation.router().pushUrl('pages/TabsPage').then(() => {
        BrowserLog.info('openTabs pushUrl ok')
        BrowserNavigation.finishTabsPagePush()
      }).catch((err: Error) => {
        BrowserLog.error(`openTabs pushUrl failed: ${JSON.stringify(err)}`)
        BrowserNavigation.finishTabsPagePush()
      })
      return
    }
    const routeParams: TabsRouteParams = { incognito: incognitoMode ? '1' : '0' }
    BrowserNavigation.router().pushUrl('pages/TabsPage', routeParams).then(() => {
      BrowserLog.info('openTabs pushUrl ok with partition')
      BrowserNavigation.finishTabsPagePush()
    }).catch((err: Error) => {
      BrowserLog.error(`openTabs pushUrl failed: ${JSON.stringify(err)}`)
      BrowserNavigation.finishTabsPagePush()
    })
  }

  /** 是否可从 BrowsePage pop 回 MainPage（仅浏览页侧滑返回使用，避免 TabsPage 误 back 退出桌面） */
  static canPopBrowsePageToMain(): boolean {
    try {
      const router = BrowserNavigation.router()
      if (!router.canGoBack()) {
        return false
      }
      const page = router.getCurrentPageName()
      return page.includes('BrowsePage')
    } catch (_err) {
      return false
    }
  }

  /** 返回首页（MainPage）：统一 replace，避免 TabsPage 等场景 router.back 触发 ExitToDesktop */
  static goHome(): void {
    BrowserLog.info('goHome begin replaceUrl')
    BrowserNavigation.router().replaceUrl('pages/MainPage')
    void BrowserStore.whenReady().then(() => {
      void BrowserStore.activateHomeTabForUi()
    })
  }

  /** 路由后退一页 */
  static goBack(): void {
    BrowserNavigation.router().back()
  }

  /** 退出浏览器应用（主页边缘滑动 / 返回键） */
  static exitApp(): void {
    const ctx = getBrowserContext()
    if (ctx !== null) {
      ctx.terminateSelf()
    }
  }

  /** 根据当前搜索引擎生成完整搜索 URL */
  static getSearchEngineUrl(query: string): string {
    const engine = BrowserStore.getSearchEngine()
    const base = getSearchEngineBase(engine)
    return `${base}${encodeURIComponent(query)}`
  }
}
