import { AppStorageKeys } from 'common'
import { BrowserTheme } from 'browser_core'
import { bindBrowserPageContext } from 'common'
import { BrowserWindowService } from 'browser_core'
import { TabsPageView } from 'tab'

/** 标签管理路由入口 */
@Entry
@Component
struct TabsPage {
  @StorageLink(AppStorageKeys.THEME) theme: string = 'light'
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0

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
    BrowserWindowService.getInstance().syncAvoidArea()
    BrowserWindowService.getInstance().syncSystemBarForTheme(this.theme === 'dark', null, true)
  }

  build() {
    Column() {
      TabsPageView()
    }
    .width('100%')
    .height('100%')
    .key(`tabs-page-font-${this.fontUiRev}`)
    .backgroundColor(this.pageBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
