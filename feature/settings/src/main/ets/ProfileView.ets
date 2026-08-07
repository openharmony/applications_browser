import { BrowserStrings } from 'common'
import { BrowserLog } from 'common'
import { BrowserNavigation } from 'browser_core'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { BookmarkItem } from 'common'
import { DownloadTask } from 'common'
import { HistoryEntry } from 'common'
import { AppStorageKeys } from 'common'
import { AppStateSync } from 'browser_core'
import {
  AboutListIcon,
  ServiceToggleItem,
  SettingsListIcon,
  StatBookmarkIcon,
  StatDownloadIcon,
  StatHistoryIcon,
  NavChevronRight,
  serviceTileBgDefault
} from 'commons'
import { ProfilePageHeader } from 'commons'
import { BrowserSafeAreaInsets } from 'commons'

/** 统计卡片单项（独立组件，count 随 @Prop 刷新） */
@Component
struct ProfileStatCell {
  @Prop count: string = '0'
  @Prop label: string = ''
  @Prop iconType: string = 'bookmark'
  onTap?: () => void
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  build() {
    Column({ space: 6 }) {
      if (this.iconType === 'history') {
        StatHistoryIcon()
      } else if (this.iconType === 'download') {
        StatDownloadIcon()
      } else {
        StatBookmarkIcon()
      }

      Text(this.label)
        .fontSize(this.uiFp(18))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDark() ? BrowserTheme.DARK_TEXT : BrowserTheme.LIGHT_TEXT)
        .letterSpacing(-0.4)

      Text(this.count)
        .fontSize(this.uiFp(11))
        .fontColor(this.isDark() ? BrowserTheme.DARK_TEXT_MUTED : BrowserTheme.LIGHT_TEXT_MUTED)
        .fontWeight(FontWeight.Medium)
    }
    .width(84)
    .key(`profile-stat-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}`)
    .onClick(() => {
      this.onTap?.()
    })
  }
}

@Component
export struct ProfileView {
  private static readonly PAGE_H_INSET: number = 16
  @StorageLink('browser_bookmarks') bookmarks: BookmarkItem[] = []
  @StorageLink('browser_history') historyList: HistoryEntry[] = []
  @StorageLink('browser_downloads') downloads: DownloadTask[] = []
  @StorageLink('browser_bookmarks_rev') bookmarksRev: number = 0
  @StorageLink('browser_history_rev') historyRev: number = 0
  @StorageLink('browser_downloads_rev') downloadsRev: number = 0
  @StorageLink('browser_list_stats_ui_rev') listStatsUiRev: number = 0
  @StorageLink('browser_incognito') isIncognito: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageProp(AppStorageKeys.SAFE_AREA_BOTTOM) safeAreaBottom: number = 0
  @StorageLink(AppStorageKeys.DARK_MODE_PICKER_VISIBLE) darkModePickerVisible: boolean = false

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  private pageBg(): string {
    return this.isDark() ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  private cardBg(): string {
    return this.isDark() ? BrowserTheme.DARK_PANEL_BG : BrowserTheme.LIGHT_PANEL_BG
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

  aboutToAppear(): void {
    BrowserStore.syncIncognitoForProfile()
    void this.reloadStatsFromDb('aboutToAppear')
  }

  /** 从 DB 重载统计（页面显示 / 面板关闭后调用） */
  private reloadStatsFromDb(source: string): void {
    void BrowserStore.whenReady().then(async () => {
      await AppStateSync.refreshProfileStatsOnShow(source)
    })
  }

  private bookmarkCount(): number {
    return this.bookmarks.filter((item) => !item.isFolder).length
  }

  build() {
    Column() {
      ProfilePageHeader({
        title: $r('app.string.profile_page_title'),
        darkMode: this.isDark()
      })

      Scroll() {
        Column() {
          this.StatsCard()
          this.SectionTitle(BrowserStrings.txt($r('app.string.common_services')))
          this.ServicesCard()
          this.SettingsCard()
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: ProfileView.PAGE_H_INSET,
          right: ProfileView.PAGE_H_INSET,
          bottom: BrowserSafeAreaInsets.homeContentBottomClearance()
        })
        .backgroundColor(this.pageBg())
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(this.pageBg())
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.pageBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .key(`profile-root-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}`)
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
      if (isVisible && currentRatio > 0) {
        void this.reloadStatsFromDb('visible')
      }
    })
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(this.uiFp(12))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.mutedColor())
      .letterSpacing(0.5)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ top: 18, bottom: 8 })
  }

  @Builder
  StatsCard() {
    Row() {
      ProfileStatCell({
        count: `${this.bookmarkCount()}`,
        label: BrowserStrings.txt($r('app.string.bookmarks')),
        iconType: 'bookmark',
        onTap: () => {
          BrowserStore.openFeaturePanel('bookmarks')
        }
      })
      ProfileStatCell({
        count: `${this.historyList.length}`,
        label: BrowserStrings.txt($r('app.string.history')),
        iconType: 'history',
        onTap: () => {
          BrowserStore.openFeaturePanel('history')
        }
      })
      ProfileStatCell({
        count: `${this.downloads.length}`,
        label: BrowserStrings.txt($r('app.string.downloads')),
        iconType: 'download',
        onTap: () => {
          BrowserStore.openFeaturePanel('downloads')
        }
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: 14, bottom: 14, left: 0, right: 0 })
    .backgroundColor(this.cardBg())
    .borderRadius(16)
    .border({ width: 1, color: this.cardBorder() })
    .margin({ bottom: 10 })
    .key(`profile_stats_${this.bookmarksRev}_${this.historyRev}_${this.downloadsRev}_` +
      `${this.listStatsUiRev}_${this.bookmarks.length}_${this.historyList.length}_${this.downloads.length}`)
  }

  @Builder
  ServicesCard() {
    Row() {
      ServiceToggleItem({
        serviceKind: 'incognito',
        label: BrowserStrings.txt($r('app.string.incognito')),
        onTap: () => {
          const nextIncognito = !BrowserStore.isIncognito()
          AppStorage.set(AppStorageKeys.INCOGNITO, nextIncognito)
          AppStorage.set(AppStorageKeys.BROWSE_INCOGNITO, nextIncognito)
          BrowserNavigation.openTabs(nextIncognito)
          void BrowserStore.setIncognitoSilent(nextIncognito)
        }
      })
      ServiceToggleItem({
        serviceKind: 'dark',
        label: BrowserStrings.txt($r('app.string.dark_mode')),
        onTap: (): void => {
          this.darkModePickerVisible = true
        }
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: 16, bottom: 16, left: 16, right: 16 })
    .backgroundColor(this.cardBg())
    .borderRadius(16)
    .border({ width: 1, color: this.cardBorder() })
    .margin({ bottom: 10 })
  }

  @Builder
  SettingsCard() {
    Column() {
      this.ListItem('settings', BrowserStrings.txt($r('app.string.settings')), () => {
        BrowserStore.openFeaturePanel('toolbox')
      })
      Divider().color(this.cardBorder()).strokeWidth(1).margin({ left: 46, right: 16 })
      this.ListItem('about', BrowserStrings.txt($r('app.string.about_browser')), () => {
        BrowserStore.openFeaturePanel('about')
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2, bottom: 2 })
    .backgroundColor(this.cardBg())
    .borderRadius(16)
    .border({ width: 1, color: this.cardBorder() })
  }

  @Builder
  ListItem(iconType: string, title: string, onTap: () => void) {
    Row() {
      if (iconType === 'about') {
        AboutListIcon()
      } else {
        Column() {
          SettingsListIcon()
        }
        .width(34)
        .height(34)
        .backgroundColor(this.iconTileBg())
        .borderRadius(10)
        .justifyContent(FlexAlign.Center)
      }

      Text(title)
        .fontSize(this.uiFp(15))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.titleColor())
        .layoutWeight(1)
        .margin({ left: 12 })

      NavChevronRight({ color: this.mutedColor(), iconSize: this.uiFp(16) })
    }
    .width('100%')
    .height(48)
    .padding({ top: 13, bottom: 13 })
    .onClick(onTap)
  }

  private iconTileBg(): ResourceColor {
    return serviceTileBgDefault()
  }
}
