import { TextMenuController } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { BrowserLog } from 'common'
import { BrowserNavigation } from 'browser_core'
import { BrowserStore } from 'browser_core'
import { WebPageController } from 'browser_core'

/** Web 文本选择菜单：屏蔽「问问小艺」、拦截搜索走浏览器内搜索 */
export class WebTextMenuHelper {
  private static readonly ASK_AI_MENU_ID: string = 'askAI'
  /** 替换系统 SEARCH（id=8）后的自定义菜单 id，避免触发 StartAbility */
  private static readonly BROWSER_SEARCH_MENU_ID: string = 'browser_search'

  /** 初始化文本菜单策略：禁用问问小艺与系统搜索 */
  static initTextMenuPolicy(): void {
    WebTextMenuHelper.disableAskAiMenuItem()
    WebTextMenuHelper.disableSystemSearchMenuItem()
  }

  /** 全局禁用问问小艺菜单项（API 20+） */
  private static disableAskAiMenuItem(): void {
    try {
      TextMenuController.disableMenuItems([TextMenuItemId.of(WebTextMenuHelper.ASK_AI_MENU_ID)])
      BrowserLog.info('[WebTextMenu] disable askAI menu item')
    } catch (err) {
      BrowserLog.warn(`disableAskAiMenuItem failed: ${JSON.stringify(err)}`)
    }
  }

  /** 禁用系统搜索项，防止 Web 内核走 StartAbility 打开「无法打开此文件」 */
  private static disableSystemSearchMenuItem(): void {
    try {
      TextMenuController.disableMenuItems([TextMenuItemId.SEARCH])
      BrowserLog.info('[WebTextMenu] disable system SEARCH menu item')
    } catch (err) {
      BrowserLog.warn(`disableSystemSearchMenuItem failed: ${JSON.stringify(err)}`)
    }
  }

  private static isAskAiMenuItem(item: TextMenuItem): boolean {
    return item.id.equals(TextMenuItemId.of(WebTextMenuHelper.ASK_AI_MENU_ID))
  }

  private static isSearchMenuItem(item: TextMenuItem): boolean {
    return item.id.equals(TextMenuItemId.SEARCH) ||
      item.id.equals(TextMenuItemId.of(WebTextMenuHelper.BROWSER_SEARCH_MENU_ID))
  }

  /** 替换系统 SEARCH 为自定义 id，并确保菜单中始终有搜索项 */
  private static buildMenuItems(menuItems: TextMenuItem[]): TextMenuItem[] {
    let items = menuItems.filter((item) => !WebTextMenuHelper.isAskAiMenuItem(item))
    const sysSearch = items.find((item) => item.id.equals(TextMenuItemId.SEARCH))
    items = items.filter((item) => !item.id.equals(TextMenuItemId.SEARCH))
    const hasCustomSearch = items.some((item) =>
      item.id.equals(TextMenuItemId.of(WebTextMenuHelper.BROWSER_SEARCH_MENU_ID)))
    if (!hasCustomSearch) {
      items.push({
        content: sysSearch?.content ?? '搜索',
        id: TextMenuItemId.of(WebTextMenuHelper.BROWSER_SEARCH_MENU_ID),
        icon: sysSearch?.icon
      })
    }
    return items
  }

  /** 读取 Web 选中文本并在当前页打开搜索结果 */
  private static handleSearchSelection(): void {
    const webController: webview.WebviewController | null = WebPageController.getInstance().getController()
    if (!webController) {
      BrowserLog.warn('[WebTextMenu] handleSearchSelection: no web controller')
      return
    }
    const script =
      '(function(){try{var s=window.getSelection().toString();return s?s:null;}catch(e){return null;}})()'
    try {
      void webController.runJavaScriptExt(script).then((result: webview.JsMessageExt) => {
        let keyword = ''
        if (result && result.getType() === webview.JsMessageType.STRING) {
          keyword = result.getString()
        }
        WebTextMenuHelper.openSearchFromSelection(keyword)
      }).catch((err: Error) => {
        BrowserLog.warn(`handleSearchSelection failed: ${err.message}`)
      })
    } catch (err) {
      BrowserLog.warn(`handleSearchSelection execute script failed: ${JSON.stringify(err)}`)
    }
  }

  private static openSearchFromSelection(keyword: string): void {
    const q = keyword.trim()
    if (q.length === 0) {
      BrowserLog.warn('[WebTextMenu] openSearchFromSelection: empty keyword')
      return
    }
    BrowserStore.addSearchHistory(q)
    const url: string = BrowserNavigation.getSearchEngineUrl(q)
    BrowserStore.pushNavStack(url)
    const webPage: WebPageController = WebPageController.getInstance()
    if (webPage.getController()) {
      webPage.loadUrl(url)
      BrowserLog.info(`[WebTextMenu] search in current web q=${q.slice(0, 40)}`)
      return
    }
    BrowserNavigation.openSearchResults(q)
  }

  /** Web 组件 editMenuOptions：过滤问问小艺、替换系统搜索 */
  static buildEditMenuOptions(): EditMenuOptions {
    return {
      onCreateMenu: (menuItems: TextMenuItem[]): TextMenuItem[] => {
        return WebTextMenuHelper.buildMenuItems(menuItems)
      },
      onPrepareMenu: (menuItems: TextMenuItem[]): TextMenuItem[] => {
        return WebTextMenuHelper.buildMenuItems(menuItems)
      },
      onMenuItemClick: (menuItem: TextMenuItem, _range: TextRange): boolean => {
        if (WebTextMenuHelper.isSearchMenuItem(menuItem)) {
          BrowserLog.info('[WebTextMenu] intercept search menu click')
          WebTextMenuHelper.handleSearchSelection()
          return true
        }
        return false
      }
    }
  }
}
