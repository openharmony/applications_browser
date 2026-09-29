// BookmarksViewModel：BookmarksPage 的数据与操作封装。

import { BookmarkDataProvider, BookmarkImportResult, BookmarkItem, BookmarkManager, BookmarkTreeNode } from '../../core/bookmarkManager';
import { BookmarkExportResult, BookmarkExportService } from '../../core/bookmarkExportService';
import { BookmarkImportService } from '../../core/bookmarkImportService';

export interface BookmarksPageListItem {
  id: string;
  type: 'folder' | 'bookmark';
  title: string;
  depth: number;
  childCount: number;
  url?: string;
  faviconUrl?: string;
  parentId: string;
  sortOrder: number;
  folderPath?: string[];
}

export interface BookmarkFolderOption {
  id: string;
  title: string;
  depth: number;
  childCount: number;
  isCurrent: boolean;
}

export interface BookmarksPageViewState {
  bookmarks: BookmarkItem[];
  items: BookmarksPageListItem[];
  keyword: string;
  parentId: string;
  parentTitle: string;
  isRootFolder: boolean;
  totalCount: number;
  folderCount: number;
  isLoading: boolean;
  errorMessage: string;
}

export interface BookmarkDataSource extends BookmarkDataProvider {
}

export class BookmarksViewModel {
  private readonly bookmarkManager: BookmarkDataSource;
  private readonly exportService: BookmarkExportService;
  private readonly importService: BookmarkImportService;
  private keyword: string = '';
  private parentId: string = BookmarkManager.ROOT_FOLDER_ID;
  private bookmarks: BookmarkItem[] = [];
  private totalCount: number = 0;
  private folderCount: number = 0;
  private isLoading: boolean = false;
  private errorMessage: string = '';
  private loadRequestId: number = 0;
  private readonly listenerMap: Map<(state: BookmarksPageViewState) => void, (bookmarks: BookmarkItem[]) => void> = new Map();

  constructor(
    bookmarkManager?: BookmarkDataSource,
    importService?: BookmarkImportService,
    exportService?: BookmarkExportService,
  ) {
    this.bookmarkManager = bookmarkManager ?? BookmarkManager.getInstance();
    this.importService = importService ?? new BookmarkImportService();
    this.exportService = exportService ?? new BookmarkExportService();
  }

  getInitialState(): BookmarksPageViewState {
    return this.getViewState();
  }

  getViewState(): BookmarksPageViewState {
    return {
      bookmarks: this.bookmarks,
      items: this.bookmarksToListItems(this.bookmarks),
      keyword: this.keyword,
      parentId: this.parentId,
      parentTitle: this.getParentTitle(),
      isRootFolder: this.parentId === BookmarkManager.ROOT_FOLDER_ID,
      totalCount: this.totalCount,
      folderCount: this.folderCount,
      isLoading: this.isLoading,
      errorMessage: this.errorMessage,
    };
  }

  async load(): Promise<BookmarksPageViewState> {
    const requestId = ++this.loadRequestId;
    const requestedKeyword = this.keyword;
    const requestedParentId = this.parentId;
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const allBookmarks = this.bookmarkManager.listBookmarks();
      const keyword = requestedKeyword.trim();
      const totalCount = allBookmarks.length;
      const folderCount = this.bookmarkManager.getFolderCount();
      const bookmarks = keyword.length > 0 ?
        await this.bookmarkManager.searchBookmarks(keyword, 200) :
        this.bookmarkManager.listBookmarksByParent(requestedParentId);
      if (requestId !== this.loadRequestId) {
        return this.getViewState();
      }
      this.totalCount = totalCount;
      this.folderCount = folderCount;
      this.bookmarks = bookmarks;
    } catch (error) {
      if (requestId !== this.loadRequestId) {
        return this.getViewState();
      }
      this.bookmarks = [];
      this.totalCount = 0;
      this.folderCount = 0;
      this.errorMessage = this.getErrorMessage(error);
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoading = false;
      }
    }

    return this.getViewState();
  }

  async setKeyword(keyword: string): Promise<BookmarksPageViewState> {
    this.keyword = keyword;
    return this.load();
  }

  async openFolder(folderId: string): Promise<BookmarksPageViewState> {
    const folder = this.bookmarkManager.getBookmarkById(folderId);
    if (!folder || !folder.isFolder) {
      return this.getViewState();
    }

    this.parentId = folder.id;
    this.keyword = '';
    return this.load();
  }

  async goRoot(): Promise<BookmarksPageViewState> {
    this.parentId = BookmarkManager.ROOT_FOLDER_ID;
    this.keyword = '';
    return this.load();
  }

  async goParent(): Promise<BookmarksPageViewState> {
    if (this.parentId === BookmarkManager.ROOT_FOLDER_ID) {
      return this.getViewState();
    }
    const currentFolder = this.bookmarkManager.getBookmarkById(this.parentId);
    this.parentId = currentFolder && currentFolder.parentId ?
      currentFolder.parentId : BookmarkManager.ROOT_FOLDER_ID;
    this.keyword = '';
    return this.load();
  }

  async createFolder(title: string): Promise<BookmarksPageViewState> {
    const folder = this.bookmarkManager.createFolder(title, this.parentId);
    if (!folder) {
      this.errorMessage = '请输入文件夹名称';
      return this.getViewState();
    }
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`文件夹创建失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  async remove(url: string): Promise<BookmarksPageViewState> {
    this.bookmarkManager.removeBookmark(url);
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`书签删除失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  async removeItem(bookmark: BookmarkItem): Promise<BookmarksPageViewState> {
    if (bookmark.isFolder) {
      this.bookmarkManager.removeBookmarkById(bookmark.id);
    } else {
      this.bookmarkManager.removeBookmark(bookmark.url);
    }
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`书签删除失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  async removeNode(nodeId: string): Promise<BookmarksPageViewState> {
    this.bookmarkManager.removeNode(nodeId);
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`书签项目删除失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  async moveNode(nodeId: string, parentId: string = BookmarkManager.ROOT_FOLDER_ID,
    sortOrder?: number): Promise<BookmarksPageViewState> {
    const moved = this.bookmarkManager.moveNode(nodeId, parentId, sortOrder);
    if (!moved) {
      this.errorMessage = '无法移动书签项目：目标文件夹无效或会形成循环';
      return this.getViewState();
    }
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`书签移动失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  async renameNode(nodeId: string, title: string): Promise<BookmarksPageViewState> {
    const renamed = this.bookmarkManager.renameNode(nodeId, title);
    if (!renamed) {
      this.errorMessage = '重命名失败：名称为空或与同级文件夹重复';
      return this.getViewState();
    }
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`重命名失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  async updateBookmark(nodeId: string, title: string, url: string): Promise<BookmarksPageViewState> {
    const updated = this.bookmarkManager.updateBookmark(nodeId, title, url);
    if (!updated) {
      this.errorMessage = '保存失败：名称不能为空、网址无效或网址已存在';
      return this.getViewState();
    }
    try {
      await this.bookmarkManager.flushPersistence();
    } catch (error) {
      this.setMutationError(`保存失败：${this.getErrorMessage(error)}`);
      return this.getViewState();
    }
    return this.load();
  }

  getFolderOptions(excludeNodeId: string = ''): BookmarkFolderOption[] {
    const options: BookmarkFolderOption[] = [{
      id: BookmarkManager.ROOT_FOLDER_ID,
      title: '全部书签',
      depth: 0,
      childCount: this.bookmarkManager.listBookmarksByParent(BookmarkManager.ROOT_FOLDER_ID).length,
      isCurrent: this.parentId === BookmarkManager.ROOT_FOLDER_ID,
    }];
    const tree = this.bookmarkManager.listTree();

    const appendFolders = (nodes: BookmarkTreeNode[], depth: number): void => {
      nodes.forEach((node: BookmarkTreeNode) => {
        if (node.type !== 'folder' || node.id === excludeNodeId) {
          return;
        }
        options.push({
          id: node.id,
          title: node.title,
          depth,
          childCount: node.children.length,
          isCurrent: this.parentId === node.id,
        });
        appendFolders(node.children, depth + 1);
      });
    };
    appendFolders(tree, 1);

    // A folder cannot be moved into one of its descendants. The data layer
    // also guards this invariant, but filtering it here makes the UI choice
    // explicit and prevents a dead-end confirmation flow.
    if (excludeNodeId.length === 0) {
      return options;
    }
    const excludedDescendants = new Set<string>();
    const excludedNode = this.findTreeNode(tree, excludeNodeId);
    if (excludedNode) {
      const collectIds = (nodes: BookmarkTreeNode[]): void => {
        nodes.forEach((node: BookmarkTreeNode) => {
          excludedDescendants.add(node.id);
          collectIds(node.children);
        });
      };
      collectIds(excludedNode.children);
    }
    return options.filter((option: BookmarkFolderOption) => !excludedDescendants.has(option.id));
  }

  async importFromPicker(context: object): Promise<BookmarkImportResult> {
    const result = await this.importService.importFromPicker(context, this.bookmarkManager);
    await this.bookmarkManager.flushPersistence();
    await this.load();
    return result;
  }

  async exportToPicker(context: object): Promise<BookmarkExportResult> {
    return this.exportService.exportToPicker(context, this.bookmarkManager);
  }

  addListener(listener: (state: BookmarksPageViewState) => void): void {
    const managerListener = (_: BookmarkItem[]) => {
      this.load()
        .then((state: BookmarksPageViewState) => listener(state))
        .catch(() => listener(this.getViewState()));
    };
    this.listenerMap.set(listener, managerListener);
    this.bookmarkManager.addListener(managerListener);
  }

  removeListener(listener: (state: BookmarksPageViewState) => void): void {
    const managerListener = this.listenerMap.get(listener);
    if (!managerListener) {
      return;
    }
    this.listenerMap.delete(listener);
    this.bookmarkManager.removeListener(managerListener);
  }

  private bookmarksToListItems(bookmarks: BookmarkItem[]): BookmarksPageListItem[] {
    const normalizedKeyword = this.keyword.trim();
    return bookmarks.map((bookmark: BookmarkItem): BookmarksPageListItem => {
      const folderPathDepth = bookmark.folderPath ? bookmark.folderPath.length : 0;
      return {
        id: bookmark.id,
        type: bookmark.isFolder ? 'folder' : 'bookmark',
        title: bookmark.title,
        depth: normalizedKeyword.length > 0 ? Math.max(0, folderPathDepth) : 0,
        childCount: bookmark.isFolder ? this.countDirectChildren(bookmark.id) : 0,
        url: bookmark.isFolder ? undefined : bookmark.url,
        faviconUrl: bookmark.faviconUrl,
        parentId: bookmark.parentId,
        sortOrder: bookmark.sortOrder,
        folderPath: bookmark.folderPath,
      };
    });
  }

  private countDirectChildren(folderId: string): number {
    const treeNode = this.findTreeNode(this.bookmarkManager.listTree(), folderId);
    return treeNode ? treeNode.children.length : 0;
  }

  private findTreeNode(nodes: BookmarkTreeNode[], nodeId: string): BookmarkTreeNode | null {
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index];
      if (node.id === nodeId) {
        return node;
      }
      const child = this.findTreeNode(node.children, nodeId);
      if (child) {
        return child;
      }
    }
    return null;
  }

  private getErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '书签加载失败';
  }

  private setMutationError(message: string): void {
    // A manager listener may have started a reload immediately after the
    // in-memory mutation. Invalidate that older reload so it cannot clear a
    // persistence failure message or restore stale loading state.
    this.loadRequestId += 1;
    this.isLoading = false;
    this.errorMessage = message;
  }

  private getParentTitle(): string {
    if (this.parentId === BookmarkManager.ROOT_FOLDER_ID) {
      return '全部书签';
    }

    const parent = this.bookmarkManager.getBookmarkById(this.parentId);
    return parent ? parent.title : '全部书签';
  }
}
