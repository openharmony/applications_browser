import { BrowserStore } from 'browser_core'

import { BrowseWebContextSheet } from './BrowseWebContextSheet'

import { DownloadFlowDialog } from 'download'

import { BrowserStrings } from 'common'

import { BrowserLog } from 'common'

import { OpenShareOptions } from 'common'

import { ShareSheet } from 'settings'



/** 缃戦〉鍥剧墖鍏ㄥ睆棰勮锛氬弻鎸囨崗鍚堢缉灏?/ 鎷変几鏀惧ぇ锛屽崟鎸囨嫋鍔紙鏀惧ぇ鍚庯級锛岄暱鎸夎彍鍗?*/

@Component

export struct WebImageLightbox {

  private static readonly MIN_SCALE: number = 0.35

  private static readonly MAX_SCALE: number = 5

  private static readonly LONG_PRESS_MS: number = 500

  private static readonly MOVE_THRESHOLD: number = 10

  private static readonly DISMISS_SWIPE_THRESHOLD: number = 60



  @StorageLink('browser_image_preview_visible') @Watch('onVisibleChange') visible: boolean = false

  @StorageLink('browser_image_preview_url') imageUrl: string = ''

  @StorageLink('browser_share_visible') shareVisible: boolean = false

  @StorageLink('browser_dl_dialog') dlDialog: string = ''



  @State private imageScale: number = 1

  @State private offsetX: number = 0

  @State private offsetY: number = 0

  @State private dismissOffsetX: number = 0

  @State private showContextMenu: boolean = false



  private pinchStartScale: number = 1

  private panBaseX: number = 0

  private panBaseY: number = 0

  private pressTimer: number = -1

  private touchActive: boolean = false

  private touchOriginX: number = 0

  private touchOriginY: number = 0

  private longPressTriggered: boolean = false



  private onVisibleChange(): void {

    if (!this.visible) {

      this.showContextMenu = false

      this.clearPressTimer()

      this.resetTransform()

    }

  }



  private resetTransform(): void {

    this.imageScale = 1

    this.offsetX = 0

    this.offsetY = 0

    this.dismissOffsetX = 0

  }



  private isAtDefaultScale(): boolean {

    return this.imageScale <= 1.02

  }



  private clearPressTimer(): void {

    if (this.pressTimer >= 0) {

      clearTimeout(this.pressTimer)

      this.pressTimer = -1

    }

  }



  private close(): void {

    this.showContextMenu = false

    this.clearPressTimer()

    BrowserLog.info('[ImagePreview] lightbox close')

    BrowserStore.closeImagePreview()

    this.resetTransform()

  }



  private openContextMenu(): void {

    this.longPressTriggered = true

    this.showContextMenu = true

    BrowserLog.info('[ImagePreview] longPress open context menu')

  }



  /** Touch 鍒嗗彂闀挎寜鑿滃崟锛圥arallel PanGesture 浼氬悶鎺?LongPressGesture锛屾敼鐢?Touch锛?*/

  private onImageTouch(event: TouchEvent): void {

    if (this.showContextMenu) {

      return

    }



    if (event.type === TouchType.Down) {

      this.touchActive = true

      this.longPressTriggered = false

      const touch = event.touches[0]

      if (touch) {

        this.touchOriginX = touch.x

        this.touchOriginY = touch.y

      }

      this.panBaseX = this.offsetX

      this.panBaseY = this.offsetY

      this.clearPressTimer()

      this.pressTimer = setTimeout(() => {

        this.pressTimer = -1

        if (!this.touchActive || this.showContextMenu) {

          return

        }

        this.openContextMenu()

      }, WebImageLightbox.LONG_PRESS_MS)

      return

    }



    if (!this.touchActive) {

      return

    }



    if (event.type === TouchType.Move) {

      const touch = event.touches[0]

      if (!touch) {

        return

      }

      const dx = touch.x - this.touchOriginX

      const dy = touch.y - this.touchOriginY

      if (!this.longPressTriggered &&

        (Math.abs(dx) > WebImageLightbox.MOVE_THRESHOLD || Math.abs(dy) > WebImageLightbox.MOVE_THRESHOLD)) {

        this.clearPressTimer()

      }

      if (this.longPressTriggered) {

        return

      }

      if (this.isAtDefaultScale()) {

        if (Math.abs(dx) >= Math.abs(dy)) {

          this.dismissOffsetX = dx

        }

      } else {

        this.offsetX = this.panBaseX + dx

        this.offsetY = this.panBaseY + dy

      }

      return

    }



    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {

      this.touchActive = false

      this.clearPressTimer()

      const touch = event.touches[0] ?? event.changedTouches[0]

      let dx = this.dismissOffsetX

      if (touch) {

        dx = touch.x - this.touchOriginX

      }

      if (!this.longPressTriggered && this.isAtDefaultScale()) {

        if (this.dlDialog.length > 0) {

          this.dismissOffsetX = 0

          return

        }

        if (Math.abs(dx) >= WebImageLightbox.DISMISS_SWIPE_THRESHOLD) {

          BrowserLog.info(`[ImagePreview] touch dismiss offsetX=${dx.toFixed(0)}`)

          this.close()

          return

        }

        this.dismissOffsetX = 0

      }

      this.longPressTriggered = false

    }

  }



  private onPinchStart(): void {

    this.clearPressTimer()

    this.pinchStartScale = this.imageScale

  }



  private onPinchUpdate(scale: number): void {

    const next = this.pinchStartScale * scale

    this.imageScale = Math.min(WebImageLightbox.MAX_SCALE, Math.max(WebImageLightbox.MIN_SCALE, next))

  }



  private onEdgeSwipeDismiss(offsetX: number): void {

    if (this.showContextMenu || this.dlDialog.length > 0) {

      return

    }

    if (Math.abs(offsetX) >= WebImageLightbox.DISMISS_SWIPE_THRESHOLD) {

      BrowserLog.info(`[ImagePreview] edge dismiss offsetX=${offsetX.toFixed(0)}`)

      this.close()

    } else {

      animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {

        this.dismissOffsetX = 0

      })

    }

  }



  private handleContextAction(action: string): void {

    const url = this.imageUrl

    this.showContextMenu = false

    if (action === 'copy_image') {

      BrowserStore.requestCopyImage(url)

    } else if (action === 'save_image') {

      BrowserStore.requestSaveImage(url)

    } else if (action === 'share_image') {

      const shareOpts: OpenShareOptions = {

        title: BrowserStrings.txt($r('app.string.web_image_share_title')),

        url: url,

        previewImage: true,

      }

      BrowserLog.info(`[ImagePreview] share_image url=${url.slice(0, 120)} previewVisible=${this.visible}`)

      BrowserStore.openShare(shareOpts)

    }

  }



  build() {

    Stack({ alignContent: Alignment.TopStart }) {

      // 鍒嗕韩鎵撳紑鏃堕殣钘?Image锛堢嫭绔嬪悎鎴愬眰浼氱洊浣忓悓绾?overlay锛屼粎璋?zIndex 鏃犳晥锛?

      if (this.visible && this.imageUrl.length > 0 && !this.shareVisible) {

        Column()

          .width('100%')

          .height('100%')

          .backgroundColor('#000000')

          .onClick(() => {

            if (!this.showContextMenu && this.dlDialog.length === 0) {

              this.close()

            }

          })



        Column() {

          Image(this.imageUrl)

            .width('100%')

            .height('100%')

            .objectFit(ImageFit.Contain)

            .scale({ x: this.imageScale, y: this.imageScale })

            .translate({

              x: this.offsetX + (this.isAtDefaultScale() ? this.dismissOffsetX : 0),

              y: this.offsetY

            })

            .animation({ duration: 0 })

        }

        .width('100%')

        .height('100%')

        .justifyContent(FlexAlign.Center)

        .hitTestBehavior(this.showContextMenu || this.dlDialog.length > 0 ? HitTestMode.None : HitTestMode.Default)

        .onTouch((event: TouchEvent) => {

          this.onImageTouch(event)

        })

        .gesture(

          PinchGesture({ fingers: 2 })

            .onActionStart(() => {

              this.onPinchStart()

            })

            .onActionUpdate((event: GestureEvent) => {

              this.onPinchUpdate(event.scale)

            })

        )



        // 杈圭紭渚ф粦鍏抽棴锛堜粎宸﹀彸 48px 鎺ョ锛屼腑闂村尯鍩熺暀缁欏浘鐗?Touch锛?

        Row() {

          Column()

            .width(48)

            .height('100%')

            .hitTestBehavior(HitTestMode.Default)

            .gesture(

              PanGesture({ direction: PanDirection.Right, distance: 1 })

                .onActionUpdate((event: GestureEvent) => {

                  if (this.isAtDefaultScale() && event.offsetX > 0) {

                    this.dismissOffsetX = event.offsetX

                  }

                })

                .onActionEnd((event: GestureEvent) => {

                  this.onEdgeSwipeDismiss(event.offsetX)

                })

            )

          Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)

          Column()

            .width(48)

            .height('100%')

            .hitTestBehavior(HitTestMode.Default)

            .gesture(

              PanGesture({ direction: PanDirection.Left, distance: 1 })

                .onActionUpdate((event: GestureEvent) => {

                  if (this.isAtDefaultScale() && event.offsetX < 0) {

                    this.dismissOffsetX = event.offsetX

                  }

                })

                .onActionEnd((event: GestureEvent) => {

                  this.onEdgeSwipeDismiss(event.offsetX)

                })

            )

        }

        .width('100%')

        .height('100%')

        .hitTestBehavior(HitTestMode.Transparent)



        Row() {

          Blank().layoutWeight(1)

          Text('×')

            .fontSize(28)

            .fontColor('#ffffff')

            .width(44)

            .height(44)

            .textAlign(TextAlign.Center)

            .borderRadius(22)

            .backgroundColor('rgba(255,255,255,0.18)')

            .onClick(() => {

              if (this.dlDialog.length === 0) {

                this.close()

              }

            })

        }

        .width('100%')

        .padding({ top: 48, right: 16 })

      }



      // 鍏ㄥ睆棰勮鍐呭垎浜細涓?lightbox 鍚?Stack锛岄伩鍏?Image 鍚堟垚灞傞伄鎸?

      if (this.visible && this.shareVisible) {

        ShareSheet()

          .width('100%')

          .height('100%')

      }

      // 鍏ㄥ睆棰勮鍐呬笅杞界‘璁わ細涓?ShareSheet 鍚屽眰锛岄伩鍏嶈 Image 鍚堟垚灞傛垨 zIndex 6000 閬尅

      if (this.visible && this.dlDialog.length > 0) {

        DownloadFlowDialog()

          .width('100%')

          .height('100%')

      }

    }

    .width('100%')

    .height('100%')

    .zIndex(6000)

    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)

    .bindContentCover(this.visible && this.showContextMenu, this.ImageContextCover(), {
      modalTransition: ModalTransition.NONE
    })

  }



  @Builder

  ImageContextCover() {

    BrowseWebContextSheet({

      visible: true,

      actions: ['copy_image', 'save_image', 'share_image'],

      onClose: () => {

        this.showContextMenu = false

      },

      onAction: (action: string) => {

        this.handleContextAction(action)

        this.showContextMenu = false

      }

    })

  }

}

