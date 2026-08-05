import { BrowserNavigation } from 'browser_core'
import { HarmonyDialogStyle } from 'commons'
import { BrowserStrings } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { BookmarkFolderTree } from 'common'
import {
  DateGroup,
  groupHistoryByDate,
  ShortcutFeature
} from 'browser_core'
import { BookmarkItem } from 'common'
import { HistoryEntry } from 'common'
import { ShortcutManager } from 'browser_core'
import { HistorySiteIcon, NavChevronRight, ShortcutEngineIcon, ShortcutTileIcon } from 'commons'
import { PanelCircleIconButton } from 'commons'

/** 添加快捷方式弹层 Tab 类型 */
type AddShortcutTab = 'recommend' | 'bookmarks' | 'history'

@Component
export struct AddShortcutSheet {
  private static readonly LIST_ICON_SIZE: number = 44
  /** 添加/已添加胶囊按钮固定宽，避免状态切换挤换行或顶开中间文案 */
  private static readonly ACTION_BTN_WIDTH: number = 78
  private static readonly ACTION_BTN_HEIGHT: number = 32
  private static readonly OPEN_DURATION: number = 340
  private static readonly CLOSE_DURATION: number = 280
  private static readonly SHEET_SLIDE_DISTANCE: number = 720

  @Link @Watch('onVisibleChanged') visible: boolean
  @StorageLink('browser_shortcut_ids') shortcutIds: string[] = []
  @StorageLink('browser_shortcuts_rev') shortcutIdsRev: number = 0
  @StorageLink('browser_bookmarks') bookmarks: BookmarkItem[] = []
  @StorageLink('browser_history') historyList: HistoryEntry[] = []
  @StorageLink('browser_theme') theme: string = 'light'
  @State activeTab: AddShortcutTab = 'recommend'
  @State bookmarkFolderId: string = ''
  @State showCustomDialog: boolean = false
  @State customName: string = ''
  @State customUrl: string = ''
  @State private isRendered: boolean = false
  @State private maskOpacity: number = 0
  @State private sheetTranslateY: number = AddShortcutSheet.SHEET_SLIDE_DISTANCE
  @State private sheetOpacity: number = 1
  @State private isAnimatingClose: boolean = false

  private isDarkMode(): boolean {
    return this.theme === 'dark'
  }

  private sheetBg(): string {
    return this.isDarkMode() ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  /** 推荐列表副标题：站点类为「浏览器」，功能类为「常用功能」 */
  private catalogSubtitle(feat: ShortcutFeature): string {
    if (feat.kind === 'feature') {
      return BrowserStrings.txt($r('app.string.common_functions'))
    }
    return BrowserStrings.txt($r('app.string.browser_name'))
  }

  private sheetText(): string {
    return this.isDarkMode() ? '#f2f2f2' : BrowserTheme.TEXT
  }

  private sheetMuted(): string {
    return this.isDarkMode() ? '#8e8e93' : BrowserTheme.TEXT_MUTED
  }

  private listSurface(): string {
    return this.isDarkMode() ? '#2c2c2e' : BrowserTheme.SURFACE
  }

  private listBorder(): string {
    return this.isDarkMode() ? '#3a3a3c' : BrowserTheme.BORDER
  }

  private tabBarBg(): string {
    return this.isDarkMode() ? '#2c2c2e' : '#eef0f3'
  }

  private tabActiveBg(): string {
    return this.isDarkMode() ? '#3a3a3c' : '#ffffff'
  }

  private iconBg(): string {
    return this.isDarkMode() ? '#141414' : BrowserTheme.SURFACE
  }

  private iconBorder(): string {
    return this.isDarkMode() ? '#2a2a2a' : BrowserTheme.BORDER
  }

  aboutToAppear(): void {
    if (this.visible) {
      this.presentSheet()
    }
  }

  private onVisibleChanged(): void {
    if (this.visible) {
      this.presentSheet()
      return
    }
    if (this.isRendered && !this.isAnimatingClose) {
      this.dismissSheet(false)
    }
  }

  private resetSheetContent(): void {
    this.showCustomDialog = false
    this.activeTab = 'recommend'
    this.bookmarkFolderId = ''
    this.customName = ''
    this.customUrl = ''
  }

  private bookmarkFolderRows(): string[] {
    if (this.bookmarkFolderId === '') {
      return BrowserStore.getBookmarkFolders()
    }
    return BrowserStore.getChildFolders(this.bookmarkFolderId).map((e) => e.id)
  }

  private visibleBookmarks(): BookmarkItem[] {
    return BrowserStore.bookmarksInFolder(this.bookmarkFolderId).filter((b) => !b.isFolder)
  }

  private presentSheet(): void {
    if (this.isRendered && this.sheetTranslateY === 0 && !this.isAnimatingClose) {
      return
    }
    this.isAnimatingClose = false
    this.isRendered = true
    this.maskOpacity = 0
    this.sheetOpacity = 1
    this.sheetTranslateY = AddShortcutSheet.SHEET_SLIDE_DISTANCE
    setTimeout(() => {
      animateTo({
        duration: AddShortcutSheet.OPEN_DURATION,
        curve: Curve.FastOutSlowIn
      }, () => {
        this.maskOpacity = 1
        this.sheetTranslateY = 0
      })
    }, 16)
  }

  private dismissSheet(updateVisible: boolean): void {
    if (!this.isRendered || this.isAnimatingClose) {
      return
    }
    this.isAnimatingClose = true
    animateTo({
      duration: AddShortcutSheet.CLOSE_DURATION,
      curve: Curve.EaseIn
    }, () => {
      this.maskOpacity = 0
      this.sheetTranslateY = AddShortcutSheet.SHEET_SLIDE_DISTANCE
      this.sheetOpacity = 0
    })
    setTimeout(() => {
      this.isRendered = false
      this.isAnimatingClose = false
      this.sheetOpacity = 1
      this.sheetTranslateY = AddShortcutSheet.SHEET_SLIDE_DISTANCE
      this.maskOpacity = 0
      this.resetSheetContent()
      if (updateVisible) {
        this.visible = false
      }
    }, AddShortcutSheet.CLOSE_DURATION)
  }

  private close(): void {
    if (this.showCustomDialog) {
      this.showCustomDialog = false
      return
    }
    this.dismissSheet(true)
  }

  private isAdded(id: string): boolean {
    return this.shortcutIds.includes(id)
  }

  private showAddResult(ok: boolean, title: string): void {
    if (ok) {
      BrowserStore.showToast(BrowserStrings.shortcutAdded(title))
      return
    }
    if (this.shortcutIds.length >= BrowserStore.getShortcutMaxCount()) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.shortcut_limit_reached')))
      return
    }
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.shortcut_already_on_home')))
  }

  private removeById(id: string): void {
    const idx = this.shortcutIds.indexOf(id)
    if (idx < 0) {
      return
    }
    const next = this.shortcutIds.slice()
    next.splice(idx, 1)
    this.shortcutIds = next
    void BrowserStore.removeShortcut(id).then(() => {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.shortcut_removed')))
    })
  }

  private appendIdIfMissing(id: string): void {
    if (this.shortcutIds.indexOf(id) >= 0) {
      return
    }
    this.shortcutIds = [...this.shortcutIds, id]
  }

  private addCatalog(feat: ShortcutFeature): void {
    void BrowserStore.addShortcut(feat.id).then((ok) => {
      if (ok) {
        this.appendIdIfMissing(feat.id)
        BrowserStore.showToast(BrowserStrings.shortcutAdded(feat.title))
        return
      }
      this.showAddResult(false, feat.title)
    })
  }

  private addBookmark(bookmark: BookmarkItem): void {
    const sid = ShortcutManager.bookmarkShortcutId(bookmark.id)
    void BrowserStore.addBookmarkShortcut(bookmark).then((ok) => {
      if (ok) {
        this.appendIdIfMissing(sid)
        BrowserStore.showToast(BrowserStrings.shortcutAdded(bookmark.title))
        return
      }
      this.showAddResult(false, bookmark.title)
    })
  }

  private addHistory(entry: HistoryEntry): void {
    const title = entry.title.length > 0 ? entry.title : entry.url
    const sid = ShortcutManager.historyShortcutId(entry.id)
    void BrowserStore.addHistoryShortcut(entry).then((ok) => {
      if (ok) {
        this.appendIdIfMissing(sid)
        BrowserStore.showToast(BrowserStrings.shortcutAdded(title))
        return
      }
      this.showAddResult(false, title)
    })
  }

  private sortedHistory(): HistoryEntry[] {
    const list = this.historyList.slice()
    list.sort((a, b) => b.visitedAt - a.visitedAt)
    return list
  }

  private openCustomDialog(): void {
    this.customName = ''
    this.customUrl = ''
    this.showCustomDialog = true
  }

  private saveCustomShortcut(): void {
    const name = this.customName.trim()
    const rawUrl = this.customUrl.trim()
    if (!name) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.custom_shortcut_name_required')))
      return
    }
    const check = BrowserNavigation.validateUrlInput(rawUrl)
    if (!check.ok || !check.url) {
      BrowserStore.showToast(check.message ?? BrowserStrings.urlFormatInvalid())
      return
    }
    void BrowserStore.addCustomShortcut(name, check.url).then((ok) => {
      if (ok) {
        BrowserStore.showToast(BrowserStrings.shortcutAdded(name))
        this.showCustomDialog = false
        this.customName = ''
        this.customUrl = ''
        return
      }
      this.showAddResult(false, name)
    })
  }

  private switchTab(tab: AddShortcutTab): void {
    this.activeTab = tab
    if (tab !== 'bookmarks') {
      this.bookmarkFolderId = ''
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isRendered) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0, 0, 0, 0.55)')
            .opacity(this.maskOpacity)
            .onClick(() => this.close())

          Column() {
            Column()
              .width(36)
              .height(4)
              .borderRadius(2)
              .backgroundColor(this.isDarkMode() ? '#5c5c5e' : '#d1d5db')
              .margin({ top: 10, bottom: 12 })

            Row() {
              Text($r('app.string.add_to_home_title'))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.sheetText())
                .layoutWeight(1)

              Column() {
                Text('×')
                  .fontSize(20)
                  .fontColor(this.sheetText())
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.close())
            }
            .width('100%')
            .margin({ bottom: 16 })

            this.TabBar()

            Scroll() {
              Column() {
                if (this.activeTab === 'recommend') {
                  this.RecommendList()
                } else if (this.activeTab === 'bookmarks') {
                  this.BookmarkList()
                } else {
                  this.HistoryList()
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .align(Alignment.Top)
            .scrollBar(BarState.Off)

            if (this.activeTab === 'recommend') {
              this.CustomShortcutLink()
            }
          }
          .width('100%')
          .height('88%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .backgroundColor(this.sheetBg())
          .borderRadius({ topLeft: 22, topRight: 22 })
          .translate({ y: this.sheetTranslateY })
          .opacity(this.sheetOpacity)
        }
        .width('100%')
        .height('100%')

        if (this.showCustomDialog) {
          this.CustomShortcutDialog()
        }
      }
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(2000)
    .hitTestBehavior(this.isRendered ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  TabBar() {
    Row({ space: 4 }) {
      this.TabChip('recommend', $r('app.string.shortcut_tab_recommend'))
      this.TabChip('bookmarks', $r('app.string.shortcut_tab_bookmarks'))
      this.TabChip('history', $r('app.string.shortcut_tab_history'))
    }
    .width('100%')
    .padding(4)
    .borderRadius(12)
    .backgroundColor(this.tabBarBg())
    .margin({ bottom: 16 })
  }

  @Builder
  TabChip(tab: AddShortcutTab, label: Resource) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.activeTab === tab ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.activeTab === tab ? this.sheetText() : this.sheetMuted())
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(10)
      .backgroundColor(this.activeTab === tab ? this.tabActiveBg() : Color.Transparent)
      .onClick(() => this.switchTab(tab))
  }

  @Builder
  RecommendList() {
    Column({ space: 10 }) {
      ForEach(ShortcutManager.buildFeatureCatalog(), (feat: ShortcutFeature) => {
        this.CatalogListRow(feat, this.isAdded(feat.id))
      }, (feat: ShortcutFeature) => `${feat.id}_${this.shortcutIdsRev}_${this.isAdded(feat.id)}`)
    }
    .width('100%')
  }

  @Builder
  BookmarkList() {
    if (this.bookmarkFolderId !== '') {
      Row({ space: 10 }) {
        PanelCircleIconButton({
          iconKind: 'back',
          darkMode: this.isDarkMode(),
          onTap: () => {
            this.bookmarkFolderId = BrowserStore.getFolderParentId(this.bookmarkFolderId)
          }
        })
        Text(BrowserStore.getFolderTitle(this.bookmarkFolderId))
          .fontSize(14)
          .fontColor(this.sheetMuted())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ bottom: 10 })
      .alignItems(VerticalAlign.Center)
    }

    if (this.bookmarkFolderRows().length === 0 && this.visibleBookmarks().length === 0) {
      this.EmptyHint($r('app.string.shortcut_empty_bookmarks'))
    } else {
      Column() {
        ForEach(this.bookmarkFolderRows(), (folderId: string, index: number) => {
          this.BookmarkFolderRow(folderId, index === this.bookmarkFolderRows().length - 1 &&
            this.visibleBookmarks().length === 0)
        }, (folderId: string) => folderId)

        ForEach(this.visibleBookmarks(), (bookmark: BookmarkItem, index: number) => {
          this.BookmarkListRow(bookmark, index === this.visibleBookmarks().length - 1,
            this.isAdded(ShortcutManager.bookmarkShortcutId(bookmark.id)))
        }, (bookmark: BookmarkItem) => {
          return `${bookmark.id}_${this.shortcutIdsRev}_${this.isAdded(ShortcutManager.bookmarkShortcutId(bookmark.id))}`
        })
      }
      .width('100%')
      .backgroundColor(this.listSurface())
      .borderRadius(12)
      .clip(true)
    }
  }

  @Builder
  HistoryList() {
    if (this.sortedHistory().length === 0) {
      this.EmptyHint($r('app.string.shortcut_empty_history'))
    } else {
      Column() {
        ForEach(groupHistoryByDate(this.sortedHistory()), (group: DateGroup<HistoryEntry>) => {
          this.HistorySection(group)
        }, (group: DateGroup<HistoryEntry>) => group.label)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  HistorySection(group: DateGroup<HistoryEntry>) {
    Column() {
      Text(group.label)
        .fontSize(13)
        .fontColor(this.sheetMuted())
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 4, bottom: 8 })

      Column() {
        ForEach(group.items, (entry: HistoryEntry, index: number) => {
          this.HistoryListRow(entry, index === group.items.length - 1,
            this.isAdded(ShortcutManager.historyShortcutId(entry.id)))
        }, (entry: HistoryEntry) => {
          return `hist_${entry.id}_${this.shortcutIdsRev}_${this.isAdded(ShortcutManager.historyShortcutId(entry.id))}`
        })
      }
      .width('100%')
      .backgroundColor(this.listSurface())
      .borderRadius(12)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 16 })
  }

  @Builder
  EmptyHint(label: Resource) {
    Text(label)
      .fontSize(14)
      .fontColor(this.sheetMuted())
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 48, bottom: 48 })
  }

  @Builder
  CustomShortcutLink() {
    Text($r('app.string.custom_shortcut'))
      .fontSize(15)
      .fontColor(BrowserTheme.PRIMARY_COLOR)
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 16, bottom: 8 })
      .onClick(() => this.openCustomDialog())
  }

  @Builder
  CatalogListRow(feat: ShortcutFeature, added: boolean) {
    Row() {
      Column() {
        if (feat.kind === 'feature') {
          ShortcutTileIcon({ tile: feat.tile ?? 'bookmark', iconSize: 26 })
        } else {
          ShortcutEngineIcon({
            text: feat.iconText ?? '',
            iconMedia: feat.iconMedia ?? '',
            iconSize: 36
          })
        }
      }
      .width(AddShortcutSheet.LIST_ICON_SIZE)
      .height(AddShortcutSheet.LIST_ICON_SIZE)
      .borderRadius(10)
      .backgroundColor(this.iconBg())
      .border({ width: 1, color: this.iconBorder() })
      .justifyContent(FlexAlign.Center)
      .margin({ right: 12 })

      Column({ space: 3 }) {
        Text(feat.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.sheetText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.catalogSubtitle(feat))
          .fontSize(12)
          .fontColor(this.sheetMuted())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
      .margin({ right: 10 })

      this.RecommendActionButton(added, () => {
        this.addCatalog(feat)
      }, () => {
        this.removeById(feat.id)
      })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.listSurface())
    .borderRadius(14)
    .alignItems(VerticalAlign.Center)
  }

  /** 列表右侧操作：未添加→添加，已添加→移除（推荐/书签/历史共用） */
  @Builder
  RecommendActionButton(added: boolean, onAdd: () => void, onRemove: () => void) {
    Row() {
      Text(added ? $r('app.string.shortcut_status_added') : $r('app.string.add_shortcut'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(added ? this.sheetMuted() : BrowserTheme.primaryColor(this.isDarkMode()))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
    }
    .width(AddShortcutSheet.ACTION_BTN_WIDTH)
    .height(AddShortcutSheet.ACTION_BTN_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(AddShortcutSheet.ACTION_BTN_HEIGHT / 2)
    .backgroundColor(added ?
      $r('sys.color.ohos_id_color_button_normal') :
      BrowserTheme.primaryLight(this.isDarkMode()))
    .flexShrink(0)
    .onClick(() => {
      if (added) {
        onRemove()
      } else {
        onAdd()
      }
    })
  }

  @Builder
  BookmarkFolderRow(folderId: string, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(18)
          .fontColor([BrowserTheme.PRIMARY_COLOR])
          .margin({ right: 10 })

        Column({ space: 2 }) {
          Text(BrowserStore.getFolderTitle(folderId))
            .fontSize(15)
            .fontColor(this.sheetText())
          Text(BrowserStore.folderItemCountLabel(folderId))
            .fontSize(12)
            .fontColor(this.sheetMuted())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        NavChevronRight({ color: this.sheetMuted(), iconSize: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (!isLast) {
        Divider()
          .color(this.listBorder())
          .strokeWidth(1)
          .margin({ left: BookmarkFolderTree.dividerStartLeading(18), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.listSurface())
    .onClick(() => {
      this.bookmarkFolderId = folderId
    })
  }

  @Builder
  BookmarkListRow(bookmark: BookmarkItem, isLast: boolean, added: boolean) {
    Column() {
      Row() {
        HistorySiteIcon({ url: bookmark.url, iconUrl: bookmark.iconUrl })
          .margin({ right: 10 })

        Column({ space: 2 }) {
          Text(bookmark.title)
            .fontSize(15)
            .fontColor(this.sheetText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(bookmark.url)
            .fontSize(12)
            .fontColor(this.sheetMuted())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .margin({ right: 10 })

        this.RecommendActionButton(added, () => {
          this.addBookmark(bookmark)
        }, () => {
          this.removeById(ShortcutManager.bookmarkShortcutId(bookmark.id))
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (!isLast) {
        Divider()
          .color(this.listBorder())
          .strokeWidth(1)
          .margin({ left: BookmarkFolderTree.dividerStartSite(), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.listSurface())
  }

  @Builder
  HistoryListRow(entry: HistoryEntry, isLast: boolean, added: boolean) {
    Column() {
      Row() {
        HistorySiteIcon({ url: entry.url, iconUrl: entry.iconUrl })
          .margin({ right: 10 })

        Column({ space: 2 }) {
          Text(entry.title.length > 0 ? entry.title : entry.url)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.sheetText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(entry.url)
            .fontSize(12)
            .fontColor(this.sheetMuted())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .margin({ right: 10 })

        this.RecommendActionButton(added, () => {
          this.addHistory(entry)
        }, () => {
          this.removeById(ShortcutManager.historyShortcutId(entry.id))
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (!isLast) {
        Divider()
          .color(this.listBorder())
          .strokeWidth(1)
          .margin({ left: BookmarkFolderTree.dividerStartSite(), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.listSurface())
  }

  @Builder
  CustomShortcutDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())
        .onClick(() => {
          this.showCustomDialog = false
        })

      Column({ space: 16 }) {
        Text($r('app.string.custom_shortcut_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)

        Column({ space: 6 }) {
          Text($r('app.string.bookmark_name_label'))
            .fontSize(13)
            .fontColor(HarmonyDialogStyle.textSecondary())
          TextInput({ placeholder: BrowserStrings.txt($r('app.string.custom_shortcut_name_hint')), text: this.customName })
            .height(44)
            .fontSize(15)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
            .onChange((v: string) => {
              BrowserNavigation.applyTextInputChange(v, this.customName.length, (text: string) => {
                this.customName = text
              })
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 6 }) {
          Text($r('app.string.bookmark_url_label'))
            .fontSize(13)
            .fontColor(HarmonyDialogStyle.textSecondary())
          TextInput({ placeholder: BrowserStrings.txt($r('app.string.custom_shortcut_url_hint')), text: this.customUrl })
            .height(44)
            .fontSize(15)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
            .onChange((v: string) => {
              BrowserNavigation.applyTextInputChange(v, this.customUrl.length, (text: string) => {
                this.customUrl = text
              }, true)
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .width('100%')
          .margin({ left: 16, right: 16 })

        Row() {
          Text($r('app.string.cancel'))
            .fontSize(HarmonyDialogStyle.BTN_FONT)
            .fontColor(HarmonyDialogStyle.textPrimary())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
            .onClick(() => {
              this.showCustomDialog = false
            })

          Text($r('app.string.save'))
            .fontSize(HarmonyDialogStyle.BTN_FONT)
            .fontColor(HarmonyDialogStyle.emphasize())
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
            .onClick(() => this.saveCustomShortcut())
        }
        .width('100%')
      }
      .width(HarmonyDialogStyle.CARD_WIDTH)
      .constraintSize({ maxWidth: HarmonyDialogStyle.CARD_MAX_WIDTH })
      .padding({ top: 20, bottom: 4, left: 16, right: 16 })
      .backgroundColor(HarmonyDialogStyle.cardBg())
      .borderRadius(HarmonyDialogStyle.CARD_RADIUS)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(2100)
  }
}
