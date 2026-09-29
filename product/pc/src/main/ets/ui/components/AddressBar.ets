// AddressBar：地址/搜索输入框，联想建议与书签切换入口。
import { hilog } from '@kit.PerformanceAnalysisKit';

export const ADDRESS_BAR_INPUT_ID: string = 'browser_address_bar_input';
export const ADDRESS_BAR_FAVORITE_ID: string = 'browser_address_bar_favorite';

const ADDRESS_FOCUS_LOG_TAG: string = 'ADDR_FOCUS';

@Component
export struct AddressBar {
  @Link text: string;
  @Prop placeholder: string = '输入网址';
  @Prop displayText: string = '';
  @Prop @Watch('handleEditingChanged') editing: boolean = false;
  @Prop readonlyMode: boolean = false;
  @Prop favoriteEnabled: boolean = false;
  @Prop favoriteActive: boolean = false;
  @Prop @Watch('handleSelectionRevisionChanged') selectionRevision: number = 0;

  private inputController: TextInputController = new TextInputController();
  // 焦点状态追踪：用于区分“点击进入未聚焦的输入框”与“聚焦状态下点击调整光标”。
  // 使用响应式状态驱动外层描边，确保输入框获得/失去焦点时立即刷新视觉状态。
  @State private inputFocused: boolean = false;
  private inputFocusedAtPress: boolean = false;
  // 进入编辑态时置位：等焦点真正落地（onFocus）后再全选。
  // startAddressEditing 里的 requestFocus 微任务跑在渲染之前，TextInput 尚未挂载，
  // 会静默失败；全选若跑在焦点之前，也会被随后的焦点初始化重置。
  private selectAfterFocus: boolean = false;
  private enterEditingFocusTimer: number = -1;

  onChangeValue: (value: string) => void = () => {};
  onSubmitValue: (value: string) => void = () => {};
  onStartEditing: () => void = () => {};
  onToggleFavorite: () => void = () => {};
  // Reports the star's bottom-right corner in window vp coordinates so the
  // parent can anchor a popover right under it.
  onFavoriteAreaChanged: (rightX: number, bottomY: number) => void =
    (_x: number, _y: number) => {};

  private handleChange(value: string): void {
    if (this.readonlyMode) {
      return;
    }
    this.text = value;
    this.onChangeValue(value);
  }

  private handleSubmit(): void {
    const value = this.text.trim();
    this.onSubmitValue(value);
  }

  private emitToggleFavorite(): void {
    if (!this.favoriteEnabled) {
      return;
    }
    this.onToggleFavorite();
  }

  private emitStartEditing(): void {
    if (this.readonlyMode || this.editing) {
      return;
    }
    this.onStartEditing();
  }

  private handleSelectionRevisionChanged(): void {
    this.selectAllInputText();
  }

  private handleEditingChanged(): void {
    if (this.editing) {
      hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG, 'EDITING_ON selectAfterFocus=%{public}s focused=%{public}s',
        String(this.selectAfterFocus), String(this.inputFocused));
      this.selectAfterFocus = true;
      if (this.enterEditingFocusTimer >= 0) {
        clearTimeout(this.enterEditingFocusTimer);
      }
      // 等 TextInput 挂载完成后再补一次焦点请求（defaultFocus 对动态插入的组件不保证生效）。
      this.enterEditingFocusTimer = setTimeout(() => {
        this.enterEditingFocusTimer = -1;
        try {
          this.getUIContext().getFocusController().requestFocus(ADDRESS_BAR_INPUT_ID);
          hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG, 'TIMER_REQUEST_FOCUS done focused=%{public}s',
            String(this.inputFocused));
        } catch (error) {
          // 仍未挂载则保留 selectAfterFocus，等真实焦点到来时再全选。
          hilog.warn(0x0000, ADDRESS_FOCUS_LOG_TAG, 'TIMER_REQUEST_FOCUS failed: %{public}s',
            JSON.stringify(error));
        }
      }, 50);
    } else {
      // TextInput 卸载时不一定触发 onBlur，这里手动复位，避免脏状态影响下一轮编辑。
      if (this.enterEditingFocusTimer >= 0) {
        clearTimeout(this.enterEditingFocusTimer);
        this.enterEditingFocusTimer = -1;
      }
      this.selectAfterFocus = false;
      this.inputFocused = false;
      this.inputFocusedAtPress = false;
    }
  }

  aboutToAppear(): void {
    // 冷启动竞态兜底：若挂载时 editing 已为 true（如启动聚焦跑在首帧渲染之前），
    // @Watch 不会因初始赋值触发，需在此手动走一次焦点调度。
    if (this.editing) {
      this.handleEditingChanged();
    }
  }

  aboutToDisappear(): void {
    if (this.enterEditingFocusTimer >= 0) {
      clearTimeout(this.enterEditingFocusTimer);
      this.enterEditingFocusTimer = -1;
    }
  }

  private selectAllInputText(): void {
    Promise.resolve().then(() => {
      try {
        this.inputController.setTextSelection(0, this.text.length);
      } catch (_) {
      }
    });
  }

  private handleInputTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      // 按下瞬间快照焦点状态：此时 onFocus 可能已触发，不能用实时值判断。
      this.inputFocusedAtPress = this.inputFocused;
    }
  }

  private handleInputClick(): void {
    // 按下时输入框没有焦点（鼠标/焦点在别处）→ 本次点击是“进入输入框”，全选文本；
    // 已经聚焦时点击 → 保持系统默认行为（光标定位），不打断用户编辑。
    if (!this.inputFocusedAtPress) {
      this.selectAllInputText();
    }
  }

  build() {
    Row() {
      Image($r('app.media.home_search'))
        .width(16)
        .height(16)
        .margin({ right: this.editing ? 6 : 8 })
        .opacity(0.72);

      if (this.editing) {
        TextInput({ text: this.text, placeholder: this.placeholder, controller: this.inputController })
          .id(ADDRESS_BAR_INPUT_ID)
          .width(0)
          .layoutWeight(1)
          .fontSize(14)
          .enabled(!this.readonlyMode)
          .padding({ left: 0, right: 0 })
          .backgroundColor('#00000000')
          .defaultFocus(true)
          .selectAll(true)
          .onChange((value: string) => this.handleChange(value))
          .onSubmit(() => this.handleSubmit())
          .onFocus(() => {
            this.inputFocused = true;
            hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG, 'INPUT_FOCUSED');
            // 焦点真正落地后才全选（进入编辑态的首次点击路径）。
            if (this.selectAfterFocus) {
              this.selectAfterFocus = false;
              this.selectAllInputText();
            }
          })
          .onBlur(() => {
            this.inputFocused = false;
            hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG, 'INPUT_BLURRED');
          })
          .onTouch((event: TouchEvent) => this.handleInputTouch(event))
          .onClick(() => this.handleInputClick());
      } else {
        Text(this.displayText.length > 0 ? this.displayText : this.placeholder)
        .width(0)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor(this.displayText.length > 0 ? '#111827' : '#9ca3af')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height('100%')
        .onClick(() => this.emitStartEditing());
      }

      Row() {
        Image(this.favoriteActive
          ? $r('app.media.home_collect_selected')
          : $r('app.media.home_collect_normal'))
          .width(16)
          .height(16)
          .opacity(this.favoriteEnabled ? 0.86 : 0.3);
      }
      .id(ADDRESS_BAR_FAVORITE_ID)
      .width(24)
      .height(24)
      .margin({ left: 10 })
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor('#00000000')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const global = newValue.globalPosition;
        this.onFavoriteAreaChanged(
          Number(global.x) + Number(newValue.width),
          Number(global.y) + Number(newValue.height),
        );
      })
      .onClick(() => this.emitToggleFavorite());
    }
    // The toolbar wrapper owns the flex allocation. This component must fill
    // that allocated slot instead of participating in a second flex pass;
    // otherwise ArkUI can recalculate it to content width during load updates.
    .width('100%')
    .constraintSize({ minWidth: 160 })
    .height(34)
    .padding({ left: this.editing ? 8 : 12, right: 12 })
    .backgroundColor('#F3F3F3')
    .borderRadius(17)
    .border({ width: 1, color: this.inputFocused ? '#1458E1' : '#d7dbe3' })
  }
}
