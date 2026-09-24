import { camera } from '@kit.CameraKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import {
  BinaryBitmap,
  HybridBinarizer,
  QRCodeReader,
  RGBLuminanceSource
} from '@ohos/zxing'
import { AppStorageKeys, BrowserLog, BrowserStrings } from 'common'
import { BrowserNavigation } from '../BrowserNavigation'
import { BrowserStore } from '../BrowserStore'
import { AppPermissionService } from '../security/AppPermissionService'

/** 解码最长边上限 */
const MAX_DECODE_EDGE: number = 1280
/** 实时识码间隔 */
const LIVE_SCAN_INTERVAL_MS: number = 900
/** 预览/拍照目标分辨率 */
const PREFER_PREVIEW_W: number = 1280
const PREFER_PREVIEW_H: number = 720

/**
 * 首页扫一扫：全屏摄像头预览 + 实时识码，点切换才在后置/前置之间切换。
 */
export class ScanQrService {
  private static busy: boolean = false
  private static capturing: boolean = false
  private static userCapture: boolean = false
  /** 扫码结果打开浏览后，退出浏览回主页时是否恢复扫码面板 */
  private static resumeAfterBrowse: boolean = false
  private static bootId: number = 0
  private static previewXcId: string = ''
  /** 串行化预览启停，避免快速翻转时相机未释放完（7400102） */
  private static previewChain: Promise<void> = Promise.resolve()
  private static scanTimer: number = -1
  /** 当前预览摄像头，默认后置；仅 switchCamera 会改 */
  private static position: camera.CameraPosition = camera.CameraPosition.CAMERA_POSITION_BACK
  private static cameraInput: camera.CameraInput | null = null
  private static previewOutput: camera.PreviewOutput | null = null
  private static photoOutput: camera.PhotoOutput | null = null
  private static session: camera.PhotoSession | null = null
  private static photoCallback: (err: BusinessError, photo: camera.Photo) => void =
    (err: BusinessError, photo: camera.Photo): void => {
      void ScanQrService.handleCapturedPhoto(err, photo)
    }

  /** 从首页地址栏旁扫一扫入口启动扫码 */
  static startScanFromHome(): void {
    ScanQrService.position = camera.CameraPosition.CAMERA_POSITION_BACK
    BrowserLog.info('[ScanQr] startScanFromHome → panel')
    AppStorage.setOrCreate(AppStorageKeys.SCAN_QR_VISIBLE, true)
  }

  /** 关闭扫码面板并释放相机 */
  static closePanel(): void {
    AppStorage.setOrCreate(AppStorageKeys.SCAN_QR_VISIBLE, false)
    ScanQrService.busy = false
    ScanQrService.position = camera.CameraPosition.CAMERA_POSITION_BACK
    void ScanQrService.stopPreview()
  }

  /** 标记：本次浏览由扫码打开，退出浏览后应回到扫码界面 */
  static markResumeAfterBrowse(): void {
    ScanQrService.resumeAfterBrowse = true
    BrowserLog.info('[ScanQr] mark resume after browse')
  }

  /** 消费「退出浏览后恢复扫码」标记 */
  static consumeResumeAfterBrowse(): boolean {
    if (!ScanQrService.resumeAfterBrowse) {
      return false
    }
    ScanQrService.resumeAfterBrowse = false
    return true
  }

  /** 清除恢复标记（用户主动关扫码，而非扫码结果进浏览） */
  static clearResumeAfterBrowse(): void {
    ScanQrService.resumeAfterBrowse = false
  }

  /** 点击切换：后置 ↔ 前置，并重启预览 */
  static switchCamera(): void {
    if (ScanQrService.previewXcId.length === 0) {
      return
    }
    if (ScanQrService.position === camera.CameraPosition.CAMERA_POSITION_BACK) {
      ScanQrService.position = camera.CameraPosition.CAMERA_POSITION_FRONT
    } else {
      ScanQrService.position = camera.CameraPosition.CAMERA_POSITION_BACK
    }
    BrowserLog.info(`[ScanQr] switch camera → pos=${ScanQrService.position}`)
    void ScanQrService.startPreview(ScanQrService.previewXcId)
  }

  /** XComponent 绑定完成后按当前摄像头启动预览 */
  static async startPreview(xcId: string): Promise<void> {
    const sid = (xcId ?? '').trim()
    if (sid.length === 0) {
      BrowserLog.warn('[ScanQr] startPreview empty xcId')
      return
    }
    ScanQrService.previewXcId = sid
    const boot = ++ScanQrService.bootId
    const job = ScanQrService.previewChain.then((): Promise<void> => {
      return ScanQrService.startPreviewLocked(boot, sid)
    })
    ScanQrService.previewChain = job.catch((): void => {})
    await job
  }

  private static async startPreviewLocked(boot: number, sid: string): Promise<void> {
    if (boot !== ScanQrService.bootId) {
      return
    }
    await ScanQrService.releaseCamera()
    if (boot !== ScanQrService.bootId) {
      return
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserLog.warn('[ScanQr] startPreview no context')
      return
    }
    const granted = await AppPermissionService.getInstance().ensureCategoryGranted('camera')
    if (boot !== ScanQrService.bootId) {
      return
    }
    if (!granted) {
      BrowserLog.warn('[ScanQr] camera permission denied')
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      return
    }
    try {
      const cameraManager = camera.getCameraManager(ctx)
      const cameras = cameraManager.getSupportedCameras()
      if (cameras.length === 0) {
        BrowserLog.error('[ScanQr] no camera device')
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
        return
      }
      for (let i = 0; i < cameras.length; i++) {
        BrowserLog.info(`[ScanQr] device[${i}] id=${cameras[i].cameraId} pos=${cameras[i].cameraPosition}`)
      }
      const target = ScanQrService.pickCamera(cameras, ScanQrService.position)
      BrowserLog.info(`[ScanQr] use camera id=${target.cameraId} pos=${target.cameraPosition}`)
      const cap = cameraManager.getSupportedOutputCapability(target, camera.SceneMode.NORMAL_PHOTO)
      const previewProfile = ScanQrService.pickProfile(cap.previewProfiles, PREFER_PREVIEW_W, PREFER_PREVIEW_H,
        camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP)
      const photoProfile = ScanQrService.pickProfile(cap.photoProfiles, PREFER_PREVIEW_W, PREFER_PREVIEW_H,
        camera.CameraFormat.CAMERA_FORMAT_JPEG)
      if (!previewProfile || !photoProfile) {
        BrowserLog.error('[ScanQr] missing preview/photo profile')
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
        return
      }
      const cameraInput = cameraManager.createCameraInput(target)
      await cameraInput.open()
      if (boot !== ScanQrService.bootId) {
        await ScanQrService.safeCloseInput(cameraInput)
        return
      }
      const previewOutput = cameraManager.createPreviewOutput(previewProfile, sid)
      const photoOutput = cameraManager.createPhotoOutput(photoProfile)
      photoOutput.on('photoAvailable', ScanQrService.photoCallback)
      const session: camera.PhotoSession =
        cameraManager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO)
      session.beginConfig()
      session.addInput(cameraInput)
      session.addOutput(previewOutput)
      session.addOutput(photoOutput)
      await session.commitConfig()
      if (boot !== ScanQrService.bootId) {
        await ScanQrService.safeReleaseSession(session, previewOutput, photoOutput, cameraInput)
        return
      }
      await session.start()
      if (boot !== ScanQrService.bootId) {
        await ScanQrService.safeReleaseSession(session, previewOutput, photoOutput, cameraInput)
        return
      }
      ScanQrService.cameraInput = cameraInput
      ScanQrService.previewOutput = previewOutput
      ScanQrService.photoOutput = photoOutput
      ScanQrService.session = session
      ScanQrService.startScanTimer()
      BrowserLog.info(`[ScanQr] preview started pos=${ScanQrService.position}`)
    } catch (err) {
      BrowserLog.error(`[ScanQr] startPreview failed: ${JSON.stringify(err)}`)
      await ScanQrService.releaseCamera()
      if (boot === ScanQrService.bootId) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      }
    }
  }

  /** 停止预览并释放相机 */
  static stopPreview(): Promise<void> {
    ScanQrService.bootId++
    const job = ScanQrService.previewChain.then((): Promise<void> => {
      return ScanQrService.releaseCamera()
    })
    ScanQrService.previewChain = job.catch((): void => {})
    return job
  }

  /** 拉起相册选已有图片并解码（不进系统相机拍照/选图） */
  static async pickFromAlbum(): Promise<void> {
    if (ScanQrService.busy) {
      return
    }
    ScanQrService.busy = true
    const xcId = ScanQrService.previewXcId
    await ScanQrService.stopPreview()
    try {
      const options = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      options.isPhotoTakingSupported = false
      options.isEditSupported = false
      const selected = await new photoAccessHelper.PhotoViewPicker().select(options)
      const uri = (selected?.photoUris?.[0] ?? '').trim()
      if (uri.length === 0) {
        ScanQrService.restartPreviewIfNeeded(xcId)
        return
      }
      await ScanQrService.decodeAndNavigate(uri)
      if (AppStorage.get<boolean>(AppStorageKeys.SCAN_QR_VISIBLE) === true) {
        ScanQrService.restartPreviewIfNeeded(xcId)
      }
    } catch (err) {
      BrowserLog.error(`[ScanQr] album pick failed: ${JSON.stringify(err)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      ScanQrService.restartPreviewIfNeeded(xcId)
    } finally {
      ScanQrService.busy = false
    }
  }

  private static startScanTimer(): void {
    ScanQrService.stopScanTimer()
    ScanQrService.scanTimer = setInterval((): void => {
      void ScanQrService.requestCapture(false)
    }, LIVE_SCAN_INTERVAL_MS) as number
  }

  private static stopScanTimer(): void {
    if (ScanQrService.scanTimer >= 0) {
      clearInterval(ScanQrService.scanTimer)
      ScanQrService.scanTimer = -1
    }
  }

  private static async requestCapture(fromUser: boolean): Promise<void> {
    if (ScanQrService.capturing || ScanQrService.busy) {
      return
    }
    const output = ScanQrService.photoOutput
    if (output === null) {
      return
    }
    ScanQrService.capturing = true
    ScanQrService.userCapture = fromUser
    try {
      await output.capture()
    } catch (err) {
      ScanQrService.capturing = false
      ScanQrService.userCapture = false
      BrowserLog.warn(`[ScanQr] capture failed: ${JSON.stringify(err)}`)
    }
  }

  private static async handleCapturedPhoto(err: BusinessError, photo: camera.Photo): Promise<void> {
    const fromUser = ScanQrService.userCapture
    ScanQrService.userCapture = false
    ScanQrService.capturing = false
    if (err !== undefined && err !== null && err.code) {
      BrowserLog.warn(`[ScanQr] photoAvailable err: ${JSON.stringify(err)}`)
      if (fromUser) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      }
      return
    }
    if (!photo) {
      if (fromUser) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      }
      return
    }
    if (ScanQrService.busy) {
      try {
        await photo.release()
      } catch (_e) {
        // ignore
      }
      return
    }
    ScanQrService.busy = true
    let text = ''
    try {
      const jpeg = await photo.main.getComponent(image.ComponentType.JPEG)
      text = await ScanQrService.decodeQrFromBuffer(jpeg.byteBuffer.slice(0))
    } catch (decodeErr) {
      BrowserLog.warn(`[ScanQr] photo decode failed: ${JSON.stringify(decodeErr)}`)
    } finally {
      try {
        await photo.main.release()
      } catch (_e) {
        // ignore
      }
      try {
        await photo.release()
      } catch (_e) {
        // ignore
      }
    }
    if (text.length === 0) {
      ScanQrService.busy = false
      if (fromUser) {
        BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      }
      return
    }
    ScanQrService.closePanel()
    ScanQrService.navigateFromScanResult(text)
  }

  private static restartPreviewIfNeeded(xcId: string): void {
    if (AppStorage.get<boolean>(AppStorageKeys.SCAN_QR_VISIBLE) !== true) {
      return
    }
    const sid = xcId.trim()
    if (sid.length === 0) {
      return
    }
    void ScanQrService.startPreview(sid)
  }

  private static async releaseCamera(): Promise<void> {
    ScanQrService.stopScanTimer()
    ScanQrService.capturing = false
    ScanQrService.userCapture = false
    const session = ScanQrService.session
    const previewOutput = ScanQrService.previewOutput
    const photoOutput = ScanQrService.photoOutput
    const cameraInput = ScanQrService.cameraInput
    ScanQrService.session = null
    ScanQrService.previewOutput = null
    ScanQrService.photoOutput = null
    ScanQrService.cameraInput = null
    await ScanQrService.safeReleaseSession(session, previewOutput, photoOutput, cameraInput)
  }

  private static async safeReleaseSession(session: camera.PhotoSession | null,
    previewOutput: camera.PreviewOutput | null, photoOutput: camera.PhotoOutput | null,
    cameraInput: camera.CameraInput | null): Promise<void> {
    if (photoOutput !== null) {
      try {
        photoOutput.off('photoAvailable', ScanQrService.photoCallback)
      } catch (_e) {
        // ignore
      }
    }
    if (session !== null) {
      try {
        await session.stop()
      } catch (_e) {
        // ignore
      }
      try {
        await session.release()
      } catch (_e) {
        // ignore
      }
    }
    if (previewOutput !== null) {
      try {
        await previewOutput.release()
      } catch (_e) {
        // ignore
      }
    }
    if (photoOutput !== null) {
      try {
        await photoOutput.release()
      } catch (_e) {
        // ignore
      }
    }
    await ScanQrService.safeCloseInput(cameraInput)
  }

  private static async safeCloseInput(cameraInput: camera.CameraInput | null): Promise<void> {
    if (cameraInput === null) {
      return
    }
    try {
      await cameraInput.close()
    } catch (_e) {
      // ignore
    }
  }

  private static pickCamera(cameras: camera.CameraDevice[],
    prefer: camera.CameraPosition): camera.CameraDevice {
    for (let i = 0; i < cameras.length; i++) {
      if (cameras[i].cameraPosition === prefer) {
        return cameras[i]
      }
    }
    return cameras[0]
  }

  private static pickProfile(profiles: camera.Profile[], preferW: number, preferH: number,
    preferFormat: camera.CameraFormat): camera.Profile | null {
    if (!profiles || profiles.length === 0) {
      return null
    }
    const matched: camera.Profile[] = []
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].format === preferFormat) {
        matched.push(profiles[i])
      }
    }
    const pool = matched.length > 0 ? matched : profiles
    let best = pool[0]
    let bestScore = Math.abs(best.size.width - preferW) + Math.abs(best.size.height - preferH)
    for (let i = 1; i < pool.length; i++) {
      const p = pool[i]
      const score = Math.abs(p.size.width - preferW) + Math.abs(p.size.height - preferH)
      if (score < bestScore) {
        best = p
        bestScore = score
      }
    }
    return best
  }

  private static async decodeAndNavigate(uri: string): Promise<void> {
    const text = await ScanQrService.decodeQrFromUri(uri)
    if (text.length === 0) {
      BrowserLog.info('[ScanQr] decode empty')
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
      return
    }
    BrowserLog.info(`[ScanQr] decode ok len=${text.length}`)
    ScanQrService.closePanel()
    ScanQrService.navigateFromScanResult(text)
  }

  private static async decodeQrFromUri(uri: string): Promise<string> {
    let file: fileIo.File | null = null
    let imageSource: image.ImageSource | null = null
    try {
      // PhotoViewPicker 返回 file://media/Photo/...，不能当沙箱路径直接解码
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      imageSource = image.createImageSource(file.fd)
      if (imageSource === null || imageSource === undefined) {
        BrowserLog.warn('[ScanQr] decode uri empty ImageSource')
        return ''
      }
      return await ScanQrService.decodeQrFromImageSource(imageSource)
    } catch (err) {
      BrowserLog.warn(`[ScanQr] decode uri failed: ${JSON.stringify(err)}`)
      return ''
    } finally {
      try {
        imageSource?.release()
      } catch (_e) {
        // ignore
      }
      if (file !== null) {
        try {
          fileIo.closeSync(file)
        } catch (_e) {
          // ignore
        }
      }
    }
  }

  private static async decodeQrFromBuffer(buffer: ArrayBuffer): Promise<string> {
    let imageSource: image.ImageSource | null = null
    try {
      imageSource = image.createImageSource(buffer)
      return await ScanQrService.decodeQrFromImageSource(imageSource)
    } catch (err) {
      BrowserLog.warn(`[ScanQr] decode buffer failed: ${JSON.stringify(err)}`)
      return ''
    } finally {
      try {
        imageSource?.release()
      } catch (_e) {
        // ignore
      }
    }
  }

  private static async decodeQrFromImageSource(imageSource: image.ImageSource): Promise<string> {
    let pixelMap: image.PixelMap | null = null
    try {
      const srcInfo = await imageSource.getImageInfo()
      const srcW = srcInfo.size.width
      const srcH = srcInfo.size.height
      if (srcW <= 0 || srcH <= 0) {
        return ''
      }
      const scale = Math.min(1, MAX_DECODE_EDGE / Math.max(srcW, srcH))
      const targetW = Math.max(1, Math.floor(srcW * scale))
      const targetH = Math.max(1, Math.floor(srcH * scale))
      pixelMap = await imageSource.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: { width: targetW, height: targetH }
      })
      return ScanQrService.decodeQrFromPixelMap(pixelMap)
    } catch (_err) {
      return ''
    } finally {
      try {
        pixelMap?.release()
      } catch (_e) {
        // ignore
      }
    }
  }

  private static decodeQrFromPixelMap(pixelMap: image.PixelMap): string {
    const info = pixelMap.getImageInfoSync()
    const width = info.size.width
    const height = info.size.height
    const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
    pixelMap.readPixelsToBufferSync(buffer)
    const rgba = new Uint8Array(buffer)
    const luminances = new Uint8ClampedArray(width * height)
    for (let i = 0, o = 0; i < luminances.length && o + 3 < rgba.length; i++, o += 4) {
      luminances[i] = ((rgba[o] + rgba[o + 1] * 2 + rgba[o + 2]) / 4) & 0xFF
    }
    const result = new QRCodeReader().decode(
      new BinaryBitmap(new HybridBinarizer(new RGBLuminanceSource(luminances, width, height)))
    )
    return (result.getText() ?? '').trim()
  }

  private static navigateFromScanResult(raw: string): void {
    const content = raw.trim()
    if (!content) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_no_valid_link')))
      return
    }
    if (/^https?:\/\//i.test(content)) {
      // 短链/商详常 replace 历史且登录在 iframe → webBack=false 会直接退浏览；
      // 标记后由 MainPage 恢复扫码，避免「返回进首页而不是扫码」。
      ScanQrService.markResumeAfterBrowse()
      BrowserNavigation.openBrowse(content, { preferHomeTab: true })
      return
    }
    const check = BrowserNavigation.validateUrlInput(content)
    if (check.ok && check.url) {
      ScanQrService.markResumeAfterBrowse()
      BrowserNavigation.openBrowse(check.url, { preferHomeTab: true })
      return
    }
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_no_valid_link')))
  }
}
