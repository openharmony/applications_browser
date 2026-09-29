// BookmarkManager：管理书签树、书签导入导出与书签栏数据。

import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';
import { normalizeHttpUrlForStorage } from './urlNormalizer';

export interface BookmarkItem {
  id: string;
  url: string;
  title: string;
  faviconUrl?: string;
  parentId: string;
  sortOrder: number;
  isFolder: boolean;
  createdAt: number;
  updatedAt: number;
  folderPath?: string[];
}

export interface BookmarkFolder {
  id: string;
  type: 'folder';
  title: string;
  parentId: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number;
}

export interface BookmarkTreeNode {
  id: string;
  type: 'folder' | 'bookmark';
  title: string;
  parentId: string;
  createdAt: number;
  updatedAt: number;
  sortOrder: number;
  url?: string;
  faviconUrl?: string;
  children: BookmarkTreeNode[];
}

export interface ImportedBookmarkItem {
  type: 'bookmark';
  url: string;
  title: string;
  faviconUrl?: string;
  createdAt?: number;
  updatedAt?: number;
  sortOrder?: number;
}

export interface ImportedBookmarkFolder {
  type: 'folder';
  title: string;
  children: ImportedBookmarkEntry[];
  createdAt?: number;
  updatedAt?: number;
  sortOrder?: number;
}

export type ImportedBookmarkEntry = ImportedBookmarkItem | ImportedBookmarkFolder;

export interface BookmarkImportResult {
  totalFolders: number;
  totalBookmarks: number;
  importedFolders: number;
  importedBookmarks: number;
  updatedBookmarks: number;
  skippedBookmarks: number;
}

export interface BookmarkImportTarget {
  importEntries(entries: ImportedBookmarkEntry[]): Promise<BookmarkImportResult>;
}

export interface BookmarkExportSource {
  listTree(): BookmarkTreeNode[];
}

export interface BookmarkDataProvider extends BookmarkImportTarget, BookmarkExportSource {
  listBookmarks(): BookmarkItem[];
  listBookmarksByParent(parentId?: string): BookmarkItem[];
  getFolderCount(): number;
  getBookmarkById(id: string): BookmarkItem | null;
  searchBookmarks(keyword: string, limit?: number): Promise<BookmarkItem[]>;
  createFolder(title: string, parentId?: string, sortOrder?: number): BookmarkItem | null;
  removeBookmark(url: string): void;
  removeBookmarkById(id: string): void;
  removeNode(nodeId: string): void;
  moveNode(nodeId: string, parentId?: string, sortOrder?: number): BookmarkItem | null;
  renameNode(nodeId: string, title: string): BookmarkItem | null;
  updateBookmark(nodeId: string, title: string, url: string): BookmarkItem | null;
  /** Waits until all queued RDB mutations have settled. */
  flushPersistence(): Promise<void>;
  addListener(listener: (bookmarks: BookmarkItem[]) => void): void;
  removeListener(listener: (bookmarks: BookmarkItem[]) => void): void;
}

interface BookmarkRecord {
  id: string;
  type: 'bookmark';
  url: string;
  normalizedUrl: string;
  title: string;
  faviconUrl?: string;
  parentId: string;
  sortOrder: number;
  createdAt: number;
  updatedAt: number;
}

type StoredBookmarkNode = BookmarkFolder | BookmarkRecord;
type BookmarkListener = (bookmarks: BookmarkItem[]) => void;

export class BookmarkManager implements BookmarkDataProvider {
  private static instance: BookmarkManager = new BookmarkManager();
  static readonly ROOT_FOLDER_ID: string = '';

  private readonly bookmarksByUrl: Map<string, BookmarkRecord> = new Map();
  private readonly nodesById: Map<string, StoredBookmarkNode> = new Map();
  private readonly childrenByParentId: Map<string, string[]> = new Map();
  private readonly listeners: Set<BookmarkListener> = new Set();
  private rdbStore: relationalStore.RdbStore | null = null;
  private readonly DB_NAME: string = 'browser_bookmarks.db';
  private readonly TABLE_NAME: string = 'bookmark_nodes';
  private isInitialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  // RDB writes are issued asynchronously by UI actions. Serialize them so a
  // quick sequence of move/rename/delete operations cannot commit out of order.
  private persistenceQueue: Promise<void> = Promise.resolve();
  private lastPersistenceError: Error | null = null;

  static getInstance(): BookmarkManager {
    return BookmarkManager.instance;
  }

  async init(context: object): Promise<void> {
    if (this.isInitialized && this.rdbStore) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.initInternal(context)
      .then((): void => {
        this.isInitialized = true;
      })
      .finally((): void => {
        this.initPromise = null;
      });
    return this.initPromise;
  }

  listBookmarks(): BookmarkItem[] {
    const bookmarks: BookmarkItem[] = [];
    this.bookmarksByUrl.forEach((bookmark: BookmarkRecord) => {
      bookmarks.push(this.cloneBookmark(bookmark));
    });
    bookmarks.sort((left: BookmarkItem, right: BookmarkItem) => right.updatedAt - left.updatedAt);
    return bookmarks;
  }

  listBookmarksByParent(parentId: string = BookmarkManager.ROOT_FOLDER_ID): BookmarkItem[] {
    const items: BookmarkItem[] = [];
    this.getSortedChildren(this.normalizeParentId(parentId)).forEach((node: StoredBookmarkNode) => {
      items.push(this.nodeToBookmarkItem(node));
    });
    return items;
  }

  listTree(): BookmarkTreeNode[] {
    return this.buildTree(BookmarkManager.ROOT_FOLDER_ID);
  }

  getFolderCount(): number {
    let count = 0;
    this.nodesById.forEach((node: StoredBookmarkNode) => {
      if (node.type === 'folder') {
        count += 1;
      }
    });
    return count;
  }

  isBookmarked(url: string): boolean {
    return this.bookmarksByUrl.has(this.normalizeUrl(url));
  }

  getBookmark(url: string): BookmarkItem | null {
    const bookmark = this.bookmarksByUrl.get(this.normalizeUrl(url));
    return bookmark ? this.cloneBookmark(bookmark) : null;
  }

  getBookmarkById(id: string): BookmarkItem | null {
    const node = this.nodesById.get(id);
    return node ? this.nodeToBookmarkItem(node) : null;
  }

  async searchBookmarks(keyword: string, limit?: number): Promise<BookmarkItem[]> {
    const normalizedKeyword = keyword.trim().toLowerCase();
    if (!normalizedKeyword) {
      return [];
    }

    const matchedItems: BookmarkItem[] = [];
    this.nodesById.forEach((node: StoredBookmarkNode) => {
      const item = this.nodeToBookmarkItem(node);
      const searchableUrl = item.isFolder ? '' : item.url;
      const searchablePath = item.folderPath ? item.folderPath.join(' / ') : '';
      if (
        item.title.toLowerCase().includes(normalizedKeyword) ||
          searchableUrl.toLowerCase().includes(normalizedKeyword) ||
          searchablePath.toLowerCase().includes(normalizedKeyword)
      ) {
        matchedItems.push(item);
      }
    });
    matchedItems.sort((left: BookmarkItem, right: BookmarkItem) => {
      if (left.parentId !== right.parentId) {
        return left.parentId.localeCompare(right.parentId);
      }
      if (left.sortOrder !== right.sortOrder) {
        return left.sortOrder - right.sortOrder;
      }
      return right.updatedAt - left.updatedAt;
    });
    return limit !== undefined && limit > 0 ? matchedItems.slice(0, Math.floor(limit)) : matchedItems;
  }

  addBookmark(url: string, title?: string, faviconUrl?: string, parentId?: string): BookmarkItem | null {
    const normalizedUrl = this.normalizeUrl(url);
    if (!this.canBookmark(normalizedUrl)) {
      return null;
    }

    const now = Date.now();
    const existing = this.bookmarksByUrl.get(normalizedUrl);
    const targetParentId = this.resolveTargetFolderId(parentId, existing?.parentId);
    if (targetParentId === null) {
      return null;
    }

    const bookmark: BookmarkRecord = {
      id: existing ? existing.id : this.generateId(),
      type: 'bookmark',
      url: normalizedUrl,
      normalizedUrl: normalizedUrl,
      title: title && title.trim().length > 0 ? title.trim() : existing?.title ?? normalizedUrl,
      faviconUrl: this.resolveFaviconValue(existing?.faviconUrl, faviconUrl),
      parentId: targetParentId,
      sortOrder: existing ? existing.sortOrder : this.getNextSortOrder(targetParentId),
      createdAt: existing ? existing.createdAt : now,
      updatedAt: now,
    };

    this.nodesById.set(bookmark.id, bookmark);
    this.rebuildIndexes();
    this.persistNode(bookmark).catch(() => {
    });
    this.notify();
    return this.cloneBookmark(bookmark);
  }

  addFolder(title: string, parentId?: string): BookmarkFolder | null {
    const normalizedTitle = title.trim();
    if (!normalizedTitle) {
      return null;
    }

    const targetParentId = this.resolveTargetFolderId(parentId);
    if (targetParentId === null) {
      return null;
    }

    const existingFolder = this.findFolderChildByTitle(targetParentId, normalizedTitle);
    if (existingFolder) {
      return this.cloneFolder(existingFolder);
    }

    const now = Date.now();
    const folder: BookmarkFolder = {
      id: this.generateFolderId(),
      type: 'folder',
      title: normalizedTitle,
      parentId: targetParentId,
      sortOrder: this.getNextSortOrder(targetParentId),
      createdAt: now,
      updatedAt: now,
    };
    this.nodesById.set(folder.id, folder);
    this.rebuildIndexes();
    this.persistNode(folder).catch(() => {
    });
    this.notify();
    return this.cloneFolder(folder);
  }

  createFolder(title: string, parentId: string = BookmarkManager.ROOT_FOLDER_ID, sortOrder?: number): BookmarkItem | null {
    const folder = this.addFolder(title, parentId);
    if (!folder) {
      return null;
    }
    if (sortOrder !== undefined && sortOrder >= 0) {
      folder.sortOrder = Math.floor(sortOrder);
      this.nodesById.set(folder.id, folder);
      this.rebuildIndexes();
      this.persistNode(folder).catch(() => {
      });
    }
    return this.folderToBookmarkItem(folder);
  }

  removeBookmark(url: string): void {
    const normalizedUrl = this.normalizeUrl(url);
    const bookmark = this.bookmarksByUrl.get(normalizedUrl);
    if (!bookmark) {
      return;
    }
    this.removeNode(bookmark.id);
  }

  removeBookmarkById(id: string): void {
    this.removeNode(id);
  }

  removeNode(nodeId: string): void {
    const node = this.nodesById.get(nodeId);
    if (!node) {
      return;
    }

    const idsToDelete = this.collectDescendantIds(nodeId);
    const parentId = node.parentId;
    idsToDelete.forEach((id: string) => {
      this.nodesById.delete(id);
    });
    this.rebuildIndexes();
    const siblingUpdates = this.normalizeSiblingSortOrders(parentId);
    siblingUpdates.forEach((sibling: StoredBookmarkNode) => {
      this.persistNode(sibling).catch(() => {
      });
    });
    this.deleteNodes(idsToDelete).catch(() => {
    });
    this.notify();
  }

  moveNode(nodeId: string, parentId: string = BookmarkManager.ROOT_FOLDER_ID, sortOrder?: number): BookmarkItem | null {
    const node = this.nodesById.get(nodeId);
    if (!node) {
      return null;
    }
    const targetParentId = this.resolveTargetFolderId(parentId);
    if (targetParentId === null || targetParentId === nodeId) {
      return null;
    }
    if (node.type === 'folder' && this.collectDescendantIds(nodeId).includes(targetParentId)) {
      return null;
    }
    // Selecting the current parent without an explicit sort order is a no-op.
    // Keep the existing position stable instead of rewriting timestamps and
    // needlessly notifying every bookmarks view.
    if (targetParentId === node.parentId && sortOrder === undefined) {
      return this.nodeToBookmarkItem(node);
    }

    const oldParentId = node.parentId;
    const oldChildren = this.getSortedChildren(oldParentId).filter((child: StoredBookmarkNode) => child.id !== nodeId);
    const targetChildren = targetParentId === oldParentId ? oldChildren : this.getSortedChildren(targetParentId);
    const requestedOrder = sortOrder !== undefined && sortOrder >= 0 ? Math.floor(sortOrder) : targetChildren.length;
    node.parentId = targetParentId;
    node.sortOrder = Math.max(0, Math.min(requestedOrder, targetChildren.length));
    node.updatedAt = Date.now();
    this.nodesById.set(node.id, node);
    this.rebuildIndexes();
    const changedNodes: StoredBookmarkNode[] = [];
    const normalizedTargetOrder: StoredBookmarkNode[] = targetChildren.slice();
    normalizedTargetOrder.splice(node.sortOrder, 0, node);
    const normalizeChildren = (children: StoredBookmarkNode[]): void => {
      children.forEach((child: StoredBookmarkNode, index: number) => {
        if (child.sortOrder !== index || child.id === node.id) {
          child.sortOrder = index;
          child.updatedAt = Date.now();
          this.nodesById.set(child.id, child);
          if (!changedNodes.some((changed: StoredBookmarkNode) => changed.id === child.id)) {
            changedNodes.push(child);
          }
        }
      });
    };
    if (targetParentId === oldParentId) {
      normalizeChildren(normalizedTargetOrder);
    } else {
      normalizeChildren(oldChildren);
      normalizeChildren(normalizedTargetOrder);
    }
    if (!changedNodes.some((changed: StoredBookmarkNode) => changed.id === node.id)) {
      changedNodes.push(node);
    }
    changedNodes.forEach((changed: StoredBookmarkNode) => {
      this.persistNode(changed).catch(() => {
      });
    });
    this.notify();
    return this.nodeToBookmarkItem(node);
  }

  renameNode(nodeId: string, title: string): BookmarkItem | null {
    const node = this.nodesById.get(nodeId);
    const normalizedTitle = title.trim();
    if (!node || normalizedTitle.length === 0) {
      return null;
    }
    if (node.type === 'folder') {
      const duplicate = this.findFolderChildByTitle(node.parentId, normalizedTitle);
      if (duplicate && duplicate.id !== node.id) {
        return null;
      }
    }
    node.title = normalizedTitle;
    node.updatedAt = Date.now();
    this.nodesById.set(node.id, node);
    this.rebuildIndexes();
    this.persistNode(node).catch(() => {
    });
    this.notify();
    return this.nodeToBookmarkItem(node);
  }

  updateBookmark(nodeId: string, title: string, url: string): BookmarkItem | null {
    const node = this.nodesById.get(nodeId);
    const normalizedTitle = title.trim();
    const normalizedUrl = this.normalizeUrl(url);
    if (!node || node.type !== 'bookmark' || normalizedTitle.length === 0 || !this.canBookmark(normalizedUrl)) {
      return null;
    }
    const duplicate = this.bookmarksByUrl.get(normalizedUrl);
    if (duplicate && duplicate.id !== node.id) {
      return null;
    }
    node.title = normalizedTitle;
    node.url = normalizedUrl;
    node.normalizedUrl = normalizedUrl;
    node.updatedAt = Date.now();
    this.nodesById.set(node.id, node);
    this.rebuildIndexes();
    this.persistNode(node).catch(() => {
    });
    this.notify();
    return this.nodeToBookmarkItem(node);
  }

  moveBookmark(url: string, parentId: string = BookmarkManager.ROOT_FOLDER_ID, sortOrder?: number): BookmarkItem | null {
    const normalizedUrl = this.normalizeUrl(url);
    const bookmark = this.bookmarksByUrl.get(normalizedUrl);
    if (!bookmark) {
      return null;
    }

    return this.moveNode(bookmark.id, parentId, sortOrder);
  }

  toggleBookmark(url: string, title?: string, faviconUrl?: string): boolean {
    if (this.isBookmarked(url)) {
      this.removeBookmark(url);
      return false;
    }
    return this.addBookmark(url, title, faviconUrl) !== null;
  }

  refreshBookmark(url: string, title?: string, faviconUrl?: string): void {
    const normalizedUrl = this.normalizeUrl(url);
    const bookmark = this.bookmarksByUrl.get(normalizedUrl);
    if (!bookmark) {
      return;
    }

    // Only lift a URL-fallback title (bookmark was saved before the page had
    // a title) to the real page title. A name set by the user via rename, or
    // captured when the bookmark was created, must survive revisits —
    // refreshBookmark is called on every visit and favicon capture, so an
    // unconditional overwrite silently reverts manual renames.
    if (title && title.trim().length > 0 &&
      (bookmark.title === bookmark.url || bookmark.title === bookmark.normalizedUrl)) {
      bookmark.title = title.trim();
    }
    const normalizedFavicon = faviconUrl ? faviconUrl.trim() : '';
    if (normalizedFavicon.length > 0 && this.shouldReplaceFavicon(bookmark.faviconUrl, normalizedFavicon)) {
      bookmark.faviconUrl = normalizedFavicon;
    }
    bookmark.updatedAt = Date.now();
    this.nodesById.set(bookmark.id, bookmark);
    this.persistNode(bookmark).catch(() => {
    });
    this.notify();
  }

  async importEntries(entries: ImportedBookmarkEntry[]): Promise<BookmarkImportResult> {
    const result: BookmarkImportResult = {
      totalFolders: 0,
      totalBookmarks: 0,
      importedFolders: 0,
      importedBookmarks: 0,
      updatedBookmarks: 0,
      skippedBookmarks: 0,
    };

    for (let index = 0; index < entries.length; index++) {
      await this.importEntry(entries[index], BookmarkManager.ROOT_FOLDER_ID, index, result);
    }
    this.rebuildIndexes();
    this.notify();
    return result;
  }

  addListener(listener: BookmarkListener): void {
    this.listeners.add(listener);
  }

  removeListener(listener: BookmarkListener): void {
    this.listeners.delete(listener);
  }

  private notify(): void {
    const snapshot = this.listBookmarks();
    this.listeners.forEach((listener: BookmarkListener) => {
      try {
        listener(snapshot);
      } catch (_) {
      }
    });
  }

  private async initInternal(context: object): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: this.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
      };

      this.rdbStore = await new Promise((resolve, reject) => {
        relationalStore.getRdbStore(context as never, config,
          (err: BusinessError | null, store: relationalStore.RdbStore | null): void => {
            if (err || !store) {
              reject(err || new Error('Failed to get bookmark store'));
            } else {
              resolve(store);
            }
          });
      });

      await this.createTable();
      await this.loadNodesFromStore();
      this.notify();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to initialize bookmarks database: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async createTable(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    const createTableSql = `
      CREATE TABLE IF NOT EXISTS ${this.TABLE_NAME} (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        url TEXT,
        normalizedUrl TEXT,
        title TEXT NOT NULL,
        faviconUrl TEXT,
        parentId TEXT NOT NULL,
        sortOrder INTEGER NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      );
    `;

    try {
      await this.rdbStore.executeSql(createTableSql);
      await this.createIndexes();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create bookmarks table: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async createIndexes(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }
    try {
      await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_parent_sort ON ${this.TABLE_NAME}(parentId, sortOrder);`);
      await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_url ON ${this.TABLE_NAME}(normalizedUrl);`);
      await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_updated_at ON ${this.TABLE_NAME}(updatedAt DESC);`);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create bookmark indexes: ${errorMessage}`);
    }
  }

  private async loadNodesFromStore(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      const resultSet = await this.rdbStore.query(predicates);
      const nodes = this.resultSetToNodes(resultSet);
      nodes.forEach((node: StoredBookmarkNode) => {
        const pendingNode = this.nodesById.get(node.id);
        // Preserve a user mutation that happened while the RDB was loading.
        if (!pendingNode || pendingNode.updatedAt <= node.updatedAt) {
          this.nodesById.set(node.id, node);
        }
      });
      this.rebuildIndexes();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to load bookmarks: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async persistNode(node: StoredBookmarkNode): Promise<void> {
    const snapshot = this.cloneStoredNode(node);
    return this.enqueuePersistence(async (): Promise<void> => {
      if (this.rdbStore) {
        await this.persistNodeInternal(snapshot);
        return;
      }
      if (this.initPromise) {
        await this.initPromise;
        if (this.rdbStore) {
          await this.persistNodeInternal(snapshot);
        }
      }
    });
  }

  private enqueuePersistence(operation: () => Promise<void>): Promise<void> {
    const next = this.persistenceQueue.then(operation, operation);
    this.persistenceQueue = next.catch((error: Error): void => {
      this.lastPersistenceError = error instanceof Error ? error : new Error(String(error));
    });
    return next;
  }

  async flushPersistence(): Promise<void> {
    await this.persistenceQueue;
    const error = this.lastPersistenceError;
    this.lastPersistenceError = null;
    if (error) {
      throw error;
    }
  }

  private async persistNodeInternal(node: StoredBookmarkNode): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('id', node.id);
      resultSet = await this.rdbStore.query(predicates, ['id']);
      const valuesBucket = this.nodeToValuesBucket(node);

      if (resultSet.goToFirstRow()) {
        const updatePredicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
        updatePredicates.equalTo('id', node.id);
        await this.rdbStore.update(valuesBucket, updatePredicates);
      } else {
        await this.rdbStore.insert(this.TABLE_NAME, valuesBucket);
      }
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to persist bookmark node: ${errorMessage}`);
      throw new Error(errorMessage);
    } finally {
      if (resultSet) {
        this.closeResultSetSafely(resultSet);
      }
    }
  }

  private async deleteNodes(nodeIds: string[]): Promise<void> {
    const ids = nodeIds.slice();
    return this.enqueuePersistence(async (): Promise<void> => {
      if (!this.rdbStore && this.initPromise) {
        await this.initPromise;
      }
      if (!this.rdbStore) {
        return;
      }
      for (let index = 0; index < ids.length; index++) {
        await this.deleteNodeInternal(ids[index]);
      }
    });
  }

  private normalizeSiblingSortOrders(parentId: string): StoredBookmarkNode[] {
    const changedNodes: StoredBookmarkNode[] = [];
    this.getSortedChildren(parentId).forEach((child: StoredBookmarkNode, index: number) => {
      if (child.sortOrder !== index) {
        child.sortOrder = index;
        child.updatedAt = Date.now();
        this.nodesById.set(child.id, child);
        changedNodes.push(child);
      }
    });
    return changedNodes;
  }

  private async deleteNodeInternal(nodeId: string): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('id', nodeId);
      await this.rdbStore.delete(predicates);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete bookmark node: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private nodeToValuesBucket(node: StoredBookmarkNode): relationalStore.ValuesBucket {
    if (node.type === 'folder') {
      return {
        id: node.id,
        type: node.type,
        url: '',
        normalizedUrl: '',
        title: node.title,
        faviconUrl: '',
        parentId: node.parentId,
        sortOrder: node.sortOrder,
        createdAt: node.createdAt,
        updatedAt: node.updatedAt,
      };
    }

    return {
      id: node.id,
      type: node.type,
      url: node.url,
      normalizedUrl: node.normalizedUrl,
      title: node.title,
      faviconUrl: node.faviconUrl ? node.faviconUrl : '',
      parentId: node.parentId,
      sortOrder: node.sortOrder,
      createdAt: node.createdAt,
      updatedAt: node.updatedAt,
    };
  }

  private resultSetToNodes(resultSet: relationalStore.ResultSet): StoredBookmarkNode[] {
    const nodes: StoredBookmarkNode[] = [];

    try {
      const rowCount = resultSet.rowCount;
      if (rowCount > 0) {
        resultSet.goToFirstRow();
        do {
          const type = this.readStringColumn(resultSet, 'type');
          if (type === 'folder') {
            nodes.push({
              id: this.readStringColumn(resultSet, 'id'),
              type: 'folder',
              title: this.readStringColumn(resultSet, 'title'),
              parentId: this.normalizeParentId(this.readStringColumn(resultSet, 'parentId')),
              sortOrder: this.readLongColumn(resultSet, 'sortOrder'),
              createdAt: this.readLongColumn(resultSet, 'createdAt'),
              updatedAt: this.readLongColumn(resultSet, 'updatedAt'),
            });
            continue;
          }

          const url = this.readStringColumn(resultSet, 'url');
          nodes.push({
            id: this.readStringColumn(resultSet, 'id'),
            type: 'bookmark',
            url: url,
            normalizedUrl: this.readOptionalStringColumn(resultSet, 'normalizedUrl') ?? this.normalizeUrl(url),
            title: this.readStringColumn(resultSet, 'title'),
            faviconUrl: this.readOptionalStringColumn(resultSet, 'faviconUrl'),
            parentId: this.normalizeParentId(this.readStringColumn(resultSet, 'parentId')),
            sortOrder: this.readLongColumn(resultSet, 'sortOrder'),
            createdAt: this.readLongColumn(resultSet, 'createdAt'),
            updatedAt: this.readLongColumn(resultSet, 'updatedAt'),
          });
        } while (resultSet.goToNextRow());
      }
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to convert bookmark nodes resultSet: ${errorMessage}`);
      throw new Error(errorMessage);
    } finally {
      this.closeResultSetSafely(resultSet);
    }

    return nodes;
  }

  private closeResultSetSafely(resultSet: relationalStore.ResultSet): void {
    try {
      resultSet.close();
    } catch (_) {
    }
  }

  private rebuildIndexes(): void {
    this.bookmarksByUrl.clear();
    this.childrenByParentId.clear();

    this.nodesById.forEach((node: StoredBookmarkNode) => {
      const parentId = this.normalizeParentId(node.parentId);
      const children = this.childrenByParentId.get(parentId) ?? [];
      children.push(node.id);
      this.childrenByParentId.set(parentId, children);
      if (node.type === 'bookmark') {
        this.bookmarksByUrl.set(node.normalizedUrl, node);
      }
    });
  }

  private buildTree(parentId: string): BookmarkTreeNode[] {
    const treeNodes: BookmarkTreeNode[] = [];
    this.getSortedChildren(parentId).forEach((node: StoredBookmarkNode) => {
      if (node.type === 'folder') {
        treeNodes.push({
          id: node.id,
          type: 'folder',
          title: node.title,
          parentId: node.parentId,
          createdAt: node.createdAt,
          updatedAt: node.updatedAt,
          sortOrder: node.sortOrder,
          children: this.buildTree(node.id),
        });
        return;
      }

      treeNodes.push({
        id: node.id,
        type: 'bookmark',
        title: node.title,
        parentId: node.parentId,
        createdAt: node.createdAt,
        updatedAt: node.updatedAt,
        sortOrder: node.sortOrder,
        url: node.url,
        faviconUrl: node.faviconUrl,
        children: [],
      });
    });
    return treeNodes;
  }

  private getSortedChildren(parentId: string): StoredBookmarkNode[] {
    const childIds = this.childrenByParentId.get(this.normalizeParentId(parentId)) ?? [];
    const children: StoredBookmarkNode[] = [];
    childIds.forEach((childId: string) => {
      const node = this.nodesById.get(childId);
      if (node !== undefined) {
        children.push(node);
      }
    });
    children.sort((left: StoredBookmarkNode, right: StoredBookmarkNode) => {
      if (left.sortOrder !== right.sortOrder) {
        return left.sortOrder - right.sortOrder;
      }
      if (left.updatedAt !== right.updatedAt) {
        return left.updatedAt - right.updatedAt;
      }
      return left.title.localeCompare(right.title);
    });
    return children;
  }

  private resolveTargetFolderId(primaryParentId?: string, fallbackParentId?: string): string | null {
    const candidate = this.normalizeParentId(primaryParentId ?? fallbackParentId);
    if (!candidate) {
      return BookmarkManager.ROOT_FOLDER_ID;
    }
    const node = this.nodesById.get(candidate);
    if (node && node.type === 'folder') {
      return candidate;
    }
    return null;
  }

  private getNextSortOrder(parentId: string): number {
    const children = this.getSortedChildren(parentId);
    if (children.length === 0) {
      return 0;
    }
    return children[children.length - 1].sortOrder + 1;
  }

  private findFolderChildByTitle(parentId: string, title: string): BookmarkFolder | null {
    const normalizedTitle = title.trim();
    const children = this.getSortedChildren(parentId);
    for (let index = 0; index < children.length; index++) {
      const node = children[index];
      if (node.type === 'folder' && node.title === normalizedTitle) {
        return node;
      }
    }
    return null;
  }

  private collectDescendantIds(nodeId: string): string[] {
    const result: string[] = [];
    const visit = (currentId: string): void => {
      result.push(currentId);
      const children = this.childrenByParentId.get(currentId) ?? [];
      children.forEach((childId: string) => visit(childId));
    };
    visit(nodeId);
    return result;
  }

  private async importEntry(
    entry: ImportedBookmarkEntry,
    parentId: string,
    sortOrder: number,
    result: BookmarkImportResult,
  ): Promise<void> {
    if (entry.type === 'folder') {
      result.totalFolders += 1;
      const folderTitle = entry.title.trim();
      if (!folderTitle) {
        return;
      }

      let folder = this.findFolderChildByTitle(parentId, folderTitle);
      if (!folder) {
        const now = Date.now();
        folder = {
          id: this.generateFolderId(),
          type: 'folder',
          title: folderTitle,
          parentId: parentId,
          createdAt: entry.createdAt ?? now,
          updatedAt: entry.updatedAt ?? entry.createdAt ?? now,
          sortOrder: entry.sortOrder ?? sortOrder,
        };
        this.nodesById.set(folder.id, folder);
        await this.persistNode(folder);
        this.rebuildIndexes();
        result.importedFolders += 1;
      }

      for (let index = 0; index < entry.children.length; index++) {
        await this.importEntry(entry.children[index], folder.id, index, result);
      }
      return;
    }

    result.totalBookmarks += 1;
    const normalizedUrl = this.normalizeUrl(entry.url);
    if (!this.canBookmark(normalizedUrl)) {
      result.skippedBookmarks += 1;
      return;
    }

    const existing = this.bookmarksByUrl.get(normalizedUrl);
    const now = Date.now();
    const bookmark: BookmarkRecord = {
      id: existing ? existing.id : this.generateId(),
      type: 'bookmark',
      url: normalizedUrl,
      normalizedUrl: normalizedUrl,
      title: entry.title && entry.title.trim().length > 0 ? entry.title.trim() : existing?.title ?? normalizedUrl,
      faviconUrl: this.resolveFaviconValue(existing?.faviconUrl, entry.faviconUrl),
      parentId: parentId,
      sortOrder: entry.sortOrder ?? sortOrder,
      createdAt: existing ? existing.createdAt : entry.createdAt ?? now,
      updatedAt: entry.updatedAt ?? now,
    };
    this.nodesById.set(bookmark.id, bookmark);
    this.bookmarksByUrl.set(normalizedUrl, bookmark);
    await this.persistNode(bookmark);

    if (existing) {
      result.updatedBookmarks += 1;
    } else {
      result.importedBookmarks += 1;
    }
  }

  private canBookmark(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private resolveFaviconValue(existing: string | undefined, incoming: string | undefined): string | undefined {
    if (!incoming || incoming.trim().length === 0) {
      return existing;
    }
    return this.shouldReplaceFavicon(existing, incoming) ? incoming.trim() : existing;
  }

  private shouldReplaceFavicon(existing: string | undefined, incoming: string | undefined): boolean {
    if (!incoming || incoming.trim().length === 0) {
      return false;
    }
    if (!existing || existing.trim().length === 0) {
      return true;
    }
    // Encoded PixelMap data is authoritative. A transient network fallback
    // must never replace it during a reload or a delayed favicon callback.
    return incoming.trim().toLowerCase().startsWith('data:') ||
      !existing.trim().toLowerCase().startsWith('data:');
  }

  private normalizeUrl(url: string): string {
    return normalizeHttpUrlForStorage(url);
  }

  private normalizeParentId(parentId?: string): string {
    if (!parentId) {
      return BookmarkManager.ROOT_FOLDER_ID;
    }
    return parentId;
  }

  private resolveFolderPath(parentId: string): string[] {
    const folderPath: string[] = [];
    let currentId = this.normalizeParentId(parentId);
    while (currentId) {
      const node = this.nodesById.get(currentId);
      if (!node || node.type !== 'folder') {
        break;
      }
      folderPath.unshift(node.title);
      currentId = this.normalizeParentId(node.parentId);
    }
    return folderPath;
  }

  private readStringColumn(resultSet: relationalStore.ResultSet, columnName: string): string {
    try {
      const columnIndex = resultSet.getColumnIndex(columnName);
      if (columnIndex < 0) {
        return '';
      }
      return resultSet.getString(columnIndex);
    } catch (_) {
      return '';
    }
  }

  private readLongColumn(resultSet: relationalStore.ResultSet, columnName: string): number {
    try {
      const columnIndex = resultSet.getColumnIndex(columnName);
      if (columnIndex < 0) {
        return 0;
      }
      return resultSet.getLong(columnIndex);
    } catch (_) {
      return 0;
    }
  }

  private readOptionalStringColumn(resultSet: relationalStore.ResultSet, columnName: string): string | undefined {
    try {
      const columnIndex = resultSet.getColumnIndex(columnName);
      if (columnIndex < 0) {
        return undefined;
      }
      const value = resultSet.getString(columnIndex);
      return value && value.trim().length > 0 ? value : undefined;
    } catch (_) {
      return undefined;
    }
  }

  private nodeToBookmarkItem(node: StoredBookmarkNode): BookmarkItem {
    if (node.type === 'folder') {
      return this.folderToBookmarkItem(node);
    }
    return this.cloneBookmark(node);
  }

  private cloneBookmark(bookmark: BookmarkRecord): BookmarkItem {
    return {
      id: bookmark.id,
      url: bookmark.url,
      title: bookmark.title,
      faviconUrl: bookmark.faviconUrl,
      parentId: bookmark.parentId,
      sortOrder: bookmark.sortOrder,
      isFolder: false,
      createdAt: bookmark.createdAt,
      updatedAt: bookmark.updatedAt,
      folderPath: this.resolveFolderPath(bookmark.parentId),
    };
  }

  private folderToBookmarkItem(folder: BookmarkFolder): BookmarkItem {
    return {
      id: folder.id,
      url: '',
      title: folder.title,
      parentId: folder.parentId,
      sortOrder: folder.sortOrder,
      isFolder: true,
      createdAt: folder.createdAt,
      updatedAt: folder.updatedAt,
      folderPath: this.resolveFolderPath(folder.parentId),
    };
  }

  private cloneFolder(folder: BookmarkFolder): BookmarkFolder {
    return {
      id: folder.id,
      type: 'folder',
      title: folder.title,
      parentId: folder.parentId,
      sortOrder: folder.sortOrder,
      createdAt: folder.createdAt,
      updatedAt: folder.updatedAt,
    };
  }

  private cloneStoredNode(node: StoredBookmarkNode): StoredBookmarkNode {
    if (node.type === 'folder') {
      return {
        id: node.id,
        type: 'folder',
        title: node.title,
        parentId: node.parentId,
        sortOrder: node.sortOrder,
        createdAt: node.createdAt,
        updatedAt: node.updatedAt,
      };
    }
    return {
      id: node.id,
      type: 'bookmark',
      url: node.url,
      normalizedUrl: node.normalizedUrl,
      title: node.title,
      faviconUrl: node.faviconUrl,
      parentId: node.parentId,
      sortOrder: node.sortOrder,
      createdAt: node.createdAt,
      updatedAt: node.updatedAt,
    };
  }

  private generateId(): string {
    return 'bm_' + Math.random().toString(36).slice(2, 11);
  }

  private generateFolderId(): string {
    return 'bf_' + Math.random().toString(36).slice(2, 11);
  }
}
