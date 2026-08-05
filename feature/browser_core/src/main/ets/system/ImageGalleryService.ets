import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { dataSharePredicates } from '@kit.ArkData'
import { common, Want } from '@kit.AbilityKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserUtils } from 'common'
import { GalleryPermissionHelper } from '../security/GalleryPermissionHelper'

/** 将网页图片写入系统相册（MediaLibraryKit） */
export class ImageGalleryService {
  private static instance: ImageGalleryService | null = null

  static getInstance(): ImageGalleryService {
    if (ImageGalleryService.instance === null) {
      ImageGalleryService.instance = new ImageGalleryService()
    }
    return ImageGalleryService.instance
  }

  /** 从 URL / data URL 下载并保存到相册 */
  async saveImageFromUrl(sourceUrl: string, title?: string): Promise<boolean> {
    const trimmed = sourceUrl.trim()
    if (!trimmed) {
      return false
    }
    try {
      const buffer = await this.loadImageBytes(trimmed)
      if (!buffer) {
        return false
      }
      const ext = trimmed.startsWith('data:') ?
        this.extensionFromDataUrl(trimmed) :
        this.extensionFromFileName(BrowserUtils.deriveDownloadFileName(trimmed, 'photo.jpg'))
      await this.saveBufferToGallery(buffer, ext, title)
      return true
    } catch (err) {
      BrowserLog.error(`saveImageFromUrl failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 拉取网页图片二进制（data URL / http(s)） */
  async loadImageBytes(sourceUrl: string): Promise<ArrayBuffer | null> {
    const trimmed = sourceUrl.trim()
    if (!trimmed) {
      return null
    }
    try {
      if (trimmed.startsWith('data:')) {
        return this.decodeDataUrl(trimmed)
      }
      if (BrowserUtils.isDirectDownloadUrl(trimmed)) {
        return await this.fetchHttpImage(trimmed)
      }
      return null
    } catch (err) {
      BrowserLog.error(`loadImageBytes failed url=${trimmed.slice(0, 80)}: ${JSON.stringify(err)}`)
      return null
    }
  }

  /**
   * 将已下载的本地图片写入系统图库，返回图库资源 URI。
   */
  async saveFileToGalleryReturningUri(localPath: string, title?: string): Promise<string | null> {
    if (!localPath || !this.fileExists(localPath)) {
      BrowserLog.warn(`saveFileToGallery missing file path=${localPath}`)
      return null
    }
    const fileName = title ?? localPath
    const ext = this.extensionFromFileName(fileName)
    try {
      const buffer = ImageGalleryService.readFileBuffer(localPath)
      if (!buffer || buffer.byteLength === 0) {
        BrowserLog.warn(`saveFileToGallery empty buffer path=${localPath}`)
        return null
      }
      BrowserLog.info(`saveFileToGallery buffer path=${localPath} bytes=${buffer.byteLength} ext=${ext}`)
      return await this.saveBufferToGallery(buffer, ext, fileName)
    } catch (err) {
      BrowserLog.warn(`saveFileToGallery buffer failed path=${localPath}: ${JSON.stringify(err)}, try createAsset`)
      try {
        return await this.saveFileViaCreateAssetReturningUri(localPath, fileName)
      } catch (fallbackErr) {
        BrowserLog.error(`saveFileToGallery failed path=${localPath}: ${JSON.stringify(fallbackErr)}`)
        return null
      }
    }
  }

  /** 将已下载的本地图片写入系统相册 */
  async saveFileToGallery(localPath: string, title?: string): Promise<boolean> {
    const uri = await this.saveFileToGalleryReturningUri(localPath, title)
    return uri !== null && uri.length > 0
  }

  /** 删除图库中的图片资源（移入系统回收站） */
  async deleteGalleryAsset(assetUri: string): Promise<boolean> {
    const uri = assetUri.trim()
    if (uri.length === 0) {
      return false
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return false
    }
    const granted = await GalleryPermissionHelper.ensureWriteImagePermission()
    if (!granted) {
      BrowserLog.warn(`deleteGalleryAsset no permission uri=${uri}`)
      return false
    }
    try {
      await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(ctx, [uri])
      BrowserLog.info(`deleteGalleryAsset ok uri=${uri}`)
      return true
    } catch (err) {
      BrowserLog.warn(`deleteGalleryAsset failed uri=${uri}: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 通过媒体库索引检测图库资源是否仍存在（用户从图库删除后 fileIo 仍可能可读） */
  async queryGalleryAssetExists(assetUri: string): Promise<boolean> {
    const uri = assetUri.trim()
    if (uri.length === 0) {
      return false
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserLog.warn(`[GalleryCheck] no context uri=${uri}`)
      return false
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(ctx)
      const predicates = new dataSharePredicates.DataSharePredicates()
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri)
      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [photoAccessHelper.PhotoKeys.URI],
        predicates: predicates
      }
      const fetchResult = await helper.getAssets(fetchOptions)
      try {
        const count = fetchResult.getCount()
        BrowserLog.info(`[GalleryCheck] exists uri=${uri} count=${count}`)
        return count > 0
      } finally {
        fetchResult.close()
      }
    } catch (err) {
      BrowserLog.warn(`[GalleryCheck] query failed uri=${uri}: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 打开图库图片；资源不存在时返回 false（避免拉起图库黑屏） */
  async openGalleryAsset(assetUri: string, mimeType: string = 'image/*'): Promise<boolean> {
    const uri = assetUri.trim()
    if (uri.length === 0) {
      return false
    }
    const exists = await this.queryGalleryAssetExists(uri)
    if (!exists) {
      BrowserLog.warn(`[GalleryCheck] open blocked missing uri=${uri}`)
      return false
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return false
    }
    const type = mimeType.includes('/') ? mimeType : BrowserUtils.inferMimeType(uri)
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: type
      }
      await ctx.startAbility(want)
      BrowserLog.info(`[GalleryCheck] open ok uri=${uri}`)
      return true
    } catch (err) {
      BrowserLog.warn(`[GalleryCheck] open failed uri=${uri}: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** createAsset + fileIo 写入（buffer 路径失败时的兜底） */
  private async saveFileViaCreateAssetReturningUri(localPath: string, title?: string): Promise<string | null> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return null
    }
    const granted = await GalleryPermissionHelper.ensureWriteImagePermission()
    if (!granted) {
      return null
    }
    const buffer = ImageGalleryService.readFileBuffer(localPath)
    const ext = this.extensionFromFileName(title ?? localPath)
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx)
    const assetUri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext)
    const file = fileIo.openSync(assetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
    try {
      fileIo.writeSync(file.fd, buffer)
    } finally {
      fileIo.closeSync(file)
    }
    BrowserLog.info(`saveFileViaCreateAsset ok uri=${assetUri} bytes=${buffer.byteLength}`)
    return assetUri.length > 0 ? assetUri : null
  }

  private static readFileBuffer(path: string): ArrayBuffer {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(path)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      return buffer
    } finally {
      fileIo.closeSync(file)
    }
  }

  private async saveBufferToGallery(data: ArrayBuffer, extension: string, title?: string): Promise<string> {
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      throw new Error('no context')
    }
    const granted = await GalleryPermissionHelper.ensureWriteImagePermission()
    if (!granted) {
      throw new Error('no gallery permission')
    }
    const ext = extension.replace(/^\./, '') || 'jpg'
    const safeTitle = ImageGalleryService.sanitizeGalleryTitle(title ?? 'browser_image')
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx)
    const options: photoAccessHelper.CreateOptions = { title: safeTitle }
    const changeRequest = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
      ctx,
      photoAccessHelper.PhotoType.IMAGE,
      ext,
      options
    )
    changeRequest.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, data)
    BrowserLog.info(`saveBufferToGallery applyChanges title=${safeTitle} ext=${ext} bytes=${data.byteLength}`)
    await helper.applyChanges(changeRequest)
    const assetUri = changeRequest.getAsset()?.uri ?? ''
    if (assetUri.length === 0) {
      throw new Error('applyChanges returned empty asset')
    }
    BrowserLog.info(`saveBufferToGallery ok assetUri=${assetUri}`)
    return assetUri
  }

  /** 相册 title 不能含扩展名或非法字符（否则 14000001） */
  private static sanitizeGalleryTitle(raw: string, fallback: string = 'browser_image'): string {
    let name = raw.trim()
    const slash = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'))
    if (slash >= 0) {
      name = name.substring(slash + 1)
    }
    const dot = name.lastIndexOf('.')
    if (dot > 0) {
      name = name.substring(0, dot)
    }
    name = name.replace(/[/\\?%*:|"<>]/g, '_').trim()
    if (name.length === 0) {
      return fallback
    }
    return name.slice(0, 64)
  }

  private async fetchHttpImage(url: string): Promise<ArrayBuffer> {
    const httpRequest = http.createHttp()
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 30000,
      readTimeout: 60000
    }
    try {
      const response = await httpRequest.request(url, options)
      if (response.responseCode !== 200) {
        throw new Error(`http ${response.responseCode}`)
      }
      const buffer = response.result as ArrayBuffer
      if (!buffer || buffer.byteLength === 0) {
        throw new Error('empty body')
      }
      return buffer
    } finally {
      httpRequest.destroy()
    }
  }

  private decodeDataUrl(dataUrl: string): ArrayBuffer {
    const commaIdx = dataUrl.indexOf(',')
    if (commaIdx < 0) {
      throw new Error('invalid data url')
    }
    const header = dataUrl.substring(0, commaIdx)
    const payload = dataUrl.substring(commaIdx + 1)
    if (header.includes(';base64')) {
      const helper = new util.Base64Helper()
      const bytes = helper.decodeSync(payload)
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    }
    const text = decodeURIComponent(payload)
    const bytes = new Uint8Array(text.length)
    for (let i = 0; i < text.length; i++) {
      bytes[i] = text.charCodeAt(i)
    }
    return bytes.buffer.slice(0, bytes.byteLength)
  }

  private extensionFromDataUrl(dataUrl: string): string {
    const header = dataUrl.substring(0, dataUrl.indexOf(','))
    if (/image\/png/i.test(header)) {
      return 'png'
    }
    if (/image\/gif/i.test(header)) {
      return 'gif'
    }
    if (/image\/webp/i.test(header)) {
      return 'webp'
    }
    return 'jpg'
  }

  private extensionFromFileName(name: string): string {
    const lower = name.toLowerCase()
    if (lower.endsWith('.png')) {
      return 'png'
    }
    if (lower.endsWith('.gif')) {
      return 'gif'
    }
    if (lower.endsWith('.webp')) {
      return 'webp'
    }
    if (lower.endsWith('.bmp')) {
      return 'bmp'
    }
    return 'jpg'
  }

  /** 下载图片到缓存目录，供系统分享等 URI 场景使用 */
  async writeImageToShareCache(sourceUrl: string): Promise<string | null> {
    const trimmed = sourceUrl.trim()
    if (!trimmed) {
      return null
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      return null
    }
    try {
      const buffer = await this.loadImageBytes(trimmed)
      if (!buffer || buffer.byteLength === 0) {
        return null
      }
      const ext = trimmed.startsWith('data:') ?
        this.extensionFromDataUrl(trimmed) :
        this.extensionFromFileName(BrowserUtils.deriveDownloadFileName(trimmed, 'photo.jpg'))
      const dir = `${ctx.cacheDir}/share`
      ImageGalleryService.ensureDirectory(dir)
      const path = `${dir}/img_${Date.now()}.${ext}`
      ImageGalleryService.writeBufferToPath(path, buffer)
      BrowserLog.info(`writeImageToShareCache ok path=${path} bytes=${buffer.byteLength}`)
      return path
    } catch (err) {
      BrowserLog.error(`writeImageToShareCache failed: ${JSON.stringify(err)}`)
      return null
    }
  }

  private static ensureDirectory(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir)
      }
    } catch (_err) {
      try {
        fileIo.mkdirSync(dir)
      } catch (_mkdirErr) {
        // 目录已存在或创建失败由后续写文件暴露
      }
    }
  }

  private static writeBufferToPath(path: string, data: ArrayBuffer): void {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, data)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (_err) {
      return false
    }
  }
}
