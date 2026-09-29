// OH Browser 核心共享类型定义。

export interface TabId extends String {
}

export interface WindowId extends String {
}

export type UrlString = string;

export type TabLoadState = 'home' | 'loading' | 'complete' | 'failed';


export interface Tab {
  id: TabId;
  windowId: WindowId;
  title: string;
  url: UrlString;
  faviconUrl?: UrlString;
  pendingUrl?: UrlString;
  isActive: boolean;
  isPrivate: boolean;
  isLoading: boolean;
  loadState: TabLoadState;
  canGoBack: boolean;
  canGoForward: boolean;
  audible: boolean;
  muted: boolean;
  /** Legacy session field; pinned tabs are no longer supported. */
  isPinned?: boolean;
  /** 页面存在 beforeunload 或其他关闭前确认时，由上层决定是否拦截关闭。 */
  closeGuard?: boolean;
  createdAt: number;
  lastActiveAt: number;
}

export interface BrowserWindowSession {
  id: WindowId;
  tabIds: TabId[];
  activeTabId: TabId | null;
  isPrivateWindow: boolean;
  createdAt: number;
  lastActiveAt: number;
}

export interface NavigationEntry {
  url: UrlString;
  title?: string;
  timestamp: number;
}
