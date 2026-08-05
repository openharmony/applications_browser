import { Configuration } from '@kit.AbilityKit'
import { uiAppearance } from '@kit.ArkUI'
import { settings } from '@kit.BasicServicesKit'
import { getBrowserContext } from 'common'
import { BrowserLog } from 'common'
import { AppStorageKeys } from 'common'
import { FontScaleService } from './FontScaleService'

/**
 * 系统字体同步。
 * App 声明 fontSizeScale=nonFollowSystem 时 Configuration.fontSizeScale 常固定为 1，
 * 需从 settings / uiAppearance 读取真实系统字号；字重仍可用 Configuration / uiAppearance。
 */
export class SystemFontSync {
  private static settingsObserverRegistered: boolean = false
  private static foregroundApplyTimer: number = -1

  /** 冷启动：写入默认系统比例，避免 AppStorage 空读 */
  static initDefaults(): void {
    AppStorage.setOrCreate(AppStorageKeys.SYSTEM_FONT_SIZE_SCALE, 1)
    AppStorage.setOrCreate(AppStorageKeys.SYSTEM_FONT_WEIGHT_SCALE, 1)
    AppStorage.setOrCreate(AppStorageKeys.FONT_FOREGROUND_TICK, 0)
  }

  /**
   * Ability 回前台后延迟通知浏览页：等 Web 完成 OnWindowShow/OnActive 再应用缩放。
   * 多任务场景下 Router onPageShow 通常不会回调。
   */
  static scheduleForegroundWebZoomApply(): void {
    if (SystemFontSync.foregroundApplyTimer >= 0) {
      clearTimeout(SystemFontSync.foregroundApplyTimer)
      SystemFontSync.foregroundApplyTimer = -1
    }
    SystemFontSync.foregroundApplyTimer = setTimeout((): void => {
      SystemFontSync.foregroundApplyTimer = -1
      const prev = AppStorage.get<number>(AppStorageKeys.FONT_FOREGROUND_TICK) ?? 0
      AppStorage.setOrCreate(AppStorageKeys.FONT_FOREGROUND_TICK, prev + 1)
      BrowserLog.info(`[Font] foreground tick=${prev + 1}`)
    }, 450) as number
  }

  /**
   * 监听 settings FONT_SCALE：系统设置改字号时，即便 Configuration 不通知也能同步。
   * 依赖已 bind 的 UIAbilityContext。
   */
  static registerSettingsObserver(): void {
    if (SystemFontSync.settingsObserverRegistered) {
      return
    }
    const ctx = getBrowserContext()
    if (!ctx) {
      BrowserLog.warn('[Font] registerSettingsObserver skipped: no context')
      return
    }
    try {
      const ok = settings.registerKeyObserver(
        ctx,
        settings.display.FONT_SCALE,
        settings.domainName.USER_PROPERTY,
        (_err) => {
          // 部分机型回调 err.code=802，不影响 getValueSync，仍同步一次
          BrowserLog.info('[Font] settings FONT_SCALE changed')
          SystemFontSync.syncFromConfiguration(ctx.config)
        }
      )
      SystemFontSync.settingsObserverRegistered = ok
      BrowserLog.info(`[Font] registerSettingsObserver ok=${ok}`)
    } catch (err) {
      BrowserLog.warn(`[Font] registerSettingsObserver failed: ${JSON.stringify(err)}`)
    }
  }

  static unregisterSettingsObserver(): void {
    if (!SystemFontSync.settingsObserverRegistered) {
      return
    }
    const ctx = getBrowserContext()
    if (!ctx) {
      return
    }
    try {
      settings.unregisterKeyObserver(ctx, settings.display.FONT_SCALE, settings.domainName.USER_PROPERTY)
    } catch (err) {
      BrowserLog.warn(`[Font] unregisterSettingsObserver failed: ${JSON.stringify(err)}`)
    }
    SystemFontSync.settingsObserverRegistered = false
  }

  /**
   * 从系统配置同步字号/字重。
   * 字号优先 settings.FONT_SCALE，再 uiAppearance，最后 Configuration。
   */
  static syncFromConfiguration(config?: Configuration): void {
    const size = SystemFontSync.resolveSizeScale(config)
    const weight = SystemFontSync.resolveWeightScale(config)
    AppStorage.setOrCreate(AppStorageKeys.SYSTEM_FONT_SIZE_SCALE, size)
    AppStorage.setOrCreate(AppStorageKeys.SYSTEM_FONT_WEIGHT_SCALE, weight)
    BrowserLog.info(`[Font] config raw size=${size} weight=${weight}`)
    FontScaleService.publish('systemConfig', true)
  }

  /** 用户切到「跟随系统」档：再读一次系统比例并刷新 UI */
  static refreshForFollowSystemMode(): void {
    SystemFontSync.syncFromConfiguration(undefined)
    FontScaleService.publish('followSystemSelect', true)
  }

  /** 字号：settings → Appearance → Configuration → 缓存 */
  private static resolveSizeScale(config?: Configuration): number {
    const fromSettings = SystemFontSync.readSettingsFontScale()
    if (fromSettings > 0) {
      return fromSettings
    }
    try {
      const fromAppearance: number = uiAppearance.getFontScale()
      if (typeof fromAppearance === 'number' && Number.isFinite(fromAppearance) && fromAppearance > 0) {
        return fromAppearance
      }
    } catch (err) {
      BrowserLog.warn(`[Font] uiAppearance.getFontScale failed: ${JSON.stringify(err)}`)
    }
    const fromConfig = config?.fontSizeScale
    if (typeof fromConfig === 'number' && Number.isFinite(fromConfig) && fromConfig > 0) {
      return fromConfig
    }
    const prev = AppStorage.get<number>(AppStorageKeys.SYSTEM_FONT_SIZE_SCALE)
    return (typeof prev === 'number' && prev > 0) ? prev : 1
  }

  /**
   * 读取系统设置里的 FONT_SCALE（USER_PROPERTY）。
   * 该值不依赖 app 的 followSystem / nonFollowSystem。
   */
  private static readSettingsFontScale(): number {
    const ctx = getBrowserContext()
    if (!ctx) {
      return 0
    }
    try {
      const raw = settings.getValueSync(
        ctx,
        settings.display.FONT_SCALE,
        '',
        settings.domainName.USER_PROPERTY
      )
      const parsed = Number.parseFloat(`${raw}`)
      if (Number.isFinite(parsed) && parsed > 0) {
        return parsed
      }
    } catch (err) {
      BrowserLog.warn(`[Font] settings FONT_SCALE read failed: ${JSON.stringify(err)}`)
    }
    return 0
  }

  /** 字重：Appearance 与 Configuration 均可；Appearance 优先 */
  private static resolveWeightScale(config?: Configuration): number {
    try {
      const fromAppearance: number = uiAppearance.getFontWeightScale()
      if (typeof fromAppearance === 'number' && Number.isFinite(fromAppearance) && fromAppearance > 0) {
        return fromAppearance
      }
    } catch (err) {
      BrowserLog.warn(`[Font] uiAppearance.getFontWeightScale failed: ${JSON.stringify(err)}`)
    }
    const fromConfig = config?.fontWeightScale
    if (typeof fromConfig === 'number' && Number.isFinite(fromConfig) && fromConfig > 0) {
      return fromConfig
    }
    const prev = AppStorage.get<number>(AppStorageKeys.SYSTEM_FONT_WEIGHT_SCALE)
    return (typeof prev === 'number' && prev > 0) ? prev : 1
  }
}
