import { fileIo } from '@kit.CoreFileKit'

import { BrowserLog } from 'common'

import { DownloadPathService } from './DownloadPathService'



/** 将本地文件复制到文管 Download 子目录 */

export class MobileDownloadPublishService {

  /** 将任意本地文件复制到文管公共 Download 目录 */

  static publishAfterDownload(sourcePath: string, fileName: string): string | null {

    const pathService = DownloadPathService.getInstance()

    if (!pathService.fileExists(sourcePath)) {

      BrowserLog.warn(`[MobilePublish] source missing path=${sourcePath}`)

      return null

    }

    if (pathService.isMobilePublicPath(sourcePath)) {

      BrowserLog.info(`[MobilePublish] already in public dir path=${sourcePath}`)

      return sourcePath

    }

    const publicDir = pathService.getPublicDownloadDir()

    if (!publicDir) {

      BrowserLog.warn('[MobilePublish] no writable public download dir')

      return null

    }

    const safeName = pathService.sanitizeFileName(fileName)

    const destPath = `${publicDir}/${pathService.resolveUniqueFileName(publicDir, safeName)}`

    if (sourcePath === destPath) {

      return destPath

    }

    try {

      pathService.deleteFileAtPath(destPath)

      fileIo.copyFileSync(sourcePath, destPath)

      BrowserLog.info(`[MobilePublish] copied src=${sourcePath} dest=${destPath}`)

      try {

        fileIo.unlinkSync(sourcePath)

      } catch (_err) {

        // 保留源文件副本

      }

      return destPath

    } catch (err) {

      BrowserLog.error(`[MobilePublish] copy failed src=${sourcePath} dest=${destPath}: ${JSON.stringify(err)}`)

      return null

    }

  }

}

