import { AppStorageKeys, TAB_LIMIT, TAB_LIMIT_DISPLAY } from 'common'
import { BrowserLog } from 'common'
import { BrowserNavigation } from 'browser_core'
import { BrowserRouterBridge } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserStrings } from 'common'
import { TabEntry, TabsRouteParams } from 'browser_core'

/** 各分区标签数量 */
export class TabPartitionCounts {
  normal: number = 0
  incognito: number = 0
}

/** 标签页管理 ViewModel：分区切换、打开/关闭/新建标签 */
@Observed
export class TabManagementViewModel {
  isIncognitoMode: boolean = false
  showCloseAllDialog: boolean = false

  /** 从路由参数或当前无痕状态初始化分区 */
  initPartitionFromRoute(): void {
    const params = BrowserRouterBridge.getInstance().getParams() as TabsRouteParams
    if (params?.incognito === '1') {
      this.isIncognitoMode = true
    } else if (params?.incognito === '0') {
      this.isIncognitoMode = false
    } else if (BrowserStore.isIncognito()) {
      this.isIncognitoMode = true
    }
  }

  filterTabs(allTabs: TabEntry[]): TabEntry[] {
    return allTabs.filter((t) => t.isIncognito === this.isIncognitoMode)
  }

  rebuildPartitionList(allTabs: TabEntry[]): TabEntry[] {
    const list = this.filterTabs(allTabs)
    list.sort((a, b) => a.sortOrder - b.sortOrder)
    return list
  }

  countByPartition(allTabs: TabEntry[]): TabPartitionCounts {
    const counts = new TabPartitionCounts()
    for (const tab of allTabs) {
      if (tab.isIncognito) {
        counts.incognito++
      } else {
        counts.normal++
      }
    }
    return counts
  }

  switchTabPartition(incognito: boolean): void {
    BrowserLog.info(`switchTabPartition incognito=${incognito}`)
    this.isIncognitoMode = incognito
    void BrowserStore.setIncognitoSilent(incognito)
  }

  openTab(tab: TabEntry): void {
    AppStorage.setOrCreate(AppStorageKeys.TABS_RETURN_TAB_ID, tab.id)
    AppStorage.set(AppStorageKeys.INCOGNITO, tab.isIncognito)
    AppStorage.set(AppStorageKeys.BROWSE_INCOGNITO, tab.isIncognito)
    if (tab.isHome || !tab.url) {
      BrowserNavigation.goHome()
    } else {
      BrowserNavigation.navigateToTabSession(tab)
    }
    void BrowserStore.whenReady().then(() => {
      void BrowserStore.setIncognitoSilent(tab.isIncognito)
      void BrowserStore.markActiveTab(tab.id)
    })
  }

  closeTab(tabId: string): Promise<void> {
    BrowserLog.info(`[TabManagement] closeTab tabId=${tabId}`)
    return BrowserStore.removeTabById(tabId)
  }

  handleCloseAll(): void {
    const incognito = this.isIncognitoMode
    this.showCloseAllDialog = false
    BrowserLog.info(`handleCloseAllTabs begin incognito=${incognito}`)
    BrowserNavigation.closeAllTabsAndGoHome(incognito)
  }

  handleNewTab(): boolean {
    const incognito = this.isIncognitoMode
    if (!BrowserNavigation.canEnqueueWindowTab(incognito)) {
      if (BrowserStore.isTabPartitionFull(incognito) && !BrowserNavigation.isWindowTabCreateBusy()) {
        BrowserStore.showTabLimitReachedToast()
      }
      BrowserLog.warn(`handleNewTab rejected: busy=${BrowserNavigation.isWindowTabCreateBusy()} limit=${TAB_LIMIT}`)
      return false
    }
    BrowserNavigation.leaveTabsThenCreateWindowTab(incognito)
    return true
  }

  handleBack(): void {
    BrowserLog.info(`handleBack partitionIncognito=${this.isIncognitoMode}`)
    BrowserNavigation.returnFromTabsManager(this.isIncognitoMode)
  }

  canCloseAllTabs(partitionCount: number): boolean {
    return partitionCount > 0
  }

  canNewTab(): boolean {
    return BrowserNavigation.canEnqueueWindowTab(this.isIncognitoMode)
  }

  newTabLabel(): string {
    return this.isIncognitoMode ?
      BrowserStrings.txt($r('app.string.new_incognito_window')) :
      BrowserStrings.txt($r('app.string.new_window'))
  }

  displayTabCount(count: number): number {
    return Math.min(count, TAB_LIMIT_DISPLAY)
  }

  reorderTabs(from: number, to: number): void {
    void BrowserStore.reorderTabs(this.isIncognitoMode, from, to)
    BrowserLog.info(`[TabManagement] reorder from=${from} to=${to} incognito=${this.isIncognitoMode}`)
  }
}
