import { wantAgent, Want } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { DownloadNotificationParams } from './DownloadNotificationParams'

interface NotificationBasicContentPayload {
  title: string
  text: string
}

interface NotificationContentPayload {
  notificationContentType: notificationManager.ContentType
  normal: NotificationBasicContentPayload
}

interface NotificationTemplatePayload {
  name: string
  data: Record<string, Object>
}

interface NotificationActionButtonPayload {
  title: string
  wantAgent: object
}

interface NotificationRequestPayload {
  id: number
  content: NotificationContentPayload
  template?: NotificationTemplatePayload
  actionButtons?: NotificationActionButtonPayload[]
  wantAgent?: object
  tapDismissed?: boolean
  notificationSlotType?: notificationManager.SlotType
}

type DownloadNotifPhase = 'running' | 'paused' | 'done'

interface DownloadNotifTaskState {
  fileName: string
  progress: number
  phase: DownloadNotifPhase
  completedAt: number
  updatedAt: number
}

interface DownloadNotifDisplayPick {
  taskId: string
  state: DownloadNotifTaskState
}

/** 下载进度系统通知：全局合并为一条；进行中显示进度+暂停，完成后冻结展示不再刷新 */
export class DownloadNotificationService {
  private static instance: DownloadNotificationService | null = null
  /** 浏览器下载统一通知 ID（所有任务共用，避免通知中心多条） */
  private static readonly UNIFIED_NOTIFICATION_ID: number = 10001
  private templateChecked: boolean = false
  private templateSupported: boolean = false
  private readonly wantAgentCache: Map<string, object> = new Map()
  private readonly taskStates: Map<string, DownloadNotifTaskState> = new Map()
  private lastPublishedPhase: DownloadNotifPhase | 'idle' = 'idle'
  private frozenCompleteKey: string = ''
  private sessionNotificationEnabled: boolean = false
  private lastProgressPublishAt: number = 0
  private lastProgressPublishPct: number = -1
  /** 进度通知最小发布间隔（ms），避免频繁 publish 触发震动 */
  private static readonly PROGRESS_PUBLISH_INTERVAL_MS: number = 3000
  /** 进度变化低于该值时跳过通知刷新（完成/暂停除外） */
  private static readonly PROGRESS_PUBLISH_MIN_DELTA: number = 5

  static getInstance(): DownloadNotificationService {
    if (DownloadNotificationService.instance === null) {
      DownloadNotificationService.instance = new DownloadNotificationService()
    }
    return DownloadNotificationService.instance
  }

  /**
   * 确保应用通知已开启（下载确认等用户操作场景可 requestIfNeeded=true 弹授权）。
   * 1600004 表示通知开关关闭，不永久缓存失败，便于用户去设置开启后重试。
   */
  async ensureNotificationAccess(requestIfNeeded: boolean = false): Promise<boolean> {
    if (BrowserStore.isIncognito()) {
      return false
    }
    const ctx = BrowserStore.getContext()
    if (ctx === null) {
      BrowserLog.warn('[DownloadNotif] no UIAbilityContext, skip')
      return false
    }
    let enabled = await this.queryNotificationEnabled()
    if (!enabled && requestIfNeeded) {
      try {
        await notificationManager.requestEnableNotification(ctx)
      } catch (reqErr) {
        BrowserLog.warn(`[DownloadNotif] requestEnableNotification: ${JSON.stringify(reqErr)}`)
      }
      enabled = await this.queryNotificationEnabled()
    }
    if (!enabled) {
      BrowserLog.warn('[DownloadNotif] notification disabled, code may be 1600004')
      return false
    }
    await this.ensureDownloadSlots()
    return true
  }

  /** 下载确认时记录通知权限，供后续进度通知快速判定 */
  markNotificationEnabledForSession(enabled: boolean): void {
    this.sessionNotificationEnabled = enabled
    BrowserLog.info(`[DownloadNotif] sessionNotificationEnabled=${enabled}`)
  }

  /** 下载进行中：更新合并通知（进度 + 暂停，与下载管理共用同一 progress） */
  async notifyRunningProgress(taskId: string, fileName: string, progress: number): Promise<void> {
    this.updateTaskState(taskId, fileName, progress, 'running')
    const pct = Math.min(100, Math.max(0, Math.floor(progress)))
    if (!this.shouldPublishProgress(pct, 'running')) {
      return
    }
    await this.refreshUnifiedNotification(true)
    this.markProgressPublished(pct)
  }

  /** 已暂停：合并通知显示继续按钮 */
  async notifyPausedProgress(taskId: string, fileName: string, progress: number): Promise<void> {
    this.updateTaskState(taskId, fileName, progress, 'paused')
    await this.refreshUnifiedNotification(true)
    this.markProgressPublished(Math.min(100, Math.max(0, Math.floor(progress))))
  }

  /** 下载完成：合并通知切到已完成态，移除暂停按钮，不再刷新进度 */
  async notifyDownloadComplete(taskId: string, fileName: string): Promise<void> {
    const name = fileName.trim()
    if (name.length === 0 || BrowserStore.isIncognito()) {
      return
    }
    this.updateTaskState(taskId, name, 100, 'done')
    await this.refreshUnifiedNotification(true)
  }

  /** 任务结束/失败/删除：从合并通知状态中移除 */
  async cancelProgress(taskId: string): Promise<void> {
    if (taskId.length === 0) {
      return
    }
    this.taskStates.delete(taskId)
    this.cancelLegacyNotification(taskId)
    if (this.taskStates.size === 0) {
      this.frozenCompleteKey = ''
      this.lastPublishedPhase = 'idle'
      await this.cancelUnifiedNotification()
      return
    }
    await this.refreshUnifiedNotification(true)
  }

  private updateTaskState(
    taskId: string,
    fileName: string,
    progress: number,
    phase: DownloadNotifPhase
  ): void {
    const id = taskId.trim()
    const name = fileName.trim()
    if (id.length === 0 || name.length === 0 || BrowserStore.isIncognito()) {
      return
    }
    const pct = Math.min(100, Math.max(0, Math.floor(progress)))
    this.taskStates.set(id, {
      fileName: name,
      progress: pct,
      phase,
      completedAt: phase === 'done' ? Date.now() : 0,
      updatedAt: Date.now()
    })
    if (phase !== 'done') {
      this.frozenCompleteKey = ''
    }
    if (phase === 'running') {
      const doneIds: string[] = []
      const allIds = this.collectTaskIds()
      for (let i = 0; i < allIds.length; i++) {
        const tid = allIds[i]
        const s = this.taskStates.get(tid)
        if (s !== undefined && s.phase === 'done' && tid !== id) {
          doneIds.push(tid)
        }
      }
      for (let i = 0; i < doneIds.length; i++) {
        this.taskStates.delete(doneIds[i])
      }
    }
  }

  private collectTaskIds(): string[] {
    const ids: string[] = []
    this.taskStates.forEach((_state: DownloadNotifTaskState, taskId: string) => {
      ids.push(taskId)
    })
    return ids
  }

  private pickDisplayTask(): DownloadNotifDisplayPick | null {
    let runningPick: DownloadNotifDisplayPick | null = null
    let pausedPick: DownloadNotifDisplayPick | null = null
    let donePick: DownloadNotifDisplayPick | null = null
    const allIds = this.collectTaskIds()
    for (let i = 0; i < allIds.length; i++) {
      const taskId = allIds[i]
      const state = this.taskStates.get(taskId)
      if (state === undefined) {
        continue
      }
      if (state.phase === 'running') {
        if (runningPick === null || state.updatedAt > runningPick.state.updatedAt) {
          const pick: DownloadNotifDisplayPick = { taskId, state }
          runningPick = pick
        }
        continue
      }
      if (state.phase === 'paused') {
        if (pausedPick === null) {
          const pick: DownloadNotifDisplayPick = { taskId, state }
          pausedPick = pick
        }
        continue
      }
      if (state.phase === 'done') {
        if (donePick === null || state.completedAt > donePick.state.completedAt) {
          const pick: DownloadNotifDisplayPick = { taskId, state }
          donePick = pick
        }
      }
    }
    if (runningPick !== null) {
      return runningPick
    }
    if (pausedPick !== null) {
      return pausedPick
    }
    return donePick
  }

  private async refreshUnifiedNotification(force: boolean): Promise<void> {
    if (BrowserStore.isIncognito()) {
      return
    }
    const picked = this.pickDisplayTask()
    if (picked === null) {
      await this.cancelUnifiedNotification()
      return
    }
    const ready = await this.ensureNotificationAccess(false)
    if (!ready) {
      BrowserLog.warn('[DownloadNotif] skip publish: notification disabled')
      return
    }
    const taskId = picked.taskId
    const state = picked.state
    if (state.phase === 'done') {
      const snapshotKey = `${taskId}_${state.fileName}`
      if (!force && this.frozenCompleteKey === snapshotKey && this.lastPublishedPhase === 'done') {
        return
      }
      this.frozenCompleteKey = snapshotKey
      await this.publishComplete(taskId, state.fileName)
      this.lastPublishedPhase = 'done'
      return
    }
    await this.publishProgress(taskId, state.fileName, state.progress, state.phase)
    this.lastPublishedPhase = state.phase
  }

  private async publishProgress(
    taskId: string,
    fileName: string,
    progress: number,
    phase: DownloadNotifPhase
  ): Promise<void> {
    const pct = Math.min(100, Math.max(0, Math.floor(progress)))
    const templateOk = await this.ensureDownloadTemplateSupported()
    const title = BrowserStrings.txt($r('app.string.download_progress_notification_title'))
    const detail = BrowserStrings.downloadNotificationProgressText(fileName, pct)
    const actionTitle = phase === 'running'
      ? BrowserStrings.txt($r('app.string.download_notification_pause'))
      : BrowserStrings.txt($r('app.string.download_notification_resume'))
    const action = phase === 'running'
      ? DownloadNotificationParams.ACTION_PAUSE
      : DownloadNotificationParams.ACTION_RESUME
    try {
      const openAgent = await this.getOpenWantAgent()
      const actionAgent = await this.getButtonWantAgent(action, taskId)
      const content: NotificationContentPayload = {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title, text: detail }
      }
      const request: NotificationRequestPayload = {
        id: DownloadNotificationService.UNIFIED_NOTIFICATION_ID,
        content,
        wantAgent: openAgent,
        tapDismissed: false,
        notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
        actionButtons: [{ title: actionTitle, wantAgent: actionAgent }]
      }
      if (templateOk) {
        request.template = {
          name: 'downloadTemplate',
          data: {
            'title': title,
            'fileName': detail,
            'progressValue': pct
          }
        }
      }
      await notificationManager.publish(request)
      this.cancelLegacyNotification(taskId)
      BrowserLog.info(`[DownloadNotif] publish progress ok id=${taskId} pct=${pct}`)
    } catch (err) {
      BrowserLog.warn(`[DownloadNotif] publish progress failed id=${taskId}: ${JSON.stringify(err)}`)
    }
  }

  private async publishComplete(taskId: string, fileName: string): Promise<void> {
    const title = BrowserStrings.txt($r('app.string.download_complete_notification_title'))
    const detail = BrowserStrings.downloadNotificationDoneText(fileName)
    try {
      const openAgent = await this.getOpenWantAgent()
      const content: NotificationContentPayload = {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title, text: detail }
      }
      const request: NotificationRequestPayload = {
        id: DownloadNotificationService.UNIFIED_NOTIFICATION_ID,
        content,
        wantAgent: openAgent,
        tapDismissed: false,
        notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION
      }
      await notificationManager.publish(request)
      this.cancelLegacyNotification(taskId)
      BrowserLog.info(`[DownloadNotif] publish complete ok id=${taskId}`)
    } catch (err) {
      BrowserLog.warn(`[DownloadNotif] publish complete failed id=${taskId}: ${JSON.stringify(err)}`)
    }
  }

  private async cancelUnifiedNotification(): Promise<void> {
    try {
      await notificationManager.cancel(DownloadNotificationService.UNIFIED_NOTIFICATION_ID)
    } catch (_err) {
      // 通知可能不存在
    }
  }

  /** 取消旧版按任务 hash 的分散通知，避免升级后残留多条 */
  private cancelLegacyNotification(taskId: string): void {
    try {
      notificationManager.cancel(this.legacyNotificationIdForTask(taskId))
    } catch (_err) {
      // 旧通知可能不存在
    }
  }

  private legacyNotificationIdForTask(taskId: string): number {
    let hash = 0
    for (let i = 0; i < taskId.length; i++) {
      hash = ((hash << 5) - hash + taskId.charCodeAt(i)) | 0
    }
    return 10000 + (Math.abs(hash) % 8000)
  }

  private requestCodeFor(taskId: string, action: string): number {
    let hash = 0
    const key = `${taskId}_${action}`
    for (let i = 0; i < key.length; i++) {
      hash = ((hash << 5) - hash + key.charCodeAt(i)) | 0
    }
    return Math.abs(hash) % 1000000
  }

  private async getOpenWantAgent(): Promise<object> {
    return this.buildWantAgent(DownloadNotificationParams.ACTION_OPEN, '', wantAgent.OperationType.START_ABILITY)
  }

  private async getButtonWantAgent(action: string, taskId: string): Promise<object> {
    return this.buildWantAgent(action, taskId, wantAgent.OperationType.SEND_COMMON_EVENT)
  }

  private async buildWantAgent(
    action: string,
    taskId: string,
    operationType: wantAgent.OperationType
  ): Promise<object> {
    const cacheKey = `${operationType}_${action}_${taskId}`
    const cached = this.wantAgentCache.get(cacheKey)
    if (cached !== undefined) {
      return cached
    }
    const ctx = BrowserStore.getContext()
    if (ctx === null) {
      throw new Error('DownloadNotificationService: no UIAbilityContext')
    }
    const parameters: Record<string, Object> = {}
    parameters[DownloadNotificationParams.KEY_ACTION] = action
    if (taskId.length > 0) {
      parameters[DownloadNotificationParams.KEY_TASK_ID] = taskId
    }
    let wantInfo: Want
    if (operationType === wantAgent.OperationType.SEND_COMMON_EVENT) {
      wantInfo = {
        action: DownloadNotificationParams.COMMON_EVENT,
        parameters
      }
    } else {
      wantInfo = {
        bundleName: ctx.abilityInfo.bundleName,
        abilityName: ctx.abilityInfo.name,
        parameters
      }
    }
    const info: wantAgent.WantAgentInfo = {
      wants: [wantInfo],
      actionType: operationType,
      requestCode: this.requestCodeFor(taskId, action),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    const agent: object = await wantAgent.getWantAgent(info)
    this.wantAgentCache.set(cacheKey, agent)
    return agent
  }

  private async queryNotificationEnabled(): Promise<boolean> {
    try {
      if (notificationManager.isNotificationEnabledSync()) {
        return true
      }
      return await notificationManager.isNotificationEnabled()
    } catch (err) {
      BrowserLog.warn(`[DownloadNotif] queryNotificationEnabled failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  private async ensureDownloadSlots(): Promise<void> {
    const slots: notificationManager.SlotType[] = [
      notificationManager.SlotType.CONTENT_INFORMATION
    ]
    for (let i = 0; i < slots.length; i++) {
      try {
        await notificationManager.addSlot(slots[i])
      } catch (_err) {
        // 槽位可能已存在
      }
    }
  }

  /** 进行中进度通知节流：降低 publish 频率，避免连续震动 */
  private shouldPublishProgress(pct: number, phase: DownloadNotifPhase): boolean {
    if (phase !== 'running') {
      return true
    }
    if (pct >= 100) {
      return true
    }
    const now = Date.now()
    if (this.lastProgressPublishPct < 0) {
      return true
    }
    if (now - this.lastProgressPublishAt >= DownloadNotificationService.PROGRESS_PUBLISH_INTERVAL_MS) {
      return true
    }
    return Math.abs(pct - this.lastProgressPublishPct) >= DownloadNotificationService.PROGRESS_PUBLISH_MIN_DELTA
  }

  private markProgressPublished(pct: number): void {
    this.lastProgressPublishAt = Date.now()
    this.lastProgressPublishPct = pct
  }

  private async ensureDownloadTemplateSupported(): Promise<boolean> {
    if (this.templateChecked) {
      return this.templateSupported
    }
    this.templateChecked = true
    try {
      this.templateSupported = await notificationManager.isSupportTemplate('downloadTemplate')
    } catch (_err) {
      this.templateSupported = false
    }
    return this.templateSupported
  }
}
