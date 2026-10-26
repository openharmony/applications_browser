import { SettingsLayoutPolicy } from '../settingsLayoutPolicy';

export interface SettingsNavigationItem {
  id: string;
  label: string;
  normalIcon: Resource;
  selectedIcon: Resource;
  enabled: boolean;
  // 是否在侧边栏中显示；false 时保留配置但隐藏入口，改回 true 即可恢复显示。
  visible?: boolean;
}

@Component
export struct SettingsSidebar {
  @Prop items: SettingsNavigationItem[] = [];
  @Prop activeItemId: string = '';
  @Prop compact: boolean = false;
  onSelectItem: (itemId: string) => void = (_: string): void => {};
  onBack: () => void = (): void => {};
  @State private hoveredItemId: string = '';
  @State private focusedItemId: string = '';
  @State private isBackHovered: boolean = false;

  private getItemBackgroundColor(item: SettingsNavigationItem): string {
    if (this.activeItemId === item.id) {
      return '#e3f2fd';
    }
    if (this.hoveredItemId === item.id) {
      return item.enabled ? '#f1f6fd' : '#f7f7f7';
    }
    if (this.focusedItemId === item.id) {
      return '#f1f6fd';
    }
    return '#ffffff';
  }

  private getItemAccentColor(item: SettingsNavigationItem): string {
    if (this.activeItemId === item.id) {
      return '#1976d2';
    }
    if (this.focusedItemId === item.id) {
      return '#7aa7dc';
    }
    return '#00000000';
  }

  private getItemTextColor(item: SettingsNavigationItem): string {
    if (!item.enabled) {
      return '#8a8a8a';
    }
    return this.activeItemId === item.id || this.hoveredItemId === item.id ? '#1976d2' : '#333333';
  }

  @Builder
  private NavigationItem(item: SettingsNavigationItem) {
    Button() {
      Row({ space: this.compact ? 0 : 12 }) {
        Image(this.activeItemId === item.id ? item.selectedIcon : item.normalIcon)
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .opacity(item.enabled ? 1 : 0.6);

        if (!this.compact) {
          Text(item.label)
            .layoutWeight(1)
            .fontSize(14)
            .fontWeight(this.activeItemId === item.id ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.getItemTextColor(item))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.compact ? 0 : 21, right: this.compact ? 0 : 20 })
      .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start);
    }
    .type(ButtonType.Normal)
    .width('100%')
    .height(52)
    .padding(0)
    .borderRadius(0)
    .hoverEffect(HoverEffect.None)
    .backgroundColor(this.getItemBackgroundColor(item))
    .border({
      width: { left: 3 },
      color: this.getItemAccentColor(item),
    })
    .opacity(item.enabled ? 1 : 0.68)
    .focusable(item.enabled)
    .accessibilityText(item.label)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .mouseResponseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .bindPopup((this.compact || !item.enabled) && this.hoveredItemId === item.id, {
      message: item.enabled ? item.label : `${item.label}（暂不可用）`,
      placement: Placement.Right,
      enableArrow: true,
      mask: false,
      showInSubWindow: false,
    })
    .onHover((isHover: boolean) => {
      this.hoveredItemId = isHover ? item.id : '';
    })
    .onFocus(() => {
      this.focusedItemId = item.enabled ? item.id : '';
    })
    .onBlur(() => {
      if (this.focusedItemId === item.id) {
        this.focusedItemId = '';
      }
    })
    .onClick(() => {
      if (item.enabled) {
        this.onSelectItem(item.id);
      }
    });
  }

  private getVisibleItems(): SettingsNavigationItem[] {
    return this.items.filter((item: SettingsNavigationItem) => item.visible !== false);
  }

  build() {
    Column() {
      Row({ space: this.compact ? 0 : 12 }) {
        Button() {
          Text('‹')
            .fontSize(28)
            .fontColor('#5f6368')
            .margin({ bottom: 3 });
        }
        .type(ButtonType.Circle)
        .width(44)
        .height(44)
        .padding(0)
        .hoverEffect(HoverEffect.None)
        .backgroundColor(this.isBackHovered ? '#f1f3f4' : '#00000000')
        .borderRadius(22)
        .accessibilityText('返回浏览器')
        .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
        .mouseResponseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
        .onHover((isHover: boolean) => {
          this.isBackHovered = isHover;
        })
        .onClick(() => this.onBack());

        if (!this.compact) {
          Text('设置')
            .fontSize(24)
            .fontWeight(FontWeight.Regular)
            .fontColor('#333333');
        }
      }
      .width('100%')
      .height(72)
      .padding({ left: this.compact ? 0 : 20, right: this.compact ? 0 : 16 })
      .justifyContent(this.compact ? FlexAlign.Center : FlexAlign.Start);

      List() {
        ForEach(this.getVisibleItems(), (item: SettingsNavigationItem) => {
          ListItem() {
            this.NavigationItem(item);
          }
          .width('100%');
        }, (item: SettingsNavigationItem) => item.id);
      }
      .width('100%')
      .layoutWeight(1)
      .cachedCount(this.items.length)
      .scrollBar(BarState.Auto);
    }
    .width(SettingsLayoutPolicy.getNavigationWidth(this.compact))
    .height('100%')
    .backgroundColor('#ffffff')
    .border({ width: { right: 1 }, color: '#e0e0e0' });
  }
}
