import { BrowserNavigation } from 'browser_core'
import { BrowserStore } from 'browser_core'

/** 搜索模块 ViewModel：地址栏搜索与历史记录 */
@Observed
export class SearchViewModel {
  query: string = ''

  navigate(input: string): void {
    const trimmed = input.trim()
    if (trimmed.length === 0) {
      return
    }
    BrowserNavigation.searchOrNavigate(trimmed)
  }

  async recordKeyword(keyword: string): Promise<void> {
    await BrowserStore.addSearchHistory(keyword)
  }
}
