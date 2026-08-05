import { Router } from '@kit.ArkUI'
import router from '@ohos.router'

/**
 * 页面 Router 桥接：持有 UIContext.getRouter() 实例，替代已废弃的全局 @ohos.router。
 * 长期可迁移至 Navigation + NavPathStack，当前为官方推荐的过渡方案（API 18+）。
 */
export class BrowserRouterBridge {
  private static instance: BrowserRouterBridge | null = null
  private pageRouter: Router | null = null

  static getInstance(): BrowserRouterBridge {
    if (BrowserRouterBridge.instance === null) {
      BrowserRouterBridge.instance = new BrowserRouterBridge()
    }
    return BrowserRouterBridge.instance
  }

  /** 绑定当前页面 Router（@Entry 页 aboutToAppear / onPageShow 调用） */
  bind(routerInst: Router): void {
    this.pageRouter = routerInst
  }

  /** 跳转到指定页面 */
  pushUrl(url: string, params?: Object): Promise<void> {
    const opts: router.RouterOptions = { url: url }
    if (params !== undefined) {
      opts.params = params
    }
    return this.require().pushUrl(opts)
  }

  /** 替换当前页为指定页面 */
  replaceUrl(url: string, params?: Object): Promise<void> {
    const opts: router.RouterOptions = { url: url }
    if (params !== undefined) {
      opts.params = params
    }
    return this.require().replaceUrl(opts)
  }

  /** 返回上一页 */
  back(): void {
    this.require().back()
  }

  /** 路由栈是否可后退（index > 0 时可 router.back 触发系统侧滑转场） */
  canGoBack(): boolean {
    try {
      return this.require().getState().index > 0
    } catch (_err) {
      return false
    }
  }

  /** 当前路由页名称（如 pages/BrowsePage） */
  getCurrentPageName(): string {
    try {
      return this.require().getState().name ?? ''
    } catch (_err) {
      return ''
    }
  }

  /** 读取当前页路由参数 */
  getParams(): Object {
    return this.require().getParams()
  }

  private require(): Router {
    if (this.pageRouter === null) {
      throw new Error('BrowserRouterBridge: Router not bound')
    }
    return this.pageRouter
  }
}
