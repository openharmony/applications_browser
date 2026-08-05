import { webview } from '@kit.ArkWeb'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { fileIo } from '@kit.CoreFileKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { DownloadRequest } from 'common'
import { formatFileSizeText } from 'common'
import { BrowserUtils } from 'common'
import { BrowserStrings } from 'common'
import { DownloadPathService } from './DownloadPathService'

const HILOG_DOMAIN: number = 0x0000
const HILOG_TAG: string = 'BrowserApp'

interface PendingWebDownload {
  item: webview.WebDownloadItem
  guid: string
}

/** 网页下载桥接：注册 WebDownloadDelegate，衔接应用内下载确认弹窗 */
export class WebDownloadService {
  private static instance: WebDownloadService | null = null
  private delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate()
  private pending: PendingWebDownload | null = null
  private guidToTaskId: Record<string, string> = {}
  /** 进行中的 ArkWeb 下载项，用于暂停时 cancel */
  private activeWebItems: Record<string, webview.WebDownloadItem> = {}
  private callbacksReady: boolean = false
  /** 无痕下载任务 ID 集合：进度/完成回调不写数据库 */
  private silentTaskIds: Set<string> = new Set()
  /** 当前挂载下载委托的 Web 控制器 */
  private attachedController: webview.WebviewController | null = null

  static getInstance(): WebDownloadService {
    if (WebDownloadService.instance === null) {
      WebDownloadService.instance = new WebDownloadService()
    }
    return WebDownloadService.instance
  }

  /** 在 Web.onControllerAttached 中注册下载委托 */
  attachController(controller: webview.WebviewController): void {
    this.attachedController = controller
    this.ensureDelegateCallbacks()
    try {
      controller.setDownloadDelegate(this.delegate)
      hilog.info(HILOG_DOMAIN, HILOG_TAG, '[WebDownload] setDownloadDelegate ok')
      BrowserLog.info('[WebDownload] setDownloadDelegate ok')
    } catch (err) {
      hilog.error(HILOG_DOMAIN, HILOG_TAG, '[WebDownload] setDownloadDelegate failed: %{public}s', JSON.stringify(err))
      BrowserLog.error(`[WebDownload] setDownloadDelegate failed: ${JSON.stringify(err)}`)
    }
  }

  /** 页面销毁时取消挂起下载并解除 Web 委托 */
  detach(): void {
    this.cancelPendingDownload()
    const taskIds = Object.keys(this.activeWebItems)
    for (let i = 0; i < taskIds.length; i++) {
      this.cancelActiveDownload(taskIds[i])
    }
    this.activeWebItems = {}
    this.guidToTaskId = {}
    this.silentTaskIds.clear()
    if (this.attachedController) {
      try {
        this.attachedController.setDownloadDelegate(new webview.WebDownloadDelegate())
        BrowserLog.info('[WebDownload] detach cleared download delegate')
      } catch (err) {
        BrowserLog.warn(`[WebDownload] detach clear delegate failed: ${JSON.stringify(err)}`)
      }
      this.attachedController = null
    }
  }

  /** 用户取消确认框时调用 */
  cancelPendingDownload(): void {
    if (!this.pending) {
      return
    }
    try {
      this.pending.item.cancel()
      BrowserLog.info(`[WebDownload] pending canceled guid=${this.pending.guid}`)
    } catch (err) {
      BrowserLog.warn(`[WebDownload] pending cancel failed: ${JSON.stringify(err)}`)
    }
    this.pending = null
  }

  /** 用户确认后开始 ArkWeb 下载；手机/平板落盘沙箱，完成后由 DownloadManager 发布到文管 */
  startPendingDownload(taskId: string, fileName: string): boolean {
    if (!this.pending) {
      hilog.warn(HILOG_DOMAIN, HILOG_TAG, '[WebDownload] startPendingDownload: no pending item')
      return false
    }
    const pending = this.pending
    this.pending = null
    const pathService = DownloadPathService.getInstance()
    const useSandboxPipeline = pathService.usesMobileDownloadStrategy() ||
      !pathService.supportsPublicDownloadDir()
    const path = useSandboxPipeline
      ? pathService.buildSavePath(fileName)
      : this.resolveSavePath(fileName)
    this.ensureParentDir(path)
    try {
      pending.item.start(path)
      this.guidToTaskId[pending.guid] = taskId
      this.activeWebItems[taskId] = pending.item
      hilog.info(HILOG_DOMAIN, HILOG_TAG, '[WebDownload] start taskId=%{public}s path=%{public}s', taskId, path)
      BrowserLog.info(`[WebDownload] start taskId=${taskId} path=${path} sandbox=${useSandboxPipeline}`)
      return true
    } catch (err) {
      hilog.error(HILOG_DOMAIN, HILOG_TAG, '[WebDownload] start failed: %{public}s', JSON.stringify(err))
      BrowserLog.error(`[WebDownload] start failed: ${JSON.stringify(err)}`)
      try {
        pending.item.cancel()
      } catch (_cancelErr) {
        // 忽略取消失败
      }
      return false
    }
  }

  /** 暂停/断网时取消进行中的 ArkWeb 下载 */
  cancelActiveDownload(taskId: string): void {
    const item = this.activeWebItems[taskId]
    if (!item) {
      return
    }
    try {
      item.cancel()
      BrowserLog.info(`[WebDownload] cancelActiveDownload taskId=${taskId}`)
    } catch (err) {
      BrowserLog.warn(`[WebDownload] cancelActiveDownload failed taskId=${taskId}: ${JSON.stringify(err)}`)
    }
    this.clearActiveWebItem(taskId)
    const keys = Object.keys(this.guidToTaskId)
    for (let i = 0; i < keys.length; i++) {
      const guid = keys[i]
      if (this.guidToTaskId[guid] === taskId) {
        this.clearGuidMapping(guid)
        break
      }
    }
  }

  private clearActiveWebItem(taskId: string): void {
    const next: Record<string, webview.WebDownloadItem> = {}
    const keys = Object.keys(this.activeWebItems)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      if (key !== taskId) {
        next[key] = this.activeWebItems[key]
      }
    }
    this.activeWebItems = next
  }

  /** 标记为无痕静默下载（不落 download_tasks 表） */
  markSilentDownload(taskId: string): void {
    this.silentTaskIds.add(taskId)
  }

  /** 判断是否无痕静默下载任务 */
  isSilentDownload(taskId: string): boolean {
    return this.silentTaskIds.has(taskId)
  }

  private finishSilentDownload(taskId: string, guid: string, fileName: string): void {
    this.silentTaskIds.delete(taskId)
    this.clearGuidMapping(guid)
    const name = fileName.trim()
    if (name.length > 0) {
      BrowserStore.showToast(BrowserStrings.downloadCompleteToast(name))
    }
  }

  /** 根据 guid 查找关联的下载任务 id */
  findTaskIdByGuid(guid: string): string {
    return this.guidToTaskId[guid] ?? ''
  }

  /** 下载结束，清除 guid 映射 */
  clearGuidMapping(guid: string): void {
    const next: Record<string, string> = {}
    const keys = Object.keys(this.guidToTaskId)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      if (key !== guid) {
        next[key] = this.guidToTaskId[key]
      }
    }
    this.guidToTaskId = next
  }

  private ensureDelegateCallbacks(): void {
    if (this.callbacksReady) {
      return
    }
    this.callbacksReady = true

    this.delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      const url = item.getUrl()
      const name = item.getSuggestedFileName() || 'download'
      const totalBytes = item.getTotalBytes()
      const guid = item.getGuid()
      hilog.info(HILOG_DOMAIN, HILOG_TAG, '[WebDownload] onBeforeDownload url=%{public}s name=%{public}s', url, name)
      BrowserLog.info(`[WebDownload] onBeforeDownload url=${url} name=${name} bytes=${totalBytes}`)

      if (this.pending) {
        this.cancelPendingDownload()
      }
      this.pending = { item: item, guid: guid }

      const file: DownloadRequest = {
        fileName: name,
        fileSizeText: formatFileSizeText(totalBytes),
        fileSizeBytes: totalBytes > 0 ? totalBytes : 0,
        mimeType: BrowserUtils.inferFileTypeLabel(name),
        sourceUrl: url
      }
      BrowserStore.requestDownload(file)
    })

    this.delegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      const guid = item.getGuid()
      const taskId = this.findTaskIdByGuid(guid)
      if (!taskId || this.isSilentDownload(taskId)) {
        return
      }
      const progress = Math.min(100, Math.max(0, Math.floor(item.getPercentComplete())))
      this.activeWebItems[taskId] = item
      BrowserStore.updateWebDownloadProgress(taskId, progress)
    })

    this.delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      const guid = item.getGuid()
      const taskId = this.findTaskIdByGuid(guid)
      BrowserLog.info(`[WebDownload] onDownloadFinish guid=${guid} taskId=${taskId}`)
      if (!taskId) {
        return
      }
      if (this.isSilentDownload(taskId)) {
        const name = item.getSuggestedFileName() || 'download'
        this.finishSilentDownload(taskId, guid, name)
        return
      }
      void BrowserStore.completeWebDownload(taskId)
      this.clearActiveWebItem(taskId)
      this.clearGuidMapping(guid)
    })

    this.delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      const guid = item.getGuid()
      const taskId = this.findTaskIdByGuid(guid)
      BrowserLog.error(`[WebDownload] onDownloadFailed guid=${guid} taskId=${taskId}`)
      if (!taskId) {
        return
      }
      if (this.isSilentDownload(taskId)) {
        this.silentTaskIds.delete(taskId)
        this.clearGuidMapping(guid)
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_failed')))
        return
      }
      void BrowserStore.failWebDownloadWithMessage(taskId,
        BrowserStrings.txt($r('app.string.download_error_network')))
      this.clearActiveWebItem(taskId)
      this.clearGuidMapping(guid)
    })
  }

  /** 构建与 ArkWeb start() 一致的本地保存路径（系统 Download 目录） */
  buildSavePath(fileName: string): string {
    return DownloadPathService.getInstance().buildSavePath(fileName)
  }

  private resolveSavePath(fileName: string): string {
    return this.buildSavePath(fileName)
  }

  private ensureParentDir(filePath: string): void {
    const slash = filePath.lastIndexOf('/')
    if (slash <= 0) {
      return
    }
    const dir = filePath.substring(0, slash)
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
    } catch (_err) {
      try {
        fileIo.mkdirSync(dir, true)
      } catch (_mkdirErr) {
        // 忽略目录创建失败
      }
    }
  }
}
