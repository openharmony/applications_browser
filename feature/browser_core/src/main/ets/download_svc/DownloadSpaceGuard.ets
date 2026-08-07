import { statfs, storageStatistics } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserUtils } from 'common'
import { DownloadPathService } from './DownloadPathService'

/** 存储空间校验结果 */
export interface DownloadSpaceCheckResult {
  ok: boolean
  /** 所需字节数（已知时） */
  requiredBytes: number
  /** 可用字节数（探测成功时） */
  freeBytes: number
  /** 失败原因：'unknown_size' 表示浏览器暂时拿不到文件大小，跳过强制校验 */
  reason: 'ok' | 'insufficient' | 'unknown_size' | 'probe_failed'
}

interface ProbeResult {
  ok: boolean
  freeBytes: number
}

const RESERVED_BYTES: number = 32 * 1024 * 1024

/** 下载前置：本地剩余空间是否支持当前文件大小 */
export class DownloadSpaceGuard {
  /**
   * 解析下载所需字节数：优先 raw bytes，其次 UI 文本，最后 HEAD 探测 URL。
   * @returns 已知大小（字节），未知返回 0
   */
  static async resolveRequiredBytes(sizeText: string, fileSizeBytes: number, sourceUrl: string): Promise<number> {
    if (Number.isFinite(fileSizeBytes) && fileSizeBytes > 0) {
      return Math.floor(fileSizeBytes)
    }
    const parsed = BrowserUtils.parseFileSizeText(sizeText)
    if (parsed > 0) {
      return parsed
    }
    const url = sourceUrl.trim()
    if (url.length > 0 && BrowserUtils.isDirectDownloadUrl(url)) {
      return await DownloadSpaceGuard.probeRemoteFileSize(url)
    }
    return 0
  }

  /** 已知 size（字节）时直接用，未知返回 0 让调用方按需跳过 */
  static async check(requiredBytes: number): Promise<DownloadSpaceCheckResult> {
    if (!Number.isFinite(requiredBytes) || requiredBytes <= 0) {
      return {
        ok: true,
        requiredBytes: 0,
        freeBytes: 0,
        reason: 'unknown_size'
      }
    }

    const probe = await DownloadSpaceGuard.probeFreeBytes()
    if (!probe.ok) {
      BrowserLog.warn(`[DownloadSpace] probe failed need=${requiredBytes}`)
      return {
        ok: true,
        requiredBytes,
        freeBytes: 0,
        reason: 'probe_failed'
      }
    }

    const need = requiredBytes + RESERVED_BYTES
    if (probe.freeBytes < need) {
      BrowserLog.warn(`[DownloadSpace] insufficient need=${need} free=${probe.freeBytes}`)
      return {
        ok: false,
        requiredBytes,
        freeBytes: probe.freeBytes,
        reason: 'insufficient'
      }
    }
    return {
      ok: true,
      requiredBytes,
      freeBytes: probe.freeBytes,
      reason: 'ok'
    }
  }

  /** 通过 HTTP HEAD / Range 探测远程文件 Content-Length */
  static async probeRemoteFileSize(url: string): Promise<number> {
    const trimmed = url.trim()
    if (trimmed.length === 0 || !BrowserUtils.isDirectDownloadUrl(trimmed) || trimmed.startsWith('data:')) {
      return 0
    }
    const headSize = await DownloadSpaceGuard.requestContentLength(trimmed, http.RequestMethod.HEAD)
    if (headSize > 0) {
      return headSize
    }
    return await DownloadSpaceGuard.requestContentLength(trimmed, http.RequestMethod.GET, 'bytes=0-0')
  }

  private static async requestContentLength(url: string, method: http.RequestMethod,
    rangeHeader: string = ''): Promise<number> {
    const httpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; OpenHarmony) AppleWebKit/537.36 Browser'
      }
      if (rangeHeader.length > 0) {
        header['Range'] = rangeHeader
      }
      const response = await httpRequest.request(url, {
        method,
        connectTimeout: 12000,
        readTimeout: 12000,
        header
      })
      const code = response.responseCode
      if (code !== 200 && code !== 206) {
        return 0
      }
      const fromHeader = DownloadSpaceGuard.parseContentLengthHeader(response.header as Record<string, string>)
      if (fromHeader > 0) {
        return fromHeader
      }
      if (code === 206 && rangeHeader.length > 0) {
        const contentRange = DownloadSpaceGuard.readHeaderValue(response.header as Record<string, string>, 'Content-Range')
        const match = contentRange.match(/\/(\d+)\s*$/)
        if (match && match[1]) {
          const total = parseInt(match[1], 10)
          if (Number.isFinite(total) && total > 0) {
            return total
          }
        }
      }
      return 0
    } catch (err) {
      BrowserLog.warn(`[DownloadSpace] probeRemoteFileSize failed url=${url.slice(0, 80)}: ${JSON.stringify(err)}`)
      return 0
    } finally {
      httpRequest.destroy()
    }
  }

  private static parseContentLengthHeader(headers: Record<string, string>): number {
    const raw = DownloadSpaceGuard.readHeaderValue(headers, 'Content-Length')
    if (raw.length === 0) {
      return 0
    }
    const value = parseInt(raw, 10)
    if (!Number.isFinite(value) || value <= 0) {
      return 0
    }
    return value
  }

  private static readHeaderValue(headers: Record<string, string>, name: string): string {
    const direct = headers[name]
    if (typeof direct === 'string' && direct.length > 0) {
      return direct.trim()
    }
    const lower = headers[name.toLowerCase()]
    if (typeof lower === 'string' && lower.length > 0) {
      return lower.trim()
    }
    const keys = Object.keys(headers)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === name.toLowerCase()) {
        const val = headers[keys[i]]
        if (typeof val === 'string' && val.length > 0) {
          return val.trim()
        }
      }
    }
    return ''
  }

  private static async probeFreeBytes(): Promise<ProbeResult> {
    const paths: string[] = []
    try {
      const downloadDir = DownloadPathService.getInstance().getDownloadDir()
      if (downloadDir.length > 0) {
        paths.push(downloadDir)
      }
    } catch (_err) {
      // ignore
    }
    const ctx = BrowserStore.getContext()
    if (ctx !== null) {
      if (ctx.filesDir && ctx.filesDir.length > 0) {
        paths.push(ctx.filesDir)
      }
      if (ctx.cacheDir && ctx.cacheDir.length > 0) {
        paths.push(ctx.cacheDir)
      }
    }
    for (let i = 0; i < paths.length; i++) {
      const path = paths[i]
      try {
        const freeSize = statfs.getFreeSizeSync(path)
        if (Number.isFinite(freeSize) && freeSize > 0) {
          BrowserLog.info(`[DownloadSpace] statfs ok path=${path} free=${freeSize}`)
          return { ok: true, freeBytes: freeSize }
        }
      } catch (err) {
        BrowserLog.warn(`[DownloadSpace] statfs getFreeSizeSync failed path=${path}: ${JSON.stringify(err)}`)
      }
      try {
        const freeSize = await statfs.getFreeSize(path)
        if (Number.isFinite(freeSize) && freeSize > 0) {
          BrowserLog.info(`[DownloadSpace] statfs async ok path=${path} free=${freeSize}`)
          return { ok: true, freeBytes: freeSize }
        }
      } catch (err) {
        BrowserLog.warn(`[DownloadSpace] statfs getFreeSize failed path=${path}: ${JSON.stringify(err)}`)
      }
    }
    try {
      const totalSize = storageStatistics.getTotalSizeSync()
      const freeSize = storageStatistics.getFreeSizeSync()
      if (Number.isFinite(totalSize) && totalSize > 0 && Number.isFinite(freeSize) && freeSize > 0) {
        return { ok: true, freeBytes: freeSize }
      }
    } catch (err) {
      BrowserLog.warn(`[DownloadSpace] storageStatistics getFreeSizeSync failed: ${JSON.stringify(err)}`)
    }
    try {
      const freeSize = await storageStatistics.getFreeSize()
      if (Number.isFinite(freeSize) && freeSize > 0) {
        return { ok: true, freeBytes: freeSize }
      }
    } catch (err) {
      BrowserLog.warn(`[DownloadSpace] storageStatistics getFreeSize failed: ${JSON.stringify(err)}`)
    }
    return { ok: false, freeBytes: 0 }
  }
}
