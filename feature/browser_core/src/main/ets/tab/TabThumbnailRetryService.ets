import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { TabSession } from 'common'
import { TabThumbnailService } from './TabThumbnailService'
import { WebStabilityGuard } from '../web/WebStabilityGuard'

/** 缩略图抓取失败后的后台重试（退避调度，成功后由 BrowserStore 刷新页签管理 UI） */
export class TabThumbnailRetryService {
  private static instance: TabThumbnailRetryService | null = null
  /** 首页 MainPage 截图组件 id */
  static readonly MAIN_PAGE_SNAPSHOT_ID: string = 'main_page_thumb_root'

  private readonly maxAttempts: number = 8
  private readonly backoffMs: number[] = [1200, 2000, 3500, 5000, 8000, 12000, 18000, 25000]
  private queue: Map<string, TabThumbRetryEntry> = new Map()
  private timerId: number = -1
  private ticking: boolean = false
  private webReadyTabId: string = ''

  static getInstance(): TabThumbnailRetryService {
    if (TabThumbnailRetryService.instance === null) {
      TabThumbnailRetryService.instance = new TabThumbnailRetryService()
    }
    return TabThumbnailRetryService.instance
  }

  start(): void {
    if (this.timerId >= 0) {
      return
    }
    this.timerId = setInterval(() => {
      void this.tick()
    }, 5000) as number
    BrowserLog.info('[TabThumbnailRetry] worker started')
  }

  /** 停止后台重试定时器，释放队列 */
  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    this.queue.clear()
    this.ticking = false
    this.webReadyTabId = ''
    BrowserLog.info('[TabThumbnailRetry] worker stopped')
  }

  notifyWebReady(tabId: string): void {
    if (!tabId) {
      return
    }
    this.webReadyTabId = tabId
    const entry = this.queue.get(tabId)
    if (entry !== undefined) {
      entry.nextAt = Date.now()
      BrowserLog.info(`[TabThumbnailRetry] web ready bump queued tab=${tabId}`)
      void this.kickCapture(tabId, entry.kind)
      return
    }
    void BrowserStore.whenReady().then(async () => {
      const tab = BrowserStore.getTabs().find((t) => t.id === tabId)
      if (!tab || tab.isIncognito || tab.isHome === true) {
        return
      }
      if ((tab.thumbnailPath ?? '').length > 0 || (tab.url ?? '').trim().length === 0) {
        return
      }
      this.enqueue(tabId, 'web', true)
      void this.kickCapture(tabId, 'web')
    })
  }

  /** Web 首屏绘制完成后立即尝试一次补抓（不等待 2.5s 定时器） */
  private async kickCapture(tabId: string, kind: TabThumbRetryKind): Promise<void> {
    if (this.ticking) {
      return
    }
    await this.tryCapture(tabId, kind)
  }

  enqueue(tabId: string, kind: TabThumbRetryKind, immediate: boolean = false): void {
    if (!tabId) {
      return
    }
    const existing = this.queue.get(tabId)
    if (existing) {
      existing.kind = kind
      if (immediate) {
        existing.nextAt = Date.now()
      }
      BrowserLog.info(`[TabThumbnailRetry] update tab=${tabId} kind=${kind} attempt=${existing.attempts}`)
      return
    }
    this.queue.set(tabId, {
      tabId,
      kind,
      attempts: 0,
      nextAt: immediate ? Date.now() : Date.now() + this.backoffMs[0]
    })
    BrowserLog.info(`[TabThumbnailRetry] enqueue tab=${tabId} kind=${kind}`)
  }

  cancel(tabId: string): void {
    if (this.queue.delete(tabId)) {
      BrowserLog.info(`[TabThumbnailRetry] cancel tab=${tabId}`)
    }
  }

  enqueueMissing(tabs: TabSession[], limit: number = 8, priorityTabId: string = ''): void {
    let added = 0
    const sorted = tabs.slice().sort((a, b) => a.sortOrder - b.sortOrder)
    const missing: TabSession[] = []
    for (const tab of sorted) {
      if (tab.isIncognito || tab.thumbnailPath) {
        continue
      }
      missing.push(tab)
    }
    if (priorityTabId.length > 0) {
      const priority = missing.find((t) => t.id === priorityTabId)
      if (priority) {
        const kind: TabThumbRetryKind =
          (priority.isHome || !priority.url.trim()) ? 'home' : 'web'
        if (kind === 'home') {
          BrowserLog.info(`[TabThumbnailRetry] skip enqueue home priority tab=${priority.id}`)
        } else {
          this.enqueue(priority.id, kind, true)
          added++
        }
      }
    }
    for (const tab of missing) {
      if (added >= limit) {
        break
      }
      if (tab.id === priorityTabId) {
        continue
      }
      // 非当前 Web 标签无法在页签管理页补抓；主页须离开前抓取，不在此入队
    }
  }

  private async tick(): Promise<void> {
    if (this.ticking || this.queue.size === 0) {
      return
    }
    this.ticking = true
    try {
      const now = Date.now()
      const due = Array.from(this.queue.values()).filter((e) => now >= e.nextAt)
      if (due.length === 0) {
        return
      }
      await this.tryCapture(due[0].tabId, due[0].kind)
    } finally {
      this.ticking = false
    }
  }

  private async tryCapture(tabId: string, kind: TabThumbRetryKind): Promise<void> {
    const entry = this.queue.get(tabId)
    if (!entry) {
      return
    }
    if (kind === 'home') {
      BrowserLog.info(`[TabThumbnailRetry] skip home tab=${tabId} (MainPage off-screen)`)
      this.queue.delete(tabId)
      return
    }
    if (kind === 'web' && TabThumbnailService.getInstance().isBrowsePageForeground()) {
      entry.nextAt = Date.now() + 800
      return
    }
    // 共享 WebView：仅允许补抓「当前已就绪」的页签，避免把 A 的画面写入 B
    if (kind === 'web' && this.webReadyTabId.length > 0 && this.webReadyTabId !== tabId) {
      BrowserLog.info(`[TabThumbnailRetry] skip non-ready tab=${tabId} ready=${this.webReadyTabId}`)
      entry.nextAt = Date.now() + 2500
      return
    }
    if (WebStabilityGuard.isGpuHeavyWorkSuspended()) {
      entry.nextAt = Date.now() + 1200
      return
    }
    BrowserLog.info(`[TabThumbnailRetry] attempt tab=${tabId} kind=${kind} n=${entry.attempts + 1}`)
    const thumbSvc = TabThumbnailService.getInstance()
    thumbSvc.beginCaptureWindow()
    let ok = false
    try {
      ok = await BrowserStore.captureTabThumbnail(tabId)
    } finally {
      thumbSvc.endCaptureWindow()
    }
    if (ok) {
      this.cancel(tabId)
      return
    }
    entry.attempts++
    if (entry.attempts >= this.maxAttempts) {
      BrowserLog.warn(`[TabThumbnailRetry] give up tab=${tabId} kind=${kind}`)
      this.queue.delete(tabId)
      return
    }
    const delay = this.backoffMs[Math.min(entry.attempts, this.backoffMs.length - 1)]
    entry.nextAt = Date.now() + delay
    BrowserLog.info(`[TabThumbnailRetry] reschedule tab=${tabId} in=${delay}ms`)
  }
}

type TabThumbRetryKind = 'web' | 'home'

interface TabThumbRetryEntry {
  tabId: string
  kind: TabThumbRetryKind
  attempts: number
  nextAt: number
}
