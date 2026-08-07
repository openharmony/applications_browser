import { AppStorageKeys } from 'common'
import { BrowserTheme } from 'browser_core'
import { bindBrowserPageContext } from 'common'
import { BrowseBackBridge } from 'browser_core'
import { BrowserWindowService } from 'browser_core'
import { BrowsePageView } from 'web'

/** 网页浏览路由入口 */
@Entry
@Component
struct BrowsePage {
  @StorageLink(AppStorageKeys.THEME) theme: string = 'light'

  private pageBg(): string {
    return this.theme === 'dark' ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  aboutToAppear(): void {
    bindBrowserPageContext(this.getUIContext())
  }

  onPageShow(): void {
    bindBrowserPageContext(this.getUIContext())
    BrowserWindowService.getInstance().applyOrientationForRotatablePage()
    BrowserWindowService.getInstance().setGestureBackEnabled(true)
    BrowserWindowService.getInstance().setPageSwipeBackEnabled(this.getUIContext(), true)
    BrowserWindowService.getInstance().ensureWindowSizeSynced()
    BrowserWindowService.getInstance().syncAvoidArea()
    BrowserWindowService.getInstance().syncSystemBarForTheme(this.theme === 'dark', null, true)
  }

  /** 系统导航条返回 / 侧滑返回：与工具栏后退共用 BrowsePageView 后退逻辑 */
  onBackPress(): boolean {
    if (BrowseBackBridge.handleBackPress()) {
      return true
    }
    return false
  }

  build() {
    Column() {
      BrowsePageView()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
