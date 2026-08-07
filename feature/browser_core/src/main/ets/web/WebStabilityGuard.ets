import { BrowserLog } from 'common'

/**
 * 系统稳定性防护：在页面切换/后台时短暂抑制 Web 截图等 GPU 重操作，
 * 降低 render_service 阻塞导致整机重启的风险。
 */
export class WebStabilityGuard {
  private static gpuSuspendUntilMs: number = 0
  private static lastWebSnapshotMs: number = 0
  /** 两次 Web 截图最小间隔（ms） */
  private static readonly MIN_WEB_SNAPSHOT_GAP_MS: number = 2800

  /** 在一段时间内跳过新的 GPU 重操作（标签截图、组件快照等） */
  static suspendGpuHeavyWork(durationMs: number): void {
    const until = Date.now() + Math.max(0, durationMs)
    if (until > WebStabilityGuard.gpuSuspendUntilMs) {
      WebStabilityGuard.gpuSuspendUntilMs = until
      BrowserLog.info(`[WebStability] suspendGpuHeavyWork ${durationMs}ms`)
    }
  }

  static isGpuHeavyWorkSuspended(): boolean {
    return Date.now() < WebStabilityGuard.gpuSuspendUntilMs
  }

  /** Web 页截图节流：距上次截图过近则跳过 */
  static tryAcquireWebSnapshot(): boolean {
    if (WebStabilityGuard.isGpuHeavyWorkSuspended()) {
      BrowserLog.info('[WebStability] skip web snapshot reason=suspended')
      return false
    }
    const now = Date.now()
    const elapsed = now - WebStabilityGuard.lastWebSnapshotMs
    if (WebStabilityGuard.lastWebSnapshotMs > 0 &&
      elapsed < WebStabilityGuard.MIN_WEB_SNAPSHOT_GAP_MS) {
      BrowserLog.info(`[WebStability] skip web snapshot reason=gap elapsed=${elapsed}ms`)
      return false
    }
    WebStabilityGuard.lastWebSnapshotMs = now
    return true
  }
}
