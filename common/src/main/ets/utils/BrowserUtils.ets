import { fileUri } from '@kit.CoreFileKit'
import { BrowserStrings } from './BrowserStrings'

/** 通用工具函数 */
export class BrowserUtils {
  /** 写入历史前规范化 URL（去尾部斜杠等） */
  static normalizeHistoryUrl(url: string): string {
    let u = url.trim()
    if (!u) {
      return ''
    }
    while (u.length > 'https://x'.length && u.endsWith('/')) {
      u = u.slice(0, -1)
    }
    return u
  }

  /** 历史去重用的站点标识（主机名，小写） */
  static historySiteKey(url: string): string {
    const normalized = BrowserUtils.normalizeHistoryUrl(url)
    if (!normalized) {
      return ''
    }
    return BrowserUtils.tabHostname(normalized).toLowerCase()
  }

  /** 远程 favicon 地址（历史无本地缓存时的展示兜底） */
  static remoteFaviconUrl(url: string): string {
    const host = BrowserUtils.historySiteKey(url)
    if (!host) {
      return ''
    }
    return `https://${host}/favicon.ico`
  }

  /** 将 UI 文件大小文本解析为字节数（无法解析返回 0） */
  static parseFileSizeText(text: string): number {
    const trimmed = text.trim().toUpperCase()
    if (!trimmed) {
      return 0
    }
    const match = trimmed.match(/^([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB|TB)?$/)
    if (!match) {
      return 0
    }
    const value = parseFloat(match[1])
    if (!Number.isFinite(value) || value < 0) {
      return 0
    }
    const unit = match[2] ?? 'B'
    const mul = BrowserUtils.fileSizeUnitMultiplier(unit)
    return Math.floor(value * mul)
  }

  private static fileSizeUnitMultiplier(unit: string): number {
    if (unit === 'KB') {
      return 1024
    }
    if (unit === 'MB') {
      return 1024 * 1024
    }
    if (unit === 'GB') {
      return 1024 * 1024 * 1024
    }
    if (unit === 'TB') {
      return 1024 * 1024 * 1024 * 1024
    }
    return 1
  }

  /** 判断 URL 是否应写入浏览历史 */
  static isRecordableHistoryUrl(url: string): boolean {
    const u = url.trim().toLowerCase()
    if (!u || u === 'about:blank') {
      return false
    }
    if (u.startsWith('javascript:') || u.startsWith('data:') || u.startsWith('blob:')) {
      return false
    }
    return /^https?:\/\//i.test(u)
  }

  /** 是否应在 WebView 内正常加载（http/https/about/本地预览路径） */
  static isWebViewLoadableUrl(url: string): boolean {
    const raw = url.trim()
    const u = raw.toLowerCase()
    if (!u) {
      return false
    }
    if (u.startsWith('http://') || u.startsWith('https://')) {
      return true
    }
    if (u.startsWith('about:')) {
      return true
    }
    // ArkWeb 内置 PDF/HTML 预览：沙箱绝对路径或 file/resource
    if (u.startsWith('file://') || u.startsWith('resource://')) {
      return true
    }
    if (raw.startsWith('/')) {
      return true
    }
    return false
  }

  /**
   * 是否为唤起原生应用的外部 scheme（store/hap/Want deeplink 等）。
   * 此类 URL 在 WebView 内加载会白屏，应在 onLoadIntercept 拦截。
   */
  static isExternalAppScheme(url: string): boolean {
    const u = url.trim()
    if (!u || BrowserUtils.isWebViewLoadableUrl(u)) {
      return false
    }
    if (u.startsWith('javascript:') || u.startsWith('data:') || u.startsWith('blob:')) {
      return false
    }
    return u.includes('://')
  }

  /** 加载中占位标题（Cloudflare「Just a moment…」/「请稍候...」等），不应写入历史与标签 */
  static isTransientPageTitle(title: string): boolean {
    const raw = title.trim()
    if (!raw) {
      return true
    }
    // 去掉末尾省略号（. … …）与空白后再判断
    const stripped = raw.replace(/[\s.。…⋯]+$/g, '').trim()
    const lower = stripped.toLowerCase()
    if (lower === 'just a moment' || lower === 'please wait' || lower === 'please wait a moment' ||
      lower === 'loading' || lower === 'one moment' || lower === 'one moment please' ||
      lower === 'checking your browser' || lower === 'attention required') {
      return true
    }
    if (stripped === '请稍候' || stripped === '请稍后' || stripped === '请稍等' ||
      stripped === '加载中' || stripped === '正在加载' || stripped === '稍候' || stripped === '稍后' ||
      stripped.startsWith('请稍候') || stripped.startsWith('请稍后') || stripped.startsWith('请稍等')) {
      return true
    }
    // 原文以占位词开头也视为临时标题（如「请稍候...」未剥净时）
    if (raw.startsWith('请稍候') || raw.startsWith('请稍后') || raw.startsWith('请稍等') ||
      lower.startsWith('just a moment') || lower.startsWith('please wait')) {
      return true
    }
    return false
  }

  /** 历史展示用标题：临时占位文案回退为主机名；纯主机名且与当前页不符时也回退 */
  static historyDisplayTitle(title: string, url: string): string {
    const host = BrowserUtils.tabHostname(url).trim()
    const t = title.trim()
    if (BrowserUtils.isValidPageTitle(t)) {
      // 标题若是「其它站点的裸主机名」，视为错绑，改用本页主机名
      if (BrowserUtils.looksLikeBareHostname(t)) {
        const titleHost = t.toLowerCase()
        const pageHost = host.toLowerCase()
        if (pageHost.length > 0 && titleHost !== pageHost &&
          !pageHost.endsWith(`.${titleHost}`) && !titleHost.endsWith(`.${pageHost}`)) {
          return host.length > 0 ? host : t
        }
      }
      return t
    }
    return host.length > 0 ? host : (t.length > 0 ? t : url.trim())
  }

  /** 是否像裸主机名（无空格、含点、无路径）——用于识别错绑的历史标题 */
  static looksLikeBareHostname(text: string): boolean {
    const t = text.trim().toLowerCase()
    if (!t || t.includes(' ') || t.includes('/') || t.includes(':')) {
      return false
    }
    if (!t.includes('.')) {
      return false
    }
    return /^[a-z0-9.-]+$/.test(t)
  }

  /** 页面标题是否合法（排除外链 scheme、加载占位文案） */
  static isValidPageTitle(title: string): boolean {
    const t = title.trim()
    if (!t) {
      return false
    }
    if (BrowserUtils.isExternalAppScheme(t)) {
      return false
    }
    if (BrowserUtils.isTransientPageTitle(t)) {
      return false
    }
    return true
  }

  /** 规范化页面 URL，用于书签去重与匹配 */
  static normalizePageUrl(url: string): string {
    let u = url.trim()
    if (!u) {
      return ''
    }
    if (!/^https?:\/\//i.test(u)) {
      u = `https://${u}`
    }
    u = u.split('#')[0].split('?')[0].toLowerCase()
    while (u.length > 1 && u.endsWith('/')) {
      u = u.slice(0, -1)
    }
    return u
  }

  /** 浏览会话站点标识（www/m 子域归一，用于入口重定向判定） */
  static browseSiteKey(url: string): string {
    const host = BrowserUtils.tabHostname(url).toLowerCase()
    if (host === 'www.baidu.com' || host === 'm.baidu.com') {
      return 'baidu.com'
    }
    if (host === 'www.so.com' || host === 'm.so.com' || host === 'so.com') {
      return 'so.com'
    }
    if (host === 'www.sogou.com' || host === 'm.sogou.com' || host === 'wap.sogou.com') {
      return 'sogou.com'
    }
    return host
  }

  /** 跳转中转页（再次 load 会重定向到外链，不宜作为后退目标） */
  static isNavTransitUrl(url: string): boolean {
    const u = url.trim().toLowerCase()
    if (!u) {
      return false
    }
    if (u.includes('baidu.php')) {
      return true
    }
    if (u.includes('/link?') || u.includes('/jump?')) {
      return true
    }
    return false
  }

  /** 将已知桌面站点 URL 转为移动端（360/搜狗等）；百度等已自适应则原样返回 */
  static resolveBrowseUrl(url: string): string {
    const trimmed = url.trim()
    if (!trimmed) {
      return trimmed
    }
    try {
      const withScheme = trimmed.startsWith('http') ? trimmed : `https://${trimmed}`
      const lower = withScheme.toLowerCase()
      if (lower.includes('://www.so.com') || lower.includes('://so.com/') || lower.endsWith('://so.com')) {
        return withScheme.replace(/:\/\/(www\.)?so\.com/i, '://m.so.com')
      }
      if (lower.includes('://www.sogou.com') || lower.includes('://wap.sogou.com') ||
        lower.includes('://sogou.com/') || lower.endsWith('://sogou.com')) {
        return withScheme.replace(/:\/\/(www\.|wap\.)?sogou\.com/i, '://m.sogou.com')
      }
    } catch (_err) {
      // 解析失败时原样返回
    }
    return trimmed
  }

  /** 根据搜索引擎 ID 返回对应的搜索 URL 前缀 */
  static getSearchEngineBase(engine: string): string {
    if (engine === 'bing') {
      return 'https://www.bing.com/search?q='
    }
    if (engine === 'sogou') {
      return 'https://m.sogou.com/web?query='
    }
    if (engine === '360') {
      return 'https://m.so.com/s?q='
    }
    return 'https://www.baidu.com/s?wd='
  }

  /** 从 URL 中提取主机名用于标签页标题展示 */
  static tabHostname(url: string): string {
    try {
      const normalized = url.startsWith('http') ? url : `https://${url}`
      const host = normalized.replace(/^https?:\/\//, '').split('/')[0]
      return host || url
    } catch {
      return url
    }
  }

  /** 判断文件名是否为常见图片格式 */
  static isImageFile(name: string): boolean {
    return /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(name)
  }

  /** 下载列表文件类型（用于类型图标） */
  static inferDownloadFileKind(name: string): string {
    const lower = name.toLowerCase()
    if (BrowserUtils.isImageFile(name)) {
      return 'image'
    }
    // PDF 及相关版式文档
    if (/\.(pdf|ofd|xps)$/i.test(lower)) {
      return 'pdf'
    }
    if (/\.(zip|rar|7z|tar|gz|tgz|bz2|xz)$/i.test(lower)) {
      return 'archive'
    }
    if (/\.(mp4|mkv|avi|mov|webm|3gp|flv|wmv|m4v)$/i.test(lower)) {
      return 'video'
    }
    if (/\.(mp3|wav|aac|flac|ogg|m4a)$/i.test(lower)) {
      return 'audio'
    }
    if (/\.(txt|html?|md|json|xml|csv)$/i.test(lower)) {
      return 'text'
    }
    return 'generic'
  }

  /**
   * 是否可用 ArkWeb 内置预览（PDF / HTML / 纯文本等）。
   * 这类文件不走系统 viewData，避免无匹配 Ability。
   */
  static canPreviewInBrowser(fileName: string): boolean {
    const lower = fileName.trim().toLowerCase()
    if (lower.length === 0) {
      return false
    }
    if (/\.pdf$/i.test(lower)) {
      return true
    }
    return /\.(html?|txt|md|json|xml|csv)$/i.test(lower)
  }

  /** 从 URL 路径推断是否可在浏览器内预览 */
  static canPreviewInBrowserUrl(url: string): boolean {
    const trimmed = url.trim()
    if (!trimmed) {
      return false
    }
    const pathPart = trimmed.split('?')[0].split('#')[0]
    const slashIdx = pathPart.lastIndexOf('/')
    const fileName = slashIdx >= 0 ? pathPart.substring(slashIdx + 1) : pathPart
    try {
      return BrowserUtils.canPreviewInBrowser(decodeURIComponent(fileName))
    } catch (_err) {
      return BrowserUtils.canPreviewInBrowser(fileName)
    }
  }

  /**
   * 构造 ArkWeb loadUrl 可用的本地预览地址。
   * 沙箱绝对路径可直接加载；已是 file/resource/http(s) 则原样返回。
   */
  static buildLocalFilePreviewUrl(localPath: string): string {
    const p = localPath.trim()
    if (!p) {
      return ''
    }
    if (p.startsWith('file://') || p.startsWith('resource://') ||
      p.startsWith('http://') || p.startsWith('https://')) {
      return p
    }
    return p
  }

  /** 从本地路径 / file:// / 普通 URL 提取文件名用于标题展示 */
  static localFileDisplayName(url: string): string {
    let path = url.trim()
    if (path.startsWith('file://')) {
      path = path.substring('file://'.length)
    }
    const noQuery = path.split('?')[0].split('#')[0]
    const slashIdx = noQuery.lastIndexOf('/')
    const name = slashIdx >= 0 ? noQuery.substring(slashIdx + 1) : noQuery
    if (name.length === 0) {
      return ''
    }
    try {
      return decodeURIComponent(name)
    } catch (_err) {
      return name
    }
  }

  /** 浏览页标题：本地预览文件用文件名，否则用主机名 */
  static browsePageTitle(url: string): string {
    const trimmed = url.trim()
    if (!trimmed) {
      return ''
    }
    const fileName = BrowserUtils.localFileDisplayName(trimmed)
    if ((trimmed.startsWith('/') || trimmed.startsWith('file://')) && fileName.length > 0) {
      return fileName
    }
    if (fileName.length > 0 && BrowserUtils.canPreviewInBrowser(fileName)) {
      return fileName
    }
    return BrowserUtils.tabHostname(trimmed)
  }

  /**
   * 下载列表图片缩略图 URI：优先图库 URI，已完成/暂停任务回退本地路径。
   */
  static resolveDownloadImagePreviewUri(fileName: string, galleryUri: string, localPath: string,
    status: string): string {
    if (!BrowserUtils.isImageFile(fileName)) {
      return ''
    }
    const gallery = galleryUri.trim()
    if (gallery.length > 0) {
      return gallery
    }
    const local = localPath.trim()
    if (local.length === 0) {
      return ''
    }
    if (status === 'pending' || status === 'queued' || status === 'failed' || status === 'deleted') {
      return ''
    }
    try {
      if (local.startsWith('file://') || local.startsWith('datashare://')) {
        return local
      }
      return fileUri.getUriFromPath(local)
    } catch (_err) {
      return local.startsWith('/') ? `file://${local}` : ''
    }
  }

  /** 从图片 URL 推断本地保存文件名 */
  static deriveDownloadFileName(url: string, fallback: string = 'photo.jpg'): string {
    const trimmed = url.trim()
    if (!trimmed) {
      return fallback
    }
    if (trimmed.startsWith('data:')) {
      const header = trimmed.substring(0, trimmed.indexOf(','))
      if (/image\/png/i.test(header)) {
        return 'photo.png'
      }
      if (/image\/gif/i.test(header)) {
        return 'photo.gif'
      }
      if (/image\/webp/i.test(header)) {
        return 'photo.webp'
      }
      return fallback
    }
    try {
      const pathPart = trimmed.split('?')[0].split('#')[0]
      const slashIdx = pathPart.lastIndexOf('/')
      const name = slashIdx >= 0 ? pathPart.substring(slashIdx + 1) : pathPart
      const decoded = decodeURIComponent(name)
      if (decoded.length > 0 && !decoded.includes('/') && BrowserUtils.isImageFile(decoded)) {
        return decoded.replace(/[/\\?%*:|"<>]/g, '_')
      }
    } catch (_err) {
      // 解析失败时使用 fallback
    }
    return fallback
  }

  /** 从图片 URL / data URL 推断 image/* MIME（剪贴板 HTML 等场景） */
  static inferImageMimeFromUrl(url: string): string {
    const trimmed = url.trim()
    if (trimmed.startsWith('data:')) {
      const commaIdx = trimmed.indexOf(',')
      const header = commaIdx >= 0 ? trimmed.substring(0, commaIdx) : trimmed
      const matched = header.match(/image\/[\w.+-]+/i)
      if (matched) {
        return matched[0].toLowerCase()
      }
      return 'image/jpeg'
    }
    const fileName = BrowserUtils.deriveDownloadFileName(trimmed, 'photo.jpg')
    const mime = BrowserUtils.inferMimeType(fileName)
    return mime.startsWith('image/') ? mime : 'image/jpeg'
  }

  /** 是否可通过 HTTP / data URL 直接拉取并保存 */
  static isDirectDownloadUrl(url: string): boolean {
    const u = url.trim().toLowerCase()
    return u.startsWith('http://') || u.startsWith('https://') || u.startsWith('data:')
  }

  /** 判断 URL 是否指向常见图片资源（用于直接打开图片链接） */
  static isImageUrl(url: string): boolean {
    const trimmed = url.trim()
    if (!trimmed) {
      return false
    }
    const pathPart = trimmed.split('?')[0].split('#')[0]
    const slashIdx = pathPart.lastIndexOf('/')
    const fileName = slashIdx >= 0 ? pathPart.substring(slashIdx + 1) : pathPart
    return BrowserUtils.isImageFile(fileName)
  }

  /** 为重复文件名生成带 (1) 后缀的建议重命名 */
  static suggestRename(name: string): string {
    const dot = name.lastIndexOf('.')
    if (dot > 0) {
      return `${name.slice(0, dot)} (1)${name.slice(dot)}`
    }
    return `${name} (1)`
  }

  /** 根据扩展名推断 MIME 类型，供系统打开文件使用 */
  static inferMimeType(name: string): string {
    const lower = name.toLowerCase()
    if (lower.endsWith('.pdf')) {
      return 'application/pdf'
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg'
    }
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    if (lower.endsWith('.bmp')) {
      return 'image/bmp'
    }
    if (lower.endsWith('.zip')) {
      return 'application/zip'
    }
    if (lower.endsWith('.txt')) {
      return 'text/plain'
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html'
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4'
    }
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg'
    }
    return '*/*'
  }

  /** 根据文件扩展名推断文件类型标签（PDF / ZIP / JPEG 等） */
  static inferFileTypeLabel(name: string): string {
    const lower = name.toLowerCase()
    if (/\.pdf$/i.test(lower)) {
      return 'PDF'
    }
    if (/\.(zip|rar|7z)$/i.test(lower)) {
      return 'ZIP'
    }
    if (BrowserUtils.isImageFile(name)) {
      return 'JPEG'
    }
    return 'File'
  }
}
