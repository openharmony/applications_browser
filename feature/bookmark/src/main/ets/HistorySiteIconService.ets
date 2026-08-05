import { common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { BrowserLog } from 'common'
import { BrowserStore } from 'browser_core'
import { BrowserUtils } from 'common'

/** 浏览历史站点图标：Web favicon 落盘 + 列表展示 URI 解析 */
export class HistorySiteIconService {
  private static readonly ICON_SIZE: number = 32
  private static instance: HistorySiteIconService | null = null

  static getInstance(): HistorySiteIconService {
    if (HistorySiteIconService.instance === null) {
      HistorySiteIconService.instance = new HistorySiteIconService()
    }
    return HistorySiteIconService.instance
  }

  /** 保存页面 favicon，返回本地文件路径（调用方移交 PixelMap 所有权，本方法负责 release） */
  async saveFavicon(pageUrl: string, pixelMap: image.PixelMap): Promise<string | null> {
    const siteKey = BrowserUtils.historySiteKey(pageUrl)
    if (!siteKey) {
      HistorySiteIconService.releasePixelMap(pixelMap)
      return null
    }
    const ctx: common.UIAbilityContext | null = BrowserStore.getContext()
    if (!ctx) {
      HistorySiteIconService.releasePixelMap(pixelMap)
      return null
    }
    this.ensureDir()
    const filePath = `${this.iconDir()}/${this.fileNameForSite(siteKey)}`
    const tmpPath = `${filePath}.tmp`
    let file: fileIo.File | null = null
    let packedMap: image.PixelMap | null = null
    try {
      packedMap = await this.normalizeIconPixelMap(pixelMap)
      file = fileIo.openSync(tmpPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      const packer = image.createImagePacker()
      const opt: image.PackingOption = {
        format: 'image/png',
        quality: 100
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
      BrowserLog.warn(`[HistoryIcon] save failed site=${siteKey}: ${JSON.stringify(err)}`)
      try {
        fileIo.unlinkSync(tmpPath)
      } catch (_e) {
      }
      return null
    } finally {
      if (file !== null) {
        try {
          fileIo.closeSync(file)
        } catch (_e) {
        }
      }
      HistorySiteIconService.releasePixelMap(pixelMap)
      if (packedMap !== null && packedMap !== pixelMap) {
        HistorySiteIconService.releasePixelMap(packedMap)
      }
    }
  }

  private static releasePixelMap(pixelMap: image.PixelMap): void {
    try {
      pixelMap.release()
    } catch (_e) {
    }
  }

  /** 列表展示 URI：优先本地缓存，否则远程 favicon */
  resolveDisplayUri(storedIconUrl: string, pageUrl: string): string {
    const localUri = this.resolveLocalDisplayUri(storedIconUrl)
    if (localUri.length > 0) {
      return localUri
    }
    return BrowserUtils.remoteFaviconUrl(pageUrl)
  }

  /** 仅解析本地已缓存 favicon；无缓存时返回空（列表默认图标走 worldclock 兜底） */
  resolveLocalDisplayUri(storedIconUrl: string): string {
    const local = storedIconUrl.trim()
    if (local.length > 0 && this.isLocalIconReadable(local)) {
      return HistorySiteIconService.toDisplayUri(local)
    }
    return ''
  }

  /** 按页面 URL 对应站点缓存解析本地 favicon（标签页卡片无 iconUrl 时用） */
  resolveLocalByPageUrl(pageUrl: string): string {
    const siteKey = BrowserUtils.historySiteKey(pageUrl)
    if (!siteKey) {
      return ''
    }
    const filePath = `${this.iconDir()}/${this.fileNameForSite(siteKey)}`
    if (!this.isLocalIconReadable(filePath)) {
      return ''
    }
    return HistorySiteIconService.toDisplayUri(filePath)
  }

  static toDisplayUri(path: string): string {
    if (!path) {
      return ''
    }
    if (path.startsWith('file://') || path.startsWith('datashare://') ||
      path.startsWith('http://') || path.startsWith('https://')) {
      return path
    }
    try {
      return fileUri.getUriFromPath(path)
    } catch (_err) {
      return path.startsWith('/') ? `file://${path}` : ''
    }
  }

  private iconDir(): string {
    const ctx: common.UIAbilityContext | null = BrowserStore.getContext()
    return `${ctx?.filesDir ?? ''}/history_icons`
  }

  private ensureDir(): void {
    const dir = this.iconDir()
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
        BrowserLog.warn(`[HistoryIcon] ensureDir failed: ${JSON.stringify(err)}`)
      }
    }
  }

  private fileNameForSite(siteKey: string): string {
    return `${siteKey.replace(/[^a-z0-9.-]/gi, '_')}.png`
  }

  private isLocalIconReadable(path: string): boolean {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return false
    }
    const localPath = path.startsWith('file://') ? path.replace('file://', '') : path
    try {
      return fileIo.accessSync(localPath)
    } catch (_err) {
      return false
    }
  }

  private async normalizeIconPixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    try {
      const info = await pixelMap.getImageInfo()
      const width = info.size.width
      const height = info.size.height
      const maxSide = Math.max(width, height)
      if (maxSide <= HistorySiteIconService.ICON_SIZE) {
        return pixelMap
      }
      const scale = HistorySiteIconService.ICON_SIZE / maxSide
      await pixelMap.scale(scale, scale)
      return pixelMap
    } catch (err) {
      BrowserLog.warn(`[HistoryIcon] normalize failed: ${JSON.stringify(err)}`)
      return pixelMap
    }
  }
}
