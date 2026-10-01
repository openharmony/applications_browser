import { KeyCode } from '@kit.InputKit';
import { AppRoute, AppRouter } from '../../core/appRouter';
import { BrowserMenu, BrowserMenuItem } from '../components/BrowserMenu';

type PlaygroundOverlayKind = 'none' | 'main_menu' | 'context_menu' | 'panel' | 'confirm_dialog';

@Component
export struct OverlayPlaygroundPage {
  @Link route: AppRoute;

  @State private overlayKind: PlaygroundOverlayKind = 'none';
  @State private overlayTitle: string = '';
  @State private anchorX: number = 0;
  @State private anchorY: number = 0;
  @State private anchorWidth: number = 0;
  @State private activeMenuIndex: number = 0;
  @State private selectedActionText: string = '暂无';
  @State private overlayStateText: string = '未打开';
  @State private focusReturnTarget: string = '无';
  @State private panelZoomPercent: number = 100;
  @State private findText: string = '';
  @State private logs: string[] = ['页面已就绪，可开始验证菜单与弹窗交互'];

  private readonly mainMenuX: number = 556;
  private readonly mainMenuY: number = 164;
  private readonly contextMenuX: number = 300;
  private readonly contextMenuY: number = 332;
  private readonly panelX: number = 510;
  private readonly panelY: number = 246;

  private getCurrentMenuItems(): BrowserMenuItem[] {
    if (this.overlayKind === 'main_menu') {
      return [
        { id: 'new_tab', label: '新建标签页', shortcut: 'Ctrl+T' },
        // 暂时预留，后期完善：无痕模式当前不对用户开放。
        { id: 'show_bookmark_bar', label: '显示书签栏', checked: true, dividerBefore: true },
        { id: 'downloads', label: '打开下载页' },
        { id: 'zoom_panel', label: '打开缩放面板', shortcut: 'Ctrl++' },
        { id: 'settings', label: '设置', dividerBefore: true, hoverHighlightDisabled: true },
        { id: 'exit', label: '退出浏览器', danger: true }
      ];
    }

    return [
      { id: 'reload_tab', label: '重新加载标签页', shortcut: 'Ctrl+R' },
      { id: 'duplicate_tab', label: '复制标签页' },
      { id: 'mute_tab', label: '使此网页静音' },
      { id: 'close_other_tabs', label: '关闭其他标签页', dividerBefore: true },
      { id: 'close_tab', label: '关闭标签页', shortcut: 'Ctrl+W', danger: true }
    ];
  }

  private hasOverlay(): boolean {
    return this.overlayKind !== 'none';
  }

  private isMenuOverlay(): boolean {
    return this.overlayKind === 'main_menu' || this.overlayKind === 'context_menu';
  }

  private getEnabledMenuIndex(startIndex: number, step: number): number {
    const items = this.getCurrentMenuItems();
    if (items.length === 0) {
      return 0;
    }

    let index = startIndex;
    for (let count = 0; count < items.length; count++) {
      if (!items[index].disabled) {
        return index;
      }
      index = (index + step + items.length) % items.length;
    }
    return 0;
  }

  private getMenuItemIndex(itemId: string): number {
    return this.getCurrentMenuItems().findIndex(item => item.id === itemId);
  }

  private canHoverHighlight(item: BrowserMenuItem): boolean {
    return !item.disabled && item.hoverHighlightDisabled !== true;
  }

  private appendLog(message: string): void {
    const timestamp = new Date().toLocaleTimeString();
    this.logs = [`${timestamp}  ${message}`, ...this.logs].slice(0, 14);
  }

  private markOverlayOpened(
    kind: PlaygroundOverlayKind,
    title: string,
    x: number,
    y: number,
    focusTarget: string
  ): void {
    this.overlayKind = kind;
    this.overlayTitle = title;
    this.anchorX = x;
    this.anchorY = y;
    this.anchorWidth = 228;
    this.focusReturnTarget = focusTarget;
    this.overlayStateText = `${title} 已打开`;
    this.activeMenuIndex = this.getEnabledMenuIndex(0, 1);
    this.appendLog(`${title} 打开，等待交互验证`);
  }

  private openMainMenu(): void {
    this.markOverlayOpened('main_menu', '主菜单', this.mainMenuX, this.mainMenuY, '主菜单触发按钮');
  }

  private openContextMenu(): void {
    this.markOverlayOpened(
      'context_menu',
      '标签页右键菜单',
      this.contextMenuX,
      this.contextMenuY,
      '标签页右键触发区'
    );
  }

  private openPanel(): void {
    this.overlayKind = 'panel';
    this.overlayTitle = '缩放与页内查找面板';
    this.anchorX = this.panelX;
    this.anchorY = this.panelY;
    this.anchorWidth = 280;
    this.focusReturnTarget = '轻面板触发按钮';
    this.overlayStateText = '缩放与页内查找面板已打开';
    this.appendLog('轻面板打开，可验证非模态内容更新');
  }

  private openConfirmDialog(): void {
    this.overlayKind = 'confirm_dialog';
    this.overlayTitle = '危险操作确认弹窗';
    this.focusReturnTarget = '确认弹窗触发按钮';
    this.overlayStateText = '危险操作确认弹窗已打开';
    this.appendLog('确认弹窗打开，可验证模态行为与主次操作');
  }

  private closeOverlay(reason: string): void {
    if (!this.hasOverlay()) {
      return;
    }
    const closingTitle = this.overlayTitle;
    this.overlayKind = 'none';
    this.overlayTitle = '';
    this.overlayStateText = `已关闭（${reason}）`;
    this.appendLog(`${closingTitle || '浮层'} 关闭，原因：${reason}`);
    this.appendLog(`焦点应回到：${this.focusReturnTarget}`);
  }

  private applyMenuAction(item: BrowserMenuItem): void {
    if (item.disabled) {
      this.appendLog(`点击被忽略：${item.label} 当前禁用`);
      return;
    }

    if (item.id === 'zoom_panel') {
      this.selectedActionText = `已执行：${item.label}`;
      this.appendLog(`执行菜单项：${item.label}`);
      this.openPanel();
      return;
    }

    this.selectedActionText = `已执行：${item.label}`;
    this.appendLog(`执行菜单项：${item.label}`);
    this.closeOverlay(`执行菜单项 ${item.label}`);
  }

  private adjustZoom(delta: number): void {
    const nextValue = this.panelZoomPercent + delta;
    this.panelZoomPercent = nextValue < 25 ? 25 : (nextValue > 300 ? 300 : nextValue);
    this.selectedActionText = `缩放调整到 ${this.panelZoomPercent}%`;
    this.appendLog(`缩放值更新为 ${this.panelZoomPercent}%`);
  }

  private handleOutsidePress(): void {
    if (!this.hasOverlay()) {
      return;
    }
    this.closeOverlay('点击外部区域');
  }

  private handleMenuItemMouseMove(item: BrowserMenuItem): void {
    if (!this.canHoverHighlight(item)) {
      return;
    }

    const nextIndex = this.getMenuItemIndex(item.id);
    if (nextIndex === -1 || nextIndex === this.activeMenuIndex) {
      return;
    }

    this.activeMenuIndex = nextIndex;
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || !this.hasOverlay()) {
      return false;
    }

    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeOverlay('按下 Esc');
      return true;
    }

    if (this.isMenuOverlay()) {
      if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
        this.activeMenuIndex = this.getEnabledMenuIndex(
          (this.activeMenuIndex + 1) % this.getCurrentMenuItems().length,
          1
        );
        this.appendLog(`键盘下移高亮到：${this.getCurrentMenuItems()[this.activeMenuIndex].label}`);
        return true;
      }

      if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
        const items = this.getCurrentMenuItems();
        this.activeMenuIndex = this.getEnabledMenuIndex((this.activeMenuIndex - 1 + items.length) % items.length, -1);
        this.appendLog(`键盘上移高亮到：${this.getCurrentMenuItems()[this.activeMenuIndex].label}`);
        return true;
      }

      if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
        this.applyMenuAction(this.getCurrentMenuItems()[this.activeMenuIndex]);
        return true;
      }
    }

    return false;
  }

  @Builder
  private InfoCard(title: string, value: string, accentColor: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(12)
        .fontColor('#6b7280');

      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(accentColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start)
    .width('32%')
    .padding(12)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .border({ width: 1, color: '#e5e7eb' });
  }

  @Builder
  private TriggerCard(title: string, desc: string, actionText: string, onPress: () => void) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827');

      Text(desc)
        .fontSize(12)
        .fontColor('#6b7280');

      Button(actionText)
        .height(34)
        .fontSize(13)
        .backgroundColor('#2563eb')
        .fontColor('#ffffff')
        .borderRadius(17)
        .onClick(() => onPress());
    }
    .alignItems(HorizontalAlign.Start)
    .width('48%')
    .padding(14)
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .border({ width: 1, color: '#dbe3f0' });
  }

  @Builder
  private MenuOverlay() {
    BrowserMenu({
      title: this.overlayTitle,
      items: this.getCurrentMenuItems(),
      activeItemId: this.getCurrentMenuItems()[this.activeMenuIndex]?.id ?? '',
      anchorX: this.anchorX,
      anchorY: this.anchorY,
      menuWidth: this.anchorWidth,
      onSelectItem: (item: BrowserMenuItem) => this.applyMenuAction(item),
      onHoverItem: (item: BrowserMenuItem) => this.handleMenuItemMouseMove(item),
      onRequestClose: () => this.closeOverlay('点击菜单外部区域'),
    });
  }

  @Builder
  private PanelOverlay() {
    Column({ space: 14 }) {
      Row() {
        Text('轻面板验证区')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827');

        Blank();

        Button('关闭')
          .fontSize(12)
          .height(28)
          .backgroundColor('#f3f4f6')
          .fontColor('#4b5563')
          .borderRadius(14)
          .onClick(() => this.closeOverlay('点击面板关闭按钮'));
      }
      .width('100%');

      Column({ space: 10 }) {
        Text(`页面缩放：${this.panelZoomPercent}%`)
          .fontSize(13)
          .fontColor('#374151');

        Row({ space: 8 }) {
          Button('-')
            .width(32)
            .height(32)
            .fontSize(18)
            .backgroundColor('#f3f4f6')
            .fontColor('#374151')
            .borderRadius(16)
            .onClick(() => this.adjustZoom(-10));

          Button('重置')
            .height(32)
            .fontSize(12)
            .backgroundColor('#eff6ff')
            .fontColor('#2563eb')
            .borderRadius(16)
            .onClick(() => {
              this.panelZoomPercent = 100;
              this.selectedActionText = '缩放已重置到 100%';
              this.appendLog('缩放已重置到 100%');
            });

          Button('+')
            .width(32)
            .height(32)
            .fontSize(18)
            .backgroundColor('#f3f4f6')
            .fontColor('#374151')
            .borderRadius(16)
            .onClick(() => this.adjustZoom(10));
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');

      Column({ space: 8 }) {
        Text('页内查找')
          .fontSize(13)
          .fontColor('#374151');

        TextInput({ text: this.findText, placeholder: '输入模拟查找关键词' })
          .fontSize(13)
          .backgroundColor('#f8fafc')
          .borderRadius(12)
          .border({ width: 1, color: '#e5e7eb' })
          .onChange((value: string) => {
            this.findText = value;
            this.appendLog(`轻面板输入更新：${value || '空值'}`);
          });
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.anchorWidth)
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .border({ width: 1, color: '#dbe3f0' })
    .position({ x: this.anchorX, y: this.anchorY });
  }

  @Builder
  private ConfirmDialogOverlay() {
    Column({ space: 14 }) {
      Text('危险操作确认')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827');

      Text(
        '这是一个测试页面内的确认弹窗，用于验证模态遮罩、主次按钮、' +
        'Esc 关闭和日志记录。'
      )
        .fontSize(13)
        .fontColor('#4b5563');

      Text(
        '建议后续把这类交互迁移到统一的官方 Dialog 封装层，' +
        '而不是长期保留页面内模拟实现。'
      )
        .fontSize(12)
        .fontColor('#6b7280');

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#f3f4f6')
          .fontColor('#374151')
          .borderRadius(18)
          .onClick(() => this.closeOverlay('点击取消按钮'));

        Button('确认删除')
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#dc2626')
          .fontColor('#ffffff')
          .borderRadius(18)
          .onClick(() => {
            this.selectedActionText = '已执行：确认删除';
            this.appendLog('确认弹窗主操作已执行');
            this.closeOverlay('点击确认删除按钮');
          });
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .width(360)
    .padding(20)
    .backgroundColor('#ffffff')
    .borderRadius(20)
    .position({ x: 250, y: 190 });
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 16 }) {
          Row({ space: 12 }) {
            Button('返回调试页')
              .height(34)
              .backgroundColor('#ffffff')
              .fontColor('#2563eb')
              .borderRadius(17)
              .border({ width: 1, color: '#bfdbfe' })
              .onClick(() => (this.route = AppRouter.devLauncher));

            Column({ space: 4 }) {
              Text('菜单 / 弹窗单页验证场')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827');

              Text('先在独立页面验证交互，再决定是否抽象进浏览器主模块。')
                .fontSize(13)
                .fontColor('#6b7280');
            }
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%');

          Row({ space: 10 }) {
            this.InfoCard('浮层状态', this.overlayStateText, '#2563eb');
            this.InfoCard('最近动作', this.selectedActionText, '#111827');
            this.InfoCard('焦点回退目标', this.focusReturnTarget, '#7c3aed');
          }
          .width('100%');

          Column({ space: 12 }) {
            Text('验证触发区')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111827');

            Row({ space: 12 }) {
              this.TriggerCard(
                '锚点菜单',
                '模拟浏览器右上角主菜单，验证锚点定位、Esc 关闭、上下键导航。',
                '打开主菜单',
                () => this.openMainMenu()
              );
              this.TriggerCard(
                '右键菜单',
                '模拟标签页右键菜单，验证上下文命令集、危险项和禁用项样式。',
                '打开右键菜单',
                () => this.openContextMenu()
              );
            }
            .width('100%');

            Row({ space: 12 }) {
              this.TriggerCard(
                '轻量面板',
                '模拟缩放 / 页内查找面板，验证非模态内容刷新和局部操作。',
                '打开轻面板',
                () => this.openPanel()
              );
              this.TriggerCard(
                '确认弹窗',
                '模拟危险操作确认，验证遮罩、主次操作和关闭链路。',
                '打开确认弹窗',
                () => this.openConfirmDialog()
              );
            }
            .width('100%');
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor('#f8fbff')
          .borderRadius(18)
          .border({ width: 1, color: '#d8e8ff' });

          Column({ space: 10 }) {
            Text('建议验收项')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111827');

            Text('1. 打开主菜单后，按 Esc 是否关闭，并在日志中记录焦点回退目标。')
              .fontSize(13)
              .fontColor('#4b5563');
            Text('2. 打开主菜单后，按方向键上下移动高亮，再按 Enter 是否执行当前项。')
              .fontSize(13)
              .fontColor('#4b5563');
            Text('3. 打开右键菜单后，禁用项是否不可点，危险项是否有明显视觉区分。')
              .fontSize(13)
              .fontColor('#4b5563');
            Text(
              '4. 打开轻面板后，调整缩放与输入文本时，' +
              '面板是否保持打开并持续刷新内容。'
            )
              .fontSize(13)
              .fontColor('#4b5563');
            Text('5. 打开确认弹窗后，遮罩点击、取消按钮、确认按钮是否都按预期关闭。')
              .fontSize(13)
              .fontColor('#4b5563');
            Text(
              '6. 主菜单中的“设置”项已配置为悬停时不高亮，' +
              '可用于验证个别菜单项关闭悬停高亮。'
            )
              .fontSize(13)
              .fontColor('#4b5563');
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor('#ffffff')
          .borderRadius(18)
          .border({ width: 1, color: '#e5e7eb' });

          Column({ space: 10 }) {
            Text('交互日志')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111827');

            Column({ space: 8 }) {
              ForEach(this.logs, (item: string) => {
                Text(item)
                  .width('100%')
                  .fontSize(12)
                  .fontColor('#475569')
                  .padding(10)
                  .backgroundColor('#f8fafc')
                  .borderRadius(10);
              }, (item: string) => item);
            }
            .width('100%');
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor('#ffffff')
          .borderRadius(18)
          .border({ width: 1, color: '#e5e7eb' });
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(20);
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .height('100%');

      if (this.hasOverlay()) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.overlayKind === 'confirm_dialog' ? '#33000000' : '#12000000')
          .onClick(() => this.handleOutsidePress());
      }

      if (this.isMenuOverlay()) {
        this.MenuOverlay();
      }

      if (this.overlayKind === 'panel') {
        this.PanelOverlay();
      }

      if (this.overlayKind === 'confirm_dialog') {
        this.ConfirmDialogOverlay();
      }
    }
    .backgroundColor('#f3f6fb')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event))
    .width('100%')
    .height('100%');
  }
}
