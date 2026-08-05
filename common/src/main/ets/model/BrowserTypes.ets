import { BookmarkItem } from './BookmarkItem'
import { DownloadTask } from './DownloadTask'
import { HistoryEntry } from './HistoryEntry'
import { TabSession } from './TabSession'

/** 功能面板类型：书签、历史、下载、设置工具箱、关于 */
export type FeaturePanelType = 'bookmarks' | 'history' | 'downloads' | 'toolbox' | 'about' | ''

/** 按日期分组后的列表结构 */
export interface DateGroup<T> {
  /** 分组标题（如「今天」「6月9日」） */
  label: string
  /** 该分组下的条目列表 */
  items: T[]
}

/** 分享弹窗展示参数 */
export interface ShareSheetParams {
  /** 分享内容标题 */
  title: string
  /** 分享链接 URL */
  url: string
  /** 文件大小描述文本 */
  size: string
  /** 是否显示预览图 */
  previewImage: boolean
}

/** 打开分享弹窗时的可选参数 */
export interface OpenShareOptions {
  /** 分享内容标题 */
  title?: string
  /** 分享链接 URL */
  url?: string
  /** 文件大小描述文本 */
  size?: string
  /** 是否显示预览图 */
  previewImage?: boolean
}

/** 下载确认弹窗的请求参数 */
export interface DownloadRequest {
  /** 待下载文件名 */
  fileName: string
  /** 文件大小展示文本 */
  fileSizeText: string
  /** 文件大小（字节，已知时优先用于空间校验） */
  fileSizeBytes?: number
  /** MIME 类型 */
  mimeType?: string
  /** 下载来源 URL */
  sourceUrl?: string
}

/** 新建标签页时的可选参数 */
export interface AddTabOptions {
  /** 初始 URL */
  url?: string
  /** 初始标题 */
  title?: string
  /** 是否创建为无痕标签 */
  incognito?: boolean
  /** 是否为主页占位标签 */
  isHome?: boolean
}

/** 打开浏览页时的路由选项 */
export interface OpenBrowseOptions {
  /** 是否跳过导航栈记录 */
  skipNav?: boolean
  /** 是否在新标签中打开 */
  newTab?: boolean
  /** 从首页打开时优先使用主页占位标签，不新建标签 */
  preferHomeTab?: boolean
  /** 页面标题 */
  title?: string
  /** 关联的标签页 ID */
  tabId?: string
}

/** 浏览页路由参数 */
export interface BrowseRouteParams {
  /** 目标 URL */
  url?: string
  /** 是否跳过导航栈（字符串形式，来自 router） */
  skipNav?: string
  /** 关联的标签页 ID（字符串形式，来自 router） */
  tabId?: string
}

/** 浏览页同步到标签页的字段补丁 */
export interface BrowseTabPatch {
  /** 当前 URL */
  url?: string
  /** 页面标题 */
  title?: string
  /** 缩略图沙箱路径 */
  thumbnailPath?: string
  /** 是否为主页占位标签 */
  isHome?: boolean
}

/** 标签管理页路由参数 */
export interface TabsRouteParams {
  /** 初始分区：'1' 无痕，'0' 普通 */
  incognito?: string
}

/** 快捷方式拖拽移动方向 */
export type ShortcutMoveDirection = 'left' | 'right' | 'up' | 'down'

/** 书签数量上限 */
export const BOOKMARK_LIMIT: number = 100

/** 标签页数量实际上限（普通 / 无痕各自独立计数） */
export const TAB_LIMIT: number = 100
/** 标签页数量 UI 展示上限（徽章数字封顶，含主页） */
export const TAB_LIMIT_DISPLAY: number = 99

/** AppStorage 键名（UI 响应式绑定） */
export class AppStorageKeys {
  /** 标签页列表 */
  static readonly TABS: string = 'browser_tabs'
  /** 持久化普通标签（内存 + DB 同步） */
  static readonly TABS_PERSISTED: string = 'browser_tabs_persisted'
  /** 标签页列表版本号（触发 UI 刷新） */
  static readonly TABS_REV: string = 'browser_tabs_rev'
  /** 书签列表 */
  static readonly BOOKMARKS: string = 'browser_bookmarks'
  /** 书签列表版本号（触发 UI 刷新） */
  static readonly BOOKMARKS_REV: string = 'browser_bookmarks_rev'
  /** 浏览历史列表 */
  static readonly HISTORY: string = 'browser_history'
  /** 浏览历史列表版本号（触发 UI 刷新） */
  static readonly HISTORY_REV: string = 'browser_history_rev'
  /** 下载任务列表 */
  static readonly DOWNLOADS: string = 'browser_downloads'
  /** 首页快捷方式 ID 顺序列表 */
  static readonly SHORTCUT_IDS: string = 'browser_shortcut_ids'
  /** 首页快捷方式完整列表（含自定义/书签/历史来源） */
  static readonly SHORTCUTS: string = 'browser_shortcuts'
  /** 快捷方式列表版本号（触发 UI 刷新） */
  static readonly SHORTCUTS_REV: string = 'browser_shortcuts_rev'
  /** 首页快捷方式动态数量上限（由 HomeView 按视口写入） */
  static readonly SHORTCUT_MAX_COUNT: string = 'browser_shortcut_max_count'
  /** 搜索历史关键词列表 */
  static readonly SEARCH_HISTORY: string = 'browser_search_history'
  /** 当前搜索引擎 ID */
  static readonly SEARCH_ENGINE: string = 'browser_search_engine'
  /** 主题模式（light / dark） */
  static readonly THEME: string = 'browser_theme'
  /** 主题偏好（system / light / dark） */
  static readonly THEME_PREFERENCE: string = 'browser_theme_preference'
  /** 主题变更序号（驱动底部导航等强制刷新） */
  static readonly THEME_REV: string = 'browser_theme_rev'
  /** 深色模式选择弹层是否可见（MainPage 层绘制，避免底栏盖住遮罩） */
  static readonly DARK_MODE_PICKER_VISIBLE: string = 'browser_dark_mode_picker_visible'
  /** 无痕模式开关 */
  static readonly INCOGNITO: string = 'browser_incognito'
  /** 最近一次浏览页的无痕上下文（「我的」页同步用） */
  static readonly BROWSE_INCOGNITO: string = 'browser_browse_incognito'
  /** User-Agent 模式 */
  static readonly UA_MODE: string = 'browser_ua_mode'
  /** 字体大小档位 */
  static readonly FONT_SIZE: string = 'browser_font_size'
  /** 系统字体大小比例（Configuration.fontSizeScale，默认 1） */
  static readonly SYSTEM_FONT_SIZE_SCALE: string = 'browser_system_font_size_scale'
  /** 系统字体粗细比例（Configuration.fontWeightScale，默认 1） */
  static readonly SYSTEM_FONT_WEIGHT_SCALE: string = 'browser_system_font_weight_scale'
  /** 字体相关 UI 刷新序号（系统/设置变更时递增） */
  static readonly FONT_UI_REV: string = 'browser_font_ui_rev'
  /** 当前 UI 有效字号倍率（小/中/大固定档位或跟随系统比例） */
  static readonly FONT_UI_SCALE: string = 'browser_font_ui_scale'
  /**
   * Ability 回前台后延迟 tick：多任务切回时页面不一定走 onPageShow，
   * Web 也可能尚未 OnWindowShow，用于在窗口可见后再强制 textZoom。
   */
  static readonly FONT_FOREGROUND_TICK: string = 'browser_font_foreground_tick'
  /** 无图模式开关 */
  static readonly IMAGE_LESS_MODE: string = 'browser_image_less'
  /** 夜间浏览模式开关（Web 深色滤镜，与主题独立） */
  static readonly NIGHT_MODE: string = 'browser_night_mode'
  /** 当前打开的功能面板类型 */
  static readonly FEATURE_PANEL: string = 'browser_feature_panel'
  /** 网站权限策略映射 */
  static readonly SITE_PERMISSIONS: string = 'browser_site_permissions'
  /** Toast 提示消息 */
  static readonly TOAST: string = 'browser_toast'
  /** 浏览页内导航栈 URL 列表 */
  static readonly NAV_STACK: string = 'browser_nav_stack'
  /** 浏览页内导航栈当前索引 */
  static readonly NAV_IDX: string = 'browser_nav_idx'
  /** 当前活跃标签页 ID */
  static readonly ACTIVE_TAB: string = 'browser_active_tab'
  /** 进入页签管理页时快照的活跃页签（用于返回） */
  static readonly TABS_RETURN_TAB_ID: string = 'browser_tabs_return_tab_id'
  /** 分享弹窗是否可见 */
  static readonly SHARE_VISIBLE: string = 'browser_share_visible'
  /** 分享内容标题 */
  static readonly SHARE_TITLE: string = 'browser_share_title'
  /** 分享链接 URL */
  static readonly SHARE_URL: string = 'browser_share_url'
  /** 分享文件大小描述 */
  static readonly SHARE_SIZE: string = 'browser_share_size'
  /** 分享是否含预览图 */
  static readonly SHARE_IMAGE: string = 'browser_share_image'
  /** 分享面板各入口可用性（探测结果） */
  static readonly SHARE_APPS: string = 'browser_share_apps'
  /** 网页图片全屏预览是否可见 */
  static readonly IMAGE_PREVIEW_VISIBLE: string = 'browser_image_preview_visible'
  /** 网页图片全屏预览 URL */
  static readonly IMAGE_PREVIEW_URL: string = 'browser_image_preview_url'
  /** 关闭预览后拦截页面返回的时间戳（ms） */
  static readonly IMAGE_PREVIEW_BACK_BLOCK_UNTIL: string = 'browser_image_preview_back_block_until'
  /** 下载确认弹窗是否可见 */
  static readonly DL_DIALOG: string = 'browser_dl_dialog'
  /** 待下载文件名 */
  static readonly DL_NAME: string = 'browser_dl_name'
  /** 待下载文件大小文本 */
  static readonly DL_SIZE: string = 'browser_dl_size'
  /** 待下载文件大小（字节） */
  static readonly DL_SIZE_BYTES: string = 'browser_dl_size_bytes'
  /** 待下载文件 MIME 类型 */
  static readonly DL_TYPE: string = 'browser_dl_type'
  /** 待下载文件来源 URL */
  static readonly DL_SOURCE: string = 'browser_dl_source'
  /** 下载列表版本号（触发 UI 刷新） */
  static readonly DOWNLOADS_REV: string = 'browser_downloads_rev'
  /** 下载进度静默刷新序号（仅进度条，不重建列表行/缩略图） */
  static readonly DOWNLOAD_PROGRESS_REV: string = 'browser_download_progress_rev'
  /** 「我的」页统计区 UI 刷新序号（关闭书签/历史/下载面板时递增） */
  static readonly LIST_STATS_UI_REV: string = 'browser_list_stats_ui_rev'
  /** 快捷方式长按菜单层动作（dismiss / edit / remove） */
  static readonly SHORTCUT_MENU_ACTION: string = 'browser_shortcut_menu_action'
  /** 主窗口宽度（vp，随旋转更新） */
  static readonly WINDOW_WIDTH: string = 'browser_window_width'
  /** 主窗口高度（vp，随旋转更新） */
  static readonly WINDOW_HEIGHT: string = 'browser_window_height'
  /** 是否横屏布局 */
  static readonly WINDOW_LANDSCAPE: string = 'browser_window_landscape'
  /** 窗口尺寸/方向变更版本号（触发 UI 重算） */
  static readonly WINDOW_REV: string = 'browser_window_rev'
  /** 状态栏避让高度（vp，沉浸式布局下子页顶栏使用） */
  static readonly SAFE_AREA_TOP: string = 'browser_safe_area_top'
  /** 系统导航条/手势条避让高度（vp，底部导航栏上移使用） */
  static readonly SAFE_AREA_BOTTOM: string = 'browser_safe_area_bottom'
}

/** 快捷方式抬起/菜单 overlay 状态（MainPage 层渲染，HomeView 同步） */
@Observed
export class ShortcutMenuOverlayState {
  /** 跟手图标是否可见 */
  liftActive: boolean = false
  /** 菜单与模糊背板是否可见 */
  menuVisible: boolean = false
  /** 手指仍按在 Grid 上（背板不拦截触摸） */
  fingerOnGrid: boolean = false
  /** 当前快捷方式 id */
  featureId: string = ''
  /** 图标锚点 X（相对 MainPage Stack） */
  iconAnchorLeft: number = 0
  /** 图标锚点 Y（相对 MainPage Stack） */
  iconAnchorTop: number = 0
  /** 跟手偏移 X */
  offsetX: number = 0
  /** 跟手偏移 Y */
  offsetY: number = 0
  /** 菜单簇左上角 X */
  menuPosX: number = 0
  /** 菜单簇左上角 Y */
  menuPosY: number = 0
  /** 是否深色主题 */
  darkMode: boolean = false
  /** 菜单打开后冻结图标坐标（不再随 sync 更新） */
  positionFrozen: boolean = false
}

/** 深拷贝标签页会话对象 */
export function cloneTab(t: TabSession): TabSession {
  return {
    id: t.id, title: t.title, url: t.url, isIncognito: t.isIncognito,
    webState: t.webState, thumbnailPath: t.thumbnailPath, sortOrder: t.sortOrder,
    isActive: t.isActive, createdAt: t.createdAt, updatedAt: t.updatedAt,
    isHome: t.isHome, hideDesc: t.hideDesc
  }
}

/** 深拷贝书签对象 */
export function cloneBookmark(b: BookmarkItem): BookmarkItem {
  return {
    id: b.id, parentId: b.parentId, title: b.title, url: b.url, iconUrl: b.iconUrl,
    sortOrder: b.sortOrder, isFolder: b.isFolder, createdAt: b.createdAt, updatedAt: b.updatedAt
  }
}

/** 深拷贝历史记录对象 */
export function cloneHistory(h: HistoryEntry): HistoryEntry {
  return {
    id: h.id, url: h.url, title: h.title, visitedAt: h.visitedAt,
    iconUrl: h.iconUrl, visitCount: h.visitCount
  }
}

/** 深拷贝快捷方式对象 */
export function cloneShortcut(s: import('./ShortcutItem').ShortcutItem): import('./ShortcutItem').ShortcutItem {
  return {
    id: s.id, title: s.title, url: s.url, iconUrl: s.iconUrl,
    sortOrder: s.sortOrder, isPreset: s.isPreset, createdAt: s.createdAt, updatedAt: s.updatedAt
  }
}

/** 深拷贝下载任务对象 */
export function cloneDownload(d: DownloadTask): DownloadTask {
  return {
    id: d.id, fileName: d.fileName, sourceUrl: d.sourceUrl, localPath: d.localPath,
    galleryUri: d.galleryUri,
    status: d.status, progress: d.progress, fileSize: d.fileSize, mimeType: d.mimeType,
    errorMessage: d.errorMessage, createdAt: d.createdAt, updatedAt: d.updatedAt
  }
}
