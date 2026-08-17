import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { BrowserUtils } from 'common'
import { GalleryPermissionHelper } from '../security/GalleryPermissionHelper'

/** 系统 Download 目录读写权限（文管可见，仅 2in1 / PC） */
const READ_WRITE_DOWNLOAD: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY'

/** Download 目录权限：2in1 点击开始下载时检查并申请；手机/平板直接落盘文管，无需此权限 */
export class DownloadPermissionHelper {
  /** 手机/平板等便携形态：直接写入文管 Download 子目录，不走 Environment API */
  static usesMobileDownloadStrategy(): boolean {
    const type = deviceInfo.deviceType
    BrowserLog.info(`[DownloadPermission] deviceType=${type}`)
    return type === 'phone' || type === 'pad' || type === 'default' || type === 'wearable'
  }

  /** 设备是否支持 Environment.getUserDownloadDir + 运行时授权（2in1 等） */
  static supportsPublicDownloadDir(): boolean {
    if (DownloadPermissionHelper.usesMobileDownloadStrategy()) {
      return false
    }
    return canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain')
  }

  /** 开始下载前是否需要弹出系统「下载目录」授权 */
  static needsRuntimePermission(): boolean {
    return DownloadPermissionHelper.supportsPublicDownloadDir()
  }

  static isDownloadDirGranted(ctx: common.UIAbilityContext): boolean {
    if (!DownloadPermissionHelper.needsRuntimePermission()) {
      return true
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const tokenId = ctx.applicationInfo.accessTokenId
      const status = atManager.checkAccessTokenSync(tokenId, READ_WRITE_DOWNLOAD)
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    } catch (err) {
      BrowserLog.warn(`DownloadPermission check failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /**
   * 下载前统一校验：先检查权限，未授权则主动申请，授权后再次 sync 校验；仍拒绝则中止下载。
   * 2in1 需 Download 目录权限；图片另需相册写入权限。
   */
  static async ensureBeforeDownload(fileName: string, notifyOnDeny: boolean = true): Promise<boolean> {
    const name = fileName.trim()
    if (name.length === 0) {
      return false
    }
    if (DownloadPermissionHelper.needsRuntimePermission()) {
      const downloadOk = await DownloadPermissionHelper.ensureDownloadDirPermission(notifyOnDeny)
      if (!downloadOk) {
        BrowserLog.warn(`[DownloadPermission] blocked before download file=${name}`)
        return false
      }
    }
    if (BrowserUtils.isImageFile(name)) {
      const galleryOk = await GalleryPermissionHelper.ensureWriteImagePermission(notifyOnDeny)
      if (!galleryOk) {
        BrowserLog.warn(`[DownloadPermission] blocked image download file=${name}`)
        return false
      }
    }
    return true
  }

  /**
   * 检查并申请 Download 目录读写权限；授权后再次 sync 校验 token。
   */
  static async ensureDownloadDirPermission(notifyOnDeny: boolean = true): Promise<boolean> {
    if (!DownloadPermissionHelper.needsRuntimePermission()) {
      return true
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserLog.warn('DownloadPermission no context')
      return false
    }
    if (DownloadPermissionHelper.isDownloadDirGranted(ctx)) {
      return true
    }
    BrowserLog.info('DownloadPermission request READ_WRITE_DOWNLOAD_DIRECTORY')
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const result = await atManager.requestPermissionsFromUser(ctx, [READ_WRITE_DOWNLOAD])
      if (DownloadPermissionHelper.isDownloadDirGranted(ctx)) {
        BrowserLog.info('DownloadPermission granted after request')
        return true
      }
      const dialogShown = DownloadPermissionHelper.wasDialogShown(result)
      BrowserLog.warn(`DownloadPermission denied dialogShown=${dialogShown} ` +
        `results=${JSON.stringify(result.authResults)}`)
      if (!dialogShown) {
        BrowserLog.info('DownloadPermission open settings')
        try {
          await atManager.requestPermissionOnSetting(ctx, [READ_WRITE_DOWNLOAD])
          if (DownloadPermissionHelper.isDownloadDirGranted(ctx)) {
            BrowserLog.info('DownloadPermission granted after settings')
            return true
          }
        } catch (settingErr) {
          BrowserLog.warn(`DownloadPermission settings failed: ${JSON.stringify(settingErr)}`)
        }
      }
    } catch (err) {
      BrowserLog.error(`DownloadPermission request failed: ${JSON.stringify(err)}`)
    }
    if (notifyOnDeny) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_permission_denied')))
    }
    return false
  }

  private static wasDialogShown(result: PermissionRequestResult): boolean {
    if (!result.dialogShownResults || result.dialogShownResults.length === 0) {
      return true
    }
    for (let i = 0; i < result.permissions.length; i++) {
      if (result.permissions[i] === READ_WRITE_DOWNLOAD) {
        return result.dialogShownResults[i] === true
      }
    }
    return result.dialogShownResults[0] === true
  }
}
