import { BrowserTheme } from 'browser_core'
import { BrowserDeviceProfile } from 'common'
import { AppStorageKeys } from 'common'
import { SearchSuggest, SearchSuggestion } from 'common'
import { BookmarkItem } from 'common'
import { HistoryEntry } from 'common'
import { DownloadTask } from 'common'
import { BrowserNavigation } from 'browser_core'
import { BrowserStrings } from 'common'
import { BrowserStore } from 'browser_core'
import { formatFileSizeText } from 'common'
import { DownloadFileIcon } from 'download'
import { PanelDownloadAction } from 'download'
import {
  BrowseToolbarDownloadProgressIcon,
  PanelHeaderCloseIcon,
  SearchLeadingIcon,
  StarBookmarkIcon,
  UrlNavigateConfirmBtn
} from 'commons'

/**
 * 浏览页地址栏：TextInput 常驻，展示态 overlay 覆盖。
 * 编辑态由组件内 @State 立即切换，避免父级 @Prop 延迟 + sessionId 重建导致需点两次。
 */
@Component
export struct BrowseAddressBar {
  @Prop @Watch('onParentEditingChanged') isEditing: boolean = false
  @Prop displayText: string = ''
  @Prop textColor: ResourceColor = Color.Black
  @Prop placeholderColor: string = '#9aa0a6'
  @Prop pillBorderColor: ResourceColor = Color.Gray
  @Prop pillBgColor: ResourceColor = Color.White
  @Prop refreshColor: ResourceColor = Color.Gray
  @Prop refreshLabel: string = '↻'
  @Prop showStopIcon: boolean = false
  @Prop bookmarked: boolean = false
  @Prop bookmarkColor: string = '#FFD700'
  @Prop bookmarks: BookmarkItem[] = []
  @Prop historyList: HistoryEntry[] = []
  @Prop isIncognito: boolean = false
  onStartEdit: () => void = () => {}
  onSubmit: (text: string) => void = () => {}
  onNavigate: (url: string) => void = () => {}
  onRefresh: () => void = () => {}
  onBookmark: () => void = () => {}
  onCopyUrl: () => void = () => {}
  onViewAllDownloads: () => void = () => {}

  @StorageLink(AppStorageKeys.FONT_SIZE) fontSizeKey: string = 'system'
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageLink(AppStorageKeys.DOWNLOADS) downloads: DownloadTask[] = []
  @StorageLink(AppStorageKeys.DOWNLOADS_REV) downloadsRev: number = 0
  @StorageLink(AppStorageKeys.DOWNLOAD_PROGRESS_REV) downloadProgressRev: number = 0

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  private actionBtnSize(): number {
    return 44
  }

  private actionIconSize(): number {
    return 28
  }

  private actionGroupWidth(): number {
    if (this.showAddressBarDownloadEntry() && !this.editing) {
      return 100
    }
    return 48
  }

  /** 组件内编辑态（点击 overlay 后立即 true，不等待父级重绘） */
  @State private editing: boolean = false
  @State private draft: string = ''
  @State private showDownloadPopover: boolean = false
  private inputController: TextInputController = new TextInputController()

  aboutToAppear(): void {
    this.draft = BrowserNavigation.clampAddressInput(this.displayText).text
  }

  onParentEditingChanged(): void {
    if (!this.isEditing) {
      this.exitEditMode()
    }
  }

  /** 退出编辑态并关闭输入法 */
  private exitEditMode(): void {
    this.editing = false
    this.showDownloadPopover = false
    try {
      this.inputController.stopEditing()
    } catch (_e) {
      // stopEditing 在部分版本不可用时不阻塞退出
    }
  }

  private enterEdit(): void {
    this.draft = BrowserNavigation.clampAddressInput(this.displayText).text
    this.editing = true
    this.onStartEdit()
    this.scheduleFocus()
  }

  private scheduleFocus(): void {
    setTimeout((): void => {
      focusControl.requestFocus('browse_url_edit_input')
      this.inputController.caretPosition(this.draft.length)
    }, 80)
  }

  private onInputChange(value: string): void {
    BrowserNavigation.applyTextInputChange(value, this.draft.length, (text: string) => {
      this.draft = text
    }, true)
  }

  private secureIcon(): string {
    const source = this.editing ? this.draft : this.displayText
    return source.trim().startsWith('https') ? '🔒' : '⚠'
  }

  /** Pad/2in1：收藏按钮后始终展示下载管理入口（不依赖横竖屏） */
  private showAddressBarDownloadEntry(): boolean {
    return BrowserDeviceProfile.isPadFormFactor()
  }

  private hasActiveDownloadTask(): boolean {
    const _rev = this.downloadsRev
    if (_rev < 0) {
      return false
    }
    for (let i = 0; i < this.downloads.length; i++) {
      const item = this.downloads[i]
      if (item.status === 'running' || item.status === 'queued') {
        return true
      }
    }
    return false
  }

  private latestActiveDownloadProgress(): number {
    const _tick = this.downloadProgressRev
    if (_tick < 0) {
      return 0
    }
    let pick: DownloadTask | null = null
    for (let i = 0; i < this.downloads.length; i++) {
      const item = this.downloads[i]
      if (item.status !== 'running' && item.status !== 'queued') {
        continue
      }
      if (pick === null || item.updatedAt > pick.updatedAt) {
        pick = item
      }
    }
    if (pick === null) {
      return 0
    }
    return Math.min(100, Math.max(0, pick.progress))
  }

  private latestActiveDownloadIndeterminate(): boolean {
    let pick: DownloadTask | null = null
    for (let i = 0; i < this.downloads.length; i++) {
      const item = this.downloads[i]
      if (item.status !== 'running' && item.status !== 'queued') {
        continue
      }
      if (pick === null || item.updatedAt > pick.updatedAt) {
        pick = item
      }
    }
    if (pick === null) {
      return false
    }
    return pick.status === 'queued' || pick.progress <= 0
  }

  private latestFiveDownloads(): DownloadTask[] {
    const list: DownloadTask[] = this.downloads.slice()
    list.sort((a, b) => b.updatedAt - a.updatedAt)
    return list.slice(0, 5)
  }

  /** 下载元信息：与下载管理一致，失败时拼接原因 */
  private downloadMetaText(item: DownloadTask): string {
    const sizeText = formatFileSizeText(item.fileSize)
    if (item.status === 'failed') {
      const reason = item.errorMessage.trim()
      if (reason.length > 0) {
        return sizeText.length > 0 ? `${sizeText} · ${reason}` : reason
      }
    }
    return sizeText
  }

  private tryOpenDownload(id: string): void {
    void BrowserStore.openDownload(id).then((result: string) => {
      if (result === 'missing') {
        void BrowserStore.redownloadMissingFile(id)
      }
    })
  }

  private onDownloadRowTap(item: DownloadTask): void {
    if (item.status === 'done') {
      this.tryOpenDownload(item.id)
      return
    }
    if (item.status === 'deleted') {
      void BrowserStore.redownloadMissingFile(item.id)
    }
  }

  private onDownloadActionRetry(id: string): void {
    void BrowserStore.retryDownload(id)
  }

  private onDownloadActionRedownload(id: string): void {
    void BrowserStore.redownloadMissingFile(id)
  }

  @Builder
  private DownloadPopoverPanel() {
    Column() {
      Text(BrowserStrings.txt($r('app.string.shortcut_downloads')))
        .fontSize(this.uiFp(13))
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .width('100%')
        .margin({ bottom: 8 })

      ForEach(this.latestFiveDownloads(), (item: DownloadTask) => {
        Row({ space: 8 }) {
          DownloadFileIcon({
            fileName: item.fileName,
            galleryUri: item.galleryUri,
            localPath: item.localPath,
            status: item.status
          })
          Column({ space: 2 }) {
            Text(item.fileName)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111827')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.downloadMetaText(item))
              .fontSize(12)
              .fontColor('#5F6B7A')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          PanelDownloadAction({
            itemId: item.id,
            itemName: item.fileName,
            status: item.status,
            progress: item.progress,
            onOpenItem: (id: string) => {
              this.tryOpenDownload(id)
            },
            onRetryRequest: (id: string, _name: string) => {
              this.onDownloadActionRetry(id)
            },
            onRedownloadRequest: (id: string, _name: string) => {
              this.onDownloadActionRedownload(id)
            }
          })
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 10, bottom: 10 })
        .backgroundColor(BrowserTheme.SURFACE)
        .borderRadius(10)
        .onClick((): void => {
          this.onDownloadRowTap(item)
        })
      }, (item: DownloadTask) => item.id)

      if (this.latestFiveDownloads().length === 0) {
        Text(BrowserStrings.txt($r('app.string.no_downloads')))
          .fontSize(this.uiFp(12))
          .fontColor('#5F6B7A')
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      }

      Row() {
        Text('查看全部')
          .fontSize(this.uiFp(12))
          .fontColor('#0A59F7')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 10, bottom: 2 })
      .border({ width: { top: 1 }, color: '#E5E8EC' })
      .margin({ top: 6 })
      .onClick((): void => {
        this.showDownloadPopover = false
        this.onViewAllDownloads()
      })
    }
    .width(390)
    .padding({ left: 12, right: 12, top: 10, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 20, color: 'rgba(17,24,39,0.18)', offsetX: 0, offsetY: 6 })
  }

  private suggestions(): SearchSuggestion[] {
    if (!this.editing || !this.draft.trim()) {
      return []
    }
    const history = this.isIncognito ? [] : this.historyList
    return SearchSuggest.buildBookmarkHistory(this.draft, history, this.bookmarks, 8)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row({ space: 8 }) {
        Row({ space: 8 }) {
          Text(this.secureIcon())
            .fontSize(this.uiFp(12))
            .flexShrink(0)
            .fontColor(this.textColor)
            .gesture(
              LongPressGesture({ repeat: false, duration: 450 })
                .onAction((): void => {
                  this.onCopyUrl()
                })
            )
          SearchLeadingIcon({ color: this.placeholderColor, iconSize: 16 })
          Stack({ alignContent: Alignment.Center }) {
            TextInput({
              text: this.editing ? this.draft : '',
              placeholder: this.editing ? $r('app.string.search_placeholder') : '',
              controller: this.inputController
            })
              .id('browse_url_edit_input')
              .fontSize(this.uiFp(13))
              .fontColor(this.textColor)
              .placeholderColor(this.placeholderColor)
              .backgroundColor(Color.Transparent)
              .width('100%')
              .height(36)
              .maxLines(1)
              .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
              .focusable(this.editing)
              .enableKeyboardOnFocus(this.editing)
              .visibility(this.editing ? Visibility.Visible : Visibility.Hidden)
              .onChange((value: string): void => {
                if (this.editing) {
                  this.onInputChange(value)
                }
              })
              .onSubmit((): void => {
                if (this.editing) {
                  this.onSubmit(BrowserNavigation.clampAddressInput(this.draft).text)
                }
              })

            if (!this.editing) {
              Row() {
                Text(this.displayText)
                  .fontSize(this.uiFp(13))
                  .fontColor(this.textColor)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .width('100%')
              .height(36)
              .backgroundColor(Color.Transparent)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .id('browse_address_bar_display')
              .onClick((): void => {
                this.enterEdit()
              })
            }
          }
          .layoutWeight(1)
          .flexShrink(1)
          .constraintSize({ minWidth: 0 })
          .height(36)

          if (this.editing) {
            Column() {
              UrlNavigateConfirmBtn({
                color: '#1a73e8',
                fontSize: this.uiFp(18)
              })
            }
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .onClick((): void => {
              this.onSubmit(BrowserNavigation.clampAddressInput(this.draft).text)
            })
          }

          Column() {
            if (this.showStopIcon) {
              PanelHeaderCloseIcon({
                color: this.refreshColor as string,
                boxSize: 14
              })
            } else {
              Text(this.refreshLabel)
                .fontSize(this.uiFp(16))
                .fontColor(this.refreshColor)
            }
          }
          .width(24)
          .height(24)
          .justifyContent(FlexAlign.Center)
          .onClick((): void => {
            this.onRefresh()
          })
        }
        .layoutWeight(1)
        .flexShrink(1)
        .constraintSize({ minWidth: 0 })
        .height(40)
        .borderRadius(999)
        .border({ width: 1, color: this.pillBorderColor })
        .backgroundColor(this.pillBgColor)
        .padding({ left: 14, right: 10 })
        .margin({ right: 6 })
        .alignItems(VerticalAlign.Center)

          Row({ space: 6 }) {
            Column() {
              StarBookmarkIcon({
                bookmarked: this.bookmarked,
                color: this.bookmarkColor,
                iconSize: this.actionIconSize()
              })
            }
            .width(this.actionBtnSize())
            .height(this.actionBtnSize())
            .borderRadius(this.actionBtnSize() / 2)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F4F6F8')
            .onClick((): void => {
              this.onBookmark()
            })

            if (this.showAddressBarDownloadEntry() && !this.editing) {
              Column() {
                if (this.hasActiveDownloadTask()) {
                  BrowseToolbarDownloadProgressIcon({
                    boxSize: this.actionIconSize(),
                    progress: this.latestActiveDownloadProgress(),
                    isDark: false,
                    indeterminate: this.latestActiveDownloadIndeterminate(),
                    variant: 'accent'
                  })
                } else {
                  Image($r('app.media.ic_download_toolbar'))
                    .width(this.actionIconSize())
                    .height(this.actionIconSize())
                    .fillColor('#111827')
                    .objectFit(ImageFit.Contain)
                }
              }
              .width(this.actionBtnSize())
              .height(this.actionBtnSize())
              .borderRadius(this.actionBtnSize() / 2)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#F4F6F8')
              .onClick((): void => {
                this.showDownloadPopover = !this.showDownloadPopover
              })
              .bindPopup(this.showDownloadPopover, {
                builder: this.DownloadPopoverPanel(),
                placement: Placement.BottomRight,
                popupColor: Color.Transparent,
                enableArrow: false
              })
            }
          }
          .width(this.actionGroupWidth())
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: this.editing ? 4 : 8 })
      }
      .width('100%')
      .height(this.editing ? 52 : 56)
      .clip(false)

      if (this.suggestions().length > 0) {
        Column() {
          ForEach(this.suggestions(), (item: SearchSuggestion) => {
            Row({ space: 8 }) {
              Text(item.kind === 'url' ? '🔗' : item.kind === 'history' ? '🕐' : '⭐')
                .fontSize(this.uiFp(14))
              Text(item.text)
                .fontSize(this.uiFp(14))
                .fontColor(this.textColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .onClick((): void => {
              const target = (item.navigateUrl ?? item.text).trim()
              if (target.length > 0) {
                this.onNavigate(target)
              }
            })
          }, (item: SearchSuggestion) => `${item.kind}_${item.navigateUrl ?? item.text}`)
        }
        .width('100%')
        .padding({ left: 28, right: 28, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .key(`browse-addr-bar-${this.fontUiRev}-${this.fontSizeKey}-${this.fontUiScale.toFixed(2)}`)
  }
}
