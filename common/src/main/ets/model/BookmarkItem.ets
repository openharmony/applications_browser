/** 书签/文件夹实体，对应 bookmarks 表 */
export interface BookmarkItem {
  /** 书签或文件夹唯一标识 */
  id: string
  /** 父文件夹 ID，根目录为空字符串 */
  parentId: string
  /** 显示标题 */
  title: string
  /** 书签 URL，文件夹为空 */
  url: string
  /** 站点图标 URL */
  iconUrl: string
  /** 同级排序序号 */
  sortOrder: number
  /** 是否为文件夹节点 */
  isFolder: boolean
  /** 创建时间戳（毫秒） */
  createdAt: number
  /** 最后更新时间戳（毫秒） */
  updatedAt: number
}

/** 创建书签或文件夹时的输入参数 */
export interface CreateBookmarkItemInput {
  /** 书签或文件夹唯一标识 */
  id: string
  /** 显示标题 */
  title: string
  /** 父文件夹 ID，缺省为根目录 */
  parentId?: string
  /** 书签 URL */
  url?: string
  /** 站点图标 URL */
  iconUrl?: string
  /** 同级排序序号 */
  sortOrder?: number
  /** 是否为文件夹节点 */
  isFolder?: boolean
  /** 创建时间戳（毫秒） */
  createdAt?: number
  /** 最后更新时间戳（毫秒） */
  updatedAt?: number
}

/** 更新书签时的可选字段集合 */
export interface BookmarkUpdateInput {
  /** 显示标题 */
  title?: string
  /** 书签 URL */
  url?: string
  /** 父文件夹 ID */
  parentId?: string
  /** 站点图标 URL */
  iconUrl?: string
  /** 同级排序序号 */
  sortOrder?: number
  /** 是否为文件夹节点 */
  isFolder?: boolean
}

/** 书签树根节点 ID（空字符串表示根目录） */
export const BOOKMARK_ROOT_ID: string = ''

/** 根据输入参数创建书签实体，并填充默认值 */
export function createBookmarkItem(input: CreateBookmarkItemInput): BookmarkItem {
  const now = Date.now()
  return {
    parentId: input.parentId ?? BOOKMARK_ROOT_ID,
    url: input.url ?? '',
    iconUrl: input.iconUrl ?? '',
    sortOrder: input.sortOrder ?? 0,
    isFolder: input.isFolder ?? false,
    createdAt: input.createdAt ?? now,
    updatedAt: input.updatedAt ?? now,
    id: input.id,
    title: input.title
  }
}
