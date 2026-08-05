import { describe, it, expect } from '@ohos/hypium'
import { BrowserStrings } from '../main/ets/common/BrowserStrings'

/** 字体档位逻辑回归：Web 缩放与 UI 系数 */
export default function fontScaleTest() {
  describe('FontScaleTest', () => {
    it('webZoom_small_isFixed85', 0, () => {
      expect(BrowserStrings.computeWebTextZoomRatio('small', 1.3)).assertEqual(85)
    })

    it('webZoom_medium_isFixed100', 0, () => {
      expect(BrowserStrings.computeWebTextZoomRatio('medium', 1.3)).assertEqual(100)
    })

    it('webZoom_large_isFixed115', 0, () => {
      expect(BrowserStrings.computeWebTextZoomRatio('large', 1.3)).assertEqual(115)
    })

    it('webZoom_system_followsSystemScale', 0, () => {
      expect(BrowserStrings.computeWebTextZoomRatio('system', 1.2)).assertEqual(120)
    })

    it('uiScale_small_is085', 0, () => {
      expect(BrowserStrings.fontSizeUiScale('small')).assertEqual(0.85)
    })

    it('normalizeFontSizeKey_defaultsToSystem', 0, () => {
      expect(BrowserStrings.normalizeFontSizeKey('')).assertEqual('system')
      expect(BrowserStrings.normalizeFontSizeKey('invalid')).assertEqual('system')
    })

    it('fontSizeKeys_hasFourTiers', 0, () => {
      const keys = BrowserStrings.fontSizeKeys()
      expect(keys.length).assertEqual(4)
      expect(keys[0]).assertEqual('system')
      expect(keys[1]).assertEqual('small')
    })

    it('uiScale_small_is085', 0, () => {
      expect(BrowserStrings.fontSizeUiScale('small')).assertEqual(0.85)
    })
  })
}
