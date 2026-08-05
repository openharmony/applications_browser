import { request } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { WebPageController } from '../web/WebPageController'
import { DownloadPathService } from './DownloadPathService'

/** 系统 Download 服务：大文件、断点续传，手机端可落盘到文管可见目录 */
export class SystemDownloadService {
  /** 手机等设备：不指定 filePath，由系统写入公共下载目录 */
  static async downloadToSystemPath(
    url: string,
    fileName: string,
    onProgress?: (percent: number) => void,
    onTaskReady?: (task: request.DownloadTask) => void
  ): Promise<string> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      throw new Error('no context for system download')
    }
    const config: request.DownloadConfig = {
      url: url,
      title: fileName,
      description: fileName,
      header: SystemDownloadService.buildHeaders(url),
      enableMetered: true,
      enableRoaming: true,
      background: true
    }
    BrowserLog.info(`[SystemDownload] systemPath start url=${url.slice(0, 80)} name=${fileName}`)
    const task = await request.downloadFile(ctx, config)
    if (onTaskReady) {
      onTaskReady(task)
    }
    return new Promise<string>((resolve, reject) => {
      let settled = false
      const settle = (action: () => void): void => {
        if (settled) {
          return
        }
        settled = true
        action()
      }
      task.on('progress', (received: number, total: number) => {
        if (total > 0 && onProgress) {
          onProgress(Math.min(99, Math.floor(received / total * 100)))
        }
      })
      task.on('complete', () => {
        void task.getTaskInfo().then((info) => {
          const savedPath = info.filePath ?? ''
          BrowserLog.info(`[SystemDownload] systemPath complete path=${savedPath}`)
          if (savedPath.length > 0) {
            settle(() => resolve(savedPath))
          } else {
            settle(() => reject(new Error('system download empty path')))
          }
        }).catch((err: Error) => {
          settle(() => reject(err))
        })
      })
      task.on('fail', (err: number) => {
        BrowserLog.error(`[SystemDownload] systemPath fail code=${err}`)
        settle(() => reject(new Error(`system download fail code=${err}`)))
      })
    })
  }

  static async downloadToFile(
    url: string,
    filePath: string,
    onProgress?: (percent: number) => void,
    onTaskReady?: (task: request.DownloadTask) => void
  ): Promise<void> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      throw new Error('no context for system download')
    }
    const config: request.DownloadConfig = {
      url: url,
      filePath: filePath,
      header: SystemDownloadService.buildHeaders(url),
      enableMetered: true,
      enableRoaming: true,
      background: true
    }
    BrowserLog.info(`[SystemDownload] start url=${url.slice(0, 80)} path=${filePath}`)
    const task = await request.downloadFile(ctx, config)
    if (onTaskReady) {
      onTaskReady(task)
    }
    return new Promise<void>((resolve, reject) => {
      let settled = false
      const settle = (action: () => void): void => {
        if (settled) {
          return
        }
        settled = true
        action()
      }
      task.on('progress', (received: number, total: number) => {
        if (total > 0 && onProgress) {
          onProgress(Math.min(99, Math.floor(received / total * 100)))
        }
      })
      task.on('complete', () => {
        BrowserLog.info(`[SystemDownload] complete path=${filePath}`)
        settle(() => resolve())
      })
      task.on('fail', (err: number) => {
        BrowserLog.error(`[SystemDownload] fail code=${err} path=${filePath}`)
        settle(() => reject(new Error(`system download fail code=${err}`)))
      })
    })
  }

  /** 优先系统公共下载；不支持 FolderObtain 时走 systemPath */
  static async downloadPreferPublic(
    url: string,
    fileName: string,
    destPath: string,
    onProgress?: (percent: number) => void,
    onTaskReady?: (task: request.DownloadTask) => void
  ): Promise<string> {
    if (!DownloadPathService.getInstance().supportsPublicDownloadDir()) {
      return SystemDownloadService.downloadToSystemPath(url, fileName, onProgress, onTaskReady)
    }
    await SystemDownloadService.downloadToFile(url, destPath, onProgress, onTaskReady)
    return destPath
  }

  static buildHeaders(sourceUrl: string): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': SystemDownloadService.resolveUserAgent(),
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
    }
    const match = sourceUrl.match(/^(https?:\/\/[^/]+)/i)
    if (match && match.length > 1) {
      headers['Referer'] = `${match[1]}/`
    }
    return headers
  }

  static resolveUserAgent(): string {
    const ctrl = WebPageController.getInstance().getController()
    if (ctrl) {
      try {
        const ua = ctrl.getUserAgent()
        if (ua && ua.length > 0) {
          return ua
        }
      } catch (_err) {
        // 使用默认 UA
      }
    }
    return 'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36'
  }
}
