import { BrowserUtils } from 'common'
import { BrowserLog } from 'common'
import { AppStorageKeys } from 'common'

/** 浏览页面前进/后退导航栈控制 */
export class NavigationController {
  private static instance: NavigationController | null = null

  /** 获取 NavigationController 单例 */
  static getInstance(): NavigationController {
    if (NavigationController.instance === null) {
      NavigationController.instance = new NavigationController()
    }
    return NavigationController.instance
  }

  /** 将 URL 压入导航栈并更新当前索引 */
  pushNavStack(url: string): void {
    const normalized = BrowserUtils.normalizeHistoryUrl(url)
    if (!normalized) {
      return
    }
    const stack = AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    const trimmed = stack.slice(0, idx + 1)
    trimmed.push(normalized)
    AppStorage.set(AppStorageKeys.NAV_STACK, trimmed)
    AppStorage.set(AppStorageKeys.NAV_IDX, trimmed.length - 1)
  }

  /** 判断是否可以后退 */
  canBrowseBack(): boolean {
    return (AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0) > 0
  }

  /** 判断是否可以前进 */
  canBrowseForward(): boolean {
    const stack = AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    return idx < stack.length - 1
  }

  /** 后退一步并返回目标 URL */
  browseBack(): string | null {
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    if (idx <= 0) {
      return null
    }
    const next = idx - 1
    AppStorage.set(AppStorageKeys.NAV_IDX, next)
    const stack = AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []
    return stack[next] ?? null
  }

  /** 后退并跳过中转跳转页与重复 URL */
  browseBackSkippingTransit(): string | null {
    const stack = AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []
    let idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    if (idx <= 0 || stack.length === 0) {
      return null
    }
    const current = this.normalizeNavUrl(stack[idx] ?? '')
    while (idx > 0) {
      idx--
      const candidate = this.normalizeNavUrl(stack[idx] ?? '')
      if (candidate.length === 0) {
        continue
      }
      if (BrowserUtils.isNavTransitUrl(candidate)) {
        continue
      }
      if (candidate === current && idx > 0) {
        continue
      }
      AppStorage.set(AppStorageKeys.NAV_IDX, idx)
      BrowserLog.info(`[NavBack] skip-transit idx=${idx} url=${candidate.slice(0, 80)}`)
      return stack[idx] ?? null
    }
    return null
  }

  /** 前进一步并返回目标 URL */
  browseForward(): string | null {
    const stack = AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    if (idx >= stack.length - 1) {
      return null
    }
    const next = idx + 1
    AppStorage.set(AppStorageKeys.NAV_IDX, next)
    return stack[next] ?? null
  }

  /** 重置导航栈为单个 URL */
  resetNavStack(url: string): void {
    const normalized = BrowserUtils.normalizeHistoryUrl(url)
    AppStorage.set(AppStorageKeys.NAV_STACK, normalized.length > 0 ? [normalized] : [])
    AppStorage.set(AppStorageKeys.NAV_IDX, 0)
  }

  /** 用最终 URL 覆盖当前栈帧（中转页重定向 replace，避免再 push 形成回退死循环） */
  replaceNavStackCurrent(url: string): void {
    const normalized = BrowserUtils.normalizeHistoryUrl(url)
    if (!normalized) {
      return
    }
    const stack = (AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []).slice()
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    if (stack.length === 0 || idx < 0 || idx >= stack.length) {
      this.resetNavStack(normalized)
      BrowserLog.info(`[NavSync] replace-reset url=${normalized.slice(0, 80)}`)
      return
    }
    stack[idx] = normalized
    AppStorage.set(AppStorageKeys.NAV_STACK, stack)
    BrowserLog.info(`[NavSync] replace idx=${idx} url=${normalized.slice(0, 80)}`)
  }

  /** 规范化 URL 便于栈内比较 */
  private normalizeNavUrl(url: string): string {
    return BrowserUtils.normalizeHistoryUrl(url)
  }

  private navUrlAt(stack: string[], index: number): string {
    return this.normalizeNavUrl(stack[index] ?? '')
  }

  /**
   * 镜像当前 Web URL 到应用栈（仅 replace/reset）。
   * 华为链路：后退只认 Web backward，应用栈不做 back/forward 对齐，避免假前进/双栈错位。
   */
  syncNavToUrl(url: string): void {
    const normalized = this.normalizeNavUrl(url)
    if (!normalized || !BrowserUtils.isRecordableHistoryUrl(normalized)) {
      BrowserLog.info(`[NavSync] skip url=${url.slice(0, 80)}`)
      return
    }
    const stack = AppStorage.get<string[]>(AppStorageKeys.NAV_STACK) ?? []
    if (stack.length === 0) {
      this.resetNavStack(normalized)
      BrowserLog.info(`[NavSync] reset url=${normalized.slice(0, 80)}`)
      return
    }
    const idx = AppStorage.get<number>(AppStorageKeys.NAV_IDX) ?? 0
    if (this.navUrlAt(stack, idx) === normalized) {
      BrowserLog.info(`[NavSync] same idx=${idx} url=${normalized.slice(0, 80)}`)
      return
    }
    this.replaceNavStackCurrent(normalized)
  }
}
