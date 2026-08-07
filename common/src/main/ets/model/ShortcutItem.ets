/** 主页快捷方式实体，对应 shortcuts 表 */
export interface ShortcutItem {
  /** 快捷方式唯一标识 */
  id: string
  /** 显示标题 */
  title: string
  /** 跳转 URL 或 feature:// 协议地址 */
  url: string
  /** 图标 URL */
  iconUrl: string
  /** 首页网格排序序号 */
  sortOrder: number
  /** 是否为预置快捷方式（不可删除） */
  isPreset: boolean
  /** 创建时间戳（毫秒） */
  createdAt: number
  /** 最后更新时间戳（毫秒） */
  updatedAt: number
}

/** 快捷方式类型：功能入口、外部站点或添加按钮 */
export type ShortcutKind = 'feature' | 'site' | 'add'

/** 预置快捷方式目录项（非 DB 行，用于 UI 渲染 feature 型入口） */
export interface ShortcutCatalogEntry {
  /** 快捷方式唯一标识 */
  id: string
  /** 本地化显示标题 */
  title: string
  /** 快捷方式类型 */
  kind: ShortcutKind
  /** 功能型入口的图标 tile 名称 */
  tile?: string
  /** 站点型入口的图标文字 */
  iconText?: string
  /** 站点型入口的媒体图标 key（对应 app.media.ic_shortcut_*） */
  iconMedia?: string
  /** 站点型入口的跳转 URL */
  url?: string
}

/** 快捷方式目录元数据（不含运行时解析的 title） */
export interface ShortcutCatalogMeta {
  /** 快捷方式唯一标识 */
  id: string
  /** 快捷方式类型 */
  kind: ShortcutKind
  /** 功能型入口的图标 tile 名称 */
  tile?: string
  /** 站点型入口的图标文字 */
  iconText?: string
  /** 站点型入口的媒体图标 key（对应 app.media.ic_shortcut_*） */
  iconMedia?: string
  /** 站点型入口的跳转 URL */
  url?: string
}

/** 创建快捷方式时的输入参数 */
export interface CreateShortcutItemInput {
  /** 快捷方式唯一标识 */
  id: string
  /** 显示标题 */
  title: string
  /** 跳转 URL */
  url: string
  /** 图标 URL */
  iconUrl?: string
  /** 首页网格排序序号 */
  sortOrder?: number
  /** 是否为预置快捷方式 */
  isPreset?: boolean
  /** 创建时间戳（毫秒） */
  createdAt?: number
  /** 最后更新时间戳（毫秒） */
  updatedAt?: number
}

/** 根据输入参数创建快捷方式实体，并填充默认值 */
export function createShortcutItem(input: CreateShortcutItemInput): ShortcutItem {
  const now = Date.now()
  return {
    iconUrl: input.iconUrl ?? '',
    sortOrder: input.sortOrder ?? 0,
    isPreset: input.isPreset ?? false,
    createdAt: input.createdAt ?? now,
    updatedAt: input.updatedAt ?? now,
    id: input.id,
    title: input.title,
    url: input.url
  }
}
