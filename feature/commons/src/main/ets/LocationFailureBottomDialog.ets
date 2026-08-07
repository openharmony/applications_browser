import { BrowserTheme } from 'browser_core'
import { HarmonyDialogStyle } from './PanelConfirmDialog'
import { BrowserStrings } from 'common'
import { AppStorageKeys } from 'common'

/** 网页定位失败底部弹框，须用户点击关闭（系统资源样式） */
@Component
export struct LocationFailureBottomDialog {
  @Prop message: string = ''
  onClose?: () => void
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())

      Column() {
        Text(this.message)
          .fontSize(HarmonyDialogStyle.MSG_FONT)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .lineHeight(24)
          .width('100%')
          .padding({
            left: HarmonyDialogStyle.MSG_PAD_H,
            right: HarmonyDialogStyle.MSG_PAD_H,
            top: 22,
            bottom: 18
          })

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .margin({ left: 16, right: 16 })

        Text(BrowserStrings.txt($r('app.string.got_it')))
          .fontSize(HarmonyDialogStyle.BTN_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(HarmonyDialogStyle.emphasize())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 22 })
          .onClick(() => {
            this.onClose?.()
          })
      }
      .width('100%')
      .backgroundColor(HarmonyDialogStyle.cardBg())
      .borderRadius({ topLeft: HarmonyDialogStyle.CARD_RADIUS, topRight: HarmonyDialogStyle.CARD_RADIUS })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(7000)
    .key(`loc-fail-dialog-${this.fontUiRev}`)
  }
}
