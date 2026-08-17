import { deviceInfo } from '@kit.BasicServicesKit'

/** 设备形态判断（手机 / 平板 / 2in1） */
export class BrowserDeviceProfile {
  /** 是否为 Pad 形态：地址栏展示下载快捷入口 */
  static isPadFormFactor(): boolean {
    const type = deviceInfo.deviceType
    return type === 'tablet' || type === '2in1'
  }

  /**
   * 是否为 Phone 形态。
   * phone：手机；default：部分机型/模拟器回落值，按手机策略处理。
   */
  static isPhoneFormFactor(): boolean {
    const type = deviceInfo.deviceType
    return type === 'phone' || type === 'default'
  }
}
