/** 下载进度通知 Want 参数键与动作值 */
export class DownloadNotificationParams {
  static readonly KEY_ACTION: string = 'browserDownloadNotifAction'
  static readonly KEY_TASK_ID: string = 'browserDownloadTaskId'
  static readonly ACTION_PAUSE: string = 'pause'
  static readonly ACTION_RESUME: string = 'resume'
  static readonly ACTION_OPEN: string = 'open'
  /** 暂停/继续按钮：SEND_COMMON_EVENT，避免拉起浏览器界面 */
  static readonly COMMON_EVENT: string = 'com.ohos.browser.action.DOWNLOAD_NOTIFICATION'
}
