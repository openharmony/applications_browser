import {
  createIdleDownloadIndicatorSnapshot,
  cloneDownloadTask,
  createDownloadTask,
  DownloadIndicatorSnapshot,
  DownloadStartRequest,
  DownloadTask,
  DownloadTaskQuery,
  DownloadTaskState,
  DownloadTaskUpdate,
  WebDownloadStartInput,
  buildDownloadStartRequest,
  compareDownloadTasksByCreatedAtDesc,
  isActiveDownloadState,
  matchesDownloadTask,
} from './downloadTypes';
import { DownloadService } from '../integration/downloadService';
import webview from '@ohos.web.webview';
import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';
import { SettingsManager } from './settingsManager';

type DownloadListener = (downloads: DownloadTask[]) => void;

export interface DownloadMutationResult {
  success: boolean;
  errorMessage?: string;
}

export class DownloadManager {
  private static instance: DownloadManager = new DownloadManager();
  private readonly DB_NAME: string = 'browser_downloads.db';
  private readonly TABLE_NAME: string = 'download_tasks';
  private items: Map<string, DownloadTask> = new Map();
  private listeners: Set<DownloadListener> = new Set();
  private downloadService: DownloadService = new DownloadService();
  private settingsManager: SettingsManager;
  private hostContext: object | undefined = undefined;
  private hasUnreadCompletedNotice: boolean = false;
  private hasUnreadFailedNotice: boolean = false;
  // This is intentionally in-memory only. Persisted completed downloads from
  // an earlier app process must not make the toolbar button reappear after a
  // browser restart, while a task started in this process keeps the button
  // visible for the rest of the session.
  private hasSessionDownloadActivity: boolean = false;
  // The toolbar progress represents the current app-session download batch.
  // Keeping the ids in memory prevents old records loaded from the database
  // from affecting the progress of a newly started download.
  private sessionDownloadIds: Set<string> = new Set();
  private rdbStore: relationalStore.RdbStore | null = null;
  private isInitialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private attemptGenerations: Map<string, number> = new Map();
  // Callback generations protect stale download events; action locks protect
  // the UI and service from duplicate user commands.
  private actionLocks: Map<string, string> = new Map();
  // Request context is deliberately process-local. In particular, Cookie is
  // never stored here or in RDB; DownloadService reads a fresh scoped Cookie
  // from ArkWeb for every start/retry.
  private requestContexts: Map<string, DownloadStartRequest> = new Map();
  private queuedPersistence: Map<string, DownloadTask> = new Map();
  private persistenceTail: Promise<void> = Promise.resolve();

  constructor(downloadService?: DownloadService, settingsManager?: SettingsManager) {
    if (downloadService) {
      this.downloadService = downloadService;
    }
    this.settingsManager = settingsManager ?? SettingsManager.getInstance();
  }

  static getInstance(): DownloadManager {
    return DownloadManager.instance;
  }

  async init(context: object): Promise<void> {
    if (this.isInitialized && this.rdbStore) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.initInternal(context)
      .then(() => {
        this.isInitialized = true;
      })
      .finally(() => {
        this.initPromise = null;
      });
    return this.initPromise;
  }

  setHostContext(context: object | undefined): void {
    this.hostContext = context;
  }

  private normalizeStartRequest(
    requestOrUrl: DownloadStartRequest | string,
    suggestedFileName?: string
  ): DownloadStartRequest {
    if (typeof requestOrUrl === 'string') {
      const request: DownloadStartRequest = {
        sourceUrl: requestOrUrl,
        fileName: suggestedFileName,
      };
      return this.applyDownloadSettings(request);
    }
    return this.applyDownloadSettings(requestOrUrl);
  }

  private applyDownloadSettings(request: DownloadStartRequest): DownloadStartRequest {
    const settings = this.settingsManager.getSettings();
    return {
      sourceUrl: request.sourceUrl,
      fileName: request.fileName,
      mimeType: request.mimeType,
      pageUrl: request.pageUrl,
      pageTitle: request.pageTitle,
      userAgent: request.userAgent,
      totalBytes: request.totalBytes,
      isPrivate: request.isPrivate,
      downloadDirectoryUri: settings.downloadDirectoryUri,
    };
  }

  startDownload(requestOrUrl: DownloadStartRequest | string, suggestedFileName?: string): DownloadTask {
    const request: DownloadStartRequest = this.normalizeStartRequest(requestOrUrl, suggestedFileName);
    const task = createDownloadTask(request, this.generateId());
    task.state = 'pending';
    if (!task.isPrivate) {
      this.hasSessionDownloadActivity = true;
      this.sessionDownloadIds.add(task.id);
    }
    this.items.set(task.id, task);
    this.persistTask(task);
    this.notify();
    return cloneDownloadTask(task);
  }

  async startManagedDownload(
    requestOrUrl: DownloadStartRequest | string,
    suggestedFileName?: string,
    hostContext?: object
  ): Promise<DownloadTask> {
    const request: DownloadStartRequest = this.normalizeStartRequest(requestOrUrl, suggestedFileName);
    const task = this.startDownload(request);
    this.requestContexts.set(task.id, request);
    const attemptGeneration = this.beginAttempt(task.id);
    const effectiveContext = hostContext ?? this.hostContext;
    if (!effectiveContext) {
      this.markFailed(task.id, '下载上下文不可用', 'missing_context');
      return this.getDownload(task.id) ?? task;
    }

    this.hostContext = effectiveContext;
    this.updateDownload(task.id, { state: 'pending' });

    try {
      await this.downloadService.start(task.id, effectiveContext, request, {
        onProgress: (receivedBytes: number, totalBytes: number, percentComplete?: number) => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.markDownloading(task.id, receivedBytes, totalBytes, percentComplete);
        },
        onComplete: (filePath?: string) => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.markCompleted(task.id, filePath);
        },
        onFail: (code: number) => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.markFailed(task.id, `下载失败，错误码：${code}`, String(code));
        },
        onPause: () => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.updateDownload(task.id, { state: 'paused', canResume: true, canRetry: false });
        },
        onRemove: () => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.cancelDownload(task.id);
        },
      });
    } catch (error) {
      if (this.isCurrentAttempt(task.id, attemptGeneration)) {
        this.markFailed(task.id, String(error), 'start_failed');
      }
    }

    return this.getDownload(task.id) ?? task;
  }

  async startWebDownload(input: WebDownloadStartInput, hostContext?: object): Promise<DownloadTask> {
    return this.startManagedDownload(buildDownloadStartRequest(input), undefined, hostContext);
  }

  createArkWebDownloadDelegate(onBeforeDownload: (item: webview.WebDownloadItem) => void): webview.WebDownloadDelegate {
    return this.downloadService.createArkWebDownloadDelegate(onBeforeDownload);
  }

  startArkWebDownload(item: webview.WebDownloadItem, input: WebDownloadStartInput,
    hostContext?: object): DownloadTask {
    const request = this.normalizeStartRequest(buildDownloadStartRequest(input));
    const task = this.startDownload(request);
    this.requestContexts.set(task.id, request);
    const attemptGeneration = this.beginAttempt(task.id);
    const effectiveContext = hostContext ?? this.hostContext;
    if (!effectiveContext) {
      return this.markFailed(task.id, '下载上下文不可用', 'missing_context') ?? task;
    }
    this.hostContext = effectiveContext;
    try {
      this.downloadService.startArkWebDownload(task.id, effectiveContext, request, item, {
        onProgress: (receivedBytes: number, totalBytes: number, percentComplete?: number) => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.markDownloading(task.id, receivedBytes, totalBytes, percentComplete);
        },
        onComplete: (filePath?: string) => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.markCompleted(task.id, filePath);
        },
        onFail: (code: number) => {
          if (!this.isCurrentAttempt(task.id, attemptGeneration)) {
            return;
          }
          this.markFailed(task.id, `网页下载失败，错误码：${code}`, String(code));
        },
      });
    } catch (error) {
      if (this.isCurrentAttempt(task.id, attemptGeneration)) {
        this.markFailed(task.id, String(error), 'arkweb_start_failed');
      }
    }
    return this.getDownload(task.id) ?? task;
  }

  getDownloads(query?: DownloadTaskQuery): DownloadTask[] {
    const downloads: DownloadTask[] = [];
    this.items.forEach((task: DownloadTask) => {
      if (matchesDownloadTask(task, query)) {
        downloads.push(this.cloneForView(task));
      }
    });
    downloads.sort(compareDownloadTasksByCreatedAtDesc);
    return downloads;
  }

  clearPrivateDownloads(): void {
    const privateTaskIds: string[] = [];
    this.items.forEach((task: DownloadTask, taskId: string) => {
      if (task.isPrivate) {
        privateTaskIds.push(taskId);
      }
    });

    if (privateTaskIds.length === 0) {
      return;
    }

    privateTaskIds.forEach((taskId: string) => {
      this.invalidateAttempt(taskId);
      this.cancelServiceTaskForRemoval(taskId);
      this.items.delete(taskId);
      this.sessionDownloadIds.delete(taskId);
      this.requestContexts.delete(taskId);
      this.queuedPersistence.delete(taskId);
      this.forgetAttempt(taskId);
    });

    this.notify();
  }

  async clearDownloads(includePrivate: boolean = false): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }

    const taskIds: string[] = [];
    this.items.forEach((task: DownloadTask, taskId: string) => {
      if (task.isPrivate && !includePrivate) {
        return;
      }
      taskIds.push(taskId);
    });

    if (taskIds.length === 0) {
      return;
    }

    taskIds.forEach((taskId: string) => {
      this.invalidateAttempt(taskId);
      this.cancelServiceTaskForRemoval(taskId);
      this.items.delete(taskId);
      this.sessionDownloadIds.delete(taskId);
      this.requestContexts.delete(taskId);
      this.queuedPersistence.delete(taskId);
      this.forgetAttempt(taskId);
    });

    this.notify();

    let firstErrorMessage: string = '';
    for (let index = 0; index < taskIds.length; index++) {
      try {
        await this.enqueuePersistence(() => this.deletePersistedTaskInternal(taskIds[index]));
      } catch (error) {
        if (!firstErrorMessage) {
          firstErrorMessage = error instanceof Error ? error.message : String(error);
        }
      }
    }
    if (firstErrorMessage) {
      throw new Error(firstErrorMessage);
    }
  }

  clearFinishedDownloads(includePrivate: boolean = false): void {
    const taskIds: string[] = [];
    this.items.forEach((task: DownloadTask, taskId: string) => {
      if (task.isPrivate && !includePrivate) {
        return;
      }
      if (!isActiveDownloadState(task.state)) {
        taskIds.push(taskId);
      }
    });

    if (taskIds.length === 0) {
      return;
    }

    taskIds.forEach((taskId: string) => {
      this.invalidateAttempt(taskId);
      this.cancelServiceTaskForRemoval(taskId);
      this.items.delete(taskId);
      this.sessionDownloadIds.delete(taskId);
      this.requestContexts.delete(taskId);
      this.queuedPersistence.delete(taskId);
      this.forgetAttempt(taskId);
      this.deletePersistedTask(taskId);
    });

    this.notify();
  }

  /**
   * Reliable settings-page variant. A record is removed from memory only
   * after its persisted copy has been deleted successfully.
   */
  async clearFinishedDownloadsAsync(includePrivate: boolean = false): Promise<DownloadMutationResult> {
    const taskIds: string[] = [];
    this.items.forEach((task: DownloadTask, taskId: string) => {
      if ((task.isPrivate && !includePrivate) || isActiveDownloadState(task.state)) {
        return;
      }
      taskIds.push(taskId);
    });

    if (taskIds.length === 0) {
      return { success: true };
    }

    const lockedIds: string[] = [];
    taskIds.forEach((taskId: string) => {
      if (this.beginAction(taskId, 'clear_finished')) {
        lockedIds.push(taskId);
      }
    });
    if (lockedIds.length === 0) {
      return { success: false, errorMessage: '下载任务正在处理中，请稍后重试' };
    }

    let firstErrorMessage: string = '';
    for (let index = 0; index < lockedIds.length; index++) {
      const taskId = lockedIds[index];
      try {
        await this.deletePersistedTaskAwait(taskId);
        this.items.delete(taskId);
        this.sessionDownloadIds.delete(taskId);
        this.requestContexts.delete(taskId);
        this.queuedPersistence.delete(taskId);
        this.invalidateAttempt(taskId);
        this.forgetAttempt(taskId);
      } catch (error) {
        if (!firstErrorMessage) {
          firstErrorMessage = error instanceof Error ? error.message : String(error);
        }
      } finally {
        this.endAction(taskId, 'clear_finished');
      }
      this.notify();
    }

    return firstErrorMessage.length > 0
      ? { success: false, errorMessage: firstErrorMessage }
      : { success: true };
  }

  /** Remove one record only after persistence has acknowledged the delete. */
  async removeDownloadAsync(id: string): Promise<DownloadMutationResult> {
    const task = this.items.get(id);
    if (!task) {
      return { success: false, errorMessage: '下载记录不存在' };
    }
    if (!this.beginAction(id, 'remove')) {
      return { success: false, errorMessage: '下载任务正在处理中，请稍后重试' };
    }

    const wasActive = isActiveDownloadState(task.state);
    try {
      if (wasActive) {
        await this.downloadService.cancel(id);
        this.invalidateAttempt(id);
        this.updateDownload(id, {
          state: 'canceled',
          canResume: false,
          canRetry: true,
        });
      }
      if (!wasActive) {
        this.invalidateAttempt(id);
      }
      await this.deletePersistedTaskAwait(id);
      this.items.delete(id);
      this.sessionDownloadIds.delete(id);
      this.requestContexts.delete(id);
      this.queuedPersistence.delete(id);
      this.forgetAttempt(id);
      this.notify();
      return { success: true };
    } catch (error) {
      return {
        success: false,
        errorMessage: error instanceof Error ? error.message : String(error),
      };
    } finally {
      this.endAction(id, 'remove');
    }
  }

  getDownload(id: string): DownloadTask | null {
    const task = this.items.get(id);
    return task ? this.cloneForView(task) : null;
  }

  getIndicatorSnapshot(): DownloadIndicatorSnapshot {
    const tasks = this.getDownloads();
    if (tasks.length === 0) {
      if (this.hasSessionDownloadActivity) {
        return {
          primaryState: 'session_history',
          activeTaskCount: 0,
          failedTaskCount: 0,
          completedTaskCount: 0,
          aggregateProgress: 100,
          hasActiveTasks: false,
          hasSessionDownloadActivity: true,
        };
      }
      return createIdleDownloadIndicatorSnapshot();
    }

    // Prefer tasks started/retried during this app session. If the process
    // restored an active task from storage before a new download was started,
    // keep that task visible as a fallback, but never mix old completed
    // history into a new task's ring progress.
    const sessionTasks = tasks.filter((task: DownloadTask) => this.sessionDownloadIds.has(task.id));
    const activeTasks = tasks.filter((task: DownloadTask) => matchesDownloadTask(task, { filter: 'active' }));
    const indicatorTasks = sessionTasks.length > 0 ? sessionTasks : activeTasks;

    let activeTaskCount = 0;
    let failedTaskCount = 0;
    let completedTaskCount = 0;

    indicatorTasks.forEach((task: DownloadTask) => {
      if (matchesDownloadTask(task, { filter: 'active' })) {
        activeTaskCount++;
      }
      if (task.state === 'failed') {
        failedTaskCount++;
      }
      if (task.state === 'completed') {
        completedTaskCount++;
      }
    });

    const aggregateProgress = this.calculateAggregateProgress(indicatorTasks);

    if (this.hasUnreadFailedNotice && activeTaskCount === 0) {
      return {
        primaryState: 'failed_notice',
        activeTaskCount: activeTaskCount,
        failedTaskCount: failedTaskCount,
        completedTaskCount: completedTaskCount,
        aggregateProgress: aggregateProgress,
        hasActiveTasks: false,
        hasSessionDownloadActivity: this.hasSessionDownloadActivity,
      };
    }

    if (activeTaskCount > 0) {
      return {
        primaryState: 'downloading',
        activeTaskCount: activeTaskCount,
        failedTaskCount: failedTaskCount,
        completedTaskCount: completedTaskCount,
        aggregateProgress: aggregateProgress,
        hasActiveTasks: true,
        hasSessionDownloadActivity: this.hasSessionDownloadActivity,
      };
    }

    if (this.hasUnreadCompletedNotice) {
      return {
        primaryState: 'completed_notice',
        activeTaskCount: 0,
        failedTaskCount: failedTaskCount,
        completedTaskCount: completedTaskCount,
        aggregateProgress: 100,
        hasActiveTasks: false,
        hasSessionDownloadActivity: this.hasSessionDownloadActivity,
      };
    }

    if (this.hasSessionDownloadActivity) {
      return {
        primaryState: 'session_history',
        activeTaskCount: 0,
        failedTaskCount: failedTaskCount,
        completedTaskCount: completedTaskCount,
        aggregateProgress: 100,
        hasActiveTasks: false,
        hasSessionDownloadActivity: true,
      };
    }

    return createIdleDownloadIndicatorSnapshot();
  }

  markIndicatorNoticeSeen(): void {
    this.hasUnreadCompletedNotice = false;
    this.hasUnreadFailedNotice = false;
    this.notify();
  }

  addListener(listener: DownloadListener): void {
    this.listeners.add(listener);
  }

  removeListener(listener: DownloadListener): void {
    this.listeners.delete(listener);
  }

  updateDownload(id: string, update: DownloadTaskUpdate): DownloadTask | null {
    const task = this.items.get(id);
    if (!task) {
      return null;
    }

    if (update.receivedBytes !== undefined) {
      task.receivedBytes = Math.max(0, update.receivedBytes);
    }
    if (update.totalBytes !== undefined) {
      task.totalBytes = update.totalBytes;
    }
    if (update.progress !== undefined) {
      task.progress = this.normalizeProgress(update.progress);
    }
    if (update.state !== undefined) {
      task.state = update.state;
    }
    if (update.filePath !== undefined) {
      task.filePath = update.filePath;
    }
    if (update.errorCode !== undefined) {
      task.errorCode = update.errorCode;
    }
    if (update.errorMessage !== undefined) {
      task.errorMessage = update.errorMessage;
    }
    if (update.canResume !== undefined) {
      task.canResume = update.canResume;
    }
    if (update.canRetry !== undefined) {
      task.canRetry = update.canRetry;
    }
    if (update.completedAt !== undefined) {
      task.completedAt = update.completedAt;
    }
    task.updatedAt = Date.now();

    if (task.state === 'completed' && !task.completedAt) {
      task.completedAt = task.updatedAt;
      task.progress = 100;
      task.canRetry = false;
      task.canResume = false;
    }
    if (task.state === 'failed') {
      task.canRetry = true;
      task.canResume = false;
    }
    if (task.state === 'canceled') {
      task.canRetry = true;
      task.canResume = false;
    }

    this.persistTask(task);
    this.notify();
    return cloneDownloadTask(task);
  }

  markDownloading(id: string, receivedBytes: number, totalBytes?: number,
    percentComplete?: number): DownloadTask | null {
    // 暂停/取消/失败/完成的任务不应被 onProgress 回调覆盖回 downloading
    const existing = this.items.get(id);
    if (existing && (existing.state === 'paused' || existing.state === 'canceled' ||
        existing.state === 'completed' || existing.state === 'failed')) {
      return cloneDownloadTask(existing);
    }
    const byteProgress = totalBytes !== undefined && totalBytes > 0
      ? Math.floor((Math.max(0, receivedBytes) * 100) / totalBytes)
      : 0;
    // ArkWeb's percentage can arrive before byte counters are updated, while
    // some implementations expose 0 even though the byte counters advance.
    // Keep the more advanced of the two signals so the toolbar ring does not
    // stall or visibly jump backwards.
    const callbackProgress = percentComplete !== undefined
      ? this.normalizeProgress(percentComplete)
      : 0;
    const progress = this.normalizeProgress(Math.max(callbackProgress, byteProgress));
    return this.updateDownload(id, {
      state: 'downloading',
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      progress: progress,
      canResume: false,
      canRetry: false,
    });
  }

  markCompleted(id: string, filePath?: string): DownloadTask | null {
    const task = this.items.get(id);
    if (task && !task.isPrivate && this.settingsManager.getSettings().showDownloadsWhenFinished) {
      this.hasUnreadCompletedNotice = true;
    }
    this.requestContexts.delete(id);
    return this.updateDownload(id, {
      state: 'completed',
      progress: 100,
      filePath: filePath,
      completedAt: Date.now(),
    });
  }

  markFailed(id: string, errorMessage?: string, errorCode?: string): DownloadTask | null {
    const task = this.items.get(id);
    if (task && !task.isPrivate) {
      this.hasUnreadFailedNotice = true;
    }
    return this.updateDownload(id, {
      state: 'failed',
      errorCode: errorCode,
      errorMessage: errorMessage,
      canRetry: true,
    });
  }

  cancelDownload(id: string): DownloadTask | null {
    return this.updateDownload(id, {
      state: 'canceled',
      canRetry: true,
      canResume: false,
    });
  }

  pauseDownload(id: string): DownloadTask | null {
    const task = this.items.get(id);
    if (!task || !isActiveDownloadState(task.state) || task.state === 'paused') {
      return task ? cloneDownloadTask(task) : null;
    }

    return this.updateDownload(id, {
      state: 'paused',
      canResume: true,
      canRetry: false,
    });
  }

  resumeDownload(id: string): DownloadTask | null {
    const task = this.items.get(id);
    if (!task || task.state !== 'paused') {
      return task ? cloneDownloadTask(task) : null;
    }

    return this.updateDownload(id, {
      state: 'pending',
      canResume: false,
      canRetry: false,
      errorCode: '',
      errorMessage: '',
    });
  }

  cancelManagedDownload(id: string): void {
    const task = this.items.get(id);
    if (!task || !isActiveDownloadState(task.state) || !this.beginAction(id, 'cancel')) {
      return;
    }
    const previous = cloneDownloadTask(task);
    // Optimistically reflect the user's command. The action label and the
    // canceled state are published immediately; a service failure restores
    // the prior active state so the row does not appear canceled falsely.
    this.cancelDownload(id);
    this.downloadService.cancel(id)
      .then(() => {
        const current = this.items.get(id);
        // A completion callback may win the race with cancellation. Never
        // turn a successfully completed download into a canceled one.
        if (current && current.state === 'canceled') {
          this.invalidateAttempt(id);
        }
        this.endAction(id, 'cancel');
      })
      .catch((error: Object) => {
        this.restoreControlStateAfterFailure(
          id, previous, 'cancel_failed', '取消下载失败，请重试', 'cancel', 'canceled'
        );
      });
  }

  pauseManagedDownload(id: string): void {
    const task = this.items.get(id);
    if (!task || !isActiveDownloadState(task.state) || task.state === 'paused' || !this.beginAction(id, 'pause')) {
      return;
    }

    const previous = cloneDownloadTask(task);
    // Publish the paused state synchronously. This is important for ArkWeb
    // downloads, whose pause event may arrive asynchronously or not at all.
    this.pauseDownload(id);
    this.downloadService.pause(id)
      .then(() => {
        const current = this.items.get(id);
        if (current && isActiveDownloadState(current.state) && current.state !== 'paused') {
          this.pauseDownload(id);
        }
        this.endAction(id, 'pause');
      })
      .catch((error: Object) => {
        this.restoreControlStateAfterFailure(
          id, previous, 'pause_failed', '暂停下载失败，请重试', 'pause', 'paused'
        );
      });
  }

  resumeManagedDownload(id: string): void {
    const task = this.items.get(id);
    if (!task || task.state !== 'paused' || !this.beginAction(id, 'resume')) {
      return;
    }

    this.downloadService.resume(id)
      .then(() => {
        const current = this.items.get(id);
        if (current && current.state === 'paused') {
          this.resumeDownload(id);
        }
        this.endAction(id, 'resume');
      })
      .catch((error: Object) => {
        this.setActionFailure(id, 'resume_failed', '继续下载失败，请重试', 'resume');
      });
  }

  retryDownload(id: string): DownloadTask | null {
    const task = this.items.get(id);
    if (!task) {
      return null;
    }
    task.errorCode = undefined;
    task.errorMessage = undefined;
    task.progress = 0;
    task.receivedBytes = 0;
    task.completedAt = undefined;
    task.state = 'pending';
    task.canRetry = false;
    task.canResume = false;
    task.updatedAt = Date.now();
    if (!task.isPrivate) {
      this.hasSessionDownloadActivity = true;
      this.sessionDownloadIds.add(id);
    }
    this.persistTask(task);
    this.notify();
    return cloneDownloadTask(task);
  }

  retryManagedDownload(id: string): void {
    const task = this.items.get(id);
    if (!task || (task.state !== 'failed' && task.state !== 'canceled') || !task.canRetry ||
      !this.beginAction(id, 'retry')) {
      return;
    }
    const previousRequest = this.requestContexts.get(id);
    const request: DownloadStartRequest = this.applyDownloadSettings({
      sourceUrl: task.sourceUrl,
      fileName: task.fileName,
      mimeType: task.mimeType,
      pageUrl: task.pageUrl,
      pageTitle: task.pageTitle,
      userAgent: previousRequest?.userAgent,
      totalBytes: task.totalBytes,
      isPrivate: task.isPrivate,
    });
    this.requestContexts.set(id, request);
    const attemptGeneration = this.beginAttempt(id);
    this.retryDownload(id);
    const effectiveContext = this.hostContext;
    if (!effectiveContext) {
      this.markFailed(id, '下载上下文不可用', 'missing_context');
      this.endAction(id, 'retry');
      return;
    }
    this.downloadService.start(id, effectiveContext, request, {
      onProgress: (receivedBytes: number, totalBytes: number, percentComplete?: number) => {
        if (!this.isCurrentAttempt(id, attemptGeneration)) {
          return;
        }
        this.markDownloading(id, receivedBytes, totalBytes, percentComplete);
      },
        onComplete: (filePath?: string) => {
          if (!this.isCurrentAttempt(id, attemptGeneration)) {
            return;
          }
          this.markCompleted(id, filePath);
          this.endAction(id, 'retry');
        },
        onFail: (code: number) => {
          if (!this.isCurrentAttempt(id, attemptGeneration)) {
            return;
          }
          this.markFailed(id, `下载失败，错误码：${code}`, String(code));
          this.endAction(id, 'retry');
        },
      onPause: () => {
        if (!this.isCurrentAttempt(id, attemptGeneration)) {
          return;
        }
        this.updateDownload(id, { state: 'paused', canResume: true, canRetry: false });
      },
      onRemove: () => {
        if (!this.isCurrentAttempt(id, attemptGeneration)) {
          return;
        }
        this.cancelDownload(id);
      },
    }).catch((error: Object) => {
      if (this.isCurrentAttempt(id, attemptGeneration)) {
        this.markFailed(id, String(error), 'retry_failed');
      }
      this.endAction(id, 'retry');
    });
  }

  removeDownload(id: string): void {
    this.invalidateAttempt(id);
    this.cancelServiceTaskForRemoval(id);
    this.items.delete(id);
    this.sessionDownloadIds.delete(id);
    this.requestContexts.delete(id);
    this.queuedPersistence.delete(id);
    this.forgetAttempt(id);
    this.deletePersistedTask(id);
    this.notify();
  }

  private cancelServiceTaskForRemoval(id: string): void {
    this.downloadService.cancel(id).catch(() => {
    });
  }

  private async initInternal(context: object): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: this.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };

    this.rdbStore = await new Promise((resolve, reject) => {
      relationalStore.getRdbStore(context as never, config,
        (err: BusinessError | null, store: relationalStore.RdbStore | null): void => {
          if (err || !store) {
            reject(err || new Error('Failed to get download store'));
            return;
          }
          resolve(store);
        });
    });

    await this.createTable();
    await this.loadTasksFromStore();
    await this.flushQueuedPersistence();
    this.persistCurrentRegularTasks();
  }

  private async createTable(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    const createTableSql = `
      CREATE TABLE IF NOT EXISTS ${this.TABLE_NAME} (
        id TEXT PRIMARY KEY,
        sourceUrl TEXT NOT NULL,
        pageUrl TEXT,
        pageTitle TEXT,
        fileName TEXT NOT NULL,
        mimeType TEXT,
        totalBytes INTEGER,
        receivedBytes INTEGER NOT NULL,
        progress INTEGER NOT NULL,
        state TEXT NOT NULL,
        filePath TEXT,
        errorCode TEXT,
        errorMessage TEXT,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        completedAt INTEGER,
        canResume INTEGER NOT NULL,
        canRetry INTEGER NOT NULL
      );
    `;

    try {
      await this.rdbStore.executeSql(createTableSql);
      await this.createIndexes();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create downloads table: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async createIndexes(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    try {
      const createdAtIndexSql =
        `CREATE INDEX IF NOT EXISTS idx_download_tasks_created_at ON ${this.TABLE_NAME}(createdAt DESC);`;
      const updatedAtIndexSql =
        `CREATE INDEX IF NOT EXISTS idx_download_tasks_updated_at ON ${this.TABLE_NAME}(updatedAt DESC);`;
      const stateIndexSql =
        `CREATE INDEX IF NOT EXISTS idx_download_tasks_state ON ${this.TABLE_NAME}(state);`;
      await this.rdbStore.executeSql(createdAtIndexSql);
      await this.rdbStore.executeSql(updatedAtIndexSql);
      await this.rdbStore.executeSql(stateIndexSql);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create download indexes: ${errorMessage}`);
    }
  }

  private async loadTasksFromStore(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      resultSet = await this.rdbStore.query(predicates);
      const tasks = this.resultSetToTasks(resultSet);
      tasks.forEach((task: DownloadTask) => {
        this.items.set(task.id, task);
      });
      this.notify();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to load download tasks: ${errorMessage}`);
    } finally {
      if (resultSet) {
        this.closeResultSetSafely(resultSet);
      }
    }
  }

  private persistTask(task: DownloadTask): void {
    if (task.isPrivate) {
      return;
    }
    const snapshot = cloneDownloadTask(task);
    if (!this.rdbStore) {
      if (this.initPromise) {
        this.queuedPersistence.set(task.id, snapshot);
      }
      return;
    }
    this.enqueuePersistence(() => this.persistTaskInternal(snapshot)).catch((error: Object) => {
      console.error(`Failed to persist download task: ${String(error)}`);
    });
  }

  private async flushQueuedPersistence(): Promise<void> {
    if (!this.rdbStore || this.queuedPersistence.size === 0) {
      return;
    }
    const snapshots: DownloadTask[] = [];
    this.queuedPersistence.forEach((task: DownloadTask) => snapshots.push(task));
    this.queuedPersistence.clear();
    await this.persistenceTail;
    for (let index = 0; index < snapshots.length; index++) {
      await this.persistTaskInternal(snapshots[index]);
    }
  }

  private async persistTaskInternal(task: DownloadTask): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('id', task.id);
      resultSet = await this.rdbStore.query(predicates, ['id']);
      const valuesBucket = this.taskToValuesBucket(task);
      if (resultSet.rowCount > 0) {
        const updatePredicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
        updatePredicates.equalTo('id', task.id);
        await this.rdbStore.update(valuesBucket, updatePredicates);
      } else {
        await this.rdbStore.insert(this.TABLE_NAME, valuesBucket);
      }
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to persist download task: ${errorMessage}`);
    } finally {
      if (resultSet) {
        this.closeResultSetSafely(resultSet);
      }
    }
  }

  private deletePersistedTask(id: string): void {
    if (!this.rdbStore) {
      return;
    }
    this.deletePersistedTaskAwait(id).catch((error: Object) => {
      console.error(`Failed to delete persisted download task: ${String(error)}`);
    });
  }

  private async deletePersistedTaskAwait(id: string): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
    if (!this.rdbStore) {
      this.queuedPersistence.delete(id);
      return;
    }
    await this.enqueuePersistence(() => this.deletePersistedTaskInternal(id));
  }

  private async deletePersistedTaskInternal(id: string): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
    predicates.equalTo('id', id);
    try {
      await this.rdbStore.delete(predicates);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete persisted download task: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private persistCurrentRegularTasks(): void {
    this.items.forEach((task: DownloadTask) => {
      this.persistTask(task);
    });
  }

  private beginAttempt(id: string): number {
    const nextGeneration = (this.attemptGenerations.get(id) ?? 0) + 1;
    this.attemptGenerations.set(id, nextGeneration);
    return nextGeneration;
  }

  private invalidateAttempt(id: string): void {
    this.beginAttempt(id);
  }

  private forgetAttempt(id: string): void {
    this.attemptGenerations.delete(id);
  }

  private cloneForView(task: DownloadTask): DownloadTask {
    const snapshot = cloneDownloadTask(task);
    const action = this.actionLocks.get(task.id);
    snapshot.actionBusy = action !== undefined;
    snapshot.actionLabel = this.getActionLabel(action);
    return snapshot;
  }

  private getActionLabel(action?: string): string {
    if (action === 'pause') {
      return '正在暂停';
    }
    if (action === 'resume') {
      return '正在继续';
    }
    if (action === 'cancel') {
      return '正在取消';
    }
    if (action === 'retry') {
      return '正在重试';
    }
    if (action === 'remove') {
      return '正在删除';
    }
    return '';
  }

  private beginAction(id: string, action: string): boolean {
    if (!this.items.has(id) || this.actionLocks.has(id)) {
      return false;
    }
    this.actionLocks.set(id, action);
    const task = this.items.get(id);
    if (task) {
      task.actionBusy = true;
      task.actionLabel = this.getActionLabel(action);
    }
    this.notify();
    return true;
  }

  private endAction(id: string, action: string): void {
    if (this.actionLocks.get(id) !== action) {
      return;
    }
    this.actionLocks.delete(id);
    const task = this.items.get(id);
    if (task) {
      task.actionBusy = false;
      task.actionLabel = '';
    }
    this.notify();
  }

  private setActionFailure(id: string, errorCode: string, errorMessage: string, action: string): void {
    const task = this.items.get(id);
    if (!task) {
      this.endAction(id, action);
      return;
    }
    // Keep the latest progress/state from the actual download callbacks. A
    // failed control command must not roll the task back over newer events.
    task.errorCode = errorCode;
    task.errorMessage = errorMessage;
    task.updatedAt = Date.now();
    task.actionBusy = false;
    task.actionLabel = '';
    this.persistTask(task);
    this.endAction(id, action);
  }

  private restoreControlStateAfterFailure(id: string, previous: DownloadTask, errorCode: string,
    errorMessage: string, action: string, optimisticState: DownloadTaskState): void {
    const task = this.items.get(id);
    if (!task) {
      this.endAction(id, action);
      return;
    }
    // A real completion/failure callback is more authoritative than this
    // control command's optimistic state. Only revert if nobody else moved
    // the task out of the optimistic state while the service call was pending.
    if (task.state === optimisticState) {
      task.state = previous.state;
      task.canResume = previous.canResume;
      task.canRetry = previous.canRetry;
    }
    task.errorCode = errorCode;
    task.errorMessage = errorMessage;
    task.updatedAt = Date.now();
    this.persistTask(task);
    this.endAction(id, action);
  }

  private isCurrentAttempt(id: string, generation: number): boolean {
    return this.attemptGenerations.get(id) === generation;
  }

  private enqueuePersistence(operation: () => Promise<void>): Promise<void> {
    const next = this.persistenceTail.then(operation, operation);
    this.persistenceTail = next.catch(() => {
    });
    return next;
  }

  private notify(): void {
    const snapshot = this.getDownloads();
    this.listeners.forEach((listener) => {
      try {
        listener(snapshot);
      } catch (_) {
      }
    });
  }

  private normalizeProgress(progress: number): number {
    if (progress < 0) {
      return 0;
    }
    if (progress > 100) {
      return 100;
    }
    return Math.floor(progress);
  }

  /**
   * Calculates the toolbar ring progress for one logical download batch.
   *
   * When every task exposes a valid size, byte-weighted progress is the most
   * faithful representation of the total data transferred. ArkWeb can report
   * an unknown size (0) while still providing a valid percentage, so mixed or
   * fully-unknown batches use the task percentages instead of silently
   * dropping those tasks from the calculation.
   */
  private calculateAggregateProgress(tasks: DownloadTask[]): number {
    const progressTasks = tasks.filter((task: DownloadTask) =>
      task.state !== 'failed' && task.state !== 'canceled');
    if (progressTasks.length === 0) {
      return 0;
    }

    const allSizesKnown = progressTasks.every((task: DownloadTask) =>
      task.totalBytes !== undefined && task.totalBytes > 0);
    if (allSizesKnown) {
      let totalBytes = 0;
      let weightedReceivedBytes = 0;
      progressTasks.forEach((task: DownloadTask) => {
        const totalBytesForTask = task.totalBytes ?? 0;
        const receivedBytes = Math.min(Math.max(0, task.receivedBytes), totalBytesForTask);
        const progressReceivedBytes = totalBytesForTask * this.normalizeProgress(task.progress) / 100;
        totalBytes += totalBytesForTask;
        // Prefer the larger value when ArkWeb's percentage arrives before its
        // byte counters, while still bounding the result by the task size.
        weightedReceivedBytes += Math.min(totalBytesForTask,
          Math.max(receivedBytes, progressReceivedBytes));
      });
      if (totalBytes > 0) {
        return this.normalizeProgress(Math.floor((weightedReceivedBytes * 100) / totalBytes));
      }
    }

    let totalProgress = 0;
    progressTasks.forEach((task: DownloadTask) => {
      if (task.state === 'completed') {
        totalProgress += 100;
      } else {
        totalProgress += this.normalizeProgress(task.progress);
      }
    });
    return this.normalizeProgress(Math.floor(totalProgress / progressTasks.length));
  }

  private generateId(): string {
    return 'dl_' + Math.random().toString(36).slice(2, 11);
  }

  private taskToValuesBucket(task: DownloadTask): relationalStore.ValuesBucket {
    return {
      id: task.id,
      sourceUrl: task.sourceUrl,
      pageUrl: task.pageUrl ?? '',
      pageTitle: task.pageTitle ?? '',
      fileName: task.fileName,
      mimeType: task.mimeType ?? '',
      totalBytes: task.totalBytes ?? -1,
      receivedBytes: task.receivedBytes,
      progress: task.progress,
      state: task.state,
      filePath: task.filePath ?? '',
      errorCode: task.errorCode ?? '',
      errorMessage: task.errorMessage ?? '',
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      completedAt: task.completedAt ?? -1,
      canResume: task.canResume ? 1 : 0,
      canRetry: task.canRetry ? 1 : 0,
    };
  }

  private resultSetToTasks(resultSet: relationalStore.ResultSet): DownloadTask[] {
    const tasks: DownloadTask[] = [];
    try {
      if (resultSet.rowCount <= 0) {
        return tasks;
      }
      resultSet.goToFirstRow();
      do {
        tasks.push(this.restoreTaskFromResultSet(resultSet));
      } while (resultSet.goToNextRow());
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to convert download tasks resultSet: ${errorMessage}`);
    }
    return tasks;
  }

  private restoreTaskFromResultSet(resultSet: relationalStore.ResultSet): DownloadTask {
    const persistedState = this.readDownloadTaskState(resultSet, 'state');
    const state = isActiveDownloadState(persistedState) ? 'failed' : persistedState;
    const task: DownloadTask = {
      id: this.readStringColumn(resultSet, 'id'),
      sourceUrl: this.readStringColumn(resultSet, 'sourceUrl'),
      pageUrl: this.readOptionalStringColumn(resultSet, 'pageUrl'),
      pageTitle: this.readOptionalStringColumn(resultSet, 'pageTitle'),
      fileName: this.readStringColumn(resultSet, 'fileName'),
      mimeType: this.readOptionalStringColumn(resultSet, 'mimeType'),
      isPrivate: false,
      totalBytes: this.readOptionalLongColumn(resultSet, 'totalBytes'),
      receivedBytes: this.readLongColumn(resultSet, 'receivedBytes'),
      progress: this.normalizeProgress(this.readLongColumn(resultSet, 'progress')),
      state: state,
      filePath: this.readOptionalStringColumn(resultSet, 'filePath'),
      errorCode: this.readOptionalStringColumn(resultSet, 'errorCode'),
      errorMessage: this.readOptionalStringColumn(resultSet, 'errorMessage'),
      createdAt: this.readLongColumn(resultSet, 'createdAt'),
      updatedAt: this.readLongColumn(resultSet, 'updatedAt'),
      completedAt: this.readOptionalLongColumn(resultSet, 'completedAt'),
      canResume: this.readBooleanColumn(resultSet, 'canResume'),
      canRetry: this.readBooleanColumn(resultSet, 'canRetry'),
    };

    if (isActiveDownloadState(persistedState)) {
      task.errorCode = 'interrupted';
      task.errorMessage = '应用重启后下载已中断';
      task.canResume = false;
      task.canRetry = true;
      task.updatedAt = Date.now();
      this.persistTask(task);
    }

    return task;
  }

  private readDownloadTaskState(resultSet: relationalStore.ResultSet, columnName: string): DownloadTaskState {
    const value = this.readStringColumn(resultSet, columnName);
    if (value === 'created' || value === 'pending' || value === 'downloading' || value === 'paused' ||
      value === 'completed' || value === 'failed' || value === 'canceled') {
      return value;
    }
    return 'failed';
  }

  private readStringColumn(resultSet: relationalStore.ResultSet, columnName: string): string {
    try {
      const columnIndex = resultSet.getColumnIndex(columnName);
      return resultSet.getString(columnIndex);
    } catch (_) {
      return '';
    }
  }

  private readOptionalStringColumn(resultSet: relationalStore.ResultSet, columnName: string): string | undefined {
    const value = this.readStringColumn(resultSet, columnName).trim();
    return value.length > 0 ? value : undefined;
  }

  private readLongColumn(resultSet: relationalStore.ResultSet, columnName: string): number {
    try {
      const columnIndex = resultSet.getColumnIndex(columnName);
      return resultSet.getLong(columnIndex);
    } catch (_) {
      return 0;
    }
  }

  private readOptionalLongColumn(resultSet: relationalStore.ResultSet, columnName: string): number | undefined {
    const value = this.readLongColumn(resultSet, columnName);
    return value >= 0 ? value : undefined;
  }

  private readBooleanColumn(resultSet: relationalStore.ResultSet, columnName: string): boolean {
    return this.readLongColumn(resultSet, columnName) === 1;
  }

  private closeResultSetSafely(resultSet: relationalStore.ResultSet): void {
    try {
      resultSet.close();
    } catch (_) {
    }
  }
}
