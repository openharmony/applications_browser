import { bundleManager } from '@kit.AbilityKit'
import { sms } from '@kit.TelephonyKit'
import { AppStorageKeys } from 'common'
import { BrowserLog } from 'common'

/** 分享面板各入口是否可用（对应应用已安装或系统能力具备） */
export interface ShareAppsAvailability {
  wechat: boolean
  qq: boolean
  sms: boolean
  wecom: boolean
  douyin: boolean
  systemShare: boolean
  bluetooth: boolean
  transfer: boolean
}

export const DEFAULT_SHARE_APPS: ShareAppsAvailability = {
  wechat: false,
  qq: false,
  sms: false,
  wecom: false,
  douyin: false,
  systemShare: false,
  bluetooth: true,
  transfer: false
}

/** 探测第三方分享应用是否已安装 */
export class ShareAppAvailability {
  static readonly BUNDLE_WECHAT: string[] = ['com.tencent.wechat', 'com.tencent.mm']
  static readonly BUNDLE_QQ: string[] = ['com.tencent.mobileqq']
  static readonly BUNDLE_WECOM: string[] = ['com.tencent.wework']
  static readonly BUNDLE_DOUYIN: string[] = ['com.ss.hm.ugc.aweme', 'com.ss.android.ugc.aweme']
  static readonly BUNDLE_TRANSFER: string[] = ['com.huawei.distributedpasteboard', 'com.ohos.superhub']
  /** 系统短信应用包名 */
  static readonly BUNDLE_MMS: string[] = ['com.ohos.mms']
  /** 系统近场分享包名候选（各产品版本） */
  static readonly BUNDLE_SYSTEM_SHARE: string[] = [
    'com.huawei.hmos.sharedialog',
    'com.huawei.android.instantshare',
    'com.ohos.sharepanel'
  ]

  private static cached: ShareAppsAvailability | null = null

  /** 返回上次探测结果 */
  static getCached(): ShareAppsAvailability {
    const fromStorage = AppStorage.get<ShareAppsAvailability>(AppStorageKeys.SHARE_APPS)
    if (fromStorage !== undefined && fromStorage !== null) {
      return fromStorage
    }
    if (ShareAppAvailability.cached !== null) {
      return ShareAppAvailability.cached
    }
    return DEFAULT_SHARE_APPS
  }

  /** 异步探测全部分享入口可用性并同步到 AppStorage */
  static async probe(): Promise<ShareAppsAvailability> {
    const result: ShareAppsAvailability = {
      wechat: await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_WECHAT),
      qq: await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_QQ),
      sms: await ShareAppAvailability.isSmsShareAvailable(),
      wecom: await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_WECOM),
      douyin: await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_DOUYIN),
      systemShare: await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_SYSTEM_SHARE),
      bluetooth: true,
      transfer: await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_TRANSFER)
    }
    ShareAppAvailability.publishAvailability(result)
    BrowserLog.info(`[ShareAvail] wechat=${result.wechat} qq=${result.qq} sms=${result.sms} ` +
      `wecom=${result.wecom} douyin=${result.douyin} systemShare=${result.systemShare} transfer=${result.transfer}`)
    return result
  }

  private static publishAvailability(result: ShareAppsAvailability): void {
    ShareAppAvailability.cached = result
    AppStorage.set(AppStorageKeys.SHARE_APPS, {
      wechat: result.wechat,
      qq: result.qq,
      sms: result.sms,
      wecom: result.wecom,
      douyin: result.douyin,
      systemShare: result.systemShare,
      bluetooth: result.bluetooth,
      transfer: result.transfer
    })
  }

  /** 短信分享是否可用：优先探测短信 App；探测失败时仍展示（避免误隐藏） */
  static async isSmsShareAvailable(): Promise<boolean> {
    if (await ShareAppAvailability.isAnyBundleInstalled(ShareAppAvailability.BUNDLE_MMS)) {
      return true
    }
    if (ShareAppAvailability.hasSmsCapabilitySync()) {
      return true
    }
    // 三方应用可能无法查询系统包信息，仍展示短信入口，点击时由 shareLinkViaSms 兜底
    return true
  }

  private static hasSmsCapabilitySync(): boolean {
    try {
      return sms.hasSmsCapability()
    } catch (_err) {
      return false
    }
  }

  private static async isAnyBundleInstalled(candidates: string[]): Promise<boolean> {
    for (let i = 0; i < candidates.length; i++) {
      if (await ShareAppAvailability.isBundleInstalled(candidates[i])) {
        return true
      }
    }
    return false
  }

  private static async isBundleInstalled(bundleName: string): Promise<boolean> {
    try {
      await bundleManager.getBundleInfo(bundleName, bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return true
    } catch (_err) {
      return false
    }
  }
}
