// SettingsPage: native browser settings center.

import { BrowserSettings, StartupBehavior } from '../../core/settingsManager';
import { ClearBrowsingDataOptions } from '../../core/privacyManager';
import { DownloadTask } from '../../core/downloadTypes';
import {
  getSitePermissionLabel,
  SitePermissionSetting,
  SitePermissionSettingDecision,
  SitePermissionType,
} from '../../core/permissionTypes';
import { SearchEngineDefinition, SearchEngineId } from '../../core/searchEngineManager';
import { fileUri } from '@kit.CoreFileKit';
import { UIAbilityContextWrapper } from '../../core/UIAbilityContextWrapper';
import { DownloadSettingsService } from '../../integration/downloadSettingsService';
import { ClipboardService } from '../../integration/clipboardService';
import { SettingsDownloadItem } from '../components/SettingsDownloadItem';
import { SettingsBookmarksManager } from '../components/SettingsBookmarksManager';
import { SettingsHistoryManager } from '../components/SettingsHistoryManager';
import { SettingsNavigationItem, SettingsSidebar } from '../components/SettingsSidebar';
import { DownloadsPageViewState, DownloadsViewModel } from '../viewmodels/DownloadsViewModel';
import { SettingsPageState, SettingsViewModel } from '../viewmodels/SettingsViewModel';
import {
  SiteSettingsPageState,
  SiteSettingsSiteSummary,
  SiteSettingsViewModel,
} from '../viewmodels/SiteSettingsViewModel';
import { SettingsLayoutPolicy } from '../settingsLayoutPolicy';

const EMPTY_SETTINGS_PAGE_STATE: SettingsPageState = {
  defaultSearchEngineId: 'baidu',
  defaultSearchEngineName: '百度',
  supportedSearchEngines: [],
  defaultZoomPercent: 100,
  downloadDirectoryUri: '',
  showDownloadsWhenFinished: true,
  homePageUrl: 'about:blank',
  startupBehavior: 'restore_session',
  javaScriptEnabled: true,
  imagesEnabled: true,
  doNotTrack: false,
  cookiesEnabled: true,
  blockThirdPartyCookies: false,
  blockThirdPartyCookiesInPrivate: false,
};

const SETTINGS_NAVIGATION_ITEMS: SettingsNavigationItem[] = [
  {
    id: 'search-engine',
    label: '搜索引擎',
    normalIcon: $r('app.media.settings_sidebar_search_engine_normal'),
    selectedIcon: $r('app.media.settings_sidebar_search_engine_selected'),
    enabled: true,
  },
  {
    id: 'browser-settings',
    label: '浏览设置',
    normalIcon: $r('app.media.settings_sidebar_browser_settings_normal'),
    selectedIcon: $r('app.media.settings_sidebar_browser_settings_selected'),
    enabled: true,
  },
  {
    id: 'download-settings-new',
    label: '下载设置',
    normalIcon: $r('app.media.settings_sidebar_download_settings_normal'),
    selectedIcon: $r('app.media.settings_sidebar_download_settings_selected'),
    enabled: true,
  },
  {
    id: 'site-settings',
    label: '网站设置',
    normalIcon: $r('app.media.settings_sidebar_site_settings_normal'),
    selectedIcon: $r('app.media.settings_sidebar_site_settings_selected'),
    enabled: true,
  },
  {
    id: 'bookmarks-manager',
    label: '书签管理',
    normalIcon: $r('app.media.settings_sidebar_bookmarks_normal'),
    selectedIcon: $r('app.media.settings_sidebar_bookmarks_selected'),
    enabled: true,
  },
  {
    id: 'startup-settings',
    label: '起始页设置',
    normalIcon: $r('app.media.settings_sidebar_startup_normal'),
    selectedIcon: $r('app.media.settings_sidebar_startup_selected'),
    enabled: true,
  },
  {
    id: 'history',
    label: '历史记录',
    normalIcon: $r('app.media.settings_sidebar_history_normal'),
    selectedIcon: $r('app.media.settings_sidebar_history_selected'),
    enabled: true,
  },
  {
    id: 'clear-data',
    label: '清除浏览数据',
    normalIcon: $r('app.media.settings_sidebar_clear_data_normal'),
    selectedIcon: $r('app.media.settings_sidebar_clear_data_selected'),
    enabled: true,
  },
  {
    id: 'default-browser',
    label: '默认浏览器',
    normalIcon: $r('app.media.settings_sidebar_default_browser_normal'),
    selectedIcon: $r('app.media.settings_sidebar_default_browser_selected'),
    enabled: false,
    visible: false,
  },
  {
    id: 'proxy-settings',
    label: '计算机代理设置',
    normalIcon: $r('app.media.settings_sidebar_proxy_settings_normal'),
    selectedIcon: $r('app.media.settings_sidebar_proxy_settings_selected'),
    enabled: false,
    visible: false,
  },
  {
    id: 'about',
    label: '关于',
    normalIcon: $r('app.media.settings_sidebar_about_normal'),
    selectedIcon: $r('app.media.settings_sidebar_about_selected'),
    enabled: true,
  },
];

// 隐藏开关：需要重新显示「浏览设置-网页缩放」入口时改为 true 即可（相关代码已完整保留）。
const SETTINGS_SHOW_DEFAULT_ZOOM_CONTROL: boolean = false;

const DEFAULT_ZOOM_VALUES: number[] = [25, 50, 75, 100, 125, 150, 200];

const EMPTY_DOWNLOADS_PAGE_STATE: DownloadsPageViewState = {
  downloads: [],
  filter: 'all',
  keyword: '',
  filteredCount: 0,
  totalCount: 0,
  activeCount: 0,
  completedCount: 0,
  failedCount: 0,
  finishedCount: 0,
};

const EMPTY_SITE_SETTINGS_PAGE_STATE: SiteSettingsPageState = {
  sites: [],
  totalSiteCount: 0,
  totalPermissionCount: 0,
};

const SITE_PERMISSION_TYPES: SitePermissionType[] = [
  'camera',
  'microphone',
  'location',
  'notifications',
  'clipboard-read',
  'clipboard-write',
];

const SITE_PERMISSION_DECISIONS: SitePermissionSettingDecision[] = ['ask', 'allow', 'deny'];

// About values mirror the product metadata shown by the settings design.
const ABOUT_VERSION: string = '1.0.0';
const ABOUT_BUILD_NUMBER: string = '12345';
const ABOUT_RELEASE_DATE: string = '2023-10-01';

@Component
export struct SettingsPage {
  // @Prop @Watch：设置页挂载期间，浏览器 3 点菜单仍可能切换目标 section
  // （搜索引擎 / 浏览设置 / 下载设置 / 网站设置 / 历史记录等）。
  // 若用普通字段，仅 aboutToAppear 读取一次，挂载后的变更全部丢失。
  @Prop @Watch('onInitialSectionIdChanged') initialSectionId: string = 'search-engine';
  onBack: () => void = (): void => {};
  onOpenUrl: (url: string) => void = (_: string): void => {};
  onOpenUrlInNewTab: (url: string) => void = (_: string): void => {};
  onOpenUrlInNewWindow: (url: string) => void = (_: string): void => {};
  onOpenUrlInPrivateWindow: (url: string) => void = (_: string): void => {};

  private readonly viewModel: SettingsViewModel = new SettingsViewModel();
  private readonly downloadsViewModel: DownloadsViewModel = new DownloadsViewModel();
  private readonly siteSettingsViewModel: SiteSettingsViewModel = new SiteSettingsViewModel();
  private readonly downloadSettingsService: DownloadSettingsService = new DownloadSettingsService();
  private readonly clipboardService: ClipboardService = new ClipboardService();
  private readonly settingsScroller: Scroller = new Scroller();
  private readonly settingsListener: (settings: BrowserSettings) => void = (_: BrowserSettings) => {
    this.viewState = this.viewModel.getState();
  };
  private readonly downloadsListener: (state: DownloadsPageViewState) => void = (state: DownloadsPageViewState) => {
    this.downloadsState = state;
    this.downloadsRenderRevision += 1;
  };

  @State private viewState: SettingsPageState = EMPTY_SETTINGS_PAGE_STATE;
  @State private activeSectionId: string = 'search-engine';
  @State private homePageUrl: string = 'about:blank';
  @State private viewportWidth: number = 1280;
  @State private isClearingBrowsingData: boolean = false;
  @State private clearBrowsingDataMessage: string = '';
  @State private clearHistorySelected: boolean = true;
  @State private clearDownloadsSelected: boolean = true;
  @State private clearSiteDataSelected: boolean = true;
  @State private clearSitePermissionsSelected: boolean = true;
  @State private showAddSearchEngineDialog: boolean = false;
  @State private showDeleteSearchEngineDialog: boolean = false;
  @State private searchEngineNameDraft: string = '';
  @State private searchEngineUrlDraft: string = '';
  @State private searchEngineDialogMessage: string = '';
  @State private pendingDeleteSearchEngineId: string = '';
  @State private pendingDeleteSearchEngineName: string = '';
  @State private downloadsState: DownloadsPageViewState = EMPTY_DOWNLOADS_PAGE_STATE;
  @State private downloadsRenderRevision: number = 0;
  @State private downloadOpenMessage: string = '';
  @State private downloadMessageIsError: boolean = false;
  @State private isClearingFinishedDownloads: boolean = false;
  @State private downloadUiBusyTaskId: string = '';
  @State private isChoosingDownloadDirectory: boolean = false;
  @State private downloadDirectoryMessage: string = '';
  @State private siteSettingsState: SiteSettingsPageState = EMPTY_SITE_SETTINGS_PAGE_STATE;
  @State private selectedSiteOrigin: string = '';
  @State private selectedSiteSettings: SitePermissionSetting[] = [];
  @State private sitePermissionFilter: SitePermissionType | undefined = undefined;
  @State private showMobileNavigation: boolean = false;
  @State private isSecondaryBackHovered: boolean = false;

  aboutToAppear(): void {
    this.activeSectionId = this.initialSectionId.trim() || 'search-engine';
    this.viewState = this.viewModel.getState();
    this.homePageUrl = this.viewState.homePageUrl;
    this.downloadsState = this.downloadsViewModel.getInitialState();
    this.siteSettingsState = this.siteSettingsViewModel.getState();
    this.viewModel.addSettingsListener(this.settingsListener);
    this.downloadsViewModel.addListener(this.downloadsListener);
  }

  aboutToDisappear(): void {
    this.viewModel.removeSettingsListener(this.settingsListener);
    this.downloadsViewModel.removeListener(this.downloadsListener);
  }

  private useCompactSidebar(): boolean {
    return SettingsLayoutPolicy.resolveNavigationMode(this.viewportWidth) === 'rail';
  }

  private showPersistentSidebar(): boolean {
    return SettingsLayoutPolicy.resolveNavigationMode(this.viewportWidth) !== 'drawer';
  }

  private useCompactContentLayout(): boolean {
    return SettingsLayoutPolicy.useCompactContent(this.viewportWidth);
  }

  private getContentPadding(): number {
    return SettingsLayoutPolicy.getContentPadding(this.viewportWidth);
  }

  @Builder
  private SecondaryBackButton(onClick: () => void) {
    Button() {
      Text('‹')
        .fontSize(28)
        .fontColor('#5f6368')
        .margin({ bottom: 3 });
    }
    .type(ButtonType.Circle)
    .width(44)
    .height(44)
    .padding(0)
    .hoverEffect(HoverEffect.None)
    .backgroundColor(this.isSecondaryBackHovered ? '#f1f3f4' : '#00000000')
    .borderRadius(22)
    .accessibilityText('返回')
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .mouseResponseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .onHover((isHover: boolean) => {
      this.isSecondaryBackHovered = isHover;
    })
    .onClick(onClick);
  }

  private updateViewportWidth(width: number): void {
    if (width > 0) {
      this.viewportWidth = width;
    }
  }

  /** 挂载期间 initialSectionId 变化（3 点菜单切换设置入口）时同步当前 section。 */
  private onInitialSectionIdChanged(): void {
    const nextSectionId = this.initialSectionId.trim() || 'search-engine';
    if (nextSectionId !== this.activeSectionId) {
      this.navigateToSection(nextSectionId);
    }
  }

  private navigateToSection(itemId: string): void {
    this.activeSectionId = itemId;
    this.showMobileNavigation = false;
    this.clearBrowsingDataMessage = '';
    this.downloadOpenMessage = '';
    this.downloadMessageIsError = false;
    if (itemId === 'site-settings') {
      this.sitePermissionFilter = undefined;
      this.siteSettingsState = this.siteSettingsViewModel.getState();
    }
    this.settingsScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 0 } });
  }

  private handleSearchEngineChange(engineId: SearchEngineId): void {
    this.viewState = this.viewModel.setDefaultSearchEngine(engineId);
  }

  private openAddSearchEngineDialog(): void {
    this.searchEngineNameDraft = '';
    this.searchEngineUrlDraft = '';
    this.searchEngineDialogMessage = '';
    this.showAddSearchEngineDialog = true;
  }

  private closeAddSearchEngineDialog(): void {
    this.showAddSearchEngineDialog = false;
    this.searchEngineDialogMessage = '';
  }

  private addSearchEngine(): void {
    try {
      this.viewState = this.viewModel.addSearchEngine(this.searchEngineNameDraft, this.searchEngineUrlDraft);
      this.closeAddSearchEngineDialog();
    } catch (error) {
      this.searchEngineDialogMessage = this.getSearchEngineErrorText(error instanceof Error ? error.message : '');
    }
  }

  private openDeleteSearchEngineDialog(engine: SearchEngineDefinition): void {
    if (engine.builtIn) {
      return;
    }
    this.pendingDeleteSearchEngineId = engine.id;
    this.pendingDeleteSearchEngineName = engine.name;
    this.showDeleteSearchEngineDialog = true;
  }

  private closeDeleteSearchEngineDialog(): void {
    this.showDeleteSearchEngineDialog = false;
    this.pendingDeleteSearchEngineId = '';
    this.pendingDeleteSearchEngineName = '';
  }

  private deletePendingSearchEngine(): void {
    if (!this.pendingDeleteSearchEngineId) {
      return;
    }
    this.viewState = this.viewModel.deleteSearchEngine(this.pendingDeleteSearchEngineId);
    this.closeDeleteSearchEngineDialog();
  }

  private getSearchEngineErrorText(code: string): string {
    if (code === 'search_engine_name_required') return '请输入搜索引擎名称';
    if (code === 'search_engine_name_too_long') return '名称不能超过 40 个字符';
    if (code === 'search_engine_url_must_be_http') return '查询网址必须以 http:// 或 https:// 开头';
    if (code === 'search_engine_url_requires_placeholder') return '查询网址必须包含 %s';
    if (code === 'search_engine_already_exists') return '该搜索引擎已经存在';
    return '无法添加搜索引擎';
  }

  private getSearchEngineDisplayTemplate(template: string): string {
    return template.split('{query}').join('%s');
  }

  private getDefaultZoomSelectedIndex(): number {
    const index = DEFAULT_ZOOM_VALUES.indexOf(this.viewState.defaultZoomPercent);
    return index >= 0 ? index : 3;
  }

  private handleHomePageUrlSubmit(value: string): void {
    this.viewState = this.viewModel.setHomePageUrl(value);
    this.homePageUrl = this.viewState.homePageUrl;
  }

  private handleResetHomePage(): void {
    this.homePageUrl = 'about:blank';
  }

  private isHomePageUrlDirty(): boolean {
    return this.homePageUrl !== this.viewState.homePageUrl;
  }

  private isSelectedSearchEngine(engineId: SearchEngineId): boolean {
    return this.viewState.defaultSearchEngineId === engineId;
  }

  private isSelectedStartupBehavior(behavior: StartupBehavior): boolean {
    return this.viewState.startupBehavior === behavior;
  }

  private clearSelectedBrowsingData(): void {
    const options: ClearBrowsingDataOptions = {
      history: this.clearHistorySelected,
      downloads: this.clearDownloadsSelected,
      siteData: this.clearSiteDataSelected,
      sitePermissions: this.clearSitePermissionsSelected,
    };
    if (!options.history && !options.downloads && !options.siteData && !options.sitePermissions) {
      this.clearBrowsingDataMessage = '请至少选择一项数据';
      return;
    }
    this.clearBrowsingData(options);
  }

  private clearBrowsingData(options: ClearBrowsingDataOptions): void {
    if (this.isClearingBrowsingData) {
      return;
    }

    this.isClearingBrowsingData = true;
    this.clearBrowsingDataMessage = '';
    this.viewModel.clearBrowsingData(options)
      .then((result) => {
        this.clearBrowsingDataMessage = result.success ? '清理完成' :
          `部分数据清理失败：${this.getClearBrowsingDataFailureText(result.failedItems)}`;
      })
      .catch(() => {
        this.clearBrowsingDataMessage = '清理失败';
      })
      .finally(() => {
        this.isClearingBrowsingData = false;
      });
  }

  private getClearBrowsingDataFailureText(failedItems: string[]): string {
    if (failedItems.length === 0) {
      return '未知原因';
    }
    return failedItems.map((item: string) => {
      if (item === 'history') return '历史记录';
      if (item === 'downloads') return '下载记录';
      if (item === 'siteData') return '站点数据';
      if (item === 'sitePermissions') return '站点权限';
      return item;
    }).join('、');
  }

  private chooseDownloadDirectory(): void {
    if (this.isChoosingDownloadDirectory) {
      return;
    }
    const context = UIAbilityContextWrapper.getCurrentContext();
    if (!context) {
      this.downloadDirectoryMessage = '暂时无法获取文件选择器上下文';
      return;
    }

    this.isChoosingDownloadDirectory = true;
    this.downloadDirectoryMessage = '';
    this.downloadSettingsService.chooseDownloadDirectory(context, this.viewState.downloadDirectoryUri)
      .then((directoryUri: string) => {
        if (directoryUri.trim().length > 0) {
          this.viewState = this.viewModel.setDownloadDirectoryUri(directoryUri);
          this.downloadDirectoryMessage = '下载目录已更新';
        }
      })
      .catch((error: Error) => {
        this.downloadDirectoryMessage = error.message || '选择下载目录失败';
      })
      .finally(() => {
        this.isChoosingDownloadDirectory = false;
      });
  }

  private resetDownloadDirectory(): void {
    this.viewState = this.viewModel.setDownloadDirectoryUri('');
    this.downloadDirectoryMessage = '已恢复系统默认下载目录';
  }

  private getDownloadDirectoryTitle(): string {
    return this.downloadSettingsService.getDirectoryDisplayName(this.viewState.downloadDirectoryUri);
  }

  private getDownloadDirectoryDescription(): string {
    const directoryUri = this.viewState.downloadDirectoryUri.trim();
    return directoryUri.length > 0 ? directoryUri : '由系统下载服务选择并管理保存位置';
  }

  private applyDownloadsState(state: DownloadsPageViewState): void {
    this.downloadsState = state;
    this.downloadsRenderRevision += 1;
  }

  /** 在系统文件管理器中打开下载文件所在目录。 */
  private async openDownloadedFolder(id: string): Promise<void> {
    if (!this.beginDownloadUiAction(id)) {
      return;
    }
    const task = this.downloadsViewModel.getDownload(id);
    const rawFilePath = task?.filePath?.trim() ?? '';
    if (!task || rawFilePath.length === 0) {
      this.downloadOpenMessage = '该下载尚未生成可定位的文件目录';
      this.downloadMessageIsError = true;
      this.endDownloadUiAction(id);
      return;
    }
    const context = UIAbilityContextWrapper.getCurrentContext();
    if (!context) {
      this.downloadOpenMessage = '暂时无法获取系统文件管理器';
      this.downloadMessageIsError = true;
      this.endDownloadUiAction(id);
      return;
    }

    let directoryUri = '';
    try {
      // FileUri 构造函数同时支持绝对路径和 file/datashare URI。
      // 对绝对路径直接构造可避免手工拼接 file:// 时丢失转义信息。
      const downloadFileUri = new fileUri.FileUri(rawFilePath);
      directoryUri = downloadFileUri.getFullDirectoryUri();
    } catch (_) {
      try {
        // 兼容部分系统返回的普通沙箱路径；getUriFromPath 会负责正确编码。
        const normalizedFileUri = fileUri.getUriFromPath(rawFilePath);
        directoryUri = new fileUri.FileUri(normalizedFileUri).getFullDirectoryUri();
      } catch (_) {
        this.downloadOpenMessage = '无法定位下载文件所在目录';
        this.downloadMessageIsError = true;
        this.endDownloadUiAction(id);
        return;
      }
    }

    if (directoryUri.trim().length === 0) {
      this.downloadOpenMessage = '无法定位下载文件所在目录';
      this.downloadMessageIsError = true;
      this.endDownloadUiAction(id);
      return;
    }

    // 通过 openLink('filemanager://openDirectory') 拉起系统文件管理器并定位到目录。
    // 若设备没有注册该链接，服务层会自动回退到 DocumentViewPicker(MIXED)。
    try {
      await this.downloadSettingsService.openDirectory(context, directoryUri);
      this.downloadOpenMessage = '';
      this.downloadMessageIsError = false;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // 取消文件选择器不应被当成下载打开失败；其它错误保留给用户。
      if (/cancel|取消|user.?abort|user.?cancel/i.test(message)) {
        this.downloadOpenMessage = '';
        this.downloadMessageIsError = false;
      } else {
        this.downloadOpenMessage = message || '无法打开文件所在目录';
        this.downloadMessageIsError = true;
      }
    } finally {
      this.endDownloadUiAction(id);
    }
  }

  private async copyDownloadUrl(id: string): Promise<void> {
    if (!this.beginDownloadUiAction(id)) {
      return;
    }
    const task = this.downloadsViewModel.getDownload(id);
    const sourceUrl = task?.sourceUrl?.trim() ?? '';
    if (sourceUrl.length === 0) {
      this.downloadOpenMessage = '当前下载没有可复制的链接';
      this.downloadMessageIsError = true;
      this.endDownloadUiAction(id);
      return;
    }
    try {
      const copied = await this.clipboardService.copyText(sourceUrl);
      this.downloadOpenMessage = copied ? '下载链接已复制' : '复制下载链接失败，请重试';
      this.downloadMessageIsError = !copied;
    } finally {
      this.endDownloadUiAction(id);
    }
  }

  private beginDownloadUiAction(id: string): boolean {
    if (this.downloadUiBusyTaskId.length > 0) {
      return false;
    }
    this.downloadUiBusyTaskId = id;
    this.downloadsRenderRevision += 1;
    return true;
  }

  private endDownloadUiAction(id: string): void {
    if (this.downloadUiBusyTaskId === id) {
      this.downloadUiBusyTaskId = '';
      this.downloadsRenderRevision += 1;
    }
  }

  private async clearFinishedDownloads(): Promise<void> {
    if (this.isClearingFinishedDownloads) {
      return;
    }
    this.isClearingFinishedDownloads = true;
    this.downloadOpenMessage = '';
    this.downloadMessageIsError = false;
    try {
      const result = await this.downloadsViewModel.clearFinishedAsync();
      this.downloadsState = this.downloadsViewModel.getViewState();
      if (!result.success) {
        this.downloadOpenMessage = result.errorMessage || '清除已结束任务失败，请重试';
        this.downloadMessageIsError = true;
      }
    } finally {
      this.isClearingFinishedDownloads = false;
      this.downloadsState = this.downloadsViewModel.getViewState();
    }
  }

  private async removeDownload(id: string): Promise<void> {
    const result = await this.downloadsViewModel.removeAsync(id);
    this.downloadsState = this.downloadsViewModel.getViewState();
    if (!result.success) {
      this.downloadOpenMessage = result.errorMessage || '删除下载记录失败，请重试';
      this.downloadMessageIsError = true;
    }
  }

  private openAllSites(permissionType?: SitePermissionType): void {
    this.sitePermissionFilter = permissionType;
    this.siteSettingsState = this.siteSettingsViewModel.getState(permissionType);
    this.navigateToSection('site-settings-all');
  }

  private openSiteDetail(origin: string): void {
    this.selectedSiteOrigin = origin;
    this.selectedSiteSettings = this.siteSettingsViewModel.getSiteSettings(origin);
    this.navigateToSection('site-detail');
  }

  private resetSelectedSite(): void {
    if (this.selectedSiteOrigin.length === 0) {
      return;
    }
    this.siteSettingsViewModel.resetSite(this.selectedSiteOrigin);
    this.siteSettingsState = this.siteSettingsViewModel.getState(this.sitePermissionFilter);
    this.selectedSiteSettings = [];
    this.navigateToSection('site-settings-all');
  }

  private setSelectedSitePermission(permissionType: SitePermissionType,
    decision: SitePermissionSettingDecision): void {
    this.selectedSiteSettings = this.siteSettingsViewModel.setPermissionDecision(
      this.selectedSiteOrigin,
      permissionType,
      decision,
    );
    this.siteSettingsState = this.siteSettingsViewModel.getState(this.sitePermissionFilter);
  }

  private getPermissionDecisionText(decision: SitePermissionSettingDecision): string {
    if (decision === 'allow') return '允许';
    if (decision === 'deny') return '禁止';
    return '询问';
  }

  private getPermissionDecisionIndex(decision: SitePermissionSettingDecision): number {
    const index = SITE_PERMISSION_DECISIONS.indexOf(decision);
    return index >= 0 ? index : 0;
  }

  private getAllSitesTitle(): string {
    return this.sitePermissionFilter ? getSitePermissionLabel(this.sitePermissionFilter) : '所有网站';
  }

  private getActiveSidebarItemId(): string {
    if (this.activeSectionId === 'manage-search-engine') return 'search-engine';
    if (this.activeSectionId === 'download-manager') return 'download-settings-new';
    if (this.activeSectionId === 'site-settings-all' || this.activeSectionId === 'site-detail' ||
      this.activeSectionId === 'cookie-settings' || this.activeSectionId === 'javascript-settings') {
      return 'site-settings';
    }
    return this.activeSectionId;
  }

  private getActiveNavigationLabel(): string {
    const activeItemId = this.getActiveSidebarItemId();
    const item = SETTINGS_NAVIGATION_ITEMS.find((navigationItem: SettingsNavigationItem) =>
      navigationItem.id === activeItemId);
    return item ? item.label : '设置';
  }

  private usesManagedListLayout(): boolean {
    return this.activeSectionId === 'bookmarks-manager' || this.activeSectionId === 'history' ||
      this.activeSectionId === 'download-manager';
  }

  private getActiveContentMaxWidth(): number {
    // The about design uses the full content pane while other sections stay readable.
    return this.activeSectionId === 'about' ? Math.max(1, this.viewportWidth) :
      SettingsLayoutPolicy.getContentMaxWidth();
  }

  @Builder
  private PageHeader(title: string) {
    Text(title)
      .width('100%')
      .fontSize(28)
      .fontWeight(FontWeight.Regular)
      .fontColor('#333333')
      .margin({ bottom: 24 });
  }

  @Builder
  private GroupTitle(title: string, topMargin: number = 0) {
    Text(title)
      .width('100%')
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor('#333333')
      .margin({ top: topMargin, bottom: 4 });
  }

  @Builder
  private AboutInfoRow(label: string, value: string, showDivider: boolean = true) {
    Row() {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor('#333333');

        Blank();

        Text(value)
          .fontSize(14)
          .fontColor('#333333')
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height('100%')
      .padding({ left: 42, right: 42 });
    }
    .width('100%')
    .height(44)
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' });
  }

  @Builder
  private AboutContent() {
    Column() {
      Row() {
        Text('关于')
          .fontSize(28)
          .fontWeight(FontWeight.Regular)
          .fontColor('#333333');
      }
      .height(68)
      .width('100%')
      .padding({ left: 42, right: 42, bottom: 20 })
      .border({ width: { bottom: 1 }, color: '#e0e0e0' });

      Column() {
        Text('浏览器信息')
          .width('100%')
          .fontSize(14)
          .fontColor('#333333')
          .padding({ left: 42, right: 42 })
          .margin({ top: 22, bottom: 4 });

        this.AboutInfoRow('版本', ABOUT_VERSION);
        this.AboutInfoRow('构建号', ABOUT_BUILD_NUMBER);
        this.AboutInfoRow('发布日期', ABOUT_RELEASE_DATE, false);
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private SettingSwitchRow(
    title: string,
    description: string,
    checked: boolean,
    onChange: (enabled: boolean) => void,
    showDivider: boolean = true,
    enabled: boolean = true,
  ) {
    if (this.useCompactContentLayout()) {
      Column({ space: 10 }) {
        Column({ space: 4 }) {
          Text(title)
            .fontSize(14)
            .fontColor('#333333');
          if (description.length > 0) {
            Text(description)
              .fontSize(12)
              .fontColor('#666666')
              .lineHeight(18);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);
        Row() {
          Toggle({ type: ToggleType.Switch, isOn: checked })
            .selectedColor('#1976d2')
            .enabled(enabled)
            .onChange((isOn: boolean) => onChange(isOn));
        }
        .width('100%')
        .justifyContent(FlexAlign.End);
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .opacity(enabled ? 1 : 0.5)
      .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' });
    } else {
      Row({ space: 20 }) {
        Column({ space: 4 }) {
          Text(title)
            .fontSize(14)
            .fontColor('#333333');
          if (description.length > 0) {
            Text(description)
              .fontSize(12)
              .fontColor('#666666')
              .lineHeight(18);
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        Toggle({ type: ToggleType.Switch, isOn: checked })
          .selectedColor('#1976d2')
          .enabled(enabled)
          .onChange((isOn: boolean) => onChange(isOn));
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ top: 12, bottom: 12 })
      .opacity(enabled ? 1 : 0.5)
      .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' });
    }
  }

  @Builder
  private SearchEngineRow(engine: SearchEngineDefinition, showDivider: boolean) {
    Row({ space: 16 }) {
      Column({ space: 4 }) {
        Text(engine.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333');

        Text(engine.searchUrlTemplate)
          .fontSize(12)
          .fontColor('#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Row() {
        if (this.isSelectedSearchEngine(engine.id)) {
          Text('✓')
            .fontSize(13)
            .fontColor('#ffffff');
        }
      }
      .width(20)
      .height(20)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      .border({ width: 1, color: this.isSelectedSearchEngine(engine.id) ? '#1976d2' : '#c7cbd1' })
      .backgroundColor(this.isSelectedSearchEngine(engine.id) ? '#1976d2' : '#ffffff');
    }
    .width('100%')
    .constraintSize({ minHeight: 62 })
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' })
    .onClick(() => this.handleSearchEngineChange(engine.id));
  }

  @Builder
  private SearchEngineManagementActions(engine: SearchEngineDefinition) {
    if (this.isSelectedSearchEngine(engine.id)) {
      Button('默认')
        .height(32)
        .fontSize(12)
        .fontColor('#666666')
        .backgroundColor('#e8eaed')
        .borderRadius(4)
        .enabled(false);
    } else {
      Button('设为默认')
        .height(32)
        .fontSize(12)
        .fontColor('#333333')
        .backgroundColor('#ffffff')
        .border({ width: 1, color: '#dddddd' })
        .borderRadius(4)
        .onClick(() => this.handleSearchEngineChange(engine.id));
    }
    if (!engine.builtIn) {
      Button('删除')
        .height(32)
        .fontSize(12)
        .fontColor('#d32f2f')
        .backgroundColor('#ffffff')
        .borderRadius(4)
        .onClick(() => this.openDeleteSearchEngineDialog(engine));
    }
  }

  @Builder
  private SearchEngineManagementRow(engine: SearchEngineDefinition, showDivider: boolean) {
    Column({ space: this.useCompactContentLayout() ? 10 : 0 }) {
      Row({ space: 18 }) {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(engine.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });

            if (engine.builtIn) {
              Text('内置')
                .fontSize(11)
                .fontColor('#666666')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('#f0f2f5')
                .borderRadius(4);
            }
          }

          Text(this.getSearchEngineDisplayTemplate(engine.searchUrlTemplate))
            .fontSize(12)
            .fontColor('#666666')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (!this.useCompactContentLayout()) {
          this.SearchEngineManagementActions(engine);
        }
      }
      .width('100%');

      if (this.useCompactContentLayout()) {
        Row({ space: 8 }) {
          this.SearchEngineManagementActions(engine);
        }
        .width('100%')
        .justifyContent(FlexAlign.End);
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' });
  }

  @Builder
  private StartupBehaviorRow(behavior: StartupBehavior, title: string, description: string, showDivider: boolean) {
    Row({ space: 16 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontColor('#333333');

        Text(description)
          .fontSize(12)
          .fontColor('#666666')
          .lineHeight(18);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Row() {
        if (this.isSelectedStartupBehavior(behavior)) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor('#1976d2');
        }
      }
      .width(20)
      .height(20)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      .border({ width: 2, color: this.isSelectedStartupBehavior(behavior) ? '#1976d2' : '#b8bdc5' });
    }
    .width('100%')
    .constraintSize({ minHeight: 62 })
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' })
    .onClick(() => {
      this.viewState = this.viewModel.setStartupBehavior(behavior);
    });
  }

  @Builder
  private ClearDataRow(title: string, description: string, selected: boolean, onChange: (selected: boolean) => void,
    showDivider: boolean = true) {
    Row({ space: 16 }) {
      Checkbox()
        .select(selected)
        .selectedColor('#1976d2')
        .onChange((value: boolean) => onChange(value));

      Column({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontColor('#333333');

        Text(description)
          .fontSize(12)
          .fontColor('#666666')
          .lineHeight(18);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .constraintSize({ minHeight: 58 })
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' });
  }

  @Builder
  private SearchEngineContent() {
    this.PageHeader('搜索引擎');
    Column() {
      this.GroupTitle('搜索引擎');
      Text(`地址栏搜索当前使用：${this.viewState.defaultSearchEngineName}`)
        .fontSize(12)
        .fontColor('#666666')
        .margin({ bottom: 8 });

      ForEach(this.viewState.supportedSearchEngines, (engine: SearchEngineDefinition, index: number) => {
        this.SearchEngineRow(engine, index < this.viewState.supportedSearchEngines.length - 1);
      }, (engine: SearchEngineDefinition) => engine.id);

      Row() {
        Column({ space: 4 }) {
          Text('管理搜索引擎')
            .fontSize(14)
            .fontColor('#333333');
          Text('添加、删除和设置默认搜索引擎')
            .fontSize(12)
            .fontColor('#666666');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Button('›')
          .width(34)
          .height(34)
          .fontSize(22)
          .fontColor('#666666')
          .backgroundColor('#ffffff')
          .borderRadius(17);
      }
      .width('100%')
      .constraintSize({ minHeight: 62 })
      .margin({ top: 8 })
      .padding({ top: 12, bottom: 4 })
      .border({ width: { top: 1 }, color: '#f0f2f5' })
      .onClick(() => {
        this.navigateToSection('manage-search-engine');
      });
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private ManageSearchEngineContent() {
    Row({ space: 12 }) {
      this.SecondaryBackButton(() => this.navigateToSection('search-engine'));

      Text('管理搜索引擎')
        .layoutWeight(1)
        .fontSize(28)
        .fontWeight(FontWeight.Regular)
        .fontColor('#333333');
    }
    .width('100%')
    .margin({ bottom: 24 });

    Column() {
      ForEach(this.viewState.supportedSearchEngines, (engine: SearchEngineDefinition, index: number) => {
        this.SearchEngineManagementRow(engine, index < this.viewState.supportedSearchEngines.length - 1);
      }, (engine: SearchEngineDefinition) => engine.id);

      Row() {
        Button('+  添加')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#1976d2')
          .borderRadius(4)
          .onClick(() => this.openAddSearchEngineDialog());
      }
      .width('100%')
      .padding({ top: 18 });
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private BrowserSettingsContent() {
    this.PageHeader('浏览设置');
    Column() {
      if (SETTINGS_SHOW_DEFAULT_ZOOM_CONTROL) {
        Row({ space: 20 }) {
          Column({ space: 4 }) {
            Text('网页缩放')
              .fontSize(14)
              .fontColor('#333333');
            Text('设置所有网站默认使用的缩放比例。')
              .fontSize(12)
              .fontColor('#666666');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Select([
            { value: '25%' },
            { value: '50%' },
            { value: '75%' },
            { value: '100%' },
            { value: '125%' },
            { value: '150%' },
            { value: '200%' },
          ])
            .selected(this.getDefaultZoomSelectedIndex())
            .value(`${this.viewState.defaultZoomPercent}%`)
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .onSelect((index: number) => {
              this.viewState = this.viewModel.setDefaultZoomPercent(DEFAULT_ZOOM_VALUES[index]);
            });
        }
        .width('100%')
        .constraintSize({ minHeight: 60 })
        .padding({ bottom: 12 })
        .border({ width: { bottom: 1 }, color: '#f0f2f5' });
      }

      this.GroupTitle('网页内容', 16);
      this.SettingSwitchRow(
        'JavaScript',
        '允许网站运行 JavaScript。',
        this.viewState.javaScriptEnabled,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setJavaScriptEnabled(enabled);
        },
      );
      this.SettingSwitchRow(
        '加载图片',
        '允许网页加载和显示图片资源。',
        this.viewState.imagesEnabled,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setImagesEnabled(enabled);
        },
      );
      this.SettingSwitchRow(
        '发送勿追踪请求',
        '向网站发送 Do Not Track 偏好。',
        this.viewState.doNotTrack,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setDoNotTrack(enabled);
        },
        false,
      );
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private DownloadSettingsContent() {
    this.PageHeader('下载设置');
    Column() {
      Row({ space: 20 }) {
        Column({ space: 4 }) {
          Text('下载内容保存到')
            .fontSize(14)
            .fontColor('#333333');
          Text(this.getDownloadDirectoryTitle())
            .fontSize(12)
            .fontColor('#666666')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.getDownloadDirectoryDescription())
            .fontSize(11)
            .fontColor('#999999')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (this.viewState.downloadDirectoryUri.length > 0) {
          Button('重置')
            .height(34)
            .fontSize(12)
            .fontColor('#333333')
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .enabled(!this.isChoosingDownloadDirectory)
            .onClick(() => this.resetDownloadDirectory());
        }

        Button(this.isChoosingDownloadDirectory ? '选择中...' : '更改')
          .height(34)
          .fontSize(12)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .enabled(!this.isChoosingDownloadDirectory)
          .onClick(() => this.chooseDownloadDirectory());
      }
      .width('100%')
      .constraintSize({ minHeight: 72 })
      .padding({ top: 12, bottom: 12 })
      .border({ width: { bottom: 1 }, color: '#f0f2f5' });

      this.SettingSwitchRow(
        '下载完成后显示下载内容',
        '下载完成后在工具栏显示完成提示，不会打断当前浏览。',
        this.viewState.showDownloadsWhenFinished,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setShowDownloadsWhenFinished(enabled);
        },
      );

      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text('下载管理')
            .fontSize(14)
            .fontColor('#333333');
          Text(this.downloadsState.totalCount > 0 ?
            `查看和管理 ${this.downloadsState.totalCount} 个下载任务` : '查看下载任务和进度')
            .fontSize(12)
            .fontColor('#666666');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Button('›')
          .width(34)
          .height(34)
          .fontSize(22)
          .fontColor('#666666')
          .backgroundColor('#ffffff')
          .borderRadius(17);
      }
      .width('100%')
      .constraintSize({ minHeight: 62 })
      .padding({ top: 12, bottom: 4 })
      .onClick(() => {
        this.navigateToSection('download-manager');
        this.downloadsState = this.downloadsViewModel.markIndicatorSeen();
      });

      if (this.downloadDirectoryMessage.length > 0) {
        Text(this.downloadDirectoryMessage)
          .width('100%')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 14 });
      }
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private DownloadManagerContent() {
    Row({ space: 12 }) {
      this.SecondaryBackButton(() => this.navigateToSection('download-settings-new'));

      Text('下载管理')
        .layoutWeight(1)
        .fontSize(28)
        .fontWeight(FontWeight.Regular)
        .fontColor('#333333');

    }
    .width('100%')
    .margin({ bottom: 8 });

    if (this.downloadsState.finishedCount > 0) {
      Row() {
        Button(this.isClearingFinishedDownloads ? '正在清除...' : '清除已结束')
          .height(34)
          .fontSize(12)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .enabled(!this.isClearingFinishedDownloads)
          .opacity(this.isClearingFinishedDownloads ? 0.55 : 1)
          .onClick(() => {
            this.clearFinishedDownloads();
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ bottom: 12 });
    }

    if (this.downloadOpenMessage.length > 0) {
      Text(this.downloadOpenMessage)
        .width('100%')
        .fontSize(12)
        .fontColor(this.downloadMessageIsError ? '#d32f2f' : '#388e3c')
        .margin({ top: -12, bottom: 12 });
    }

    Column() {
      if (this.downloadsState.downloads.length === 0) {
        Column({ space: 8 }) {
          Text('暂无下载记录')
            .fontSize(16)
            .fontColor('#666666');
          Text('开始下载后，任务进度和操作会显示在这里。')
            .fontSize(12)
            .fontColor('#999999');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        List() {
          ForEach(this.downloadsState.downloads, (task: DownloadTask, index: number) => {
            ListItem() {
              SettingsDownloadItem({
                task: task,
                renderRevision: $downloadsRenderRevision,
                getTask: (id: string) => this.downloadsViewModel.getDownload(id),
                extraActionBusy: this.downloadUiBusyTaskId === task.id,
                compact: this.useCompactContentLayout(),
                showDivider: index < this.downloadsState.downloads.length - 1,
                onCancel: (id: string) => this.applyDownloadsState(this.downloadsViewModel.cancel(id)),
                onPause: (id: string) => this.applyDownloadsState(this.downloadsViewModel.pause(id)),
                onResume: (id: string) => this.applyDownloadsState(this.downloadsViewModel.resume(id)),
                onRetry: (id: string) => this.applyDownloadsState(this.downloadsViewModel.retry(id)),
                onRemove: (id: string) => {
                  this.removeDownload(id);
                },
                onCopy: (id: string) => {
                  this.copyDownloadUrl(id);
                },
                onOpenFolder: (id: string) => this.openDownloadedFolder(id),
              });
            }
          // 下载进度会高频变化，列表身份必须只使用稳定的任务 ID。
          // 如果把 progress/state 放进 key，ArkUI 会在每次进度回调时销毁并重建整行，
          // 导致操作按钮和图标持续闪动。
          }, (task: DownloadTask) => task.id);
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({ strokeWidth: 0, color: '#00000000' });
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .border({ width: 1, color: '#e0e0e0' })
    .borderRadius(8);
  }

  @Builder
  private SiteNavigationRow(title: string, description: string, onClick: () => void, showDivider: boolean = true) {
    Row({ space: 16 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontColor('#333333');
        Text(description)
          .fontSize(12)
          .fontColor('#666666')
          .maxLines(2)
          .lineHeight(18);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Button('›')
        .width(34)
        .height(34)
        .fontSize(22)
        .fontColor('#666666')
        .backgroundColor('#ffffff')
        .borderRadius(17);
    }
    .width('100%')
    .constraintSize({ minHeight: 62 })
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: showDivider ? 1 : 0 }, color: '#f0f2f5' })
    .onClick(() => onClick());
  }

  @Builder
  private SiteSettingsContent() {
    this.PageHeader('网站设置');
    Column() {
      this.GroupTitle('网站');
      this.SiteNavigationRow(
        '所有网站',
        this.siteSettingsState.totalSiteCount > 0 ?
          `${this.siteSettingsState.totalSiteCount} 个网站保存了权限设置` : '管理所有网站的设置',
        () => this.openAllSites(),
        false,
      );

      this.GroupTitle('权限', 18);
      ForEach(SITE_PERMISSION_TYPES, (permissionType: SitePermissionType, index: number) => {
        this.SiteNavigationRow(
          getSitePermissionLabel(permissionType),
          this.siteSettingsViewModel.getPermissionCount(permissionType) > 0 ?
            `${this.siteSettingsViewModel.getPermissionCount(permissionType)} 项已保存设置` : '网站请求时由您决定',
          () => this.openAllSites(permissionType),
          index < SITE_PERMISSION_TYPES.length - 1,
        );
      }, (permissionType: SitePermissionType) => permissionType);

      this.GroupTitle('网页元素', 18);
      this.SiteNavigationRow(
        'Cookie',
        this.viewState.cookiesEnabled ? '允许网站保存和读取 Cookie 数据' : '已禁止所有网站使用 Cookie',
        () => {
          this.navigateToSection('cookie-settings');
        },
      );
      this.SiteNavigationRow(
        'JavaScript',
        this.viewState.javaScriptEnabled ? '允许网站运行 JavaScript' : '已禁止网站运行 JavaScript',
        () => {
          this.navigateToSection('javascript-settings');
        },
        false,
      );
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private AllSitesSettingsContent() {
    Row({ space: 12 }) {
      this.SecondaryBackButton(() => {
        this.sitePermissionFilter = undefined;
        this.siteSettingsState = this.siteSettingsViewModel.getState();
        this.navigateToSection('site-settings');
      });
      Text(this.getAllSitesTitle())
        .layoutWeight(1)
        .fontSize(28)
        .fontWeight(FontWeight.Regular)
        .fontColor('#333333');
    }
    .width('100%')
    .margin({ bottom: 24 });

    Column() {
      if (this.siteSettingsState.sites.length === 0) {
        Column({ space: 8 }) {
          Text('没有网站')
            .fontSize(16)
            .fontColor('#666666');
          Text(this.sitePermissionFilter ? '没有网站保存此项权限设置' : '网站权限被记住后会显示在这里')
            .fontSize(12)
            .fontColor('#999999');
        }
        .width('100%')
        .constraintSize({ minHeight: 180 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        ForEach(this.siteSettingsState.sites, (site: SiteSettingsSiteSummary, index: number) => {
          this.SiteNavigationRow(
            site.displayName,
            site.permissionSummary,
            () => this.openSiteDetail(site.origin),
            index < this.siteSettingsState.sites.length - 1,
          );
        }, (site: SiteSettingsSiteSummary) => site.origin);
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private SiteDetailSettingsContent() {
    Row({ space: 12 }) {
      this.SecondaryBackButton(() => {
        this.siteSettingsState = this.siteSettingsViewModel.getState(this.sitePermissionFilter);
        this.navigateToSection('site-settings-all');
      });
      Text(`${this.selectedSiteOrigin} 的设置`)
        .layoutWeight(1)
        .fontSize(24)
        .fontWeight(FontWeight.Regular)
        .fontColor('#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Button('重置权限')
        .height(34)
        .fontSize(12)
        .fontColor('#ffffff')
        .backgroundColor('#d32f2f')
        .borderRadius(4)
        .onClick(() => this.resetSelectedSite());
    }
    .width('100%')
    .margin({ bottom: 24 });

    Column() {
      this.GroupTitle('权限');
      ForEach(this.selectedSiteSettings, (setting: SitePermissionSetting, index: number) => {
        Row({ space: 20 }) {
          Column({ space: 4 }) {
            Text(getSitePermissionLabel(setting.permissionType))
              .fontSize(14)
              .fontColor('#333333');
            Text(`当前设置：${this.getPermissionDecisionText(setting.decision)}`)
              .fontSize(12)
              .fontColor('#666666');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Select([
            { value: '询问' },
            { value: '允许' },
            { value: '禁止' },
          ])
            .selected(this.getPermissionDecisionIndex(setting.decision))
            .value(this.getPermissionDecisionText(setting.decision))
            .backgroundColor('#ffffff')
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .onSelect((decisionIndex: number) => {
              this.setSelectedSitePermission(setting.permissionType, SITE_PERMISSION_DECISIONS[decisionIndex]);
            });
        }
        .width('100%')
        .constraintSize({ minHeight: 62 })
        .padding({ top: 12, bottom: 12 })
        .border({ width: { bottom: index < this.selectedSiteSettings.length - 1 ? 1 : 0 }, color: '#f0f2f5' });
      }, (setting: SitePermissionSetting) => setting.permissionType);
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private CookieSettingsContent() {
    Row({ space: 12 }) {
      this.SecondaryBackButton(() => this.navigateToSection('site-settings'));
      Text('Cookie')
        .layoutWeight(1)
        .fontSize(28)
        .fontWeight(FontWeight.Regular)
        .fontColor('#333333');
    }
    .width('100%')
    .margin({ bottom: 24 });

    Column() {
      this.SettingSwitchRow(
        'Cookie',
        '允许网站保存和读取 Cookie 数据。',
        this.viewState.cookiesEnabled,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setCookiesEnabled(enabled);
        },
      );
      this.SettingSwitchRow(
        '无痕模式第三方 Cookie',
        '当前 Web 内核使用统一策略，无痕窗口跟随下方“禁止第三方 Cookie”设置。',
        this.viewState.blockThirdPartyCookies,
        (_enabled: boolean) => {
        },
        true,
        false,
      );
      this.SettingSwitchRow(
        '禁止第三方 Cookie',
        '阻止普通与无痕窗口中的第三方网站保存和读取 Cookie 数据。',
        this.viewState.blockThirdPartyCookies,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setBlockThirdPartyCookies(enabled);
        },
        false,
        this.viewState.cookiesEnabled,
      );
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private JavaScriptSettingsContent() {
    Row({ space: 12 }) {
      this.SecondaryBackButton(() => this.navigateToSection('site-settings'));
      Text('JavaScript')
        .layoutWeight(1)
        .fontSize(28)
        .fontWeight(FontWeight.Regular)
        .fontColor('#333333');
    }
    .width('100%')
    .margin({ bottom: 24 });

    Column() {
      this.SettingSwitchRow(
        'JavaScript',
        '允许网站运行 JavaScript。关闭后部分网站可能无法正常使用。',
        this.viewState.javaScriptEnabled,
        (enabled: boolean) => {
          this.viewState = this.viewModel.setJavaScriptEnabled(enabled);
        },
        false,
      );
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private StartupSettingsContent() {
    this.PageHeader('起始页设置');
    Column() {
      this.GroupTitle('启动时');
      this.StartupBehaviorRow('new_tab', '打开新标签页', '启动后显示一个新的空白标签页。', true);
      this.StartupBehaviorRow('restore_session', '继续浏览上次打开的网页', '恢复上次保留的普通标签页。', true);
      this.StartupBehaviorRow('home_page', '打开主页', '启动后打开下方配置的主页地址。', false);

      Row({ space: 10 }) {
        TextInput({ text: this.homePageUrl, placeholder: 'about:blank 或 https://example.com' })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .backgroundColor('#ffffff')
          .borderRadius(4)
          .padding({ left: 12, right: 12 })
          .border({ width: 1, color: '#dddddd' })
          .onChange((value: string) => {
            this.homePageUrl = value;
          })
          .onSubmit(() => this.handleHomePageUrlSubmit(this.homePageUrl));

        Button('保存')
          .height(36)
          .fontSize(13)
          .backgroundColor(this.isHomePageUrlDirty() ? '#1976d2' : '#d5d7db')
          .fontColor(this.isHomePageUrlDirty() ? '#ffffff' : '#9aa0a6')
          .borderRadius(4)
          .enabled(this.isHomePageUrlDirty())
          .onClick(() => this.handleHomePageUrlSubmit(this.homePageUrl));

        Button('重置')
          .height(36)
          .fontSize(13)
          .backgroundColor('#f0f2f5')
          .fontColor('#333333')
          .borderRadius(4)
          .onClick(() => this.handleResetHomePage());
      }
      .width('100%')
      .margin({ top: 18 });
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private ClearDataContent() {
    this.PageHeader('清除浏览数据');
    Column() {
      this.GroupTitle('选择要清除的数据');
      this.ClearDataRow('历史记录', '清除已保存的网页访问记录。', this.clearHistorySelected,
        (selected: boolean) => {
          this.clearHistorySelected = selected;
        });
      this.ClearDataRow('下载记录', '清除下载列表，不删除已下载的本地文件。', this.clearDownloadsSelected,
        (selected: boolean) => {
          this.clearDownloadsSelected = selected;
        });
      this.ClearDataRow('Cookie 和站点数据', '退出网站并清除站点保存的数据。', this.clearSiteDataSelected,
        (selected: boolean) => {
          this.clearSiteDataSelected = selected;
        });
      this.ClearDataRow('网站设置', '重置网站的位置、相机和麦克风等权限。', this.clearSitePermissionsSelected,
        (selected: boolean) => {
          this.clearSitePermissionsSelected = selected;
        }, false);

      Row({ space: 14 }) {
        if (this.clearBrowsingDataMessage.length > 0) {
          Text(this.clearBrowsingDataMessage)
            .layoutWeight(1)
            .fontSize(12)
            .fontColor('#666666');
        } else {
          Row()
            .layoutWeight(1);
        }

        Button(this.isClearingBrowsingData ? '正在清理...' : '清除数据')
          .height(36)
          .fontSize(13)
          .backgroundColor('#1976d2')
          .fontColor('#ffffff')
          .borderRadius(4)
          .enabled(!this.isClearingBrowsingData)
          .onClick(() => this.clearSelectedBrowsingData());
      }
      .width('100%')
      .margin({ top: 20 });
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  private ActiveSectionContent() {
    if (this.activeSectionId === 'manage-search-engine') {
      this.ManageSearchEngineContent();
    } else if (this.activeSectionId === 'browser-settings') {
      this.BrowserSettingsContent();
    } else if (this.activeSectionId === 'download-settings-new') {
      this.DownloadSettingsContent();
    } else if (this.activeSectionId === 'download-manager') {
      this.DownloadManagerContent();
    } else if (this.activeSectionId === 'site-settings') {
      this.SiteSettingsContent();
    } else if (this.activeSectionId === 'site-settings-all') {
      this.AllSitesSettingsContent();
    } else if (this.activeSectionId === 'site-detail') {
      this.SiteDetailSettingsContent();
    } else if (this.activeSectionId === 'cookie-settings') {
      this.CookieSettingsContent();
    } else if (this.activeSectionId === 'javascript-settings') {
      this.JavaScriptSettingsContent();
    } else if (this.activeSectionId === 'bookmarks-manager') {
      SettingsBookmarksManager({
        compact: this.useCompactContentLayout(),
        onOpenUrl: (url: string) => this.onOpenUrl(url),
        onOpenUrlInNewTab: (url: string) => this.onOpenUrlInNewTab(url),
        onOpenUrlInNewWindow: (url: string) => this.onOpenUrlInNewWindow(url),
        onOpenUrlInPrivateWindow: (url: string) => this.onOpenUrlInPrivateWindow(url),
      });
    } else if (this.activeSectionId === 'history') {
      SettingsHistoryManager({
        compact: this.useCompactContentLayout(),
        onOpenUrl: (url: string) => this.onOpenUrl(url),
      });
    } else if (this.activeSectionId === 'startup-settings') {
      this.StartupSettingsContent();
    } else if (this.activeSectionId === 'clear-data') {
      this.ClearDataContent();
    } else if (this.activeSectionId === 'about') {
      this.AboutContent();
    } else {
      this.SearchEngineContent();
    }
  }

  @Builder
  private AddSearchEngineDialog() {
    Column() {
      Row() {
        Text('添加搜索引擎')
          .layoutWeight(1)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333');
        Button('×')
          .width(30)
          .height(30)
          .fontSize(22)
          .fontColor('#666666')
          .backgroundColor('#00000000')
          .borderRadius(15)
          .onClick(() => this.closeAddSearchEngineDialog());
      }
      .width('100%');

      Text('名称')
        .width('100%')
        .fontSize(13)
        .fontColor('#333333')
        .margin({ top: 20, bottom: 8 });
      TextInput({ text: this.searchEngineNameDraft, placeholder: '例如：百度' })
        .width('100%')
        .height(40)
        .fontSize(13)
        .backgroundColor('#ffffff')
        .border({ width: 1, color: '#dddddd' })
        .borderRadius(4)
        .onChange((value: string) => {
          this.searchEngineNameDraft = value;
          this.searchEngineDialogMessage = '';
        });

      Text('查询网址（使用 %s 作为搜索词占位符）')
        .width('100%')
        .fontSize(13)
        .fontColor('#333333')
        .margin({ top: 16, bottom: 8 });
      TextInput({ text: this.searchEngineUrlDraft, placeholder: 'https://example.com/search?q=%s' })
        .width('100%')
        .height(40)
        .fontSize(13)
        .backgroundColor('#ffffff')
        .border({ width: 1, color: '#dddddd' })
        .borderRadius(4)
        .onChange((value: string) => {
          this.searchEngineUrlDraft = value;
          this.searchEngineDialogMessage = '';
        });

      if (this.searchEngineDialogMessage.length > 0) {
        Text(this.searchEngineDialogMessage)
          .width('100%')
          .fontSize(12)
          .fontColor('#d32f2f')
          .margin({ top: 10 });
      }

      Row({ space: 10 }) {
        Button('取消')
          .height(36)
          .fontSize(13)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .onClick(() => this.closeAddSearchEngineDialog());
        Button('添加')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#1976d2')
          .borderRadius(4)
          .onClick(() => this.addSearchEngine());
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 22 });
    }
    .width(440)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private DeleteSearchEngineDialog() {
    Column() {
      Text('删除搜索引擎')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333');
      Text(`确定要删除“${this.pendingDeleteSearchEngineName}”吗？`)
        .width('100%')
        .fontSize(14)
        .fontColor('#555555')
        .margin({ top: 18 });
      Row({ space: 10 }) {
        Button('取消')
          .height(36)
          .fontSize(13)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .onClick(() => this.closeDeleteSearchEngineDialog());
        Button('删除')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#d32f2f')
          .borderRadius(4)
          .onClick(() => this.deletePendingSearchEngine());
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 24 });
    }
    .width(400)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private MobileSettingsHeader() {
    Row({ space: 10 }) {
      Button('‹')
        .width(36)
        .height(36)
        .fontSize(26)
        .fontColor('#5f6368')
        .backgroundColor('#00000000')
        .borderRadius(18)
        .onClick(() => this.onBack());
      Text(this.getActiveNavigationLabel())
        .layoutWeight(1)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Button('☰')
        .width(36)
        .height(36)
        .fontSize(19)
        .fontColor('#5f6368')
        .backgroundColor('#00000000')
        .borderRadius(18)
        .onClick(() => {
          this.showMobileNavigation = true;
        });
    }
    .width('100%')
    .height(56)
    .padding({ left: 10, right: 10 })
    .backgroundColor('#ffffff')
    .border({ width: { bottom: 1 }, color: '#e0e0e0' });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        if (this.showPersistentSidebar()) {
          SettingsSidebar({
            items: SETTINGS_NAVIGATION_ITEMS,
            activeItemId: this.getActiveSidebarItemId(),
            compact: this.useCompactSidebar(),
            onSelectItem: (itemId: string) => this.navigateToSection(itemId),
            onBack: () => this.onBack(),
          });
        }

        Column() {
          if (!this.showPersistentSidebar()) {
            this.MobileSettingsHeader();
          }

          if (this.usesManagedListLayout()) {
            Column() {
              Column() {
                this.ActiveSectionContent();
              }
              .width('100%')
              .height('100%')
              .constraintSize({ maxWidth: this.getActiveContentMaxWidth() })
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Start);
            }
            .width('100%')
            .layoutWeight(1)
            .padding({
              left: this.getContentPadding(),
              right: this.getContentPadding(),
              top: this.getContentPadding(),
              bottom: this.getContentPadding(),
            })
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Start);
          } else {
            List({ scroller: this.settingsScroller }) {
              ListItem() {
                Column() {
                  Column() {
                    this.ActiveSectionContent();
                  }
                  .width('100%')
                  .constraintSize({ maxWidth: this.getActiveContentMaxWidth() })
                  .alignItems(HorizontalAlign.Start)
                  .justifyContent(FlexAlign.Start);
                }
                .width('100%')
                .padding({
                  left: this.getContentPadding(),
                  right: this.getContentPadding(),
                  top: this.getContentPadding(),
                  bottom: 40,
                })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Start);
              }
              .width('100%');
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Auto)
            .divider({ strokeWidth: 0, color: '#00000000' })
            .backgroundColor('#f8f9fa');
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .backgroundColor('#f8f9fa');
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Top)
      .backgroundColor('#f8f9fa');

      if (this.showMobileNavigation) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => {
            this.showMobileNavigation = false;
          });
        Row() {
          SettingsSidebar({
            items: SETTINGS_NAVIGATION_ITEMS,
            activeItemId: this.getActiveSidebarItemId(),
            compact: false,
            onSelectItem: (itemId: string) => this.navigateToSection(itemId),
            onBack: () => this.onBack(),
          });
        }
        .width(SettingsLayoutPolicy.getDrawerWidth())
        .height('100%')
        .align(Alignment.Start);
      }

      if (this.showAddSearchEngineDialog || this.showDeleteSearchEngineDialog) {
        Column() {
          if (this.showAddSearchEngineDialog) {
            this.AddSearchEngineDialog();
          } else {
            this.DeleteSearchEngineDialog();
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeAddSearchEngineDialog();
          this.closeDeleteSearchEngineDialog();
        });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f8f9fa')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateViewportWidth(Number(newValue.width));
    });
  }
}
