import { common } from '@kit.AbilityKit'
import { image } from '@kit.ImageKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserUtils } from 'common'

/** 浏览历史站点图标：Web favicon 落盘 + 列表展示 URI 解析 */
export class HistorySiteIconService {
  private static readonly ICON_SIZE: number = 32
  /** 过小尺寸（如 Web 回传 1x1 占位图）不落盘，避免历史列表出现空白色块 */
  private static readonly MIN_ICON_SIDE: number = 8
  /** 过小 PNG（约 1x1）判定为无效缓存，展示时回退 worldclock */
  private static readonly MIN_ICON_FILE_BYTES: number = 128
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
      if (!(await this.isUsableIconPixelMap(pixelMap))) {
        BrowserLog.warn(`[HistoryIcon] skip tiny/blank favicon site=${siteKey}`)
        return null
      }
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
      if (!HistorySiteIconService.isIconFileLargeEnough(tmpPath)) {
        BrowserLog.warn(`[HistoryIcon] skip undersized packed favicon site=${siteKey}`)
        try {
          fileIo.unlinkSync(tmpPath)
        } catch (_e) {
        }
        return null
      }
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

  /** 删除指定页面的本地站点图标缓存（用于丢弃串台写入） */
  removeLocalIcon(pageUrl: string): void {
    const siteKey = BrowserUtils.historySiteKey(pageUrl)
    if (!siteKey) {
      return
    }
    const filePath = `${this.iconDir()}/${this.fileNameForSite(siteKey)}`
    try {
      if (fileIo.accessSync(filePath)) {
        fileIo.unlinkSync(filePath)
      }
    } catch (err) {
      BrowserLog.warn(`[HistoryIcon] removeLocalIcon failed site=${siteKey}: ${JSON.stringify(err)}`)
    }
  }

  /** 列表展示 URI：仅本地缓存（远程易在列表复用时串台，不再用于行内展示） */
  resolveDisplayUri(storedIconUrl: string, pageUrl: string): string {
    return this.resolveLocalIconForPage(storedIconUrl, pageUrl)
  }

  /** 解析并校验归属当前页面的本地图标；错绑站点则丢弃。
   * allowSiteFileFallback：无可靠 iconUrl 时是否按站点文件名兜底（历史列表勿开）。 */
  resolveLocalIconForPage(storedIconUrl: string, pageUrl: string, allowSiteFileFallback: boolean = false): string {
    const siteKey = BrowserUtils.historySiteKey(pageUrl)
    if (!siteKey) {
      return ''
    }
    const fromStored = this.resolveLocalDisplayUri(storedIconUrl, siteKey)
    if (fromStored.length > 0) {
      return fromStored
    }
    if (allowSiteFileFallback) {
      return this.resolveLocalByPageUrl(pageUrl)
    }
    return ''
  }

  /** 仅解析本地已缓存 favicon；可选校验必须属于指定站点 */
  resolveLocalDisplayUri(storedIconUrl: string, expectedSiteKey: string = ''): string {
    const local = storedIconUrl.trim()
    if (local.length === 0 || !this.isLocalIconReadable(local)) {
      return ''
    }
    if (expectedSiteKey.length > 0 && !this.pathBelongsToSite(local, expectedSiteKey)) {
      BrowserLog.warn(`[HistoryIcon] drop mismatched iconUrl site=${expectedSiteKey} path=${local.slice(-48)}`)
      return ''
    }
    return HistorySiteIconService.toDisplayUri(local)
  }

  /** 路径文件名是否对应当前站点缓存 */
  private pathBelongsToSite(path: string, siteKey: string): boolean {
    if (!siteKey) {
      return false
    }
    const expected = this.fileNameForSite(siteKey).toLowerCase()
    const normalized = path.replace(/\\/g, '/').toLowerCase()
    const slash = normalized.lastIndexOf('/')
    const name = slash >= 0 ? normalized.substring(slash + 1) : normalized
    return name === expected || name.startsWith(`${expected}.`)
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
      if (!fileIo.accessSync(localPath)) {
        return false
      }
      return HistorySiteIconService.isIconFileLargeEnough(localPath)
    } catch (_err) {
      return false
    }
  }

  private static isIconFileLargeEnough(path: string): boolean {
    try {
      const stat = fileIo.statSync(path)
      return stat.size >= HistorySiteIconService.MIN_ICON_FILE_BYTES
    } catch (_err) {
      return false
    }
  }

  private async isUsableIconPixelMap(pixelMap: image.PixelMap): Promise<boolean> {
    try {
      const info = await pixelMap.getImageInfo()
      const width = info.size.width
      const height = info.size.height
      return width >= HistorySiteIconService.MIN_ICON_SIDE &&
        height >= HistorySiteIconService.MIN_ICON_SIDE
    } catch (err) {
      BrowserLog.warn(`[HistoryIcon] inspect favicon failed: ${JSON.stringify(err)}`)
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
