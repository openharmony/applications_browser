// BrowserContextMenu：网页内容区域的轻量右键菜单。

export interface BrowserContextMenuItem {
  id: string;
  label: string;
  leadingIcon?: string;
  // 图片图标（本地资源或网络 favicon）。设置后优先于 leadingIcon 渲染。
  leadingImage?: ResourceStr;
  shortcut?: string;
  disabled?: boolean;
  dividerBefore?: boolean;
}

@Component
export struct BrowserContextMenu {
  @Prop items: BrowserContextMenuItem[] = [];
  @Prop anchorX: number = 0;
  @Prop anchorY: number = 0;
  @Prop menuWidth: number = 248;
  @Prop maxMenuHeight: number = 420;
  // 可选的菜单内拖拽排序：仅书签文件夹弹出菜单开启，其它调用方保持纯展示。
  @Prop reorderEnabled: boolean = false;

  @State private hoveredItemId: string = '';
  @State private draggingItemId: string = '';
  @State private dragOverItemId: string = '';
  @State private failedImageIds: string[] = [];

  onSelectItem: (item: BrowserContextMenuItem) => void = (_item: BrowserContextMenuItem): void => {};
  onDismiss: () => void = (): void => {};
  onReorderItem: (sourceItemId: string, targetItemId: string) => void =
    (_sourceItemId: string, _targetItemId: string): void => {};
  // 拖拽会话起止上报：宿主可据此把拖拽源提升为页面级状态（跨组件拖出场景）。
  onReorderDragStart: (itemId: string) => void = (_itemId: string): void => {};
  onReorderDragEnd: () => void = (): void => {};

  private isItemDraggable(item: BrowserContextMenuItem): boolean {
    return this.reorderEnabled && !item.disabled;
  }

  private clearDragState(): void {
    this.draggingItemId = '';
    this.dragOverItemId = '';
  }

  private isItemHovered(item: BrowserContextMenuItem): boolean {
    return !item.disabled && this.hoveredItemId === item.id;
  }

  private getItemTextColor(item: BrowserContextMenuItem): string {
    return item.disabled ? '#aeb6c2' : '#20252d';
  }

  private getItemIconColor(item: BrowserContextMenuItem): string {
    return item.disabled ? '#c5ccd6' : '#5f6875';
  }

  private hasLeadingImage(item: BrowserContextMenuItem): boolean {
    return item.leadingImage !== undefined && item.leadingImage !== '';
  }

  // 网络 favicon 加载失败时回退到默认站点图标，避免菜单里出现空图占位。
  private getMenuImageSource(item: BrowserContextMenuItem): ResourceStr {
    if (this.failedImageIds.indexOf(item.id) >= 0) {
      return $r('app.media.default_site_icon');
    }
    return item.leadingImage ?? '';
  }

  private markMenuImageFailed(item: BrowserContextMenuItem): void {
    if (this.failedImageIds.indexOf(item.id) >= 0) {
      return;
    }
    this.failedImageIds = this.failedImageIds.concat([item.id]);
  }

  private handleSelect(item: BrowserContextMenuItem): void {
    if (item.disabled) {
      return;
    }
    this.onSelectItem(item);
  }

  @Builder
  private MenuContent() {
    Column({ space: 0 }) {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.items, (item: BrowserContextMenuItem) => {
            Column({ space: 0 }) {
              if (item.dividerBefore) {
                Divider()
                  .color('#edf0f4')
                  .margin({ left: 10, right: 10, top: 5, bottom: 5 });
              }

              Row({ space: 10 }) {
                if (this.hasLeadingImage(item)) {
                  Image(this.getMenuImageSource(item))
                    .width(16)
                    .height(16)
                    .borderRadius(3)
                    .objectFit(ImageFit.Contain)
                    .onError(() => this.markMenuImageFailed(item));
                } else {
                  Text(item.leadingIcon ?? '')
                    .width(18)
                    .fontSize(15)
                    .fontColor(this.getItemIconColor(item))
                    .textAlign(TextAlign.Center);
                }

                Text(item.label)
                  .layoutWeight(1)
                  .fontSize(14)
                  .fontColor(this.getItemTextColor(item))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });

                if (item.shortcut) {
                  Text(item.shortcut)
                    .fontSize(12)
                    .fontColor(item.disabled ? '#c5ccd6' : '#8a929e');
                }
              }
              .width('100%')
              .height(40)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.isItemHovered(item) ? '#f1f4f8' : '#ffffff')
              .border({
                width: this.dragOverItemId === item.id && this.draggingItemId !== '' ? 2 : 0,
                color: '#1976d2',
              })
              .borderRadius(4)
              .opacity(item.disabled ? 0.72 : 1)
              .onHover((isHover: boolean) => {
                if (isHover) {
                  this.hoveredItemId = item.disabled ? '' : item.id;
                } else if (this.hoveredItemId === item.id) {
                  this.hoveredItemId = '';
                }
              })
              .onClick(() => this.handleSelect(item))
              .draggable(this.isItemDraggable(item))
              .onDragStart(() => {
                this.draggingItemId = item.id;
                this.onReorderDragStart(item.id);
              })
              .onDragEnter(() => {
                if (this.draggingItemId !== '' && this.draggingItemId !== item.id && !item.disabled) {
                  this.dragOverItemId = item.id;
                }
              })
              .onDragLeave(() => {
                if (this.dragOverItemId === item.id) {
                  this.dragOverItemId = '';
                }
              })
              .onDrop(() => {
                const sourceItemId = this.draggingItemId;
                if (sourceItemId === '' || sourceItemId === item.id || item.disabled) {
                  this.clearDragState();
                  return;
                }
                this.onReorderItem(sourceItemId, item.id);
                this.clearDragState();
              })
              .onDragEnd(() => {
                this.clearDragState();
                this.onReorderDragEnd();
              });
            }
          }, (item: BrowserContextMenuItem) => item.id);
        }
        .width('100%');
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .constraintSize({ maxHeight: this.maxMenuHeight });
    }
    .width(this.menuWidth)
    .backgroundColor('#ffffff')
    .borderRadius(10)
    .border({ width: 1, color: '#dfe4eb' })
    .shadow({ radius: 18, color: '#28000000', offsetX: 0, offsetY: 6 })
    .onClick(() => {});
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 拖拽排序进行中不渲染背景捕获层：backdrop 一旦存在（哪怕 Transparent、
      // 哪怕只挂 onDrop），都可能被 drag 命中测试当作最上层 drop 目标，书签栏
      // 收不到 onDragEnter/onDrop。drag move 是实时命中测试，移除后事件直达下层。
      // 拖拽结束（onDragEnd）清状态后 backdrop 恢复，点击空白关闭菜单不受影响。
      if (!(this.reorderEnabled && this.draggingItemId !== '')) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000000')
          .onClick(() => this.onDismiss());
      }

      Column() {
        this.MenuContent();
      }
      .position({ x: this.anchorX, y: this.anchorY });
    }
    .width('100%')
    .height('100%')
    .zIndex(5);
  }
}
