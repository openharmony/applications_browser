import { connection } from '@kit.NetworkKit'
import { BrowserLog } from 'common'
import { DownloadManager } from './DownloadManager'

/** 监听网络断开，自动暂停进行中的下载任务 */
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
      const netConn = connection.createNetConnection()
      netConn.on('netLost', () => {
        BrowserLog.info('[DownloadNet] netLost, pause running downloads')
        void DownloadManager.getInstance().pauseAllRunningDownloads('network')
      })
      netConn.on('netUnavailable', () => {
        BrowserLog.info('[DownloadNet] netUnavailable, pause running downloads')
        void DownloadManager.getInstance().pauseAllRunningDownloads('network')
      })
      netConn.on('netAvailable', () => {
        BrowserLog.info('[DownloadNet] netAvailable, resume network-paused downloads')
        DownloadManager.getInstance().resetNetworkPauseFlag()
        void DownloadManager.getInstance().resumeNetworkPausedDownloads()
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
