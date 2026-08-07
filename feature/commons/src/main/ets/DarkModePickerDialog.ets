import { BrowserStore } from 'browser_core'
import { HarmonyDialogStyle } from './PanelConfirmDialog'
import { BrowserStrings } from 'common'
import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'

/** 深色模式选择弹框：跟随系统 / 浅色 / 深色（系统资源样式） */
@Component
export struct DarkModePickerDialog {
  @Prop visible: boolean = false
  onClose?: () => void

  @StorageLink(AppStorageKeys.THEME_PREFERENCE) themePreference: string = 'light'
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1

  private selectMode(mode: string): void {
    BrowserStore.setThemePreference(mode)
    this.onClose?.()
  }

  build() {
    if (!this.visible) {
      Column()
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(HarmonyDialogStyle.maskColor())
          .onClick(() => {
            this.onClose?.()
          })

        Column() {
          Text($r('app.string.dark_mode_dialog_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(HarmonyDialogStyle.textPrimary())
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({
              top: HarmonyDialogStyle.MSG_PAD_TOP,
              bottom: 8,
              left: HarmonyDialogStyle.MSG_PAD_H,
              right: HarmonyDialogStyle.MSG_PAD_H
            })

          ForEach(BrowserStrings.themeModeKeys(), (mode: string) => {
            Row() {
              Text(BrowserStrings.themeModeLabel(mode))
                .fontSize(HarmonyDialogStyle.BTN_FONT)
                .fontColor(HarmonyDialogStyle.textPrimary())
                .layoutWeight(1)
              this.RadioMark(mode === BrowserStrings.normalizeThemeModeKey(this.themePreference))
            }
            .width('100%')
            .padding({
              left: HarmonyDialogStyle.MSG_PAD_H,
              right: HarmonyDialogStyle.MSG_PAD_H,
              top: 16,
              bottom: 16
            })
            .onClick(() => {
              this.selectMode(mode)
            })
          }, (mode: string) => `${mode}-${this.fontUiRev}`)

          Divider()
            .color(HarmonyDialogStyle.separator())
            .strokeWidth(1)
            .width('100%')
            .margin({ top: 4, left: 16, right: 16 })

          Text($r('app.string.cancel'))
            .fontSize(HarmonyDialogStyle.BTN_FONT)
            .fontColor(HarmonyDialogStyle.emphasize())
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: HarmonyDialogStyle.BTN_PAD_V, bottom: 18 })
            .onClick(() => {
              this.onClose?.()
            })
        }
        .width(HarmonyDialogStyle.CARD_WIDTH)
        .constraintSize({ maxWidth: HarmonyDialogStyle.CARD_MAX_WIDTH })
        .backgroundColor(HarmonyDialogStyle.cardBg())
        .borderRadius(HarmonyDialogStyle.CARD_RADIUS)
        .clip(true)
      }
      .width('100%')
      .height('100%')
      .zIndex(7000)
      .hitTestBehavior(HitTestMode.Default)
      .key(`dark-mode-picker-${this.fontUiRev}-${this.themePreference}-${this.fontUiScale.toFixed(2)}`)
    }
  }

  @Builder
  RadioMark(selected: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(22)
          .fontColor([HarmonyDialogStyle.emphasize()])
          .fontWeight(FontWeight.Medium)
      } else {
        Blank()
          .width(22)
          .height(22)
      }
    }
    .width(28)
    .height(28)
  }
}
