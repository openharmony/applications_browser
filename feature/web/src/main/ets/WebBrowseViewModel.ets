import { BrowserStore } from 'browser_core'
import { BrowserNavigation } from 'browser_core'
import { BrowserStrings } from 'common'
import { BrowserUtils } from 'common'
import { OpenBrowseOptions, OpenShareOptions, tabHostname } from 'browser_core'
import { BookmarkItem } from 'common'
import { WebPageController } from 'browser_core'

/** 网页浏览 ViewModel：页内搜索、上下文菜单、地址栏编辑、更多面板等 UI 状态 */
@Observed
export class WebBrowseViewModel {
  showMoreSheet: boolean = false
  showFindBar: boolean = false
  findText: string = ''
  findMatchCount: number = 0
  findMatchIndex: number = 0
  showWebCtx: boolean = false
  showLinkCtx: boolean = false
  contextMenuX: number = 0
  contextMenuY: number = 0
  contextImageUrl: string = ''
  contextLinkUrl: string = ''
  webCtxActions: string[] = []
  showUrlEdit: boolean = false
  urlEditText: string = ''

  openImagePreview(url: string): void {
    BrowserStore.openImagePreview(url)
  }

  requestSaveImage(url: string): void {
    BrowserStore.requestSaveImage(url)
  }

  requestCopyImage(url: string): void {
    BrowserStore.requestCopyImage(url)
  }

  openShare(title: string, url: string, previewImage: boolean = false): void {
    BrowserStore.openShare({ title, url, previewImage })
  }

  goBack(): void {
    BrowserNavigation.goBack()
  }

  closeImagePreview(): void {
    BrowserStore.closeImagePreview()
  }

  closeMoreSheet(): void {
    this.showMoreSheet = false
  }

  openMoreSheet(): void {
    this.showMoreSheet = true
  }

  openFindBar(): void {
    this.showFindBar = true
  }

  closeFindBar(webPage: WebPageController): void {
    this.showFindBar = false
    this.findText = ''
    this.findMatchCount = 0
    this.findMatchIndex = 0
    webPage.clearFind()
  }

  findDisplay(): string {
    if (this.findMatchCount <= 0) {
      return '0/0'
    }
    return `${this.findMatchIndex}/${this.findMatchCount}`
  }

  /** 输入关键词触发页内查找；匹配数/当前序号由 onSearchResultReceive 回写 */
  runFindInPage(keyword: string, webPage: WebPageController): void {
    const q = keyword.trim()
    if (q.length === 0) {
      webPage.clearFind()
      this.findMatchCount = 0
      this.findMatchIndex = 0
      return
    }
    webPage.searchInPage(q)
  }

  /** 应用 ArkWeb searchAllAsync / searchNext 的统计回调（ordinal 从 0 起） */
  applySearchResult(activeOrdinal: number, numberOfMatches: number, isDoneCounting: boolean): void {
    if (!isDoneCounting) {
      return
    }
    const total = numberOfMatches > 0 ? Math.floor(numberOfMatches) : 0
    this.findMatchCount = total
    if (total <= 0) {
      this.findMatchIndex = 0
      return
    }
    const ordinal = Math.max(0, Math.floor(activeOrdinal))
    this.findMatchIndex = Math.min(total, ordinal + 1)
  }

  stepFindMatch(forward: boolean, webPage: WebPageController): void {
    if (this.findMatchCount <= 0) {
      return
    }
    webPage.findNext(forward)
  }

  isWebContextMenuVisible(): boolean {
    return this.showWebCtx || this.showLinkCtx
  }

  closeWebContextMenu(): void {
    this.showWebCtx = false
    this.showLinkCtx = false
    this.contextImageUrl = ''
    this.contextLinkUrl = ''
    this.webCtxActions = []
  }

  openImageContextMenu(imageUrl: string, actions: string[]): void {
    this.contextImageUrl = imageUrl
    this.webCtxActions = actions
    this.showWebCtx = true
    this.showLinkCtx = false
  }

  /** 长按锚点 X/Y（vp，相对 BrowsePage 窗口，供 overlay 定位） */
  openLinkContextMenu(linkUrl: string, anchorX: number, anchorY: number): void {
    this.contextLinkUrl = linkUrl
    this.contextMenuX = anchorX
    this.contextMenuY = anchorY
    this.showLinkCtx = true
    this.showWebCtx = false
  }

  handleWebContextAction(action: string, currentUrl: string): void {
    if (action === 'copy_image') {
      const imageUrl = this.contextImageUrl.length > 0 ? this.contextImageUrl : currentUrl
      BrowserStore.requestCopyImage(imageUrl)
      return
    }
    if (action === 'save_image') {
      const imageUrl = this.contextImageUrl.length > 0 ? this.contextImageUrl : currentUrl
      BrowserStore.requestSaveImage(imageUrl)
      return
    }
    if (action === 'share_image') {
      const imageUrl = this.contextImageUrl.length > 0 ? this.contextImageUrl : currentUrl
      const shareOpts: OpenShareOptions = {
        title: BrowserStrings.txt($r('app.string.web_image_share_title')),
        url: imageUrl,
        previewImage: true,
      }
      BrowserStore.openShare(shareOpts)
      return
    }
    if (action === 'open_in_new_tab') {
      const link = this.contextLinkUrl.trim()
      if (link.length > 0) {
        const tabOpts: OpenBrowseOptions = { newTab: true, title: tabHostname(link) }
        BrowserNavigation.openBrowse(link, tabOpts)
      }
      return
    }
    if (action === 'copy_link') {
      const link = this.contextLinkUrl.trim()
      if (link.length > 0) {
        void BrowserStore.copyToClipboard(link)
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_link_copied')))
      }
    }
  }

  openLinkInNewWindow(): void {
    const link = this.contextLinkUrl.trim()
    if (link.length > 0) {
      const tabOpts: OpenBrowseOptions = { newTab: true, title: tabHostname(link) }
      BrowserNavigation.openBrowse(link, tabOpts)
    }
  }

  copyContextLink(): void {
    const link = this.contextLinkUrl.trim()
    if (link.length > 0) {
      void BrowserStore.copyToClipboard(link)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_link_copied')))
    }
  }

  copyContextImage(currentUrl: string): void {
    const imageUrl = this.contextImageUrl.length > 0 ? this.contextImageUrl : currentUrl
    BrowserStore.requestCopyImage(imageUrl)
  }

  openUrlEdit(currentUrl: string): void {
    const clamped = BrowserNavigation.clampAddressInput(currentUrl)
    this.urlEditText = clamped.text
    this.showUrlEdit = true
  }

  closeUrlEdit(): void {
    this.showUrlEdit = false
    this.urlEditText = ''
  }

  applyUrlEditChange(value: string): void {
    BrowserNavigation.applyTextInputChange(value, this.urlEditText.length, (text: string) => {
      this.urlEditText = text
    }, true)
  }

  urlEditSecure(currentUrl: string): boolean {
    const text = this.urlEditText.trim()
    return text.startsWith('https') || currentUrl.startsWith('https')
  }

  isCurrentPageBookmarked(currentUrl: string, bookmarks: BookmarkItem[]): boolean {
    const normalized = BrowserUtils.normalizePageUrl(currentUrl)
    if (!normalized) {
      return false
    }
    return bookmarks.some((b) => {
      return !b.isFolder && !!b.url && BrowserUtils.normalizePageUrl(b.url) === normalized
    })
  }

  copyPageUrl(url: string): void {
    void BrowserStore.copyToClipboard(url)
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_link_copied')))
  }

  resetOverlayState(): void {
    this.showMoreSheet = false
    this.closeWebContextMenu()
    this.showUrlEdit = false
    this.urlEditText = ''
  }
}
