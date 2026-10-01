// TabManager：管理标签页的生命周期与状态。

import { BrowserWindowSession, Tab, TabId, TabLoadState, WindowId } from './types';
import { BrowserSessionSnapshot, ClosedTabSessionRecord } from './sessionManager';
import { isSameHttpDocumentUrl } from './urlNormalizer';

interface ClosedTabRecord {
  tab: Tab;
  insertIndex: number;
  closedAt: number;
}

interface TabCloseCandidate {
  id: TabId;
  index: number;
  tab: Tab;
}

export class TabManager {
  private tabs: Map<TabId, Tab> = new Map();
  private windowSessions: Map<WindowId, BrowserWindowSession> = new Map();
  private recentlyClosedTabs: ClosedTabRecord[] = [];
  private readonly maxRecentlyClosedTabs: number = 20;

  createTab(initialUrl: string = '', isPrivate: boolean = false, windowId?: WindowId): Tab {
    const targetWindowId = windowId ?? this.getDefaultWindowId();
    const session = this.ensureWindowSession(targetWindowId, isPrivate);
    const id = this.generateTabId();
    const now = Date.now();
    const normalizedUrl = this.normalizeInitialUrl(initialUrl);
    const loadState = this.resolveInitialLoadState(normalizedUrl);
    const homeTitle = isPrivate ? '无痕标签页' : '新标签页';
    const tab: Tab = {
      id,
      windowId: targetWindowId,
      title: loadState === 'home' ? homeTitle : '',
      url: normalizedUrl,
      faviconUrl: undefined,
      pendingUrl: loadState === 'home' ? undefined : normalizedUrl,
      isActive: false,
      isPrivate,
      isLoading: loadState === 'loading',
      loadState,
      canGoBack: false,
      canGoForward: false,
      audible: false,
      muted: false,
      isPinned: false,
      closeGuard: false,
      createdAt: now,
      lastActiveAt: now,
    };

    this.tabs.set(id, tab);
    this.insertTabIntoWindow(session, id);
    this.setActiveTab(id);
    return this.cloneTab(tab);
  }

  closeTab(id: TabId): void {
    this.closeTabs([id]);
  }

  /** Close a stable set of tabs in one mutation pass. */
  closeTabs(ids: TabId[]): Tab[] {
    const requestedIds: string[] = [];
    ids.forEach((id: TabId) => {
      const key = String(id);
      if (!requestedIds.includes(key)) {
        requestedIds.push(key);
      }
    });
    const closedTabs: Tab[] = [];
    this.windowSessions.forEach((session: BrowserWindowSession) => {
      const candidates: TabCloseCandidate[] = [];
      session.tabIds.forEach((tabId: TabId, index: number) => {
        if (!requestedIds.includes(String(tabId))) {
          return;
        }
        const tab = this.tabs.get(tabId);
        if (!tab || tab.closeGuard === true) {
          return;
        }
        candidates.push({ id: tabId, index, tab });
      });
      if (candidates.length === 0) {
        return;
      }
      const activeId = session.activeTabId;
      const activeWasClosed = activeId !== null && candidates.some((item) => String(item.id) === String(activeId));
      const activeIndex = activeId === null ? -1 : session.tabIds.findIndex(
        (tabId) => String(tabId) === String(activeId)
      );
      candidates.forEach((item) => {
        if (!item.tab.isPrivate) {
          this.pushRecentlyClosedTab(this.cloneTab(item.tab), item.index);
        }
        closedTabs.push(this.cloneTab(item.tab));
        this.tabs.delete(item.id);
      });
      const removedIds = candidates.map((item) => String(item.id));
      session.tabIds = session.tabIds.filter((tabId) => !removedIds.includes(String(tabId)));
      if (!activeWasClosed) {
        return;
      }
      if (session.tabIds.length === 0) {
        session.activeTabId = null;
        return;
      }
      const nextIndex = activeIndex < session.tabIds.length ? Math.max(0, activeIndex) : session.tabIds.length - 1;
      this.setActiveTab(session.tabIds[nextIndex]);
    });
    return closedTabs;
  }

  closeOtherTabs(targetTabId: TabId): Tab[] {
    const target = this.tabs.get(targetTabId);
    if (!target) {
      return [];
    }
    const session = this.windowSessions.get(target.windowId);
    if (!session) {
      return [];
    }
    return this.closeTabs(session.tabIds.filter((tabId) => String(tabId) !== String(targetTabId)));
  }

  closeTabsToRight(targetTabId: TabId): Tab[] {
    const target = this.tabs.get(targetTabId);
    if (!target) {
      return [];
    }
    const session = this.windowSessions.get(target.windowId);
    if (!session) {
      return [];
    }
    const targetIndex = session.tabIds.findIndex((tabId) => String(tabId) === String(targetTabId));
    return targetIndex < 0 ? [] : this.closeTabs(session.tabIds.slice(targetIndex + 1));
  }

  canCloseTab(id: TabId): boolean {
    const tab = this.tabs.get(id);
    return !!tab && tab.closeGuard !== true;
  }

  restoreLastClosedTab(windowId?: WindowId): Tab | null {
    if (this.recentlyClosedTabs.length === 0) {
      return null;
    }

    const targetWindowId = windowId ?? this.getDefaultWindowId();
    let recordIndex = -1;
    for (let index = this.recentlyClosedTabs.length - 1; index >= 0; index--) {
      const record = this.recentlyClosedTabs[index];
      if (String(record.tab.windowId) === String(targetWindowId)) {
        recordIndex = index;
        break;
      }
    }

    if (recordIndex === -1) {
      return null;
    }

    const record = this.recentlyClosedTabs.splice(recordIndex, 1)[0];
    const session = this.ensureWindowSession(targetWindowId, record.tab.isPrivate);
    const restoredTab = this.cloneTab(record.tab);
    restoredTab.windowId = targetWindowId;
    restoredTab.isActive = false;
    restoredTab.lastActiveAt = Date.now();

    this.tabs.set(restoredTab.id, restoredTab);
    this.insertTabAtWindowIndex(session, restoredTab.id, record.insertIndex);
    this.setActiveTab(restoredTab.id);
    return this.cloneTab(restoredTab);
  }

  hasRecentlyClosedTab(windowId?: WindowId): boolean {
    const targetWindowId = windowId ?? this.getDefaultWindowId();
    return this.recentlyClosedTabs.some((record: ClosedTabRecord) => {
      return String(record.tab.windowId) === String(targetWindowId);
    });
  }

  updateTab(id: TabId, partial: Partial<Tab>): Tab | null {
    const tab = this.tabs.get(id);
    if (!tab) {
      return null;
    }

    const next: Tab = this.cloneTab(tab);
    if (partial.title !== undefined) {
      next.title = partial.title;
    }
    if (partial.url !== undefined) {
      next.url = partial.url;
    }
    if (this.hasPartialField(partial, 'faviconUrl')) {
      next.faviconUrl = partial.faviconUrl;
    }
    if (this.hasPartialField(partial, 'pendingUrl')) {
      next.pendingUrl = partial.pendingUrl;
    }
    if (partial.isActive !== undefined) {
      next.isActive = partial.isActive;
    }
    if (partial.isPrivate !== undefined) {
      next.isPrivate = partial.isPrivate;
    }
    if (partial.isLoading !== undefined) {
      next.isLoading = partial.isLoading;
    }
    if (partial.loadState !== undefined) {
      next.loadState = partial.loadState;
    }
    if (partial.canGoBack !== undefined) {
      next.canGoBack = partial.canGoBack;
    }
    if (partial.canGoForward !== undefined) {
      next.canGoForward = partial.canGoForward;
    }
    if (partial.audible !== undefined) {
      next.audible = partial.audible;
    }
    if (partial.muted !== undefined) {
      next.muted = partial.muted;
    }
    // Ignore legacy pin state. Pinning is no longer supported.
    next.isPinned = false;
    if (partial.closeGuard !== undefined) {
      next.closeGuard = partial.closeGuard;
    }
    if (partial.createdAt !== undefined) {
      next.createdAt = partial.createdAt;
    }
    if (partial.lastActiveAt !== undefined) {
      next.lastActiveAt = partial.lastActiveAt;
    }
    this.tabs.set(id, next);
    return this.cloneTab(next);
  }

  setActiveTab(id: TabId): void {
    const tab = this.tabs.get(id);
    if (!tab) {
      return;
    }

    const session = this.windowSessions.get(tab.windowId);
    if (!session) {
      return;
    }

    const now = Date.now();
    session.activeTabId = id;
    session.lastActiveAt = now;

    session.tabIds.forEach(tabId => {
      const item = this.tabs.get(tabId);
      if (!item) {
        return;
      }
      item.isActive = String(tabId) === String(id);
      if (item.isActive) {
        item.lastActiveAt = now;
      }
    });
  }

  getTab(id: TabId): Tab | null {
    const tab = this.tabs.get(id);
    return tab ? this.cloneTab(tab) : null;
  }

  getActiveTabId(windowId?: WindowId): TabId | null {
    const targetWindowId = windowId ?? this.getDefaultWindowId();
    return this.windowSessions.get(targetWindowId)?.activeTabId ?? null;
  }

  getActiveTab(windowId?: WindowId): Tab | null {
    const activeTabId = this.getActiveTabId(windowId);
    if (!activeTabId) {
      return null;
    }
    return this.getTab(activeTabId);
  }

  getTabs(windowId?: WindowId): Tab[] {
    const targetWindowId = windowId ?? this.getDefaultWindowId();
    const session = this.windowSessions.get(targetWindowId);
    if (!session) {
      return [];
    }

    const result: Tab[] = [];
    session.tabIds.forEach(tabId => {
      const tab = this.tabs.get(tabId);
      if (tab) {
        result.push(this.cloneTab(tab));
      }
    });
    return result;
  }

  getWindowSession(windowId?: WindowId): BrowserWindowSession | null {
    const targetWindowId = windowId ?? this.getDefaultWindowId();
    const session = this.windowSessions.get(targetWindowId);
    if (!session) {
      return null;
    }
    return this.cloneSession(session);
  }

  exportSessionSnapshot(activeWindowId?: WindowId): BrowserSessionSnapshot {
    const windows: BrowserWindowSession[] = [];
    this.windowSessions.forEach((session: BrowserWindowSession) => {
      windows.push(this.cloneSession(session));
    });

    const tabs: Tab[] = [];
    this.tabs.forEach((tab: Tab) => {
      tabs.push(this.cloneTab(tab));
    });

    return {
      version: 1,
      windows,
      tabs,
      recentlyClosedTabs: this.recentlyClosedTabs
        .filter((record: ClosedTabRecord): boolean => !record.tab.isPrivate)
        .map((record: ClosedTabRecord): ClosedTabSessionRecord => this.cloneClosedTabRecordForSnapshot(record)),
      activeWindowId: String(activeWindowId ?? this.getDefaultWindowId()),
      savedAt: Date.now(),
    };
  }

  restoreFromSessionSnapshot(snapshot: BrowserSessionSnapshot, windowId?: WindowId): boolean {
    const targetWindowId = windowId ?? this.getDefaultWindowId();
    const sourceWindow = snapshot.windows.find(
      (session: BrowserWindowSession) => String(session.id) === String(targetWindowId)
    ) ?? snapshot.windows[0];
    if (!sourceWindow) {
      return false;
    }

    const restoredTabs: Tab[] = [];
    sourceWindow.tabIds.forEach((tabId: TabId) => {
      const sourceTab = snapshot.tabs.find((tab: Tab) => String(tab.id) === String(tabId));
      if (!sourceTab || sourceTab.isPrivate) {
        return;
      }
      restoredTabs.push(this.cloneRestoredTab(sourceTab, targetWindowId));
    });

    if (restoredTabs.length === 0) {
      return false;
    }

    this.tabs.clear();
    this.windowSessions.clear();
    this.recentlyClosedTabs = this.restoreClosedTabRecords(snapshot.recentlyClosedTabs ?? [], targetWindowId);

    const session: BrowserWindowSession = {
      id: targetWindowId,
      tabIds: restoredTabs.map((tab: Tab) => tab.id),
      activeTabId: null,
      isPrivateWindow: false,
      createdAt: sourceWindow.createdAt,
      lastActiveAt: Date.now(),
    };
    this.windowSessions.set(targetWindowId, session);

    restoredTabs.forEach((tab: Tab) => {
      this.tabs.set(tab.id, tab);
    });

    const hasPreferredActiveTab = sourceWindow.activeTabId && restoredTabs.some(
      (tab: Tab) => String(tab.id) === String(sourceWindow.activeTabId)
    );
    const preferredActiveId = hasPreferredActiveTab ? sourceWindow.activeTabId : restoredTabs[0].id;
    this.setActiveTab(preferredActiveId);
    return true;
  }

  updateTabLoadState(id: TabId, loadState: TabLoadState, title?: string, url?: string): Tab | null {
    const tab = this.tabs.get(id);
    if (!tab) {
      return null;
    }

    const nextTitle = title !== undefined ? title : tab.title;
    const nextUrl = url !== undefined ? url : tab.url;
    const documentChanged = url !== undefined && !isSameHttpDocumentUrl(tab.url, nextUrl);
    const homeTitle = tab.isPrivate ? '无痕标签页' : '新标签页';
    tab.loadState = loadState;
    tab.isLoading = loadState === 'loading';
    tab.url = nextUrl;
    // A new document must not inherit the previous page's favicon while
    // ArkWeb is between navigation callbacks. Same-document reloads retain it.
    if (loadState === 'loading' && documentChanged) {
      tab.faviconUrl = undefined;
    }
    tab.pendingUrl = loadState === 'loading' ? nextUrl : undefined;
    tab.title = nextTitle || (loadState === 'home' ? homeTitle : tab.title);
    return this.cloneTab(tab);
  }

  updateTabNavigationState(id: TabId, canGoBack: boolean, canGoForward: boolean): Tab | null {
    const tab = this.tabs.get(id);
    if (!tab) {
      return null;
    }
    tab.canGoBack = canGoBack;
    tab.canGoForward = canGoForward;
    return this.cloneTab(tab);
  }

  private generateTabId(): TabId {
    // 简单的 ID 生成器；后续可替换为更稳健的实现。
    return ('tab_' + Math.random().toString(36).substr(2, 9)) as TabId;
  }

  private hasPartialField(partial: Partial<Tab>, fieldName: string): boolean {
    return Object.keys(partial).includes(fieldName);
  }

  private getDefaultWindowId(): WindowId {
    return 'window_main' as WindowId;
  }

  private ensureWindowSession(windowId: WindowId, isPrivateWindow: boolean): BrowserWindowSession {
    const existing = this.windowSessions.get(windowId);
    if (existing) {
      return existing;
    }

    const now = Date.now();
    const session: BrowserWindowSession = {
      id: windowId,
      tabIds: [],
      activeTabId: null,
      isPrivateWindow,
      createdAt: now,
      lastActiveAt: now,
    };
    this.windowSessions.set(windowId, session);
    return session;
  }

  private insertTabIntoWindow(session: BrowserWindowSession, tabId: TabId): void {
    if (!session.activeTabId) {
      session.tabIds.push(tabId);
      return;
    }

    const activeIndex = session.tabIds.findIndex(id => String(id) === String(session.activeTabId));
    if (activeIndex === -1) {
      session.tabIds.push(tabId);
      return;
    }
    session.tabIds.splice(activeIndex + 1, 0, tabId);
  }

  private insertTabAtWindowIndex(session: BrowserWindowSession, tabId: TabId, insertIndex: number): void {
    let normalizedIndex = insertIndex < 0 ? 0 : insertIndex;
    if (normalizedIndex >= session.tabIds.length) {
      session.tabIds.push(tabId);
      return;
    }
    session.tabIds.splice(normalizedIndex, 0, tabId);
  }

  private normalizeInitialUrl(initialUrl: string): string {
    const value = initialUrl.trim();
    return value ? value : 'about:blank';
  }

  private resolveInitialLoadState(url: string): TabLoadState {
    return url === 'about:blank' ? 'home' : 'loading';
  }

  private pushRecentlyClosedTab(tab: Tab, insertIndex: number): void {
    this.recentlyClosedTabs.push({
      tab,
      insertIndex,
      closedAt: Date.now(),
    });

    if (this.recentlyClosedTabs.length > this.maxRecentlyClosedTabs) {
      this.recentlyClosedTabs.shift();
    }
  }

  private restoreClosedTabRecords(records: ClosedTabSessionRecord[], windowId: WindowId): ClosedTabRecord[] {
    const restoredRecords: ClosedTabRecord[] = [];
    records.forEach((record: ClosedTabSessionRecord) => {
      if (!record || !record.tab || record.tab.isPrivate) {
        return;
      }
      restoredRecords.push({
        tab: this.cloneRestoredTab(record.tab, windowId),
        insertIndex: Math.max(0, record.insertIndex),
        closedAt: record.closedAt > 0 ? record.closedAt : Date.now(),
      });
    });
    return restoredRecords.slice(-this.maxRecentlyClosedTabs);
  }

  private cloneClosedTabRecordForSnapshot(record: ClosedTabRecord): ClosedTabSessionRecord {
    return {
      tab: this.cloneTab(record.tab),
      insertIndex: record.insertIndex,
      closedAt: record.closedAt,
    };
  }

  private cloneTab(tab: Tab): Tab {
    return {
      id: tab.id,
      windowId: tab.windowId,
      title: tab.title,
      url: tab.url,
      faviconUrl: tab.faviconUrl,
      pendingUrl: tab.pendingUrl,
      isActive: tab.isActive,
      isPrivate: tab.isPrivate,
      isLoading: tab.isLoading,
      loadState: tab.loadState,
      canGoBack: tab.canGoBack,
      canGoForward: tab.canGoForward,
      audible: tab.audible,
      muted: tab.muted,
      isPinned: false,
      closeGuard: tab.closeGuard === true,
      createdAt: tab.createdAt,
      lastActiveAt: tab.lastActiveAt,
    };
  }

  private cloneRestoredTab(tab: Tab, windowId: WindowId): Tab {
    return {
      id: tab.id,
      windowId,
      title: tab.title && tab.title.trim().length > 0
        ? tab.title
        : (tab.url === 'about:blank' ? '新标签页' : tab.url),
      url: tab.url && tab.url.trim().length > 0 ? tab.url : 'about:blank',
      faviconUrl: tab.faviconUrl,
      pendingUrl: undefined,
      isActive: false,
      isPrivate: false,
      isLoading: false,
      loadState: tab.url === 'about:blank' ? 'home' : 'complete',
      canGoBack: false,
      canGoForward: false,
      audible: false,
      muted: false,
      isPinned: false,
      closeGuard: false,
      createdAt: tab.createdAt,
      lastActiveAt: tab.lastActiveAt,
    };
  }

  private cloneSession(session: BrowserWindowSession): BrowserWindowSession {
    const tabIds: TabId[] = [];
    session.tabIds.forEach(tabId => tabIds.push(tabId));
    return {
      id: session.id,
      tabIds,
      activeTabId: session.activeTabId,
      isPrivateWindow: session.isPrivateWindow,
      createdAt: session.createdAt,
      lastActiveAt: session.lastActiveAt,
    };
  }
}
