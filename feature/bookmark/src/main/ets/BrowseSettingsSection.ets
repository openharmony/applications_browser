import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { BrowserStrings } from 'common'
import { AppStorageKeys } from 'common'
import { SettingsInlinePicker, SettingsPickOption } from 'commons'
import { DarkModePickerDialog } from 'commons'
import { NavChevronRight } from 'commons'

/** 浏览设置子页：独立组件，@StorageLink 绑定 fontUiScale 保证切换档位后当前页即时刷新 */
@Component
export struct BrowseSettingsSection {
  @Link fontSize: string
  @Link imageLessMode: boolean
  @Prop isDark: boolean = false
  onOpenEngine?: () => void
  onClearData?: () => void

  @StorageLink(AppStorageKeys.FONT_UI_REV) fontUiRev: number = 0
  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1
  @StorageLink(AppStorageKeys.THEME_PREFERENCE) themePreference: string = 'light'
  @State showDarkModePicker: boolean = false

  private uiFp(base: number): number {
    return BrowserTheme.scaledFp(base, this.fontUiScale)
  }

  private titleColor(): string {
    return this.isDark ? BrowserTheme.DARK_TEXT : BrowserTheme.LIGHT_TEXT
  }

  private mutedColor(): string {
    return this.isDark ? BrowserTheme.DARK_TEXT_MUTED : BrowserTheme.LIGHT_TEXT_MUTED
  }

  private cardBg(): string {
    return this.isDark ? BrowserTheme.DARK_PANEL_BG : BrowserTheme.LIGHT_PANEL_BG
  }

  private fontSizePickerOptions(): SettingsPickOption[] {
    return BrowserStrings.fontSizeKeys().map((key: string): SettingsPickOption => ({
      key,
      label: BrowserStrings.fontSizeLabel(key)
    }))
  }

  build() {
    Stack() {
      Column() {
        Text($r('app.string.settings_browse'))
          .fontSize(this.uiFp(12))
          .fontColor(this.mutedColor())
          .padding({ left: 16, top: 12, bottom: 8 })

        this.SettingsRow(BrowserStrings.txt($r('app.string.search_engine')), () => {
          this.onOpenEngine?.()
        })

        Row() {
          Text($r('app.string.night_mode'))
            .fontSize(this.uiFp(15))
            .fontColor(this.titleColor())
            .layoutWeight(1)
          Text(BrowserStrings.themeModeLabel(this.themePreference))
            .fontSize(this.uiFp(14))
            .fontColor(this.mutedColor())
          NavChevronRight({ color: this.mutedColor(), iconSize: this.uiFp(18) })
            .margin({ left: 6 })
        }
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.cardBg())
        .onClick((): void => {
          this.showDarkModePicker = true
        })

        Row() {
          Text($r('app.string.image_less_mode'))
            .fontSize(this.uiFp(15))
            .fontColor(this.titleColor())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.imageLessMode })
            .onChange((on: boolean) => {
              void BrowserStore.setImageLessMode(on)
            })
        }
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.cardBg())

        this.SettingsRow(BrowserStrings.txt($r('app.string.clear_cookies_cache')), () => {
          this.onClearData?.()
        })

        Column() {
          Row() {
            Text($r('app.string.font_size'))
              .fontSize(this.uiFp(15))
              .fontColor(this.titleColor())
              .layoutWeight(1)
            SettingsInlinePicker({
              options: this.fontSizePickerOptions(),
              selectedKey: this.fontSize,
              isDark: this.isDark,
              menuWidth: 176,
              onSelect: (key: string) => {
                const normalized = BrowserStrings.normalizeFontSizeKey(key)
                this.fontSize = normalized
                void BrowserStore.setFontSize(normalized)
              }
            })
          }
          Text($r('app.string.font_size_system_sync_hint'))
            .fontSize(this.uiFp(11))
            .fontColor(this.mutedColor())
            .margin({ top: 6 })
        }
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.cardBg())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .key(`browse-settings-${this.fontUiRev}-${this.fontUiScale.toFixed(2)}-${this.fontSize}`)

      DarkModePickerDialog({
        visible: this.showDarkModePicker,
        onClose: (): void => {
          this.showDarkModePicker = false
        }
      })
    }
    .width('100%')
  }

  @Builder
  SettingsRow(title: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(this.uiFp(15))
        .fontColor(this.titleColor())
        .layoutWeight(1)
      NavChevronRight({ color: this.mutedColor(), iconSize: this.uiFp(18) })
    }
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.cardBg())
    .margin({ bottom: 1 })
    .onClick(onTap)
  }
}
