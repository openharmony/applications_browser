import { AppStorageKeys, DownloadRequest, ShareSheetParams, OpenShareOptions } from 'common'
import { DownloadTask, createDownloadTask, CreateDownloadTaskInput, formatFileSizeText, DownloadStatus } from 'common'
import { DownloadRepository } from 'common'
import { AppStateSync } from '../AppStateSync'
import { BrowserUtils } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { BrowserLog } from 'common'
import { pasteboard } from '@kit.BasicServicesKit'
import { common, Want, wantConstant } from '@kit.AbilityKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { request } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { WebDownloadService } from './WebDownloadService'
import { ImageGalleryService } from '../system/ImageGalleryService'
import { DownloadPathService } from './DownloadPathService'
import { DownloadPermissionHelper } from './DownloadPermissionHelper'
import { SystemDownloadService } from './SystemDownloadService'
import { DownloadPublishService } from './DownloadPublishService'
import { MobileDownloadPublishService } from './MobileDownloadPublishService'
import { DownloadNotificationService } from './DownloadNotificationService'
import { DownloadSpaceGuard } from './DownloadSpaceGuard'
import { DownloadNetworkHelper } from '../system/DownloadNetworkHelper'
import { ShareAppAvailability } from '../system/ShareAppAvailability'
import { SslHandler } from '../security/SslHandler'
import { getBrowserUIContext } from 'common'

/** 打开下载文件的结果 */
export type OpenDownloadResult = 'opened' | 'missing' | 'not_ready' | 'failed' | 'not_found'

/** 下载确认弹窗点「确定」后的结果 */
export interface ConfirmDownloadOutcome {
  started: boolean
  notificationEnabled: boolean
}

/** 下载前剩余空间校验参数 */
export interface DownloadSpaceGuardParams {
  sizeText?: string
  fileSizeBytes?: number
  sourceUrl?: string
  showToast?: boolean
  failTaskId?: string
}

/** 下载文件发布结果（沙箱 → 公共 Download） */
export interface DownloadPublishResult {
  path: string
  visibility: 'public' | 'sandbox'
}

/** 系统下载回调 */
interface SystemDownloadHooks {
  onProgress: (pct: number) => void
  onTaskReady: (task: request.DownloadTask) => void
}

/** 下载任务队列、进度、暂停与重试 */
export class DownloadManager {
  private static instance: DownloadManager | null = null
  private timers: Map<string, number> = new Map()
  /** 下载进度 UI 刷新节流，避免高频 DB/AppStorage 更新冻屏 */
  private progressUiGate: Map<string, number> = new Map()
  /** 进行中的系统 downloadFile 任务，暂停时可 remove */
  private systemDownloadTasks: Map<string, request.DownloadTask> = new Map()
  /** 进行中的 HTTP 流式下载，暂停时可 destroy */
  private httpDownloadRequests: Map<string, http.HttpRequest> = new Map()
  /** 断网批量暂停时避免重复 Toast */
  private networkPauseToastShown: boolean = false
  /** 断网暂停的任务 id，网络恢复后自动断点续传 */
  private networkPausedTaskIds: Set<string> = new Set()
  /** 暂停/断网中止传输时保留残缺文件，避免 stream settle 误删 */
  private downloadAbortFlags: Map<string, 'pause'> = new Map()
  /** 同时下载的最大并发数（超过时新任务进入排队） */
  private static readonly MAX_CONCURRENT_DOWNLOADS: number = 5
  /** 当前 running 任务计数（仅 DownloadManager 内部使用，不持久化） */
  private runningCount: number = 0

  /** 获取 DownloadManager 单例 */
  static getInstance(): DownloadManager {
    if (DownloadManager.instance === null) {
      DownloadManager.instance = new DownloadManager()
    }
    return DownloadManager.instance
  }

  /** 获取全部下载任务列表 */
  async getAll(): Promise<DownloadTask[]> {
    return DownloadRepository.getInstance().findAll()
  }

  /** 发起下载请求并弹出确认对话框；重名将在保存时自动追加 (1)(2)… */
  requestDownload(file: DownloadRequest): void {
    const name = file.fileName.trim()
    if (!name) {
      return
    }
    AppStorage.set(AppStorageKeys.DL_NAME, name)
    AppStorage.set(AppStorageKeys.DL_SIZE, file.fileSizeText || '')
    AppStorage.set(AppStorageKeys.DL_SIZE_BYTES, file.fileSizeBytes ?? 0)
    AppStorage.set(AppStorageKeys.DL_TYPE, file.mimeType || BrowserUtils.inferFileTypeLabel(name))
    AppStorage.set(AppStorageKeys.DL_SOURCE, file.sourceUrl ?? '')
    AppStorage.set(AppStorageKeys.DL_DIALOG, 'confirm')
  }

  /** 关闭下载确认对话框；confirm 流程传 false 以保留挂起的 WebDownloadItem */
  closeDownloadDialog(cancelWebPending: boolean = true): void {
    if (cancelWebPending) {
      WebDownloadService.getInstance().cancelPendingDownload()
    }
    AppStorage.set(AppStorageKeys.DL_DIALOG, '')
  }

  /** 确认下载并创建下载任务（自动处理重名） */
  async confirmDownloadProceed(): Promise<ConfirmDownloadOutcome> {
    const denied: ConfirmDownloadOutcome = { started: false, notificationEnabled: false }
    const rawName = AppStorage.get<string>(AppStorageKeys.DL_NAME) ?? ''
    const sizeText = AppStorage.get<string>(AppStorageKeys.DL_SIZE) ?? ''
    if (!rawName) {
      this.closeDownloadDialog(true)
      return denied
    }
    const notifReady = await DownloadNotificationService.getInstance().ensureNotificationAccess(true)
    DownloadNotificationService.getInstance().markNotificationEnabledForSession(notifReady)
    const granted = await DownloadPermissionHelper.ensureBeforeDownload(rawName)
    if (!granted) {
      WebDownloadService.getInstance().cancelPendingDownload()
      return denied
    }
    const sourceUrl = AppStorage.get<string>(AppStorageKeys.DL_SOURCE) ?? ''
    this.closeDownloadDialog(false)
    void this.executeConfirmedDownload(rawName, sizeText, sourceUrl)
    return { started: true, notificationEnabled: notifReady }
  }

  /** 后台执行确认下载（路径探测、空间检查、落盘） */
  private async executeConfirmedDownload(rawName: string, sizeText: string, sourceUrl: string): Promise<void> {
    await this.sleepMs(100)
    const sizeBytes = AppStorage.get<number>(AppStorageKeys.DL_SIZE_BYTES) ?? 0
    const spaceOk = await this.ensureDownloadSpace({
      sizeText,
      fileSizeBytes: sizeBytes,
      sourceUrl,
      showToast: true
    })
    if (!spaceOk) {
      WebDownloadService.getInstance().cancelPendingDownload()
      return
    }
    const fileName = DownloadPathService.getInstance().resolveUniqueDownloadName(rawName)
    await this.proceedDownload(fileName, sizeText, sourceUrl, sizeBytes)
  }

  /** 处理重复文件下载（取消、覆盖或重命名） */
  async handleDuplicateDownload(act: string): Promise<void> {
    if (act === 'cancel') {
      this.closeDownloadDialog()
      return
    }
    const name = AppStorage.get<string>(AppStorageKeys.DL_NAME) ?? ''
    if (act === 'overwrite') {
      const all = await DownloadRepository.getInstance().findAll()
      for (const d of all.filter((x) => x.fileName === name)) {
        await DownloadRepository.getInstance().deleteById(d.id)
      }
      await AppStateSync.refreshDownloads()
    } else if (act === 'rename') {
      const name = AppStorage.get<string>(AppStorageKeys.DL_NAME) ?? ''
      AppStorage.set(AppStorageKeys.DL_NAME,
        DownloadPathService.getInstance().resolveUniqueDownloadName(name))
    }
    AppStorage.set(AppStorageKeys.DL_DIALOG, 'confirm')
  }

  /** 创建下载任务并开始下载（ArkWeb / HTTP / data URL）；无痕模式仅落盘不入下载列表 */
  async proceedDownload(fileName: string, sizeText: string, sourceUrl: string = '',
    knownSizeBytes: number = 0): Promise<void> {
    const granted = await DownloadPermissionHelper.ensureBeforeDownload(fileName, false)
    if (!granted) {
      WebDownloadService.getInstance().cancelPendingDownload()
      return
    }
    const parsedSize = knownSizeBytes > 0 ? knownSizeBytes : BrowserUtils.parseFileSizeText(sizeText)
    const spaceOk = await this.ensureDownloadSpace({
      sizeText,
      fileSizeBytes: parsedSize,
      sourceUrl,
      showToast: true
    })
    if (!spaceOk) {
      WebDownloadService.getInstance().cancelPendingDownload()
      return
    }
    if (BrowserStore.isIncognito()) {
      await this.proceedIncognitoDownload(fileName, sourceUrl, parsedSize, sizeText)
      return
    }
    // 同步一次真实 running 数，避免依赖易过期的缓存
    await this.syncRunningCountFromDb()
    const initialStatus: DownloadStatus =
      this.runningCount < DownloadManager.MAX_CONCURRENT_DOWNLOADS ? 'running' : 'queued'
    const taskInput: CreateDownloadTaskInput = {
      id: `d${Date.now()}`,
      fileName,
      sourceUrl,
      status: initialStatus,
      progress: 0,
      fileSize: parsedSize > 0 ? parsedSize : undefined,
      mimeType: BrowserUtils.inferMimeType(fileName)
    }
    const task = createDownloadTask(taskInput)
    await DownloadRepository.getInstance().upsert(task)
    await AppStateSync.refreshDownloads()
    if (initialStatus === 'queued') {
      BrowserLog.info(`proceedDownload queued id=${task.id} file=${fileName} runningCount=${this.runningCount}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_queued_toast'), fileName))
      return
    }
    this.runningCount++
    await this.startTaskByMode(task, fileName, sourceUrl)
  }

  /** 根据任务类型分发到 Web/系统/HTTP/模拟下载；调用方需保证 runningCount 已 +1 */
  private async startTaskByMode(task: DownloadTask, fileName: string, sourceUrl: string): Promise<void> {
    this.syncRunningNotification(task)
    const id = task.id
    const webStarted = WebDownloadService.getInstance().startPendingDownload(id, fileName)
    if (webStarted) {
      task.localPath = WebDownloadService.getInstance().buildSavePath(fileName)
      await DownloadRepository.getInstance().upsert(task)
      await AppStateSync.refreshDownloads()
      return
    }
    BrowserLog.info(`[Download] WebDownload not used id=${id} fallback HTTP sourceUrl=${sourceUrl.slice(0, 80)}`)
    if (BrowserUtils.isDirectDownloadUrl(sourceUrl)) {
      task.localPath = WebDownloadService.getInstance().buildSavePath(fileName)
      this.prepareDownloadTargetPath(task)
      await DownloadRepository.getInstance().upsert(task)
      await AppStateSync.refreshDownloads()
      void this.downloadFromUrl(id, sourceUrl, task.localPath, true)
      return
    }
    BrowserLog.warn(`startTaskByMode no handler sourceUrl=${sourceUrl}`)
    this.simulateDownload(id)
  }

  /** 重新开始指定下载任务 */
  async startDownload(id: string): Promise<boolean> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item) {
      return false
    }
    await this.prepareDownloadNotificationAccess()
    const granted = await DownloadPermissionHelper.ensureBeforeDownload(item.fileName)
    if (!granted) {
      return false
    }
    if (item.status !== 'pending' && item.status !== 'queued' && item.status !== 'paused' && item.status !== 'failed') {
      return false
    }
    const isResume = item.status === 'paused'
    if (BrowserUtils.isDirectDownloadUrl(item.sourceUrl)) {
      item.localPath = item.localPath.length > 0
        ? item.localPath
        : WebDownloadService.getInstance().buildSavePath(item.fileName)
    }
    if (isResume) {
      item.localPath = DownloadPathService.getInstance().resolveResumeLocalPath(item)
      this.syncProgressFromPartialFile(item)
      const spaceOk = await this.checkSpaceBeforeResume(item)
      if (!spaceOk) {
        return false
      }
      await DownloadRepository.getInstance().upsert(item)
    } else {
      const spaceOk = await this.ensureDownloadSpace({
        fileSizeBytes: item.fileSize,
        sourceUrl: item.sourceUrl,
        showToast: true
      })
      if (!spaceOk) {
        return false
      }
      this.prepareDownloadTargetPath(item)
    }
    const started = await this.activateOrQueueTask(item, true, isResume)
    if (!started) {
      await DownloadRepository.getInstance().upsert(item)
      return true
    }
    this.syncRunningNotification(item)
    if ((BrowserUtils.isDirectDownloadUrl(item.sourceUrl) || item.sourceUrl.trim().length > 0) &&
      item.localPath.length > 0) {
      await DownloadRepository.getInstance().upsert(item)
      void this.downloadFromUrl(id, item.sourceUrl, item.localPath, !isResume)
      this.kickstartDownloadNotification(id)
      return true
    }
    this.simulateDownload(id)
    return true
  }

  /** 无痕模式：文件正常保存，但不写入 download_tasks 表 */
  private async proceedIncognitoDownload(fileName: string, sourceUrl: string,
    knownSizeBytes: number = 0, sizeText: string = ''): Promise<void> {
    const spaceOk = await this.ensureDownloadSpace({
      sizeText,
      fileSizeBytes: knownSizeBytes,
      sourceUrl,
      showToast: true
    })
    if (!spaceOk) {
      WebDownloadService.getInstance().cancelPendingDownload()
      return
    }
    const ephemeralId = `silent_${Date.now()}`
    WebDownloadService.getInstance().markSilentDownload(ephemeralId)
    const webStarted = WebDownloadService.getInstance().startPendingDownload(ephemeralId, fileName)
    if (webStarted) {
      return
    }
    if (BrowserUtils.isDirectDownloadUrl(sourceUrl)) {
      const path = WebDownloadService.getInstance().buildSavePath(fileName)
      void this.downloadFromUrlSilent(sourceUrl, path, fileName)
      return
    }
    BrowserLog.warn(`proceedIncognitoDownload no handler sourceUrl=${sourceUrl}`)
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_started')))
  }

  /** 无痕模式 HTTP/data URL 下载：图片写入图库，其他文件落盘文管 Download */
  private async downloadFromUrlSilent(sourceUrl: string, destPath: string, fileName: string = ''): Promise<void> {
    let targetPath = destPath
    try {
      if (sourceUrl.trim().startsWith('data:')) {
        targetPath = this.writeWithFallback(destPath, (path) => {
          this.saveDataUrlToFile(sourceUrl, path)
        })
      } else {
        targetPath = await this.saveHttpUrlToFile(sourceUrl, destPath, 'silent')
      }
      BrowserLog.info(`downloadFromUrlSilent ok path=${targetPath}`)
      const name = fileName.length > 0 ? fileName : targetPath.substring(targetPath.lastIndexOf('/') + 1)
      const published = await this.publishDownloadPathIfNeeded(targetPath, name)
      targetPath = published.path
      if (BrowserUtils.isImageFile(name)) {
        const galleryUri = await ImageGalleryService.getInstance().saveFileToGalleryReturningUri(targetPath, name)
        if (galleryUri && galleryUri.length > 0) {
          DownloadPathService.getInstance().deleteFileAtPath(targetPath)
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.image_saved_to_gallery')))
        } else if (published.visibility === 'sandbox') {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_failed')))
        } else {
          BrowserStore.showToast(BrowserStrings.txt($r('app.string.image_save_gallery_failed')))
        }
        return
      }
      if (published.visibility === 'sandbox') {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_publish_failed')))
      }
    } catch (err) {
      BrowserLog.error(`downloadFromUrlSilent failed url=${sourceUrl}: ${JSON.stringify(err)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_failed')))
    }
  }

  /** 更新网页下载进度（节流，避免大文件下载时 UI 卡死） */
  async updateWebDownloadProgress(id: string, progress: number): Promise<void> {
    const pct = Math.min(100, Math.max(0, Math.floor(progress)))
    const now = Date.now()
    const lastAt = this.progressUiGate.get(id) ?? 0
    if (pct < 100 && now - lastAt < 400) {
      return
    }
    this.progressUiGate.set(id, now)
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item || item.status !== 'running') {
      return
    }
    if (item.progress === pct) {
      return
    }
    item.progress = pct
    await DownloadRepository.getInstance().upsert(item)
    AppStateSync.patchDownloadItem(item)
    this.syncRunningNotification(item)
  }

  /** 网页下载完成：沙箱落盘后发布到文管，发布失败则标记失败 */
  async completeWebDownload(id: string): Promise<void> {
    this.clearTimer(id)
    this.progressUiGate.delete(id)
    this.clearActiveTransfer(id)
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item || item.status !== 'running') {
      return
    }
    item.progress = 100
    let path = this.resolveDownloadLocalPath(item)
    if (!path || !this.fileExists(path)) {
      await this.failWebDownloadWithReason(id, BrowserStrings.txt($r('app.string.download_error_file_missing')), [])
      return
    }
    item.localPath = path
    const sandboxPathBeforePublish = path
    try {
      const stat = fileIo.statSync(path)
      item.fileSize = stat.size
    } catch (_err) {
      // 忽略 stat 失败
    }

    const published = await this.publishDownloadPathIfNeeded(path, item.fileName)
    path = published.path
    if (BrowserUtils.isImageFile(item.fileName)) {
      const galleryUri = await ImageGalleryService.getInstance().saveFileToGalleryReturningUri(path, item.fileName)
      if (galleryUri && galleryUri.length > 0) {
        item.galleryUri = galleryUri
        DownloadPathService.getInstance().deleteFileAtPath(path)
        item.localPath = ''
        item.status = 'done'
        item.errorMessage = ''
      } else if (published.visibility === 'sandbox') {
        await this.failWebDownloadWithReason(id,
          BrowserStrings.txt($r('app.string.download_publish_failed')), [sandboxPathBeforePublish, path])
        return
      } else {
        item.localPath = path
        item.status = 'done'
        item.errorMessage = ''
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.image_save_gallery_failed')))
      }
    } else if (published.visibility === 'sandbox') {
      await this.failWebDownloadWithReason(id,
        BrowserStrings.txt($r('app.string.download_publish_failed')), [sandboxPathBeforePublish, path])
      return
    } else {
      item.localPath = path
      item.status = 'done'
      item.errorMessage = ''
    }
    await DownloadRepository.getInstance().upsert(item)
    await AppStateSync.refreshDownloads()
    this.finishDownloadNotification(id, item.fileName)
    if (this.runningCount > 0) {
      this.runningCount--
    }
    void this.tryPromoteQueuedTask()
    if (item.status === 'done' && BrowserUtils.canPreviewInBrowser(item.fileName)) {
      BrowserLog.info(`[FilePreview] auto open after web download id=${id} name=${item.fileName}`)
      void this.openDownloadFile(id)
    }
  }

  /** 网页下载失败 */
  async failWebDownload(id: string): Promise<void> {
    await this.failWebDownloadWithReason(id, BrowserStrings.txt($r('app.string.download_failed')))
  }

  /** 标记下载失败并写入原因（供 WebDownload 等外部回调） */
  async failWebDownloadWithMessage(id: string, reason: string): Promise<void> {
    await this.failWebDownloadWithReason(id, reason)
  }

  /** 标记下载失败并写入原因；同时清理沙箱与文管残留文件 */
  private async failWebDownloadWithReason(id: string, reason: string, extraPaths: string[] = []): Promise<void> {
    this.clearTimer(id)
    this.progressUiGate.delete(id)
    this.clearActiveTransfer(id)
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item) {
      return
    }
    if (item.status === 'paused') {
      return
    }
    const wasRunning = item.status === 'running'
    this.cleanupFailedDownloadFiles(item, extraPaths)
    item.status = 'failed'
    item.errorMessage = reason.length > 0 ? reason : BrowserStrings.txt($r('app.string.download_failed'))
    item.localPath = ''
    await DownloadRepository.getInstance().upsert(item)
    await AppStateSync.refreshDownloads()
    this.clearDownloadNotification(id)
    BrowserStore.showToast(item.errorMessage)
    if (wasRunning && this.runningCount > 0) {
      this.runningCount--
    }
    void this.tryPromoteQueuedTask()
  }

  /** 失败/异常时删除沙箱、文管及任务关联路径上的残缺文件 */
  private cleanupFailedDownloadFiles(item: DownloadTask, extraPaths: string[] = []): void {
    const pathService = DownloadPathService.getInstance()
    const paths: string[] = []
    const push = (p: string): void => {
      const trimmed = p.trim()
      if (trimmed.length > 0) {
        paths.push(trimmed)
      }
    }
    for (let i = 0; i < extraPaths.length; i++) {
      push(extraPaths[i])
    }
    push(item.localPath)
    push(this.resolveDownloadLocalPath(item))
    pathService.cleanupFailedArtifacts(item.fileName, paths)
  }

  private extractDownloadErrorMessage(err: object | string): string {
    const raw = DownloadManager.formatErrorText(err)
    const lower = raw.toLowerCase()
    if (raw.includes('13400001') || lower.includes('enospc') || lower.includes('no space') ||
      lower.includes('disk full') || (lower.includes('storage') && lower.includes('insufficient'))) {
      return BrowserStrings.txt($r('app.string.download_error_storage'))
    }
    if (raw.includes('2300060') || lower.includes('ssl') || lower.includes('certificate') ||
      lower.includes('peer certificate')) {
      return BrowserStrings.txt($r('app.string.download_error_ssl'))
    }
    if (raw.includes('2300018') || lower.includes('partial file') || lower.includes('econnreset') ||
      lower.includes('etimedout') || lower.includes('network') || lower.includes('timeout') ||
      lower.includes('http status 5') || raw.includes('all download methods failed')) {
      return BrowserStrings.txt($r('app.string.download_error_network'))
    }
    if (lower.includes('http status 4') && !lower.includes('416')) {
      return BrowserStrings.txt($r('app.string.download_error_network'))
    }
    if (raw.length > 0 && raw.length < 160 && !raw.startsWith('{')) {
      return raw
    }
    return BrowserStrings.txt($r('app.string.download_failed'))
  }

  /** 从 Error / BusinessError / 字符串提取可读错误文本 */
  private static formatErrorText(err: object | string): string {
    if (typeof err === 'string') {
      return err
    }
    if (err instanceof Error) {
      return err.message.length > 0 ? err.message : err.name
    }
    const record = err as Record<string, string | number>
    const code = record['code']
    const message = record['message']
    if (code !== undefined || message !== undefined) {
      return `${code ?? ''} ${message ?? ''}`.trim()
    }
    const json = JSON.stringify(err)
    if (json !== '{}' && json.length > 0) {
      return json
    }
    return 'unknown error'
  }

  /** 调用系统应用打开已下载的本地文件；PDF/HTML 等走 ArkWeb 内置预览 */
  async openDownloadFile(id: string): Promise<OpenDownloadResult> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item) {
      return 'not_found'
    }
    if (item.status === 'deleted') {
      return 'missing'
    }
    if (item.status !== 'done') {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_not_ready')))
      return 'not_ready'
    }
    const path = this.resolveDownloadLocalPath(item)
    if (!(await this.isDownloadFilePresentAsync(item))) {
      BrowserLog.error(`openDownloadFile missing id=${id} path=${path} galleryUri=${item.galleryUri}`)
      await this.markDownloadAsDeleted(item)
      return 'missing'
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
      return 'failed'
    }
    try {
      const galleryUri = item.galleryUri.trim()
      if (BrowserUtils.isImageFile(item.fileName) && galleryUri.length > 0) {
        const opened = await ImageGalleryService.getInstance().openGalleryAsset(galleryUri, item.mimeType)
        if (!opened) {
          await this.markDownloadAsDeleted(item)
          return 'missing'
        }
        return 'opened'
      }
      if (BrowserUtils.canPreviewInBrowser(item.fileName)) {
        return this.openDownloadFileInBrowser(path, item.fileName)
      }
      const openUri = fileUri.getUriFromPath(path)
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: openUri,
        type: item.mimeType.includes('/') ? item.mimeType : BrowserUtils.inferMimeType(item.fileName),
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      }
      await ctx.startAbility(want)
      return 'opened'
    } catch (_err) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
      return 'failed'
    }
  }

  /** 将本地文件复制到沙箱（如需）后用 ArkWeb 预览 */
  private openDownloadFileInBrowser(localPath: string, fileName: string): OpenDownloadResult {
    const loadPath = DownloadPathService.getInstance().ensurePreviewLoadPath(localPath, fileName)
    const previewUrl = BrowserUtils.buildLocalFilePreviewUrl(loadPath)
    if (previewUrl.length === 0 || !DownloadPathService.getInstance().fileExists(loadPath)) {
      BrowserLog.error(`[FilePreview] missing path=${loadPath}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_open_failed')))
      return 'failed'
    }
    BrowserLog.info(`[FilePreview] open in browser name=${fileName} url=${previewUrl.slice(0, 120)}`)
    BrowserStore.openLocalFilePreview(previewUrl, fileName)
    return 'opened'
  }

  /** 本地文件缺失或已删除状态时重新下载（需有 sourceUrl） */
  async redownloadMissingFile(id: string): Promise<boolean> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item) {
      return false
    }
    if (item.status !== 'done' && item.status !== 'deleted') {
      return false
    }
    const path = this.resolveDownloadLocalPath(item)
    if (await this.isDownloadFilePresentAsync(item)) {
      return false
    }
    if (!BrowserUtils.isDirectDownloadUrl(item.sourceUrl)) {
      return false
    }
    return this.restartDirectDownload(id)
  }

  /** 解析下载任务对应的本地文件路径 */
  private resolveDownloadLocalPath(task: DownloadTask): string {
    if (task.localPath.trim().length > 0) {
      return task.localPath
    }
    return DownloadPathService.getInstance().buildSavePath(task.fileName)
  }

  private fileExists(path: string): boolean {
    return DownloadPathService.getInstance().fileExists(path)
  }

  /** 暂停正在进行的下载任务（保留残缺文件与进度，支持断点续传） */
  async pauseDownload(id: string, reason: 'user' | 'network' = 'user'): Promise<void> {
    this.downloadAbortFlags.set(id, 'pause')
    this.clearActiveTransfer(id)
    this.clearTimer(id)
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item || item.status !== 'running') {
      this.downloadAbortFlags.delete(id)
      return
    }
    this.syncProgressFromPartialFile(item)
    item.status = 'paused'
    item.errorMessage = ''
    await DownloadRepository.getInstance().upsert(item)
    await AppStateSync.refreshDownloads()
    this.syncPausedNotification(item)
    if (reason === 'network') {
      this.networkPausedTaskIds.add(id)
    }
    if (this.runningCount > 0) {
      this.runningCount--
    }
    this.downloadAbortFlags.delete(id)
    void this.tryPromoteQueuedTask()
  }

  /** 应用重启后，将未完成的 running 任务统一标记为 paused，并根据残缺文件校正进度 */
  async recoverInterruptedDownloadsOnStartup(): Promise<void> {
    const items = await DownloadRepository.getInstance().findAll()
    let changed = 0
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.status !== 'running') {
        continue
      }
      item.status = 'paused'
      item.errorMessage = ''
      item.localPath = DownloadPathService.getInstance().resolveResumeLocalPath(item)
      this.syncProgressFromPartialFile(item)
      await DownloadRepository.getInstance().upsert(item)
      changed++
    }
    if (changed > 0) {
      await AppStateSync.refreshDownloads()
      BrowserLog.info(`[Download] recoverInterruptedDownloadsOnStartup paused=${changed}`)
    }
    this.runningCount = 0
    void this.tryPromoteQueuedTask()
  }

  /** 断网或批量场景：暂停全部 running 任务 */
  async pauseAllRunningDownloads(reason: 'network' | 'manual'): Promise<void> {
    const items = await DownloadRepository.getInstance().findAll()
    let paused = 0
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.status !== 'running') {
        continue
      }
      const pauseReason: 'user' | 'network' = reason === 'network' ? 'network' : 'user'
      await this.pauseDownload(item.id, pauseReason)
      paused++
    }
    if (paused > 0 && reason === 'network' && !this.networkPauseToastShown) {
      this.networkPauseToastShown = true
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_paused_network')))
    }
  }

  /** 网络恢复后允许再次提示断网暂停 */
  resetNetworkPauseFlag(): void {
    this.networkPauseToastShown = false
  }

  /** 断网暂停的任务在网络恢复后自动断点续传 */
  async resumeNetworkPausedDownloads(): Promise<void> {
    if (!DownloadNetworkHelper.isNetworkAvailable()) {
      return
    }
    const ids: string[] = []
    this.networkPausedTaskIds.forEach((taskId: string) => {
      ids.push(taskId)
    })
    this.networkPausedTaskIds.clear()
    if (ids.length === 0) {
      return
    }
    BrowserLog.info(`[Download] resumeNetworkPausedDownloads count=${ids.length}`)
    let resumed = 0
    for (let i = 0; i < ids.length; i++) {
      const item = await DownloadRepository.getInstance().findById(ids[i])
      if (!item || item.status !== 'paused') {
        continue
      }
      const ok = await this.resumeDownload(ids[i])
      if (ok) {
        resumed++
      }
    }
    if (resumed > 0) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_resumed_network')))
    }
  }

  /** 恢复已暂停的下载任务（断点续传） */
  async resumeDownload(id: string): Promise<boolean> {
    BrowserLog.info(`[Download] resumeDownload requested id=${id}`)
    if (!DownloadNetworkHelper.isNetworkAvailable()) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_resume_need_network')))
      return false
    }
    this.networkPausedTaskIds.delete(id)
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item) {
      BrowserLog.warn(`[Download] resumeDownload skipped id=${id} reason=not_found`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_resume_failed')))
      return false
    }
    if (item.status !== 'paused') {
      BrowserLog.warn(`[Download] resumeDownload skipped id=${id} status=${item.status}`)
      if (item.status === 'running' || item.status === 'queued') {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_already_running')))
      } else {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_resume_failed')))
      }
      return false
    }
    await this.prepareDownloadNotificationAccess()
    const granted = await DownloadPermissionHelper.ensureBeforeDownload(item.fileName)
    if (!granted) {
      return false
    }
    if (BrowserUtils.isDirectDownloadUrl(item.sourceUrl)) {
      item.localPath = DownloadPathService.getInstance().resolveResumeLocalPath(item)
    } else if (item.sourceUrl.trim().length > 0) {
      item.localPath = DownloadPathService.getInstance().resolveResumeLocalPath(item)
    }
    this.syncProgressFromPartialFile(item)
    const spaceOk = await this.checkSpaceBeforeResume(item)
    if (!spaceOk) {
      return false
    }
    await DownloadRepository.getInstance().upsert(item)
    const started = await this.activateOrQueueTask(item, true, true)
    if (!started) {
      await DownloadRepository.getInstance().upsert(item)
      return true
    }
    this.syncRunningNotification(item)
    if (BrowserUtils.isDirectDownloadUrl(item.sourceUrl) || item.sourceUrl.trim().length > 0) {
      await DownloadRepository.getInstance().upsert(item)
      void this.downloadFromUrl(id, item.sourceUrl, item.localPath, false)
      this.kickstartDownloadNotification(id)
      return true
    }
    this.simulateDownload(id)
    return true
  }

  /** 删除下载任务；deleteLocal 为 true 时同步删除文管/图库文件 */
  async removeDownload(id: string, deleteLocal: boolean = true): Promise<void> {
    this.clearDownloadNotification(id)
    this.clearTimer(id)
    this.clearActiveTransfer(id)
    let wasRunning = false
    if (deleteLocal) {
      const item = await DownloadRepository.getInstance().findById(id)
      if (item) {
        wasRunning = item.status === 'running'
        await this.deleteDownloadFile(item)
      }
    }
    await DownloadRepository.getInstance().deleteById(id)
    await AppStateSync.refreshDownloads()
    if (wasRunning && this.runningCount > 0) {
      this.runningCount--
    }
    void this.tryPromoteQueuedTask()
  }

  /** 同步已完成任务的文件/图库存在性，缺失则标记为已删除 */
  async syncDownloadFileStates(): Promise<void> {
    const items = await DownloadRepository.getInstance().findAll()
    BrowserLog.info(`[GalleryCheck] syncDownloadFileStates total=${items.length}`)
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.status !== 'done') {
        continue
      }
      if (!(await this.isDownloadFilePresentAsync(item))) {
        await this.markDownloadAsDeleted(item)
      }
    }
  }

  private async deleteDownloadFile(item: DownloadTask): Promise<void> {
    if (BrowserUtils.isImageFile(item.fileName) && item.galleryUri.trim().length > 0) {
      await ImageGalleryService.getInstance().deleteGalleryAsset(item.galleryUri)
    }
    const pathService = DownloadPathService.getInstance()
    const resolved = this.resolveDownloadLocalPath(item)
    if (resolved) {
      pathService.deleteFileAtPath(resolved)
    }
    const raw = item.localPath.trim()
    if (raw.length > 0 && raw !== resolved) {
      pathService.deleteFileAtPath(raw)
    }
  }

  private async markDownloadAsDeleted(item: DownloadTask): Promise<void> {
    if (item.status === 'deleted') {
      return
    }
    item.status = 'deleted'
    item.errorMessage = BrowserStrings.txt($r('app.string.download_status_deleted'))
    await DownloadRepository.getInstance().upsert(item)
    await AppStateSync.refreshDownloads()
    BrowserLog.info(`[GalleryCheck] markDeleted id=${item.id} file=${item.fileName}`)
  }

  /** 下载任务对应文件是否仍存在（图片查媒体库索引，其他查本地路径） */
  private async isDownloadFilePresentAsync(item: DownloadTask): Promise<boolean> {
    if (BrowserUtils.isImageFile(item.fileName)) {
      const galleryUri = item.galleryUri.trim()
      if (galleryUri.length > 0) {
        return ImageGalleryService.getInstance().queryGalleryAssetExists(galleryUri)
      }
      // 旧任务无 galleryUri 时回退查本地路径
    }
    const path = this.resolveDownloadLocalPath(item)
    return !!path && this.fileExists(path)
  }

  /** 重命名下载任务文件 */
  async renameDownload(id: string, fileName: string): Promise<void> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (item) {
      item.fileName = fileName.trim()
      await DownloadRepository.getInstance().upsert(item)
      await AppStateSync.refreshDownloads()
    }
  }

  /** 重新下载失败的任务 */
  async retryDownload(id: string): Promise<boolean> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item || item.status !== 'failed') {
      return false
    }
    await this.prepareDownloadNotificationAccess()
    const granted = await DownloadPermissionHelper.ensureBeforeDownload(item.fileName)
    if (!granted) {
      return false
    }
    if (BrowserUtils.isDirectDownloadUrl(item.sourceUrl)) {
      return this.restartDirectDownload(id)
    }
    const started = await this.activateOrQueueTask(item, true)
    if (!started) {
      return true
    }
    this.syncRunningNotification(item)
    this.simulateDownload(id)
    return true
  }

  /** 重置任务并通过 HTTP / data URL 重新下载 */
  private async restartDirectDownload(id: string): Promise<boolean> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item || !BrowserUtils.isDirectDownloadUrl(item.sourceUrl)) {
      return false
    }
    const spaceOk = await this.ensureDownloadSpace({
      fileSizeBytes: item.fileSize,
      sourceUrl: item.sourceUrl,
      showToast: true
    })
    if (!spaceOk) {
      return false
    }
    item.galleryUri = ''
    const oldPath = item.localPath.trim()
    if (item.localPath.trim().length === 0) {
      item.localPath = WebDownloadService.getInstance().buildSavePath(item.fileName)
    }
    this.discardStaleDownloadPath(oldPath, item.localPath)
    this.prepareDownloadTargetPath(item)
    const started = await this.activateOrQueueTask(item, true)
    if (!started) {
      await DownloadRepository.getInstance().upsert(item)
      return true
    }
    this.syncRunningNotification(item)
    await DownloadRepository.getInstance().upsert(item)
    void this.downloadFromUrl(id, item.sourceUrl, item.localPath, true)
    this.kickstartDownloadNotification(id)
    return true
  }

  /** 继续/开始下载前：申请通知权限并注册槽位（重启后 taskStates 为空，需重新 publish） */
  private async prepareDownloadNotificationAccess(): Promise<void> {
    const ready = await DownloadNotificationService.getInstance().ensureNotificationAccess(true)
    DownloadNotificationService.getInstance().markNotificationEnabledForSession(ready)
    BrowserLog.info(`[DownloadNotif] prepareDownloadNotificationAccess ready=${ready}`)
  }

  /** 通过 HTTP 或 data URL 下载并写入本地文件；freshStart=false 时尝试 Range 断点续传 */
  private async downloadFromUrl(id: string, sourceUrl: string, destPath: string,
    freshStart: boolean = true): Promise<void> {
    const item = await DownloadRepository.getInstance().findById(id)
    if (!item) {
      return
    }
    const previousPath = item.localPath.trim()
    if (item.localPath.trim().length === 0) {
      item.localPath = destPath.trim().length > 0 ? destPath : WebDownloadService.getInstance().buildSavePath(item.fileName)
    }
    let canonicalPath = freshStart ? this.prepareDownloadTargetPath(item) : this.ensureDownloadTargetPath(item)
    if (item.localPath !== previousPath) {
      await DownloadRepository.getInstance().upsert(item)
    }
    let targetPath = canonicalPath
    let startByte = freshStart ? 0 : this.getPartialFileSize(canonicalPath)
    if (!freshStart && startByte <= 0) {
      const altPath = DownloadPathService.getInstance().resolveResumeLocalPath(item)
      if (altPath !== canonicalPath) {
        item.localPath = altPath
        canonicalPath = altPath
        startByte = this.getPartialFileSize(canonicalPath)
        await DownloadRepository.getInstance().upsert(item)
      }
    }
    if (startByte > 0) {
      this.syncProgressFromPartialFile(item)
      await DownloadRepository.getInstance().upsert(item)
      BrowserLog.info(`[Download] resume id=${id} startByte=${startByte} progress=${item.progress}`)
    }
    try {
      const kickoffProgress = Math.min(99, Math.max(0, item.progress))
      await this.updateWebDownloadProgress(id, kickoffProgress)
      if (sourceUrl.trim().startsWith('data:')) {
        targetPath = this.writeWithFallback(canonicalPath, (path) => {
          this.saveDataUrlToFile(sourceUrl, path)
        })
      } else {
        targetPath = await this.saveHttpUrlToFile(sourceUrl, canonicalPath, id, startByte, item.fileSize)
      }
      BrowserLog.info(`downloadFromUrl ok id=${id} path=${targetPath}`)
      this.discardStaleDownloadPath(canonicalPath, targetPath)
      const latest = await DownloadRepository.getInstance().findById(id)
      if (latest && latest.localPath !== targetPath) {
        latest.localPath = targetPath
        await DownloadRepository.getInstance().upsert(latest)
      }
      await this.completeWebDownload(id)
    } catch (err) {
      BrowserLog.error(`downloadFromUrl failed id=${id} url=${sourceUrl} path=${targetPath}: ${DownloadManager.formatErrorText(err as object)}`)
      const latest = await DownloadRepository.getInstance().findById(id)
      if (!latest || latest.status === 'paused') {
        return
      }
      if (!DownloadNetworkHelper.isNetworkAvailable()) {
        await this.pauseDownload(id, 'network')
        return
      }
      await this.failWebDownloadWithReason(id, this.extractDownloadErrorMessage(err as object),
        [targetPath, canonicalPath])
    }
  }

  private registerSystemDownloadTask(taskId: string, task: request.DownloadTask): void {
    if (taskId.length === 0 || taskId === 'silent') {
      return
    }
    this.systemDownloadTasks.set(taskId, task)
  }

  private clearActiveTransfer(taskId: string): void {
    const sysTask = this.systemDownloadTasks.get(taskId)
    if (sysTask !== undefined) {
      void sysTask.remove().catch((_err: Error) => {
        // 忽略 remove 失败
      })
      this.systemDownloadTasks.delete(taskId)
    }
    const httpReq = this.httpDownloadRequests.get(taskId)
    if (httpReq !== undefined) {
      try {
        httpReq.destroy()
      } catch (_err) {
        // 忽略 destroy 失败
      }
      this.httpDownloadRequests.delete(taskId)
    }
    WebDownloadService.getInstance().cancelActiveDownload(taskId)
  }

  private buildSystemDownloadHooks(taskId: string): SystemDownloadHooks {
    return {
      onProgress: (pct: number): void => {
        if (taskId.length > 0 && taskId !== 'silent') {
          void this.updateWebDownloadProgress(taskId, pct)
        }
      },
      onTaskReady: (task: request.DownloadTask): void => {
        this.registerSystemDownloadTask(taskId, task)
      }
    }
  }

  private isSslRelatedError(message: string): boolean {
    const lower = message.toLowerCase()
    return message.includes('2300060') || lower.includes('ssl') || lower.includes('certificate') ||
      lower.includes('peer certificate')
  }

  /**
   * 证书异常时询问用户是否仍继续下载。
   * 默认拒绝；仅用户确认（或该主机此前已在浏览 SSL 弹窗中信任）后才允许 skip。
   */
  private async confirmSkipSslForUrl(url: string): Promise<boolean> {
    const host = BrowserUtils.tabHostname(url)
    if (SslHandler.shouldProceed(host)) {
      return true
    }
    const uiCtx = getBrowserUIContext()
    if (!uiCtx) {
      BrowserLog.warn(`[Download] ssl confirm skipped: no UIContext host=${host}`)
      return false
    }
    try {
      const result = await uiCtx.getPromptAction().showDialog({
        title: BrowserStrings.txt($r('app.string.ssl_error_title')),
        message: BrowserStrings.txt($r('app.string.download_ssl_confirm_message')),
        buttons: [
          { text: BrowserStrings.txt($r('app.string.cancel')), color: '#999999' },
          { text: BrowserStrings.txt($r('app.string.download_ssl_continue')), color: '#007DFF' }
        ]
      })
      if (result.index === 1) {
        SslHandler.allowProceed(host)
        BrowserLog.info(`[Download] user allowed ssl skip host=${host}`)
        return true
      }
    } catch (err) {
      BrowserLog.warn(`[Download] ssl confirm dialog failed: ${JSON.stringify(err)}`)
    }
    return false
  }

  private async saveHttpUrlToFile(url: string, destPath: string, taskId: string,
    startByte: number = 0, totalFileSize: number = 0): Promise<string> {
    const hooks = this.buildSystemDownloadHooks(taskId)
    const onProgress = hooks.onProgress
    const onTaskReady = hooks.onTaskReady
    const headers = SystemDownloadService.buildHeaders(url)
    const pathService = DownloadPathService.getInstance()

    let lastError = ''
    let fallbackOffset = 0

    this.ensureParentDir(destPath)

    const tryStream = async (path: string, offset: number, skipSsl: boolean): Promise<void> => {
      await this.saveHttpUrlToFileStream(url, path, taskId, headers, offset, totalFileSize, skipSsl)
    }

    /** 系统校验证书失败后，经用户确认再以 skip 重试一次 */
    const retryStreamAfterSslConfirm = async (path: string, offset: number): Promise<boolean> => {
      if (!this.isSslRelatedError(lastError)) {
        return false
      }
      const allowSkip = await this.confirmSkipSslForUrl(url)
      if (!allowSkip) {
        return false
      }
      try {
        await tryStream(path, offset, true)
        BrowserLog.info(`saveHttpUrlToFile stream ok after ssl confirm path=${path}`)
        return true
      } catch (err) {
        lastError = DownloadManager.formatErrorText(err as object)
        if (this.downloadAbortFlags.get(taskId) !== 'pause') {
          this.removePartialFile(path)
        }
        BrowserLog.warn(`saveHttpUrlToFile stream ssl-confirm retry failed path=${path}: ${lastError}`)
        return false
      }
    }

    if (startByte > 0) {
      try {
        await tryStream(destPath, startByte, false)
        BrowserLog.info(`saveHttpUrlToFile range ok path=${destPath} startByte=${startByte}`)
        return destPath
      } catch (err) {
        lastError = DownloadManager.formatErrorText(err as object)
        BrowserLog.warn(`saveHttpUrlToFile range resume failed path=${destPath}: ${lastError}`)
        if (await retryStreamAfterSslConfirm(destPath, startByte)) {
          return destPath
        }
        fallbackOffset = this.getPartialFileSize(destPath)
        BrowserLog.info(`saveHttpUrlToFile range exhausted, fallback offset=${fallbackOffset} path=${destPath}`)
      }
    } else {
      this.removePartialFile(destPath)
    }

    if (fallbackOffset <= 0) {
      try {
        await SystemDownloadService.downloadToFile(url, destPath, onProgress, onTaskReady)
        return destPath
      } catch (err) {
        lastError = DownloadManager.formatErrorText(err as object)
        if (this.downloadAbortFlags.get(taskId) !== 'pause') {
          this.removePartialFile(destPath)
        }
        BrowserLog.warn(`saveHttpUrlToFile system failed path=${destPath}: ${lastError}`)
      }
    }

    try {
      await tryStream(destPath, fallbackOffset, false)
      return destPath
    } catch (err) {
      lastError = DownloadManager.formatErrorText(err as object)
      if (this.downloadAbortFlags.get(taskId) !== 'pause') {
        this.removePartialFile(destPath)
      }
      BrowserLog.warn(`saveHttpUrlToFile stream failed path=${destPath}: ${lastError}`)
    }

    if (await retryStreamAfterSslConfirm(destPath, fallbackOffset)) {
      return destPath
    }

    if (pathService.usesMobileDownloadStrategy()) {
      const fileName = destPath.substring(destPath.lastIndexOf('/') + 1)
      const sandboxPath = pathService.buildSandboxSavePath(fileName)
      if (sandboxPath !== destPath) {
        const sandboxStart = startByte > 0 ? this.getPartialFileSize(sandboxPath) : 0
        if (sandboxStart === 0 && startByte === 0) {
          this.removePartialFile(sandboxPath)
        }
        this.ensureParentDir(sandboxPath)
        if (sandboxStart > 0) {
          try {
            await tryStream(sandboxPath, sandboxStart, false)
            return sandboxPath
          } catch (err) {
            lastError = DownloadManager.formatErrorText(err as object)
            BrowserLog.warn(`saveHttpUrlToFile sandbox range failed path=${sandboxPath}: ${JSON.stringify(err)}`)
            if (await retryStreamAfterSslConfirm(sandboxPath, sandboxStart)) {
              return sandboxPath
            }
            this.removePartialFile(sandboxPath)
          }
        }
        try {
          await SystemDownloadService.downloadToFile(url, sandboxPath, onProgress, onTaskReady)
          return sandboxPath
        } catch (err) {
          if (this.downloadAbortFlags.get(taskId) !== 'pause') {
            this.removePartialFile(sandboxPath)
          }
          BrowserLog.warn(`saveHttpUrlToFile sandbox system failed path=${sandboxPath}: ${JSON.stringify(err)}`)
        }
        try {
          await tryStream(sandboxPath, 0, false)
          return sandboxPath
        } catch (err) {
          lastError = DownloadManager.formatErrorText(err as object)
          if (this.downloadAbortFlags.get(taskId) !== 'pause') {
            this.removePartialFile(sandboxPath)
          }
          BrowserLog.warn(`saveHttpUrlToFile sandbox stream failed path=${sandboxPath}: ${JSON.stringify(err)}`)
        }
        if (await retryStreamAfterSslConfirm(sandboxPath, 0)) {
          return sandboxPath
        }
      }
    }

    throw new Error(lastError.length > 0 ? lastError : `all download methods failed url=${url.slice(0, 80)}`)
  }

  private removePartialFile(path: string): void {
    try {
      if (DownloadPathService.getInstance().fileExists(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_err) {
      // 忽略删除失败
    }
  }

  /** 删除未完成任务的本地残缺文件 */
  private cleanupIncompleteDownloadFile(item: DownloadTask): void {
    if (item.status === 'done') {
      return
    }
    const pathService = DownloadPathService.getInstance()
    const primary = item.localPath.trim()
    if (primary.length > 0) {
      pathService.deleteFileAtPath(primary)
    }
    const resolved = this.resolveDownloadLocalPath(item)
    if (resolved.length > 0 && resolved !== primary) {
      pathService.deleteFileAtPath(resolved)
    }
  }

  /** 新一轮下载前：固定唯一落盘路径并清理旧残缺文件 */
  private prepareDownloadTargetPath(item: DownloadTask): string {
    if (item.localPath.trim().length === 0) {
      item.localPath = WebDownloadService.getInstance().buildSavePath(item.fileName)
    }
    this.cleanupIncompleteDownloadFile(item)
    return item.localPath
  }

  /** 续传/暂停恢复：绑定已有残缺文件路径，不删除、不另起 (1)(2) 新文件 */
  private ensureDownloadTargetPath(item: DownloadTask): string {
    const path = DownloadPathService.getInstance().resolveResumeLocalPath(item)
    item.localPath = path
    return path
  }

  /** 读取本地残缺文件已下载字节数 */
  private getPartialFileSize(path: string): number {
    const trimmed = path.trim()
    if (trimmed.length === 0 || !this.fileExists(trimmed)) {
      return 0
    }
    try {
      const stat = fileIo.statSync(trimmed)
      return stat.size > 0 ? stat.size : 0
    } catch (_err) {
      return 0
    }
  }

  /** 根据已下载字节与总大小同步 progress */
  private syncProgressFromPartialFile(item: DownloadTask): void {
    const path = this.resolveDownloadLocalPath(item)
    const downloaded = this.getPartialFileSize(path)
    if (downloaded <= 0) {
      return
    }
    item.progress = this.computeProgressFromBytes(downloaded, item.fileSize)
  }

  private computeProgressFromBytes(downloaded: number, total: number): number {
    if (total > 0) {
      return Math.min(99, Math.max(1, Math.floor(downloaded / total * 100)))
    }
    return 10
  }

  /** 续传前校验剩余磁盘空间 */
  private async checkSpaceBeforeResume(item: DownloadTask): Promise<boolean> {
    const path = this.resolveDownloadLocalPath(item)
    const downloaded = this.getPartialFileSize(path)
    const totalBytes = item.fileSize > 0 ? item.fileSize :
      await DownloadSpaceGuard.resolveRequiredBytes('', 0, item.sourceUrl)
    if (totalBytes <= 0) {
      return true
    }
    const remaining = totalBytes - downloaded
    if (remaining <= 0) {
      return true
    }
    return this.ensureDownloadSpace({
      fileSizeBytes: remaining,
      sourceUrl: item.sourceUrl,
      showToast: true,
      failTaskId: item.id
    })
  }

  /**
   * 统一下载前剩余空间校验。
   * @returns true 表示可继续下载；false 表示空间不足并已提示
   */
  private async ensureDownloadSpace(options: DownloadSpaceGuardParams): Promise<boolean> {
    const required = await DownloadSpaceGuard.resolveRequiredBytes(
      options.sizeText ?? '',
      options.fileSizeBytes ?? 0,
      options.sourceUrl ?? ''
    )
    if (required <= 0) {
      return true
    }
    const check = await DownloadSpaceGuard.check(required)
    if (check.ok) {
      return true
    }
    BrowserLog.warn(`[Download] space blocked need=${required} free=${check.freeBytes}`)
    if (options.showToast !== false) {
      const needText = formatFileSizeText(required)
      const freeText = formatFileSizeText(check.freeBytes)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_space_insufficient'), needText, freeText))
    }
    if (options.failTaskId && options.failTaskId.length > 0) {
      await this.failWebDownloadWithReason(options.failTaskId,
        BrowserStrings.txt($r('app.string.download_error_storage')), [])
    }
    return false
  }

  /** 落盘路径切换时删除旧路径，避免文管残留多个残缺文件 */
  private discardStaleDownloadPath(previousPath: string, currentPath: string): void {
    const prev = previousPath.trim()
    const curr = currentPath.trim()
    if (prev.length > 0 && prev !== curr) {
      this.removePartialFile(prev)
    }
  }

  private sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms)
    })
  }

  /** 从 DB 拉取 running 数，覆盖易过期的内存缓存 */
  private async syncRunningCountFromDb(): Promise<void> {
    try {
      const items = await DownloadRepository.getInstance().findAll()
      let count = 0
      for (let i = 0; i < items.length; i++) {
        if (items[i].status === 'running') {
          count++
        }
      }
      this.runningCount = count
    } catch (err) {
      BrowserLog.warn(`[Download] syncRunningCountFromDb failed: ${JSON.stringify(err)}`)
    }
  }

  /**
   * 申请下载 slot：有空闲则置 running 并返回 true（调用方负责启动传输）；
   * 已满则置 queued 并返回 false。
   */
  private async activateOrQueueTask(item: DownloadTask, showQueuedToast: boolean = true,
    preserveProgress: boolean = false): Promise<boolean> {
    await this.syncRunningCountFromDb()
    if (this.runningCount >= DownloadManager.MAX_CONCURRENT_DOWNLOADS) {
      if (item.status !== 'queued') {
        item.status = 'queued'
        if (!preserveProgress) {
          item.progress = 0
        }
        item.errorMessage = ''
        await DownloadRepository.getInstance().upsert(item)
        await AppStateSync.refreshDownloads()
      }
      if (showQueuedToast) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.download_queued_toast'), item.fileName))
      }
      BrowserLog.info(`[Download] activateOrQueueTask queued id=${item.id} runningCount=${this.runningCount}`)
      return false
    }
    item.status = 'running'
    if (!preserveProgress) {
      item.progress = 0
    }
    item.errorMessage = ''
    await DownloadRepository.getInstance().upsert(item)
    await AppStateSync.refreshDownloads()
    this.runningCount++
    BrowserLog.info(`[Download] activateOrQueueTask running id=${item.id} runningCount=${this.runningCount}`)
    return true
  }

  /** 有空闲 slot 时，按创建时间依次将 queued 任务提升为 running */
  private async tryPromoteQueuedTask(): Promise<void> {
    while (true) {
      await this.syncRunningCountFromDb()
      if (this.runningCount >= DownloadManager.MAX_CONCURRENT_DOWNLOADS) {
        return
      }
      const promoted = await this.promoteOneQueuedTask()
      if (!promoted) {
        return
      }
    }
  }

  /** 提升最早的一条 queued 任务为 running */
  private async promoteOneQueuedTask(): Promise<boolean> {
    let candidate: DownloadTask | null = null
    try {
      const items = await DownloadRepository.getInstance().findAll()
      for (let i = 0; i < items.length; i++) {
        const item = items[i]
        if (item.status !== 'queued') {
          continue
        }
        if (candidate === null || item.createdAt < candidate.createdAt) {
          candidate = item
        }
      }
    } catch (err) {
      BrowserLog.warn(`[Download] promoteOneQueuedTask findAll failed: ${JSON.stringify(err)}`)
      return false
    }
    if (candidate === null) {
      return false
    }
    const task = candidate as DownloadTask
    const spaceOk = await this.ensureDownloadSpace({
      fileSizeBytes: task.fileSize,
      sourceUrl: task.sourceUrl,
      showToast: true
    })
    if (!spaceOk) {
      return false
    }
    const started = await this.activateOrQueueTask(task, false)
    if (!started) {
      return false
    }
    BrowserLog.info(`[Download] promote queued id=${task.id} file=${task.fileName}`)
    void this.startTaskByMode(task, task.fileName, task.sourceUrl)
    return true
  }

  /** 流式下载大文件，支持 HTTP Range 断点续传；skipSslValidation 仅在用户确认证书风险后使用 */
  private saveHttpUrlToFileStream(
    url: string,
    destPath: string,
    taskId: string,
    headers: Record<string, string>,
    startByte: number = 0,
    totalFileSize: number = 0,
    skipSslValidation: boolean = false
  ): Promise<void> {
    this.ensureParentDir(destPath)
    const httpRequest = http.createHttp()
    if (taskId.length > 0 && taskId !== 'silent') {
      this.httpDownloadRequests.set(taskId, httpRequest)
    }
    let fileFd: number = -1
    let streamFailed = false
    let streamError = ''
    let responseCode = 0
    let settled = false
    const requestHeaders: Record<string, string> = {}
    const headerKeys = Object.keys(headers)
    for (let i = 0; i < headerKeys.length; i++) {
      requestHeaders[headerKeys[i]] = headers[headerKeys[i]]
    }
    if (startByte > 0) {
      requestHeaders['Range'] = `bytes=${startByte}-`
    }

    const closeFile = (): void => {
      if (fileFd >= 0) {
        try {
          fileIo.closeSync(fileFd)
        } catch (_err) {
          // 忽略关闭失败
        }
        fileFd = -1
      }
    }

    const destroyRequest = (): void => {
      try {
        httpRequest.off('dataReceive')
        httpRequest.off('dataEnd')
        httpRequest.off('dataReceiveProgress')
      } catch (_err) {
        // 忽略 off 失败
      }
      httpRequest.destroy()
    }

    const shouldKeepPartial = (): boolean => {
      return this.downloadAbortFlags.get(taskId) === 'pause'
    }

    const isFileComplete = (): boolean => {
      if (totalFileSize <= 0) {
        return false
      }
      return this.getPartialFileSize(destPath) >= totalFileSize
    }

    const settle = (resolve: () => void, reject: (err: Error) => void, err?: Error): void => {
      if (settled) {
        return
      }
      settled = true
      if (taskId.length > 0 && taskId !== 'silent') {
        this.httpDownloadRequests.delete(taskId)
      }
      closeFile()
      destroyRequest()
      const okCode = responseCode === 200 || responseCode === 206
      const completeBySize = isFileComplete()
      const failed = err !== undefined || (streamFailed && !completeBySize) || (!okCode && !completeBySize)
      if (failed && !shouldKeepPartial()) {
        this.removePartialFile(destPath)
      }
      if (err) {
        reject(err)
        return
      }
      if (streamFailed && !completeBySize) {
        reject(new Error(streamError.length > 0 ? streamError : 'stream download failed'))
        return
      }
      if (!okCode && !completeBySize) {
        reject(new Error(`http status ${responseCode}`))
        return
      }
      if (!DownloadPathService.getInstance().fileExists(destPath)) {
        reject(new Error('download file missing after stream'))
        return
      }
      if (completeBySize && !okCode) {
        BrowserLog.info(`saveHttpUrlToFileStream complete by size path=${destPath} code=${responseCode}`)
      }
      resolve()
    }

    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      if (fileFd < 0 || streamFailed) {
        return
      }
      try {
        fileIo.writeSync(fileFd, data)
      } catch (err) {
        streamFailed = true
        streamError = JSON.stringify(err)
      }
    })

    if (taskId.length > 0 && taskId !== 'silent') {
      httpRequest.on('dataReceiveProgress', (info: http.DataReceiveProgressInfo) => {
        let total = totalFileSize
        if (total <= 0 && info.totalSize > 0) {
          total = startByte > 0 ? startByte + info.totalSize : info.totalSize
        }
        const received = startByte > 0 ? startByte + info.receiveSize : info.receiveSize
        if (total > 0) {
          const pct = Math.min(99, Math.floor(received / total * 100))
          void this.updateWebDownloadProgress(taskId, pct)
        } else if (info.receiveSize > 0 && startByte > 0) {
          const pct = Math.min(99, Math.floor((startByte + info.receiveSize) / (startByte + info.totalSize) * 100))
          void this.updateWebDownloadProgress(taskId, pct)
        }
      })
    }

    const openMode = startByte > 0
      ? fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND
      : fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
    const opened = fileIo.openSync(destPath, openMode)
    fileFd = opened.fd

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      connectTimeout: 60000,
      readTimeout: 600000,
      header: requestHeaders
    }
    if (skipSslValidation) {
      options.remoteValidation = 'skip'
    }

    return new Promise<void>((resolve, reject) => {
      let responseReady = false
      let dataEndReceived = false

      const tryFinish = (): void => {
        if (!responseReady || !dataEndReceived) {
          return
        }
        settle(resolve, reject)
      }

      httpRequest.on('dataEnd', () => {
        dataEndReceived = true
        tryFinish()
      })

      httpRequest.requestInStream(url, options).then((code: number) => {
        responseCode = code
        if (code === 416 && startByte > 0) {
          streamFailed = true
          streamError = 'range not satisfiable'
        } else if (code === 200 && startByte > 0) {
          streamFailed = true
          streamError = 'range ignored by server'
        } else if (code !== 200 && code !== 206) {
          streamFailed = true
          streamError = `http status ${code}`
        }
        responseReady = true
        tryFinish()
      }).catch((err: Error) => {
        responseReady = true
        dataEndReceived = true
        settle(resolve, reject, err)
      })
    })
  }

  /** 沙箱残留文件发布到文管可见位置（正常流程应已直写公共目录） */
  private async publishDownloadPathIfNeeded(localPath: string, fileName: string): Promise<DownloadPublishResult> {
    if (!DownloadPublishService.isSandboxPath(localPath)) {
      const publicResult: DownloadPublishResult = { path: localPath, visibility: 'public' }
      return publicResult
    }
    const publishedPath = MobileDownloadPublishService.publishAfterDownload(localPath, fileName)
      ?? DownloadPublishService.publishToPublicIfNeeded(localPath, fileName)
    if (publishedPath && publishedPath.length > 0) {
      const movedResult: DownloadPublishResult = { path: publishedPath, visibility: 'public' }
      return movedResult
    }
    BrowserLog.error(`[DownloadPublish] failed to publish sandbox file path=${localPath}`)
    const sandboxResult: DownloadPublishResult = { path: localPath, visibility: 'sandbox' }
    return sandboxResult
  }

  private writeWithFallback(destPath: string, writeFn: (path: string) => void): string {
    const fileName = destPath.substring(destPath.lastIndexOf('/') + 1)
    const candidates = DownloadPathService.getInstance().resolveDownloadTargetPaths(fileName)
    let lastErr: object | string = 'write failed'
    for (let i = 0; i < candidates.length; i++) {
      const path = candidates[i]
      try {
        this.ensureParentDir(path)
        writeFn(path)
        if (i > 0) {
          BrowserLog.info(`writeWithFallback ok fallback path=${path}`)
        }
        return path
      } catch (err) {
        lastErr = err as object
        BrowserLog.warn(`writeWithFallback failed path=${path}: ${JSON.stringify(err)}`)
      }
    }
    throw new Error(JSON.stringify(lastErr))
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
      fileIo.mkdirSync(dir, true)
    }
  }

  private saveDataUrlToFile(dataUrl: string, destPath: string): void {
    const commaIdx = dataUrl.indexOf(',')
    if (commaIdx < 0) {
      throw new Error('invalid data url')
    }
    const header = dataUrl.substring(0, commaIdx)
    const payload = dataUrl.substring(commaIdx + 1)
    let buffer: ArrayBuffer
    if (header.includes(';base64')) {
      const helper = new util.Base64Helper()
      const bytes = helper.decodeSync(payload)
      buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    } else {
      const text = decodeURIComponent(payload)
      const bytes = new Uint8Array(text.length)
      for (let i = 0; i < text.length; i++) {
        bytes[i] = text.charCodeAt(i)
      }
      buffer = bytes.buffer.slice(0, bytes.byteLength)
    }
    this.writeArrayBufferToFile(destPath, buffer)
  }

  private writeArrayBufferToFile(path: string, data: ArrayBuffer): void {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, data)
    } finally {
      fileIo.closeSync(file)
    }
  }

  /** 模拟下载进度更新直至完成 */
  private simulateDownload(id: string): void {
    this.clearTimer(id)
    const timer = setInterval(async () => {
      const item = await DownloadRepository.getInstance().findById(id)
      if (!item || item.status !== 'running') {
        this.clearTimer(id)
        return
      }
      const nextProgress = Math.min(100, item.progress + 12)
      if (nextProgress >= 100) {
        item.progress = 100
        item.status = 'done'
        await DownloadRepository.getInstance().upsert(item)
        await AppStateSync.refreshDownloads()
        this.finishDownloadNotification(id, item.fileName)
        this.clearTimer(id)
        if (this.runningCount > 0) {
          this.runningCount--
        }
        void this.tryPromoteQueuedTask()
        return
      }
      if (item.status !== 'running') {
        this.clearTimer(id)
        return
      }
      item.progress = nextProgress
      await DownloadRepository.getInstance().upsert(item)
      AppStateSync.patchDownloadItem(item)
      this.syncRunningNotification(item)
    }, 400)
    this.timers.set(id, timer)
  }

  /** 清除指定任务的进度模拟定时器 */
  private clearTimer(id: string): void {
    const timer = this.timers.get(id)
    if (timer !== undefined) {
      clearInterval(timer)
      this.timers.delete(id)
    }
  }

  /** Ability 销毁时停止全部进行中的传输与进度定时器 */
  shutdown(): void {
    const timerIds: string[] = []
    this.timers.forEach((_timer: number, id: string) => {
      timerIds.push(id)
    })
    for (let i = 0; i < timerIds.length; i++) {
      this.clearTimer(timerIds[i])
    }
    const transferIds: string[] = []
    this.systemDownloadTasks.forEach((_task: request.DownloadTask, id: string) => {
      transferIds.push(id)
    })
    this.httpDownloadRequests.forEach((_req: http.HttpRequest, id: string) => {
      if (transferIds.indexOf(id) < 0) {
        transferIds.push(id)
      }
    })
    for (let i = 0; i < transferIds.length; i++) {
      this.clearActiveTransfer(transferIds[i])
    }
    BrowserLog.info(`[Download] shutdown timers=${timerIds.length} transfers=${transferIds.length}`)
  }

  private syncRunningNotification(task: DownloadTask): void {
    void DownloadNotificationService.getInstance()
      .notifyRunningProgress(task.id, task.fileName, task.progress)
  }

  /** 下载启动后立即刷新一次通知（不再强制抬升至 10%） */
  private kickstartDownloadNotification(id: string): void {
    void DownloadRepository.getInstance().findById(id).then((item) => {
      if (item && item.status === 'running') {
        void this.updateWebDownloadProgress(id, Math.min(99, Math.max(0, item.progress)))
      }
    })
  }

  private syncPausedNotification(task: DownloadTask): void {
    void DownloadNotificationService.getInstance()
      .notifyPausedProgress(task.id, task.fileName, task.progress)
  }

  private finishDownloadNotification(taskId: string, fileName: string): void {
    const name = fileName.trim()
    if (name.length > 0) {
      BrowserStore.showToast(BrowserStrings.downloadCompleteToast(name))
    }
    void DownloadNotificationService.getInstance().notifyDownloadComplete(taskId, fileName)
  }

  private clearDownloadNotification(taskId: string): void {
    void DownloadNotificationService.getInstance().cancelProgress(taskId)
  }
}

/** 短信分享 payload */
interface ShareSmsPayload {
  title: string
  url: string
  body: string
}

/** 拉起系统短信编辑页的 Want 构造 */
interface MmsLaunchAttempt {
  label: string
  build: () => Want
}

/** MMS contactObjects 元素（与系统短信 Contact 字段一致） */
interface MmsContactInfo {
  contactsName: string
  telephone: number
}

/** 分享能力封装 */
export class ShareService {
  private static instance: ShareService | null = null

  /** 获取 ShareService 单例 */
  static getInstance(): ShareService {
    if (ShareService.instance === null) {
      ShareService.instance = new ShareService()
    }
    return ShareService.instance
  }

  /** 拼接分享正文 */
  private shareBody(title: string, url: string): string {
    const safeTitle = title.trim()
    const safeUrl = url.trim()
    if (safeTitle.length > 0 && safeUrl.length > 0) {
      return `${safeTitle}\n${safeUrl}`
    }
    return safeTitle.length > 0 ? safeTitle : safeUrl
  }

  /** 构造 sendData Want（分享选择器） */
  private buildSendDataWant(title: string, url: string, mimeType: string = 'text/plain'): Want {
    const body = this.shareBody(title, url)
    const safeTitle = title.trim()
    const safeUrl = url.trim()
    return {
      action: 'ohos.want.action.sendData',
      type: mimeType,
      parameters: {
        'ability.params.stream': body,
        'ability.subject': safeTitle.length > 0 ? safeTitle : safeUrl,
        [wantConstant.Params.CONTENT_TITLE_KEY]: safeTitle,
        [wantConstant.Params.SHARE_URL_KEY]: safeUrl,
        [wantConstant.Params.SHARE_ABSTRACT_KEY]: body
      }
    }
  }

  /** 拉起分享选择器 */
  private async shareViaSendData(title: string, url: string, mimeType: string = 'text/plain'): Promise<void> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
      return
    }
    try {
      await ctx.startAbility(this.buildSendDataWant(title, url, mimeType))
    } catch (_err) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
    }
  }

  /** 尝试通过 sendData 直达指定应用 */
  private async tryLaunchSendData(ctx: common.UIAbilityContext, title: string, url: string,
    bundleName: string): Promise<boolean> {
    const body = this.shareBody(title, url)
    const safeTitle = title.trim()
    const safeUrl = url.trim()
    const wants: Want[] = [
      {
        action: 'ohos.want.action.sendData',
        bundleName,
        type: 'text/plain',
        parameters: {
          'ability.params.stream': body,
          'ability.subject': safeTitle.length > 0 ? safeTitle : safeUrl
        }
      },
      {
        action: 'ohos.want.action.sendData',
        bundleName,
        parameters: {
          [wantConstant.Params.CONTENT_TITLE_KEY]: safeTitle,
          [wantConstant.Params.SHARE_URL_KEY]: safeUrl,
          [wantConstant.Params.SHARE_ABSTRACT_KEY]: body
        }
      }
    ]
    for (let i = 0; i < wants.length; i++) {
      try {
        await ctx.startAbility(wants[i])
        return true
      } catch (_err) {
        // 尝试下一种 Want 参数组合
      }
    }
    return false
  }

  /** 优先直达目标应用，失败则回退分享选择器 */
  private async shareLinkToBundles(title: string, url: string, bundleCandidates: string[]): Promise<void> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
      return
    }
    for (let i = 0; i < bundleCandidates.length; i++) {
      const launched = await this.tryLaunchSendData(ctx, title, url, bundleCandidates[i])
      if (launched) {
        BrowserLog.info(`[Share] launched bundle=${bundleCandidates[i]}`)
        return
      }
    }
    await this.shareViaSendData(title, url)
  }

  /** 尝试通过 sendData 分享本地文件 */
  private async shareFileViaSendData(title: string, filePath: string): Promise<boolean> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return false
    }
    try {
      if (!fileIo.accessSync(filePath)) {
        return false
      }
      const uri = fileUri.getUriFromPath(filePath)
      return await ShareService.tryLaunchSendDataWithUri(ctx, uri, BrowserUtils.inferMimeType(filePath), title)
    } catch (_err) {
      return false
    }
  }

  /** 尝试通过 sendData 分享 URI */
  private async shareUriViaSendData(title: string, uri: string, mimeType: string): Promise<boolean> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return false
    }
    return ShareService.tryLaunchSendDataWithUri(ctx, uri, mimeType, title)
  }

  /** 打开分享面板并填充分享内容 */
  openShareSheet(opts: ShareSheetParams): void {
    const previewVisible = AppStorage.get<boolean>(AppStorageKeys.IMAGE_PREVIEW_VISIBLE) ?? false
    BrowserLog.info(`[ShareSheet] open title=${opts.title ?? ''} previewImage=${opts.previewImage ?? false} ` +
      `imagePreviewVisible=${previewVisible} url=${(opts.url ?? '').slice(0, 100)}`)
    AppStorage.set(AppStorageKeys.SHARE_VISIBLE, true)
    AppStorage.set(AppStorageKeys.SHARE_TITLE, opts.title || 'Browser')
    AppStorage.set(AppStorageKeys.SHARE_URL, opts.url || '')
    AppStorage.set(AppStorageKeys.SHARE_SIZE, opts.size || '')
    AppStorage.set(AppStorageKeys.SHARE_IMAGE, opts.previewImage)
    void ShareAppAvailability.probe()
    void this.copySharePayload(opts.title ?? '', opts.url ?? '')
  }

  /** 打开分享面板时复制分享正文到剪贴板 */
  async copySharePayload(title: string, url: string): Promise<void> {
    const body = this.shareBody(title, url)
    if (body.length === 0) {
      return
    }
    await this.copyText(body)
  }

  /** 以简化参数打开分享面板 */
  openShare(opts: OpenShareOptions): void {
    this.openShareSheet({
      title: opts.title ?? 'Browser',
      url: opts.url ?? '',
      size: opts.size ?? '',
      previewImage: opts.previewImage ?? false
    })
  }

  /** 关闭分享面板 */
  closeShareSheet(): void {
    BrowserLog.info('[ShareSheet] close')
    AppStorage.set(AppStorageKeys.SHARE_VISIBLE, false)
  }

  /** 复制文本到系统剪贴板 */
  async copyText(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await pasteboard.getSystemPasteboard().setData(data)
    } catch (err) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.copy_failed')))
    }
  }

  /** 拉起系统短信应用并预填标题与链接（三方应用不可直接发短信，需跳转编辑页） */
  async shareLinkViaSms(title: string, url: string): Promise<void> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
      return
    }
    const payload = ShareService.resolveSmsSharePayload(title, url)
    if (payload.body.length === 0) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
      return
    }
    BrowserLog.info(`[Share] sms title=${payload.title.slice(0, 40)} url=${payload.url.slice(0, 80)} ` +
      `bodyLen=${payload.body.length}`)
    const launched = await ShareService.tryLaunchMmsText(ctx, payload.body)
    if (!launched) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
    }
  }

  /** 解析分享标题/链接，优先使用 AppStorage 中的分享面板数据 */
  private static resolveSmsSharePayload(title: string, url: string): ShareSmsPayload {
    const safeTitle = title.trim() || (AppStorage.get<string>(AppStorageKeys.SHARE_TITLE) ?? '').trim()
    const safeUrl = url.trim() || (AppStorage.get<string>(AppStorageKeys.SHARE_URL) ?? '').trim()
    let body = ''
    if (safeTitle.length > 0 && safeUrl.length > 0) {
      body = `${safeTitle}\n${safeUrl}`
    } else if (safeUrl.length > 0) {
      body = safeUrl
    } else if (safeTitle.length > 0) {
      body = safeTitle
    }
    return { title: safeTitle, url: safeUrl, body: body }
  }

  /** startAbility 静默尝试，失败不抛错 */
  private static async startAbilityQuiet(ctx: common.UIAbilityContext, want: Want): Promise<boolean> {
    try {
      await ctx.startAbility(want)
      return true
    } catch (err) {
      BrowserLog.warn(`[Share] startAbility failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 构造 MMS 新建会话 Want（contactObjects 必须为 JSON 字符串） */
  private static buildMmsComposeWant(body: string, pageFlag: string, contacts: MmsContactInfo[]): Want {
    return {
      bundleName: 'com.ohos.mms',
      abilityName: 'com.ohos.mms.MainAbility',
      moduleName: 'entry',
      parameters: {
        'contactObjects': JSON.stringify(contacts),
        'pageFlag': pageFlag,
        'content': body,
        'msgContent': body,
        'sms_body': body,
        'transmitContent': body,
        'draftContent': body
      }
    }
  }

  /** 尝试拉起短信新建会话并预填正文（避免 viewData+MainAbility 假成功只进列表） */
  private static async tryLaunchMmsText(ctx: common.UIAbilityContext, body: string): Promise<boolean> {
    const trimmed = body.trim()
    if (trimmed.length === 0) {
      return false
    }
    const smsUri = `sms:?body=${encodeURIComponent(trimmed)}`
    const blankContact: MmsContactInfo[] = [{ contactsName: '', telephone: 0 }]

    const openLinkOk = await ShareService.tryOpenLinkSms(ctx, trimmed, smsUri)
    if (openLinkOk) {
      BrowserLog.info(`[Share] sms opened via openLink+smsUri bodyLen=${trimmed.length}`)
      return true
    }

    const attempts: MmsLaunchAttempt[] = [
      {
        label: 'viewData+smsUri+official',
        build: (): Want => ({
          bundleName: 'com.ohos.mms',
          action: 'ohos.want.action.viewData',
          uri: smsUri
        })
      },
      {
        label: 'conversation+blank-contact',
        build: (): Want => ShareService.buildMmsComposeWant(trimmed, 'conversation', blankContact)
      },
      {
        label: 'sendData+stream-array',
        build: (): Want => ({
          bundleName: 'com.ohos.mms',
          abilityName: 'com.ohos.mms.MainAbility',
          moduleName: 'entry',
          action: 'ohos.want.action.sendData',
          type: 'text/plain',
          parameters: {
            'ability.params.stream': [trimmed],
            'ability.subject': trimmed.split('\n')[0],
            'content': trimmed,
            'msgContent': trimmed,
            'transmitContent': trimmed,
            'draftContent': trimmed
          }
        })
      },
      {
        label: 'conversation+uri+blank-contact',
        build: (): Want => ({
          bundleName: 'com.ohos.mms',
          abilityName: 'com.ohos.mms.MainAbility',
          moduleName: 'entry',
          uri: smsUri,
          parameters: {
            'contactObjects': JSON.stringify(blankContact),
            'pageFlag': 'conversation',
            'content': trimmed,
            'msgContent': trimmed,
            'sms_body': trimmed,
            'transmitContent': trimmed,
            'draftContent': trimmed
          }
        })
      }
    ]

    for (let i = 0; i < attempts.length; i++) {
      const attempt = attempts[i]
      const ok = await ShareService.startAbilityQuiet(ctx, attempt.build())
      if (ok) {
        BrowserLog.info(`[Share] sms opened via ${attempt.label} bodyLen=${trimmed.length}`)
        return true
      }
    }
    return false
  }

  /** 通过 openLink 打开 sms: URI（部分系统版本对第三方应用更友好） */
  private static async tryOpenLinkSms(ctx: common.UIAbilityContext, body: string, smsUri: string): Promise<boolean> {
    try {
      await ctx.openLink(smsUri, {
        parameters: {
          'sms_body': body,
          'content': body
        }
      })
      return true
    } catch (err) {
      BrowserLog.warn(`[Share] openLink sms failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** sendData 分享单个文件 URI（stream 必须为数组） */
  private static async tryLaunchSendDataWithUri(ctx: common.UIAbilityContext, uri: string,
    mimeType: string, title: string): Promise<boolean> {
    const shareFlags = wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION |
      wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION
    const safeTitle = title.trim()
    const wants: Want[] = [
      {
        action: 'ohos.want.action.sendData',
        uri,
        type: mimeType,
        flags: shareFlags,
        parameters: {
          'ability.params.stream': [uri],
          'ability.subject': safeTitle.length > 0 ? safeTitle : 'file',
        },
      },
    ]
    for (let i = 0; i < wants.length; i++) {
      try {
        await ctx.startAbility(wants[i])
        BrowserLog.info(`[Share] sendData uri attempt=${i}`)
        return true
      } catch (_err) {
        // 尝试下一种 Want
      }
    }
    return false
  }

  /** 分享到微信 */
  async shareLinkViaWeChat(title: string, url: string): Promise<void> {
    await this.shareLinkToBundles(title, url, ShareAppAvailability.BUNDLE_WECHAT)
  }

  /** 分享到 QQ */
  async shareLinkViaQQ(title: string, url: string): Promise<void> {
    await this.shareLinkToBundles(title, url, ShareAppAvailability.BUNDLE_QQ)
  }

  /** 分享到企业微信 */
  async shareLinkViaWeCom(title: string, url: string): Promise<void> {
    await this.shareLinkToBundles(title, url, ShareAppAvailability.BUNDLE_WECOM)
  }

  /** 分享到抖音 */
  async shareLinkViaDouyin(title: string, url: string): Promise<void> {
    await this.shareLinkToBundles(title, url, ShareAppAvailability.BUNDLE_DOUYIN)
  }

  /** 调用分享选择器分享链接 */
  async shareLinkViaSystem(title: string, url: string): Promise<void> {
    await this.shareViaSendData(title, url)
  }

  /** 添加到超级中转站：复制内容并尝试拉起中转站应用 */
  async shareToTransferStation(title: string, url: string): Promise<void> {
    const body = this.shareBody(title, url)
    await this.copyText(body)
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_transfer')))
      return
    }
    for (let i = 0; i < ShareAppAvailability.BUNDLE_TRANSFER.length; i++) {
      const launched = await this.tryLaunchSendData(ctx, title, url, ShareAppAvailability.BUNDLE_TRANSFER[i])
      if (launched) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_transfer')))
        return
      }
    }
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.toast_transfer')))
  }

  /** 打印/蓝牙等场景：优先分享文件，否则走分享选择器 */
  async shareForDeviceAction(title: string, url: string, localPath: string = ''): Promise<void> {
    if (localPath.length > 0) {
      const shared = await this.shareFileViaSendData(title, localPath)
      if (shared) {
        return
      }
    }
    await this.shareViaSendData(title, url)
  }

  /** 蓝牙分享：走系统 sendData，由用户选择蓝牙传输目标 */
  async shareViaBluetooth(title: string, url: string, localPath: string = ''): Promise<void> {
    if (localPath.length > 0) {
      const shared = await this.shareFileViaSendData(title, localPath)
      if (shared) {
        return
      }
    }
    await this.shareViaSendData(title, url)
  }

  /** 分享图片链接或本地图片文件 */
  async shareImageViaSystem(title: string, imageUrl: string, localPath: string = ''): Promise<void> {
    if (localPath.length > 0) {
      const shared = await this.shareFileViaSendData(title || imageUrl, localPath)
      if (shared) {
        return
      }
    }
    const cached = await ImageGalleryService.getInstance().writeImageToShareCache(imageUrl)
    if (cached) {
      const shared = await this.shareFileViaSendData(title || imageUrl, cached)
      if (shared) {
        return
      }
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
      return
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.sendData',
        type: 'text/plain',
        parameters: {
          'ability.params.stream': imageUrl,
          'ability.subject': title || imageUrl
        }
      }
      await ctx.startAbility(want)
    } catch (_err) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.share_failed')))
    }
  }
}
