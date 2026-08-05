import { BrowserStore } from 'browser_core'
import { OpenShareOptions } from 'browser_core'

/** 分享 ViewModel：打开/关闭分享面板 */
@Observed
export class ShareViewModel {
  open(opts: OpenShareOptions): void {
    BrowserStore.openShare(opts)
  }

  close(): void {
    BrowserStore.closeShareSheet()
  }

  async shareImage(title: string, url: string, localPath: string = ''): Promise<void> {
    await BrowserStore.shareImageViaSystem(title, url, localPath)
  }
}
