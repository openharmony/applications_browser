import { BrowserStore } from 'browser_core'
import { HarmonyDialogStyle } from 'commons'
import { BrowserStrings } from 'common'
import { suggestRename } from 'browser_core'
import { DownloadFileIcon } from './DownloadFileIcon'

@Component
export struct DownloadFlowDialog {
  @StorageLink('browser_dl_dialog') dialogMode: string = ''
  @StorageLink('browser_dl_name') fileName: string = ''
  @StorageLink('browser_dl_size') fileSize: string = ''
  @StorageLink('browser_dl_type') fileType: string = ''

  private close(): void {
    BrowserStore.closeDownloadDialog()
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.dialogMode === 'confirm') {
        this.ConfirmDialog()
      } else if (this.dialogMode === 'duplicate') {
        this.DuplicateDialog()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.dialogMode ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  ConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())
        .onClick(() => this.close())

      Column() {
        Text($r('app.string.download_file_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: HarmonyDialogStyle.MSG_PAD_TOP, bottom: 16 })

        Row({ space: 12 }) {
          DownloadFileIcon({
            fileName: this.fileName,
            localPath: '',
            galleryUri: '',
            status: 'pending'
          })

          Column({ space: 4 }) {
            Text(this.fileName)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(HarmonyDialogStyle.textPrimary())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.fileSize} · ${this.fileType}`)
              .fontSize(13)
              .fontColor(HarmonyDialogStyle.textSecondary())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: HarmonyDialogStyle.MSG_PAD_H,
          right: HarmonyDialogStyle.MSG_PAD_H,
          bottom: 20
        })

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
            .onClick(() => this.close())

          Text($r('app.string.confirm'))
            .fontSize(HarmonyDialogStyle.BTN_FONT)
            .fontColor(HarmonyDialogStyle.emphasize())
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
            .onClick(() => BrowserStore.confirmDownloadProceed())
        }
        .width('100%')
      }
      .width(HarmonyDialogStyle.CARD_WIDTH)
      .constraintSize({ maxWidth: HarmonyDialogStyle.CARD_MAX_WIDTH })
      .backgroundColor(HarmonyDialogStyle.cardBg())
      .borderRadius(HarmonyDialogStyle.CARD_RADIUS)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(5200)
  }

  @Builder
  DuplicateDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())
        .onClick(() => this.close())

      Column() {
        Text($r('app.string.file_exists_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({
            top: HarmonyDialogStyle.MSG_PAD_TOP,
            bottom: 10,
            left: HarmonyDialogStyle.MSG_PAD_H,
            right: HarmonyDialogStyle.MSG_PAD_H
          })

        Text(BrowserStrings.fileExistsMessage(this.fileName))
          .fontSize(HarmonyDialogStyle.SUB_FONT)
          .fontColor(HarmonyDialogStyle.textSecondary())
          .textAlign(TextAlign.Center)
          .lineHeight(20)
          .padding({
            left: HarmonyDialogStyle.MSG_PAD_H,
            right: HarmonyDialogStyle.MSG_PAD_H,
            bottom: 16
          })

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        Text($r('app.string.overwrite_file'))
          .fontSize(HarmonyDialogStyle.BTN_FONT)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
          .onClick(() => BrowserStore.handleDuplicateDownload('overwrite'))

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        Text(BrowserStrings.renameSaveWith(suggestRename(this.fileName)))
          .fontSize(HarmonyDialogStyle.BTN_FONT)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
          .onClick(() => BrowserStore.handleDuplicateDownload('rename'))

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        Text($r('app.string.cancel'))
          .fontSize(HarmonyDialogStyle.BTN_FONT)
          .fontColor(HarmonyDialogStyle.emphasize())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
          .onClick(() => BrowserStore.handleDuplicateDownload('cancel'))
      }
      .width(HarmonyDialogStyle.CARD_WIDTH)
      .constraintSize({ maxWidth: HarmonyDialogStyle.CARD_MAX_WIDTH })
      .backgroundColor(HarmonyDialogStyle.cardBg())
      .borderRadius(HarmonyDialogStyle.CARD_RADIUS)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(5200)
  }
}
