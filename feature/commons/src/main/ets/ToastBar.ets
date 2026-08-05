import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'

/** 全局 Toast 提示条（绑定 browser_toast） */
@Component
export struct ToastBar {
  /** 当前要展示的 Toast 文案，空字符串时不渲染 */
  @StorageLink('browser_toast') toastMessage: string = ''
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0

  build() {
    if (this.toastMessage) {
      Text(this.toastMessage)
        .fontSize(BrowserTheme.uiFontSize(14))
        .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Regular))
        .fontColor('#ffffff')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('rgba(17, 24, 39, 0.88)')
        .borderRadius(999)
        .position({ x: '50%', y: '78%' })
        .translate({ x: '-50%' })
        .zIndex(9999)
    }
  }
}
