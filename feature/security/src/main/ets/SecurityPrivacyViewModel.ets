import { SslHandler } from 'browser_core'
import { BrowserNavigation } from 'browser_core'

/** 安全与隐私 ViewModel：SSL 证书异常处理 */
@Observed
export class SecurityPrivacyViewModel {
  sslHost: string = ''
  showSslDialog: boolean = false

  onSslError(host: string): void {
    this.sslHost = host
    this.showSslDialog = true
  }

  allowSslProceed(): void {
    SslHandler.allowProceed(this.sslHost)
    SslHandler.confirmPending()
    this.showSslDialog = false
  }

  cancelSsl(): void {
    SslHandler.cancelPending()
    this.showSslDialog = false
    BrowserNavigation.goHome()
  }
}
