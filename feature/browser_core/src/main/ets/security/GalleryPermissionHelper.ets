import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'

/** 相册写入权限（保存网页图片到系统相册） */
const WRITE_IMAGE_VIDEO: Permissions = 'ohos.permission.WRITE_IMAGEVIDEO'

/**
 * 相册写入权限：保存图片前检查并主动弹出系统授权框。
 */
export class GalleryPermissionHelper {
  /** 是否已授予相册写入权限 */
  static isWriteImageGranted(ctx: common.UIAbilityContext): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const tokenId = ctx.applicationInfo.accessTokenId
      const status = atManager.checkAccessTokenSync(tokenId, WRITE_IMAGE_VIDEO)
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    } catch (err) {
      BrowserLog.warn(`GalleryPermission check failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /**
   * 确保相册写入权限：未授权时弹出系统授权对话框；用户拒绝后提示说明。
   * @returns 是否可继续保存到相册
   */
  static async ensureWriteImagePermission(notifyOnDeny: boolean = true): Promise<boolean> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserLog.warn('GalleryPermission no context')
      return false
    }
    if (GalleryPermissionHelper.isWriteImageGranted(ctx)) {
      return true
    }
    BrowserLog.info('GalleryPermission request WRITE_IMAGEVIDEO')
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      await atManager.requestPermissionsFromUser(ctx, [WRITE_IMAGE_VIDEO])
      if (GalleryPermissionHelper.isWriteImageGranted(ctx)) {
        BrowserLog.info('GalleryPermission granted after request')
        return true
      }
      BrowserLog.warn('GalleryPermission denied after request')
    } catch (err) {
      BrowserLog.error(`GalleryPermission request failed: ${JSON.stringify(err)}`)
    }
    if (notifyOnDeny) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.image_permission_denied')))
    }
    return false
  }
}
