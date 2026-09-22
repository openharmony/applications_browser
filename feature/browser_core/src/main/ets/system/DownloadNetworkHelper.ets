import { connection } from '@kit.NetworkKit'
import { BrowserLog } from 'common'

/** 下载模块用的网络状态探测 */
export class DownloadNetworkHelper {
  private static lastDefaultNetId: number = -1
  private static defaultNetSwitchAtMs: number = 0
  private static readonly SWITCH_WINDOW_MS: number = 8000

  /** 当前是否有可用默认网络 */
  static isNetworkAvailable(): boolean {
    try {
      return connection.hasDefaultNetSync()
    } catch (err) {
      BrowserLog.warn(`[DownloadNet] hasDefaultNetSync failed: ${JSON.stringify(err)}`)
      return true
    }
  }

  /** 当前默认网 netId，不可用时返回 -1 */
  static getDefaultNetId(): number {
    try {
      if (!connection.hasDefaultNetSync()) {
        return -1
      }
      return connection.getDefaultNetSync().netId
    } catch (err) {
      BrowserLog.warn(`[DownloadNet] getDefaultNetSync failed: ${JSON.stringify(err)}`)
      return -1
    }
  }

  /** 监听启动时记录当前默认网，避免把首次 netAvailable 当成切网 */
  static captureInitialDefaultNetId(): void {
    const netId = DownloadNetworkHelper.getDefaultNetId()
    if (netId >= 0) {
      DownloadNetworkHelper.lastDefaultNetId = netId
    }
  }

  /** 记一次默认网重大变更（断网 / 切卡），供传输失败时按暂停处理 */
  static markDefaultNetSwitch(): void {
    DownloadNetworkHelper.defaultNetSwitchAtMs = Date.now()
  }

  /** 是否处于默认网切换保护窗口内 */
  static isInDefaultNetSwitchWindow(): boolean {
    if (DownloadNetworkHelper.defaultNetSwitchAtMs <= 0) {
      return false
    }
    return Date.now() - DownloadNetworkHelper.defaultNetSwitchAtMs < DownloadNetworkHelper.SWITCH_WINDOW_MS
  }

  /**
   * 对比默认网身份是否变化。
   * 双卡切默认移动网时 netId 会变，但可能不经过完全无网。
   */
  static checkDefaultNetIdentityChanged(): boolean {
    const current = DownloadNetworkHelper.getDefaultNetId()
    const previous = DownloadNetworkHelper.lastDefaultNetId
    if (current >= 0 && previous >= 0 && current !== previous) {
      DownloadNetworkHelper.lastDefaultNetId = current
      DownloadNetworkHelper.markDefaultNetSwitch()
      BrowserLog.info(`[DownloadNet] default netId ${previous} -> ${current}`)
      return true
    }
    if (current >= 0) {
      DownloadNetworkHelper.lastDefaultNetId = current
    }
    return false
  }
}
