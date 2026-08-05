import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'

/** 设置页内联选项（label + key） */
export interface SettingsPickOption {
  label: string
  key: string
}

/**
 * 设置页自定义下拉：选项文字使用 BrowserTheme.uiFontSize，随浏览器字体档位实时变化。
 * 替代系统 Select（Select 不支持 fontSize，下拉项始终跟随系统字号）。
 */
@Component
export struct SettingsInlinePicker {
  @Prop options: SettingsPickOption[] = []
  @Prop selectedKey: string = ''
  @Prop isDark: boolean = false
  @Prop menuWidth: number = 168
  /** 触发器固定宽度；>0 时文字左对齐、三角标右对齐 */
  @Prop triggerWidth: number = 0
  onSelect?: (key: string) => void

  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageLink(AppStorageKeys.SYSTEM_FONT_SIZE_SCALE) systemFontSizeScale: number = 1
  @State menuVisible: boolean = false

  private textColor(): string {
    return this.isDark ? BrowserTheme.DARK_TEXT : BrowserTheme.LIGHT_TEXT
  }

  private mutedColor(): string {
    return this.isDark ? BrowserTheme.DARK_TEXT_MUTED : BrowserTheme.LIGHT_TEXT_MUTED
  }

  private menuBg(): string {
    return this.isDark ? BrowserTheme.DARK_SURFACE : BrowserTheme.LIGHT_SURFACE
  }

  private triggerBg(): string {
    return this.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'
  }

  private selectedLabel(): string {
    for (const opt of this.options) {
      if (opt.key === this.selectedKey) {
        return opt.label
      }
    }
    return this.options.length > 0 ? this.options[0].label : ''
  }

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  build() {
    Row({ space: 4 }) {
      Text(this.selectedLabel())
        .fontSize(this.uiFp(14))
        .fontColor(this.textColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      Text('▾')
        .fontSize(this.uiFp(12))
        .fontColor(this.mutedColor())
    }
    .width(this.triggerWidth > 0 ? this.triggerWidth : undefined)
    .constraintSize({ minWidth: 88 })
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(8)
    .backgroundColor(this.triggerBg())
    .onClick(() => {
      this.menuVisible = !this.menuVisible
    })
    .bindPopup(this.menuVisible, {
      builder: this.DropdownMenu(),
      placement: Placement.Bottom,
      enableArrow: false,
      mask: true,
      popupColor: Color.Transparent,
      onStateChange: (event) => {
        this.menuVisible = event.isVisible
      }
    })
    .key(`settings-picker-${this.fontUiRev}-${this.selectedKey}-${this.fontUiScale}-${this.systemFontSizeScale}`)
  }

  @Builder
  DropdownMenu() {
    Column() {
      ForEach(this.options, (opt: SettingsPickOption) => {
        Row() {
          Text(opt.label)
            .fontSize(this.uiFp(14))
            .fontColor(this.textColor())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (opt.key === this.selectedKey) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(this.uiFp(16))
              .fontColor([BrowserTheme.primaryColor(this.isDark)])
              .fontWeight(FontWeight.Medium)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.menuVisible = false
          this.onSelect?.(opt.key)
        })
      }, (opt: SettingsPickOption) => `${opt.key}-${this.fontUiRev}`)
    }
    .width(this.menuWidth)
    .backgroundColor(this.menuBg())
    .borderRadius(12)
    .border({ width: 1, color: BrowserTheme.borderColor(this.isDark) })
    .shadow({
      radius: 16,
      color: 'rgba(17, 24, 39, 0.12)',
      offsetX: 0,
      offsetY: 6
    })
    .key(`settings-picker-menu-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}`)
  }
}
