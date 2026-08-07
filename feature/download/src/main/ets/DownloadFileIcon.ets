import { BrowserUtils } from 'common'

/** 下载列表左侧图标：按扩展名区分类型；失败态用 ic_file_fail */
@Component
export struct DownloadFileIcon {
  /** 类型 / 失败图标统一边长 */
  static readonly ICON_SIZE: number = 40

  @Prop fileName: string = ''
  @Prop galleryUri: string = ''
  @Prop localPath: string = ''
  @Prop status: string = 'pending'
  @Prop boxSize: number = DownloadFileIcon.ICON_SIZE

  private fileKind(): string {
    return BrowserUtils.inferDownloadFileKind(this.fileName)
  }

  private iconRes(): Resource {
    if (this.status === 'failed') {
      return $r('app.media.ic_file_fail')
    }
    const kind = this.fileKind()
    if (kind === 'pdf') {
      return $r('app.media.ic_file_pdf')
    }
    if (kind === 'archive') {
      return $r('app.media.ic_file_zip')
    }
    if (kind === 'video') {
      return $r('app.media.ic_file_mp4')
    }
    return $r('app.media.ic_file_fallback')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.iconRes())
        .width(this.boxSize)
        .height(this.boxSize)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .margin({ right: 8 })
    .flexShrink(0)
  }
}
