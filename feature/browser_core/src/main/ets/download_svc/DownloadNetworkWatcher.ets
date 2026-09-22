import { connection } from '@kit.NetworkKit'
import { BrowserLog } from 'common'
import { DownloadManager } from './DownloadManager'
import { DownloadNetworkHelper } from '../system/DownloadNetworkHelper'

/**
 * 监听网络断开与默认网切换：暂停进行中的下载。
 * 网络恢复或切到另一张卡后不自动续传，由用户点「继续」断点续传（与断网恢复一致）。
 */
export class DownloadNetworkWatcher {
  private static instance: DownloadNetworkWatcher | null = null
  private netConnection: connection.NetConnection | null = null
  private started: boolean = false

  static getInstance(): DownloadNetworkWatcher {
    if (DownloadNetworkWatcher.instance === null) {
      DownloadNetworkWatcher.instance = new DownloadNetworkWatcher()
    }
    return DownloadNetworkWatcher.instance
  }

  start(): void {
    if (this.started) {
      return
    }
    this.started = true
    try {
      DownloadNetworkHelper.captureInitialDefaultNetId()
      const netConn = connection.createNetConnection()
      netConn.on('netLost', () => {
        BrowserLog.info('[DownloadNet] netLost, pause running downloads')
        DownloadNetworkHelper.markDefaultNetSwitch()
        void DownloadManager.getInstance().pauseAllRunningDownloads('network')
      })
      netConn.on('netUnavailable', () => {
        BrowserLog.info('[DownloadNet] netUnavailable, pause running downloads')
        DownloadNetworkHelper.markDefaultNetSwitch()
        void DownloadManager.getInstance().pauseAllRunningDownloads('network')
      })
      netConn.on('netAvailable', () => {
        // 切卡/断网恢复后保持暂停，不自动续传
        BrowserLog.info('[DownloadNet] netAvailable, keep network-paused downloads paused')
        this.pauseIfDefaultNetSwitched()
        DownloadManager.getInstance().resetNetworkPauseFlag()
      })
      netConn.on('netCapabilitiesChange', () => {
        this.pauseIfDefaultNetSwitched()
      })
      netConn.on('netConnectionPropertiesChange', () => {
        this.pauseIfDefaultNetSwitched()
      })
      netConn.register(() => {
        BrowserLog.info('[DownloadNet] NetConnection registered')
      })
      this.netConnection = netConn
    } catch (err) {
      BrowserLog.warn(`[DownloadNet] start failed: ${JSON.stringify(err)}`)
      this.started = false
    }
  }

  /** 默认网身份变化（如卡1→卡2）时暂停仍在 running 的任务 */
  private pauseIfDefaultNetSwitched(): void {
    if (!DownloadNetworkHelper.checkDefaultNetIdentityChanged()) {
      return
    }
    BrowserLog.info('[DownloadNet] default net switched, pause running downloads')
    void DownloadManager.getInstance().pauseAllRunningDownloads('network')
  }

  stop(): void {
    if (this.netConnection !== null) {
      try {
        this.netConnection.unregister(() => {
          BrowserLog.info('[DownloadNet] NetConnection unregistered')
        })
      } catch (_err) {
        // 忽略注销失败
      }
      this.netConnection = null
    }
    this.started = false
  }
}
