// ClipboardService：系统剪贴板能力封装。

import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const CLIPBOARD_LOG_DOMAIN: number = 0x0000;
const CLIPBOARD_LOG_TAG: string = 'ClipboardTrace';
// ArkWeb/ArkUI may still be completing the previous clipboard transaction
// when Ctrl+V arrives. Keep the retry window bounded so a failed paste never
// leaves the address bar waiting indefinitely.
const CLIPBOARD_READ_RETRY_DELAYS_MS: number[] = [0, 60, 120, 240, 360];

interface ClipboardError {
  code?: number | string;
}

export class ClipboardService {
  async copyText(text: string): Promise<boolean> {
    if (text.trim().length === 0) {
      return false;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /**
   * Reads plain text from the system pasteboard.
   *
   * Pasteboard read can transiently fail while another copy/paste operation is
   * finishing. Keep the retry local to this service so all callers get the
   * same behavior without duplicating platform-specific timing work.
   */
  async readText(): Promise<string> {
    for (let index = 0; index < CLIPBOARD_READ_RETRY_DELAYS_MS.length; index++) {
      const delayMs = CLIPBOARD_READ_RETRY_DELAYS_MS[index];
      if (delayMs > 0) {
        await this.delay(delayMs);
      }
      try {
        const data = await pasteboard.getSystemPasteboard().getData();
        if (!data || data.getRecordCount() <= 0) {
          this.trace('READ_EMPTY', `attempt=${index + 1}`);
          continue;
        }
        const record = data.getRecord(0);
        // toPlainText also handles URI/HTML records copied from another app.
        const text = record.toPlainText();
        if (text.length > 0) {
          this.trace('READ_SUCCESS', `attempt=${index + 1} length=${text.length}`);
          return text;
        }
        this.trace('READ_EMPTY', `attempt=${index + 1}`);
      } catch (error) {
        const code = this.getErrorCode(error);
        this.trace('READ_FAILED', `attempt=${index + 1} code=${code}`);
      }
    }
    this.trace('READ_GIVE_UP', `attempts=${CLIPBOARD_READ_RETRY_DELAYS_MS.length}`);
    return '';
  }

  private delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, delayMs);
    });
  }

  private getErrorCode(error: ClipboardError): string {
    const value = error;
    return value && value.code !== undefined ? String(value.code) : 'unknown';
  }

  private trace(stage: string, detail: string): void {
    hilog.info(CLIPBOARD_LOG_DOMAIN, CLIPBOARD_LOG_TAG,
      '%{public}s %{public}s', stage, detail);
  }
}
