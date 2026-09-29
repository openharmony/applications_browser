// NavigationController：管理导航行为与每个标签页的历史栈。

import { NavigationEntry, TabId, UrlString } from './types';
import { isSameHttpNavigationUrl } from './urlNormalizer';

export class NavigationController {
  private histories: Map<TabId, NavigationEntry[]> = new Map();
  private positions: Map<TabId, number> = new Map();

  navigateTo(tabId: TabId, url: UrlString): void {
    const entry: NavigationEntry = {
      url,
      timestamp: Date.now(),
    };
    const history = this.histories.get(tabId) ?? [];
    const currentPos = this.positions.get(tabId);
    const currentUrl = currentPos !== undefined ? history[currentPos]?.url : undefined;

    if (isSameHttpNavigationUrl(currentUrl, url)) {
      return;
    }

    if (currentPos !== undefined && currentPos < history.length - 1) {
      history.splice(currentPos + 1);
    }
    history.push(entry);
    this.histories.set(tabId, history);
    this.positions.set(tabId, history.length - 1);
  }

  ensureCurrentEntry(tabId: TabId, url: UrlString): void {
    const history = this.histories.get(tabId) ?? [];
    if (history.length > 0) {
      return;
    }
    this.navigateTo(tabId, url);
  }

  replaceCurrentEntry(tabId: TabId, url: UrlString): void {
    const history = this.histories.get(tabId) ?? [];
    const pos = this.positions.get(tabId);
    if (history.length === 0 || pos === undefined || pos < 0 || pos >= history.length) {
      this.navigateTo(tabId, url);
      return;
    }
    if (isSameHttpNavigationUrl(history[pos]?.url, url)) {
      return;
    }
    history[pos] = {
      url,
      timestamp: Date.now(),
    };
    this.histories.set(tabId, history);
  }

  syncWithPageNavigation(tabId: TabId, url: UrlString): void {
    const history = this.histories.get(tabId) ?? [];
    if (history.length === 0) {
      this.navigateTo(tabId, url);
      return;
    }

    const currentPos = this.resolvePosition(tabId, history);
    const currentUrl = history[currentPos]?.url;
    if (isSameHttpNavigationUrl(currentUrl, url)) {
      return;
    }

    const previousUrl = currentPos > 0 ? history[currentPos - 1]?.url : undefined;
    if (isSameHttpNavigationUrl(previousUrl, url)) {
      this.positions.set(tabId, currentPos - 1);
      return;
    }

    const nextUrl = currentPos < history.length - 1 ? history[currentPos + 1]?.url : undefined;
    if (isSameHttpNavigationUrl(nextUrl, url)) {
      this.positions.set(tabId, currentPos + 1);
      return;
    }

    history.splice(currentPos + 1);
    history.push({
      url,
      timestamp: Date.now(),
    });
    this.histories.set(tabId, history);
    this.positions.set(tabId, history.length - 1);
  }

  canGoBack(tabId: TabId): boolean {
    const pos = this.positions.get(tabId);
    return pos !== undefined && pos > 0;
  }

  canGoForward(tabId: TabId): boolean {
    const pos = this.positions.get(tabId);
    const history = this.histories.get(tabId);
    return pos !== undefined && history !== undefined && pos < history.length - 1;
  }

  goBack(tabId: TabId): UrlString | null {
    if (!this.canGoBack(tabId)) {
      return null;
    }
    const pos = (this.positions.get(tabId) as number) - 1;
    this.positions.set(tabId, pos);
    return this.histories.get(tabId)?.[pos].url ?? null;
  }

  peekBack(tabId: TabId): UrlString | null {
    if (!this.canGoBack(tabId)) {
      return null;
    }
    const pos = (this.positions.get(tabId) as number) - 1;
    return this.histories.get(tabId)?.[pos].url ?? null;
  }

  goForward(tabId: TabId): UrlString | null {
    if (!this.canGoForward(tabId)) {
      return null;
    }
    const pos = (this.positions.get(tabId) as number) + 1;
    this.positions.set(tabId, pos);
    return this.histories.get(tabId)?.[pos].url ?? null;
  }

  peekForward(tabId: TabId): UrlString | null {
    if (!this.canGoForward(tabId)) {
      return null;
    }
    const pos = (this.positions.get(tabId) as number) + 1;
    return this.histories.get(tabId)?.[pos].url ?? null;
  }

  clear(tabId: TabId): void {
    this.histories.delete(tabId);
    this.positions.delete(tabId);
  }

  private resolvePosition(tabId: TabId, history: NavigationEntry[]): number {
    const currentPos = this.positions.get(tabId);
    if (currentPos === undefined || currentPos < 0) {
      return history.length - 1;
    }
    if (currentPos >= history.length) {
      return history.length - 1;
    }
    return currentPos;
  }
}
