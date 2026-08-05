import { BrowserStore } from './BrowserStore'
import { BrowserStrings } from 'common'
import { AppStorageKeys } from 'common'
import { FontScaleService } from './settings/FontScaleService'

/** 浏览器 UI 主题色与动态颜色 getter */
export class BrowserTheme {
  /** 浅色模式页面背景色 */
  static readonly LIGHT_BG: string = '#f4f5f7'
  /** 浅色模式卡片/表面背景色 */
  static readonly LIGHT_SURFACE: string = '#ffffff'
  /** 浅色模式主文字色 */
  static readonly LIGHT_TEXT: string = '#111827'
  /** 浅色模式次级文字色 */
  static readonly LIGHT_TEXT_SECONDARY: string = '#6b7280'
  /** 浅色模式弱化文字色 */
  static readonly LIGHT_TEXT_MUTED: string = '#9ca3af'
  /** 浅色模式主题色 */
  static readonly PRIMARY: string = '#2563eb'
  /** 深色模式主题色 */
  static readonly PRIMARY_DARK: string = '#3b82f6'
  /** 浅色模式主题色浅背景 */
  static readonly PRIMARY_LIGHT: string = 'rgba(37, 99, 235, 0.08)'
  /** 浅色模式边框色 */
  static readonly BORDER: string = 'rgba(17, 24, 39, 0.08)'
  /** 快捷方式 tile 渐变起始色 */
  static readonly TILE_GRADIENT_START: string = '#4d9dff'
  /** 快捷方式 tile 渐变结束色 */
  static readonly TILE_GRADIENT_END: string = '#1a7af5'
  /** 底部导航栏阴影色 */
  static readonly NAV_SHADOW: string = 'rgba(17, 24, 39, 0.1)'
  /** 首页浅色渐变颜色序列（通体淡蓝，搜索区中段统一 #e8f2ff） */
  static readonly HOME_GRADIENT: string[] = ['#d4e8ff', '#dceeff', '#e8f2ff', '#f3f8ff']

  /** 深色模式页面背景色 */
  static readonly DARK_BG: string = '#0f1117'
  /** 深色模式卡片/表面背景色 */
  static readonly DARK_SURFACE: string = '#1a1d26'
  /** 深色模式主文字色 */
  static readonly DARK_TEXT: string = '#f3f4f6'
  /** 深色模式次级文字色 */
  static readonly DARK_TEXT_SECONDARY: string = '#9ca3af'
  /** 深色模式弱化文字色 */
  static readonly DARK_TEXT_MUTED: string = '#6b7280'
  /** 深色模式边框色 */
  static readonly DARK_BORDER: string = 'rgba(243, 244, 246, 0.08)'
  /** 深色模式主题色浅背景 */
  static readonly DARK_PRIMARY_LIGHT: string = 'rgba(59, 130, 246, 0.12)'
  /** 深色模式导航栏背景（半透明） */
  static readonly DARK_NAV_BG: string = 'rgba(26, 29, 38, 0.94)'
  /** 浅色模式导航栏背景（半透明） */
  static readonly LIGHT_NAV_BG: string = 'rgba(255, 255, 255, 0.94)'
  /** 底部导航栏实色背景（不用 blur，避免主题切换视觉不变） */
  static readonly LIGHT_NAV_SOLID: string = '#ffffff'
  static readonly DARK_NAV_SOLID: string = '#1e2128'
  /** 深色模式快捷方式图标背景（浅灰，保证彩色图标可读） */
  static readonly SHORTCUT_ICON_BG_DARK: string = '#e5e7eb'
  /** 深色模式快捷方式图标边框 */
  static readonly SHORTCUT_ICON_BORDER_DARK: string = '#d1d5db'

  /**
   * 浏览器 UI 字号（fp）。
   * 倍率由 FontScaleService 写入 FONT_UI_SCALE；档位切换或系统字体变更时递增 FONT_UI_REV 重建。
   * @deprecated 组件内请用 scaledFp(base, this.fontUiScale) 以保证 @StorageLink 响应式刷新
   */
  static uiFontSize(baseFp: number): number {
    const factor = AppStorage.get<number>(AppStorageKeys.FONT_UI_SCALE) ?? FontScaleService.currentFactor()
    return BrowserTheme.scaledFp(baseFp, factor)
  }

  /** 按倍率计算 fp 字号；factor 须来自组件 @StorageLink(FONT_UI_SCALE) */
  static scaledFp(baseFp: number, factor: number): number {
    const f = factor > 0 ? factor : 1
    return Math.max(1, Math.round(baseFp * f))
  }

  /**
   * 浏览器 UI 字重：在基准字重上随系统 fontWeightScale 加粗。
   */
  static uiFontWeight(base: FontWeight): FontWeight {
    const scale = AppStorage.get<number>(AppStorageKeys.SYSTEM_FONT_WEIGHT_SCALE) ?? 1
    if (scale <= 1.05) {
      return base
    }
    if (scale < 1.2) {
      if (base === FontWeight.Lighter || base === FontWeight.Regular) {
        return FontWeight.Medium
      }
      return base
    }
    if (base === FontWeight.Lighter || base === FontWeight.Regular || base === FontWeight.Medium) {
      return FontWeight.Bold
    }
    return base
  }

  /** 底部导航栏实色背景 */
  static navBgSolid(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_NAV_SOLID : BrowserTheme.LIGHT_NAV_SOLID
  }

  /** 当前主题下的导航栏背景色（半透明） */
  static navBg(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_NAV_BG : BrowserTheme.LIGHT_NAV_BG
  }
  /** 当前主题下的导航选中项背景 */
  static navActiveBg(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_PRIMARY_LIGHT : BrowserTheme.PRIMARY_LIGHT
  }

  /** 当前主题下的边框色 */
  static borderColor(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_BORDER : BrowserTheme.BORDER
  }

  /** 当前主题下的主题色 */
  static primaryColor(isDark: boolean): string {
    return isDark ? BrowserTheme.PRIMARY_DARK : BrowserTheme.PRIMARY
  }

  /** 当前主题下的弱化文字色 */
  static textMuted(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_TEXT_MUTED : BrowserTheme.LIGHT_TEXT_MUTED
  }

  /** 当前主题下的主文字色 */
  static text(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_TEXT : BrowserTheme.LIGHT_TEXT
  }

  /** 当前主题下的次级文字色 */
  static textSecondary(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_TEXT_SECONDARY : BrowserTheme.LIGHT_TEXT_SECONDARY
  }

  /** 当前主题下的页面背景色 */
  static bg(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  /** 当前主题下的卡片/表面背景色 */
  static surface(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_SURFACE : BrowserTheme.LIGHT_SURFACE
  }

  /** 当前主题下的主题色浅背景 */
  static primaryLight(isDark: boolean): string {
    return isDark ? BrowserTheme.DARK_PRIMARY_LIGHT : BrowserTheme.PRIMARY_LIGHT
  }

  /** 深色模式下快捷方式图标背景 */
  static shortcutIconBg(isDark: boolean): string {
    return isDark ? BrowserTheme.SHORTCUT_ICON_BG_DARK : BrowserTheme.LIGHT_SURFACE
  }

  /** 深色模式下快捷方式图标边框 */
  static shortcutIconBorder(isDark: boolean): string {
    return isDark ? BrowserTheme.SHORTCUT_ICON_BORDER_DARK : BrowserTheme.BORDER
  }

  /** 当前主题下的导航栏背景色 */
  static get NAV_BG(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_NAV_BG : BrowserTheme.LIGHT_NAV_BG
  }

  /** 当前主题下的导航选中项背景 */
  static get NAV_ACTIVE_BG(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_PRIMARY_LIGHT : BrowserTheme.PRIMARY_LIGHT
  }

  /** 当前主题下的边框色 */
  static get BORDER_COLOR(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_BORDER : BrowserTheme.BORDER
  }
  /** 当前主题下的页面背景色 */
  static get BG(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  /** 当前主题下的卡片/表面背景色 */
  static get SURFACE(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_SURFACE : BrowserTheme.LIGHT_SURFACE
  }

  /** 当前主题下的主文字色 */
  static get TEXT(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_TEXT : BrowserTheme.LIGHT_TEXT
  }

  /** 当前主题下的次级文字色 */
  static get TEXT_SECONDARY(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_TEXT_SECONDARY : BrowserTheme.LIGHT_TEXT_SECONDARY
  }

  /** 当前主题下的弱化文字色 */
  static get TEXT_MUTED(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.DARK_TEXT_MUTED : BrowserTheme.LIGHT_TEXT_MUTED
  }

  /** 当前主题下的主题色 */
  static get PRIMARY_COLOR(): string {
    return BrowserStore.isDarkMode() ? BrowserTheme.PRIMARY_DARK : BrowserTheme.PRIMARY
  }

  /**
   * 获取首页背景渐变色标。
   * isDark 为可选入参——若传入，则用入参决定（与 build 中的 this.isDarkMode() 同源，触发响应式刷新）；
   * 若不传则回退到 BrowserStore.isDarkMode()（仅 build 外一次性调用使用）。
   */
  static homeGradientColors(isDark?: boolean): Array<[ResourceColor, number]> {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    if (dark) {
      return [['#1a2744', 0.0], ['#161f36', 0.22], ['#121828', 0.52], [BrowserTheme.DARK_BG, 1.0]]
    }
    return [['#d4e8ff', 0.0], ['#dceeff', 0.28], ['#e8f2ff', 0.48], ['#e8f2ff', 0.62], ['#eef5ff', 0.82], ['#f3f8ff', 1.0]]
  }

  /** 搜索框附近统一底色（与渐变中段、截断柔边一致） */
  static homeMidFillColor(isDark?: boolean): string {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    return dark ? '#121828' : '#e8f2ff'
  }

  /** 水面倒影区水色渐变：近水面透出倒影，向下溶入统一中段水色 */
  static homeBgReflectionColors(isDark?: boolean): Array<[ResourceColor, number]> {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    if (dark) {
      return [
        ['rgba(26, 39, 68, 0.06)', 0.0],
        ['rgba(22, 31, 54, 0.14)', 0.45],
        ['rgba(18, 24, 40, 0.28)', 1.0]
      ]
    }
    return [
      ['rgba(232, 242, 255, 0.04)', 0.0],
      ['rgba(232, 242, 255, 0.12)', 0.4],
      ['rgba(232, 242, 255, 0.22)', 0.75],
      ['rgba(232, 242, 255, 0.32)', 1.0]
    ]
  }

  /**
   * 深色倒影区内左右渐隐：边缘盖住硬白边，向中心透明透出倒影（更宽更柔）。
   */
  static homeBgReflectionInAreaFadeColors(): Array<[ResourceColor, number]> {
    const edge: string = 'rgba(18, 24, 40, 0.9)'
    const near: string = 'rgba(18, 24, 40, 0.55)'
    const mid: string = 'rgba(18, 24, 40, 0.22)'
    return [
      [edge, 0.0],
      [near, 0.1],
      [mid, 0.22],
      ['rgba(18, 24, 40, 0.06)', 0.34],
      ['rgba(18, 24, 40, 0)', 0.42],
      ['rgba(18, 24, 40, 0)', 0.58],
      ['rgba(18, 24, 40, 0.06)', 0.66],
      [mid, 0.78],
      [near, 0.9],
      [edge, 1.0]
    ]
  }

  /** 深色倒影区内上下渐隐：近水面保留，向下加速溶入背景 */
  static homeBgReflectionInAreaVerticalFadeColors(): Array<[ResourceColor, number]> {
    return [
      ['rgba(18, 24, 40, 0)', 0.0],
      ['rgba(18, 24, 40, 0.04)', 0.25],
      ['rgba(18, 24, 40, 0.16)', 0.55],
      ['rgba(18, 24, 40, 0.4)', 0.78],
      ['rgba(18, 24, 40, 0.72)', 1.0]
    ]
  }

  /** 近水面高光：模拟光在水面上的反射带 */
  static homeBgReflectionSheenColors(isDark?: boolean): Array<[ResourceColor, number]> {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    if (dark) {
      return [
        ['rgba(180, 200, 255, 0.14)', 0.0],
        ['rgba(120, 150, 220, 0.05)', 0.55],
        ['rgba(15, 17, 23, 0)', 1.0]
      ]
    }
    return [
      ['rgba(255, 255, 255, 0.35)', 0.0],
      ['rgba(232, 242, 255, 0.16)', 0.4],
      ['rgba(232, 242, 255, 0)', 1.0]
    ]
  }

  /** 倒影下部：轻柔溶入中段水色，避免截断处发灰发深 */
  static homeBgReflectionDepthColors(isDark?: boolean): Array<[ResourceColor, number]> {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    if (dark) {
      return [
        ['rgba(18, 24, 40, 0)', 0.0],
        ['rgba(18, 24, 40, 0.18)', 0.55],
        ['rgba(18, 24, 40, 0.28)', 1.0]
      ]
    }
    return [
      ['rgba(232, 242, 255, 0)', 0.0],
      ['rgba(232, 242, 255, 0.2)', 0.5],
      ['rgba(232, 242, 255, 0.38)', 1.0]
    ]
  }

  /** 截断线附近短柔边：溶入统一中段色，消除硬边 */
  static homeBgClipEdgeFadeColors(isDark?: boolean): Array<[ResourceColor, number]> {
    const mid = BrowserTheme.homeMidFillColor(isDark)
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    if (dark) {
      return [
        ['rgba(18, 24, 40, 0)', 0.0],
        ['rgba(18, 24, 40, 0.45)', 0.55],
        [mid, 1.0]
      ]
    }
    return [
      ['rgba(232, 242, 255, 0)', 0.0],
      ['rgba(232, 242, 255, 0.55)', 0.5],
      [mid, 1.0]
    ]
  }

  /** 水面分界柔光：左右淡出，避免硬亮线突兀 */
  static homeBgHorizonLineColors(isDark?: boolean): Array<[ResourceColor, number]> {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    if (dark) {
      return [
        ['rgba(160, 190, 255, 0)', 0.0],
        ['rgba(160, 190, 255, 0.12)', 0.2],
        ['rgba(180, 205, 255, 0.22)', 0.5],
        ['rgba(160, 190, 255, 0.12)', 0.8],
        ['rgba(160, 190, 255, 0)', 1.0]
      ]
    }
    return [
      ['rgba(255, 255, 255, 0)', 0.0],
      ['rgba(255, 255, 255, 0.22)', 0.2],
      ['rgba(255, 255, 255, 0.4)', 0.5],
      ['rgba(255, 255, 255, 0.22)', 0.8],
      ['rgba(255, 255, 255, 0)', 1.0]
    ]
  }

  /** 将 #rrggbb 转为系统栏 API 所需的 #AARRGGBB；已为 8 位 hex 则原样返回 */
  static systemBarArgb(color: string): string {
    const hex = color.trim()
    if (hex.length === 9 && hex.startsWith('#')) {
      return hex.toUpperCase()
    }
    if (hex.length === 7 && hex.startsWith('#')) {
      return `#FF${hex.substring(1).toUpperCase()}`
    }
    return BrowserTheme.systemBarArgb(BrowserTheme.LIGHT_BG)
  }

  /** 首页/状态栏下方避让区顶色，与 homeGradientColors 起点一致 */
  static topEdgeColor(isDark?: boolean): string {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    return dark ? '#1a2744' : '#d4e8ff'
  }

  /** 首页渐变底端色，与 MainPage 底区、系统导航条避让区对齐 */
  static bottomEdgeColor(isDark?: boolean): string {
    const dark = isDark === undefined ? BrowserStore.isDarkMode() : isDark
    return dark ? BrowserTheme.DARK_BG : '#f3f8ff'
  }

  /** 获取无痕模式首页背景渐变色标 */
  static incognitoHomeGradientColors(): Array<[ResourceColor, number]> {
    return [['#0f1a28', 0.0], ['#121820', 0.35], ['#0a0a0a', 1.0]]
  }

  /** 无痕模式下地址导航栏背景色（强制黑色） */
  static readonly INCOGNITO_NAV_BG: string = '#000000'

  /** 无痕模式下地址输入框内部背景色（深灰，避免纯黑过硬） */
  static readonly INCOGNITO_ADDRESS_BG: string = '#1f2329'
}
