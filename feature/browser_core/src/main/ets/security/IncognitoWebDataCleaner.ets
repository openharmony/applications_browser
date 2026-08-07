import { webview } from '@kit.ArkWeb'
import { BrowserLog } from 'common'

/** 无痕会话 Web 数据清理：cookie、本地存储、地理定位权限、页面缓存等 */
export class IncognitoWebDataCleaner {
  private static instance: IncognitoWebDataCleaner | null = null

  /** 获取单例 */
  static getInstance(): IncognitoWebDataCleaner {
    if (IncognitoWebDataCleaner.instance === null) {
      IncognitoWebDataCleaner.instance = new IncognitoWebDataCleaner()
    }
    return IncognitoWebDataCleaner.instance
  }

  /** 清理无痕分区 Web 数据；可传入当前 Web 控制器以顺带清除页面缓存 */
  purgeIncognitoWebData(controller?: webview.WebviewController | null): void {
    try {
      webview.WebviewController.initializeWebEngine()
    } catch (err) {
      BrowserLog.warn(`[IncognitoClean] init engine: ${JSON.stringify(err)}`)
    }

    try {
      webview.WebCookieManager.clearAllCookiesSync(true)
    } catch (err) {
      BrowserLog.warn(`[IncognitoClean] cookies: ${JSON.stringify(err)}`)
    }

    try {
      webview.WebStorage.deleteAllData(true)
    } catch (err) {
      BrowserLog.warn(`[IncognitoClean] storage: ${JSON.stringify(err)}`)
    }

    try {
      webview.GeolocationPermissions.deleteAllGeolocation(true)
    } catch (err) {
      BrowserLog.warn(`[IncognitoClean] geolocation: ${JSON.stringify(err)}`)
    }

    if (controller) {
      try {
        controller.removeCache(true)
      } catch (err) {
        BrowserLog.warn(`[IncognitoClean] removeCache: ${JSON.stringify(err)}`)
      }
    }

    BrowserLog.info('[IncognitoClean] purgeIncognitoWebData done')
  }
}
