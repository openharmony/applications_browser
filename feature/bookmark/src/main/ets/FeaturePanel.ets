import { bundleManager } from '@kit.AbilityKit'
import { BrowserStore } from 'browser_core'
import { AppStorageKeys } from 'common'
import { BrowserTheme } from 'browser_core'
import { BrowserStrings } from 'common'
import { FeaturePanelType } from 'browser_core'
import { SitePermissionId, SitePermissionPolicy, SitePermissionsMap, DEFAULT_SITE_PERMISSIONS, AppSystemPermissionId } from 'common'
import { WebPermissionGate } from 'browser_core'
import { AppPermissionService } from 'browser_core'
import { LocationWarmupService } from 'browser_core'
import { BrowserLog } from 'common'
import { BookmarksPanel } from './BookmarksPanel'
import { DownloadsPanel } from 'download'
import { HistoryPanel } from './HistoryPanel'
import { PanelConfirmDialog } from 'commons'
import { PanelSubpageHeader } from 'commons'
import { SettingsInlinePicker, SettingsPickOption } from 'commons'
import { BrowseSettingsSection } from './BrowseSettingsSection'
import { NavChevronRight } from 'commons'

@Component
export struct FeaturePanel {
  @StorageLink('browser_feature_panel') panelType: FeaturePanelType = ''
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageLink('browser_image_less') imageLessMode: boolean = false
  @State settingsView: string = 'main'
  @State fontSize: string = 'system'
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_SIZE) @Watch('onFontSizeStorageChanged') fontSizeStorage: string = 'system'
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageLink(AppStorageKeys.SYSTEM_FONT_SIZE_SCALE) systemFontScale: number = 1
  @State searchEngine: string = 'baidu'
  @State sitePerms: SitePermissionsMap = DEFAULT_SITE_PERMISSIONS
  @State showClearDataConfirm: boolean = false
  @State appVersion: string = ''
  @State appPermRev: number = 0

  aboutToAppear(): void {
    this.fontSize = BrowserStore.getFontSize()
    this.fontSize = BrowserStrings.normalizeFontSizeKey(this.fontSize)
    this.searchEngine = BrowserStore.getSearchEngine()
    this.sitePerms = BrowserStore.getSitePermissions()
    this.loadAppVersion()
  }

  private async loadAppVersion(): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      this.appVersion = info.versionName
    } catch (e) {
      BrowserLog.warn(`[About] loadAppVersion failed: ${JSON.stringify(e)}`)
    }
  }

  private close(): void {
    this.settingsView = 'main'
    BrowserStore.closeFeaturePanel()
  }

  /** AppStorage 字体档位变更时同步 Select 展示 */
  private onFontSizeStorageChanged(): void {
    this.fontSize = BrowserStrings.normalizeFontSizeKey(this.fontSizeStorage)
  }

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private pageBg(): string {
    return this.isDark() ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  private cardBg(): string {
    return this.isDark() ? BrowserTheme.DARK_PANEL_BG : BrowserTheme.LIGHT_PANEL_BG
  }

  /** 书签/历史/下载全屏列表：整页白底，避免底部 safe area 露出灰色 pageBg */
  private isListPanel(): boolean {
    return this.panelType === 'bookmarks' || this.panelType === 'history' || this.panelType === 'downloads'
  }

  private shellBg(): string {
    return this.isListPanel() ? this.cardBg() : this.pageBg()
  }

  private cardBorder(): string {
    return this.isDark() ? BrowserTheme.DARK_BORDER : BrowserTheme.BORDER
  }

  private titleColor(): string {
    return this.isDark() ? BrowserTheme.DARK_TEXT : BrowserTheme.LIGHT_TEXT
  }

  private mutedColor(): string {
    return this.isDark() ? BrowserTheme.DARK_TEXT_MUTED : BrowserTheme.LIGHT_TEXT_MUTED
  }

  private secondaryColor(): string {
    return this.isDark() ? BrowserTheme.DARK_TEXT_SECONDARY : BrowserTheme.LIGHT_TEXT_SECONDARY
  }

  private primaryColor(): string {
    return this.isDark() ? BrowserTheme.PRIMARY_DARK : BrowserTheme.PRIMARY
  }

  /** 响应式字号：必须引用 this.fontUiScale，不可使用 BrowserTheme.uiFontSize 静态读 AppStorage */
  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  private fontSizePickerOptions(): SettingsPickOption[] {
    return BrowserStrings.fontSizeKeys().map((key: string): SettingsPickOption => ({
      key,
      label: BrowserStrings.fontSizeLabel(key)
    }))
  }

  private permissionPickerOptions(): SettingsPickOption[] {
    return [
      { key: 'allow', label: BrowserStrings.sitePermissionLabel('allow') },
      { key: 'deny', label: BrowserStrings.sitePermissionLabel('deny') }
    ]
  }

  private settingsHeaderTitle(): string {
    if (this.settingsView === 'browse') {
      return BrowserStrings.txt($r('app.string.settings_browse'))
    }
    if (this.settingsView === 'engine') {
      return BrowserStrings.txt($r('app.string.search_engine'))
    }
    if (this.settingsView === 'privacy') {
      return BrowserStrings.txt($r('app.string.settings_site_permissions'))
    }
    return BrowserStrings.txt($r('app.string.settings'))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.panelType === 'bookmarks') {
          BookmarksPanel({
            onClose: () => this.close()
          })
            .width('100%')
            .height('100%')
            .layoutWeight(1)
        } else if (this.panelType === 'history') {
          HistoryPanel({
            onClose: () => this.close()
          })
            .width('100%')
            .height('100%')
            .layoutWeight(1)
        } else if (this.panelType === 'downloads') {
          DownloadsPanel({
            onClose: () => this.close()
          })
            .width('100%')
            .height('100%')
            .layoutWeight(1)
        } else if (this.panelType === 'toolbox') {
          this.SettingsShell()
        } else if (this.panelType === 'about') {
          this.AboutShell()
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .backgroundColor(this.shellBg())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .zIndex(2000)
      .key(`feature-panel-font-${this.fontUiRev}-${this.fontSizeStorage}-${this.fontUiScale}`)
      .visibility(this.panelType ? Visibility.Visible : Visibility.None)
      .hitTestBehavior(this.panelType ? HitTestMode.Default : HitTestMode.None)

      if (this.showClearDataConfirm) {
        PanelConfirmDialog({
          message: BrowserStrings.txt($r('app.string.clear_data_confirm')),
          confirmLabel: BrowserStrings.txt($r('app.string.confirm')),
          cancelLabel: BrowserStrings.txt($r('app.string.cancel')),
          onConfirm: () => {
            this.showClearDataConfirm = false
            void BrowserStore.clearCookiesAndCache()
          },
          onCancel: () => {
            this.showClearDataConfirm = false
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.shellBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .hitTestBehavior(this.panelType || this.showClearDataConfirm ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  SettingsShell() {
    Column() {
      PanelSubpageHeader({
        title: this.settingsHeaderTitle(),
        batchMode: false,
        darkMode: this.isDark(),
        showSearch: false,
        showMore: false,
        onBack: () => {
          if (this.settingsView !== 'main') {
            this.settingsView = 'main'
          } else {
            this.close()
          }
        }
      })

      Scroll() {
        Column() {
          this.SettingsContent()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
    .key(`settings-shell-${this.fontUiRev}-${this.fontSizeStorage}-${this.fontUiScale}`)
  }

  @Builder
  AboutShell() {
    Column() {
      PanelSubpageHeader({
        title: BrowserStrings.txt($r('app.string.about_browser')),
        batchMode: false,
        darkMode: this.isDark(),
        showSearch: false,
        showMore: false,
        onBack: () => {
          this.close()
        }
      })

      this.AboutContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
  }

  @Builder
  SettingsContent() {
    if (this.settingsView === 'main') {
      this.SettingsRow(BrowserStrings.txt($r('app.string.settings_browse')), () => {
        this.settingsView = 'browse'
      })
      this.SettingsRow(BrowserStrings.txt($r('app.string.settings_site_permissions')), () => {
        this.enterPrivacySettings()
      })
      this.SettingsRow(BrowserStrings.txt($r('app.string.about_browser')), () => {
        BrowserStore.openFeaturePanel('about')
      })
    } else if (this.settingsView === 'browse') {
      BrowseSettingsSection({
        fontSize: $fontSize,
        imageLessMode: $imageLessMode,
        isDark: this.isDark(),
        onOpenEngine: () => {
          this.settingsView = 'engine'
        },
        onClearData: () => {
          this.showClearDataConfirm = true
        }
      })
    } else if (this.settingsView === 'engine') {
      Text($r('app.string.search_engine_default_hint'))
        .fontSize(this.uiFp(12))
        .fontColor(this.mutedColor())
        .padding({ left: 16, top: 12, bottom: 8 })
      ForEach(['baidu', 'bing', 'sogou', '360'], (id: string) => {
        Row() {
          Text(BrowserStrings.engineName(id))
            .fontSize(this.uiFp(15))
            .fontColor(this.titleColor())
            .layoutWeight(1)
          if (this.searchEngine === id) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(this.uiFp(18))
              .fontColor([this.primaryColor()])
              .fontWeight(FontWeight.Medium)
          }
        }
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.cardBg())
        .onClick(() => {
          this.searchEngine = id
          BrowserStore.setSearchEngine(id)
        })
      })
    } else if (this.settingsView === 'privacy') {
      Text($r('app.string.settings_site_permissions'))
        .fontSize(this.uiFp(12))
        .fontColor(this.mutedColor())
        .padding({ left: 16, top: 12, bottom: 8 })
      ForEach(['location', 'camera', 'microphone', 'notification'], (permId: string) => {
        Row() {
          Text(this.permissionLabel(permId))
            .fontSize(this.uiFp(15))
            .fontColor(this.titleColor())
            .layoutWeight(1)
          SettingsInlinePicker({
            options: this.permissionPickerOptions(),
            selectedKey: this.sitePermPolicy(permId),
            isDark: this.isDark(),
            menuWidth: 128,
            triggerWidth: 128,
            onSelect: (key: string) => {
              void this.applySitePermChange(permId, key as SitePermissionPolicy)
            }
          })
        }
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.cardBg())
      })
      // 浏览器应用权限（系统级）：申请 / 跳转系统设置
      this.AppPermissionManageSection()
    }
  }

  /** 进入网站权限页时刷新系统授权状态 */
  private enterPrivacySettings(): void {
    this.sitePerms = BrowserStore.getSitePermissions()
    this.settingsView = 'privacy'
    void AppPermissionService.getInstance().refreshAllStatuses().then(() => {
      this.appPermRev++
    })
  }

  private isAppPermGranted(permId: string): boolean {
    return AppStorage.get<string>(`browser_app_perm_${permId}`) === 'granted'
  }

  private appPermGrantedLabel(): string {
    return BrowserStrings.txt($r('app.string.perm_app_granted_short'))
  }

  private async requestAppPerm(permId: string): Promise<void> {
    const pid = permId as AppSystemPermissionId
    await AppPermissionService.getInstance().requestAppCategoryPermission(pid, true)
    this.appPermRev++
  }

  @Builder
  AppPermActionBtn(label: string, onTap: () => void) {
    Text(label)
      .fontSize(this.uiFp(13))
      .fontColor(this.primaryColor())
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(6)
      .backgroundColor(this.isDark() ? 'rgba(255,255,255,0.08)' : 'rgba(0,122,255,0.08)')
      .onClick(() => {
        onTap()
      })
  }

  @Builder
  AppPermissionManageSection() {
    Column({ space: 8 }) {
      Text(BrowserStrings.txt($r('app.string.perm_app_manage_header')))
        .fontSize(this.uiFp(12))
        .fontColor(this.mutedColor())
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Text(BrowserStrings.txt($r('app.string.perm_app_settings_hint')))
        .fontSize(this.uiFp(12))
        .fontColor(this.mutedColor())
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 4 })

      ForEach(['location', 'camera', 'microphone', 'notification', 'image_video'], (permId: string) => {
        Row() {
          Text(this.permissionLabel(permId))
            .fontSize(this.uiFp(15))
            .fontColor(this.titleColor())
            .layoutWeight(1)
          if (this.isAppPermGranted(permId)) {
            Text(this.appPermGrantedLabel())
              .fontSize(this.uiFp(13))
              .fontColor(this.mutedColor())
          } else {
            this.AppPermActionBtn(BrowserStrings.txt($r('app.string.perm_app_request')), () => {
              void this.requestAppPerm(permId)
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.cardBg())
      }, (permId: string) => `${permId}_${this.appPermRev}`)

      Row() {
        Text(BrowserStrings.txt($r('app.string.perm_app_open_settings')))
          .fontSize(this.uiFp(15))
          .fontColor(this.primaryColor())
          .layoutWeight(1)
        NavChevronRight({ color: this.mutedColor(), iconSize: this.uiFp(18) })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor(this.cardBg())
      .onClick(() => {
        void AppPermissionService.getInstance().openAppDetailInSystemSettings()
      })
    }
    .width('100%')
    .key(`app-perm-manage-${this.appPermRev}`)
  }

  private permissionLabel(permId: string): string {
    switch (permId) {
      case 'location':
        return BrowserStrings.txt($r('app.string.perm_location'))
      case 'camera':
        return BrowserStrings.txt($r('app.string.perm_camera'))
      case 'microphone':
        return BrowserStrings.txt($r('app.string.perm_microphone'))
      case 'image_video':
        return BrowserStrings.txt($r('app.string.perm_image_video'))
      default:
        return BrowserStrings.txt($r('app.string.perm_notification'))
    }
  }

  private sitePermPolicy(permId: string): SitePermissionPolicy {
    if (permId === 'location') {
      return this.sitePerms.location
    }
    if (permId === 'camera') {
      return this.sitePerms.camera
    }
    if (permId === 'microphone') {
      return this.sitePerms.microphone
    }
    return this.sitePerms.notification
  }

  /**
   * 切换网站权限策略。
   * - 禁止：直接保存。
   * - 允许：先校验/申请浏览器应用权限，仍无则强制改回禁止并提示。
   */
  private async applySitePermChange(permId: string, policy: SitePermissionPolicy): Promise<void> {
    const pid = permId as SitePermissionId
    if (policy === 'deny') {
      await BrowserStore.setSitePermissionUnchecked(pid, 'deny')
      this.sitePerms = BrowserStore.getSitePermissions()
      WebPermissionGate.getInstance().notifyPolicyChanged()
      return
    }
    const granted = await AppPermissionService.getInstance().ensureCategoryGranted(pid)
    if (!granted) {
      await BrowserStore.setSitePermissionUnchecked(pid, 'deny')
      this.sitePerms = BrowserStore.getSitePermissions()
      this.appPermRev++
      BrowserStore.showToast(BrowserStrings.appPermissionMissingCannotAllowToast(pid))
      return
    }
    // 麦克风：设置页允许时校验全局开关并预热音频会话
    if (pid === 'microphone') {
      const switchOpened = await WebPermissionGate.requestCaptureGlobalSwitch(pid)
      if (!switchOpened) {
        await BrowserStore.setSitePermissionUnchecked(pid, 'deny')
        this.sitePerms = BrowserStore.getSitePermissions()
        this.appPermRev++
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.perm_global_switch_off_toast'),
          BrowserStrings.permCategoryLabel(pid)))
        return
      }
      await WebPermissionGate.prepareMicrophoneAudioSession()
    }
    await BrowserStore.setSitePermissionUnchecked(pid, 'allow')
    this.sitePerms = BrowserStore.getSitePermissions()
    this.appPermRev++
    WebPermissionGate.getInstance().notifyPolicyChanged()
    if (pid === 'location') {
      LocationWarmupService.startAtAppLaunch('settingsAllow')
    }
  }

  @Builder
  SettingsRow(title: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(this.uiFp(15))
        .fontColor(this.titleColor())
        .layoutWeight(1)
      NavChevronRight({ color: this.mutedColor(), iconSize: this.uiFp(18) })
    }
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.cardBg())
    .margin({ bottom: 1 })
    .onClick(onTap)
  }

  @Builder
  AboutContent() {
    Column({ space: 8 }) {
      Text($r('app.string.browser_name'))
        .fontSize(this.uiFp(20))
        .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Bold))
        .fontColor(this.titleColor())
      Text(this.appVersion.length > 0 ? `版本 v${this.appVersion}` : $r('app.string.version_label'))
        .fontSize(this.uiFp(14))
        .fontColor(this.mutedColor())
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }
}
