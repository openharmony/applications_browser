// ClipboardService：系统剪贴板能力封装。

import { pasteboard } from '@kit.BasicServicesKit';

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
}
