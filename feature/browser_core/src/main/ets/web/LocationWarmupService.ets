import { geoLocationManager } from '@kit.LocationKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { webview } from '@kit.ArkWeb'
import { BrowserLog } from 'common'
import { BrowserStore } from '../BrowserStore'
import { BrowserStrings } from 'common'
import { WebPermissionGate } from './WebPermissionGate'

/** 3301100：系统定位总开关关闭 */
const ERR_LOCATION_SWITCH_OFF: number = 3301100

/** GPS 预热超时（毫秒） */
const GPS_WARMUP_TIMEOUT_MS: number = 25000

/** 网络定位回退超时（毫秒） */
const NETWORK_LOCATE_TIMEOUT_MS: number = 15000

/** 定位缓存状态 */
export type LocationCacheState = 'idle' | 'switchOff' | 'processing' | 'success' | 'failure'

/** 缓存坐标 */
export interface CachedLocation {
  latitude: number
  longitude: number
  accuracy: number
  timestamp: number
}

/**
 * 应用启动预热 + 网站 geolocation 请求的状态机。
 * 启动：检查系统定位开关 → GPS 预热 → 失败则网络定位 → 缓存/记录状态。
 */
export class LocationWarmupService {
  private static state: LocationCacheState = 'idle'
  private static cached: CachedLocation | null = null
  private static pipelineRunning: boolean = false
  private static lastTrigger: string = ''
  private static lastCode: number = 0

  static getState(): LocationCacheState {
    return LocationWarmupService.state
  }

  static getCachedLocation(): CachedLocation | null {
    return LocationWarmupService.cached
  }

  static isWarmupReady(): boolean {
    return LocationWarmupService.state === 'success' && LocationWarmupService.cached !== null
  }

  /** 预热是否仍在进行 */
  static isProcessing(): boolean {
    return LocationWarmupService.state === 'processing' || LocationWarmupService.pipelineRunning
  }

  /** 系统定位总开关是否关闭 */
  static isSystemLocationSwitchOff(): boolean {
    return LocationWarmupService.state === 'switchOff' ||
      LocationWarmupService.lastCode === ERR_LOCATION_SWITCH_OFF
  }

  /** 兼容旧日志：预热快照 */
  static getSnapshot(): LocationWarmupSnapshot {
    return {
      warming: LocationWarmupService.isProcessing(),
      lastTrigger: LocationWarmupService.lastTrigger,
      lastStartMs: 0,
      lastCompleteMs: 0,
      lastElapsedMs: -1,
      lastOk: LocationWarmupService.state === 'success',
      lastCode: LocationWarmupService.lastCode,
      systemSwitchOff: LocationWarmupService.isSystemLocationSwitchOff()
    }
  }

  /** 应用启动或设置开启定位后触发（需网站位置允许 + 应用位置权限已授予） */
  static startAtAppLaunch(trigger: string = 'appInit'): void {
    if (!BrowserStore.isAppPermissionGranted('location')) {
      BrowserLog.info(`[Location] start skip trigger=${trigger} reason=appPermNotGranted`)
      return
    }
    if (BrowserStore.getSitePermission('location') !== 'allow') {
      BrowserLog.info(`[Location] start skip trigger=${trigger} reason=sitePolicyDeny`)
      return
    }
    if (LocationWarmupService.isProcessing()) {
      BrowserLog.info(`[Location] start skip trigger=${trigger} reason=processing`)
      return
    }
    if (LocationWarmupService.state === 'success' && LocationWarmupService.cached !== null) {
      BrowserLog.info(`[Location] start skip trigger=${trigger} reason=alreadySuccess`)
      return
    }
    BrowserLog.info(`[Location] start trigger=${trigger} sitePolicy=allow`)
    void LocationWarmupService.runWarmupPipeline(trigger)
  }

  /**
   * 网站 onGeolocationShow：按浏览器设置 → 定位状态依次处理。
   * 仅使用 GeolocationPermissions 静态 API，不调用 event.geolocation.invoke（native SIGSEGV 风险）。
   */
  static handleWebGeolocationShow(
    origin: string,
    siteAllowed: boolean,
    appGranted: boolean,
    incognito: boolean): void {
    const normOrigin: string = WebPermissionGate.normalizeWebOrigin(origin)
    if (!siteAllowed) {
      WebPermissionGate.getInstance().denySiteLocationRequest(normOrigin, incognito)
      BrowserLog.info(`[Location] webGeo deny reason=siteNotAllowed origin=${normOrigin.slice(0, 80)}`)
      return
    }
    if (!appGranted) {
      LocationWarmupService.denyGeolocation(normOrigin, incognito)
      BrowserLog.info(`[Location] webGeo deny reason=appPermNotGranted origin=${normOrigin.slice(0, 80)}`)
      return
    }
    const state = LocationWarmupService.state
    BrowserLog.info(`[Location] webGeo state=${state} origin=${normOrigin.slice(0, 80)}`)
    if (state === 'switchOff') {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.web_location_fetch_failed_hint')))
      LocationWarmupService.denyGeolocation(normOrigin, incognito)
      return
    }
    if (state === 'processing') {
      BrowserStore.showToast(BrowserStrings.txt($r('app.string.web_location_loading_hint')))
      LocationWarmupService.denyGeolocation(normOrigin, incognito)
      return
    }
    if (state === 'success' && LocationWarmupService.cached !== null) {
      const c = LocationWarmupService.cached
      WebPermissionGate.getInstance().grantGeolocationForShow(normOrigin, incognito)
      BrowserLog.info(`[Location] webGeo allow static lat=${c.latitude.toFixed(4)} lng=${c.longitude.toFixed(4)} acc=${c.accuracy.toFixed(0)}`)
      return
    }
    BrowserStore.showToast(BrowserStrings.txt($r('app.string.web_location_retry_failed_hint')))
    LocationWarmupService.denyGeolocation(normOrigin, incognito)
  }

  private static denyGeolocation(origin: string, incognito: boolean): void {
    try {
      WebPermissionGate.getInstance().clearGeolocationOrigin(origin, incognito)
      WebPermissionGate.getInstance().invalidateLocationSession(origin)
    } catch (e) {
      BrowserLog.warn(`[Location] denyGeolocation failed: ${JSON.stringify(e)}`)
    }
  }

  private static async runWarmupPipeline(trigger: string): Promise<void> {
    LocationWarmupService.pipelineRunning = true
    LocationWarmupService.lastTrigger = trigger
    LocationWarmupService.state = 'processing'
    LocationWarmupService.lastCode = 0
    BrowserLog.info(`[Location] pipeline start trigger=${trigger} state=processing`)

    const switchOn = await LocationWarmupService.isSystemLocationSwitchOn()
    if (!switchOn) {
      LocationWarmupService.state = 'switchOff'
      LocationWarmupService.lastCode = ERR_LOCATION_SWITCH_OFF
      LocationWarmupService.cached = null
      LocationWarmupService.pipelineRunning = false
      BrowserLog.info(`[Location] pipeline end state=switchOff trigger=${trigger}`)
      return
    }

    try {
      const gpsLoc = await LocationWarmupService.fetchLocation(
        geoLocationManager.LocatingPriority.PRIORITY_ACCURACY, GPS_WARMUP_TIMEOUT_MS, 'gps')
      LocationWarmupService.markSuccess(gpsLoc, trigger, 'gps')
      return
    } catch (gpsErr) {
      const gpsCode = (gpsErr as BusinessError).code ?? 0
      LocationWarmupService.lastCode = gpsCode
      if (gpsCode === ERR_LOCATION_SWITCH_OFF) {
        LocationWarmupService.state = 'switchOff'
        LocationWarmupService.cached = null
        LocationWarmupService.pipelineRunning = false
        BrowserLog.info(`[Location] pipeline end state=switchOff trigger=${trigger} phase=gps`)
        return
      }
      BrowserLog.warn(`[Location] gps failed trigger=${trigger} code=${gpsCode} tryNetwork=true`)
    }

    try {
      const netLoc = await LocationWarmupService.fetchLocation(
        geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED, NETWORK_LOCATE_TIMEOUT_MS, 'network')
      LocationWarmupService.markSuccess(netLoc, trigger, 'network')
    } catch (netErr) {
      const netCode = (netErr as BusinessError).code ?? 0
      LocationWarmupService.lastCode = netCode
      if (netCode === ERR_LOCATION_SWITCH_OFF) {
        LocationWarmupService.state = 'switchOff'
      } else {
        LocationWarmupService.state = 'failure'
      }
      LocationWarmupService.cached = null
      LocationWarmupService.pipelineRunning = false
      BrowserLog.warn(`[Location] pipeline end state=${LocationWarmupService.state} trigger=${trigger} code=${netCode}`)
    }
  }

  private static markSuccess(loc: geoLocationManager.Location, trigger: string, phase: string): void {
    LocationWarmupService.cached = {
      latitude: loc.latitude,
      longitude: loc.longitude,
      accuracy: loc.accuracy ?? 0,
      timestamp: loc.timeStamp ?? Date.now()
    }
    LocationWarmupService.state = 'success'
    LocationWarmupService.lastCode = 0
    LocationWarmupService.pipelineRunning = false
    const c = LocationWarmupService.cached
    BrowserLog.info(`[Location] pipeline end state=success trigger=${trigger} phase=${phase} lat=${c.latitude.toFixed(4)} lng=${c.longitude.toFixed(4)}`)
  }

  private static fetchLocation(
    priority: geoLocationManager.LocatingPriority,
    timeoutMs: number,
    phase: string): Promise<geoLocationManager.Location> {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: priority,
      locatingTimeoutMs: timeoutMs
    }
    BrowserLog.info(`[Location] fetch start phase=${phase} timeoutMs=${timeoutMs}`)
    return geoLocationManager.getCurrentLocation(request)
  }

  private static async isSystemLocationSwitchOn(): Promise<boolean> {
    try {
      const enabled = geoLocationManager.isLocationEnabled()
      BrowserLog.info(`[Location] isLocationEnabled=${enabled}`)
      return enabled
    } catch (e) {
      BrowserLog.warn(`[Location] isLocationEnabled failed: ${JSON.stringify(e)}`)
      return true
    }
  }
}

/** 兼容旧日志字段 */
export interface LocationWarmupSnapshot {
  warming: boolean
  lastTrigger: string
  lastStartMs: number
  lastCompleteMs: number
  lastElapsedMs: number
  lastOk: boolean
  lastCode: number
  systemSwitchOff: boolean
}
