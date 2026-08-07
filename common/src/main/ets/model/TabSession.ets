import { BrowserStrings } from '../utils/BrowserStrings'

/** 标签页会话实体，对应 tab_sessions 表 */
export interface TabSession {
  /** 标签页唯一标识 */
  id: string
  /** 标签页标题 */
  title: string
  /** 当前页面 URL */
  url: string
  /** 是否为无痕标签页 */
  isIncognito: boolean
  /** Web 组件状态快照（序列化字符串） */
  webState: string
  /** 缩略图本地路径 */
  thumbnailPath: string
  /** 排序序号，越小越靠前 */
  sortOrder: number
  /** 是否为当前激活标签 */
  isActive: boolean
  /** 创建时间戳（毫秒） */
  createdAt: number
  /** 最后更新时间戳（毫秒） */
  updatedAt: number
  /** UI 扩展：是否为主页占位标签 */
  isHome?: boolean
  /** UI 扩展：是否隐藏描述文字 */
  hideDesc?: boolean
}

/** 创建标签页会话时的输入参数 */
export interface CreateTabSessionInput {
  /** 标签页唯一标识 */
  id: string
  /** 标签页标题，缺省为「新标签页」 */
  title?: string
  /** 当前页面 URL */
  url?: string
  /** 是否为无痕标签页 */
  isIncognito?: boolean
  /** Web 组件状态快照 */
  webState?: string
  /** 缩略图本地路径 */
  thumbnailPath?: string
  /** 排序序号 */
  sortOrder?: number
  /** 是否为当前激活标签 */
  isActive?: boolean
  /** 创建时间戳（毫秒） */
  createdAt?: number
  /** 最后更新时间戳（毫秒） */
  updatedAt?: number
  /** 是否为主页占位标签 */
  isHome?: boolean
  /** 是否隐藏描述文字 */
  hideDesc?: boolean
}

/** 根据输入参数创建标签页会话实体，并填充默认值 */
export function createTabSession(input: CreateTabSessionInput): TabSession {
  const now = Date.now()
  return {
    title: input.title ?? BrowserStrings.newTab(),
    url: input.url ?? '',
    isIncognito: input.isIncognito ?? false,
    webState: input.webState ?? '',
    thumbnailPath: input.thumbnailPath ?? '',
    sortOrder: input.sortOrder ?? 0,
    isActive: input.isActive ?? false,
    createdAt: input.createdAt ?? now,
    updatedAt: input.updatedAt ?? now,
    isHome: input.isHome,
    hideDesc: input.hideDesc,
    id: input.id
  }
}
