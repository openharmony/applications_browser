import { commonEventManager } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { DownloadNotificationActionHandler } from './DownloadNotificationActionHandler'
import { DownloadNotificationParams } from './DownloadNotificationParams'

/** 订阅下载通知公共事件，供通知栏暂停/继续在后台处理 */
export class DownloadNotificationEventBridge {
  private static instance: DownloadNotificationEventBridge | null = null
  private subscribed: boolean = false
  private subscriber: commonEventManager.CommonEventSubscriber | null = null

  static getInstance(): DownloadNotificationEventBridge {
    if (DownloadNotificationEventBridge.instance === null) {
      DownloadNotificationEventBridge.instance = new DownloadNotificationEventBridge()
    }
    return DownloadNotificationEventBridge.instance
  }

  /** 注册公共事件订阅（幂等） */
  ensureSubscribed(): void {
    if (this.subscribed || this.subscriber !== null) {
      return
    }
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [DownloadNotificationParams.COMMON_EVENT]
    }
    commonEventManager.createSubscriber(subscribeInfo, (err, subscriber) => {
      if (err) {
        BrowserLog.warn(`[DownloadNotif] createSubscriber failed: ${JSON.stringify(err)}`)
        return
      }
      if (this.subscribed || this.subscriber !== null) {
        try {
          commonEventManager.unsubscribe(subscriber)
        } catch (_e) {
        }
        return
      }
      this.subscriber = subscriber
      commonEventManager.subscribe(subscriber, (subErr, data) => {
        if (subErr) {
          BrowserLog.warn(`[DownloadNotif] subscribe callback failed: ${JSON.stringify(subErr)}`)
          return
        }
        DownloadNotificationActionHandler.handleEventData(data)
      })
      this.subscribed = true
      BrowserLog.info('[DownloadNotif] common event subscribed')
    })
  }

  /** Ability 销毁时取消公共事件订阅 */
  dispose(): void {
    const sub = this.subscriber
    this.subscriber = null
    this.subscribed = false
    if (sub === null) {
      return
    }
    try {
      commonEventManager.unsubscribe(sub)
      BrowserLog.info('[DownloadNotif] common event unsubscribed')
    } catch (err) {
      BrowserLog.warn(`[DownloadNotif] unsubscribe failed: ${JSON.stringify(err)}`)
    }
  }
}
