/** Web 页 JavaScript 桥：供注入脚本调用原生能力 */
import { WebMicCaptureService } from 'browser_core'

export class WebBrowseJsBridge {
  private readonly onOpenImagePreview: (url: string) => void

  constructor(onOpenImagePreview: (url: string) => void) {
    this.onOpenImagePreview = onOpenImagePreview
  }

  /** 网页内点击图片时打开全屏预览 */
  openImagePreview(url: string): void {
    const src = (url ?? '').trim()
    if (src.length > 0) {
      this.onOpenImagePreview(src)
    }
  }

  /**
   * 启动原生麦克风旁路（绕过 ArkWeb audioBus 缺陷）。
   * @param origin 页面 origin，用于站点权限判定
   */
  startNativeMic(origin: string): string {
    return WebMicCaptureService.getInstance().start((origin ?? '').trim())
  }

  /** 停止原生麦克风旁路 */
  stopNativeMic(): string {
    WebMicCaptureService.getInstance().stop()
    return 'idle'
  }

  /** idle | starting | ready | error:... */
  getNativeMicState(): string {
    return WebMicCaptureService.getInstance().getState()
  }

  /**
   * 拉取 PCM Base64（S16LE mono 48kHz）。
   * @param maxBytes 最大字节数（字符串形式，JSBridge 传参兼容）
   */
  pullMicPcm(maxBytes: string): string {
    const n = Number.parseInt(maxBytes, 10)
    const limit = Number.isFinite(n) && n > 0 ? n : 4096
    return WebMicCaptureService.getInstance().pullPcmBase64(limit)
  }
}
