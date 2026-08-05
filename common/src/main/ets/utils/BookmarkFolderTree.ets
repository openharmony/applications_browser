import { BookmarkItem, BOOKMARK_ROOT_ID } from '../model/BookmarkItem'
import { BrowserStrings } from './BrowserStrings'

/** 文件夹选择行（仅文件夹树） */
export interface BookmarkFolderPickRow {
  id: string
  title: string
  depth: number
  /** 是否含子文件夹（用于展开箭头） */
  hasChildren: boolean
}

/** 书签内容树行（文件夹 + 书签混排） */
export interface BookmarkTreeRow {
  id: string
  title: string
  url: string
  depth: number
  isFolder: boolean
  /** 文件夹是否含子项（书签或子文件夹） */
  hasChildren: boolean
}

/** 书签多级文件夹：DFS 展平 + 阶梯缩进 / 分割线 / 展开 */
export class BookmarkFolderTree {
  /** 相对根的每层额外左缩进（vp），约等于图标槽宽 */
  static readonly DEPTH_INDENT: number = 24
  /** 根层基础左内边距（vp） */
  static readonly BASE_PADDING: number = 16
  /** 文件夹图标宽度（vp） */
  static readonly ICON_SIZE: number = 24
  /** 书签/历史站点图标盒宽（vp，HistorySiteIcon 默认） */
  static readonly SITE_ICON_SIZE: number = 32
  /** 展开箭头宽度（vp） */
  static readonly CHEVRON_SIZE: number = 20
  /** 图标与标题间距（vp） */
  static readonly ICON_GAP: number = 10
  /** 批量编辑拖动手柄占位宽（vp，含右侧间距） */
  static readonly BATCH_HANDLE_SLOT: number = 34

  /** 行内容左内边距（图标起点） */
  static indentLeft(depth: number, base: number = BookmarkFolderTree.BASE_PADDING): number {
    const d = depth < 0 ? 0 : depth
    return base + d * BookmarkFolderTree.DEPTH_INDENT
  }

  /**
   * 分割线起点：对齐当前行标题文字左缘（跳过缩进 + 图标 + 间距）
   * 与参考图一致，分割线随层级阶梯缩短
   */
  static dividerStart(depth: number, base: number = BookmarkFolderTree.BASE_PADDING): number {
    return BookmarkFolderTree.indentLeft(depth, base) +
      BookmarkFolderTree.ICON_SIZE + BookmarkFolderTree.ICON_GAP
  }

  /** 站点图标行（书签条目）分割线起点 */
  static dividerStartSite(base: number = BookmarkFolderTree.BASE_PADDING): number {
    return base + BookmarkFolderTree.SITE_ICON_SIZE + BookmarkFolderTree.ICON_GAP
  }

  /** 下载列表图标行分割线起点（40 图标 + 8 间距） */
  static dividerStartDownload(base: number = BookmarkFolderTree.BASE_PADDING): number {
    return base + 40 + 8
  }

  /** 通用：左内边距 + 前置图标宽 + 间距 → 文字左缘 */
  static dividerStartLeading(
    iconSize: number,
    gap: number = BookmarkFolderTree.ICON_GAP,
    base: number = BookmarkFolderTree.BASE_PADDING
  ): number {
    return base + iconSize + gap
  }

  /** 批量态文件夹行分割线起点（含拖动手柄） */
  static dividerStartBatchFolder(base: number = BookmarkFolderTree.BASE_PADDING): number {
    return base + BookmarkFolderTree.BATCH_HANDLE_SLOT +
      BookmarkFolderTree.ICON_SIZE + BookmarkFolderTree.ICON_GAP
  }

  /** 批量态书签行分割线起点（含拖动手柄） */
  static dividerStartBatchSite(base: number = BookmarkFolderTree.BASE_PADDING): number {
    return base + BookmarkFolderTree.BATCH_HANDLE_SLOT +
      BookmarkFolderTree.SITE_ICON_SIZE + BookmarkFolderTree.ICON_GAP
  }

  /** 是否展开：未在收起列表中则视为展开 */
  static isExpanded(folderId: string, collapsedIds: string[]): boolean {
    return collapsedIds.indexOf(folderId) < 0
  }

  /** 切换文件夹展开/收起 */
  static toggleCollapsed(folderId: string, collapsedIds: string[]): string[] {
    const idx = collapsedIds.indexOf(folderId)
    if (idx >= 0) {
      const next = collapsedIds.slice()
      next.splice(idx, 1)
      return next
    }
    return [...collapsedIds, folderId]
  }

  /**
   * 构建文件夹选择列表（含根目录 depth=0）
   * @param collapsedIds 收起的文件夹 id；空数组表示全部展开
   */
  static folderPickRows(
    bookmarks: BookmarkItem[],
    includeRoot: boolean = true,
    rootTitle?: string,
    collapsedIds: string[] = []
  ): BookmarkFolderPickRow[] {
    const rows: BookmarkFolderPickRow[] = []
    if (includeRoot) {
      const rootHas = BookmarkFolderTree.childFolders(bookmarks, BOOKMARK_ROOT_ID).length > 0
      rows.push({
        id: BOOKMARK_ROOT_ID,
        title: rootTitle ?? BrowserStrings.bookmarkRoot(),
        depth: 0,
        hasChildren: rootHas
      })
      if (BookmarkFolderTree.isExpanded(BOOKMARK_ROOT_ID, collapsedIds)) {
        BookmarkFolderTree.appendFolderChildren(bookmarks, BOOKMARK_ROOT_ID, 0, rows, collapsedIds)
      }
    } else {
      BookmarkFolderTree.appendFolderChildren(bookmarks, BOOKMARK_ROOT_ID, -1, rows, collapsedIds)
    }
    return rows
  }

  private static appendFolderChildren(
    bookmarks: BookmarkItem[],
    parentId: string,
    depth: number,
    rows: BookmarkFolderPickRow[],
    collapsedIds: string[]
  ): void {
    const children = BookmarkFolderTree.childFolders(bookmarks, parentId)
    for (const folder of children) {
      const hasChildren = BookmarkFolderTree.childFolders(bookmarks, folder.id).length > 0
      rows.push({
        id: folder.id,
        title: folder.title,
        depth: depth + 1,
        hasChildren: hasChildren
      })
      if (hasChildren && BookmarkFolderTree.isExpanded(folder.id, collapsedIds)) {
        BookmarkFolderTree.appendFolderChildren(bookmarks, folder.id, depth + 1, rows, collapsedIds)
      }
    }
  }

  /**
   * 构建内容树（文件夹与书签混排）
   * @param collapsedIds 收起的文件夹 id
   */
  static contentTreeRows(bookmarks: BookmarkItem[], collapsedIds: string[] = []): BookmarkTreeRow[] {
    const rows: BookmarkTreeRow[] = []
    BookmarkFolderTree.appendContentChildren(bookmarks, BOOKMARK_ROOT_ID, 0, rows, collapsedIds)
    return rows
  }

  private static appendContentChildren(
    bookmarks: BookmarkItem[],
    parentId: string,
    depth: number,
    rows: BookmarkTreeRow[],
    collapsedIds: string[]
  ): void {
    const children = BookmarkFolderTree.childrenOf(bookmarks, parentId)
    for (const item of children) {
      const hasChildren = item.isFolder ?
        BookmarkFolderTree.childrenOf(bookmarks, item.id).length > 0 : false
      rows.push({
        id: item.id,
        title: item.title,
        url: item.url,
        depth: depth,
        isFolder: item.isFolder,
        hasChildren: hasChildren
      })
      if (item.isFolder && hasChildren && BookmarkFolderTree.isExpanded(item.id, collapsedIds)) {
        BookmarkFolderTree.appendContentChildren(bookmarks, item.id, depth + 1, rows, collapsedIds)
      }
    }
  }

  static childFoldersOf(bookmarks: BookmarkItem[], parentId: string): BookmarkItem[] {
    return BookmarkFolderTree.childrenOf(bookmarks, parentId).filter((b) => b.isFolder)
  }

  private static childFolders(bookmarks: BookmarkItem[], parentId: string): BookmarkItem[] {
    return BookmarkFolderTree.childFoldersOf(bookmarks, parentId)
  }

  private static childrenOf(bookmarks: BookmarkItem[], parentId: string): BookmarkItem[] {
    const pid = parentId || BOOKMARK_ROOT_ID
    return bookmarks
      .filter((b) => (b.parentId || BOOKMARK_ROOT_ID) === pid)
      .sort((a, b) => a.sortOrder - b.sortOrder)
  }

  /** drill-down：当前层仅含直接子文件夹的选择行 */
  static flatFolderPickRows(
    bookmarks: BookmarkItem[],
    parentId: string = BOOKMARK_ROOT_ID,
    rootTitle?: string
  ): BookmarkFolderPickRow[] {
    const pid = parentId || BOOKMARK_ROOT_ID
    const rows: BookmarkFolderPickRow[] = []
    if (pid === BOOKMARK_ROOT_ID) {
      const rootHas = BookmarkFolderTree.childFolders(bookmarks, BOOKMARK_ROOT_ID).length > 0
      rows.push({
        id: BOOKMARK_ROOT_ID,
        title: rootTitle ?? BrowserStrings.bookmarkRoot(),
        depth: 0,
        hasChildren: rootHas
      })
    }
    for (const folder of BookmarkFolderTree.childFolders(bookmarks, pid)) {
      rows.push({
        id: folder.id,
        title: folder.title,
        depth: 0,
        hasChildren: BookmarkFolderTree.childFolders(bookmarks, folder.id).length > 0
      })
    }
    return rows
  }

  /** drill-down：当前层文件夹 + 书签混排（folders 在前） */
  static flatContentRows(bookmarks: BookmarkItem[], parentId: string = BOOKMARK_ROOT_ID): BookmarkTreeRow[] {
    const rows: BookmarkTreeRow[] = []
    for (const item of BookmarkFolderTree.childrenOf(bookmarks, parentId)) {
      const hasChildren = item.isFolder ?
        BookmarkFolderTree.childrenOf(bookmarks, item.id).length > 0 : false
      rows.push({
        id: item.id,
        title: item.title,
        url: item.url,
        depth: 0,
        isFolder: item.isFolder,
        hasChildren: hasChildren
      })
    }
    return rows
  }
}
