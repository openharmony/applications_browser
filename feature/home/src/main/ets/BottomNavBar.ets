import { BrowserStrings } from 'common'
import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'

/** 首页底部导航栏（主页 / 我的）：白底悬浮胶囊，选中蓝 / 未选中黑 */
@Component
export struct BottomNavBar {
  private static readonly OUTER_PAD: number = 4
  /** 胶囊内左右内边距，避免首尾项贴圆角边 */
  private static readonly INNER_H_PAD: number = 36
  private static readonly ITEM_MIN_H: number = 44
  private static readonly ICON_SIZE: number = 22
  /** 与标签页顶栏一致的水平外边距 */
  private static readonly H_INSET: number = 16

  /** 当前选中的 Tab 索引（0=主页，1=我的） */
  @Prop activeIndex: number = 0
  /** 是否深色模式（由 MainPage 计算传入，避免子组件 StorageLink 不同步） */
  @Prop isDark: boolean = false
  @StorageLink('browser_font_ui_rev') fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  /** Tab 切换回调 */
  onTabChange?: (index: number) => void

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  /** 选中：主题蓝；未选中：深色正文（非弱化灰） */
  private navIconColor(index: number): string {
    return this.activeIndex === index ?
      BrowserTheme.primaryColor(this.isDark) :
      BrowserTheme.text(this.isDark)
  }

  build() {
    Column() {
      Row() {
        this.NavItem(0, BrowserStrings.txt($r('app.string.home_title')), true)
        this.NavItem(1, BrowserStrings.txt($r('app.string.profile_nav_title')), false)
      }
      .width('100%')
      .padding({
        left: BottomNavBar.INNER_H_PAD,
        right: BottomNavBar.INNER_H_PAD,
        top: BottomNavBar.OUTER_PAD,
        bottom: BottomNavBar.OUTER_PAD
      })
      .alignItems(VerticalAlign.Center)
      .clip(true)
      .backgroundColor(BrowserTheme.navBgSolid(this.isDark))
      .borderRadius(999)
      .shadow({
        radius: 20,
        color: this.isDark ? 'rgba(0, 0, 0, 0.40)' : 'rgba(17, 24, 39, 0.12)',
        offsetX: 0,
        offsetY: 6
      })
    }
    .width('100%')
    .padding({ left: BottomNavBar.H_INSET, right: BottomNavBar.H_INSET })
  }

  /** 单个底部导航项（图标内联绘制，避免 @Prop color 子组件不随主题刷新） */
  @Builder
  NavItem(index: number, label: string, isHome: boolean) {
    Column({ space: 2 }) {
      if (isHome) {
        Image($r('app.media.ic_home'))
          .width(BottomNavBar.ICON_SIZE)
          .height(BottomNavBar.ICON_SIZE)
          .fillColor(this.navIconColor(index))
          .objectFit(ImageFit.Contain)
      } else {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
          .fontSize(BottomNavBar.ICON_SIZE)
          .fontColor([this.navIconColor(index)])
          .width(BottomNavBar.ICON_SIZE)
          .height(BottomNavBar.ICON_SIZE)
      }

      Text(label)
        .fontSize(this.uiFp(11))
        .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Medium))
        .fontColor(this.navIconColor(index))
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: BottomNavBar.ITEM_MIN_H })
    .padding({ top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTabChange?.(index)
    })
  }
}
