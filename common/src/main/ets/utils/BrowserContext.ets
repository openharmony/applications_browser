import { common } from '@kit.AbilityKit'
import { BrowserRouterBridge } from './BrowserRouterBridge'

/** UIAbility 上下文持有者，避免 BrowserStrings 与 BrowserStore 循环依赖 */
let abilityContext: common.UIAbilityContext | null = null
/** 当前活跃页面的 UIContext（截图等 UI 能力，由 @Entry 页绑定） */
let pageUIContext: UIContext | null = null

/** 绑定 UIAbility 上下文（EntryAbility.onCreate 调用） */
export function bindBrowserContext(context: common.UIAbilityContext): void {
  abilityContext = context
}

/** 获取已绑定的 UIAbility 上下文 */
export function getBrowserContext(): common.UIAbilityContext | null {
  return abilityContext
}

/** 绑定当前页面 UIContext 与 Router（@Entry 页生命周期内调用） */
export function bindBrowserPageContext(ctx: UIContext): void {
  pageUIContext = ctx
  BrowserRouterBridge.getInstance().bind(ctx.getRouter())
}

/** 获取已绑定的 UIContext */
export function getBrowserUIContext(): UIContext | null {
  return pageUIContext
}
