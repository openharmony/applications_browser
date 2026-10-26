// SessionManager：会话持久化与恢复（窗口 + 标签页）。

import { preferences } from '@kit.ArkData';
import { BrowserWindowSession, Tab } from './types';

export interface BrowserSessionSnapshot {
  version: number;
  windows: BrowserWindowSession[];
  tabs: Tab[];
  recentlyClosedTabs?: ClosedTabSessionRecord[];
  activeWindowId: string;
  savedAt: number;
}

export interface ClosedTabSessionRecord {
  tab: Tab;
  insertIndex: number;
  closedAt: number;
}

export class SessionManager {
  private static instance: SessionManager = new SessionManager();
  private readonly STORE_NAME: string = 'browser_session_store';
  private readonly SESSION_KEY: string = 'last_regular_session';
  private store: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;
  private pendingSave: Promise<void> | null = null;
  private queuedSnapshot: BrowserSessionSnapshot | null = null;

  static getInstance(): SessionManager {
    return SessionManager.instance;
  }

  async init(context: object): Promise<void> {
    if (this.store) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.openStore(context)
      .then((store: preferences.Preferences | null) => {
        if (!store) {
          return;
        }
        this.store = store;
      })
      .finally(() => {
        this.initPromise = null;
      });
    return this.initPromise;
  }

  private async openStore(context: object): Promise<preferences.Preferences | null> {
    try {
      return await preferences.getPreferences(context as never, this.STORE_NAME);
    } catch (_) {
      return null;
    }
  }

  async restoreSession(): Promise<BrowserSessionSnapshot | null> {
    if (!this.store && this.initPromise) {
      await this.initPromise;
    }
    if (!this.store) {
      return null;
    }

    try {
      const rawValue = await this.store.get(this.SESSION_KEY, '');
      if (typeof rawValue !== 'string' || rawValue.trim().length === 0) {
        return null;
      }
      const parsed = JSON.parse(rawValue) as BrowserSessionSnapshot;
      if (!this.isValidSnapshot(parsed)) {
        return null;
      }
      return this.cloneSnapshot(parsed);
    } catch (_) {
      return null;
    }
  }

  saveSession(snapshot: BrowserSessionSnapshot): void {
    if (!this.store) {
      if (this.initPromise) {
        const deferredSnapshot = this.cloneSnapshot(snapshot);
        this.initPromise
          .then(() => this.saveSession(deferredSnapshot))
          .catch(() => {
          });
      }
      return;
    }

    if (this.pendingSave) {
      this.queuedSnapshot = this.cloneSnapshot(snapshot);
      return;
    }

    const sanitized = this.sanitizeSnapshot(snapshot);
    const serialized = JSON.stringify(sanitized);
    this.pendingSave = this.store.put(this.SESSION_KEY, serialized)
      .then(() => this.store ? this.store.flush() : Promise.resolve())
      .catch(() => {
      })
      .finally(() => {
        this.pendingSave = null;
        const nextSnapshot = this.queuedSnapshot;
        this.queuedSnapshot = null;
        if (nextSnapshot) {
          this.saveSession(nextSnapshot);
        }
      });
  }

  async clearSession(): Promise<void> {
    if (!this.store) {
      return;
    }
    try {
      await this.store.put(this.SESSION_KEY, '');
      await this.store.flush();
    } catch (_) {
    }
  }

  private sanitizeSnapshot(snapshot: BrowserSessionSnapshot): BrowserSessionSnapshot {
    const tabs = snapshot.tabs
      .filter((tab: Tab) => !tab.isPrivate)
      .map((tab: Tab) => this.cloneTabForPersistence(tab));
    const validTabIds = new Set<string>();
    tabs.forEach((tab: Tab) => validTabIds.add(String(tab.id)));

    const windows: BrowserWindowSession[] = snapshot.windows
      .filter((windowSession: BrowserWindowSession) => !windowSession.isPrivateWindow)
      .map((windowSession: BrowserWindowSession): BrowserWindowSession => {
        const tabIds = windowSession.tabIds.filter((tabId): boolean => validTabIds.has(String(tabId)));
        const hasActiveTab = windowSession.activeTabId &&
          validTabIds.has(String(windowSession.activeTabId));
        const activeTabId = hasActiveTab ? windowSession.activeTabId : (tabIds[0] ?? null);
        const sanitizedWindow: BrowserWindowSession = {
          id: windowSession.id,
          tabIds,
          activeTabId,
          isPrivateWindow: false,
          createdAt: windowSession.createdAt,
          lastActiveAt: windowSession.lastActiveAt,
        };
        return sanitizedWindow;
      })
      .filter((windowSession: BrowserWindowSession) => windowSession.tabIds.length > 0);

    return {
      version: 1,
      windows,
      tabs,
      recentlyClosedTabs: this.sanitizeClosedTabs(snapshot.recentlyClosedTabs ?? []),
      activeWindowId: snapshot.activeWindowId || 'window_main',
      savedAt: Date.now(),
    };
  }

  private isValidSnapshot(snapshot: BrowserSessionSnapshot): boolean {
    return !!snapshot && snapshot.version === 1 && Array.isArray(snapshot.windows) && Array.isArray(snapshot.tabs);
  }

  private cloneSnapshot(snapshot: BrowserSessionSnapshot): BrowserSessionSnapshot {
    return {
      version: snapshot.version,
      windows: snapshot.windows.map(
        (windowSession: BrowserWindowSession): BrowserWindowSession => this.cloneWindowSession(windowSession)
      ),
      tabs: snapshot.tabs.map((tab: Tab) => this.cloneTabForPersistence(tab)),
      recentlyClosedTabs: (snapshot.recentlyClosedTabs ?? []).map(
        (record: ClosedTabSessionRecord): ClosedTabSessionRecord => this.cloneClosedTabRecord(record)
      ),
      activeWindowId: snapshot.activeWindowId,
      savedAt: snapshot.savedAt,
    };
  }

  private sanitizeClosedTabs(records: ClosedTabSessionRecord[]): ClosedTabSessionRecord[] {
    const sanitized: ClosedTabSessionRecord[] = [];
    records.forEach((record: ClosedTabSessionRecord) => {
      if (!record || !record.tab || record.tab.isPrivate) {
        return;
      }
      sanitized.push(this.cloneClosedTabRecord(record));
    });
    return sanitized.slice(-20);
  }

  private cloneClosedTabRecord(record: ClosedTabSessionRecord): ClosedTabSessionRecord {
    return {
      tab: this.cloneTabForPersistence(record.tab),
      insertIndex: Math.max(0, record.insertIndex),
      closedAt: record.closedAt > 0 ? record.closedAt : Date.now(),
    };
  }

  private cloneTabForPersistence(tab: Tab): Tab {
    return {
      id: tab.id,
      windowId: tab.windowId,
      title: tab.title,
      url: tab.url,
      faviconUrl: tab.faviconUrl,
      pendingUrl: undefined,
      isActive: tab.isActive,
      isPrivate: false,
      isLoading: false,
      loadState: tab.url === 'about:blank' ? 'home' : 'complete',
      canGoBack: false,
      canGoForward: false,
      audible: false,
      muted: false,
      // Legacy field retained in the session schema for compatibility. The
      // current browser no longer supports pinned tabs.
      isPinned: false,
      closeGuard: false,
      createdAt: tab.createdAt,
      lastActiveAt: tab.lastActiveAt,
    };
  }

  private cloneWindowSession(windowSession: BrowserWindowSession): BrowserWindowSession {
    return {
      id: windowSession.id,
      tabIds: windowSession.tabIds.map((tabId) => tabId),
      activeTabId: windowSession.activeTabId,
      isPrivateWindow: windowSession.isPrivateWindow,
      createdAt: windowSession.createdAt,
      lastActiveAt: windowSession.lastActiveAt,
    };
  }
}
