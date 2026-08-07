import { BrowserTheme } from 'browser_core'
import { HistorySiteIconService } from 'browser_core'
import { TabSession } from 'common'
import { TAB_LIMIT_DISPLAY } from 'common'

const ENGINE_BLUE: string = '#2932e1'
/** 服务开关选中：高对比蓝（与标签管理选中态一致） */
export const SERVICE_TOGGLE_ON_COLOR: string = '#0A59F7'
/** 服务开关非选中图标：与设置入口蓝色一致 */
export const SERVICE_TOGGLE_OFF_COLOR: string = BrowserTheme.PRIMARY
export const SERVICE_TOGGLE_OFF_COLOR_DARK: string = BrowserTheme.PRIMARY_DARK
/** 标签管理切换器：选中态蓝色 */
export const TAB_SWITCH_ACTIVE_COLOR: string = '#0A59F7'
/** 标签管理切换器：未选中态浅蓝色 */
export const TAB_SWITCH_INACTIVE_COLOR: string = '#65A9FF'

/** 常用服务 / 统计入口图标底：与书签、历史、下载统一（系统强调色 10% 透明度） */
export function serviceTileBgDefault(): ResourceColor {
  return $r('sys.color.comp_emphasize_tertiary')
}

/** 常用服务选中态图标底（系统强调色 20% 透明度，深浅色自动适配） */
export function serviceTileBgSelected(): ResourceColor {
  return $r('sys.color.comp_emphasize_secondary')
}

/** 图标色：选中高对比蓝；非选中为设置蓝 */
export function serviceToggleIconColor(isOn: boolean, isDark: boolean = false): ResourceColor {
  if (isOn) {
    return SERVICE_TOGGLE_ON_COLOR
  }
  return isDark ? SERVICE_TOGGLE_OFF_COLOR_DARK : SERVICE_TOGGLE_OFF_COLOR
}

/**
 * 文案色：选中高对比蓝；
 * 非选中为次要文字色（与常用功能书签/历史/下载文案一致）
 */
export function serviceToggleLabelColor(isOn: boolean, isDark: boolean = false): string {
  if (isOn) {
    return SERVICE_TOGGLE_ON_COLOR
  }
  return isDark ? BrowserTheme.DARK_TEXT_SECONDARY : BrowserTheme.LIGHT_TEXT_SECONDARY
}

/** 兼容旧调用：等同图标色 */
export function serviceToggleTextColor(isOn: boolean, isDark: boolean = false): ResourceColor {
  return serviceToggleIconColor(isOn, isDark)
}

/** 图标底：选中蓝底更明显；非选中与三标签统一 */
export function serviceToggleTileBg(isOn: boolean, isDark: boolean = false): ResourceColor {
  if (isOn) {
    return isDark ? 'rgba(59, 130, 246, 0.22)' : 'rgba(10, 89, 247, 0.14)'
  }
  return serviceTileBgDefault()
}

/** 子页顶栏返回：sys.symbol.chevron_left */
@Component
export struct PanelBackChevronIcon {
  @Prop color: string = '#111827'
  @Prop boxSize: number = 18

  build() {
    SymbolGlyph($r('sys.symbol.chevron_left'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 顶栏圆形按钮内搜索图标：sys.symbol.magnifyingglass */
@Component
export struct PanelHeaderSearchIcon {
  @Prop color: string = '#6b7280'
  @Prop boxSize: number = 17

  build() {
    SymbolGlyph($r('sys.symbol.magnifyingglass'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 顶栏圆钮内图标统一尺寸（与 PanelHeaderCloseIcon 叉号一致） */
export const PANEL_HEADER_ICON_BOX_SIZE: number = 18
export const PANEL_HEADER_ICON_STROKE: number = 1.5
/** 叉号横条长度 = boxSize * INNER_ARM_RATIO */
export const PANEL_HEADER_ICON_INNER_ARM_RATIO: number = 0.62

/** 顶栏圆形按钮内关闭图标：sys.symbol.xmark */
@Component
export struct PanelHeaderCloseIcon {
  @Prop color: string = '#111827'
  @Prop boxSize: number = PANEL_HEADER_ICON_BOX_SIZE

  build() {
    SymbolGlyph($r('sys.symbol.xmark'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 顶栏圆形按钮内确认图标：sys.symbol.checkmark */
@Component
export struct PanelHeaderConfirmIcon {
  @Prop color: ResourceColor = $r('sys.color.ohos_id_color_emphasize')
  @Prop boxSize: number = PANEL_HEADER_ICON_BOX_SIZE

  build() {
    SymbolGlyph($r('sys.symbol.checkmark'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 顶栏圆形按钮内更多图标：sys.symbol.dot_grid_2x2 */
@Component
export struct PanelHeaderMoreIcon {
  @Prop color: string = '#6b7280'
  @Prop boxSize: number = 17

  build() {
    SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 无痕模式图标（与「我的常用服务」一致） */
@Component
export struct IncognitoServiceIcon {
  @Prop iconSize: number = 22
  @Prop showTile: boolean = true
  @StorageLink('browser_incognito') isIncognito: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'

  private tintColor(): ResourceColor {
    return serviceToggleIconColor(this.isIncognito, this.theme === 'dark')
  }

  private tileBg(): ResourceColor {
    return serviceToggleTileBg(this.isIncognito, this.theme === 'dark')
  }

  build() {
    Column() {
      Image($r('app.media.ic_incognito_mono'))
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.tintColor())
        .objectFit(ImageFit.Contain)
    }
    .width(this.showTile ? 36 : this.iconSize)
    .height(this.showTile ? 36 : this.iconSize)
    .backgroundColor(this.showTile ? this.tileBg() : Color.Transparent)
    .borderRadius(this.showTile ? 10 : 0)
    .justifyContent(FlexAlign.Center)
  }
}

/** 服务开关项（图标 + 文字同一组件内绑定 AppStorage，保证同步变色） */
@Component
export struct ServiceToggleItem {
  /** 服务类型：incognito / dark */
  @Prop serviceKind: string = 'incognito'
  @Prop label: string = ''
  onTap?: () => void

  @StorageLink('browser_incognito') isIncognito: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'

  private isOn(): boolean {
    if (this.serviceKind === 'incognito') {
      return this.isIncognito
    }
    return this.theme === 'dark'
  }

  private iconResource(): Resource {
    if (this.serviceKind === 'incognito') {
      return $r('app.media.ic_incognito_mono')
    }
    return $r('app.media.ic_dark_mode')
  }

  private iconColor(): ResourceColor {
    return serviceToggleIconColor(this.isOn(), this.theme === 'dark')
  }

  private labelColor(): string {
    return serviceToggleLabelColor(this.isOn(), this.theme === 'dark')
  }

  private tileBg(): ResourceColor {
    return serviceToggleTileBg(this.isOn(), this.theme === 'dark')
  }

  build() {
    Column({ space: 7 }) {
      if (this.serviceKind === 'incognito') {
        IncognitoServiceIcon()
      } else {
        Column() {
          Image(this.iconResource())
            .width(22)
            .height(22)
            .fillColor(this.iconColor())
            .objectFit(ImageFit.Contain)
        }
        .width(36)
        .height(36)
        .backgroundColor(this.tileBg())
        .borderRadius(10)
        .justifyContent(FlexAlign.Center)
      }

      Text(this.label)
        .fontSize(11)
        .fontColor(this.labelColor())
        .fontWeight(FontWeight.Medium)
    }
    .onClick(() => {
      this.onTap?.()
    })
  }
}

/** 浏览页底栏导航图标尺寸（较原 Unicode 17fp 略大，笔划加粗） */
export const BROWSE_TOOLBAR_ICON_BOX: number = 30
export const BROWSE_TOOLBAR_ICON_STROKE: number = 2.85

const BROWSE_CHEVRON_BASE_BOX: number = 18
const BROWSE_BACK_CHEVRON_POINTS: number[][] = [
  [10.65, 13.95],
  [5.7, 9],
  [10.65, 4.05],
  [9.6, 3],
  [3.75, 9],
  [9.6, 15]
]

/** 缩放 PanelBackChevron 路径；forward 为 true 时水平镜像为右向箭头 */
function browseToolbarChevronPoints(boxSize: number, forward: boolean): number[][] {
  const scale = boxSize / BROWSE_CHEVRON_BASE_BOX
  const points: number[][] = []
  for (let i = 0; i < BROWSE_BACK_CHEVRON_POINTS.length; i++) {
    const px = BROWSE_BACK_CHEVRON_POINTS[i][0] * scale
    const py = BROWSE_BACK_CHEVRON_POINTS[i][1] * scale
    points.push(forward ? [boxSize - px, py] : [px, py])
  }
  return points
}

/** 与 PanelBackChevronIcon 一致：左箭头右移、右箭头左移，在底栏格内视觉居中 */
function browseToolbarChevronNudge(boxSize: number, forward: boolean): number {
  const nudge = 1.5 * (boxSize / BROWSE_CHEVRON_BASE_BOX)
  return forward ? -nudge : nudge
}

/** 浏览页底栏：返回 — sys.symbol.chevron_left */
@Component
export struct BrowseToolbarBackIcon {
  @Prop color: string = '#111827'
  @Prop boxSize: number = BROWSE_TOOLBAR_ICON_BOX

  build() {
    SymbolGlyph($r('sys.symbol.chevron_left'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 浏览页底栏：前进 Chevron（闭合多边形，右向镜像） */
@Component
export struct BrowseToolbarForwardIcon {
  @Prop color: string = '#111827'
  @Prop boxSize: number = BROWSE_TOOLBAR_ICON_BOX

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Polygon({ width: this.boxSize, height: this.boxSize })
        .points(browseToolbarChevronPoints(this.boxSize, true))
        .fill(this.color)
        .translate({ x: browseToolbarChevronNudge(this.boxSize, true), y: 0 })
    }
    .width(this.boxSize)
    .height(this.boxSize)
  }
}

/** 浏览页底栏：更多菜单 — sys.symbol.dot_grid_2x2 */
@Component
export struct BrowseToolbarMoreIcon {
  @Prop color: string = '#111827'
  @Prop boxSize: number = BROWSE_TOOLBAR_ICON_BOX

  build() {
    SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
      .fontSize(this.boxSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

/** 浏览页底栏：下载进行中 — 环形进度 + 中心下载图标 */
@Component
export struct BrowseToolbarDownloadProgressIcon {
  @Prop boxSize: number = BROWSE_TOOLBAR_ICON_BOX
  @Prop progress: number = 0
  @Prop isDark: boolean = false
  /** queued 等尚无进度数字时为 true，显示最小弧 + 呼吸动画 */
  @Prop indeterminate: boolean = false
  /** toolbar=底栏黑色；accent=更多页等服务入口蓝色 */
  @Prop variant: 'toolbar' | 'accent' = 'toolbar'
  /** variant=toolbar 时传入，与底栏其它图标颜色一致 */
  @Prop iconColor: string = ''

  private clampedProgress(): number {
    return Math.min(100, Math.max(0, Math.floor(this.progress)))
  }

  /** 环形进度展示值：0% 时保留最小可见弧，避免「看不出在下载」 */
  private ringProgress(): number {
    const pct = this.clampedProgress()
    if (pct > 0) {
      return pct
    }
    return this.indeterminate ? 18 : 12
  }

  private trackColor(): string {
    return this.isDark ? '#3D4552' : '#E5E8EC'
  }

  private resolvedAccentColor(): ResourceColor {
    return SERVICE_TOGGLE_ON_COLOR
  }

  private resolvedIconColor(): ResourceColor {
    if (this.variant === 'accent') {
      return this.resolvedAccentColor()
    }
    if (this.iconColor.trim().length > 0) {
      return this.iconColor
    }
    return this.isDark ? '#E8EAED' : '#111827'
  }

  private ringActiveColor(): ResourceColor {
    return this.variant === 'accent' ? this.resolvedAccentColor() : this.resolvedIconColor()
  }

  private innerIconSize(): number {
    return this.boxSize * 0.52
  }

  private ringStroke(): number {
    return Math.max(2, Math.floor(this.boxSize * 0.09))
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: this.ringProgress(), total: 100, type: ProgressType.Ring })
        .width(this.boxSize)
        .height(this.boxSize)
        .color(this.ringActiveColor())
        .backgroundColor(this.trackColor())
        .style({ strokeWidth: this.ringStroke() })

      Image($r('app.media.ic_download_toolbar'))
        .width(this.innerIconSize())
        .height(this.innerIconSize())
        .fillColor(this.resolvedIconColor())
        .objectFit(ImageFit.Contain)
    }
    .width(this.boxSize)
    .height(this.boxSize)
  }
}

@Component
export struct NavHomeIcon {
  @Prop color: string = BrowserTheme.PRIMARY
  @Prop iconSize: number = 22

  build() {
    Image($r('app.media.ic_home'))
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }
}

/** 底部/首页标签入口数量徽章（与当前无痕分区计数一致） */
@Component
export struct TabCountBadge {
  @Prop boxSize: number = 22
  @Prop fontSize: number = 11
  @Prop frameStroke: number = 1.5
  @Prop cornerRadius: number = 5
  @Prop useTotalCount: boolean = false
  @StorageLink('browser_tabs') tabs: TabSession[] = []
  /** 与 TabsPage 一致：仅靠 tabs 数组替换时冷启动/后台重建常不触发重绘 */
  @StorageLink('browser_tabs_rev') tabsRev: number = 0
  @StorageLink('browser_incognito') isIncognito: boolean = false
  @StorageLink('browser_theme') theme: string = 'light'
  @StorageLink('browser_font_ui_rev') fontUiRev: number = 0

  private isDark(): boolean {
    return this.theme === 'dark'
  }

  private displayCount(): number {
    const raw = this.useTotalCount ?
      this.tabs.length :
      this.tabs.filter((t) => this.isIncognito ? t.isIncognito : !t.isIncognito).length
    return Math.min(raw, TAB_LIMIT_DISPLAY)
  }

  private badgeFontSize(): number {
    const base = this.displayCount() >= 10 ? Math.max(9, this.fontSize - 1) : this.fontSize
    return BrowserTheme.uiFontSize(base)
  }

  build() {
    Column() {
      Text(this.displayCount().toString())
        .fontSize(this.badgeFontSize())
        .fontWeight(FontWeight.Medium)
        .fontColor(BrowserTheme.text(this.isDark()))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .textOverflow({ overflow: TextOverflow.Clip })
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .border({ width: this.frameStroke, color: BrowserTheme.text(this.isDark()) })
    .borderRadius(this.cornerRadius)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .clip(true)
    // tabsRev 变化时强制重建，避免 rebuild 期间 markNeedUpdate 被丢弃导致数字卡住
    .key(`tab-count-${this.tabsRev}-${this.displayCount()}-${this.fontUiRev}`)
  }
}

@Component
export struct NavProfileIcon {
  @Prop color: string = BrowserTheme.PRIMARY

  build() {
    Stack() {
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .border({ width: 1.75, color: this.color })
      Text('+')
        .fontSize(9)
        .fontColor(this.color)
        .position({ x: 9, y: -1 })
      Text('+')
        .fontSize(9)
        .fontColor(this.color)
        .position({ x: 9, y: 13 })
      Text('+')
        .fontSize(9)
        .fontColor(this.color)
        .position({ x: -1, y: 6 })
      Text('+')
        .fontSize(9)
        .fontColor(this.color)
        .position({ x: 19, y: 6 })
    }
    .width(22)
    .height(22)
  }
}

/** 收藏星标颜色（空心 / 实心一致） */
export const BOOKMARK_STAR_COLOR: string = '#F5A623'

@Component
export struct StarBookmarkIcon {
  @Prop bookmarked: boolean = false
  @Prop color: string = BOOKMARK_STAR_COLOR
  @Prop iconSize: number = 20

  build() {
    Image(this.bookmarked ? $r('app.media.ic_star_filled') : $r('app.media.ic_star_outline'))
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }
}

@Component
export struct TileBookmarkIcon {
  @Prop iconSize: number = 26

  build() {
    Image($r('app.media.ic_bookmark'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}

@Component
export struct TileHistoryIcon {
  @Prop iconSize: number = 26

  build() {
    Image($r('app.media.ic_history'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}

@Component
export struct TileDownloadIcon {
  @Prop iconSize: number = 26

  build() {
    Image($r('app.media.ic_download'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}

@Component
export struct StatBookmarkIcon {
  build() {
    Column() {
      Image($r('app.media.ic_bookmark'))
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
    }
    .width(36)
    .height(36)
    .backgroundColor(serviceTileBgDefault())
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct StatHistoryIcon {
  build() {
    Column() {
      Image($r('app.media.ic_history'))
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
    }
    .width(36)
    .height(36)
    .backgroundColor(serviceTileBgDefault())
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct StatDownloadIcon {
  build() {
    Column() {
      Image($r('app.media.ic_download'))
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
    }
    .width(36)
    .height(36)
    .backgroundColor(serviceTileBgDefault())
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
  }
}

/** 模块图标资源映射（对应 docs/icons 设计稿） */
function moduleIconResource(tile: string): Resource {
  if (tile === 'history') {
    return $r('app.media.ic_history')
  }
  if (tile === 'download') {
    return $r('app.media.ic_download')
  }
  return $r('app.media.ic_bookmark')
}

@Component
export struct SettingsListIcon {
  build() {
    SymbolGlyph($r('sys.symbol.gearshape'))
      .fontSize(18)
      .fontColor([BrowserTheme.PRIMARY])
  }
}

@Component
export struct AboutListIcon {
  build() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(18)
        .fontColor([BrowserTheme.PRIMARY])
    }
    .width(34)
    .height(34)
    .backgroundColor(serviceTileBgDefault())
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct ShortcutTileIcon {
  @Prop tile: string = 'bookmark'
  @Prop iconSize: number = 26

  build() {
    Image(moduleIconResource(this.tile))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}

/** 站点品牌图标资源映射 */
function siteIconResource(media: string): Resource {
  if (media === 'quark') {
    return $r('app.media.ic_shortcut_quark')
  }
  if (media === '360') {
    return $r('app.media.ic_shortcut_360')
  }
  return $r('app.media.ic_shortcut_baidu')
}

@Component
export struct ShortcutEngineIcon {
  @Prop text: string = 'du'
  @Prop iconMedia: string = ''
  @Prop iconSize: number = 32

  build() {
    if (this.iconMedia.length > 0) {
      Image(siteIconResource(this.iconMedia))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
    } else {
      SymbolGlyph($r('sys.symbol.worldclock'))
        .fontSize(Math.max(14, this.iconSize * 0.55))
        .fontColor([ENGINE_BLUE])
    }
  }
}

/** 历史/书签/标签卡片左侧站点预览图标（本地 favicon → worldclock 兜底） */
@Component
export struct HistorySiteIcon {
  @Prop @Watch('onIconPropsChanged') url: string = ''
  @Prop @Watch('onIconPropsChanged') iconUrl: string = ''
  @Prop boxSize: number = 32
  @State private useFallback: boolean = false

  private onIconPropsChanged(): void {
    this.useFallback = false
  }

  private localDisplayUri(): string {
    const svc: HistorySiteIconService = HistorySiteIconService.getInstance()
    const fromStored: string = svc.resolveLocalDisplayUri(this.iconUrl)
    if (fromStored.length > 0) {
      return fromStored
    }
    return svc.resolveLocalByPageUrl(this.url)
  }

  private iconInnerSize(): number {
    return Math.max(10, this.boxSize - (this.boxSize >= 28 ? 8 : 4))
  }

  private fallbackGlyphSize(): number {
    return Math.max(10, Math.round(this.boxSize * 0.55))
  }

  private tileRadius(): number {
    return this.boxSize >= 28 ? 8 : 4
  }

  @Builder
  FallbackIcon() {
    SymbolGlyph($r('sys.symbol.worldclock'))
      .fontSize(this.fallbackGlyphSize())
      .fontColor([BrowserTheme.PRIMARY_COLOR])
  }

  build() {
    Column() {
      if (!this.useFallback && this.localDisplayUri().length > 0) {
        Image(this.localDisplayUri())
          .key(`history-site-icon-${this.iconUrl}-${this.url}`)
          .width(this.iconInnerSize())
          .height(this.iconInnerSize())
          .objectFit(ImageFit.Contain)
          .borderRadius(Math.max(2, this.tileRadius() - 2))
          .onError(() => {
            this.useFallback = true
          })
      } else {
        this.FallbackIcon()
      }
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(this.tileRadius())
    .backgroundColor(BrowserTheme.PRIMARY_LIGHT)
    .justifyContent(FlexAlign.Center)
    .flexShrink(0)
  }
}

/** 搜索栏前置放大镜（首页 / 搜索态 / 地址栏共用） */
@Component
export struct SearchLeadingIcon {
  @Prop color: string = '#9aa0a6'
  @Prop iconSize: number = 18

  build() {
    SymbolGlyph($r('sys.symbol.magnifyingglass'))
      .fontSize(this.iconSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Regular)
      .flexShrink(0)
  }
}

/** 地址栏编辑态：确认跳转 */
@Component
export struct UrlNavigateConfirmBtn {
  @Prop color: ResourceColor = '#1a73e8'
  @Prop fontSize: number = 18

  build() {
    Text('→')
      .fontSize(this.fontSize)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.color)
      .width(28)
      .height(28)
      .textAlign(TextAlign.Center)
      .flexShrink(0)
  }
}

/** 扫一扫图标（搜索框尾部，直接使用 ic_scan 资源） */
@Component
export struct ScanQrIcon {
  @Prop color: string = '#9aa0a6'
  @Prop iconSize: number = 20

  build() {
    Image($r('app.media.ic_scan'))
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }
}

/** 分享：Material 三点连线 */
@Component
export struct ShareInlineIcon {
  @Prop color: string = BrowserTheme.TEXT
  @Prop iconSize: number = 18

  build() {
    Image($r('app.media.ic_share'))
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }
}

/** 分享（与 ShareInlineIcon 同源，尺寸默认略大） */
@Component
export struct ShareCircleIcon {
  @Prop color: string = BrowserTheme.TEXT
  @Prop iconSize: number = 20

  build() {
    ShareInlineIcon({ color: this.color, iconSize: this.iconSize })
  }
}

/** 搜索历史清空等：sys.symbol.trash */
@Component
export struct TrashClearIcon {
  @Prop color: string = BrowserTheme.TEXT_SECONDARY
  @Prop iconSize: number = 18

  build() {
    SymbolGlyph($r('sys.symbol.trash'))
      .fontSize(this.iconSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }
}

@Component
export struct TabSquareIcon {
  @Prop color: string = BrowserTheme.TEXT

  build() {
    Column()
      .width(14)
      .height(14)
      .borderRadius(2.5)
      .border({ width: 1.75, color: this.color })
  }
}

/** 标签管理顶栏：方框内数字（与设计稿一致） */
@Component
export struct TabSwitchCountBadge {
  @Prop count: number = 0
  @Prop color: string = TAB_SWITCH_ACTIVE_COLOR
  @Prop boxSize: number = 18

  private displayText(): string {
    return Math.min(Math.max(0, this.count), TAB_LIMIT_DISPLAY).toString()
  }

  private badgeFontSize(): number {
    const raw = this.displayText()
    return BrowserTheme.uiFontSize(raw.length >= 2 ? 10 : 12)
  }

  build() {
    Column() {
      Text(this.displayText())
        .fontSize(this.badgeFontSize())
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .textOverflow({ overflow: TextOverflow.Clip })
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .border({ width: 1.6, color: this.color })
    .borderRadius(4)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .clip(true)
  }
}

@Component
export struct IncognitoFootIcon {
  @Prop color: string = TAB_SWITCH_ACTIVE_COLOR

  build() {
    Image($r('app.media.ic_incognito_mono'))
      .width(18)
      .height(18)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }
}

/** 页签管理底栏三按钮统一图标字号（槽位 28） */
const TABS_BOTTOM_ICON_SIZE: number = 22

@Component
export struct TabsBottomTrashIcon {
  /** 可点 / 不可点；颜色随底栏面板深浅（无痕深色底不能用浅色主题的系统文字色） */
  @Prop canUse: boolean = true
  @Prop darkPanel: boolean = false

  private iconColor(): ResourceColor {
    if (this.darkPanel) {
      return this.canUse ? BrowserTheme.text(true) : BrowserTheme.textMuted(true)
    }
    return this.canUse ?
      $r('sys.color.ohos_id_color_text_primary') :
      $r('sys.color.ohos_id_color_text_tertiary')
  }

  build() {
    SymbolGlyph($r('sys.symbol.trash'))
      .fontSize(TABS_BOTTOM_ICON_SIZE)
      .fontColor([this.iconColor()])
      .fontWeight(FontWeight.Medium)
  }
}

/** 圆形加减符号（几何绘制，避免字体基线偏移） */
@Component
export struct CirclePlusMinusIcon {
  @Prop minus: boolean = false
  @Prop color: string = '#ffffff'
  @Prop barLength: number = 10
  @Prop barThickness: number = 1.75

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(this.barLength)
        .height(this.barThickness)
        .backgroundColor(this.color)
        .borderRadius(this.barThickness / 2)
      if (!this.minus) {
        Row()
          .width(this.barThickness)
          .height(this.barLength)
          .backgroundColor(this.color)
          .borderRadius(this.barThickness / 2)
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct TabsBottomPlusIcon {
  @Prop darkMode: boolean = false

  private iconColor(): string {
    return BrowserTheme.text(this.darkMode)
  }

  build() {
    SymbolGlyph($r('sys.symbol.plus'))
      .fontSize(TABS_BOTTOM_ICON_SIZE)
      .fontColor([this.iconColor()])
      .fontWeight(FontWeight.Medium)
  }
}

@Component
export struct TabsBottomBackIcon {
  @Prop darkMode: boolean = false

  private iconColor(): string {
    return BrowserTheme.text(this.darkMode)
  }

  build() {
    SymbolGlyph($r('sys.symbol.chevron_left'))
      .fontSize(TABS_BOTTOM_ICON_SIZE)
      .fontColor([this.iconColor()])
      .fontWeight(FontWeight.Medium)
  }
}

/** 列表进入/导航箭头：sys.symbol.chevron_right */
@Component
export struct NavChevronRight {
  @Prop color: string = '#9ca3af'
  @Prop iconSize: number = 16

  build() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(this.iconSize)
      .fontColor([this.color])
  }
}

/** 选中勾选：sys.symbol.checkmark（仅选中时显示） */
@Component
export struct SelectionCheckCircle {
  @Prop selected: boolean = false
  @Prop color: string = '#2563eb'
  @Prop iconSize: number = 20

  build() {
    if (this.selected) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(this.iconSize)
        .fontColor([this.color])
        .fontWeight(FontWeight.Medium)
    } else {
      Blank()
        .width(this.iconSize)
        .height(this.iconSize)
    }
  }
}

/** 单选 Radio（空心 / 实心圆点） */
@Component
export struct SelectionRadio {
  @Prop selected: boolean = false
  @Prop color: string = '#0A59F7'
  @Prop mutedColor: string = '#c4c7cc'
  @Prop disabled: boolean = false
  @Prop boxSize: number = 22

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(this.boxSize)
        .height(this.boxSize)
        .fill(Color.Transparent)
        .stroke(this.selected && !this.disabled ? this.color : this.mutedColor)
        .strokeWidth(2)
        .opacity(this.disabled ? 0.45 : 1)
      if (this.selected) {
        Circle()
          .width(this.boxSize * 0.55)
          .height(this.boxSize * 0.55)
          .fill(this.disabled ? this.mutedColor : this.color)
          .opacity(this.disabled ? 0.45 : 1)
      }
    }
    .width(this.boxSize + 6)
    .height(this.boxSize + 6)
  }
}

/** 文件夹树展开箭头：收起 chevron_right / 展开 chevron_down */
@Component
export struct FolderExpandChevron {
  @Prop expanded: boolean = false
  @Prop color: string = '#6b7280'
  @Prop iconSize: number = 20

  build() {
    SymbolGlyph(this.expanded ?
      $r('sys.symbol.chevron_down') :
      $r('sys.symbol.chevron_right'))
      .fontSize(this.iconSize)
      .fontColor([this.color])
  }
}
