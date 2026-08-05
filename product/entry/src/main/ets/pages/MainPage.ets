import { BrowserNavigation } from 'browser_core'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { bindBrowserPageContext } from 'common'
import { BottomNavBar } from 'home'
import { AddShortcutSheet } from 'home'
import { FeaturePanel } from 'bookmark'
import { HomeView } from 'home'
import { ProfileView } from 'settings'
import { DownloadFlowDialog } from 'download'
import { ShareSheet } from 'settings'
import { ToastBar } from 'commons'
import { DarkModePickerDialog } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'
import { ShortcutContextMenuLayer } from 'home'
import { AppStorageKeys, ShortcutMenuOverlayState } from 'common'
import { TabThumbnailRetryService } from 'browser_core'
import { AppStateSync } from 'browser_core'
import { BrowserLog } from 'common'
import { BrowserWindowService } from 'browser_core'
import { FeaturePanelBackBridge } from 'browser_core'

/** 浏览器主页容器：主页/我的双 Tab，承载搜索、快捷方式与全局弹层 */
@Entry
@Component
struct MainPage {
  @State currentTab: number = 0
  @State isSearchMode: boolean = false
  @State showAddShortcutSheet: boolean = false
  @State shortcutMenuOverlay: ShortcutMenuOverlayState = new ShortcutMenuOverlayState()
  /** MainPage Stack 全局原点（overlay 坐标换算） */
  @State mainPageGlobalX: number = 0
  @State mainPageGlobalY: number = 0
  @StorageLink(AppStorageKeys.THEME) theme: string = 'light'
  @StorageLink(AppStorageKeys.DARK_MODE_PICKER_VISIBLE) darkModePickerVisible: boolean = false
  @StorageLink('browser_feature_panel') featurePanel: string = ''
  @StorageLink('browser_share_visible') shareVisible: boolean = false
  @StorageLink('browser_dl_dialog') dlDialog: string = ''
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_SIZE) fontSizeKey: string = 'system'
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageProp(AppStorageKeys.SAFE_AREA_BOTTOM) safeAreaBottom: number = 0

  private isDarkMode(): boolean {
    return this.theme === 'dark'
  }

  private pageBg(): string {
    return this.isDarkMode() ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  /** 根 Stack 背景：首页与渐变顶色一致（沉浸式透明状态栏下透出），其它 Tab 用页面底色 */
  private stackBg(): string {
    if (this.currentTab === 0) {
      return BrowserTheme.topEdgeColor(this.isDarkMode())
    }
    return this.pageBg()
  }

  private showBottomNav(): boolean {
    // 全屏面板 / 弹层打开时隐藏底栏，避免悬浮胶囊盖住分享、下载管理等界面
    return !this.isSearchMode
      && !this.showAddShortcutSheet
      && this.featurePanel.length === 0
      && !this.shareVisible
      && this.dlDialog.length === 0
      && !this.darkModePickerVisible
  }

  /** 先关闭弹层 / 搜索 / 快捷方式菜单，返回 true 表示已消费 */
  private dismissMainPageOverlays(): boolean {
    if (this.shareVisible) {
      BrowserStore.closeShareSheet()
      return true
    }
    if (this.dlDialog.length > 0) {
      BrowserStore.closeDownloadDialog()
      return true
    }
    if (this.featurePanel.length > 0) {
      BrowserStore.closeFeaturePanel()
      return true
    }
    if (this.showAddShortcutSheet) {
      this.showAddShortcutSheet = false
      return true
    }
    if (this.shortcutMenuOverlay.menuVisible || this.shortcutMenuOverlay.liftActive) {
      AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, 'dismiss')
      return true
    }
    if (this.isSearchMode) {
      this.isSearchMode = false
      return true
    }
    return false
  }

  onBackPress(): boolean {
    if (this.featurePanel.length > 0 && FeaturePanelBackBridge.handleBackPress()) {
      return true
    }
    if (this.dismissMainPageOverlays()) {
      return true
    }
    if (this.currentTab !== 0) {
      this.currentTab = 0
      return true
    }
    BrowserNavigation.exitApp()
    return true
  }

  aboutToAppear(): void {
    bindBrowserPageContext(this.getUIContext())
    this.resetMainPageInteractionState('aboutToAppear')
    BrowserStore.init()
  }

  onPageShow(): void {
    bindBrowserPageContext(this.getUIContext())
    // FeaturePanel 子页打开时保持可旋转，避免前后台切换把方向重新锁回竖屏
    if (this.featurePanel.length > 0) {
      BrowserWindowService.getInstance().applyOrientationForRotatablePage()
    } else {
      BrowserWindowService.getInstance().applyOrientationForMainShell()
    }
    BrowserWindowService.getInstance().setGestureBackEnabled(true)
    BrowserWindowService.getInstance().setPageSwipeBackEnabled(this.getUIContext(), true)
    BrowserWindowService.getInstance().syncAvoidArea()
    BrowserWindowService.getInstance().syncSystemBarForTheme(this.isDarkMode(), null, true)
    void BrowserStore.whenReady().then(async () => {
      await BrowserNavigation.restoreLastActiveTabOnLaunch()
    })
  }

  /** 离开主页前抓取首页标签缩略图（须用 MainPage 自身 UIContext，不能用全局 bind） */
  onPageHide(): void {
    const pageCtx = this.getUIContext()
    void BrowserStore.whenReady().then(async () => {
      const home = await BrowserStore.ensureHomeTab(BrowserStore.isIncognito())
      if (home) {
        await BrowserStore.captureHomeTabThumbnailForTab(home.id, pageCtx)
      }
    })
  }

  /** 重置弹层与快捷方式 overlay，避免全屏层拦截触摸 */
  private resetMainPageInteractionState(source: string): void {
    this.isSearchMode = false
    this.showAddShortcutSheet = false
    BrowserStore.closeShareSheet()
    BrowserStore.closeFeaturePanel()
    BrowserStore.closeDownloadDialog()
    this.shortcutMenuOverlay.liftActive = false
    this.shortcutMenuOverlay.menuVisible = false
    this.shortcutMenuOverlay.fingerOnGrid = false
    this.shortcutMenuOverlay.positionFrozen = false
    AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, 'dismiss')
    BrowserLog.info(`[MainPage] reset interaction source=${source} ` +
      `share=${this.shareVisible} panel=${this.featurePanel} dl=${this.dlDialog} ` +
      `sheet=${this.showAddShortcutSheet} search=${this.isSearchMode} menu=false lift=false`)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        HomeView({
          isSearchMode: $isSearchMode,
          showAddSheet: $showAddShortcutSheet,
          shortcutMenuOverlay: $shortcutMenuOverlay,
          mainPageGlobalX: $mainPageGlobalX,
          mainPageGlobalY: $mainPageGlobalY
        })
          .width('100%')
          .height('100%')
          .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)

        ProfileView()
          .width('100%')
          .height('100%')
          .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .height('100%')
      .key(`main-content-font-${this.fontUiRev}-${this.fontSizeKey}-${this.fontUiScale}`)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          BrowserLog.info(`[MainPage] content touch down tab=${this.currentTab}`)
        }
      })

      if (this.showBottomNav()) {
        Column() {
          Blank()
            .layoutWeight(1)
            .hitTestBehavior(HitTestMode.None)
          Row() {
            BottomNavBar({
              activeIndex: this.currentTab,
              isDark: this.isDarkMode(),
              onTabChange: (index: number) => {
                this.currentTab = index
                BrowserWindowService.getInstance().syncSystemBarForTheme(this.isDarkMode(), null, true)
                if (index === 1) {
                  void BrowserStore.whenReady().then(() => AppStateSync.refreshProfileStatsOnShow('tabSwitch'))
                }
              }
            })
          }
          .width('100%')
          .padding({ bottom: BrowserSafeAreaInsets.bottom(BrowserSafeAreaInsets.BOTTOM_NAV_EXTRA) })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.darkModePickerVisible) {
        DarkModePickerDialog({
          visible: this.darkModePickerVisible,
          onClose: (): void => {
            this.darkModePickerVisible = false
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(7000)
      }

      if (this.showAddShortcutSheet) {
        AddShortcutSheet({ visible: $showAddShortcutSheet })
          .width('100%')
          .height('100%')
          .zIndex(2000)
      }

      if (this.featurePanel.length > 0) {
        FeaturePanel()
          .width('100%')
          .height('100%')
          .zIndex(2000)
          .key(`main-feature-panel-${this.fontUiRev}-${this.fontSizeKey}-${this.fontUiScale.toFixed(2)}`)
      }

      if (this.shareVisible) {
        ShareSheet()
          .width('100%')
          .height('100%')
          .zIndex(6500)
      }

      if (this.dlDialog.length > 0) {
        DownloadFlowDialog()
          .width('100%')
          .height('100%')
          .zIndex(5200)
      }

      ToastBar()

      if (this.shortcutMenuOverlay.menuVisible && this.currentTab === 0) {
        Column()
          .width('100%')
          .height('100%')
          .backdropBlur(24)
          .backgroundColor(Color.Transparent)
          .zIndex(4990)
          .hitTestBehavior(HitTestMode.Default)
          .onClick(() => {
            AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, 'dismiss')
          })

        ShortcutContextMenuLayer({
          state: this.shortcutMenuOverlay,
          menuWidth: 144
        })
          .width('100%')
          .height('100%')
          .clip(false)
          .zIndex(5000)
      }
    }
    .width('100%')
    .height('100%')
    .id(TabThumbnailRetryService.MAIN_PAGE_SNAPSHOT_ID)
    .backgroundColor(this.stackBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_old, area) => {
      const g = area.globalPosition
      if (g) {
        this.mainPageGlobalX = g.x as number
        this.mainPageGlobalY = g.y as number
      }
    })
  }
}
