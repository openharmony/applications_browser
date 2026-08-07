import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { BrowserStrings } from 'common'
import { tabHostname } from 'browser_core'
import { AppStorageKeys } from 'common'
import { ShareAppAvailability, ShareAppsAvailability, DEFAULT_SHARE_APPS } from 'browser_core'

@Component
export struct ShareSheet {
  @StorageLink('browser_share_visible') @Watch('onShareVisibleChanged') visible: boolean = false
  @StorageLink(AppStorageKeys.SHARE_APPS) shareApps: ShareAppsAvailability = DEFAULT_SHARE_APPS
  @StorageLink('browser_share_title') shareTitle: string = ''
  @StorageLink('browser_share_url') shareUrl: string = ''
  @StorageLink('browser_share_size') shareSize: string = ''
  @StorageLink('browser_share_image') previewImage: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'

  aboutToAppear(): void {
    this.refreshShareApps()
  }

  private onShareVisibleChanged(): void {
    if (!this.visible) {
      return
    }
    this.refreshShareApps()
  }

  /** 打开分享面板时刷新可用应用列表 */
  private refreshShareApps(): void {
    this.shareApps = ShareAppAvailability.getCached()
    void ShareAppAvailability.probe()
  }

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private close(): void {
    BrowserStore.closeShareSheet()
  }

  private displayUrl(): string {
    const url = this.shareUrl
    return url.length > 56 ? `${url.slice(0, 53)}…` : url
  }

  private harmonyMode(): boolean {
    return this.previewImage || this.shareSize.length > 0
  }

  private subLabel(): string {
    if (this.shareSize) {
      return this.shareSize
    }
    return tabHostname(this.shareUrl)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.visible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => this.close())

        Column() {
          if (this.harmonyMode()) {
            this.HarmonySheet()
          } else {
            this.BrowserSheet()
          }
        }
        .width('100%')
        .backgroundColor(BrowserTheme.panelBg(this.isDark()))
        .borderRadius({ topLeft: 20, topRight: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(6500)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  BrowserSheet() {
    Column() {
      Column({ space: 6 }) {
        Text(this.shareTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(BrowserTheme.text(this.isDark()))
          .textAlign(TextAlign.Center)
          .width('100%')
        Text(this.displayUrl())
          .fontSize(12)
          .fontColor(BrowserTheme.textMuted(this.isDark()))
          .textAlign(TextAlign.Center)
          .width('100%')
        this.ShareClipboardSubtitle(true)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 14 })

      Divider()
        .color(BrowserTheme.borderColor(this.isDark()))
        .margin({ left: 16, right: 16 })

      Row() {
        if (this.shareApps.wechat) {
          this.ShareTarget('微', '#07c160', BrowserStrings.txt($r('app.string.share_wechat')), () => {
            void BrowserStore.shareViaWeChat(this.shareTitle, this.shareUrl)
            this.close()
          })
        }
        if (this.shareApps.qq) {
          this.ShareTarget('Q', '#12b7f5', BrowserStrings.txt($r('app.string.share_qq')), () => {
            void BrowserStore.shareViaQQ(this.shareTitle, this.shareUrl)
            this.close()
          })
        }
        if (this.shareApps.sms) {
          this.ShareTarget('✉', '#ff9500', BrowserStrings.txt($r('app.string.share_sms')), () => {
            void BrowserStore.shareViaSms(this.shareTitle, this.shareUrl)
            this.close()
          })
        }
        this.ShareTarget('🔗', '#6366f1', BrowserStrings.txt($r('app.string.copy_link')), () => {
          void BrowserStore.copyToClipboard(this.shareUrl)
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_link_copied')))
          this.close()
        })
        this.ShareTarget('⎘', '#2563eb', BrowserStrings.txt($r('app.string.system_share')), () => {
          void BrowserStore.shareViaSystem(this.shareTitle, this.shareUrl)
          this.close()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .justifyContent(FlexAlign.SpaceAround)

      Text($r('app.string.cancel'))
        .fontSize(15)
        .fontColor(BrowserTheme.text(this.isDark()))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        .onClick(() => this.close())
    }
    .width('100%')
  }

  @Builder
  ShareClipboardSubtitle(centered: boolean) {
    Text($r('app.string.share_clipboard_subtitle'))
      .fontSize(11)
      .fontColor(BrowserTheme.textMuted(this.isDark()))
      .textAlign(centered ? TextAlign.Center : TextAlign.Start)
      .width('100%')
      .margin({ top: 2 })
  }

  @Builder
  ShareTarget(icon: string, color: string, label: string, onTap: () => void) {
    Column({ space: 8 }) {
      Column() {
        Text(icon)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
      }
      .width(48)
      .height(48)
      .borderRadius(14)
      .backgroundColor(color)
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(12)
        .fontColor(BrowserTheme.textSecondary(this.isDark()))
    }
    .onClick(onTap)
  }

  private shareLink(): void {
    void BrowserStore.shareViaSystem(this.shareTitle, this.shareUrl)
  }

  private shareImage(): void {
    void BrowserStore.shareImageViaSystem(this.shareTitle, this.shareUrl)
  }

  @Builder
  HarmonySheet() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.share_one_item'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(BrowserTheme.text(this.isDark()))
          Text(this.subLabel())
            .fontSize(13)
            .fontColor(BrowserTheme.textMuted(this.isDark()))
          this.ShareClipboardSubtitle(false)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('×')
          .fontSize(22)
          .fontColor(BrowserTheme.text(this.isDark()))
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => this.close())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 12 })

      if (this.previewImage) {
        Column() {
          Text($r('app.string.image_label'))
            .fontSize(12)
            .fontColor('#ffffff')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('rgba(0,0,0,0.45)')
            .borderRadius(8)
            .margin(12)
        }
        .width('100%')
        .height(120)
        .backgroundColor('#374151')
        .borderRadius(12)
        .margin({ left: 16, right: 16, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      }

      Scroll() {
        Row({ space: 16 }) {
          if (this.shareApps.systemShare) {
            this.HarmonyApp('⎘', '#2563eb', BrowserStrings.txt($r('app.string.share')), () => {
              if (this.previewImage) {
                this.shareImage()
              } else {
                this.shareLink()
              }
            })
          }
          if (this.shareApps.qq) {
            this.HarmonyApp('Q', '#12b7f5', BrowserStrings.txt($r('app.string.share_qq')), () => {
              void BrowserStore.shareViaQQ(this.shareTitle, this.shareUrl)
            })
          }
          if (!this.previewImage && this.shareApps.sms) {
            this.HarmonyApp('✉', '#ff9500', BrowserStrings.txt($r('app.string.share_sms')), () => {
              void BrowserStore.shareViaSms(this.shareTitle, this.shareUrl)
            })
          }
          if (this.shareApps.wecom) {
            this.HarmonyApp('企', '#4b5563', BrowserStrings.txt($r('app.string.wecom')), () => {
              void BrowserStore.shareViaWeCom(this.shareTitle, this.shareUrl)
            })
          }
          if (this.shareApps.douyin) {
            this.HarmonyApp('♪', '#111827', BrowserStrings.txt($r('app.string.douyin')), () => {
              void BrowserStore.shareViaDouyin(this.shareTitle, this.shareUrl)
            })
          }
          if (this.shareApps.bluetooth) {
            this.HarmonyApp('ᛒ', '#6366f1', BrowserStrings.txt($r('app.string.bluetooth')), () => {
              void BrowserStore.shareViaBluetooth(this.shareTitle, this.shareUrl)
            })
          }
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Row() {
        this.HarmonyAction('⧉', BrowserStrings.txt($r('app.string.copy')), () => {
          void BrowserStore.copyToClipboard(this.shareUrl)
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_copied')))
          this.close()
        })
        if (this.shareApps.transfer) {
          this.HarmonyAction('⇄', BrowserStrings.txt($r('app.string.add_to_transfer')), () => {
            void BrowserStore.shareViaTransfer(this.shareTitle, this.shareUrl)
            this.close()
          })
        }
        this.HarmonyAction('⎙', BrowserStrings.txt($r('app.string.print')), () => {
          void BrowserStore.shareViaPrint(this.shareTitle, this.shareUrl)
          this.close()
        })
        this.HarmonyAction('💾', BrowserStrings.txt($r('app.string.save_as')), () => {
          if (this.previewImage && this.shareUrl.length > 0) {
            BrowserStore.requestSaveImage(this.shareUrl)
          } else if (this.shareUrl.length > 0) {
            void BrowserStore.shareViaSystem(this.shareTitle, this.shareUrl)
          } else {
            BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
          }
          this.close()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
  }

  @Builder
  HarmonyApp(icon: string, color: string, label: string, onTap: () => void) {
    Column({ space: 8 }) {
      Column() {
        Text(icon)
          .fontSize(16)
          .fontColor('#ffffff')
      }
      .width(48)
      .height(48)
      .borderRadius(14)
      .backgroundColor(color)
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(11)
        .fontColor(BrowserTheme.textSecondary(this.isDark()))
    }
    .onClick(() => {
      onTap()
      this.close()
    })
  }

  @Builder
  HarmonyAction(icon: string, label: string, onTap: () => void) {
    Column({ space: 6 }) {
      Text(icon)
        .fontSize(18)
      Text(label)
        .fontSize(11)
        .fontColor(BrowserTheme.textSecondary(this.isDark()))
    }
    .onClick(onTap)
  }
}
