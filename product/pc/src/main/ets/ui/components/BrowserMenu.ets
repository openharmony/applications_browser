export interface BrowserMenuItem {
  id: string;
  label: string;
  leadingIcon?: string;
  leadingIconResource?: Resource;
  shortcut?: string;
  disabled?: boolean;
  checked?: boolean;
  danger?: boolean;
  dividerBefore?: boolean;
  hoverHighlightDisabled?: boolean;
  showArrow?: boolean;
  trailingText?: string;
  kind?: 'action' | 'zoom';
  zoomPercent?: number;
}

export interface BrowserSubMenuState {
  visible: boolean;
  items: BrowserMenuItem[];
  activeItemId: string;
  anchorX: number;
  anchorY: number;
  menuWidth: number;
}

@Component
export struct BrowserMenu {
  @Prop title: string = '';
  @Prop items: BrowserMenuItem[] = [];
  @Prop activeItemId: string = '';
  @Prop anchorX: number = 0;
  @Prop anchorY: number = 0;
  @Prop menuWidth: number = 228;
  @Prop maxMenuHeight: number = 640;
  @Prop maxSubMenuHeight: number = 360;
  @Prop zoomPercent: number = 100;
  @Prop useAbsolutePosition: boolean = true;
  @Prop dismissOnOutsideClick: boolean = true;
  @Prop subMenuState: BrowserSubMenuState = {
    visible: false,
    items: [],
    activeItemId: '',
    anchorX: 0,
    anchorY: 0,
    menuWidth: 220,
  };

  onSelectItem: (item: BrowserMenuItem) => void = (_: BrowserMenuItem): void => {};
  onHoverItem: (item: BrowserMenuItem) => void = (_: BrowserMenuItem): void => {};
  onSelectSubMenuItem: (item: BrowserMenuItem) => void = (_: BrowserMenuItem): void => {};
  onHoverSubMenuItem: (item: BrowserMenuItem) => void = (_: BrowserMenuItem): void => {};
  onZoomOut: () => void = (): void => {};
  onZoomIn: () => void = (): void => {};
  onZoomReset: () => void = (): void => {};
  onRequestClose: () => void = (): void => {};
  @Prop canZoomOut: boolean = true;
  @Prop canZoomIn: boolean = true;

  private canHoverHighlight(item: BrowserMenuItem): boolean {
    return !item.disabled && item.hoverHighlightDisabled !== true;
  }

  private isActive(item: BrowserMenuItem): boolean {
    return this.activeItemId.length > 0 && this.activeItemId === item.id;
  }

  private getLeadingIcon(item: BrowserMenuItem): string {
    return item.leadingIcon ?? '';
  }

  @Builder
  private LeadingIcon(item: BrowserMenuItem) {
    if (item.leadingIconResource) {
      Image(item.leadingIconResource)
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .opacity(item.disabled ? 0.4 : 1);
    } else {
      Text(item.checked ? '✓' : this.getLeadingIcon(item))
        .width(18)
        .fontSize(15)
        .fontColor(item.disabled ? '#c7cdd8' : (item.checked ? '#2563eb' : '#6b7280'))
        .textAlign(TextAlign.Center);
    }
  }

  private getZoomButtonBackground(item: BrowserMenuItem, enabled: boolean): string {
    if (item.disabled || !enabled) {
      return '#f8fafc';
    }
    return '#ffffff';
  }

  private getZoomButtonBorder(item: BrowserMenuItem, enabled: boolean): string {
    if (item.disabled || !enabled) {
      return '#e5e7eb';
    }
    return '#d1d5db';
  }

  private getZoomButtonText(item: BrowserMenuItem, enabled: boolean): string {
    if (item.disabled || !enabled) {
      return '#c7cdd8';
    }
    return '#4b5563';
  }

  private handleSelectItem(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }
    this.onSelectItem(item);
  }

  private handleSelectSubMenuItem(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }
    this.onSelectSubMenuItem(item);
  }

  private handleHoverItem(item: BrowserMenuItem): void {
    if (!this.canHoverHighlight(item)) {
      return;
    }
    this.onHoverItem(item);
  }

  private handleHoverSubMenuItem(item: BrowserMenuItem): void {
    if (item.disabled) {
      return;
    }
    this.onHoverSubMenuItem(item);
  }

  private handleZoomOut(item: BrowserMenuItem): void {
    if (item.disabled || !this.canZoomOut) {
      return;
    }
    this.onZoomOut();
  }

  private handleZoomIn(item: BrowserMenuItem): void {
    if (item.disabled || !this.canZoomIn) {
      return;
    }
    this.onZoomIn();
  }

  private getResolvedZoomPercent(item: BrowserMenuItem): number {
    return Math.round(this.zoomPercent > 0 ? this.zoomPercent : (item.zoomPercent ?? 100));
  }

  @Builder
  private ZoomButton(label: string, enabled: boolean, item: BrowserMenuItem, onPress: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      Text(label)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getZoomButtonText(item, enabled))
        .textAlign(TextAlign.Center);
    }
    .width(32)
    .height(32)
    .backgroundColor(this.getZoomButtonBackground(item, enabled))
    .borderRadius(8)
    .border({ width: 1, color: this.getZoomButtonBorder(item, enabled) })
    .opacity(!item.disabled && enabled ? 1 : 0.72)
    .onClick(() => {
      if (!item.disabled && enabled) {
        onPress();
      }
    });
  }

  @Builder
  private ZoomRow(item: BrowserMenuItem) {
    Row() {
      Row({ space: 10 }) {
        this.LeadingIcon(item);

        Text(item.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(item.disabled ? '#c7cdd8' : '#111827');
      }

      Blank();

      Row({ space: 10 }) {
        this.ZoomButton('-', this.canZoomOut, item, () => this.handleZoomOut(item));

        Text(`${this.getResolvedZoomPercent(item)}%`)
          .width(52)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(item.disabled ? '#c7cdd8' : '#111827')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (!item.disabled && this.getResolvedZoomPercent(item) !== 100) {
              this.onZoomReset();
            }
          });

        this.ZoomButton('+', this.canZoomIn, item, () => this.handleZoomIn(item));
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.canHoverHighlight(item) && this.isActive(item) ? '#f9fafb' : '#ffffff')
    .opacity(item.disabled ? 0.72 : 1)
    .onMouse((_event: MouseEvent) => this.handleHoverItem(item));
  }

  @Builder
  private ActionRow(item: BrowserMenuItem) {
    Row() {
      this.LeadingIcon(item);

      Text(item.label)
        .layoutWeight(1)
        .margin({ left: 12 })
        .fontSize(14)
        .fontColor(item.disabled ? '#c7cdd8' : (item.danger ? '#dc2626' : '#111827'));

      if (item.trailingText) {
        Text(item.trailingText)
          .fontSize(12)
          .fontColor(item.disabled ? '#d1d5db' : '#6b7280');
      }

      if (item.shortcut) {
        Text(item.shortcut)
          .fontSize(12)
          .fontColor(item.disabled ? '#d1d5db' : '#6b7280');
      }

      if (item.showArrow) {
        Text('›')
          .margin({ left: 8 })
          .fontSize(15)
          .fontColor(item.disabled ? '#d1d5db' : '#6b7280');
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.canHoverHighlight(item) && this.isActive(item) ? '#f4f6f8' : '#ffffff')
    .opacity(item.disabled ? 0.72 : 1)
    .onMouse((_event: MouseEvent) => this.handleHoverItem(item))
    .onClick(() => this.handleSelectItem(item));
  }

  @Builder
  private MenuContent(items: BrowserMenuItem[], activeItemId: string, isSubMenu: boolean = false) {
    Column({ space: 0 }) {
      if (!isSubMenu && this.title.length > 0) {
        Row() {
          Text(this.title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })
        .border({ width: { bottom: 1 }, color: '#eef2f7' });
      }

      Scroll() {
        Column({ space: 0 }) {
          ForEach(items, (item: BrowserMenuItem) => {
            Column({ space: 0 }) {
              if (item.dividerBefore) {
                Divider()
                  .color('#edf1f5')
                  .margin({ left: 16, right: 16, top: 5, bottom: 5 });
              }

              if (item.kind === 'zoom') {
                this.ZoomRow(item);
              } else {
                if (isSubMenu) {
                  Row() {
                    this.LeadingIcon(item);

                    Text(item.label)
                      .layoutWeight(1)
                      .margin({ left: 12 })
                      .fontSize(14)
                      .fontColor(item.disabled ? '#c7cdd8' : (item.danger ? '#dc2626' : '#111827'));
                  }
                  .width('100%')
                  .height(42)
                  .padding({ left: 16, right: 16 })
                  .backgroundColor(!item.disabled && activeItemId === item.id ? '#f4f6f8' : '#ffffff')
                  .opacity(item.disabled ? 0.72 : 1)
                  .onMouse((_event: MouseEvent) => this.handleHoverSubMenuItem(item))
                  .onClick(() => this.handleSelectSubMenuItem(item));
                } else {
                  this.ActionRow(item);
                }
              }
            }
          }, (item: BrowserMenuItem) => item.id);
        }
        .width('100%');
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .constraintSize({ maxHeight: isSubMenu ? this.maxSubMenuHeight : this.maxMenuHeight });
    }
    .width(isSubMenu ? this.subMenuState.menuWidth : this.menuWidth)
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .border({ width: 1, color: '#e7ebf0' })
    .shadow({ radius: 24, color: '#22000000', offsetX: 0, offsetY: 8 })
    .onClick(() => {});
  }

  @Builder
  private OutsideDismissLayer() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onClick(() => this.onRequestClose());
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.dismissOnOutsideClick) {
        this.OutsideDismissLayer();
      }

      if (this.useAbsolutePosition) {
        Column() {
          this.MenuContent(this.items, this.activeItemId, false);
        }
        .position({ x: this.anchorX, y: this.anchorY });

        if (this.subMenuState.visible) {
          Column() {
            this.MenuContent(this.subMenuState.items, this.subMenuState.activeItemId, true);
          }
          .position({
            x: this.anchorX + this.subMenuState.anchorX,
            y: this.anchorY + this.subMenuState.anchorY,
          });
        }
      } else {
        this.MenuContent(this.items, this.activeItemId, false);
        if (this.subMenuState.visible) {
          Column() {
            this.MenuContent(this.subMenuState.items, this.subMenuState.activeItemId, true);
          }
          .position({ x: this.subMenuState.anchorX, y: this.subMenuState.anchorY });
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}
