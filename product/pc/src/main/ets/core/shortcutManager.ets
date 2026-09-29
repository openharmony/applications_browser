// ShortcutManager：键盘快捷键与命令的统一注册与分发。

import { KeyCode } from '@kit.InputKit';
import { Tab, TabId } from './types';

export type BrowserShortcutCommand =
  'new_tab' |
  'new_window' |
  'new_private_tab' |
  'close_tab' |
  'close_window' |
  'next_tab' |
  'prev_tab' |
  'select_tab' |
  'restore_tab' |
  'focus_address_bar' |
  'reload_tab' |
  'reload_tab_ignore_cache' |
  'go_back' |
  'go_forward' |
  'go_home' |
  'zoom_in' |
  'zoom_out' |
  'zoom_reset' |
  'toggle_bookmark' |
  'toggle_bookmark_bar' |
  'open_bookmarks' |
  'open_history' |
  'open_downloads' |
  'open_dev_launcher' |
  'open_find_in_page' |
  'find_next' |
  'find_previous' |
  'stop_loading' |
  'toggle_fullscreen' |
  'open_clear_browsing_data' |
  'print_page' |
  'save_page' |
  'view_source' |
  'open_file' |
  'open_tab_search';

export interface BrowserShortcutAction {
  command: BrowserShortcutCommand;
  targetTabId?: TabId;
}

export class ShortcutManager {
  resolve(event: KeyEvent, tabs: Tab[], activeTabId: string): BrowserShortcutAction | null {
    return this.resolveInput(
      event.type === KeyType.Down,
      event.keyCode,
      this.isCtrlPressed(event),
      this.isAltPressed(event),
      this.isShiftPressed(event),
      tabs,
      activeTabId,
    );
  }

  resolveInput(
    isKeyDown: boolean,
    keyCode: number,
    ctrlPressed: boolean,
    altPressed: boolean,
    shiftPressed: boolean,
    tabs: Tab[],
    activeTabId: string,
  ): BrowserShortcutAction | null {
    if (!isKeyDown) {
      return null;
    }

    if (!ctrlPressed && !altPressed) {
      if (keyCode === KeyCode.KEYCODE_ESCAPE && !shiftPressed) {
        return { command: 'stop_loading' };
      }
      if (keyCode === KeyCode.KEYCODE_F11 && !shiftPressed) {
        return { command: 'toggle_fullscreen' };
      }
      if (keyCode === KeyCode.KEYCODE_F6) {
        return { command: 'focus_address_bar' };
      }
      if (keyCode === KeyCode.KEYCODE_F5 || keyCode === KeyCode.KEYCODE_REFRESH) {
        return { command: shiftPressed ? 'reload_tab_ignore_cache' : 'reload_tab' };
      }
      return null;
    }

    if (altPressed && !ctrlPressed) {
      if (keyCode === KeyCode.KEYCODE_D) {
        return { command: 'focus_address_bar' };
      }
      if (keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
        return { command: 'go_back' };
      }
      if (keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
        return { command: 'go_forward' };
      }
      if (keyCode === KeyCode.KEYCODE_HOME) {
        return { command: 'go_home' };
      }
      return null;
    }

    if (ctrlPressed && altPressed) {
      return null;
    }

    if (keyCode === KeyCode.KEYCODE_F5 || keyCode === KeyCode.KEYCODE_REFRESH) {
      return { command: ctrlPressed || shiftPressed ? 'reload_tab_ignore_cache' : 'reload_tab' };
    }

    if (keyCode === KeyCode.KEYCODE_T) {
      if (shiftPressed) {
        return { command: 'restore_tab' };
      }
      return { command: 'new_tab' };
    }

    if (keyCode === KeyCode.KEYCODE_N) {
      // 暂时预留，后期完善：Ctrl+Shift+N 无痕窗口快捷键暂不开放。
      if (shiftPressed) {
        return null;
      }
      return { command: 'new_window' };
    }

    if ((keyCode === KeyCode.KEYCODE_L || keyCode === KeyCode.KEYCODE_K ||
      keyCode === KeyCode.KEYCODE_E) && !shiftPressed) {
      return { command: 'focus_address_bar' };
    }

    if (keyCode === KeyCode.KEYCODE_R) {
      return { command: shiftPressed ? 'reload_tab_ignore_cache' : 'reload_tab' };
    }

    if (keyCode === KeyCode.KEYCODE_F) {
      return { command: 'open_find_in_page' };
    }

    if (keyCode === KeyCode.KEYCODE_W) {
      return { command: shiftPressed ? 'close_window' : 'close_tab' };
    }

    if (keyCode === KeyCode.KEYCODE_FORWARD_DEL && shiftPressed) {
      return { command: 'open_clear_browsing_data' };
    }

    if (keyCode === KeyCode.KEYCODE_G) {
      return { command: shiftPressed ? 'find_previous' : 'find_next' };
    }

    if (keyCode === KeyCode.KEYCODE_P && !shiftPressed) {
      return { command: 'print_page' };
    }

    if (keyCode === KeyCode.KEYCODE_S && !shiftPressed) {
      return { command: 'save_page' };
    }

    if (keyCode === KeyCode.KEYCODE_U && !shiftPressed) {
      return { command: 'view_source' };
    }

    if (keyCode === KeyCode.KEYCODE_O && !shiftPressed) {
      return { command: 'open_file' };
    }

    if (keyCode === KeyCode.KEYCODE_A && shiftPressed) {
      return { command: 'open_tab_search' };
    }

    if (keyCode === KeyCode.KEYCODE_EQUALS || keyCode === KeyCode.KEYCODE_PLUS ||
      keyCode === KeyCode.KEYCODE_NUMPAD_ADD) {
      return { command: 'zoom_in' };
    }

    if (keyCode === KeyCode.KEYCODE_MINUS || keyCode === KeyCode.KEYCODE_NUMPAD_SUBTRACT) {
      return { command: 'zoom_out' };
    }

    if (keyCode === KeyCode.KEYCODE_0 || keyCode === KeyCode.KEYCODE_NUMPAD_0) {
      return { command: 'zoom_reset' };
    }

    if (keyCode === KeyCode.KEYCODE_D && !shiftPressed) {
      return { command: 'toggle_bookmark' };
    }

    if (keyCode === KeyCode.KEYCODE_B && shiftPressed) {
      return { command: 'toggle_bookmark_bar' };
    }

    if (keyCode === KeyCode.KEYCODE_O && shiftPressed) {
      return { command: 'open_bookmarks' };
    }

    if (keyCode === KeyCode.KEYCODE_H) {
      return { command: 'open_history' };
    }

    if (keyCode === KeyCode.KEYCODE_J) {
      return { command: 'open_downloads' };
    }

    if (keyCode === KeyCode.KEYCODE_TAB || keyCode === KeyCode.KEYCODE_PAGE_UP ||
      keyCode === KeyCode.KEYCODE_PAGE_DOWN) {
      const reverse = keyCode === KeyCode.KEYCODE_PAGE_UP ||
        (keyCode === KeyCode.KEYCODE_TAB && shiftPressed);
      const targetTabId = this.resolveTabSwitchTarget(tabs, activeTabId, reverse);
      if (!targetTabId) {
        return null;
      }

      return {
        command: reverse ? 'prev_tab' : 'next_tab',
        targetTabId,
      };
    }

    const tabIndex = this.resolveTabIndex(keyCode, tabs.length);
    if (tabIndex >= 0 && tabIndex < tabs.length) {
      return { command: 'select_tab', targetTabId: tabs[tabIndex].id };
    }

    return null;
  }

  private resolveTabIndex(keyCode: number, tabCount: number): number {
    if (keyCode === KeyCode.KEYCODE_9 || keyCode === KeyCode.KEYCODE_NUMPAD_9) {
      return tabCount > 0 ? tabCount - 1 : -1;
    }
    const digitCodes: number[] = [
      KeyCode.KEYCODE_1,
      KeyCode.KEYCODE_2,
      KeyCode.KEYCODE_3,
      KeyCode.KEYCODE_4,
      KeyCode.KEYCODE_5,
      KeyCode.KEYCODE_6,
      KeyCode.KEYCODE_7,
      KeyCode.KEYCODE_8,
    ];
    const numpadCodes: number[] = [
      KeyCode.KEYCODE_NUMPAD_1,
      KeyCode.KEYCODE_NUMPAD_2,
      KeyCode.KEYCODE_NUMPAD_3,
      KeyCode.KEYCODE_NUMPAD_4,
      KeyCode.KEYCODE_NUMPAD_5,
      KeyCode.KEYCODE_NUMPAD_6,
      KeyCode.KEYCODE_NUMPAD_7,
      KeyCode.KEYCODE_NUMPAD_8,
    ];
    const digitIndex = digitCodes.indexOf(keyCode);
    if (digitIndex >= 0) {
      return digitIndex;
    }
    return numpadCodes.indexOf(keyCode);
  }

  private isCtrlPressed(event: KeyEvent): boolean {
    if (event.getModifierKeyState) {
      try {
        return event.getModifierKeyState(['ctrl']);
      } catch (_) {
      }
    }
    return false;
  }

  private isShiftPressed(event: KeyEvent): boolean {
    if (event.getModifierKeyState) {
      try {
        return event.getModifierKeyState(['shift']);
      } catch (_) {
      }
    }
    return false;
  }

  private isAltPressed(event: KeyEvent): boolean {
    if (event.getModifierKeyState) {
      try {
        return event.getModifierKeyState(['alt']);
      } catch (_) {
      }
    }
    return false;
  }

  private resolveTabSwitchTarget(tabs: Tab[], activeTabId: string, reverse: boolean): TabId | null {
    if (tabs.length === 0) {
      return null;
    }

    const currentIndex = tabs.findIndex(tab => String(tab.id) === activeTabId);
    if (currentIndex === -1) {
      return tabs[0].id;
    }

    const nextIndex = reverse
      ? (currentIndex - 1 + tabs.length) % tabs.length
      : (currentIndex + 1) % tabs.length;
    return tabs[nextIndex].id;
  }
}
