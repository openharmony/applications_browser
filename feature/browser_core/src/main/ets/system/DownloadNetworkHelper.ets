import { connection } from '@kit.NetworkKit'
import { BrowserLog } from 'common'

/** 下载模块用的网络状态探测 */
export class DownloadNetworkHelper {
  /** 当前是否有可用默认网络 */
  static isNetworkAvailable(): boolean {
    try {
      return connection.hasDefaultNetSync()
    } catch (err) {
      BrowserLog.warn(`[DownloadNet] hasDefaultNetSync failed: ${JSON.stringify(err)}`)
      return true
    }
  }
}
