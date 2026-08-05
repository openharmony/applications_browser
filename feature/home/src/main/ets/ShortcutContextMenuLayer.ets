import { BrowserTheme } from 'browser_core'
import { ShortcutFeature } from 'browser_core'
import { ShortcutManager } from 'browser_core'
import { ShortcutMenuOverlayState } from 'common'
import { AppStorageKeys } from 'common'
import { ShortcutContextMenu } from './ShortcutContextMenu'
import { ShortcutEngineIcon, ShortcutTileIcon } from './BrowserIcons'

/** 快捷方式长按 overlay：跟手图标 + 菜单（背板 blur 由 MainPage 层 backdropBlur 渲染） */
@Component
export struct ShortcutContextMenuLayer {
  @ObjectLink state: ShortcutMenuOverlayState
  menuWidth: number = 144

  private isDarkMode(): boolean {
    return this.state.darkMode
  }

  private feature(): ShortcutFeature | undefined {
    return ShortcutManager.resolveDisplayEntry(this.state.featureId)
  }

  private iconBoxSize(feature: ShortcutFeature): number {
    return feature.kind === 'feature' ? 52 : 48
  }

  private dismissMenu(): void {
    AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, 'dismiss')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.state.liftActive && this.feature() !== undefined) {
        this.LiftIcon(this.feature()!)
      }

      if (this.state.menuVisible) {
        // 全屏 dismiss 层置于 LiftIcon 之上、菜单之下，避免 HitTestMode.None 的浮层导致点击穿透
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.Default)
          .onClick(() => {
            this.dismissMenu()
          })
          .zIndex(2)

        ShortcutContextMenu({
          posX: this.state.menuPosX,
          posY: this.state.menuPosY,
          darkMode: this.isDarkMode(),
          menuWidth: this.menuWidth,
          onEdit: () => {
            AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, 'edit')
          },
          onRemove: () => {
            AppStorage.set(AppStorageKeys.SHORTCUT_MENU_ACTION, 'remove')
          }
        })
          .zIndex(3)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .clip(false)
    .hitTestBehavior(this.state.menuVisible ? HitTestMode.Default : HitTestMode.None)
  }

  /** 与原 Grid 图标同位置弹起，仅 scale 略放大 */
  @Builder
  LiftIcon(feature: ShortcutFeature) {
    Column() {
      if (feature.kind === 'feature') {
        ShortcutTileIcon({ tile: feature.tile ?? 'bookmark', iconSize: 28 })
      } else {
        ShortcutEngineIcon({ text: feature.iconText ?? '', iconMedia: feature.iconMedia ?? '', iconSize: 36 })
      }
    }
    .width(this.iconBoxSize(feature))
    .height(this.iconBoxSize(feature))
    .backgroundColor(BrowserTheme.shortcutIconBg(this.isDarkMode()))
    .borderRadius(14)
    .border({ width: 1, color: BrowserTheme.shortcutIconBorder(this.isDarkMode()) })
    .shadow({
      radius: 18,
      color: 'rgba(37, 99, 235, 0.35)',
      offsetX: 0,
      offsetY: 10
    })
    .justifyContent(FlexAlign.Center)
    .scale({ x: 1.12, y: 1.12 })
    .position({
      x: this.state.iconAnchorLeft + this.state.offsetX,
      y: this.state.iconAnchorTop + this.state.offsetY
    })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(1)
  }
}
