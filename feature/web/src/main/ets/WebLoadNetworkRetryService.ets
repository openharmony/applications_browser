import { connection } from '@kit.NetworkKit'
import { BrowserLog } from 'common'
import { DownloadNetworkHelper } from 'browser_core'

type WebReloadHandler = () => void

/** 网页因断网加载失败后，监听网络恢复并自动重载 */
export class WebLoadNetworkRetryService {
  private static instance: WebLoadNetworkRetryService | null = null
  private pendingUrl: string = ''
  private reloadHandler: WebReloadHandler | null = null
  private netConnection: connection.NetConnection | null = null
  private watching: boolean = false
  private reloadInFlight: boolean = false
  /** 是否已触发过网络恢复后的 reload（成功后延迟确认再清除 pending） */
  private reloadTriggered: boolean = false
  private pageEndClearTimer: number = -1

  static getInstance(): WebLoadNetworkRetryService {
    if (WebLoadNetworkRetryService.instance === null) {
      WebLoadNetworkRetryService.instance = new WebLoadNetworkRetryService()
    }
    return WebLoadNetworkRetryService.instance
  }

  /** 登记断网未完成 URL，网络恢复后触发 reload */
  scheduleReloadOnNetworkRestore(url: string, reload: WebReloadHandler): void {
    const trimmed = url.trim()
    if (trimmed.length === 0) {
      return
    }
    this.pendingUrl = trimmed
    this.reloadHandler = reload
    this.reloadTriggered = false
    this.cancelPageEndClear()
    this.ensureWatching()
    BrowserLog.info(`[WebNetRetry] scheduled url=${trimmed.slice(0, 80)}`)
  }

  /** 页面加载成功或离开浏览页时清除待重载 */
  clearPending(): void {
    if (this.pendingUrl.length === 0 && !this.watching) {
      return
    }
    this.pendingUrl = ''
    this.reloadHandler = null
    this.reloadInFlight = false
    this.reloadTriggered = false
    this.stopWatching()
    BrowserLog.info('[WebNetRetry] cleared')
  }

  hasPending(): boolean {
    return this.pendingUrl.length > 0
  }

  /** 网络恢复 reload 后 onPageEnd：延迟确认无二次错误页再清除 pending */
  notifyPageEndForRetry(loadedUrl: string): void {
    if (!this.reloadTriggered || this.pendingUrl.length === 0) {
      return
    }
    if (!WebLoadNetworkRetryService.urlsMatch(loadedUrl, this.pendingUrl)) {
      return
    }
    this.cancelPageEndClear()
    this.pageEndClearTimer = setTimeout((): void => {
      this.pageEndClearTimer = -1
      if (this.reloadTriggered && this.pendingUrl.length > 0) {
        this.clearPending()
      }
    }, 400)
  }

  /** 再次出现错误页时取消 onPageEnd 的误清除 */
  cancelPageEndClear(): void {
    if (this.pageEndClearTimer >= 0) {
      clearTimeout(this.pageEndClearTimer)
      this.pageEndClearTimer = -1
    }
  }

  private static urlsMatch(a: string, b: string): boolean {
    return WebLoadNetworkRetryService.normalizeUrl(a) === WebLoadNetworkRetryService.normalizeUrl(b)
  }

  private static normalizeUrl(url: string): string {
    return url.trim().replace(/\/$/, '')
  }

  private ensureWatching(): void {
    if (this.watching) {
      return
    }
    try {
      const netConn = connection.createNetConnection()
      netConn.on('netAvailable', () => {
        BrowserLog.info('[WebNetRetry] netAvailable')
        this.scheduleTryReload(500)
      })
      netConn.on('netCapabilitiesChange', () => {
        if (DownloadNetworkHelper.isNetworkAvailable()) {
          BrowserLog.info('[WebNetRetry] netCapabilitiesChange, network up')
          this.scheduleTryReload(500)
        }
      })
      netConn.on('netConnectionPropertiesChange', () => {
        if (DownloadNetworkHelper.isNetworkAvailable()) {
          BrowserLog.info('[WebNetRetry] netConnectionPropertiesChange, network up')
          this.scheduleTryReload(500)
        }
      })
      netConn.register(() => {
        BrowserLog.info('[WebNetRetry] NetConnection registered')
        if (DownloadNetworkHelper.isNetworkAvailable()) {
          this.scheduleTryReload(300)
        }
      })
      this.netConnection = netConn
      this.watching = true
    } catch (err) {
      BrowserLog.warn(`[WebNetRetry] start failed: ${JSON.stringify(err)}`)
      this.watching = false
    }
  }

  private retryTimer: number = -1

  private scheduleTryReload(delayMs: number): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer)
    }
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1
      this.tryReload()
    }, delayMs)
  }

  private tryReload(): void {
    if (this.reloadInFlight || !this.pendingUrl || !this.reloadHandler) {
      return
    }
    if (!DownloadNetworkHelper.isNetworkAvailable()) {
      return
    }
    const handler = this.reloadHandler
    this.reloadInFlight = true
    this.reloadTriggered = true
    BrowserLog.info(`[WebNetRetry] reload url=${this.pendingUrl.slice(0, 80)}`)
    handler()
    setTimeout((): void => {
      this.reloadInFlight = false
    }, 2500)
  }

  private stopWatching(): void {
    this.cancelPageEndClear()
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer)
      this.retryTimer = -1
    }
    if (this.netConnection !== null) {
      try {
        this.netConnection.unregister(() => {
          BrowserLog.info('[WebNetRetry] NetConnection unregistered')
        })
      } catch (_err) {
        // 忽略注销失败
      }
      this.netConnection = null
    }
    this.watching = false
  }
}
