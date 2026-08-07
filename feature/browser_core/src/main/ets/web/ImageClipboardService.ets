import { pasteboard } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { util } from '@kit.ArkTS'
import { BrowserLog } from 'common'
import { BrowserUtils } from 'common'
import { ImageGalleryService } from '../system/ImageGalleryService'

/**
 * 网页图片剪贴板：PixelMap + text/html(Base64) 双轨写入（备忘录等文档 App）。
 * 禁止 setUnifiedData（本机 libudmf CFI 崩溃）。
 */
export class ImageClipboardService {
  private static instance: ImageClipboardService | null = null
  private static readonly LOG_TAG: string = '[CopyImage]'
  /** 保持 PixelMap 存活，避免 setData 后立即 release */
  private heldClipboardPixelMap: image.PixelMap | null = null

  static getInstance(): ImageClipboardService {
    if (ImageClipboardService.instance === null) {
      ImageClipboardService.instance = new ImageClipboardService()
    }
    return ImageClipboardService.instance
  }

  /** 下载图片 → PixelMap + HTML(Base64) → 写入系统剪贴板 */
  async copyImageFromUrl(sourceUrl: string): Promise<boolean> {
    const trimmed = sourceUrl.trim()
    if (!trimmed) {
      return false
    }
    let imageSource: image.ImageSource | null = null
    try {
      const buffer = await ImageGalleryService.getInstance().loadImageBytes(trimmed)
      if (!buffer || buffer.byteLength === 0) {
        BrowserLog.warn(`${ImageClipboardService.LOG_TAG} empty buffer`)
        return false
      }

      imageSource = image.createImageSource(buffer)
      const pixelMap = await imageSource.createPixelMap({
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      })
      const info = pixelMap.getImageInfoSync()
      if (info.size.width <= 0 || info.size.height <= 0) {
        pixelMap.release()
        return false
      }

      const mimeType = BrowserUtils.inferImageMimeFromUrl(trimmed)
      const base64 = ImageClipboardService.toBase64Payload(trimmed, buffer)
      if (!base64) {
        pixelMap.release()
        BrowserLog.warn(`${ImageClipboardService.LOG_TAG} base64 failed`)
        return false
      }

      const html = ImageClipboardService.buildHtmlFragment(
        base64,
        mimeType,
        info.size.width,
        info.size.height,
      )
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap)
      pasteData.addRecord(pasteboard.MIMETYPE_TEXT_HTML, html)
      await pasteboard.getSystemPasteboard().setData(pasteData)
      ImageClipboardService.replaceHeldPixelMap(this, pixelMap)
      BrowserLog.info(`${ImageClipboardService.LOG_TAG} ok ${info.size.width}x${info.size.height} mime=${mimeType}`)
      return true
    } catch (err) {
      BrowserLog.error(`${ImageClipboardService.LOG_TAG} failed: ${JSON.stringify(err)}`)
      return false
    } finally {
      try {
        imageSource?.release()
      } catch (_releaseErr) {
        // 忽略
      }
    }
  }

  /** data URL 直接取 Base64 载荷，否则对原始字节编码 */
  private static toBase64Payload(sourceUrl: string, buffer: ArrayBuffer): string {
    if (sourceUrl.startsWith('data:')) {
      const commaIdx = sourceUrl.indexOf(',')
      if (commaIdx < 0) {
        return ''
      }
      const header = sourceUrl.substring(0, commaIdx)
      if (header.includes(';base64')) {
        return sourceUrl.substring(commaIdx + 1)
      }
    }
    try {
      const helper = new util.Base64Helper()
      return helper.encodeToStringSync(new Uint8Array(buffer))
    } catch (err) {
      BrowserLog.warn(`${ImageClipboardService.LOG_TAG} encode err: ${JSON.stringify(err)}`)
      return ''
    }
  }

  /** CF_HTML 风格片段，供备忘录等文档 App 解析内嵌图片 */
  private static buildHtmlFragment(
    base64: string,
    mimeType: string,
    width: number,
    height: number,
  ): string {
    return '<html><body><!--StartFragment-->' +
      `<img src="data:${mimeType};base64,${base64}" width="${width}" height="${height}"/>` +
      '<!--EndFragment--></body></html>'
  }

  private static replaceHeldPixelMap(service: ImageClipboardService, pixelMap: image.PixelMap): void {
    const previous = service.heldClipboardPixelMap
    service.heldClipboardPixelMap = pixelMap
    if (previous !== null && previous !== pixelMap) {
      try {
        previous.release()
      } catch (_releaseErr) {
        // 忽略
      }
    }
  }
}
