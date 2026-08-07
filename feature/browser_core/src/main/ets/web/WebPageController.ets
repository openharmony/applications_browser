import { webview } from '@kit.ArkWeb'
import { image } from '@kit.ImageKit'
import { BrowserLog } from 'common'
import { TabThumbnailService } from '../tab/TabThumbnailService'

/** Web 层控制器，封装 ArkWeb WebviewController */
export class WebPageController {
  private static instance: WebPageController | null = null
  private controller: webview.WebviewController | null = null
  private loading: boolean = false

  /** 获取 WebPageController 单例 */
  static getInstance(): WebPageController {
    if (WebPageController.instance === null) {
      WebPageController.instance = new WebPageController()
    }
    return WebPageController.instance
  }

  /** 绑定页面级 WebviewController */
  bindController(ctrl: webview.WebviewController): void {
    this.controller = ctrl
  }

  /** 启用自定义错误页（onOverrideErrorPage 前置条件） */
  ensureErrorPageEnabled(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    try {
      if (!ctrl.getErrorPageEnabled()) {
        ctrl.setErrorPageEnabled(true)
      }
    } catch (err) {
      BrowserLog.warn(`ensureErrorPageEnabled failed: ${JSON.stringify(err)}`)
    }
  }

  /** 确保 UA 含 Mobile，使站点按移动端 viewport 渲染；若已修改则返回 true */
  ensureMobileUserAgent(): boolean {
    const ctrl = this.controller
    if (!ctrl) {
      return false
    }
    try {
      const ua = ctrl.getUserAgent()
      if (/Mobile/i.test(ua)) {
        return false
      }
      ctrl.setCustomUserAgent(`${ua} Mobile`)
      BrowserLog.info('[WebPage] append Mobile to User-Agent')
      return true
    } catch (err) {
      BrowserLog.warn(`ensureMobileUserAgent failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 页面缺少 viewport meta 时注入，避免搜索结果等桌面版式撑宽 */
  ensureViewportMeta(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    const script =
      '(function(){if(window.__browserViewportMeta){return;}' +
      'window.__browserViewportMeta=1;' +
      'var existing=document.querySelector("meta[name=viewport]");' +
      'if(existing&&existing.getAttribute("content")){return;}' +
      'var meta=document.createElement("meta");' +
      'meta.name="viewport";' +
      'meta.content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes";' +
      '(document.head||document.documentElement).appendChild(meta);})();'
    try {
      void ctrl.runJavaScriptExt(script)
    } catch (err) {
      BrowserLog.warn(`ensureViewportMeta failed: ${JSON.stringify(err)}`)
    }
  }

  /** 解绑控制器（页面销毁时） */
  unbindController(): void {
    this.controller = null
    this.loading = false
  }

  /** 获取当前绑定的控制器 */
  getController(): webview.WebviewController | null {
    return this.controller
  }

  /** 获取 Web 当前页面 URL */
  getCurrentUrl(): string {
    const ctrl = this.controller
    if (!ctrl) {
      return ''
    }
    try {
      return ctrl.getUrl()
    } catch (err) {
      BrowserLog.warn(`WebPageController.getCurrentUrl failed: ${JSON.stringify(err)}`)
      return ''
    }
  }

  /** 是否正在加载 */
  isLoading(): boolean {
    return this.loading
  }

  /** 设置加载状态 */
  setLoading(loading: boolean): void {
    this.loading = loading
  }

  /** 加载指定 URL */
  loadUrl(url: string): void {
    const ctrl = this.controller
    if (!ctrl) {
      BrowserLog.error('WebPageController.loadUrl: controller not bound')
      return
    }
    try {
      ctrl.loadUrl(url)
      this.loading = true
    } catch (err) {
      BrowserLog.error(`WebPageController.loadUrl failed: ${JSON.stringify(err)}`)
    }
  }

  /** 刷新当前页面 */
  refresh(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    try {
      ctrl.refresh()
      this.loading = true
    } catch (err) {
      BrowserLog.error(`WebPageController.refresh failed: ${JSON.stringify(err)}`)
    }
  }

  /**
   * 热更新当前页 Web 文本缩放（100=默认）。
   * textZoomRatio 属性变更在部分页面不即时生效，通过 JS 注入兜底。
   */
  applyTextZoomRatio(percent: number): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    const ratio = Math.max(0.5, Math.min(3, percent / 100))
    const pct = (ratio * 100).toFixed(1)
    const script =
      `(function(){var r=${ratio.toFixed(3)};var p='${pct}%';` +
      'try{document.documentElement.style.setProperty("-webkit-text-size-adjust",p);' +
      'document.documentElement.style.setProperty("text-size-adjust",p);' +
      'if(document.body){document.body.style.setProperty("-webkit-text-size-adjust",p);' +
      'document.body.style.zoom=r;}}catch(e){}})();'
    try {
      void ctrl.runJavaScriptExt(script)
      BrowserLog.info(`[Font] web applyTextZoom=${percent}`)
    } catch (err) {
      BrowserLog.warn(`applyTextZoomRatio failed: ${JSON.stringify(err)}`)
    }
  }

  /** 停止当前页面加载 */
  stop(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    try {
      ctrl.stop()
      this.loading = false
    } catch (err) {
      BrowserLog.error(`WebPageController.stop failed: ${JSON.stringify(err)}`)
    }
  }

  /** 清除 Web 内可后退的历史（保留当前页），用于入口重定向链收尾 */
  clearWebHistory(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    try {
      ctrl.clearHistory()
      BrowserLog.info('[WebPage] clearHistory after entry settle')
    } catch (err) {
      BrowserLog.warn(`clearWebHistory failed: ${JSON.stringify(err)}`)
    }
  }

  /** Web 内是否可以后退 */
  canGoBack(): boolean {
    const ctrl = this.controller
    if (!ctrl) {
      return false
    }
    try {
      return ctrl.accessBackward()
    } catch (_err) {
      return false
    }
  }

  /** Web 内是否可以前进 */
  canGoForward(): boolean {
    const ctrl = this.controller
    if (!ctrl) {
      return false
    }
    try {
      return ctrl.accessForward()
    } catch (_err) {
      return false
    }
  }

  /** Web 内后退 */
  goBack(): boolean {
    const ctrl = this.controller
    if (!ctrl || !this.canGoBack()) {
      return false
    }
    try {
      ctrl.backward()
      return true
    } catch (err) {
      BrowserLog.error(`WebPageController.goBack failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** Web 内前进 */
  goForward(): boolean {
    const ctrl = this.controller
    if (!ctrl || !this.canGoForward()) {
      return false
    }
    try {
      ctrl.forward()
      return true
    } catch (err) {
      BrowserLog.error(`WebPageController.goForward failed: ${JSON.stringify(err)}`)
      return false
    }
  }

  private findKeyword: string = ''

  /** 页内查找：searchAllAsync 高亮全部匹配，结果经 onSearchResultReceive 回调 */
  searchInPage(keyword: string): void {
    const ctrl = this.controller
    const q = keyword.trim()
    if (!ctrl || q.length === 0) {
      this.clearFind()
      return
    }
    this.findKeyword = q
    try {
      ctrl.searchAllAsync(q)
      BrowserLog.info(`[Find] searchAllAsync kw=${q.slice(0, 40)}`)
    } catch (err) {
      BrowserLog.error(`searchInPage failed: ${JSON.stringify(err)}`)
    }
  }

  /** 跳转到下一个/上一个匹配项（依赖 searchAllAsync 已建立匹配列表） */
  findNext(forward: boolean): void {
    const ctrl = this.controller
    if (!ctrl || !this.findKeyword) {
      return
    }
    try {
      ctrl.searchNext(forward)
    } catch (err) {
      BrowserLog.error(`findNext failed: ${JSON.stringify(err)}`)
    }
  }

  /** 截取当前 Web 可视区域，供标签缩略图使用（未绘制完成或超时时返回 null） */
  captureSnapshot(timeoutMs: number = 2000): Promise<image.PixelMap | null> {
    if (!TabThumbnailService.getInstance().isWebCaptureAllowed()) {
      return Promise.resolve(null)
    }
    return new Promise((resolve) => {
      const ctrl = this.controller
      if (!ctrl) {
        resolve(null)
        return
      }
      let settled = false
      const finish = (result: image.PixelMap | null): void => {
        if (settled) {
          // 超时后迟到的 PixelMap 必须释放，避免原生图像内存泄漏
          if (result !== null) {
            try {
              result.release()
            } catch (_e) {
            }
          }
          return
        }
        settled = true
        clearTimeout(timer)
        resolve(result)
      }
      const timer = setTimeout(() => {
        BrowserLog.warn(`captureSnapshot timeout ${timeoutMs}ms`)
        finish(null)
      }, timeoutMs) as number
      try {
        ctrl.webPageSnapshot({
          id: TabThumbnailService.WEB_SNAPSHOT_ID,
          size: { width: '100%', height: '100%' }
        }, (err, result) => {
          if (err) {
            BrowserLog.warn(`captureSnapshot callback: ${JSON.stringify(err)}`)
            finish(null)
            return
          }
          if (!result?.status || !result.imagePixelMap) {
            BrowserLog.warn(`captureSnapshot not ready status=${result?.status ?? false}`)
            finish(null)
            return
          }
          finish(result.imagePixelMap)
        })
      } catch (err) {
        BrowserLog.warn(`captureSnapshot not ready: ${JSON.stringify(err)}`)
        finish(null)
      }
    })
  }

  /** 清除页内查找高亮 */
  clearFind(): void {
    this.findKeyword = ''
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    try {
      ctrl.clearMatches()
    } catch (err) {
      BrowserLog.error(`clearFind failed: ${JSON.stringify(err)}`)
    }
  }

  /** 注入网页图片点击钩子；长按菜单由 onContextMenuShow 接管。跳过视频/链接/播放器内图片，避免阻断视频播放。 */
  installImageInteractionHooks(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    const script =
      '(function(){if(window.__browserImgHooks===2){return;}' +
      'window.__browserImgHooks=2;' +
      'var style=document.createElement("style");' +
      'style.textContent="img{-webkit-touch-callout:none;-webkit-user-drag:none;user-select:none;}";' +
      '(document.head||document.documentElement).appendChild(style);' +
      'document.addEventListener("dragstart",function(ev){' +
      'var el=ev.target;if(!el){return;}' +
      'if(el.tagName==="IMG"||(el.closest&&el.closest("img"))){ev.preventDefault();}},true);' +
      'var skipPreview=function(el){' +
      'if(!el||el.tagName!=="IMG"){return true;}' +
      'if(el.closest){if(el.closest("video")){return true;}' +
      'if(el.closest("a")){return true;}' +
      'var n=el;while(n){var c=(n.className||"").toString().toLowerCase();' +
      'if(/video|player|play|media|jwplayer|bilibili|youku|iqiyi|vjs-/.test(c)){return true;}' +
      'n=n.parentElement;}}' +
      'var p=el.parentElement;if(p){if(p.querySelector&&p.querySelector("video")){return true;}' +
      'if(p.getAttribute&&p.getAttribute("role")==="button"){return true;}' +
      'if(p.onclick||(p.getAttribute&&p.getAttribute("onclick"))){return true;}}' +
      'var w=el.naturalWidth||el.clientWidth||0,h=el.naturalHeight||el.clientHeight||0;' +
      'if(w>0&&h>0&&w<80&&h<80){return true;}' +
      'return false;};' +
      'document.addEventListener("click",function(ev){' +
      'var el=ev.target;if(!el||el.tagName!=="IMG"){return;}' +
      'if(skipPreview(el)){return;}' +
      'var src=(el.currentSrc||el.src||"").trim();if(!src){return;}' +
      'ev.preventDefault();ev.stopPropagation();' +
      'if(window.BrowserBridge&&typeof window.BrowserBridge.openImagePreview==="function"){' +
      'window.BrowserBridge.openImagePreview(src);}},true);})();'
    try {
      void ctrl.runJavaScriptExt(script)
    } catch (err) {
      BrowserLog.warn(`installImageInteractionHooks failed: ${JSON.stringify(err)}`)
    }
  }

  /** 禁止超链接默认拖拽预览（避免长按时出现跟手缩略图） */
  installLinkDragBlock(): void {
    const ctrl = this.controller
    if (!ctrl) {
      return
    }
    const script =
      '(function(){if(window.__browserLinkDragBlock){return;}' +
      'window.__browserLinkDragBlock=1;' +
      'var patch=function(){document.querySelectorAll("a").forEach(function(a){a.draggable=false;});};' +
      'document.addEventListener("dragstart",function(ev){' +
      'var el=ev.target;if(!el){return;}' +
      'if(el.tagName==="A"||el.closest("a")){ev.preventDefault();}},true);' +
      'patch();' +
      'new MutationObserver(patch).observe(document.documentElement,{childList:true,subtree:true});})();'
    try {
      void ctrl.runJavaScriptExt(script)
    } catch (err) {
      BrowserLog.warn(`installLinkDragBlock failed: ${JSON.stringify(err)}`)
    }
  }
}
