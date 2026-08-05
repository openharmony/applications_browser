import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { getBrowserUIContext } from 'common'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { WebPageController } from '../web/WebPageController'
import { WebStabilityGuard } from '../web/WebStabilityGuard'

/**
 * 标签页缩略图：Web 截图仅在离开浏览页时执行（浏览中禁止，避免冻屏）。
 */
export class TabThumbnailService {
  static readonly WEB_SNAPSHOT_ID: string = 'browse_web_view'
  /** 缩略图最大宽度，减小文件体积与解码耗时 */
  private static readonly THUMB_MAX_WIDTH: number = 320
  private static readonly THUMB_JPEG_QUALITY: number = 62
  private static instance: TabThumbnailService | null = null
  private capturing: boolean = false
  private captureInflight: Map<string, Promise<string | null>> = new Map()
  /** 浏览页是否在前台 */
  private browsePageForeground: boolean = false
  /** 进入标签管理前显式开启的短窗口（此时浏览页仍可见但允许截图） */
  private captureWindowOpen: boolean = false

  static getInstance(): TabThumbnailService {
    if (TabThumbnailService.instance === null) {
      TabThumbnailService.instance = new TabThumbnailService()
    }
    return TabThumbnailService.instance
  }

  setBrowsePageForeground(foreground: boolean): void {
    this.browsePageForeground = foreground
  }

  isBrowsePageForeground(): boolean {
    return this.browsePageForeground
  }

  beginCaptureWindow(): void {
    this.captureWindowOpen = true
  }

  endCaptureWindow(): void {
    this.captureWindowOpen = false
  }

  isWebCaptureAllowed(): boolean {
    return this.captureWindowOpen || !this.browsePageForeground
  }

  private thumbDir(): string {
    const ctx = BrowserStore.getContext()
    return `${ctx?.filesDir ?? ''}/tab_thumbnails`
  }

  private ensureDir(): void {
    const dir = this.thumbDir()
    if (!dir) {
      return
    }
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
    } catch (_err) {
      try {
        fileIo.mkdirSync(dir, true)
      } catch (err) {
        BrowserLog.error(`TabThumbnail ensureDir failed: ${JSON.stringify(err)}`)
      }
    }
  }

  async savePixelMap(tabId: string, pixelMap: image.PixelMap): Promise<string | null> {
    const ctx = BrowserStore.getContext()
    if (!ctx || !tabId) {
      return null
    }
    this.ensureDir()
    const filePath = `${this.thumbDir()}/${tabId}.jpg`
    const tmpPath = `${filePath}.tmp`
    let file: fileIo.File | null = null
    let packedMap: image.PixelMap | null = null
    try {
      packedMap = await this.normalizeThumbPixelMap(pixelMap)
      file = fileIo.openSync(tmpPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      const packer = image.createImagePacker()
      const opt: image.PackingOption = {
        format: 'image/jpeg',
        quality: TabThumbnailService.THUMB_JPEG_QUALITY
      }
      await packer.packToFile(packedMap, file.fd, opt)
      fileIo.closeSync(file)
      file = null
      try {
        fileIo.unlinkSync(filePath)
      } catch (_e) {
      }
      fileIo.renameSync(tmpPath, filePath)
      return filePath
    } catch (err) {
      BrowserLog.error(`TabThumbnail save failed: ${JSON.stringify(err)}`)
      return null
    } finally {
      try {
        pixelMap.release()
      } catch (_e) {
      }
      if (packedMap !== null && packedMap !== pixelMap) {
        try {
          packedMap.release()
        } catch (_e) {
        }
      }
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (_e) {
        }
      }
    }
  }

  private async normalizeThumbPixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    try {
      const info = await pixelMap.getImageInfo()
      const width = info.size.width
      if (width <= TabThumbnailService.THUMB_MAX_WIDTH) {
        return pixelMap
      }
      const scale = TabThumbnailService.THUMB_MAX_WIDTH / width
      await pixelMap.scale(scale, scale)
      return pixelMap
    } catch (err) {
      BrowserLog.warn(`TabThumbnail normalize failed: ${JSON.stringify(err)}`)
      return pixelMap
    }
  }

  async captureForTab(tabId: string): Promise<string | null> {
    if (!tabId) {
      return null
    }
    if (!this.isWebCaptureAllowed()) {
      BrowserLog.info(`TabThumbnail skip web tab=${tabId} reason=foreground`)
      return null
    }
    if (!WebStabilityGuard.tryAcquireWebSnapshot()) {
      return null
    }
    const inflight = this.captureInflight.get(tabId)
    if (inflight) {
      return inflight
    }
    const task = this.runCaptureForTab(tabId).finally(() => {
      this.captureInflight.delete(tabId)
    })
    this.captureInflight.set(tabId, task)
    return task
  }

  private async runCaptureForTab(tabId: string): Promise<string | null> {
    const lockAcquired = await this.waitCaptureLock(3000)
    if (!lockAcquired) {
      BrowserLog.warn(`TabThumbnail lock timeout tab=${tabId}`)
      return null
    }
    this.capturing = true
    const fast = this.captureWindowOpen
    const retryDelaysMs: number[] = fast ? [0, 120, 240] : [0, 200, 400]
    const deadline = Date.now() + (fast ? 1800 : 2500)
    try {
      for (let i = 0; i < retryDelaysMs.length; i++) {
        if (Date.now() >= deadline || !this.isWebCaptureAllowed()) {
          break
        }
        if (retryDelaysMs[i] > 0) {
          await this.delay(retryDelaysMs[i])
        }
        const remainMs = Math.max(300, deadline - Date.now())
        const pixelMap = await WebPageController.getInstance().captureSnapshot(remainMs)
        if (!pixelMap) {
          continue
        }
        const path = await this.savePixelMap(tabId, pixelMap)
        if (path) {
          BrowserLog.info(`TabThumbnail web saved tab=${tabId} attempt=${i + 1}`)
          return path
        }
      }
      BrowserLog.warn(`TabThumbnail web exhausted tab=${tabId}`)
      return null
    } finally {
      this.capturing = false
    }
  }

  async captureHomeFromComponent(
    tabId: string,
    componentId: string,
    uiContext?: UIContext | null
  ): Promise<string | null> {
    if (!tabId || !componentId) {
      return null
    }
    const lockAcquired = await this.waitCaptureLock(3000)
    if (!lockAcquired) {
      BrowserLog.warn(`TabThumbnail home lock timeout tab=${tabId}`)
      return null
    }
    this.capturing = true
    try {
      const uiCtx = uiContext ?? getBrowserUIContext()
      if (!uiCtx) {
        BrowserLog.warn(`TabThumbnail home no uiContext tab=${tabId}`)
        return null
      }
      BrowserLog.info(`TabThumbnail home snap tab=${tabId} id=${componentId}`)
      const pixelMap = await uiCtx.getComponentSnapshot().get(componentId, {
        waitUntilRenderFinished: true
      })
      if (!pixelMap) {
        BrowserLog.warn(`TabThumbnail home empty pixelMap tab=${tabId}`)
        return null
      }
      const path = await this.savePixelMap(tabId, pixelMap)
      if (path) {
        BrowserLog.info(`TabThumbnail home saved tab=${tabId}`)
      }
      return path
    } catch (err) {
      BrowserLog.warn(`TabThumbnail home failed tab=${tabId}: ${JSON.stringify(err)}`)
      return null
    } finally {
      this.capturing = false
    }
  }

  private async waitCaptureLock(maxWaitMs: number): Promise<boolean> {
    const deadline = Date.now() + maxWaitMs
    while (this.capturing) {
      if (Date.now() >= deadline) {
        return false
      }
      await this.delay(80)
    }
    return true
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => {
      setTimeout(() => resolve(), ms)
    })
  }

  deleteThumbnail(path: string): void {
    if (!path) {
      return
    }
    try {
      fileIo.unlinkSync(path)
    } catch (_err) {
    }
  }

  static toDisplayUri(path: string): string {
    if (!path) {
      return ''
    }
    if (path.startsWith('file://') || path.startsWith('datashare://')) {
      return path
    }
    try {
      return fileUri.getUriFromPath(path)
    } catch (_err) {
      return `file://${path}`
    }
  }
}
