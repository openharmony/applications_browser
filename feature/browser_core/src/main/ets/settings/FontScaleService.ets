import { BrowserLog } from 'common'
import { BrowserStrings } from 'common'
import { AppStorageKeys } from 'common'

/** 字体档位与系统比例 → AppStorage 有效倍率，驱动 UI 实时刷新 */
export class FontScaleService {
  /** 根据当前档位与系统比例计算 UI 倍率 */
  static currentFactor(): number {
    const key = BrowserStrings.normalizeFontSizeKey(
      AppStorage.get<string>(AppStorageKeys.FONT_SIZE) ?? 'system')
    if (key === 'system') {
      const sys = AppStorage.get<number>(AppStorageKeys.SYSTEM_FONT_SIZE_SCALE) ?? 1
      return sys > 0 ? sys : 1
    }
    return BrowserStrings.fontSizeUiScale(key)
  }

  /**
   * 写入 FONT_UI_SCALE，必要时递增 FONT_UI_REV 触发全树重建。
   * @param reason 日志来源
   * @param bumpRev 是否递增刷新序号
   */
  static publish(reason: string, bumpRev: boolean): void {
    const factor = FontScaleService.currentFactor()
    const tier = BrowserStrings.normalizeFontSizeKey(
      AppStorage.get<string>(AppStorageKeys.FONT_SIZE) ?? 'system')
    const prevScale = AppStorage.get<number>(AppStorageKeys.FONT_UI_SCALE) ?? factor
    AppStorage.set(AppStorageKeys.FONT_UI_SCALE, factor)
    const scaleChanged = Math.abs(prevScale - factor) > 0.001
    let rev = AppStorage.get<number>(AppStorageKeys.FONT_UI_REV) ?? 0
    if (bumpRev || scaleChanged) {
      rev += 1
      AppStorage.set(AppStorageKeys.FONT_UI_REV, rev)
    }
    BrowserLog.info(`[Font] publish reason=${reason} tier=${tier} factor=${factor.toFixed(2)} rev=${rev} ` +
      `bump=${bumpRev} scaleCh=${scaleChanged}`)
  }
}
