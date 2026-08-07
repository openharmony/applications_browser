import { SettingsKeys } from 'common'
import { SettingsRepository } from 'common'
import { BrowserLog } from 'common'

/** SSL 证书异常处理：默认拒绝，UI 确认后调用 pending handler 继续加载 */
export class SslHandler {
  private static allowedHosts: Set<string> = new Set()
  private static pendingHandler: SslErrorHandler | undefined = undefined
  private static pendingHost: string = ''
  private static loaded: boolean = false

  /** 判断 SSL 证书异常时是否允许继续访问该主机 */
  static shouldProceed(host: string): boolean {
    return host.length > 0 && SslHandler.allowedHosts.has(host)
  }

  /**
   * 子资源 SSL：资源主机已信任，或当前页面主框架主机已信任时放行。
   * 用户确认 www.baidu.com 后，t12.baidu.com / bdstatic.com 等子资源一并放行。
   */
  static shouldProceedResource(resourceHost: string, pageHost: string): boolean {
    if (SslHandler.shouldProceed(resourceHost)) {
      return true
    }
    return pageHost.length > 0 && SslHandler.shouldProceed(pageHost)
  }

  /** 从持久化存储恢复已信任主机（应用启动时调用） */
  static async loadPersisted(): Promise<void> {
    if (SslHandler.loaded) {
      return
    }
    SslHandler.loaded = true
    try {
      const raw = await SettingsRepository.getInstance().getValue(SettingsKeys.SSL_ALLOWED_HOSTS)
      if (!raw || raw.length === 0) {
        return
      }
      const parsed = JSON.parse(raw) as string[]
      if (!Array.isArray(parsed)) {
        return
      }
      for (const host of parsed) {
        if (typeof host === 'string' && host.length > 0) {
          SslHandler.allowedHosts.add(host)
        }
      }
      BrowserLog.info(`[SslHandler] loaded trusted hosts=${SslHandler.allowedHosts.size}`)
    } catch (err) {
      BrowserLog.warn(`[SslHandler] loadPersisted failed: ${JSON.stringify(err)}`)
    }
  }

  /** 用户确认后继续访问该主机，并持久化 */
  static allowProceed(host: string): void {
    if (host.length === 0) {
      return
    }
    SslHandler.allowedHosts.add(host)
    void SslHandler.persistAllowedHosts()
  }

  /** 记录主框架 SSL 错误，等待用户弹窗确认 */
  static bindPending(handler: SslErrorHandler, host: string): void {
    SslHandler.pendingHandler = handler
    SslHandler.pendingHost = host
  }

  /** 用户确认：通知 Web 继续并完成 pending 请求 */
  static confirmPending(): void {
    const handler = SslHandler.pendingHandler
    if (handler) {
      handler.handleConfirm()
    }
    SslHandler.clearPending()
  }

  /** 用户取消：通知 Web 终止 pending 请求 */
  static cancelPending(): void {
    const handler = SslHandler.pendingHandler
    if (handler) {
      handler.handleCancel()
    }
    SslHandler.clearPending()
  }

  /** 清除已信任的主机记录 */
  static reset(): void {
    SslHandler.allowedHosts.clear()
    SslHandler.clearPending()
    void SettingsRepository.getInstance().setValue(SettingsKeys.SSL_ALLOWED_HOSTS, '[]')
  }

  private static async persistAllowedHosts(): Promise<void> {
    try {
      const list = Array.from(SslHandler.allowedHosts)
      await SettingsRepository.getInstance().setValue(SettingsKeys.SSL_ALLOWED_HOSTS, JSON.stringify(list))
    } catch (err) {
      BrowserLog.warn(`[SslHandler] persist failed: ${JSON.stringify(err)}`)
    }
  }

  private static clearPending(): void {
    SslHandler.pendingHandler = undefined
    SslHandler.pendingHost = ''
  }
}
