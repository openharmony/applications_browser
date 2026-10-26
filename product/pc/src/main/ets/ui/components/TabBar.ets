// TabBar：标签栏（横向展示打开的标签，含新建/关闭等控制）。

import { Tab, TabId } from '../../core/types';
import { TabClosePresentation, TabDisplayMode, TabItem } from './TabItem';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MAX_TAB_WIDTH: number = 232;
const MIN_TAB_WIDTH: number = 44;
const TAB_GAP: number = 2;
const TAB_STRIP_GAP: number = 8;
const NEW_TAB_BUTTON_WIDTH: number = 30;
const TAB_BAR_HORIZONTAL_PADDING: number = 18;
const NORMAL_TAB_THRESHOLD: number = 180;
const COMPACT_TAB_THRESHOLD: number = 80;
const FAVICON_LOG_DOMAIN: number = 0x0000;
const FAVICON_LOG_TAG: string = 'FaviconTrace';

export interface TabFaviconPresentation {
  tabId: string;
  // A cached data URI may be available before a new PixelMap is created.
  // Keeping this nullable makes the presentation model safe for that case.
  favicon: PixelMap | null;
  revision: number;
  dataUri?: string;
  ownedByApp?: boolean;
  source?: 'fallback' | 'callback';
}

export interface TabContextMenuPosition {
  x: number;
  y: number;
}

@Component
export struct TabBar {
  @Prop tabs: Tab[] = [];
  @Prop activeTabId: string = '';
  @Prop runtimeFavicons: TabFaviconPresentation[] = [];

  @State private tabsViewportWidth: number = 0;
  @State private hoveredTabId: string = '';

  onTabSelect: (tabId: TabId) => void = () => {};
  onTabClose: (tabId: TabId) => void = () => {};
  onTabContextMenu: (tabId: TabId, index: number, position: TabContextMenuPosition) => void =
    (_tabId: TabId, _index: number, _position: TabContextMenuPosition): void => {};
  onTabToggleMute: (tabId: TabId) => void = (_tabId: TabId): void => {};
  onNewTab: () => void = () => {};

  aboutToAppear(): void {
    hilog.info(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG,
      'TAB_BAR_APPEAR tabs=%{public}d active=%{public}s runtimeEntries=%{public}d',
      this.tabs.length, this.activeTabId, this.runtimeFavicons.length);
  }

  private isActiveTab(tab: Tab): boolean {
    return String(tab.id) === this.activeTabId;
  }

  private getDisplayTitle(tab: Tab): string {
    if (tab.title && tab.title.trim().length > 0) {
      return tab.title;
    }
    if (tab.loadState === 'home') {
      if (tab.isPrivate) {
        return '无痕标签页';
      }
      return '新标签页';
    }
    if (tab.pendingUrl && tab.pendingUrl.trim().length > 0) {
      return tab.pendingUrl;
    }
    if (tab.url && tab.url.trim().length > 0) {
      return tab.url;
    }
    return '标签页';
  }

  private getTabRenderKey(tab: Tab): string {
    // Include the title in the key. ArkUI can retain a ForEach child with the
    // same tab id while the tab model object is replaced asynchronously by a
    // page-title callback; recreating that item guarantees the new title is
    // bound to Text instead of leaving the initial placeholder rendered.
    const faviconUrl = tab.faviconUrl ? tab.faviconUrl.trim() : '';
    const runtimeRevision = this.getRuntimeFaviconRevision(tab.id);
    const title = this.getDisplayTitle(tab);
    // The audio indicator changes without any title/url transition. ForEach
    // reuses a child whose key is unchanged and then never re-applies its
    // @Prop values, so the tab would keep rendering the audio state it was
    // created with (usually "silent") no matter what the model says. Folding
    // the audio state into the key is what makes the speaker icon appear and
    // switch on the tab strip.
    const audioKey = `${tab.audible ? 'a' : '-'}${tab.muted ? 'm' : '-'}`;
    const key = `${String(tab.id)}:${tab.url}:${title}:${audioKey}`;
    hilog.info(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG,
      'TAB_KEY tab=%{public}s key=%{public}s url=%{public}s faviconUrl=%{public}s ' +
      'title=%{public}s runtimeRevision=%{public}d runtime=%{public}s dataUriLength=%{public}d loading=%{public}s',
      String(tab.id), key, tab.url, faviconUrl, title, runtimeRevision,
      String(this.getRuntimeFavicon(tab.id) !== null), this.getRuntimeFaviconDataUri(tab.id).length,
      String(tab.isLoading));
    return key;
  }

  private getRuntimeFavicon(tabId: TabId): PixelMap | null {
    const entry = this.runtimeFavicons.find((item: TabFaviconPresentation) => item.tabId === String(tabId));
    return entry?.favicon ?? null;
  }

  private getRuntimeFaviconDataUri(tabId: TabId): string {
    const entry = this.runtimeFavicons.find((item: TabFaviconPresentation) => item.tabId === String(tabId));
    return entry?.dataUri ?? '';
  }

  private getRuntimeFaviconSource(tabId: TabId): 'fallback' | 'callback' {
    const entry = this.runtimeFavicons.find((item: TabFaviconPresentation) => item.tabId === String(tabId));
    return entry?.source ?? 'callback';
  }

  private getRuntimeFaviconRevision(tabId: TabId): number {
    const entry = this.runtimeFavicons.find((item: TabFaviconPresentation) => item.tabId === String(tabId));
    return entry ? entry.revision : 0;
  }

  private getAvailableTabsWidth(): number {
    if (this.tabsViewportWidth <= 0) {
      return 0;
    }
    const availableWidth = this.tabsViewportWidth - TAB_BAR_HORIZONTAL_PADDING - NEW_TAB_BUTTON_WIDTH - TAB_STRIP_GAP;
    return availableWidth > 0 ? availableWidth : 0;
  }

  private getComputedTabWidth(): number {
    const tabCount = this.tabs.length;
    if (tabCount <= 0) {
      return MAX_TAB_WIDTH;
    }

    const availableWidth = this.getAvailableTabsWidth();
    if (availableWidth <= 0) {
      return MAX_TAB_WIDTH;
    }

    const totalGapWidth = TAB_GAP * (tabCount - 1);
    const candidateWidth = Math.floor((availableWidth - totalGapWidth) / tabCount);
    if (candidateWidth >= MAX_TAB_WIDTH) {
      return MAX_TAB_WIDTH;
    }
    if (candidateWidth <= MIN_TAB_WIDTH) {
      return MIN_TAB_WIDTH;
    }
    return candidateWidth;
  }

  private getTabDisplayMode(tabWidth: number): TabDisplayMode {
    if (tabWidth >= NORMAL_TAB_THRESHOLD) {
      return 'normal';
    }
    if (tabWidth >= COMPACT_TAB_THRESHOLD) {
      return 'compact';
    }
    return 'iconOnly';
  }

  private getTabsContentWidth(tabWidth: number): number {
    const tabCount = this.tabs.length;
    if (tabCount <= 0) {
      return 0;
    }
    return (tabWidth * tabCount) + (TAB_GAP * (tabCount - 1));
  }

  private getTabsViewportDisplayWidth(tabWidth: number): number {
    const contentWidth = this.getTabsContentWidth(tabWidth);
    const availableWidth = this.getAvailableTabsWidth();
    if (availableWidth <= 0) {
      return contentWidth;
    }
    return contentWidth < availableWidth ? contentWidth : availableWidth;
  }

  private isInteractingTab(tab: Tab): boolean {
    return this.isActiveTab(tab) || this.hoveredTabId === String(tab.id);
  }

  private getClosePresentation(tab: Tab, tabWidth: number, displayMode: TabDisplayMode): TabClosePresentation {
    if (this.tabs.length <= 1) {
      return 'hidden';
    }

    if (!this.isInteractingTab(tab)) {
      return 'hidden';
    }
    return 'trailing';
  }

  private handleTabHoverIn(tabId: TabId): void {
    this.hoveredTabId = String(tabId);
  }

  private handleTabHoverOut(tabId: TabId): void {
    if (this.hoveredTabId !== String(tabId)) {
      return;
    }
    this.hoveredTabId = '';
  }

  private resolveTabsViewportWidth(newValue: Area): void {
    const nextWidth = Number(newValue.width);
    if (nextWidth > 0 && nextWidth !== this.tabsViewportWidth) {
      this.tabsViewportWidth = nextWidth;
    }
  }

  private resolveTabContextMenuPosition(event: MouseEvent): TabContextMenuPosition {
    // windowX/windowY are in the same coordinate space as the root page Stack.
    // Keep fallbacks for older previewers that may not populate the window
    // fields, but never pass NaN into an absolute-positioned menu.
    const candidatesX: number[] = [Number(event.windowX), Number(event.displayX), Number(event.x)];
    const candidatesY: number[] = [Number(event.windowY), Number(event.displayY), Number(event.y)];
    const x = candidatesX.find((value: number) => Number.isFinite(value) && value >= 0) ?? 0;
    const y = candidatesY.find((value: number) => Number.isFinite(value) && value >= 0) ?? 0;
    return { x, y };
  }

  build() {
    Row({ space: TAB_STRIP_GAP }) {
      Scroll() {
        Row({ space: TAB_GAP }) {
          if (this.tabs.length === 0) {
            Text('暂无标签页')
              .fontSize(12)
              .fontColor('#7a8390');
          } else {
            ForEach(this.tabs, (tab: Tab) => {
              TabItem({
                tabId: String(tab.id),
                title: this.getDisplayTitle(tab),
                faviconUrl: tab.faviconUrl,
                favicon: this.getRuntimeFavicon(tab.id),
                runtimeFaviconSource: this.getRuntimeFaviconSource(tab.id),
                faviconDataUri: this.getRuntimeFaviconDataUri(tab.id),
                tabWidth: this.getComputedTabWidth(),
                displayMode: this.getTabDisplayMode(this.getComputedTabWidth()),
                closePresentation: this.getClosePresentation(
                  tab,
                  this.getComputedTabWidth(),
                  this.getTabDisplayMode(this.getComputedTabWidth()),
                ),
                isActive: this.isActiveTab(tab),
                isLoading: tab.isLoading,
                isPrivate: tab.isPrivate,
                audible: tab.audible,
                muted: tab.muted,
                canClose: this.tabs.length > 1 && tab.closeGuard !== true,
                onSelect: () => this.onTabSelect(tab.id),
                onClose: () => this.onTabClose(tab.id),
                onPointerMouse: (event: MouseEvent) => {
                  // ArkUI's component MouseAction enum maps BUTTON_DOWN to 2.
                  // Use the numeric value here because @kit.InputKit exports a
                  // different multimodal Action type than the component event.
                  if (event.button === 2 && Number(event.action) === 2) {
                    const index = this.tabs.findIndex((item: Tab) => String(item.id) === String(tab.id));
                    this.onTabContextMenu(tab.id, index, this.resolveTabContextMenuPosition(event));
                  }
                },
                onToggleMute: () => {
                  if (tab.audible || tab.muted) {
                    this.onTabToggleMute(tab.id);
                  }
                },
                onHoverIn: () => this.handleTabHoverIn(tab.id),
                onHoverOut: () => this.handleTabHoverOut(tab.id),
              });
            }, (tab: Tab) => this.getTabRenderKey(tab));
          }
        }
        .width(this.tabs.length > 0 ? this.getTabsContentWidth(this.getComputedTabWidth()) : 0)
        .justifyContent(FlexAlign.Start);
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width(this.getTabsViewportDisplayWidth(this.getComputedTabWidth()));

      Button('+')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#4b5563')
        .width(30)
        .height(30)
        .padding(0)
        .backgroundColor('#00000000')
        .borderRadius(15)
        .onClick(() => this.onNewTab());
    }
    .width('100%')
    // 与外层 40px 标签栏完全等高，避免激活标签底部留下 2px 的灰色空隙，
    // 从而在标签栏与地址栏工具行之间形成类似分割线的视觉效果。
    .height(40)
    .padding({ left: 8, right: 10, top: 8, bottom: 0 })
    .onAreaChange((_oldValue: Area, newValue: Area) => this.resolveTabsViewportWidth(newValue))
    .backgroundColor('#00000000');
  }
}
