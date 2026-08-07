import { Configuration, ConfigurationConstant } from '@kit.AbilityKit'
import { BrowserLog } from 'common'
import { BrowserStrings } from 'common'
import { BrowserStore } from '../BrowserStore'
import { AppStorageKeys } from 'common'
import { BrowserWindowService } from './BrowserWindowService'

/** 系统深色模式 → AppStorage 有效主题；偏好为 system 时随 Configuration.colorMode 变化 */
export class SystemThemeSync {
  /** 从 Configuration 同步系统 colorMode（启动、onConfigurationUpdate、environment） */
  static syncFromConfiguration(config: Configuration | undefined): void {
    if (!SystemThemeSync.isFollowSystemMode()) {
      return
    }
    SystemThemeSync.applyEffectiveFromConfig(config, 'systemConfig')
  }

  /** 用户选择「跟随系统」时立即按当前系统 colorMode 刷新 */
  static refreshForFollowSystemMode(): void {
    const ctx = BrowserStore.getContext()
    SystemThemeSync.applyEffectiveFromConfig(ctx?.config, 'followSystemSelect')
  }

  /** 当前偏好是否为跟随系统 */
  static isFollowSystemMode(): boolean {
    const raw = AppStorage.get<string>(AppStorageKeys.THEME_PREFERENCE) ?? 'light'
    return BrowserStrings.normalizeThemeModeKey(raw) === 'system'
  }

  /** 读取系统 colorMode 是否为深色 */
  static isSystemDark(config?: Configuration): boolean {
    const cm = config?.colorMode ?? BrowserStore.getContext()?.config?.colorMode
    return cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }

  /** 根据偏好与系统配置解析当前是否应显示深色 UI */
  static resolveEffectiveDark(preference: string, config?: Configuration): boolean {
    const pref = BrowserStrings.normalizeThemeModeKey(preference)
    if (pref === 'system') {
      return SystemThemeSync.isSystemDark(config)
    }
    return pref === 'dark'
  }

  /** 应用主题偏好：更新有效 theme、系统 colorMode 与状态栏 */
  static applyPreference(preference: string, config?: Configuration): void {
    const pref = BrowserStrings.normalizeThemeModeKey(preference)
    AppStorage.setOrCreate(AppStorageKeys.THEME_PREFERENCE, pref)
    const dark = SystemThemeSync.resolveEffectiveDark(pref, config)
    AppStorage.set(AppStorageKeys.THEME, dark ? 'dark' : 'light')
    AppStorage.set(AppStorageKeys.NIGHT_MODE, dark)
    BrowserWindowService.getInstance().syncColorModeForPreference(pref, dark, BrowserStore.getContext())
    BrowserLog.info(`[Theme] applyPreference pref=${pref} effective=${dark ? 'dark' : 'light'}`)
  }

  private static applyEffectiveFromConfig(config: Configuration | undefined, source: string): void {
    const prevDark = (AppStorage.get<string>(AppStorageKeys.THEME) ?? 'light') === 'dark'
    const dark = SystemThemeSync.isSystemDark(config)
    if (prevDark === dark) {
      return
    }
    AppStorage.set(AppStorageKeys.THEME, dark ? 'dark' : 'light')
    AppStorage.set(AppStorageKeys.NIGHT_MODE, dark)
    const rev = (AppStorage.get<number>(AppStorageKeys.THEME_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.THEME_REV, rev)
    // 仅更新状态栏，禁止 setColorMode（会触发 configuration 回调形成闪烁死循环）
    BrowserWindowService.getInstance().syncSystemBarForTheme(dark, BrowserStore.getContext(), true)
    BrowserLog.info(`[Theme] ${source} systemDark=${dark} rev=${rev}`)
  }
}
