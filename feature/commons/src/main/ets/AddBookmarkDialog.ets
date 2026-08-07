import { BrowserTheme } from 'browser_core'
import { BrowserNavigation } from 'browser_core'
import { BrowserStrings } from 'common'
import { AppStorageKeys } from 'common'
import { BrowserStore } from 'browser_core'
import { BookmarkItem } from 'common'
import { BookmarkFolderPickRow, BookmarkFolderTree } from 'common'
import { FolderExpandChevron, NavChevronRight } from './BrowserIcons'
import { PanelCircleIconButton, PanelHeaderStyle } from './PanelSubpageHeader'

/** 添加书签编辑弹窗：网页标题作 placeholder，未输入时使用默认标题 */

@Component

export struct AddBookmarkDialog {

  @Prop @Watch('onVisibleChanged') visible: boolean = false

  /** 网页标题，作为输入框 placeholder 及空输入时的默认名称 */

  @Prop defaultTitle: string = ''

  /** 半模态样式（历史长按入口使用），默认仍为居中弹框 */

  @Prop halfModal: boolean = false

  /** 可选：展示 URL（半模态下用于对齐视觉稿） */

  @Prop url: string = ''

  onCancel?: () => void

  onConfirm?: (name: string, parentId: string) => void



  @State inputName: string = ''

  @State selectedParentId: string = ''

  @State showLocationPicker: boolean = false

  @State showNewFolderForm: boolean = false

  @State pickParentId: string = ''

  @State newFolderName: string = ''

  @State newFolderParent: string = ''

  @State locationCollapsedFolderIds: string[] = []

  @StorageLink(AppStorageKeys.THEME) theme: string = 'light'

  @StorageLink(AppStorageKeys.FONT_UI_SCALE) fontUiScale: number = 1

  @StorageLink(AppStorageKeys.BOOKMARKS) bookmarks: BookmarkItem[] = []

  private titleInputController: TextInputController = new TextInputController()
  private static readonly HALF_MODAL_HEIGHT: string = '70%'
  /** 半模态挂载后稍延迟再获焦，避免节点未就绪 */
  private static readonly TITLE_FOCUS_DELAY_MS: number = 150
  private titleFocusTimer: number = -1

  aboutToAppear(): void {
    // HistoryPanel 条件挂载时 visible 首帧即为 true，@Watch 不一定触发
    if (this.visible) {
      this.resetForOpen()
      this.scheduleTitleFocus()
    }
  }

  private onVisibleChanged(): void {
    if (this.visible) {
      this.resetForOpen()
      this.scheduleTitleFocus()
      return
    }
    this.clearTitleFocusTimer()
  }

  private resetForOpen(): void {
    this.inputName = this.defaultTitle.trim()
    this.selectedParentId = ''
    this.showLocationPicker = false
    this.showNewFolderForm = false
    this.pickParentId = ''
    this.newFolderName = ''
    this.newFolderParent = ''
    this.locationCollapsedFolderIds = []
  }

  private clearTitleFocusTimer(): void {
    if (this.titleFocusTimer >= 0) {
      clearTimeout(this.titleFocusTimer)
      this.titleFocusTimer = -1
    }
  }

  private scheduleTitleFocus(): void {
    if (!this.halfModal || this.showLocationPicker || this.showNewFolderForm) {
      return
    }
    this.clearTitleFocusTimer()
    this.titleFocusTimer = setTimeout((): void => {
      this.titleFocusTimer = -1
      if (!this.visible || this.showLocationPicker || this.showNewFolderForm) {
        return
      }
      focusControl.requestFocus('add_bookmark_title_input')
      try {
        this.titleInputController.caretPosition(this.inputName.length)
      } catch (_e) {
        // caretPosition 在部分版本不可用时不阻塞
      }
    }, AddBookmarkDialog.TITLE_FOCUS_DELAY_MS) as number
  }

  private isDark(): boolean {

    return this.theme === 'dark'

  }



  private uiFp(base: number): number {

    return BrowserTheme.scaledFp(base, this.fontUiScale)

  }



  private cardBg(): string {

    return BrowserTheme.panelBg(this.isDark())

  }



  private textColor(): string {

    return BrowserTheme.text(this.isDark())

  }



  private listPanelBg(): string {

    return this.isDark() ? '#2c2c2e' : '#eef0f3'

  }



  private resolveName(): string {

    const custom = this.inputName.trim()

    if (custom.length > 0) {

      return custom

    }

    return this.defaultTitle.trim()

  }



  private confirm(): void {

    const name = this.resolveName()

    if (name.length === 0) {

      return

    }

    this.onConfirm?.(name, this.selectedParentId)

  }



  private dismissOverlay(): void {

    if (this.showNewFolderForm) {

      this.showNewFolderForm = false

      return

    }

    if (this.showLocationPicker) {

      this.showLocationPicker = false

      return

    }

    this.onCancel?.()

  }



  private openLocationPicker(): void {
    this.clearTitleFocusTimer()
    try {
      this.titleInputController.stopEditing()
    } catch (_e) {
      // stopEditing 在部分版本不可用时不阻塞
    }
    this.pickParentId = this.selectedParentId
    this.locationCollapsedFolderIds = []
    this.showLocationPicker = true
  }



  private locationPickRows(): BookmarkFolderPickRow[] {
    return BookmarkFolderTree.folderPickRows(
      this.bookmarks,
      true,
      BrowserStrings.txt($r('app.string.bookmark_root_dir')),
      this.locationCollapsedFolderIds
    )
  }

  private selectFolder(folderId: string): void {
    this.pickParentId = folderId
  }

  private confirmLocationPicker(): void {
    this.selectedParentId = this.pickParentId
    this.showLocationPicker = false
    this.locationCollapsedFolderIds = []
  }

  private openNewFolderForm(): void {

    this.newFolderParent = this.pickParentId || this.selectedParentId

    this.newFolderName = ''

    this.showNewFolderForm = true

  }



  private saveNewFolder(): void {

    const name = this.newFolderName.trim()

    if (!name) {

      BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_name_required')))

      return

    }

    const parentId = this.newFolderParent

    void BrowserStore.addFolderEntry(name, parentId).then((ok) => {

      if (!ok) {

        BrowserStore.showToast(BrowserStrings.txt($r('app.string.folder_exists')))

        return

      }

      const folder = BrowserStore.getBookmarks().find((b) => {

        return b.isFolder && b.title === name && (b.parentId || '') === (parentId || '')

      })

      if (folder) {

        this.selectedParentId = folder.id

        this.pickParentId = folder.id

      }

      this.showNewFolderForm = false

      this.showLocationPicker = false

    })

  }



  private sheetBg(): string {

    return this.isDark() ? '#1c1c1e' : '#ffffff'

  }



  private sheetDivider(): string {

    return this.isDark() ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.08)'

  }



  @Builder

  HalfModalHeader(title: ResourceStr, showConfirm: boolean, onClose: () => void, onConfirm?: () => void) {

    Row() {

      Text('×')

        .fontSize(this.uiFp(20))

        .fontColor(this.textColor())

        .width(44)

        .height(44)

        .textAlign(TextAlign.Center)

        .onClick(() => onClose())



      Text(title)

        .fontSize(this.uiFp(17))

        .fontWeight(FontWeight.Medium)

        .fontColor(this.textColor())

        .layoutWeight(1)

        .textAlign(TextAlign.Center)



      if (showConfirm) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(this.uiFp(22))
          .fontColor([BrowserTheme.primaryColor(this.isDark())])
          .width(44)
          .height(44)
          .onClick(() => onConfirm?.())
      } else {
        Blank().width(44).height(44)
      }

    }

    .width('100%')

    .padding({ left: 8, right: 8, top: 6, bottom: 6 })

  }



  @Builder
  LocationTreeFolderRow(row: BookmarkFolderPickRow, isLast: boolean) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(this.uiFp(BookmarkFolderTree.ICON_SIZE))
          .fontColor([BrowserTheme.primaryColor(this.isDark())])
          .margin({ right: BookmarkFolderTree.ICON_GAP })

        Text(row.title)
          .fontSize(this.uiFp(15))
          .fontColor(this.textColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (row.hasChildren) {
          FolderExpandChevron({
            expanded: BookmarkFolderTree.isExpanded(row.id, this.locationCollapsedFolderIds),
            color: BrowserTheme.textMuted(this.isDark()),
            iconSize: this.uiFp(BookmarkFolderTree.CHEVRON_SIZE)
          })
            .padding({ left: 8, right: 8 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.locationCollapsedFolderIds =
                BookmarkFolderTree.toggleCollapsed(row.id, this.locationCollapsedFolderIds)
            })
        }
      }
      .width('100%')
      .padding({
        left: BookmarkFolderTree.indentLeft(row.depth, 12),
        right: 12,
        top: 12,
        bottom: 12
      })

      if (!isLast) {
        Divider()
          .color(this.sheetDivider())
          .strokeWidth(0.5)
          .margin({ left: BookmarkFolderTree.dividerStart(row.depth, 12), right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.pickParentId === row.id ?
      BrowserTheme.primaryLight(this.isDark()) : Color.Transparent)
    .onClick(() => {
      this.selectFolder(row.id)
    })
  }

  @Builder
  LocationPickerSheet() {
    Column() {
      Row() {
        PanelCircleIconButton({
          iconKind: 'back',
          darkMode: this.isDark(),
          onTap: () => {
            this.showLocationPicker = false
            this.locationCollapsedFolderIds = []
          }
        })

        Text($r('app.string.select_target_folder'))
          .fontSize(this.uiFp(17))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: PanelHeaderStyle.TITLE_GAP })
      }
      .width('100%')
      .padding({
        left: PanelHeaderStyle.H_PADDING,
        right: PanelHeaderStyle.H_PADDING,
        top: PanelHeaderStyle.V_PADDING,
        bottom: PanelHeaderStyle.V_PADDING
      })
      .alignItems(VerticalAlign.Center)

      Divider().color(this.sheetDivider()).strokeWidth(0.5).margin({ left: 16, right: 16 })

      Scroll() {
        Column() {
          ForEach(this.locationPickRows(), (row: BookmarkFolderPickRow, index: number) => {
            this.LocationTreeFolderRow(row, index === this.locationPickRows().length - 1)
          }, (row: BookmarkFolderPickRow) =>
            `${row.id}_${this.locationCollapsedFolderIds.length}_${this.pickParentId}_${this.bookmarks.length}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .margin({ left: 8, right: 8 })

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(44)
          .fontSize(this.uiFp(16))
          .fontColor(this.textColor())
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            this.showLocationPicker = false
            this.locationCollapsedFolderIds = []
          })
        Button($r('app.string.confirm'))
          .layoutWeight(1)
          .height(44)
          .fontSize(this.uiFp(16))
          .fontColor(Color.White)
          .backgroundColor(BrowserTheme.PRIMARY_COLOR)
          .onClick(() => {
            this.confirmLocationPicker()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    }
    .width('100%')
    .height(AddBookmarkDialog.HALF_MODAL_HEIGHT)
    .backgroundColor(this.sheetBg())
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 16 })
    .onClick(() => {
    })
  }



  @Builder

  NewFolderSheet() {

    Column() {

      this.HalfModalHeader($r('app.string.new_folder'), false, () => {

        this.showNewFolderForm = false

      })



      Divider().color(this.sheetDivider()).strokeWidth(0.5).margin({ left: 16, right: 16 })



      Column({ space: 12 }) {

        Text($r('app.string.folder_name_label'))

          .fontSize(this.uiFp(13))

          .fontColor(BrowserTheme.TEXT_MUTED)

          .width('100%')

        TextInput({ text: this.newFolderName, placeholder: $r('app.string.new_folder') })

          .fontSize(this.uiFp(15))

          .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)

          .onChange((v: string) => {

            BrowserNavigation.applyTextInputChange(v, this.newFolderName.length, (text: string) => {

              this.newFolderName = text

            })

          })

        Row() {

          Text($r('app.string.location_label'))

            .fontSize(this.uiFp(14))

            .fontColor(BrowserTheme.TEXT_MUTED)

          Blank().layoutWeight(1)

          Text(BrowserStore.folderLocationLabel(this.newFolderParent))

            .fontSize(this.uiFp(14))

            .fontColor(this.textColor())

            .maxLines(1)

            .textOverflow({ overflow: TextOverflow.Ellipsis })

            .constraintSize({ maxWidth: '50%' })

        }

        .width('100%')

        Row({ space: 12 }) {

          Button($r('app.string.cancel'))

            .layoutWeight(1)

            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))

            .fontColor(this.textColor())

            .onClick(() => {

              this.showNewFolderForm = false

            })

          Button($r('app.string.save'))

            .layoutWeight(1)

            .onClick(() => {

              this.saveNewFolder()

            })

        }

        .width('100%')

      }

      .width('100%')

      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

    }
    .width('100%')
    .height(AddBookmarkDialog.HALF_MODAL_HEIGHT)
    .backgroundColor(this.sheetBg())
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 16 })
    .onClick(() => {
    })
  }

  @Builder
  AddBookmarkHalfSheet() {

    Column() {

      this.HalfModalHeader($r('app.string.add_to_bookmarks'), true, () => {

        this.onCancel?.()

      }, () => {

        this.confirm()

      })



      Divider().color(this.sheetDivider()).strokeWidth(0.5).margin({ left: 16, right: 16 })



      Column({ space: 0 }) {

        Row() {

          TextInput({ text: this.inputName, placeholder: this.defaultTitle, controller: this.titleInputController })
            .id('add_bookmark_title_input')
            .layoutWeight(1)
            .fontSize(this.uiFp(16))
            .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)
            .backgroundColor(Color.Transparent)
            .padding({ left: 16, right: 8, top: 10, bottom: 10 })
            .defaultFocus(true)
            .enableKeyboardOnFocus(true)
            .onChange((v: string) => {
              BrowserNavigation.applyTextInputChange(v, this.inputName.length, (text: string) => {
                this.inputName = text
              })
            })



          if (this.inputName.length > 0) {

            Text('×')

              .fontSize(this.uiFp(18))

              .fontColor(BrowserTheme.TEXT_MUTED)

              .width(36)

              .height(36)

              .textAlign(TextAlign.Center)

              .margin({ right: 8 })

              .onClick(() => {

                this.inputName = ''

              })

          }

        }

        .width('100%')

        .alignItems(VerticalAlign.Center)



        if (this.url.trim().length > 0) {

          Divider().color(this.sheetDivider()).strokeWidth(0.5).margin({ left: 16, right: 16 })

          Text(this.url)

            .fontSize(this.uiFp(13))

            .fontColor(BrowserTheme.TEXT_MUTED)

            .padding({ left: 16, right: 16, top: 10, bottom: 10 })

            .maxLines(2)

            .textOverflow({ overflow: TextOverflow.Ellipsis })

        }



        Divider().color(this.sheetDivider()).strokeWidth(0.5).margin({ left: 16, right: 16 })

        Row() {

          Text($r('app.string.location_label'))

            .fontSize(this.uiFp(14))

            .fontColor(this.textColor())

          Row() {

            Text(BrowserStore.folderLocationLabel(this.selectedParentId))

              .fontSize(this.uiFp(14))

              .fontColor(BrowserTheme.TEXT_MUTED)

              .margin({ right: 6 })

            NavChevronRight({ color: BrowserTheme.TEXT_MUTED, iconSize: this.uiFp(14) })

          }

        }

        .width('100%')

        .justifyContent(FlexAlign.SpaceBetween)

        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        .onClick(() => {

          this.openLocationPicker()

        })

      }

      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(AddBookmarkDialog.HALF_MODAL_HEIGHT)
    .backgroundColor(this.sheetBg())
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 12 })
    .onClick(() => {
    })
  }

  build() {

    if (!this.visible) {

      Column()

    } else {

      Stack({ alignContent: this.halfModal ? Alignment.Bottom : Alignment.Center }) {

        Column()

          .width('100%')

          .height('100%')

          .backgroundColor('rgba(0,0,0,0.45)')

          .onClick(() => {

            this.dismissOverlay()

          })



        if (this.halfModal) {

          if (this.showNewFolderForm) {

            this.NewFolderSheet()

          } else if (this.showLocationPicker) {

            this.LocationPickerSheet()

          } else {

            this.AddBookmarkHalfSheet()

          }

        } else {

          Column({ space: 16 }) {

            Text($r('app.string.new_bookmark'))

              .fontSize(this.uiFp(17))

              .fontWeight(FontWeight.Bold)

              .fontColor(this.textColor())

            TextInput({ text: this.inputName, placeholder: this.defaultTitle })

              .fontSize(this.uiFp(15))

              .maxLength(BrowserNavigation.INPUT_MAX_LENGTH)

              .onChange((v: string) => {

                BrowserNavigation.applyTextInputChange(v, this.inputName.length, (text: string) => {

                  this.inputName = text

                })

              })

            Row({ space: 12 }) {

              Button($r('app.string.cancel'))

                .layoutWeight(1)

                .backgroundColor($r('sys.color.ohos_id_color_button_normal'))

                .fontColor(this.textColor())

                .onClick(() => {

                  this.onCancel?.()

                })

              Button($r('app.string.save'))

                .layoutWeight(1)

                .onClick(() => {

                  this.confirm()

                })

            }

            .width('100%')

          }

          .width('85%')

          .padding(24)

          .backgroundColor(this.cardBg())

          .borderRadius(16)

          .onClick(() => {

          })

        }

      }

      .width('100%')

      .height('100%')

      .zIndex(6600)

    }

  }

}


