// AddressBar：地址/搜索输入框，联想建议与书签切换入口。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyCode } from '@kit.InputKit';
import { ClipboardService } from '../../integration/clipboardService';
import { PermissionService } from '../../integration/permissionService';

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
  private readonly clipboardService: ClipboardService = new ClipboardService();
  private readonly permissionService: PermissionService = new PermissionService();
  // 焦点状态追踪：用于区分点击进入未聚焦的输入框与聚焦状态下调整光标。
  // 使用响应式状态驱动外层描边，确保输入框获得/失去焦点时立即刷新视觉状态。
  @State private inputFocused: boolean = false;
  private inputFocusedAtPress: boolean = false;
  // 进入编辑态时置位：等焦点真正落地（onFocus）后再全选。
  // startAddressEditing 里的 requestFocus 微任务跑在渲染之前，TextInput 尚未挂载，
  // 会静默失败；全选若跑在焦点之前，也会被随后的焦点初始化重置。
  private selectAfterFocus: boolean = false;
  private enterEditingFocusTimer: number = -1;
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private pasteFallbackTimer: number = -1;
  private pasteRequestId: number = 0;
  private nativePasteRequestId: number = -1;
  private inputChangeRevision: number = 0;
  private pastePermissionReady: boolean = false;
  private pastePermissionPromise: Promise<boolean> | null = null;

  // The native TextInput paste operation is the primary path. If the system
  // pasteboard is temporarily busy, the native callback may not arrive; the
  // fallback then retries the read without stealing the normal Ctrl+V event.
  private static readonly PASTE_FALLBACK_DELAY_MS: number = 420;

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
    this.inputChangeRevision += 1;
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
      this.selectionStart = 0;
      this.selectionEnd = this.text.length;
      hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG, 'EDITING_ON selectAfterFocus=%{public}s focused=%{public}s',
        String(this.selectAfterFocus), String(this.inputFocused));
      this.selectAfterFocus = true;
      if (this.enterEditingFocusTimer >= 0) {
        clearTimeout(this.enterEditingFocusTimer);
      }
      // 等 TextInput 挂载完成后再补一次焦点请求，动态插入的组件不保证 defaultFocus 生效。
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
    this.cancelPasteFallback();
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
    // 按下时输入框没有焦点（鼠标/焦点在别处）→ 本次点击是“进入输入框”，
    // 全选文本；
    // 已经聚焦时点击 → 保持系统默认行为（光标定位），不打断用户编辑。
    if (!this.inputFocusedAtPress) {
      this.selectAllInputText();
    }
  }

  private isCtrlPressed(event: KeyEvent): boolean {
    if (!event.getModifierKeyState) {
      return false;
    }
    try {
      return event.getModifierKeyState(['ctrl']);
    } catch (_) {
      return false;
    }
  }

  private isShiftPressed(event: KeyEvent): boolean {
    if (!event.getModifierKeyState) {
      return false;
    }
    try {
      return event.getModifierKeyState(['shift']);
    } catch (_) {
      return false;
    }
  }

  private handleInputKeyEvent(event: KeyEvent): boolean {
    const isKeyboardPaste = event.keyCode === KeyCode.KEYCODE_V && this.isCtrlPressed(event);
    const isPasteKey = event.keyCode === KeyCode.KEYCODE_PASTE;
    const isShiftInsert = event.keyCode === KeyCode.KEYCODE_INSERT && this.isShiftPressed(event);
    if (event.type !== KeyType.Down || (!isKeyboardPaste && !isPasteKey && !isShiftInsert) ||
      this.readonlyMode) {
      return false;
    }
    this.schedulePasteFallback();
    // Let TextInput perform its normal paste first. Returning true here would
    // suppress the native operation and make a transient failure more likely.
    return false;
  }

  private schedulePasteFallback(): void {
    this.cancelPasteFallback();
    const requestId = this.pasteRequestId + 1;
    this.pasteRequestId = requestId;
    const requestText = this.text;
    const requestRevision = this.inputChangeRevision;
    const requestStart = this.selectionStart;
    const requestEnd = this.selectionEnd;
    hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG,
      'PASTE_KEY request=%{public}s textLength=%{public}s selection=%{public}s-%{public}s',
      String(requestId), String(requestText.length), String(requestStart), String(requestEnd));
    this.pasteFallbackTimer = setTimeout(() => {
      this.pasteFallbackTimer = -1;
      if (this.nativePasteRequestId === requestId ||
        this.inputChangeRevision !== requestRevision || this.text !== requestText) {
        hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG,
          'PASTE_FALLBACK_SKIP request=%{public}s native=%{public}s changed=%{public}s',
          String(requestId), String(this.nativePasteRequestId === requestId),
          String(this.inputChangeRevision !== requestRevision || this.text !== requestText));
        return;
      }
      void this.applyPasteFallback(requestId, requestText, requestStart, requestEnd);
    }, AddressBar.PASTE_FALLBACK_DELAY_MS);
  }

  private cancelPasteFallback(): void {
    if (this.pasteFallbackTimer >= 0) {
      clearTimeout(this.pasteFallbackTimer);
      this.pasteFallbackTimer = -1;
    }
  }

  private ensurePastePermission(): Promise<boolean> {
    if (this.pastePermissionReady) {
      return Promise.resolve(true);
    }
    if (this.pastePermissionPromise) {
      return this.pastePermissionPromise;
    }
    const context = this.getUIContext().getHostContext();
    this.pastePermissionPromise = this.permissionService.ensureForPasteboard(context)
      .then((granted: boolean) => {
        this.pastePermissionReady = granted;
        return granted;
      })
      .catch(() => false)
      .finally(() => {
        this.pastePermissionPromise = null;
      });
    return this.pastePermissionPromise;
  }

  private async applyPasteFallback(
    requestId: number,
    requestText: string,
    requestStart: number,
    requestEnd: number,
  ): Promise<void> {
    hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG,
      'PASTE_FALLBACK_BEGIN request=%{public}s', String(requestId));
    const granted = await this.ensurePastePermission();
    if (!granted) {
      hilog.warn(0x0000, ADDRESS_FOCUS_LOG_TAG,
        'PASTE_FALLBACK_DENIED request=%{public}s', String(requestId));
      return;
    }
    const pastedText = await this.clipboardService.readText();
    // Do not overwrite input entered while the fallback was waiting for the
    // permission or pasteboard retry window.
    if (this.nativePasteRequestId === requestId || this.text !== requestText) {
      hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG,
        'PASTE_FALLBACK_ABORT request=%{public}s native=%{public}s changed=%{public}s',
        String(requestId), String(this.nativePasteRequestId === requestId),
        String(this.text !== requestText));
      return;
    }
    if (pastedText.length === 0) {
      hilog.warn(0x0000, ADDRESS_FOCUS_LOG_TAG,
        'PASTE_FALLBACK_EMPTY request=%{public}s', String(requestId));
      return;
    }

    const start = Math.max(0, Math.min(requestStart, this.text.length));
    const end = Math.max(start, Math.min(requestEnd, this.text.length));
    const nextText = this.text.slice(0, start) + pastedText + this.text.slice(end);
    this.text = nextText;
    this.selectionStart = start + pastedText.length;
    this.selectionEnd = this.selectionStart;
    this.inputChangeRevision += 1;
    this.onChangeValue(nextText);
    hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG,
      'PASTE_FALLBACK_APPLIED request=%{public}s length=%{public}s',
      String(requestId), String(pastedText.length));
    setTimeout(() => {
      try {
        this.inputController.setTextSelection(this.selectionStart, this.selectionEnd);
      } catch (_) {
      }
    }, 0);
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
          .onPaste((value: string) => {
            // Native context-menu/selection-menu paste is still supported. The
            // value is applied by TextInput.onChange; this callback is only a
            // diagnostic signal and intentionally does not read the clipboard
            // a second time.
            this.nativePasteRequestId = this.pasteRequestId;
            this.cancelPasteFallback();
            hilog.info(0x0000, ADDRESS_FOCUS_LOG_TAG,
              'PASTE_NATIVE request=%{public}s length=%{public}s',
              String(this.nativePasteRequestId), String(value.length));
          })
          .onKeyEvent((event: KeyEvent): boolean => this.handleInputKeyEvent(event))
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.selectionStart = selectionStart;
            this.selectionEnd = selectionEnd;
          })
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
