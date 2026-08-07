import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'BrowserTab'

/** 标签页相关调试日志（hilog 过滤 tag: BrowserTab） */
export class BrowserLog {
  /** 输出 info 级别日志 */
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message)
  }

  /** 输出 warn 级别日志 */
  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message)
  }

  /** 输出 error 级别日志 */
  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message)
  }
}
