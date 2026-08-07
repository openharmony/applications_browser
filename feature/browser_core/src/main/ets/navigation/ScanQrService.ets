import { common, Want } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { BrowserNavigation } from '../BrowserNavigation'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'

/** 系统扫码服务包名 */
const SCAN_SERVICE_BUNDLE = 'com.ohos.scanservice'
/** 全屏默认扫码 Ability */
const SCAN_ABILITY_NAME = 'ScanAbility'
/** Scan Kit 二维码类型枚举值（scanCore.ScanType.QR_CODE） */
const SCAN_TYPE_QR_CODE = 11

/** 传给 ScanAbility 的 scanOption 结构 */
interface ScanOptionPayload {
  enableAlbum: boolean
  enableMultiMode: boolean
  scanTypes: number[]
}

/** ScanAbility 回传参数字段 */
interface ScanResultParameters {
  originalValue?: string
  scanType?: number
}

/**
 * 首页扫一扫：调起系统 Scan Service 默认扫码界面，识别二维码后跳转网页。
 * 通过 startAbilityForResult 拉起 com.ohos.scanservice，避免应用内直接加载 @kit.ScanKit 模块。
 */
export class ScanQrService {
  private static scanning: boolean = false

  /** 从首页地址栏旁扫一扫入口启动扫码 */
  static startScanFromHome(): void {
    void ScanQrService.launchScan()
  }

  private static async launchScan(): Promise<void> {
    if (ScanQrService.scanning) {
      return
    }
    const ctx = BrowserStore.getContext()
    if (!ctx) {
      BrowserLog.warn('[ScanQr] no UIAbilityContext')
      return
    }
    ScanQrService.scanning = true
    try {
      const scanOption: ScanOptionPayload = {
        enableAlbum: true,
        enableMultiMode: false,
        scanTypes: [SCAN_TYPE_QR_CODE],
      }
      const want: Want = {
        bundleName: SCAN_SERVICE_BUNDLE,
        abilityName: SCAN_ABILITY_NAME,
        parameters: {
          scanOption: scanOption,
        },
      }
      const abilityResult = await ctx.startAbilityForResult(want)
      ScanQrService.handleScanAbilityResult(abilityResult)
    } catch (err) {
      const code = (err as BusinessError).code ?? 0
      BrowserLog.error(`[ScanQr] startAbilityForResult failed code=${code}: ${JSON.stringify(err)}`)
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_failed')))
    } finally {
      ScanQrService.scanning = false
    }
  }

  private static handleScanAbilityResult(abilityResult: common.AbilityResult): void {
    if (abilityResult.resultCode !== 0) {
      BrowserLog.info(`[ScanQr] user canceled or empty result, code=${abilityResult.resultCode}`)
      return
    }
    const params = abilityResult.want?.parameters as ScanResultParameters | undefined
    const value = (params?.originalValue ?? '').trim()
    if (!value) {
      BrowserLog.info('[ScanQr] no originalValue in result')
      return
    }
    ScanQrService.navigateFromScanResult(value)
  }

  /** 将扫码内容解析为网址并在当前首页标签打开 */
  private static navigateFromScanResult(raw: string): void {
    const content = raw.trim()
    if (!content) {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_no_valid_link')))
      return
    }
    if (/^https?:\/\//i.test(content)) {
      BrowserNavigation.openBrowse(content, { preferHomeTab: true })
      return
    }
    const check = BrowserNavigation.validateUrlInput(content)
    if (check.ok && check.url) {
      BrowserNavigation.openBrowse(check.url, { preferHomeTab: true })
      return
    }
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.scan_no_valid_link')))
  }
}
