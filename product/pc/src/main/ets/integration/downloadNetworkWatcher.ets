import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadManager } from '../core/downloadManager';

const DOWNLOAD_LOG_DOMAIN: number = 0x0000;
const DOWNLOAD_LOG_TAG: string = 'DownloadTrace';

/** 网络变化时暂停并恢复下载，保留系统下载服务的断点状态。 */
export class DownloadNetworkWatcher {
  private static instance: DownloadNetworkWatcher = new DownloadNetworkWatcher();
  private netConnection: connection.NetConnection | null = null;
  private started: boolean = false;

  static getInstance(): DownloadNetworkWatcher {
    return DownloadNetworkWatcher.instance;
  }

  start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    try {
      const netConnection = connection.createNetConnection();
      netConnection.on('netLost', () => {
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_LOST');
        void DownloadManager.getInstance().pauseAllDownloadsForNetwork();
      });
      netConnection.on('netUnavailable', () => {
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_UNAVAILABLE');
        void DownloadManager.getInstance().pauseAllDownloadsForNetwork();
      });
      netConnection.on('netAvailable', () => {
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_AVAILABLE');
        void DownloadManager.getInstance().resumeNetworkPausedDownloads();
      });
      netConnection.on('netCapabilitiesChange', () => {
        if (this.hasDefaultNetwork()) {
          hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_CAPABILITIES_AVAILABLE');
          void DownloadManager.getInstance().resumeNetworkPausedDownloads();
        }
      });
      netConnection.on('netConnectionPropertiesChange', () => {
        if (this.hasDefaultNetwork()) {
          hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_PROPERTIES_AVAILABLE');
          void DownloadManager.getInstance().resumeNetworkPausedDownloads();
        }
      });
      netConnection.register(() => {
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_WATCHER_REGISTERED');
      });
      this.netConnection = netConnection;
    } catch (_) {
      this.started = false;
      hilog.warn(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_WATCHER_START_FAILED');
    }
  }

  stop(): void {
    const netConnection = this.netConnection;
    if (!netConnection) {
      this.started = false;
      return;
    }
    try {
      netConnection.unregister(() => {
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG, 'NETWORK_WATCHER_UNREGISTERED');
      });
    } catch (_) {
    }
    this.netConnection = null;
    this.started = false;
  }

  private hasDefaultNetwork(): boolean {
    try {
      return connection.hasDefaultNetSync();
    } catch (_) {
      return false;
    }
  }
}
