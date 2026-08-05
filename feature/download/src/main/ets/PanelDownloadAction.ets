import { BrowserStore } from 'browser_core'
import { BrowserTheme } from 'browser_core'
import { AppStorageKeys } from 'common'
import { DownloadTask } from 'common'

/** 下载列表右侧操作区：统一灰色胶囊 + 蓝色文案 */
@Component
export struct PanelDownloadAction {
  private static readonly CAPSULE_W: number = 72
  private static readonly CAPSULE_H: number = 32

  @Prop itemId: string = ''
  @Prop itemName: string = ''
  @Prop status: string = 'pending'
  @Prop progress: number = 0
  @StorageLink(AppStorageKeys.DOWNLOADS) downloads: DownloadTask[] = []
  @StorageLink(AppStorageKeys.DOWNLOAD_PROGRESS_REV) downloadProgressRev: number = 0
  onOpenItem?: (id: string) => void
  /** 失败/已删除任务点击后由父级弹出「是否重新下载」确认框 */
  onRetryRequest?: (id: string, name: string) => void
  /** 已删除任务点击后弹出重新下载确认（与 onRetryRequest 分离文案） */
  onRedownloadRequest?: (id: string, name: string) => void

  private liveTask(): DownloadTask | undefined {
    const _tick = this.downloadProgressRev
    if (_tick < 0) {
      return undefined
    }
    for (let i = 0; i < this.downloads.length; i++) {
      if (this.downloads[i].id === this.itemId) {
        return this.downloads[i]
      }
    }
    return undefined
  }

  private liveStatus(): string {
    const task = this.liveTask()
    if (task !== undefined) {
      return task.status
    }
    return this.status
  }

  private liveProgress(): number {
    const task = this.liveTask()
    if (task !== undefined) {
      return task.progress
    }
    return this.progress
  }

  build() {
    Column() {
      if (this.liveStatus() === 'pending' || this.liveStatus() === 'queued') {
        this.StatusCapsuleRes($r('app.string.download_status_queued'))
      } else if (this.liveStatus() === 'failed') {
        this.StatusCapsuleRes($r('app.string.download_status_failed'))
      } else if (this.liveStatus() === 'deleted') {
        this.StatusCapsuleRes($r('app.string.download_status_deleted'))
      } else if (this.liveStatus() === 'running') {
        this.StatusCapsuleText(`${this.liveProgress()}%`)
      } else if (this.liveStatus() === 'paused') {
        this.StatusCapsuleRes($r('app.string.continue_action'))
      } else {
        this.StatusCapsuleRes($r('app.string.download_action_open'))
      }
    }
    .width(PanelDownloadAction.CAPSULE_W)
    .height(PanelDownloadAction.CAPSULE_H)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .flexShrink(0)
    .onClick(() => {
      this.handleTap()
    })
  }

  /** 灰色胶囊底 + 蓝色文案（资源文案）：打开 / 失败 / 已删除 / 排队 / 继续 */
  @Builder
  StatusCapsuleRes(label: Resource) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(BrowserTheme.PRIMARY_COLOR)
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width(PanelDownloadAction.CAPSULE_W)
    .height(PanelDownloadAction.CAPSULE_H)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .borderRadius(PanelDownloadAction.CAPSULE_H / 2)
  }

  /** 灰色胶囊底 + 蓝色文案（进度百分比） */
  @Builder
  StatusCapsuleText(label: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(BrowserTheme.PRIMARY_COLOR)
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width(PanelDownloadAction.CAPSULE_W)
    .height(PanelDownloadAction.CAPSULE_H)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .borderRadius(PanelDownloadAction.CAPSULE_H / 2)
  }

  private handleTap(): void {
    const status = this.liveStatus()
    if (status === 'pending' || status === 'queued') {
      BrowserStore.startDownload(this.itemId)
      return
    }
    if (status === 'failed') {
      this.onRetryRequest?.(this.itemId, this.itemName)
      return
    }
    if (status === 'deleted') {
      this.onRedownloadRequest?.(this.itemId, this.itemName)
      return
    }
    if (status === 'running') {
      BrowserStore.pauseDownload(this.itemId)
      return
    }
    if (status === 'paused') {
      BrowserStore.resumeDownload(this.itemId)
      return
    }
    if (this.onOpenItem) {
      this.onOpenItem(this.itemId)
      return
    }
    void BrowserStore.openDownload(this.itemId)
  }
}
