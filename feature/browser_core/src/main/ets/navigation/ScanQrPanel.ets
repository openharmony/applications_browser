import { AppStorageKeys, BrowserLog } from 'common'
import { ScanQrService } from './ScanQrService'

const SCAN_LINE_DURATION: number = 2600
/** 扫描杠移动区：文字下方与底部留白 */
const SCAN_TRAVEL_TOP: number = 24
const SCAN_TRAVEL_BOTTOM: number = 40

/** 全屏扫一扫：扫描杠来回扫，右上翻转，底部相册 */
@Component
export struct ScanQrPanel {
  @StorageProp(AppStorageKeys.SAFE_AREA_TOP) safeAreaTop: number = 0
  @StorageProp(AppStorageKeys.SAFE_AREA_BOTTOM) safeAreaBottom: number = 0
  @State private scanLineY: number = 0
  private xController: XComponentController = new XComponentController()
  private scanStarted: boolean = false
  private panelAlive: boolean = false

  aboutToAppear(): void {
    this.panelAlive = true
    BrowserLog.info('[ScanQrPanel] appear')
  }

  aboutToDisappear(): void {
    this.panelAlive = false
    void ScanQrService.stopPreview()
  }

  private close(): void {
    ScanQrService.clearResumeAfterBrowse()
    ScanQrService.closePanel()
  }

  private startScanLine(height: number): void {
    if (this.scanStarted || !this.panelAlive) {
      return
    }
    const travel = height - SCAN_TRAVEL_TOP - SCAN_TRAVEL_BOTTOM - 2
    if (travel < 40) {
      return
    }
    this.scanStarted = true
    this.scanLineY = SCAN_TRAVEL_TOP
    setTimeout((): void => {
      if (!this.panelAlive) {
        return
      }
      this.scanLineY = SCAN_TRAVEL_TOP + travel
    }, 40)
  }

  @Builder
  circleIcon(icon: Resource, size: number, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(size > 50 ? 26 : 22)
        .fontColor(['#ffffff'])
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor('rgba(0,0,0,0.38)')
    .justifyContent(FlexAlign.Center)
    .onClick(onTap)
  }

  build() {
    Stack() {
      XComponent({
        id: 'browser_scan_preview',
        type: XComponentType.SURFACE,
        controller: this.xController
      })
        .width('100%')
        .height('100%')
        .onLoad((): void => {
          const xcId = this.xController.getXComponentSurfaceId()
          BrowserLog.info(`[ScanQrPanel] preview ready id=${xcId}`)
          void ScanQrService.startPreview(xcId)
        })
        .onDestroy((): void => {
          void ScanQrService.stopPreview()
        })

      Column() {
        Row() {
          this.circleIcon($r('sys.symbol.xmark'), 44, (): void => this.close())
          Blank()
          this.circleIcon($r('sys.symbol.arrow_triangle_2_circlepath_camera'), 44, (): void => {
            ScanQrService.switchCamera()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: Math.max(this.safeAreaTop, 10) + 6 })

        Text($r('app.string.scan_banner'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#ffffff')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 10, bottom: 16 })

        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(2)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [
                ['rgba(255,255,255,0.00)', 0.00],
                ['rgba(255,255,255,0.55)', 0.08],
                ['rgba(255,255,255,1.00)', 0.50],
                ['rgba(255,255,255,0.55)', 0.92],
                ['rgba(255,255,255,0.00)', 1.00]
              ]
            })
            .offset({ y: this.scanLineY })
            .animation({
              duration: SCAN_LINE_DURATION,
              curve: Curve.Linear,
              iterations: -1,
              playMode: PlayMode.Alternate,
              expectedFrameRateRange: {
                expected: 60,
                min: 30,
                max: 60
              }
            })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .clip(true)
        .onAreaChange((_old: Area, area: Area): void => {
          const h = Number(area.height)
          if (h > 0) {
            this.startScanLine(h)
          }
        })

        Row() {
          this.circleIcon($r('sys.symbol.picture'), 56, (): void => {
            void ScanQrService.pickFromAlbum()
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({
          top: 12,
          bottom: Math.max(this.safeAreaBottom, 0) + 28
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
