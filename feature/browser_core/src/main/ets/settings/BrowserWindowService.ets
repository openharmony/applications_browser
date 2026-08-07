import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { BrowserDeviceProfile } from 'common'
import { BrowserLog } from 'common'
import { AppStorageKeys } from 'common'

/** 窗口物理尺寸（px） */
export interface WindowSizePx {
  width: number
  height: number
}

/** 主窗口尺寸与横竖屏状态同步（module.json5 auto_rotation：独立旋转，旋转锁关闭时随传感器） */
export class BrowserWindowService {
  /** 避让区 vp 变化低于该阈值时不写 AppStorage，避免多任务手势期间底部 padding 抖动 */
  private static readonly AVOID_AREA_EPSILON_VP: number = 4
  /** 多任务动画期间 avoidAreaChange 连发，合并为一次同步 */
  private static readonly AVOID_AREA_DEBOUNCE_MS: number = 200
  /** 窗口尺寸帧间抖动容差（px），忽略多任务缩放过程中的微小变化 */
  private static readonly WINDOW_SIZE_EPSILON_PX: number = 12
  /** 连续窗口事件触发冻结的阈值（500ms 内） */
  private static readonly RAPID_EVENT_FREEZE_COUNT: number = 2
  private static readonly RAPID_EVENT_WINDOW_MS: number = 400
  /** 多任务动画结束后延迟解冻，等待 SceneBoard 壁纸缩放稳定 */
  private static readonly LAYOUT_UNFREEZE_DELAY_MS: number = 450
  /** 冷启动：首帧 + SceneBoard 2250ms dismiss 后各钉一次即可 */
  private static readonly SYSTEM_BAR_COLD_START_DELAYS_MS: number[] = [0, 2600]
  /** 回前台/SceneBoard 动画结束后补钉，覆盖多任务划掉再冷启动 */
  private static readonly SYSTEM_BAR_FOREGROUND_DELAYS_MS: number[] = [0, 400, 2800]
  /** 状态栏避让高度低于该值视为 SystemUI 未真正展示 */
  private static readonly SYSTEM_BAR_TOP_MIN_VP: number = 10
  /** 两次钉住状态栏的最小间隔，避免频繁 IPC 拖慢整机 */
  private static readonly SYSTEM_BAR_PIN_MIN_INTERVAL_MS: number = 8000

  private static instance: BrowserWindowService | null = null
  private mainWindow: window.Window | null = null
  private abilityContext: common.UIAbilityContext | null = null
  private sizeHandler: ((size: window.Size) => void) | null = null
  private avoidAreaHandler: ((options: window.AvoidAreaOptions) => void) | null = null
  private avoidAreaSyncTimer: number = -1
  private unfreezeTimer: number = -1
  private layoutFrozen: boolean = false
  private rapidEventCount: number = 0
  private rapidEventWindowStart: number = 0
  private systemBarsConfigured: boolean = false
  /** 已成功钉住沉浸式 layoutFullScreen=true */
  private systemBarsPinned: boolean = false
  private systemBarPinInFlight: boolean = false
  private lastSystemBarPinAt: number = 0
  private systemBarPinTimers: number[] = []
  private knownDirection: ConfigurationConstant.Direction = ConfigurationConstant.Direction.DIRECTION_NOT_SET
  /** 上次已同步的状态栏深浅色，避免重复 setWindowSystemBarProperties 引发闪烁 */
  private lastSyncedBarDark: boolean | null = null
  /** 上次 setColorMode 目标（followSystem / light / dark），避免跟随系统时反复写入 */
  private lastColorModeTarget: string = ''
  /** 上次已设置的窗口方向，避免页面切换时重复 IPC */
  private lastPreferredOrientation: window.Orientation | null = null

  static getInstance(): BrowserWindowService {
    if (BrowserWindowService.instance === null) {
      BrowserWindowService.instance = new BrowserWindowService()
    }
    return BrowserWindowService.instance
  }

  /** 多任务/窗口缩放动画期间冻结布局同步，避免 SceneBoard 壁纸反复缩放 */
  isLayoutFrozen(): boolean {
    return this.layoutFrozen
  }

  /** Ability 进入后台：取消补钉定时器，SceneBoard 会接管 SystemUI */
  onAbilityBackground(): void {
    this.clearSystemBarPinTimers()
    this.systemBarsPinned = false
    this.setLayoutFrozen(true, 'abilityBackground')
  }

  /** Ability 回到前台：SceneBoard 可能仍 disable 状态栏，须强制多轮补钉+同步内容色 */
  onAbilityForeground(): void {
    this.scheduleLayoutUnfreeze('abilityForeground')
    this.systemBarsPinned = false
    const win = this.mainWindow
    if (win !== null) {
      this.scheduleSystemBarRetryPin(win, 'foreground', BrowserWindowService.SYSTEM_BAR_FOREGROUND_DELAYS_MS)
    }
  }

  /** 首帧内容加载完成后补钉（bindWindow 可能尚未完成时的兜底） */
  onContentLoaded(): void {
    const win = this.mainWindow
    if (win !== null) {
      this.scheduleSystemBarRetryPin(win, 'coldStart', BrowserWindowService.SYSTEM_BAR_COLD_START_DELAYS_MS)
    }
  }

  /** 冷启动：从 Ability 配置读取方向，不强制竖屏（应用独立旋转） */
  initOrientationFromContext(context?: common.UIAbilityContext): void {
    const dir = context?.config?.direction ?? ConfigurationConstant.Direction.DIRECTION_NOT_SET
    this.knownDirection = dir
    BrowserLog.info(`[Window] initOrientation direction=${dir}`)
  }

  /** WindowStage 创建后绑定主窗口 */
  attachStage(stage: window.WindowStage, context?: common.UIAbilityContext): void {
    if (context !== undefined) {
      this.abilityContext = context
      this.initOrientationFromContext(context)
    }
    stage.getMainWindow().then((win: window.Window) => {
      this.bindWindow(win)
    }).catch((err: Error) => {
      BrowserLog.error(`[Window] getMainWindow failed: ${JSON.stringify(err)}`)
    })
  }

  private bindWindow(win: window.Window): void {
    this.detachWindow()
    this.mainWindow = win
    void this.ensureAutoRotation(win)
    this.syncWindowSize(win)
    this.sizeHandler = (size: window.Size) => {
      this.onWindowInteractionPulse('sizeChange')
      this.applyWindowSize(size.width, size.height)
    }
    win.on('windowSizeChange', this.sizeHandler)
    void this.ensureSystemBarsVisible(win, 'bindWindow').then(() => {
      this.syncAvoidArea(win)
      this.avoidAreaHandler = (_options: window.AvoidAreaOptions) => {
        this.onWindowInteractionPulse('avoidAreaChange')
        this.scheduleSyncAvoidArea(win)
      }
      win.on('avoidAreaChange', this.avoidAreaHandler)
    })
    this.syncSystemBarForTheme()
    this.scheduleSystemBarRetryPin(win, 'coldStart', BrowserWindowService.SYSTEM_BAR_COLD_START_DELAYS_MS)
    BrowserLog.info('[Window] attached auto_rotation')
  }

  /**
   * 绑定窗口时的初始方向：
   * - Phone：入口是首页，先锁竖屏
   * - Pad：始终自动旋转
   */
  private async ensureAutoRotation(win: window.Window): Promise<void> {
    if (BrowserDeviceProfile.isPhoneFormFactor()) {
      await this.setPreferredOrientationInternal(win, window.Orientation.PORTRAIT, 'bindWindow-phone')
      return
    }
    await this.setPreferredOrientationInternal(win, window.Orientation.AUTO_ROTATION, 'bindWindow-pad')
  }

  /**
   * 首页 / 我的（MainPage）：Phone 锁定竖屏，Pad 保持自动旋转。
   */
  applyOrientationForMainShell(): void {
    if (BrowserDeviceProfile.isPhoneFormFactor()) {
      void this.applyPreferredOrientation(window.Orientation.PORTRAIT, 'mainShell-phone')
      return
    }
    void this.applyPreferredOrientation(window.Orientation.AUTO_ROTATION, 'mainShell-pad')
  }

  /**
   * - Phone：AUTO_ROTATION_RESTRICTED 遵循系统旋转锁定设置（锁定时保持当前方向，关闭时随传感器）
   * - Pad：保持 AUTO_ROTATION（平板通常不设旋转锁概念）
   */
  applyOrientationForRotatablePage(): void {
    if (BrowserDeviceProfile.isPhoneFormFactor()) {
      void this.applyPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED, 'rotatablePage-phone')
      return
    }
    void this.applyPreferredOrientation(window.Orientation.AUTO_ROTATION, 'rotatablePage-pad')
  }

  private async applyPreferredOrientation(orientation: window.Orientation, reason: string): Promise<void> {
    const win = this.mainWindow
    if (win === null) {
      BrowserLog.warn(`[Window] setPreferredOrientation skipped no window reason=${reason}`)
      return
    }
    await this.setPreferredOrientationInternal(win, orientation, reason)
  }

  private async setPreferredOrientationInternal(win: window.Window, orientation: window.Orientation,
    reason: string): Promise<void> {
    if (this.lastPreferredOrientation === orientation) {
      return
    }
    try {
      await win.setPreferredOrientation(orientation)
      this.lastPreferredOrientation = orientation
      BrowserLog.info(`[Window] preferredOrientation=${orientation} reason=${reason}`)
    } catch (err) {
      BrowserLog.warn(`[Window] setPreferredOrientation failed reason=${reason}: ${JSON.stringify(err)}`)
    }
  }

  /**
   * 沉浸式钉住状态栏：layoutFullScreen=true，状态栏/导航栏底透明，由页面背景透出。
   */
  private async ensureSystemBarsVisible(win: window.Window, reason: string = 'direct', force: boolean = false): Promise<void> {
    if (this.systemBarPinInFlight) {
      BrowserLog.info(`[Window] pinSystemBars skipped reason=${reason} inFlight=true`)
      return
    }
    const now = Date.now()
    if (!force && this.systemBarsPinned &&
      now - this.lastSystemBarPinAt < BrowserWindowService.SYSTEM_BAR_PIN_MIN_INTERVAL_MS) {
      return
    }
    if (!force && !this.systemBarsPinned &&
      now - this.lastSystemBarPinAt < 500 &&
      this.lastSystemBarPinAt > 0) {
      return
    }
    this.systemBarPinInFlight = true
    try {
      await win.setWindowLayoutFullScreen(true)
      try {
        win.setImmersiveModeEnabledState(true)
      } catch (immersiveErr) {
        BrowserLog.warn(`[Window] setImmersiveModeEnabledState failed: ${JSON.stringify(immersiveErr)}`)
      }
      await win.setWindowSystemBarEnable(['status', 'navigation'])
      await win.setSpecificSystemBarEnabled('status', true, false)
      let layoutFullScreen = false
      try {
        layoutFullScreen = win.getWindowProperties().isLayoutFullScreen
      } catch (_propErr) {
        layoutFullScreen = false
      }
      if (layoutFullScreen) {
        this.systemBarsPinned = true
      }
      this.lastSystemBarPinAt = Date.now()
      if (!this.systemBarsConfigured) {
        BrowserLog.info('[Window] systemBars pinned visible (immersive transparent)')
        this.systemBarsConfigured = true
      }
      BrowserLog.info(`[Window] pinSystemBars reason=${reason} pinned=${this.systemBarsPinned} immersive=${layoutFullScreen}`)
      this.syncSystemBarForTheme(undefined, null, true)
      this.syncAvoidArea(win)
      this.verifySystemBarArea(win, reason)
    } catch (err) {
      BrowserLog.warn(`[Window] ensureSystemBarsVisible failed reason=${reason}: ${JSON.stringify(err)}`)
      this.systemBarsPinned = false
    } finally {
      this.systemBarPinInFlight = false
    }
  }

  /** 多轮补钉：force 绕过防抖；用于冷启动与回前台 */
  private scheduleSystemBarRetryPin(win: window.Window, tag: string, delays: number[]): void {
    this.clearSystemBarPinTimers()
    for (const delay of delays) {
      const timer = setTimeout(() => {
        void this.ensureSystemBarsVisible(win, `${tag}@${delay}ms`, true)
        if (delay > 0) {
          this.syncAvoidArea(win)
        }
      }, delay) as number
      this.systemBarPinTimers.push(timer)
    }
  }

  /** 读取避让区高度；沉浸式下 systemTop 供 UI padding，状态栏底透明由页面背景透出 */
  private verifySystemBarArea(win: window.Window, reason: string): void {
    try {
      const ui = win.getUIContext()
      const systemTopVp = ui.px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height)
      let layoutFullScreen = false
      try {
        layoutFullScreen = win.getWindowProperties().isLayoutFullScreen
      } catch (_propErr) {
        layoutFullScreen = false
      }
      if (!layoutFullScreen) {
        this.systemBarsPinned = false
        BrowserLog.warn(`[Window] statusBar not immersive reason=${reason} systemTop=${systemTopVp.toFixed(1)}`)
        return
      }
      if (systemTopVp < BrowserWindowService.SYSTEM_BAR_TOP_MIN_VP) {
        this.systemBarsPinned = false
        BrowserLog.warn(`[Window] statusBar area missing reason=${reason} topVp=${systemTopVp.toFixed(1)}`)
        return
      }
      BrowserLog.info(`[Window] statusBar immersive ok reason=${reason} topVp=${systemTopVp.toFixed(1)}`)
    } catch (err) {
      BrowserLog.warn(`[Window] verifySystemBarArea failed reason=${reason}: ${JSON.stringify(err)}`)
    }
  }

  private clearSystemBarPinTimers(): void {
    for (const timer of this.systemBarPinTimers) {
      clearTimeout(timer)
    }
    this.systemBarPinTimers = []
  }

  /** 状态栏/导航栏底透明，仅同步内容色（浅色黑字、深色白字） */
  private buildSystemBarProps(dark: boolean): window.SystemBarProperties {
    const contentColor = dark ? '#FFFFFFFF' : '#FF000000'
    return {
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor,
      isStatusBarLightIcon: dark,
      isNavigationBarLightIcon: dark,
      enableStatusBarAnimation: false,
      enableNavigationBarAnimation: false
    }
  }

  /** 同步应用 colorMode（仅用户切换主题偏好或启动加载偏好时调用，不在状态栏同步链路中调用） */
  syncColorModeForPreference(
    preference: string,
    effectiveDark: boolean,
    context?: common.UIAbilityContext | null
  ): void {
    const ctx = context ?? this.abilityContext
    if (ctx === null) {
      return
    }
    const pref = preference === 'system' ? 'system' : (preference === 'dark' ? 'dark' : 'light')
    if (pref === this.lastColorModeTarget) {
      this.syncSystemBarForTheme(effectiveDark, context, true)
      return
    }
    try {
      if (pref === 'system') {
        ctx.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
        BrowserLog.info('[Window] app colorMode=NOT_SET (follow system)')
      } else {
        ctx.getApplicationContext().setColorMode(
          effectiveDark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
            ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        )
        BrowserLog.info(`[Window] app colorMode=${effectiveDark ? 'dark' : 'light'}`)
      }
      this.lastColorModeTarget = pref
    } catch (err) {
      BrowserLog.warn(`[Window] setColorMode failed: ${JSON.stringify(err)}`)
    }
    this.syncSystemBarForTheme(effectiveDark, context, true)
  }

  /**
   * 按当前有效主题同步状态栏/导航栏颜色与内容色（浅色黑字、深色白字）。
   * 仅 setWindowSystemBarProperties，不调用 setColorMode（setColorMode 见 syncColorModeForPreference）。
   */
  syncSystemBarForTheme(isDark?: boolean, _context?: common.UIAbilityContext | null, force: boolean = false): void {
    const win = this.mainWindow
    if (win === null) {
      return
    }
    const dark = isDark ?? ((AppStorage.get<string>(AppStorageKeys.THEME) ?? 'light') === 'dark')
    if (!force && this.lastSyncedBarDark === dark) {
      return
    }
    this.lastSyncedBarDark = dark
    const props = this.buildSystemBarProps(dark)
    void win.setWindowSystemBarProperties(props).then(() => {
      BrowserLog.info(`[Window] systemBar synced dark=${dark} transparent content=${props.statusBarContentColor} ` +
        `lightIcon=${props.isStatusBarLightIcon}`)
    }).catch((err: Error) => {
      BrowserLog.warn(`[Window] setWindowSystemBarProperties failed dark=${dark}: ${JSON.stringify(err)}`)
    })
  }

  /** 启动时记录系统方向，供尺寸回调判定横竖屏 */
  setKnownDirection(direction: ConfigurationConstant.Direction): void {
    this.knownDirection = direction
  }

  /** 屏幕方向变更（仅 direction 变化时由 MainAbility 调用） */
  onDirectionChanged(direction: ConfigurationConstant.Direction): void {
    this.knownDirection = direction
    BrowserLog.info(`[Window] direction=${direction}`)
    if (this.mainWindow !== null) {
      this.syncWindowSize(this.mainWindow)
    } else {
      this.applyLandscapeFromDirection(direction)
    }
  }

  /** 解绑窗口监听 */
  detachWindow(): void {
    if (this.mainWindow !== null) {
      if (this.sizeHandler !== null) {
        try {
          this.mainWindow.off('windowSizeChange', this.sizeHandler)
        } catch (_err) {
          // 忽略重复解绑
        }
      }
      if (this.avoidAreaHandler !== null) {
        try {
          this.mainWindow.off('avoidAreaChange', this.avoidAreaHandler)
        } catch (_err) {
          // 忽略重复解绑
        }
      }
    }
    this.clearSystemBarPinTimers()
    this.clearAvoidAreaSyncTimer()
    this.clearUnfreezeTimer()
    this.layoutFrozen = false
    this.mainWindow = null
    this.sizeHandler = null
    this.avoidAreaHandler = null
    this.systemBarsConfigured = false
    this.systemBarsPinned = false
    this.systemBarPinInFlight = false
    this.lastSystemBarPinAt = 0
    this.lastSyncedBarDark = null
    this.lastPreferredOrientation = null
  }

  /** 窗口级边缘返回手势（false=禁止 Router 直接出栈，改由页面 onBackPress / 自定义侧滑处理） */
  setGestureBackEnabled(enabled: boolean): void {
    const win = this.mainWindow
    if (win === null) {
      BrowserLog.warn('[Window] setGestureBackEnabled: no main window')
      return
    }
    void win.setGestureBackEnabled(enabled).then(() => {
      BrowserLog.info(`[Window] setGestureBackEnabled=${enabled}`)
    }).catch((err: Error) => {
      BrowserLog.warn(`[Window] setGestureBackEnabled failed: ${JSON.stringify(err)}`)
    })
  }

  /** 页面级侧滑返回开关（系统黑球侧滑动效） */
  setPageSwipeBackEnabled(uiContext: UIContext | null, enabled: boolean): void {
    if (uiContext === null) {
      return
    }
    try {
      uiContext.enableSwipeBack(enabled)
      BrowserLog.info(`[Window] enableSwipeBack=${enabled}`)
    } catch (err) {
      BrowserLog.warn(`[Window] enableSwipeBack failed: ${JSON.stringify(err)}`)
    }
  }

  /** 当前是否为横屏（宽 > 高） */
  static isLandscape(): boolean {
    return AppStorage.get<boolean>(AppStorageKeys.WINDOW_LANDSCAPE) ?? false
  }

  /** 将主窗口尺寸写入 AppStorage（BrowsePage 等子页进入时兜底同步） */
  ensureWindowSizeSynced(): void {
    if (this.mainWindow !== null) {
      this.syncWindowSize(this.mainWindow)
    }
  }

  /**
   * 读取窗口尺寸（px）。AppStorage 未写入时从主窗口直接读取并回写。
   */
  resolveWindowSizePx(): WindowSizePx {
    const storedW = AppStorage.get<number>(AppStorageKeys.WINDOW_WIDTH) ?? 0
    const storedH = AppStorage.get<number>(AppStorageKeys.WINDOW_HEIGHT) ?? 0
    if (storedW > 0 && storedH > 0) {
      return { width: storedW, height: storedH }
    }
    if (this.mainWindow !== null) {
      try {
        const rect = this.mainWindow.getWindowProperties().windowRect
        if (rect.width > 0 && rect.height > 0) {
          this.applyWindowSize(rect.width, rect.height)
          return { width: rect.width, height: rect.height }
        }
      } catch (err) {
        BrowserLog.warn(`[Window] resolveWindowSizePx failed: ${JSON.stringify(err)}`)
      }
    }
    return { width: storedW, height: storedH }
  }

  private syncWindowSize(win: window.Window): void {
    try {
      const rect = win.getWindowProperties().windowRect
      this.applyWindowSize(rect.width, rect.height)
    } catch (err) {
      BrowserLog.warn(`[Window] syncWindowSize failed: ${JSON.stringify(err)}`)
    }
  }

  private applyWindowSize(width: number, height: number): void {
    if (width <= 0 || height <= 0 || this.layoutFrozen) {
      return
    }
    const prevW = AppStorage.get<number>(AppStorageKeys.WINDOW_WIDTH) ?? 0
    const prevH = AppStorage.get<number>(AppStorageKeys.WINDOW_HEIGHT) ?? 0
    const landscape = this.resolveLandscape(width, height)
    const prevLandscape = AppStorage.get<boolean>(AppStorageKeys.WINDOW_LANDSCAPE) ?? false
    if (Math.abs(width - prevW) < BrowserWindowService.WINDOW_SIZE_EPSILON_PX &&
      Math.abs(height - prevH) < BrowserWindowService.WINDOW_SIZE_EPSILON_PX &&
      landscape === prevLandscape) {
      return
    }
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_WIDTH, width)
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_HEIGHT, height)
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_LANDSCAPE, landscape)
    const rev = (AppStorage.get<number>(AppStorageKeys.WINDOW_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.WINDOW_REV, rev)
    BrowserLog.info(`[Window] size=${width}x${height} landscape=${landscape} rev=${rev}`)
  }

  private resolveLandscape(width: number, height: number): boolean {
    if (this.knownDirection === ConfigurationConstant.Direction.DIRECTION_HORIZONTAL) {
      return true
    }
    if (this.knownDirection === ConfigurationConstant.Direction.DIRECTION_VERTICAL) {
      return false
    }
    if (height <= 0) {
      return false
    }
    // 宽显著大于高才视为横屏，避免竖屏桌面宽窗口误判
    return width > height * 1.08
  }

  private applyLandscapeFromDirection(direction: ConfigurationConstant.Direction): void {
    if (direction === ConfigurationConstant.Direction.DIRECTION_NOT_SET) {
      return
    }
    const landscape = direction === ConfigurationConstant.Direction.DIRECTION_HORIZONTAL
    AppStorage.setOrCreate(AppStorageKeys.WINDOW_LANDSCAPE, landscape)
    const rev = (AppStorage.get<number>(AppStorageKeys.WINDOW_REV) ?? 0) + 1
    AppStorage.set(AppStorageKeys.WINDOW_REV, rev)
  }

  /** 同步状态栏/导航条避让高度到 AppStorage，供顶栏与底部导航使用 */
  syncAvoidArea(win?: window.Window): void {
    const target = win ?? this.mainWindow
    if (target === null) {
      return
    }
    this.commitAvoidArea(target)
  }

  /** 合并多任务手势期间的连续 avoidAreaChange，避免底部导航条反复跳动 */
  private scheduleSyncAvoidArea(win: window.Window): void {
    this.clearAvoidAreaSyncTimer()
    this.avoidAreaSyncTimer = setTimeout(() => {
      this.avoidAreaSyncTimer = -1
      this.commitAvoidArea(win)
    }, BrowserWindowService.AVOID_AREA_DEBOUNCE_MS)
  }

  private clearAvoidAreaSyncTimer(): void {
    if (this.avoidAreaSyncTimer >= 0) {
      clearTimeout(this.avoidAreaSyncTimer)
      this.avoidAreaSyncTimer = -1
    }
  }

  private commitAvoidArea(target: window.Window): void {
    if (this.layoutFrozen) {
      return
    }
    try {
      const ui = target.getUIContext()
      const systemArea = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const systemTopVp = ui.px2vp(systemArea.topRect.height)
      let bottomVp = ui.px2vp(systemArea.bottomRect.height)
      try {
        const navArea = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
        bottomVp = Math.max(bottomVp, ui.px2vp(navArea.bottomRect.height))
      } catch (_navErr) {
        // 部分设备无独立导航条避让区，沿用 TYPE_SYSTEM.bottomRect
      }
      let layoutFullScreen = false
      try {
        layoutFullScreen = target.getWindowProperties().isLayoutFullScreen
      } catch (_propErr) {
        layoutFullScreen = false
      }
      // 沉浸式：UI 须自行 padding SAFE_AREA_TOP，背景经 expandSafeArea(TOP) 延伸至状态栏下
      const topVp = layoutFullScreen ? systemTopVp : 0
      const prevTop = AppStorage.get<number>(AppStorageKeys.SAFE_AREA_TOP) ?? 0
      const prevBottom = AppStorage.get<number>(AppStorageKeys.SAFE_AREA_BOTTOM) ?? 0
      const topDelta = Math.abs(topVp - prevTop)
      const bottomDelta = Math.abs(bottomVp - prevBottom)
      if (topDelta < BrowserWindowService.AVOID_AREA_EPSILON_VP &&
        bottomDelta < BrowserWindowService.AVOID_AREA_EPSILON_VP) {
        return
      }
      AppStorage.setOrCreate(AppStorageKeys.SAFE_AREA_TOP, topVp)
      AppStorage.setOrCreate(AppStorageKeys.SAFE_AREA_BOTTOM, bottomVp)
      BrowserLog.info(`[Window] safeArea uiTop=${topVp.toFixed(1)} systemTop=${systemTopVp.toFixed(1)} ` +
        `bottom=${bottomVp.toFixed(1)}vp immersive=${layoutFullScreen}`)
    } catch (err) {
      BrowserLog.warn(`[Window] syncAvoidArea failed: ${JSON.stringify(err)}`)
    }
  }

  private onWindowInteractionPulse(source: string): void {
    const now = Date.now()
    if (now - this.rapidEventWindowStart > BrowserWindowService.RAPID_EVENT_WINDOW_MS) {
      this.rapidEventCount = 0
      this.rapidEventWindowStart = now
    }
    this.rapidEventCount++
    if (this.rapidEventCount >= BrowserWindowService.RAPID_EVENT_FREEZE_COUNT) {
      this.setLayoutFrozen(true, `rapid:${source}`)
    }
  }

  private setLayoutFrozen(frozen: boolean, reason: string): void {
    if (this.layoutFrozen === frozen) {
      return
    }
    this.layoutFrozen = frozen
    if (frozen) {
      this.clearUnfreezeTimer()
      BrowserLog.info(`[Window] layoutFrozen=true reason=${reason}`)
      return
    }
    BrowserLog.info(`[Window] layoutFrozen=false reason=${reason}`)
    if (this.mainWindow !== null) {
      this.syncWindowSize(this.mainWindow)
      this.commitAvoidArea(this.mainWindow)
      this.systemBarsPinned = false
      void this.ensureSystemBarsVisible(this.mainWindow, `unfreeze:${reason}`, true)
    }
  }

  private scheduleLayoutUnfreeze(reason: string): void {
    this.clearUnfreezeTimer()
    this.unfreezeTimer = setTimeout(() => {
      this.unfreezeTimer = -1
      this.setLayoutFrozen(false, reason)
    }, BrowserWindowService.LAYOUT_UNFREEZE_DELAY_MS)
  }

  private clearUnfreezeTimer(): void {
    if (this.unfreezeTimer >= 0) {
      clearTimeout(this.unfreezeTimer)
      this.unfreezeTimer = -1
    }
  }
}

