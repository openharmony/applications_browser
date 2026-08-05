import { fileIo } from '@kit.CoreFileKit'
import Environment from '@ohos.file.environment'
import { BrowserStore } from '../BrowserStore'
import { BrowserLog } from 'common'
import { BrowserUtils } from 'common'
import { AppStorageKeys } from 'common'
import { DownloadTask } from 'common'
import { DownloadPermissionHelper } from './DownloadPermissionHelper'

/** 下载路径：进行中落盘沙箱，完成后发布到文管 Download */
export class DownloadPathService {
  private static instance: DownloadPathService | null = null
  private publicDirCache: string = ''
  private publicDirResolved: boolean = false

  static getInstance(): DownloadPathService {
    if (DownloadPathService.instance === null) {
      DownloadPathService.instance = new DownloadPathService()
    }
    return DownloadPathService.instance
  }

  supportsPublicDownloadDir(): boolean {
    return DownloadPermissionHelper.supportsPublicDownloadDir()
  }

  usesMobileDownloadStrategy(): boolean {
    return DownloadPermissionHelper.usesMobileDownloadStrategy()
  }

  hasPublicDownloadDir(): boolean {
    return this.getPublicDownloadDir() !== null
  }

  /** 文管可见 Download 目录（仅用于完成后发布） */
  getPublicDownloadDir(): string | null {
    if (this.publicDirCache.length > 0) {
      return this.publicDirCache
    }
    if (this.publicDirResolved) {
      return null
    }
    let dir: string | null = null
    if (this.usesMobileDownloadStrategy()) {
      dir = this.resolvePortablePublicDownloadDir()
    } else {
      dir = this.tryEnvironmentDownloadDir()
      if (!dir) {
        dir = this.resolvePortablePublicDownloadDir()
      }
    }
    this.publicDirResolved = true
    if (dir) {
      this.publicDirCache = dir
      BrowserLog.info(`[DownloadPath] public download dir=${dir}`)
    }
    return dir
  }

  /** 下载进行中使用的目录：手机/平板优先沙箱，2in1 有权限时用公共 Download */
  getDownloadDir(): string {
    if (this.usesMobileDownloadStrategy()) {
      return this.getSandboxDownloadDir()
    }
    const ctx = BrowserStore.getContext()
    if (ctx && DownloadPermissionHelper.isDownloadDirGranted(ctx)) {
      try {
        const publicDir = Environment.getUserDownloadDir()
        if (publicDir && publicDir.length > 0) {
          this.ensureDir(publicDir)
          if (this.canWriteProbe(publicDir)) {
            BrowserLog.info(`[DownloadPath] use public Download dir=${publicDir}`)
            return publicDir
          }
        }
      } catch (err) {
        BrowserLog.warn(`[DownloadPath] getUserDownloadDir failed: ${JSON.stringify(err)}`)
      }
    }
    return this.getSandboxDownloadDir()
  }

  getMobilePublicDownloadDir(): string | null {
    if (!this.usesMobileDownloadStrategy()) {
      return null
    }
    return this.getPublicDownloadDir()
  }

  buildSandboxSavePath(fileName: string): string {
    const dir = this.getSandboxDownloadDir()
    return `${dir}/${this.sanitizeFileName(fileName)}`
  }

  /**
   * 为 ArkWeb 预览准备可读路径：已在沙箱则直接返回；
   * 公共 Download 等路径复制到沙箱 preview 目录（Web fileAccess 更稳）。
   */
  ensurePreviewLoadPath(sourcePath: string, fileName: string): string {
    const src = sourcePath.trim()
    if (src.length === 0 || !this.fileExists(src)) {
      return src
    }
    if (this.isAppSandboxPath(src)) {
      return src
    }
    const ctx = BrowserStore.getContext()
    const base = ctx?.filesDir || ctx?.cacheDir || ''
    if (base.length === 0) {
      return src
    }
    const dir = `${base}/preview`
    this.ensureDir(dir)
    const dest = `${dir}/${this.sanitizeFileName(fileName)}`
    try {
      if (this.fileExists(dest)) {
        this.deleteFileAtPath(dest)
      }
      fileIo.copyFileSync(src, dest)
      BrowserLog.info(`[DownloadPath] preview copy src=${src} dest=${dest}`)
      return dest
    } catch (err) {
      BrowserLog.warn(`[DownloadPath] preview copy failed: ${JSON.stringify(err)}`)
      return src
    }
  }

  /**
   * 外部 Want（文件管理器）传入的 file:// URI / 绝对路径 → 沙箱预览路径。
   * 依赖调用方授予的临时读权限（FLAG_AUTH_READ_URI_PERMISSION）。
   */
  prepareExternalUriPreview(uriOrPath: string, fileName: string): string {
    const src = uriOrPath.trim()
    if (src.length === 0) {
      return ''
    }
    const safeName = this.sanitizeFileName(
      fileName.trim().length > 0 ? fileName : BrowserUtils.localFileDisplayName(src) || 'preview.bin')
    if (!src.startsWith('file://') && !src.startsWith('datashare://') && this.fileExists(src)) {
      return this.ensurePreviewLoadPath(src, safeName)
    }
    const ctx = BrowserStore.getContext()
    const base = ctx?.filesDir || ctx?.cacheDir || ''
    if (base.length === 0) {
      return ''
    }
    const dir = `${base}/preview`
    this.ensureDir(dir)
    const dest = `${dir}/${safeName}`
    try {
      if (this.fileExists(dest)) {
        this.deleteFileAtPath(dest)
      }
      const srcFile = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY)
      try {
        const dstFile = fileIo.openSync(dest,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
        try {
          fileIo.copyFileSync(srcFile.fd, dstFile.fd)
        } finally {
          fileIo.closeSync(dstFile)
        }
      } finally {
        fileIo.closeSync(srcFile)
      }
      BrowserLog.info(`[DownloadPath] external uri preview ok dest=${dest}`)
      return dest
    } catch (err) {
      BrowserLog.error(`[DownloadPath] external uri preview failed uri=${src.slice(0, 120)}: ${JSON.stringify(err)}`)
      this.deleteFileAtPath(dest)
      return ''
    }
  }

  /** 是否为应用沙箱路径（filesDir / cacheDir / haps 内非 Download） */
  isAppSandboxPath(path: string): boolean {
    if (!path || path.length === 0) {
      return true
    }
    const ctx = BrowserStore.getContext()
    const filesDir = ctx?.filesDir ?? ''
    const cacheDir = ctx?.cacheDir ?? ''
    if (filesDir.length > 0 && path.startsWith(filesDir)) {
      return true
    }
    if (cacheDir.length > 0 && path.startsWith(cacheDir)) {
      return true
    }
    return path.includes('/haps/') && !path.includes('/Download')
  }

  private getSandboxDownloadDir(): string {
    const ctx = BrowserStore.getContext()
    const base = ctx?.filesDir || ctx?.cacheDir || ''
    const fallback = base ? `${base}/downloads` : '/data/storage/el2/base/cache/web'
    this.ensureDir(fallback)
    BrowserLog.info(`[DownloadPath] sandbox download dir=${fallback}`)
    return fallback
  }

  private tryEnvironmentDownloadDir(): string | null {
    const ctx = BrowserStore.getContext()
    if (!ctx || !DownloadPermissionHelper.isDownloadDirGranted(ctx)) {
      return null
    }
    try {
      const publicDir = Environment.getUserDownloadDir()
      if (publicDir && publicDir.length > 0) {
        this.ensureDir(publicDir)
        if (this.canWriteProbe(publicDir)) {
          return publicDir
        }
      }
    } catch (err) {
      BrowserLog.warn(`[DownloadPath] getUserDownloadDir failed: ${JSON.stringify(err)}`)
    }
    return null
  }

  private resolvePortablePublicDownloadDir(): string | null {
    const ctx = BrowserStore.getContext()
    const bundleName = ctx?.applicationInfo?.name ?? 'com.ohos.browser'
    const candidates = this.buildPortablePublicDirCandidates(bundleName)
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i]
      this.ensureDir(candidate)
      if (this.canWriteProbe(candidate)) {
        return candidate
      }
      BrowserLog.warn(`[DownloadPath] public candidate not writable dir=${candidate}`)
    }
    return null
  }

  private buildPortablePublicDirCandidates(bundleName: string): string[] {
    const candidates: string[] = []
    const pushUnique = (dir: string): void => {
      if (dir.length > 0 && !candidates.includes(dir)) {
        candidates.push(dir)
      }
    }
    try {
      if (canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain')) {
        const base = Environment.getUserDownloadDir()
        pushUnique(`${base}/${bundleName}`)
      }
    } catch (err) {
      BrowserLog.warn(`[DownloadPath] Environment.getUserDownloadDir failed: ${JSON.stringify(err)}`)
    }
    try {
      const base = Environment.getUserDownloadDir()
      pushUnique(`${base}/${bundleName}`)
    } catch (_err) {
      // 忽略
    }
    pushUnique(`/storage/Users/currentUser/Download/${bundleName}`)
    pushUnique(`/storage/Users/0/Download/${bundleName}`)
    pushUnique(`/storage/media/100/local/files/Docs/Download/${bundleName}`)
    pushUnique(`/storage/media/100/local/files/Download/${bundleName}`)
    pushUnique(`/storage/media/100/local/download/${bundleName}`)
    return candidates
  }

  private canWriteProbe(dir: string): boolean {
    const probe = `${dir}/.browser_dl_probe_${Date.now()}`
    try {
      const file = fileIo.openSync(probe, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      fileIo.closeSync(file)
      fileIo.unlinkSync(probe)
      return true
    } catch (err) {
      BrowserLog.warn(`[DownloadPath] write probe failed dir=${dir}: ${JSON.stringify(err)}`)
      return false
    }
  }

  ensureDirectory(dir: string): void {
    this.ensureDir(dir)
  }

  buildPublicSavePath(fileName: string): string | null {
    const dir = this.getPublicDownloadDir()
    if (!dir) {
      return null
    }
    const uniqueName = this.resolveUniqueFileName(dir, fileName)
    return `${dir}/${uniqueName}`
  }

  buildMobilePublicSavePath(fileName: string): string | null {
    return this.buildPublicSavePath(fileName)
  }

  isMobilePublicPath(path: string): boolean {
    const dir = this.getPublicDownloadDir()
    return dir !== null && dir.length > 0 && path.startsWith(dir)
  }

  canUsePublicDownloadDir(): boolean {
    return this.tryEnvironmentDownloadDir() !== null
  }

  /** 下载落盘候选：优先沙箱（稳定），2in1 有权限时可直写公共目录 */
  resolveDownloadTargetPaths(fileName: string): string[] {
    if (this.usesMobileDownloadStrategy()) {
      return [this.buildSandboxSavePath(fileName)]
    }
    if (this.canUsePublicDownloadDir()) {
      return [this.buildSavePath(fileName)]
    }
    return [this.buildSandboxSavePath(fileName)]
  }

  buildSavePath(fileName: string): string {
    const dir = this.getDownloadDir()
    return `${dir}/${this.sanitizeFileName(fileName)}`
  }

  /**
   * 断点续传/异常重启恢复：优先复用 DB 路径或任务文件名对应的稳定沙箱路径，
   * 避免因残缺文件已存在而 resolveUniqueFileName 生成 (1)(2) 新路径导致从头下载。
   */
  resolveResumeLocalPath(task: DownloadTask): string {
    const stored = task.localPath.trim()
    if (stored.length > 0 && this.fileExists(stored)) {
      return stored
    }
    const stable = this.buildSavePath(task.fileName)
    if (this.fileExists(stable)) {
      return stable
    }
    if (stored.length > 0) {
      return stored
    }
    return stable
  }

  resolveUniqueDownloadName(fileName: string): string {
    const dir = this.getDownloadDir()
    let candidate = this.sanitizeFileName(fileName)
    let attempt = 0
    while (attempt < 999 && this.isNameTaken(dir, candidate)) {
      candidate = this.nextDuplicateName(fileName, attempt)
      attempt++
    }
    return candidate
  }

  resolveUniqueFileName(dir: string, fileName: string): string {
    let candidate = this.sanitizeFileName(fileName)
    let attempt = 0
    while (attempt < 999 && this.fileExists(`${dir}/${candidate}`)) {
      candidate = this.nextDuplicateName(fileName, attempt)
      attempt++
    }
    return candidate
  }

  sanitizeFileName(fileName: string): string {
    return fileName.replace(/[/\\?%*:|"<>]/g, '_').trim() || 'download'
  }

  fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (_err) {
      return false
    }
  }

  deleteFileAtPath(path: string): boolean {
    if (!path || path.length === 0) {
      return false
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
        BrowserLog.info(`[DownloadPath] deleted file path=${path}`)
        return true
      }
    } catch (err) {
      BrowserLog.warn(`[DownloadPath] delete file failed path=${path}: ${JSON.stringify(err)}`)
    }
    return false
  }

  /** 下载异常失败：清理沙箱、文管及已知路径上的残留文件 */
  cleanupFailedArtifacts(fileName: string, knownPaths: string[] = []): void {
    const safeName = this.sanitizeFileName(fileName)
    const candidates: string[] = []
    const pushUnique = (path: string): void => {
      const p = path.trim()
      if (p.length > 0 && !candidates.includes(p)) {
        candidates.push(p)
      }
    }
    for (let i = 0; i < knownPaths.length; i++) {
      pushUnique(knownPaths[i])
    }
    pushUnique(`${this.getSandboxDownloadDir()}/${safeName}`)
    const publicDir = this.getPublicDownloadDir()
    if (publicDir !== null && publicDir.length > 0) {
      pushUnique(`${publicDir}/${safeName}`)
    }
    let removed = 0
    for (let i = 0; i < candidates.length; i++) {
      if (this.deleteFileAtPath(candidates[i])) {
        removed++
      }
    }
    if (removed > 0) {
      BrowserLog.info(`[DownloadPath] cleanupFailedArtifacts file=${safeName} removed=${removed}`)
    }
  }

  private isNameTaken(dir: string, fileName: string): boolean {
    if (this.fileExists(`${dir}/${fileName}`)) {
      return true
    }
    const tasks = AppStorage.get<DownloadTask[]>(AppStorageKeys.DOWNLOADS) ?? []
    return tasks.some((t) =>
      t.fileName === fileName && (t.status === 'done' || t.status === 'running' || t.status === 'paused')
    )
  }

  private nextDuplicateName(originalName: string, attempt: number): string {
    const safe = this.sanitizeFileName(originalName)
    const dot = safe.lastIndexOf('.')
    const suffix = ` (${attempt + 1})`
    if (dot > 0) {
      return `${safe.slice(0, dot)}${suffix}${safe.slice(dot)}`
    }
    return `${safe}${suffix}`
  }

  private ensureDir(dir: string): void {
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
      } catch (mkdirErr) {
        BrowserLog.warn(`[DownloadPath] mkdir failed dir=${dir}: ${JSON.stringify(mkdirErr)}`)
      }
    }
  }
}
