import { fileIo } from '@kit.CoreFileKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { DownloadPathService } from './DownloadPathService'
import { DownloadPermissionHelper } from './DownloadPermissionHelper'

/** 将残留沙箱文件发布到文管 Download 目录 */
export class DownloadPublishService {
  /** 是否为应用沙箱路径（文管不可见） */
  static isSandboxPath(path: string): boolean {
    if (!path || path.length === 0) {
      return true
    }
    const ctx = BrowserStore.getContext()
    const filesDir = ctx?.filesDir ?? ''
    const cacheDir = ctx?.cacheDir ?? ''
    if (filesDir.length > 0 && path.startsWith(filesDir)) {
      return true
    }
    if (cacheDir.length > 0 && path.startsWith(cacheDir)) {
      return true
    }
    return path.includes('/haps/') && !path.includes('/Download')
  }

  /** 沙箱文件复制到文管公共 Download，返回最终路径 */
  static publishToPublicIfNeeded(localPath: string, fileName: string): string | null {
    if (!DownloadPublishService.isSandboxPath(localPath)) {
      return localPath
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return null
    }
    if (!DownloadPermissionHelper.usesMobileDownloadStrategy() &&
      !DownloadPermissionHelper.isDownloadDirGranted(ctx)) {
      return null
    }
    return DownloadPublishService.copyToPublicDownload(localPath, fileName)
  }

  /** 复制到文管 Download 目录 */
  static copyToPublicDownload(localPath: string, fileName: string): string | null {
    if (!DownloadPathService.getInstance().fileExists(localPath)) {
      BrowserLog.warn(`[DownloadPublish] source missing path=${localPath}`)
      return null
    }
    try {
      const publicDir = DownloadPathService.getInstance().getPublicDownloadDir()
      if (!publicDir || publicDir.length === 0) {
        BrowserLog.error('[DownloadPublish] no public download dir for copy')
        return null
      }
      DownloadPathService.getInstance().ensureDirectory(publicDir)
      const uniqueName = DownloadPathService.getInstance().resolveUniqueFileName(publicDir, fileName)
      const destPath = `${publicDir}/${uniqueName}`
      if (localPath === destPath) {
        return destPath
      }
      fileIo.copyFileSync(localPath, destPath)
      BrowserLog.info(`[DownloadPublish] copied to public src=${localPath} dest=${destPath}`)
      try {
        fileIo.unlinkSync(localPath)
      } catch (_err) {
        // 保留沙箱副本不影响主流程
      }
      return destPath
    } catch (err) {
      BrowserLog.error(`[DownloadPublish] copy failed: ${JSON.stringify(err)}`)
      return null
    }
  }
}
