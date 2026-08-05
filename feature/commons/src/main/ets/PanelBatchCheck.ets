import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'

@Component
export struct PanelBatchCheck {
  @Prop selected: boolean = false
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0

  build() {
    SymbolGlyph(this.selected ?
      $r('sys.symbol.checkmark_circle') :
      $r('sys.symbol.circle'))
      .fontSize(BrowserTheme.uiFontSize(22))
      .fontColor([this.selected ? BrowserTheme.PRIMARY_COLOR : '#c5c5c5'])
  }
}
