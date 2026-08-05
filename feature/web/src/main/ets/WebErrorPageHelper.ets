import { BrowserStrings } from 'common'
import { DownloadNetworkHelper } from 'browser_core'

/** 网页主资源加载失败时的自定义错误页 HTML（配合 onOverrideErrorPage） */
export class WebErrorPageHelper {
  private static readonly ERR_INTERNET_DISCONNECTED: number = -106
  private static readonly ERR_NAME_NOT_RESOLVED: number = -105
  private static readonly ERR_CONNECTION_FAILED: number = -104
  private static readonly ERR_NETWORK_CHANGED: number = -21
  private static readonly ERR_ADDRESS_UNREACHABLE: number = -109

  /** 是否为断网类加载错误（需监听网络恢复后自动重载） */
  static isOfflineLoadError(errorCode: number): boolean {
    return WebErrorPageHelper.isOfflineError(errorCode)
  }

  /** 构建替换默认错误页的 HTML */
  static buildOverrideHtml(failedUrl: string, errorCode: number, darkMode: boolean): string {
    const offline = WebErrorPageHelper.isOfflineError(errorCode)
    const safeUrl = WebErrorPageHelper.escapeHtml(failedUrl.trim())
    const title = offline ?
      BrowserStrings.txt($r('app.string.web_error_title_offline')) :
      BrowserStrings.txt($r('app.string.web_error_title_general'))
    const desc = offline ?
      BrowserStrings.txt($r('app.string.web_error_desc_offline')) :
      BrowserStrings.txt($r('app.string.web_error_desc_general'), safeUrl)
    const codeLabel = WebErrorPageHelper.resolveErrorLabel(errorCode, offline)
    const bg = darkMode ? '#1f1f1f' : '#f5f5f5'
    const fg = darkMode ? '#e8eaed' : '#202124'
    const muted = darkMode ? '#9aa0a6' : '#5f6368'
    const codeColor = darkMode ? '#80868b' : '#80868b'
    return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
    background: ${bg};
    color: ${fg};
  }
  .wrap { max-width: 520px; width: 100%; text-align: center; }
  .icon {
    width: 48px;
    height: 48px;
    margin: 0 auto 20px;
    border-radius: 10px;
    background: #1a73e8;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    font-size: 18px;
    font-weight: 600;
    line-height: 1;
  }
  h1 {
    margin: 0 0 12px;
    font-size: 22px;
    font-weight: 500;
    line-height: 1.35;
    text-align: center;
  }
  p {
    margin: 0 0 18px;
    font-size: 14px;
    line-height: 1.65;
    color: ${muted};
    word-break: break-word;
    text-align: center;
  }
  .code {
    font-size: 12px;
    color: ${codeColor};
    letter-spacing: 0.4px;
    text-transform: uppercase;
    text-align: center;
  }
</style>
</head>
<body>
  <div class="wrap">
    <div class="icon">&lt;/&gt;</div>
    <h1>${title}</h1>
    <p>${desc}</p>
    <div class="code">${codeLabel}</div>
  </div>
</body>
</html>`
  }

  private static isOfflineError(errorCode: number): boolean {
    if (!DownloadNetworkHelper.isNetworkAvailable()) {
      return true
    }
    return WebErrorPageHelper.isNetworkRelatedErrorCode(errorCode)
  }

  /** 断网/网络类错误码（用于自动重载监听） */
  private static isNetworkRelatedErrorCode(errorCode: number): boolean {
    return errorCode === WebErrorPageHelper.ERR_INTERNET_DISCONNECTED ||
      errorCode === WebErrorPageHelper.ERR_NETWORK_CHANGED ||
      errorCode === WebErrorPageHelper.ERR_CONNECTION_FAILED ||
      errorCode === WebErrorPageHelper.ERR_ADDRESS_UNREACHABLE
  }

  private static resolveErrorLabel(errorCode: number, offline: boolean): string {
    if (offline) {
      return 'ERR_INTERNET_DISCONNECTED'
    }
    if (errorCode > 0) {
      return `HTTP_${errorCode}`
    }
    if (errorCode === WebErrorPageHelper.ERR_NAME_NOT_RESOLVED) {
      return 'ERR_NAME_NOT_RESOLVED'
    }
    if (errorCode === WebErrorPageHelper.ERR_CONNECTION_FAILED) {
      return 'ERR_CONNECTION_FAILED'
    }
    if (errorCode === WebErrorPageHelper.ERR_ADDRESS_UNREACHABLE) {
      return 'ERR_ADDRESS_UNREACHABLE'
    }
    if (errorCode === WebErrorPageHelper.ERR_INTERNET_DISCONNECTED) {
      return 'ERR_INTERNET_DISCONNECTED'
    }
    return 'ERR_FAILED'
  }

  private static escapeHtml(raw: string): string {
    return raw
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
  }
}
