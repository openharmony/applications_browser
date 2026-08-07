/** 浏览器设置键常量，对应 settings 表键名 */
export class SettingsKeys {
  /** 默认搜索引擎 ID */
  static readonly DEFAULT_SEARCH_ENGINE: string = 'defaultSearchEngine'
  /** 主题模式（light / dark） */
  static readonly THEME_MODE: string = 'themeMode'
  /** 无图模式开关 */
  static readonly IMAGE_LESS_MODE: string = 'imageLessMode'
  /** 夜间模式开关 */
  static readonly NIGHT_MODE: string = 'nightMode'
  /** 无痕模式开关 */
  static readonly INCOGNITO_MODE: string = 'incognitoMode'
  /** User-Agent 模式（mobile / desktop） */
  static readonly UA_MODE: string = 'uaMode'
  /** 字体大小档位（system / small / medium / large） */
  static readonly FONT_SIZE: string = 'fontSize'
  /** 搜索历史 JSON 存储键 */
  static readonly SEARCH_HISTORY: string = 'searchHistory'
  /** 网站权限策略 JSON 存储键 */
  static readonly SITE_PERMISSIONS: string = 'sitePermissions'
  /** 最后活跃页签 JSON（id + incognito） */
  static readonly LAST_ACTIVE_TAB: string = 'lastActiveTab'
  /** origin 级别网站权限 JSON（key: `${origin}|${permId}`，value: policy） */
  static readonly ORIGIN_PERMISSIONS: string = 'originPermissions'
  /** 用户确认继续访问的 SSL 主机列表 JSON 数组 */
  static readonly SSL_ALLOWED_HOSTS: string = 'sslAllowedHosts'
  /** 启动时用户已拒绝/关闭通知授权提示（true 则冷启动不再自动弹） */
  static readonly NOTIFICATION_STARTUP_DECLINED: string = 'notificationStartupDeclined'
}

/** 持久化的最后活跃页签记录 */
export interface LastActiveTabRecord {
  /** 页签 ID */
  id: string
  /** 是否属于无痕分区 */
  incognito: boolean
}

/** 网站权限策略：只允许 / 禁止（已移除询问模式） */
export type SitePermissionPolicy = 'allow' | 'deny'

/** 网站权限项 ID */
export type SitePermissionId = 'location' | 'camera' | 'microphone' | 'notification'

/** 系统应用权限项（含相册等，不在网站策略内） */
export type AppSystemPermissionId = SitePermissionId | 'image_video'

/** 各网站权限项的策略映射 */
export interface SitePermissionsMap {
  /** 位置权限 */
  location: SitePermissionPolicy
  /** 相机权限 */
  camera: SitePermissionPolicy
  /** 麦克风权限 */
  microphone: SitePermissionPolicy
  /** 通知权限 */
  notification: SitePermissionPolicy
}

/** 网站权限默认策略：默认全部禁止（已移除询问模式） */
export const DEFAULT_SITE_PERMISSIONS: SitePermissionsMap = {
  location: 'deny',
  camera: 'deny',
  microphone: 'deny',
  notification: 'deny'
}

/** 浏览器设置实体，聚合所有用户偏好项 */
export interface BrowserSettings {
  /** 默认搜索引擎 ID */
  defaultSearchEngine: string
  /** 主题模式（light / dark） */
  themeMode: string
  /** 无图模式是否开启 */
  imageLessMode: boolean
  /** 夜间模式是否开启 */
  nightMode: boolean
  /** 无痕模式是否开启 */
  incognitoMode: boolean
  /** User-Agent 模式 */
  uaMode: string
  /** 字体大小档位 */
  fontSize: string
}

/** 部分更新设置时的可选字段集合 */
export interface SettingsUpdateInput {
  /** 默认搜索引擎 ID */
  defaultSearchEngine?: string
  /** 主题模式 */
  themeMode?: string
  /** 无图模式开关 */
  imageLessMode?: boolean
  /** 夜间模式开关 */
  nightMode?: boolean
  /** 无痕模式开关 */
  incognitoMode?: boolean
  /** User-Agent 模式 */
  uaMode?: string
  /** 字体大小档位 */
  fontSize?: string
}

/** 浏览器设置的出厂默认值 */
export const DEFAULT_BROWSER_SETTINGS: BrowserSettings = {
  defaultSearchEngine: 'baidu',
  themeMode: 'light',
  imageLessMode: false,
  nightMode: false,
  incognitoMode: false,
  uaMode: 'mobile',
  fontSize: 'system'
}
