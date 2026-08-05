import { AppStorageKeys } from 'common'

/**
 * 沉浸式布局下顶部状态栏避让占位（非沉浸式时 SAFE_AREA_TOP=0，高度为 0）。
 * fillColor 与页面顶色一致，避免沉浸式模式下出现异色条。
 */
@Component
export struct PageTopSafeInset {
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  @Prop fillColor: ResourceColor = Color.Transparent

  build() {
    if (this.safeAreaTop <= 0) {
      Blank().width(0).height(0)
    } else {
      Blank()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor(this.fillColor)
        .hitTestBehavior(HitTestMode.None)
    }
  }
}

/** 顶栏 / 底栏 padding 计算（非组件场景） */
export class BrowserSafeAreaInsets {
  /** 底部导航与系统导航条之间的额外间距（vp） */
  static readonly BOTTOM_NAV_EXTRA: number = 14
  /** 面板底栏（批量操作条）与系统导航条之间的额外间距（vp） */
  static readonly BOTTOM_BAR_EXTRA: number = 14
  /** 批量底栏内容区高度（vp，仅图标+文案行，不含系统底边避让；避让写在外层 padding） */
  static readonly BATCH_BAR_HEIGHT: number = 48
  /** 无系统避让数据时的最小底边距（vp） */
  static readonly BOTTOM_MIN_FALLBACK: number = 34
  /** 浏览页底部工具栏内容区高度（vp，不含系统避让 padding） */
  static readonly BROWSE_TOOLBAR_HEIGHT: number = 48
  /** 首页/我的底部胶囊导航估算高度（vp，含外层 padding） */
  static readonly HOME_NAV_PILL_HEIGHT: number = 48
  /** 首页内容与底部导航之间的留白（vp） */
  static readonly HOME_CONTENT_GAP: number = 16

  static top(extra: number = 0): number {
    const inset = AppStorage.get<number>(AppStorageKeys.SAFE_AREA_TOP) ?? 0
    return inset + extra
  }

  /** 底部导航条距屏幕底边的 padding（系统避让 + 额外间距） */
  static bottom(extra: number = BrowserSafeAreaInsets.BOTTOM_NAV_EXTRA): number {
    const inset = AppStorage.get<number>(AppStorageKeys.SAFE_AREA_BOTTOM) ?? 0
    return Math.max(BrowserSafeAreaInsets.BOTTOM_MIN_FALLBACK, inset + extra)
  }

  /** 首页滚动区底部避让（底栏 padding + 胶囊高度 + 内容间距） */
  static homeContentBottomClearance(): number {
    return BrowserSafeAreaInsets.bottom(BrowserSafeAreaInsets.BOTTOM_NAV_EXTRA) +
      BrowserSafeAreaInsets.HOME_NAV_PILL_HEIGHT +
      BrowserSafeAreaInsets.HOME_CONTENT_GAP
  }

  /** 批量操作底栏总占位（内容行高 + 系统底边避让） */
  static batchBarScrollClearance(): number {
    return BrowserSafeAreaInsets.BATCH_BAR_HEIGHT +
      BrowserSafeAreaInsets.batchBarBottomPadding()
  }

  /**
   * 批量底栏底边 padding：仅系统导航避让，不再加 BOTTOM_BAR_EXTRA，
   * 避免图标/文案悬在导航条上方留出大块空白。
   */
  static batchBarBottomPadding(): number {
    const inset = AppStorage.get<number>(AppStorageKeys.SAFE_AREA_BOTTOM) ?? 0
    return inset > 0 ? inset : BrowserSafeAreaInsets.BOTTOM_MIN_FALLBACK
  }
}
