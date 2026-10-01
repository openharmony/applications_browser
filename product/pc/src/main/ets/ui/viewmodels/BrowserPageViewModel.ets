// BrowserPageViewModel：浏览页（BrowserPage）的状态编排。

import { AddressInputResolver } from '../../core/addressInputResolver';
import { NavigationController } from '../../core/navigationController';
import { SearchEngineId, SearchEngineManager } from '../../core/searchEngineManager';
import { BrowserSessionSnapshot, SessionManager } from '../../core/sessionManager';
import { SettingsManager } from '../../core/settingsManager';
import { TabManager } from '../../core/tabManager';
import { Tab, TabId, UrlString } from '../../core/types';

export interface BrowserPageViewState {
  tabs: Tab[];
  activeTabId: string;
  addressText: string;
  showHome: boolean;
  currentUrl: string;
  canGoBack: boolean;
  canGoForward: boolean;
  isPrivate: boolean;
}

export class BrowserPageViewModel {
  private readonly tabManager: TabManager;
  private readonly navigationController: NavigationController;
  private readonly searchEngineManager: SearchEngineManager;
  private readonly addressInputResolver: AddressInputResolver;
  private readonly sessionManager: SessionManager;

  constructor(tabManager?: TabManager, navigationController?: NavigationController, sessionManager?: SessionManager) {
    this.tabManager = tabManager ?? new TabManager();
    this.navigationController = navigationController ?? new NavigationController();
    this.sessionManager = sessionManager ?? SessionManager.getInstance();
    this.searchEngineManager = new SearchEngineManager(SettingsManager.getInstance());
    this.addressInputResolver = new AddressInputResolver(this.searchEngineManager);
  }

  getInitialState(): BrowserPageViewState {
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  async restoreLastSession(shouldRestore: () => boolean = (): boolean => true): Promise<BrowserPageViewState> {
    const snapshot = await this.sessionManager.restoreSession();
    // Session loading is asynchronous. Let the caller cancel before the
    // snapshot mutates the live tab manager; returning the current state keeps
    // a user's interaction that happened while preferences were loading.
    if (!shouldRestore()) {
      return this.getViewState();
    }
    if (snapshot) {
      this.tabManager.restoreFromSessionSnapshot(snapshot);
    }
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  persistCurrentSession(): void {
    const snapshot: BrowserSessionSnapshot = this.tabManager.exportSessionSnapshot();
    this.sessionManager.saveSession(snapshot);
  }

  getViewState(): BrowserPageViewState {
    this.ensureAtLeastOneTab();
    const tabs = this.tabManager.getTabs();
    const activeTab = this.tabManager.getActiveTab();

    if (!activeTab) {
      return this.getEmptyViewState();
    }

    return {
      tabs,
      activeTabId: String(activeTab.id),
      addressText: this.resolveAddressText(activeTab),
      showHome: activeTab.loadState === 'home',
      currentUrl: activeTab.url,
      canGoBack: activeTab.canGoBack,
      canGoForward: activeTab.canGoForward,
      isPrivate: activeTab.isPrivate,
    };
  }

  newTab(isPrivate: boolean = false): BrowserPageViewState {
    this.tabManager.createTab('', isPrivate);
    return this.getViewState();
  }

  newTabWithUrl(url: string, isPrivate: boolean = false): BrowserPageViewState {
    const normalizedUrl = url.trim();
    if (!normalizedUrl) {
      return this.newTab(isPrivate);
    }
    this.tabManager.createTab(normalizedUrl, isPrivate);
    return this.getViewState();
  }

  selectTab(tabId: TabId): BrowserPageViewState {
    this.tabManager.setActiveTab(tabId);
    return this.getViewState();
  }

  closeTab(tabId: TabId): BrowserPageViewState {
    this.tabManager.closeTab(tabId);
    this.navigationController.clear(tabId);
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  closeTabs(tabIds: TabId[]): BrowserPageViewState {
    const closedTabs = this.tabManager.closeTabs(tabIds);
    closedTabs.forEach((tab: Tab) => this.navigationController.clear(tab.id));
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  closeOtherTabs(targetTabId: TabId): BrowserPageViewState {
    const closedTabs = this.tabManager.closeOtherTabs(targetTabId);
    closedTabs.forEach((tab: Tab) => this.navigationController.clear(tab.id));
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  closeTabsToRight(targetTabId: TabId): BrowserPageViewState {
    const closedTabs = this.tabManager.closeTabsToRight(targetTabId);
    closedTabs.forEach((tab: Tab) => this.navigationController.clear(tab.id));
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  canCloseTab(tabId: TabId): boolean {
    return this.tabManager.canCloseTab(tabId);
  }

  canRestoreLastClosedTab(): boolean {
    return this.tabManager.hasRecentlyClosedTab();
  }

  updateTabMute(tabId: TabId, muted: boolean): BrowserPageViewState {
    this.tabManager.updateTab(tabId, { muted });
    return this.getViewState();
  }

  updateTabAudio(tabId: TabId, audible: boolean): BrowserPageViewState {
    this.tabManager.updateTab(tabId, { audible });
    return this.getViewState();
  }

  restoreLastClosedTab(): BrowserPageViewState {
    const restoredTab = this.tabManager.restoreLastClosedTab();
    if (restoredTab) {
      this.navigationController.clear(restoredTab.id);
      this.tabManager.updateTabNavigationState(restoredTab.id, false, false);
    }
    this.ensureAtLeastOneTab();
    return this.getViewState();
  }

  updateAddressDraft(value: string): BrowserPageViewState {
    const activeTab = this.tabManager.getActiveTab();
    if (!activeTab) {
      return this.getViewState();
    }

    this.tabManager.updateTab(activeTab.id, {
      pendingUrl: value,
    });
    return this.getViewState();
  }

  submitAddress(value: string): BrowserPageViewState {
    const activeTab = this.tabManager.getActiveTab();
    if (!activeTab) {
      return this.getViewState();
    }

    const resolved = this.addressInputResolver.resolve(value);
    if (resolved.kind === 'empty' || !resolved.targetUrl) {
      this.tabManager.updateTab(activeTab.id, {
        pendingUrl: undefined,
      });
      return this.getViewState();
    }

    this.seedNavigationFromCurrentTab(activeTab);
    this.navigationController.navigateTo(activeTab.id, resolved.targetUrl);
    this.tabManager.updateTabLoadState(
      activeTab.id, 'loading', this.resolveLoadingTitle(resolved.targetUrl), resolved.targetUrl
    );
    this.tabManager.updateTabNavigationState(
      activeTab.id,
      this.navigationController.canGoBack(activeTab.id),
      this.navigationController.canGoForward(activeTab.id),
    );
    return this.getViewState();
  }

  setDefaultSearchEngine(engineId: SearchEngineId): BrowserPageViewState {
    this.searchEngineManager.setDefaultEngine(engineId);
    return this.getViewState();
  }

  goHome(): BrowserPageViewState {
    const activeTab = this.tabManager.getActiveTab();
    if (!activeTab) {
      return this.getViewState();
    }

    const homePageUrl = this.resolveHomePageUrl();
    if (homePageUrl !== 'about:blank') {
      this.seedNavigationFromCurrentTab(activeTab);
      this.navigationController.navigateTo(activeTab.id, homePageUrl);
      this.tabManager.updateTabLoadState(activeTab.id, 'loading', this.resolveLoadingTitle(homePageUrl), homePageUrl);
      this.tabManager.updateTabNavigationState(
        activeTab.id,
        this.navigationController.canGoBack(activeTab.id),
        this.navigationController.canGoForward(activeTab.id),
      );
      return this.getViewState();
    }

    const homeTitle = activeTab.isPrivate ? '无痕标签页' : '新标签页';

    this.navigationController.clear(activeTab.id);
    this.tabManager.updateTab(activeTab.id, {
      title: homeTitle,
      url: 'about:blank',
      faviconUrl: undefined,
      pendingUrl: undefined,
      isLoading: false,
      loadState: 'home',
      canGoBack: false,
      canGoForward: false,
    });
    return this.getViewState();
  }

  goBack(): BrowserPageViewState {
    const activeTab = this.tabManager.getActiveTab();
    if (!activeTab) {
      return this.getViewState();
    }

    const targetUrl = this.navigationController.goBack(activeTab.id);
    if (targetUrl) {
      this.tabManager.updateTabLoadState(activeTab.id, 'loading', this.resolveLoadingTitle(targetUrl), targetUrl);
      this.tabManager.updateTabNavigationState(
        activeTab.id,
        this.navigationController.canGoBack(activeTab.id),
        this.navigationController.canGoForward(activeTab.id),
      );
    }
    return this.getViewState();
  }

  goForward(): BrowserPageViewState {
    const activeTab = this.tabManager.getActiveTab();
    if (!activeTab) {
      return this.getViewState();
    }

    const targetUrl = this.navigationController.goForward(activeTab.id);
    if (targetUrl) {
      this.tabManager.updateTabLoadState(activeTab.id, 'loading', this.resolveLoadingTitle(targetUrl), targetUrl);
      this.tabManager.updateTabNavigationState(
        activeTab.id,
        this.navigationController.canGoBack(activeTab.id),
        this.navigationController.canGoForward(activeTab.id),
      );
    }
    return this.getViewState();
  }

  reloadActiveTab(): BrowserPageViewState {
    const activeTab = this.tabManager.getActiveTab();
    if (!activeTab) {
      return this.getViewState();
    }
    if (activeTab.loadState !== 'home') {
      this.tabManager.updateTabLoadState(
        activeTab.id, 'loading', this.resolveLoadingTitle(activeTab.url), activeTab.url
      );
    }
    return this.getViewState();
  }

  updateTabFromPageBegin(tabId: TabId, url: UrlString): BrowserPageViewState {
    this.seedNavigationFromExistingTab(tabId);
    this.navigationController.syncWithPageNavigation(tabId, url);
    this.tabManager.updateTabLoadState(tabId, 'loading', this.resolveLoadingTitle(url), url);
    this.tabManager.updateTabNavigationState(
      tabId,
      this.navigationController.canGoBack(tabId),
      this.navigationController.canGoForward(tabId),
    );
    this.tabManager.updateTab(tabId, {
      faviconUrl: this.resolveFaviconUrl(url),
    });
    return this.getViewState();
  }

  updateTabFromPageEnd(tabId: TabId, url: UrlString, title?: string): BrowserPageViewState {
    this.seedNavigationFromExistingTab(tabId);
    this.navigationController.syncWithPageNavigation(tabId, url);
    return this.completeTabLoad(tabId, url, title);
  }

  updateTabFromHistoryReplace(tabId: TabId, url: UrlString, title?: string): BrowserPageViewState {
    this.seedNavigationFromExistingTab(tabId);
    this.navigationController.replaceCurrentEntry(tabId, url);
    return this.completeTabLoad(tabId, url, title);
  }

  private completeTabLoad(tabId: TabId, url: UrlString, title?: string): BrowserPageViewState {
    const suppliedTitle = title ? title.trim() : '';
    const existingTab = this.tabManager.getTab(tabId);
    // onTitleReceive can arrive before PageEnd, while controller.getTitle()
    // still returns an empty string at PageEnd. Preserve that real title
    // instead of replacing it with the loading placeholder or host name.
    const loadingTitle = this.resolveLoadingTitle(url);
    const existingTitle = existingTab?.title?.trim() ?? '';
    const preservedTitle = existingTitle.length > 0 && existingTitle !== loadingTitle
      ? existingTitle
      : '';
    const nextTitle = suppliedTitle || preservedTitle || this.resolveCompletedTitle(url);
    this.tabManager.updateTabLoadState(tabId, 'complete', nextTitle, url);
    this.tabManager.updateTabNavigationState(
      tabId,
      this.navigationController.canGoBack(tabId),
      this.navigationController.canGoForward(tabId),
    );
    return this.getViewState();
  }

  updateTabFavicon(tabId: TabId, faviconUrl: string): BrowserPageViewState {
    const normalizedFaviconUrl = faviconUrl.trim();
    const tab = this.tabManager.getTab(tabId);
    if (!tab || tab.loadState === 'home' || normalizedFaviconUrl.length === 0) {
      return this.getViewState();
    }
    this.tabManager.updateTab(tabId, { faviconUrl: normalizedFaviconUrl });
    return this.getViewState();
  }

  updateTabLoadStopped(tabId: TabId): BrowserPageViewState {
    const tab = this.tabManager.getTab(tabId);
    if (!tab) {
      return this.getViewState();
    }
    this.tabManager.updateTabLoadState(tabId, 'complete', tab.title, tab.url);
    return this.getViewState();
  }

  updateTabTitle(tabId: TabId, title: string): BrowserPageViewState {
    const normalizedTitle = title.trim();
    const tab = this.tabManager.getTab(tabId);
    if (!tab || tab.loadState === 'home' || normalizedTitle.length === 0) {
      return this.getViewState();
    }
    this.tabManager.updateTab(tabId, { title: normalizedTitle });
    return this.getViewState();
  }

  updateTabLoadFailed(tabId: TabId, url: UrlString, title?: string): BrowserPageViewState {
    this.seedNavigationFromExistingTab(tabId);
    this.navigationController.syncWithPageNavigation(tabId, url);
    const nextTitle = this.resolveCompletedTitle(url, title);
    this.tabManager.updateTabLoadState(tabId, 'failed', nextTitle, url);
    this.tabManager.updateTabNavigationState(
      tabId,
      this.navigationController.canGoBack(tabId),
      this.navigationController.canGoForward(tabId),
    );
    this.tabManager.updateTab(tabId, {
      faviconUrl: undefined,
    });
    return this.getViewState();
  }

  updateNavigationState(tabId: TabId, canGoBack: boolean, canGoForward: boolean): BrowserPageViewState {
    this.tabManager.updateTabNavigationState(
      tabId,
      canGoBack,
      canGoForward,
    );
    return this.getViewState();
  }

  peekBack(tabId: TabId): UrlString | null {
    return this.navigationController.peekBack(tabId);
  }

  peekForward(tabId: TabId): UrlString | null {
    return this.navigationController.peekForward(tabId);
  }

  getActiveTabId(): TabId | null {
    return this.tabManager.getActiveTabId();
  }

  private ensureAtLeastOneTab(): void {
    if (this.tabManager.getTabs().length > 0) {
      return;
    }
    this.tabManager.createTab('');
  }

  private seedNavigationFromExistingTab(tabId: TabId): void {
    const tab = this.tabManager.getTab(tabId);
    if (!tab) {
      return;
    }
    this.seedNavigationFromCurrentTab(tab);
  }

  private seedNavigationFromCurrentTab(tab: Tab): void {
    if (tab.loadState === 'home') {
      return;
    }
    if (!tab.url || tab.url === 'about:blank') {
      return;
    }
    this.navigationController.ensureCurrentEntry(tab.id, tab.url);
  }

  private resolveAddressText(tab: Tab): string {
    if (tab.pendingUrl !== undefined) {
      return tab.pendingUrl;
    }
    if (tab.loadState === 'home') {
      return '';
    }
    return tab.url;
  }

  private resolveHomePageUrl(): string {
    const configuredUrl = SettingsManager.getInstance().getSettings().homePageUrl.trim();
    if (!configuredUrl || configuredUrl === 'about:blank') {
      return 'about:blank';
    }
    const resolved = this.addressInputResolver.resolve(configuredUrl);
    if (resolved.kind === 'empty' || !resolved.targetUrl) {
      return 'about:blank';
    }
    return resolved.targetUrl;
  }

  private resolveLoadingTitle(url: string): string {
    return this.extractDisplayHost(url) || '加载中';
  }

  private resolveCompletedTitle(url: string, title?: string): string {
    const nextTitle = title ? title.trim() : '';
    if (nextTitle.length > 0) {
      return nextTitle;
    }
    return this.extractDisplayHost(url) || url;
  }

  private extractDisplayHost(url: string): string {
    const trimmed = url.trim();
    if (!trimmed) {
      return '';
    }

    const matched = trimmed.match(/^https?:\/\/([^\/]+)/i);
    if (matched && matched[1]) {
      return matched[1];
    }

    if (trimmed === 'about:blank') {
      return '新标签页';
    }
    return trimmed;
  }

  private resolveFaviconUrl(url: string): string | undefined {
    const trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return undefined;
    }
    const matched = trimmed.match(/^(https?:\/\/[^\/?#]+)/i);
    if (!matched || !matched[1]) {
      return undefined;
    }
    return `${matched[1]}/favicon.ico`;
  }

  private getEmptyViewState(): BrowserPageViewState {
    return {
      tabs: [],
      activeTabId: '',
      addressText: '',
      showHome: true,
      currentUrl: 'about:blank',
      canGoBack: false,
      canGoForward: false,
      isPrivate: false,
    };
  }
}
