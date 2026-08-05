import { BrowserTheme } from 'browser_core'
import { BrowserNavigation } from 'browser_core'
import { AppStorageKeys } from 'common'
import {
  PanelBackChevronIcon,
  PanelHeaderCloseIcon,
  PanelHeaderConfirmIcon,
  PanelHeaderMoreIcon,
  PanelHeaderSearchIcon,
  PANEL_HEADER_ICON_BOX_SIZE,
  SERVICE_TOGGLE_ON_COLOR
} from './BrowserIcons'

/** 子页顶栏尺寸与配色（对齐设计稿） */
export class PanelHeaderStyle {
  static readonly CIRCLE_SIZE: number = 32
  static readonly CIRCLE_RADIUS: number = 16
  static readonly ICON_LIGHT: string = '#111827'
  static readonly ICON_MUTED_LIGHT: string = '#6b7280'
  static readonly ICON_DARK: string = '#f2f2f2'
  static readonly ICON_MUTED_DARK: string = '#a8a8a8'
  static readonly H_PADDING: number = 16
  static readonly V_PADDING: number = 14
  static readonly ACTION_GAP: number = 8
  static readonly TITLE_GAP: number = 12
  static readonly TITLE_SIZE: number = 16
  static readonly MENU_TOP: number = 56
  static readonly MENU_RIGHT: number = 16
  static readonly MENU_WIDTH: number = 156
  static readonly MENU_RADIUS: number = 14
  /** 顶栏向左展开搜索胶囊：高度与 CIRCLE_SIZE(32) 一致，避免展开后顶栏变高 */
  static readonly SEARCH_CAPSULE_H: number = 32
  static readonly SEARCH_CAPSULE_PAD_H: number = 10
  static readonly SEARCH_CAPSULE_GAP: number = 6
  /** 胶囊内输入/占位文字字号（适配 32 高，避免裁切与撑高） */
  static readonly SEARCH_CAPSULE_FONT: number = 12
  static readonly SEARCH_CAPSULE_ICON: number = 16
  static readonly SEARCH_CAPSULE_CLOSE: number = 20
}

/** 弹出菜单项 */
export interface PanelMenuItem {
  label: string | Resource
  iconKind: string
  danger?: boolean
  onTap: () => void
}

/** 圆形图标按钮（返回 / 搜索 / 更多 / 叉叉） */
@Component
export struct PanelCircleIconButton {
  @Prop iconKind: string = 'back'
  @Prop darkMode: boolean = false
  onTap?: () => void

  private iconColor(): string {
    return this.darkMode ? PanelHeaderStyle.ICON_MUTED_DARK : PanelHeaderStyle.ICON_MUTED_LIGHT
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.iconKind === 'back') {
        PanelBackChevronIcon({
          color: this.darkMode ? PanelHeaderStyle.ICON_DARK : PanelHeaderStyle.ICON_LIGHT,
          boxSize: 18
        })
      } else if (this.iconKind === 'close') {
        PanelHeaderCloseIcon({
          color: this.darkMode ? PanelHeaderStyle.ICON_DARK : PanelHeaderStyle.ICON_LIGHT,
          boxSize: PANEL_HEADER_ICON_BOX_SIZE
        })
      } else if (this.iconKind === 'search') {
        PanelHeaderSearchIcon({
          color: this.iconColor(),
          boxSize: 17
        })
      } else if (this.iconKind === 'more') {
        PanelHeaderMoreIcon({
          color: this.iconColor(),
          boxSize: 17
        })
      } else if (this.iconKind === 'confirm') {
        PanelHeaderConfirmIcon({
          color: SERVICE_TOGGLE_ON_COLOR,
          boxSize: PANEL_HEADER_ICON_BOX_SIZE
        })
      }
    }
    .width(PanelHeaderStyle.CIRCLE_SIZE)
    .height(PanelHeaderStyle.CIRCLE_SIZE)
    .borderRadius(PanelHeaderStyle.CIRCLE_RADIUS)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .onClick(() => {
      this.onTap?.()
    })
  }
}

/** 菜单行图标 */
@Component
struct PanelMenuRowIcon {
  @Prop iconKind: string = 'edit'
  @Prop danger: boolean = false
  @Prop darkMode: boolean = false

  private stroke(): string {
    if (this.danger) {
      return '#ef4444'
    }
    return this.darkMode ? PanelHeaderStyle.ICON_DARK : PanelHeaderStyle.ICON_LIGHT
  }

  build() {
    if (this.iconKind === 'trash') {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([this.stroke()])
        .fontWeight(FontWeight.Medium)
    } else if (this.iconKind === 'folder') {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(18)
        .fontColor([this.stroke()])
        .fontWeight(FontWeight.Medium)
    } else {
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(18)
        .fontColor([this.stroke()])
        .fontWeight(FontWeight.Medium)
    }
  }
}

/** 我的子功能统一顶栏：左返回 + 左对齐标题 + 右搜索/更多；搜索可向左展开胶囊 */
@Component
export struct PanelSubpageHeader {
  @Prop title: string = ''
  @Prop batchMode: boolean = false
  @Prop darkMode: boolean = false
  @Prop showSearch: boolean = true
  @Prop showMore: boolean = true
  /** 搜索胶囊是否展开（占用标题区） */
  @Prop searchExpanded: boolean = false
  @Prop searchText: string = ''
  @Prop searchPlaceholder: Resource = $r('app.string.search_placeholder')
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  onBack?: () => void
  onSearch?: () => void
  onMore?: () => void
  onSearchChange?: (text: string) => void
  /** 点胶囊内 ×：收起并清空 */
  onSearchClear?: () => void

  private headerBg(): string {
    return this.darkMode ? BrowserTheme.DARK_SURFACE : '#ffffff'
  }

  private headerBorderColor(): string {
    return this.darkMode ? BrowserTheme.DARK_BORDER : BrowserTheme.BORDER
  }

  private titleColor(): string {
    return this.darkMode ? BrowserTheme.DARK_TEXT : '#111827'
  }

  private searchIconColor(): string {
    return this.darkMode ? PanelHeaderStyle.ICON_MUTED_DARK : PanelHeaderStyle.ICON_MUTED_LIGHT
  }

  private inputTextColor(): string {
    return this.darkMode ? BrowserTheme.DARK_TEXT : '#111827'
  }

  build() {
    Row() {
      Row() {
        PanelCircleIconButton({
          iconKind: this.batchMode ? 'close' : 'back',
          darkMode: this.darkMode,
          onTap: () => {
            this.onBack?.()
          }
        })

        if (!this.batchMode && this.showSearch && this.searchExpanded) {
          this.SearchCapsule()
        } else {
          Text(this.title)
            .fontSize(BrowserTheme.scaledFp(PanelHeaderStyle.TITLE_SIZE, this.fontUiScale))
            .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Medium))
            .fontColor(this.titleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .margin({ left: PanelHeaderStyle.TITLE_GAP })
            .height(PanelHeaderStyle.CIRCLE_SIZE)
        }

        if (!this.batchMode && ((this.showSearch && !this.searchExpanded) || this.showMore)) {
          Row({ space: PanelHeaderStyle.ACTION_GAP }) {
            if (this.showSearch && !this.searchExpanded) {
              PanelCircleIconButton({
                iconKind: 'search',
                darkMode: this.darkMode,
                onTap: () => {
                  this.onSearch?.()
                }
              })
                .id('panel_header_search')
            }
            if (this.showMore) {
              PanelCircleIconButton({
                iconKind: 'more',
                darkMode: this.darkMode,
                onTap: () => {
                  this.onMore?.()
                }
              })
            }
          }
          .height(PanelHeaderStyle.CIRCLE_SIZE)
          .margin({ left: this.searchExpanded ? PanelHeaderStyle.ACTION_GAP : 0 })
          .alignItems(VerticalAlign.Center)
        } else if (this.batchMode) {
          Blank().width(PanelHeaderStyle.CIRCLE_SIZE).height(PanelHeaderStyle.CIRCLE_SIZE)
        }
      }
      .width('100%')
      .height(PanelHeaderStyle.CIRCLE_SIZE)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: PanelHeaderStyle.H_PADDING,
      right: PanelHeaderStyle.H_PADDING,
      top: PanelHeaderStyle.V_PADDING + this.safeAreaTop,
      bottom: PanelHeaderStyle.V_PADDING
    })
    .backgroundColor(this.headerBg())
    .border({ width: { bottom: 1 }, color: this.headerBorderColor() })
    .key(`panel-header-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}`)
  }

  /** 向左展开：放大镜 + 输入 + 关闭，占用标题区 */
  @Builder
  SearchCapsule() {
    Row({ space: PanelHeaderStyle.SEARCH_CAPSULE_GAP }) {
      PanelHeaderSearchIcon({
        color: this.searchIconColor(),
        boxSize: PanelHeaderStyle.SEARCH_CAPSULE_ICON
      })

      TextInput({
        text: this.searchText,
        placeholder: this.searchPlaceholder
      })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .height(PanelHeaderStyle.SEARCH_CAPSULE_H)
        .fontSize(BrowserTheme.scaledFp(PanelHeaderStyle.SEARCH_CAPSULE_FONT, this.fontUiScale))
        .fontColor(this.inputTextColor())
        .placeholderFont({
          size: BrowserTheme.scaledFp(PanelHeaderStyle.SEARCH_CAPSULE_FONT, this.fontUiScale),
          weight: FontWeight.Regular
        })
        .placeholderColor(this.searchIconColor())
        .caretColor(BrowserTheme.PRIMARY_COLOR)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .border({ width: 0 })
        .showUnderline(false)
        .defaultFocus(true)
        .enableKeyboardOnFocus(true)
        .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
        .onChange((v: string) => {
          this.onSearchChange?.(v)
        })

      Stack({ alignContent: Alignment.Center }) {
        PanelHeaderCloseIcon({
          color: this.searchIconColor(),
          boxSize: 14
        })
      }
      .width(PanelHeaderStyle.SEARCH_CAPSULE_CLOSE)
      .height(PanelHeaderStyle.SEARCH_CAPSULE_CLOSE)
      .flexShrink(0)
      .onClick(() => {
        if (this.onSearchClear) {
          this.onSearchClear()
        } else {
          this.onSearch?.()
        }
      })
    }
    .layoutWeight(1)
    .height(PanelHeaderStyle.SEARCH_CAPSULE_H)
    .padding({
      left: PanelHeaderStyle.SEARCH_CAPSULE_PAD_H,
      right: PanelHeaderStyle.SEARCH_CAPSULE_PAD_H - 2
    })
    .margin({ left: PanelHeaderStyle.TITLE_GAP })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
    .clip(false)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .borderRadius(PanelHeaderStyle.SEARCH_CAPSULE_H / 2)
  }
}

/** 我的页主标题顶栏（无返回） */
@Component
export struct ProfilePageHeader {
  @Prop title: string | Resource = ''
  @Prop darkMode: boolean = false
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0

  private headerBg(): string {
    return this.darkMode ? BrowserTheme.DARK_BG : BrowserTheme.LIGHT_BG
  }

  private titleColor(): string {
    return this.darkMode ? BrowserTheme.DARK_TEXT : '#111827'
  }

  build() {
    Row() {
      Text(this.title)
        .fontSize(BrowserTheme.uiFontSize(PanelHeaderStyle.TITLE_SIZE))
        .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Medium))
        .fontColor(this.titleColor())
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: PanelHeaderStyle.V_PADDING + 4 + this.safeAreaTop,
      bottom: PanelHeaderStyle.V_PADDING
    })
    .backgroundColor(this.headerBg())
  }
}

/** 右上角弹出菜单（编辑 / 一键清空等） */
@Component
export struct PanelPopoverMenu {
  @Prop visible: boolean = false
  @Prop darkMode: boolean = false
  @Prop items: PanelMenuItem[] = []
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  onDismiss?: () => void

  private menuBg(): string {
    return this.darkMode ? BrowserTheme.DARK_SURFACE : '#ffffff'
  }

  private menuBorderColor(): string {
    return this.darkMode ? BrowserTheme.DARK_BORDER : 'rgba(0, 0, 0, 0.06)'
  }

  private textColor(danger: boolean): string {
    if (danger) {
      return '#ef4444'
    }
    return this.darkMode ? BrowserTheme.DARK_TEXT : '#111827'
  }

  build() {
    if (!this.visible) {
      Column()
    } else {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onDismiss?.()
          })

        Column() {
          ForEach(this.items, (item: PanelMenuItem, index: number) => {
            Column() {
              if (index > 0) {
                Divider()
                  .color(this.menuBorderColor())
                  .strokeWidth(1)
                  .margin({ left: 16, right: 16 })
              }
              Row({ space: 10 }) {
                PanelMenuRowIcon({
                  iconKind: item.iconKind,
                  danger: item.danger === true,
                  darkMode: this.darkMode
                })
                Text(item.label)
                  .fontSize(BrowserTheme.uiFontSize(15))
                  .fontWeight(BrowserTheme.uiFontWeight(FontWeight.Medium))
                  .fontColor(this.textColor(item.danger === true))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 13, bottom: 13 })
              .onClick(() => {
                item.onTap()
              })
            }
          }, (item: PanelMenuItem, index: number) => `${index}_${item.iconKind}`)
        }
        .width(PanelHeaderStyle.MENU_WIDTH)
        .backgroundColor(this.menuBg())
        .borderRadius(PanelHeaderStyle.MENU_RADIUS)
        .border({ width: 1, color: this.menuBorderColor() })
        .shadow({
          radius: 16,
          color: 'rgba(17, 24, 39, 0.12)',
          offsetX: 0,
          offsetY: 6
        })
        .margin({
          top: PanelHeaderStyle.MENU_TOP + this.safeAreaTop,
          right: PanelHeaderStyle.MENU_RIGHT
        })
      }
      .width('100%')
      .height('100%')
      .zIndex(4000)
    }
  }
}
