import { HarmonyDialogStyle } from 'commons'

@Component
export struct DownloadDeleteDialog {
  onCancel?: () => void
  onDeleteBoth?: () => void
  onDeleteTaskOnly?: () => void

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())
        .onClick(() => this.onCancel?.())

      Column() {
        Text($r('app.string.delete_history_confirm'))
          .fontSize(HarmonyDialogStyle.MSG_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({
            top: HarmonyDialogStyle.MSG_PAD_TOP,
            bottom: HarmonyDialogStyle.MSG_PAD_BOTTOM,
            left: HarmonyDialogStyle.MSG_PAD_H,
            right: HarmonyDialogStyle.MSG_PAD_H
          })

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        Text($r('app.string.delete_task_and_file'))
          .fontSize(HarmonyDialogStyle.BTN_FONT)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
          .onClick(() => this.onDeleteBoth?.())

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        Text($r('app.string.delete_task_only'))
          .fontSize(HarmonyDialogStyle.BTN_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.warning())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
          .onClick(() => this.onDeleteTaskOnly?.())

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
          .onClick(() => this.onCancel?.())
      }
      .width(HarmonyDialogStyle.CARD_WIDTH)
      .constraintSize({ maxWidth: HarmonyDialogStyle.CARD_MAX_WIDTH })
      .backgroundColor(HarmonyDialogStyle.cardBg())
      .borderRadius(HarmonyDialogStyle.CARD_RADIUS)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(5000)
  }
}
