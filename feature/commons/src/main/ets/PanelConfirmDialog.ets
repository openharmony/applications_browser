import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'

/**
 * 鸿蒙系统弹窗视觉 token（对齐系统 AlertDialog 外观，不改业务回调）。
 * 颜色均取 sys.color，随深浅色自动适配。
 */
export class HarmonyDialogStyle {
  static readonly CARD_WIDTH: string = '80%'
  static readonly CARD_MAX_WIDTH: number = 336
  /** 系统警告弹窗常用圆角 */
  static readonly CARD_RADIUS: number = 24
  static readonly MSG_PAD_TOP: number = 24
  static readonly MSG_PAD_BOTTOM: number = 16
  static readonly MSG_PAD_H: number = 24
  static readonly SUB_PAD_BOTTOM: number = 20
  static readonly BTN_PAD_V: number = 16
  static readonly MSG_FONT: number = 16
  static readonly SUB_FONT: number = 14
  static readonly BTN_FONT: number = 16

  static maskColor(): Resource {
    return $r('sys.color.ohos_id_color_mask_thin')
  }

  static cardBg(): Resource {
    return $r('sys.color.ohos_id_color_dialog_bg')
  }

  static textPrimary(): Resource {
    return $r('sys.color.ohos_id_color_text_primary')
  }

  static textSecondary(): Resource {
    return $r('sys.color.ohos_id_color_text_secondary')
  }

  /** 强调操作（确认 / 主按钮） */
  static emphasize(): Resource {
    return $r('sys.color.ohos_id_color_emphasize')
  }

  /** 警示 / 破坏性操作 */
  static warning(): Resource {
    return $r('sys.color.ohos_id_color_warning')
  }

  static separator(): Resource {
    return $r('sys.color.ohos_id_color_list_separator')
  }
}

/** 居中确认弹窗：系统资源样式，逻辑由外部 onCancel / onConfirm 提供 */
@Component
export struct PanelConfirmDialog {
  @Prop message: string = ''
  @Prop subtitle: string = ''
  @Prop confirmLabel: string = ''
  @Prop cancelLabel: string = ''
  /** 仅展示确认按钮（如「知道了」） */
  @Prop hideCancel: boolean = false
  /** 确认按钮是否使用警示色 */
  @Prop confirmDanger: boolean = true
  onCancel?: () => void
  onConfirm?: () => void
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0

  private confirmColor(): Resource {
    return this.confirmDanger ? HarmonyDialogStyle.warning() : HarmonyDialogStyle.emphasize()
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyDialogStyle.maskColor())
        .onClick(() => this.onCancel?.())

      Column() {
        Text(this.message)
          .fontSize(HarmonyDialogStyle.MSG_FONT)
          .fontColor(HarmonyDialogStyle.textPrimary())
          .fontWeight(FontWeight.Medium)
          .lineHeight(22)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({
            top: HarmonyDialogStyle.MSG_PAD_TOP,
            bottom: this.subtitle.length > 0 ? 8 : HarmonyDialogStyle.MSG_PAD_BOTTOM,
            left: HarmonyDialogStyle.MSG_PAD_H,
            right: HarmonyDialogStyle.MSG_PAD_H
          })

        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(HarmonyDialogStyle.SUB_FONT)
            .fontColor(HarmonyDialogStyle.textSecondary())
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({
              bottom: HarmonyDialogStyle.SUB_PAD_BOTTOM,
              left: HarmonyDialogStyle.MSG_PAD_H,
              right: HarmonyDialogStyle.MSG_PAD_H
            })
        }

        Divider()
          .color(HarmonyDialogStyle.separator())
          .strokeWidth(1)
          .width('100%')
          .margin({ left: 16, right: 16 })

        Row() {
          if (!this.hideCancel) {
            Text(this.cancelLabel.length > 0 ? this.cancelLabel : $r('app.string.cancel'))
              .fontSize(HarmonyDialogStyle.BTN_FONT)
              .fontColor(HarmonyDialogStyle.textPrimary())
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
              .onClick(() => this.onCancel?.())
          }

          Text(this.confirmLabel.length > 0 ? this.confirmLabel : $r('app.string.confirm'))
            .fontSize(HarmonyDialogStyle.BTN_FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.confirmColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: HarmonyDialogStyle.BTN_PAD_V })
            .onClick(() => this.onConfirm?.())
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
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
    .key(`panel-confirm-${this.fontUiRev}`)
  }
}
