import { Want } from '@kit.AbilityKit'
import { commonEventManager } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { DownloadManager } from './DownloadManager'
import { DownloadNotificationParams } from './DownloadNotificationParams'

/** 处理通知栏按钮 / 点击触发的 Want 或公共事件 */
export class DownloadNotificationActionHandler {
  /** 通知正文点击：拉起浏览器并打开下载管理 */
  static handleWant(want: Want): void {
    const params = want.parameters
    if (params === undefined || params === null) {
      return
    }
    DownloadNotificationActionHandler.handleParameters(params)
  }

  /** 通知栏暂停/继续按钮：公共事件，不跳转界面 */
  static handleEventData(data: commonEventManager.CommonEventData): void {
    const params = data.parameters
    if (params === undefined || params === null) {
      return
    }
    DownloadNotificationActionHandler.handleParameters(params as Record<string, Object>)
  }

  private static handleParameters(params: Record<string, Object>): void {
    const actionRaw = params[DownloadNotificationParams.KEY_ACTION]
    if (typeof actionRaw !== 'string' || actionRaw.length === 0) {
      return
    }

    if (actionRaw === DownloadNotificationParams.ACTION_OPEN) {
      BrowserStore.openFeaturePanel('downloads')
      BrowserLog.info('[DownloadNotif] open downloads panel from notification')
      return
    }

    const taskIdRaw = params[DownloadNotificationParams.KEY_TASK_ID]
    if (typeof taskIdRaw !== 'string' || taskIdRaw.length === 0) {
      return
    }

    if (actionRaw === DownloadNotificationParams.ACTION_PAUSE) {
      void DownloadManager.getInstance().pauseDownload(taskIdRaw)
      BrowserLog.info(`[DownloadNotif] pause from notification id=${taskIdRaw}`)
      return
    }

    if (actionRaw === DownloadNotificationParams.ACTION_RESUME) {
      void DownloadManager.getInstance().resumeDownload(taskIdRaw).then((ok: boolean) => {
        if (ok) {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_resumed')))
        }
      })
      BrowserLog.info(`[DownloadNotif] resume from notification id=${taskIdRaw}`)
    }
  }
}
