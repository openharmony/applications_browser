import {
  BookmarkFolderOption,
  BookmarksPageListItem,
  BookmarksPageViewState,
  BookmarksViewModel,
} from '../viewmodels/BookmarksViewModel';
import { ClipboardService } from '../../integration/clipboardService';
import { BrowserContextMenu, BrowserContextMenuItem } from './BrowserContextMenu';

const EMPTY_BOOKMARKS_STATE: BookmarksPageViewState = {
  bookmarks: [],
  items: [],
  keyword: '',
  parentId: '',
  parentTitle: '全部书签',
  isRootFolder: true,
  totalCount: 0,
  folderCount: 0,
  isLoading: false,
  errorMessage: '',
};

// 新建文件夹弹层内输入框的焦点 ID：等 bindContentCover 挂载完成后 requestFocus。
const BOOKMARK_NEW_FOLDER_INPUT_ID: string = 'bookmark_new_folder_input';

@Component
export struct SettingsBookmarksManager {
  @Prop compact: boolean = false;
  onOpenUrl: (url: string) => void = (_: string): void => {};
  onOpenUrlInNewTab: (url: string) => void = (_: string): void => {};
  onOpenUrlInNewWindow: (url: string) => void = (_: string): void => {};
  onOpenUrlInPrivateWindow: (url: string) => void = (_: string): void => {};

  private readonly viewModel: BookmarksViewModel = new BookmarksViewModel();
  private readonly clipboardService: ClipboardService = new ClipboardService();
  private readonly bookmarksListener: (state: BookmarksPageViewState) => void = (state: BookmarksPageViewState) => {
    this.applyState(state);
  };
  // 新建文件夹弹层挂载是异步的：延迟到 TextInput 可聚焦后再补一次焦点请求。
  private createFolderFocusTimer: number = -1;

  @State private viewState: BookmarksPageViewState = EMPTY_BOOKMARKS_STATE;
  @State private keyword: string = '';
  @State private newFolderName: string = '';
  @State private showCreateFolderDialog: boolean = false;
  @State private showRenameDialog: boolean = false;
  @State private showMoveDialog: boolean = false;
  @State private showDeleteDialog: boolean = false;
  @State private pendingEditId: string = '';
  @State private pendingEditTitle: string = '';
  @State private pendingEditIsFolder: boolean = false;
  @State private renameDraft: string = '';
  @State private renameDraftUrl: string = '';
  @State private moveFolderOptions: BookmarkFolderOption[] = [];
  @State private pendingDeleteId: string = '';
  @State private pendingDeleteTitle: string = '';
  @State private pendingDeleteIsFolder: boolean = false;
  @State private isImporting: boolean = false;
  @State private isExporting: boolean = false;
  @State private statusMessage: string = '';
  @State private failedFaviconKeys: string[] = [];
  @State private isMutating: boolean = false;
  @State private actionMenuItemId: string = '';
  @State private actionMenuX: number = 0;
  @State private actionMenuY: number = 0;
  @State private viewportWidth: number = 1280;
  @State private viewportHeight: number = 720;
  @State private showPageActionMenu: boolean = false;
  @State private pageActionMenuItems: BrowserContextMenuItem[] = [];
  @State private pageActionMenuX: number = 0;
  @State private pageActionMenuY: number = 0;
  @State private draggingItemId: string = '';
  @State private dragOverItemId: string = '';

  aboutToAppear(): void {
    this.applyState(this.viewModel.getInitialState());
    this.reloadBookmarks();
    this.viewModel.addListener(this.bookmarksListener);
  }

  aboutToDisappear(): void {
    this.cancelCreateFolderInputFocus();
    this.closeActionMenu();
    this.viewModel.removeListener(this.bookmarksListener);
  }

  private applyState(state: BookmarksPageViewState): void {
    this.closeActionMenu();
    this.viewState = state;
    this.keyword = state.keyword;
  }

  private getFaviconKey(item: BookmarksPageListItem): string {
    return `${item.id}:${item.faviconUrl ?? ''}`;
  }

  private markFaviconFailed(item: BookmarksPageListItem): void {
    const key = this.getFaviconKey(item);
    if (this.failedFaviconKeys.indexOf(key) < 0) {
      this.failedFaviconKeys = this.failedFaviconKeys.concat([key]);
    }
  }

  private canRenderFavicon(item: BookmarksPageListItem): boolean {
    const faviconUrl = item.faviconUrl ? item.faviconUrl.trim() : '';
    return item.type !== 'folder' && faviconUrl.length > 0 &&
      this.failedFaviconKeys.indexOf(this.getFaviconKey(item)) < 0;
  }

  private getFaviconSource(item: BookmarksPageListItem): string {
    return item.faviconUrl ? item.faviconUrl.trim() : '';
  }

  private buildPendingState(keyword: string = this.viewState.keyword): BookmarksPageViewState {
    return {
      bookmarks: this.viewState.bookmarks,
      items: this.viewState.items,
      keyword: keyword,
      parentId: this.viewState.parentId,
      parentTitle: this.viewState.parentTitle,
      isRootFolder: this.viewState.isRootFolder,
      totalCount: this.viewState.totalCount,
      folderCount: this.viewState.folderCount,
      isLoading: true,
      errorMessage: '',
    };
  }

  private buildErrorState(error: Error): BookmarksPageViewState {
    return {
      bookmarks: this.viewState.bookmarks,
      items: this.viewState.items,
      keyword: this.keyword,
      parentId: this.viewState.parentId,
      parentTitle: this.viewState.parentTitle,
      isRootFolder: this.viewState.isRootFolder,
      totalCount: this.viewState.totalCount,
      folderCount: this.viewState.folderCount,
      isLoading: false,
      errorMessage: error.message || '书签加载失败',
    };
  }

  private beginMutation(): boolean {
    if (this.isMutating) {
      return false;
    }
    this.isMutating = true;
    return true;
  }

  private finishMutation(): void {
    this.isMutating = false;
  }

  private beginDrag(item: BookmarksPageListItem): DragItemInfo {
    this.closeActionMenu();
    this.draggingItemId = item.id;
    this.dragOverItemId = '';
    return { extraInfo: item.id };
  }

  private clearDragState(): void {
    this.draggingItemId = '';
    this.dragOverItemId = '';
  }

  private dropOnItem(target: BookmarksPageListItem): void {
    const sourceId = this.draggingItemId;
    this.clearDragState();
    if (!sourceId || sourceId === target.id || this.isMutating) {
      return;
    }
    const source = this.viewState.items.find((item: BookmarksPageListItem) => item.id === sourceId);
    if (!source) {
      return;
    }
    const targetParentId = target.type === 'folder' ? target.id : target.parentId;
    let targetOrder: number | undefined = target.type === 'folder' ? undefined : target.sortOrder;
    if (target.type !== 'folder' && source.parentId === target.parentId && source.sortOrder < target.sortOrder) {
      targetOrder = Math.max(0, target.sortOrder - 1);
    }
    if (!this.beginMutation()) {
      return;
    }
    this.applyState(this.buildPendingState());
    this.viewModel.moveNode(sourceId, targetParentId, targetOrder)
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)))
      .finally(() => this.finishMutation());
  }

  private dropOnList(): void {
    const sourceId = this.draggingItemId;
    this.clearDragState();
    if (!sourceId || this.isMutating) {
      return;
    }
    if (!this.beginMutation()) {
      return;
    }
    this.applyState(this.buildPendingState());
    this.viewModel.moveNode(sourceId, this.viewState.parentId)
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)))
      .finally(() => this.finishMutation());
  }

  private reloadBookmarks(): void {
    this.applyState(this.buildPendingState());
    this.viewModel.load()
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private setKeyword(keyword: string): void {
    this.keyword = keyword;
    this.applyState(this.buildPendingState(keyword));
    this.viewModel.setKeyword(keyword)
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private openItem(item: BookmarksPageListItem): void {
    if (item.type === 'folder') {
      this.applyState(this.buildPendingState(''));
      this.viewModel.openFolder(item.id)
        .then((state: BookmarksPageViewState) => this.applyState(state))
        .catch((error: Error) => this.applyState(this.buildErrorState(error)));
      return;
    }
    if (item.url) {
      this.onOpenUrl(item.url);
    }
  }

  private goParent(): void {
    this.applyState(this.buildPendingState(''));
    this.viewModel.goParent()
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private goRoot(): void {
    this.applyState(this.buildPendingState(''));
    this.viewModel.goRoot()
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private openCreateFolderDialog(): void {
    this.newFolderName = '';
    this.showCreateFolderDialog = true;
    this.scheduleCreateFolderInputFocus();
  }

  private scheduleCreateFolderInputFocus(): void {
    this.cancelCreateFolderInputFocus();
    // bindContentCover 弹层内的 TextInput 要等覆盖层挂载完成才可聚焦，
    // 立即 requestFocus 会静默失败，延迟到挂载稳定后再补一次（与 AddressBar 同套路）。
    this.createFolderFocusTimer = setTimeout(() => {
      this.createFolderFocusTimer = -1;
      try {
        this.getUIContext().getFocusController().requestFocus(BOOKMARK_NEW_FOLDER_INPUT_ID);
      } catch (_) {
        // 弹层尚未就绪时忽略，用户仍可手动点击输入框聚焦。
      }
    }, 50);
  }

  private cancelCreateFolderInputFocus(): void {
    if (this.createFolderFocusTimer >= 0) {
      clearTimeout(this.createFolderFocusTimer);
      this.createFolderFocusTimer = -1;
    }
  }

  private openRenameDialog(item: BookmarksPageListItem): void {
    this.pendingEditId = item.id;
    this.pendingEditTitle = item.title;
    this.pendingEditIsFolder = item.type === 'folder';
    this.renameDraft = item.title;
    this.renameDraftUrl = item.url ?? '';
    this.showRenameDialog = true;
  }

  private toggleActionMenu(item: BookmarksPageListItem, event: ClickEvent): void {
    if (this.isMutating) {
      return;
    }
    if (this.actionMenuItemId === item.id) {
      this.closeActionMenu();
      return;
    }
    const menuWidth = this.getActionMenuWidth();
    const rawX = Number(event.windowX);
    const rawY = Number(event.windowY);
    const clickX = Number.isFinite(rawX) ? rawX : Number(event.displayX);
    const clickY = Number.isFinite(rawY) ? rawY : Number(event.displayY);
    this.actionMenuX = Math.max(8, Math.min(clickX - menuWidth + 28, this.viewportWidth - menuWidth - 8));
    this.actionMenuY = Math.max(8, Math.min(clickY + 8, this.viewportHeight - 250));
    this.actionMenuItemId = item.id;
    this.showPageActionMenu = false;
  }

  private showItemActionMenuAt(item: BookmarksPageListItem, rawX: number, rawY: number): void {
    if (this.isMutating) {
      return;
    }
    const menuWidth = this.getActionMenuWidth();
    this.pageActionMenuItems = this.getActionMenuItems(item);
    this.pageActionMenuX = Math.max(8, Math.min(rawX, this.viewportWidth - menuWidth - 8));
    this.pageActionMenuY = Math.max(8, Math.min(rawY, this.viewportHeight - 300));
    this.actionMenuItemId = item.id;
    this.showPageActionMenu = true;
  }

  private showEmptyActionMenuAt(rawX: number, rawY: number): void {
    if (this.isMutating) {
      return;
    }
    const menuWidth = this.getActionMenuWidth();
    this.pageActionMenuItems = [
      { id: 'new_folder', label: '新建文件夹', leadingIcon: '+' },
      { id: 'import', label: '导入书签', leadingIcon: '↓' },
      { id: 'export', label: '导出书签', leadingIcon: '↑' },
    ];
    this.pageActionMenuX = Math.max(8, Math.min(rawX, this.viewportWidth - menuWidth - 8));
    this.pageActionMenuY = Math.max(8, Math.min(rawY, this.viewportHeight - 180));
    this.actionMenuItemId = '';
    this.showPageActionMenu = true;
  }

  private closeActionMenu(): void {
    this.actionMenuItemId = '';
    this.showPageActionMenu = false;
    this.pageActionMenuItems = [];
  }

  private getActionMenuWidth(): number {
    return Math.min(164, Math.max(120, this.viewportWidth - 16));
  }

  private getActionMenuItems(item: BookmarksPageListItem): BrowserContextMenuItem[] {
    const items: BrowserContextMenuItem[] = [
      { id: 'open', label: item.type === 'folder' ? '打开' : '当前标签页打开', leadingIcon: '↗' },
    { id: 'edit', label: item.type === 'folder' ? '重命名' : '编辑', leadingIcon: '✎' },
    ];
    if (item.type !== 'folder') {
      items.splice(1, 0,
        { id: 'open_new_tab', label: '在新标签页打开', leadingIcon: '+' },
        { id: 'open_new_window', label: '在新窗口打开', leadingIcon: '□' },
        // 暂时预留，后期完善：无痕窗口打开方式当前不对用户开放。
      );
      items.push({ id: 'copy', label: '复制链接', leadingIcon: '▣' });
    }
    items.push({ id: 'move', label: '移动', leadingIcon: '↔' });
    items.push({ id: 'delete', label: '删除', leadingIcon: '⌫', dividerBefore: true });
    return items;
  }

  private getActiveActionMenuItems(): BrowserContextMenuItem[] {
    const item = this.viewState.items.find((entry: BookmarksPageListItem) => entry.id === this.actionMenuItemId);
    return item ? this.getActionMenuItems(item) : [];
  }

  private handleActionMenuSelect(menuItem: BrowserContextMenuItem): void {
    const item = this.viewState.items.find((entry: BookmarksPageListItem) => entry.id === this.actionMenuItemId);
    if (!item) {
      this.closeActionMenu();
      return;
    }
    this.closeActionMenu();
    if (menuItem.id === 'open') {
      this.openItem(item);
    } else if (menuItem.id === 'open_new_tab' && item.url) {
      this.onOpenUrlInNewTab(item.url);
    } else if (menuItem.id === 'open_new_window' && item.url) {
      this.onOpenUrlInNewWindow(item.url);
    // 暂时预留，后期完善：无痕窗口打开能力保留在回调接口中，但当前不处理。
    } else if (menuItem.id === 'edit') {
      this.openRenameDialog(item);
    } else if (menuItem.id === 'copy') {
      this.copyUrlFromMenu(item);
    } else if (menuItem.id === 'move') {
      this.openMoveDialog(item);
    } else if (menuItem.id === 'delete') {
      this.openDeleteDialog(item);
    }
  }

  private handlePageActionMenuSelect(menuItem: BrowserContextMenuItem): void {
    if (menuItem.id === 'new_folder') {
      this.closeActionMenu();
      this.openCreateFolderDialog();
      return;
    }
    if (menuItem.id === 'import') {
      this.closeActionMenu();
      this.importBookmarks();
      return;
    }
    if (menuItem.id === 'export') {
      this.closeActionMenu();
      this.exportBookmarks();
      return;
    }
    this.handleActionMenuSelect(menuItem);
  }

  @Builder
  private BookmarkActionMenuOverlay() {
    BrowserContextMenu({
      items: this.showPageActionMenu ? this.pageActionMenuItems : this.getActiveActionMenuItems(),
      anchorX: this.showPageActionMenu ? this.pageActionMenuX : this.actionMenuX,
      anchorY: this.showPageActionMenu ? this.pageActionMenuY : this.actionMenuY,
      menuWidth: this.getActionMenuWidth(),
      maxMenuHeight: 250,
      onSelectItem: (menuItem: BrowserContextMenuItem) => this.handlePageActionMenuSelect(menuItem),
      onDismiss: () => this.closeActionMenu(),
    });
  }

  private async copyUrlFromMenu(item: BookmarksPageListItem): Promise<void> {
    if (!item.url) {
      this.statusMessage = '当前书签没有可复制的链接';
      this.closeActionMenu();
      return;
    }
    const copied = await this.clipboardService.copyText(item.url);
    this.statusMessage = copied ? '链接已复制' : '复制链接失败，请重试';
    this.closeActionMenu();
  }

  private closeRenameDialog(): void {
    this.showRenameDialog = false;
    this.pendingEditId = '';
    this.pendingEditTitle = '';
    this.pendingEditIsFolder = false;
    this.renameDraft = '';
    this.renameDraftUrl = '';
  }

  private renamePendingItem(): void {
    const nodeId = this.pendingEditId;
    const title = this.renameDraft.trim();
    const url = this.renameDraftUrl.trim();
    const isFolder = this.pendingEditIsFolder;
    if (nodeId.length === 0 || title.length === 0 || (!isFolder && url.length === 0)) {
      return;
    }
    if (!this.beginMutation()) {
      return;
    }
    this.closeRenameDialog();
    this.applyState(this.buildPendingState());
    const request = isFolder ?
      this.viewModel.renameNode(nodeId, title) :
      this.viewModel.updateBookmark(nodeId, title, url);
    request
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)))
      .finally(() => this.finishMutation());
  }

  private openMoveDialog(item: BookmarksPageListItem): void {
    this.pendingEditId = item.id;
    this.pendingEditTitle = item.title;
    this.pendingEditIsFolder = item.type === 'folder';
    this.moveFolderOptions = this.viewModel.getFolderOptions(item.type === 'folder' ? item.id : '');
    this.showMoveDialog = true;
  }

  private closeMoveDialog(): void {
    this.showMoveDialog = false;
    this.pendingEditId = '';
    this.pendingEditTitle = '';
    this.pendingEditIsFolder = false;
    this.moveFolderOptions = [];
  }

  private movePendingItem(parentId: string): void {
    const nodeId = this.pendingEditId;
    if (nodeId.length === 0) {
      return;
    }
    if (!this.beginMutation()) {
      return;
    }
    this.closeMoveDialog();
    this.applyState(this.buildPendingState());
    this.viewModel.moveNode(nodeId, parentId)
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)))
      .finally(() => this.finishMutation());
  }

  private closeCreateFolderDialog(): void {
    this.cancelCreateFolderInputFocus();
    this.showCreateFolderDialog = false;
    this.newFolderName = '';
  }

  private createFolder(): void {
    const folderName = this.newFolderName.trim();
    if (folderName.length === 0) {
      return;
    }
    if (!this.beginMutation()) {
      return;
    }
    this.applyState(this.buildPendingState());
    this.viewModel.createFolder(folderName)
      .then((state: BookmarksPageViewState) => {
        this.closeCreateFolderDialog();
        this.applyState(state);
      })
      .catch((error: Error) => this.applyState(this.buildErrorState(error)))
      .finally(() => this.finishMutation());
  }

  private openDeleteDialog(item: BookmarksPageListItem): void {
    this.pendingDeleteId = item.id;
    this.pendingDeleteTitle = item.title;
    this.pendingDeleteIsFolder = item.type === 'folder';
    this.showDeleteDialog = true;
  }

  private closeDeleteDialog(): void {
    this.showDeleteDialog = false;
    this.pendingDeleteId = '';
    this.pendingDeleteTitle = '';
    this.pendingDeleteIsFolder = false;
  }

  private deletePendingItem(): void {
    if (this.pendingDeleteId.length === 0) {
      return;
    }
    if (!this.beginMutation()) {
      return;
    }
    const itemId = this.pendingDeleteId;
    this.closeDeleteDialog();
    this.applyState(this.buildPendingState());
    this.viewModel.removeNode(itemId)
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)))
      .finally(() => this.finishMutation());
  }

  private async importBookmarks(): Promise<void> {
    if (this.isImporting) {
      return;
    }
    this.isImporting = true;
    this.statusMessage = '正在选择书签文件...';
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('当前页面上下文不可用');
      }
      const result = await this.viewModel.importFromPicker(context);
      this.applyState(this.viewModel.getViewState());
      this.statusMessage =
        `导入完成：新增文件夹 ${result.importedFolders} 个，` +
        `新增书签 ${result.importedBookmarks} 条，更新 ${result.updatedBookmarks} 条，` +
        `跳过 ${result.skippedBookmarks} 条。`;
    } catch (error) {
      const err = error as Error;
      this.statusMessage = err.message ? `导入失败：${err.message}` : '导入失败';
    } finally {
      this.isImporting = false;
    }
  }

  private async exportBookmarks(): Promise<void> {
    if (this.isExporting) {
      return;
    }
    this.isExporting = true;
    this.statusMessage = '正在选择导出位置...';
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('当前页面上下文不可用');
      }
      const result = await this.viewModel.exportToPicker(context);
      this.statusMessage =
        `导出完成：文件夹 ${result.totalFolders} 个，书签 ${result.totalBookmarks} 条。`;
    } catch (error) {
      const err = error as Error;
      this.statusMessage = err.message ? `导出失败：${err.message}` : '导出失败';
    } finally {
      this.isExporting = false;
    }
  }

  @Builder
  private BookmarkIcon(item: BookmarksPageListItem) {
    Row() {
      if (item.type === 'folder') {
        Text('□')
          .fontSize(16)
          .fontColor('#d99a00');
      } else if (this.canRenderFavicon(item)) {
        Image(this.getFaviconSource(item))
          .width(18)
          .height(18)
          .borderRadius(3)
          .objectFit(ImageFit.Contain)
          .onError(() => this.markFaviconFailed(item));
      } else {
        Text('●')
          .fontSize(9)
          .fontColor('#666666');
      }
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .borderRadius(4)
    .backgroundColor(item.type === 'folder' ? '#fff7dc' : '#f0f2f5');
  }

  @Builder
  private BookmarkRow(item: BookmarksPageListItem, showDivider: boolean) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        this.BookmarkIcon(item);
        Column({ space: 4 }) {
          Text(item.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(item.type === 'folder' ? `文件夹 · ${item.childCount} 项` : (item.url ?? ''))
            .fontSize(12)
            .fontColor('#666666')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => this.openItem(item));
        Button('更多')
          .height(32)
          .fontSize(12)
          .fontColor('#374151')
          .backgroundColor(this.actionMenuItemId === item.id ? '#eef2f7' : '#ffffff')
        .border({ width: 1, color: '#d9dee7' })
        .borderRadius(5)
        .enabled(!this.isMutating)
          .onClick((event: ClickEvent) => this.toggleActionMenu(item, event));
      }
      .width('100%');
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(item.type === 'folder' ? '#f8f9fa' : '#ffffff')
    .border({
      width: {
        top: this.dragOverItemId === item.id ? 2 : 0,
        bottom: showDivider ? 1 : 0,
      },
      color: this.dragOverItemId === item.id ? '#1976d2' : '#f0f2f5',
    })
    .draggable(!this.isMutating)
    .onDragStart(() => this.beginDrag(item))
    .onDragEnter(() => {
      this.dragOverItemId = item.id;
    })
    .onDragLeave(() => {
      if (this.dragOverItemId === item.id) {
        this.dragOverItemId = '';
      }
    })
    .onDrop(() => this.dropOnItem(item))
    .onDragEnd(() => this.clearDragState())
    .onMouse((event: MouseEvent) => {
      if (event.button !== MouseButton.Right) {
        return;
      }
      event.stopPropagation();
      const rawX = Number(event.windowX);
      const rawY = Number(event.windowY);
      this.showItemActionMenuAt(
        item,
        Number.isFinite(rawX) ? rawX : Math.max(8, Number(event.displayX)),
        Number.isFinite(rawY) ? rawY : Math.max(8, Number(event.displayY)),
      );
    });
  }

  @Builder
  private CreateFolderDialog() {
    Column() {
      Text('新建文件夹')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333');
      Text('文件夹名称')
        .width('100%')
        .fontSize(13)
        .fontColor('#333333')
        .margin({ top: 20, bottom: 8 });
      TextInput({ text: this.newFolderName, placeholder: '请输入文件夹名称' })
        .id(BOOKMARK_NEW_FOLDER_INPUT_ID)
        .width('100%')
        .height(40)
        .fontSize(13)
        .backgroundColor('#ffffff')
        .border({ width: 1, color: '#dddddd' })
        .borderRadius(4)
        .onChange((value: string) => {
          this.newFolderName = value;
        })
        .onSubmit(() => this.createFolder());
      Row({ space: 10 }) {
        Button('取消')
          .height(36)
          .fontSize(13)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .onClick(() => this.closeCreateFolderDialog());
        Button('创建')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#1976d2')
          .borderRadius(4)
          .enabled(this.newFolderName.trim().length > 0)
          .onClick(() => this.createFolder());
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 22 });
    }
    .width(420)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private DeleteDialog() {
    Column() {
      Text('删除书签项目')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333');
      Text(this.pendingDeleteIsFolder ?
        `确定要删除“${this.pendingDeleteTitle}”吗？文件夹中的内容也会被删除。` :
        `确定要删除“${this.pendingDeleteTitle}”吗？`)
        .width('100%')
        .fontSize(14)
        .fontColor('#555555')
        .lineHeight(21)
        .margin({ top: 18 });
      Row({ space: 10 }) {
        Button('取消')
          .height(36)
          .fontSize(13)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .onClick(() => this.closeDeleteDialog());
        Button('删除')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#d32f2f')
          .borderRadius(4)
          .onClick(() => this.deletePendingItem());
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 24 });
    }
    .width(420)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private RenameDialog() {
    Column() {
      Text(this.pendingEditIsFolder ? '重命名文件夹' : '重命名书签')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333');
      TextInput({ text: this.renameDraft, placeholder: '请输入名称' })
        .width('100%')
        .height(40)
        .fontSize(13)
        .backgroundColor('#ffffff')
        .border({ width: 1, color: '#dddddd' })
        .borderRadius(4)
        .margin({ top: 18 })
        .onChange((value: string) => {
          this.renameDraft = value;
        })
        .onSubmit(() => this.renamePendingItem());
      if (!this.pendingEditIsFolder) {
        TextInput({ text: this.renameDraftUrl, placeholder: '请输入网址（http:// 或 https://）' })
          .width('100%')
          .height(40)
          .fontSize(13)
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .margin({ top: 10 })
          .onChange((value: string) => {
            this.renameDraftUrl = value;
          })
          .onSubmit(() => this.renamePendingItem());
      }
      Row({ space: 10 }) {
        Button('取消')
          .height(36)
          .fontSize(13)
          .fontColor('#333333')
          .backgroundColor('#ffffff')
          .border({ width: 1, color: '#dddddd' })
          .borderRadius(4)
          .onClick(() => this.closeRenameDialog());
        Button('保存')
          .height(36)
          .fontSize(13)
          .fontColor('#ffffff')
          .backgroundColor('#1976d2')
          .borderRadius(4)
          .enabled(this.renameDraft.trim().length > 0 &&
            (this.pendingEditIsFolder || this.renameDraftUrl.trim().length > 0))
          .onClick(() => this.renamePendingItem());
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 22 });
    }
    .width(420)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private MoveDialog() {
    Column() {
      Text(this.pendingEditIsFolder ? '移动文件夹' : '移动书签')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333');
      Text(`选择“${this.pendingEditTitle}”的目标文件夹`)
        .width('100%')
        .fontSize(13)
        .fontColor('#666666')
        .margin({ top: 10, bottom: 12 });
      List({ space: 0 }) {
        ForEach(this.moveFolderOptions, (option: BookmarkFolderOption) => {
          ListItem() {
            Button() {
              Row({ space: 8 }) {
                Text(option.depth > 0 ? '└' : '⌂')
                  .fontSize(13)
                  .fontColor('#6b7280');
                Text(option.isCurrent ? `${option.title}（当前位置）` : option.title)
                  .layoutWeight(1)
                  .fontSize(13)
                  .fontColor('#333333')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(`${option.childCount}`)
                  .fontSize(11)
                  .fontColor('#9ca3af');
              }
              .width('100%')
              .padding({ left: option.depth * 16, right: 10 });
            }
            .width('100%')
            .height(38)
            .padding(0)
            .backgroundColor('#ffffff')
            .border({ width: { bottom: 1 }, color: '#f0f2f5' })
            .enabled(!this.isMutating && !option.isCurrent)
            .opacity(option.isCurrent ? 0.55 : 1)
            .onClick(() => this.movePendingItem(option.id));
          }
        }, (option: BookmarkFolderOption) => option.id || 'root');
      }
      .width('100%')
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Auto);
      Button('取消')
        .height(36)
        .fontSize(13)
        .fontColor('#333333')
        .backgroundColor('#ffffff')
        .border({ width: 1, color: '#dddddd' })
        .borderRadius(4)
        .alignSelf(ItemAlign.End)
        .margin({ top: 16 })
        .onClick(() => this.closeMoveDialog());
    }
    .width(420)
    .constraintSize({ maxWidth: '90%' })
    .padding(24)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#ffffff')
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {});
  }

  @Builder
  private BookmarkDialogCover() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeCreateFolderDialog();
          this.closeRenameDialog();
          this.closeMoveDialog();
          this.closeDeleteDialog();
        });
      if (this.showCreateFolderDialog) {
        this.CreateFolderDialog();
      } else if (this.showRenameDialog) {
        this.RenameDialog();
      } else if (this.showMoveDialog) {
        this.MoveDialog();
      } else {
        this.DeleteDialog();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#00000000');
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Text('书签管理')
          .width('100%')
          .fontSize(28)
          .fontWeight(FontWeight.Regular)
          .fontColor('#333333')
          .margin({ bottom: 24 });

        Column() {
          if (this.compact) {
            Column({ space: 8 }) {
              Button('+  新建文件夹')
                .width('100%')
                .height(36)
                .fontSize(12)
                .fontColor('#333333')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#dddddd' })
                .borderRadius(4)
                .onClick(() => this.openCreateFolderDialog());
              Row({ space: 8 }) {
                Button(this.isImporting ? '导入中...' : '导入书签')
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(12)
                  .enabled(!this.isImporting)
                  .onClick(() => this.importBookmarks());
                Button(this.isExporting ? '导出中...' : '导出书签')
                  .layoutWeight(1)
                  .height(36)
                  .fontSize(12)
                  .enabled(!this.isExporting)
                  .onClick(() => this.exportBookmarks());
              }
              .width('100%');
            }
            .width('100%')
            .margin({ bottom: 16 });
          } else {
            Row({ space: 10 }) {
              Button('+  新建文件夹')
                .height(36)
                .fontSize(12)
                .fontColor('#333333')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#dddddd' })
                .borderRadius(4)
                .onClick(() => this.openCreateFolderDialog());
              Button(this.isImporting ? '导入中...' : '导入书签')
                .height(36)
                .fontSize(12)
                .fontColor('#333333')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#dddddd' })
                .borderRadius(4)
                .enabled(!this.isImporting)
                .onClick(() => this.importBookmarks());
              Button(this.isExporting ? '导出中...' : '导出书签')
                .height(36)
                .fontSize(12)
                .fontColor('#333333')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#dddddd' })
                .borderRadius(4)
                .enabled(!this.isExporting)
                .onClick(() => this.exportBookmarks());
            }
            .width('100%')
            .margin({ bottom: 16 });
          }

          TextInput({ text: this.keyword, placeholder: '搜索书签、网址或文件夹' })
            .width('100%')
            .height(40)
            .fontSize(13)
            .backgroundColor('#ffffff')
            .padding({ left: 12, right: 12 })
            .border({ width: 1, color: '#dddddd' })
            .borderRadius(4)
            .onChange((value: string) => this.setKeyword(value));

          Row({ space: 10 }) {
            if (!this.viewState.isRootFolder && this.keyword.length === 0) {
              Button('‹')
                .width(30)
                .height(30)
                .fontSize(22)
                .fontColor('#666666')
                .backgroundColor('#ffffff')
                .borderRadius(15)
                .onClick(() => this.goParent());
            }
            Text(
              this.keyword.length > 0
                ? `搜索结果 ${this.viewState.items.length} 项`
                : this.viewState.parentTitle
            )
              .layoutWeight(1)
              .fontSize(13)
              .fontColor('#555555')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            if (!this.compact) {
              Text(`书签 ${this.viewState.totalCount} · 文件夹 ${this.viewState.folderCount}`)
                .fontSize(12)
                .fontColor('#888888');
            }
            if (!this.viewState.isRootFolder) {
              Button('全部书签')
                .height(30)
                .fontSize(12)
                .fontColor('#333333')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#dddddd' })
                .borderRadius(4)
                .onClick(() => this.goRoot());
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 50 });

          if (this.compact) {
            Text(`书签 ${this.viewState.totalCount} · 文件夹 ${this.viewState.folderCount}`)
              .width('100%')
              .fontSize(12)
              .fontColor('#888888')
              .textAlign(TextAlign.End)
              .margin({ bottom: 8 });
          }

          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .width('100%')
              .fontSize(12)
              .fontColor('#555555')
              .padding({ top: 8, bottom: 12 });
          }

          Column() {
            if (this.viewState.isLoading) {
              Column() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color('#1976d2');
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
          } else if (this.viewState.errorMessage.length > 0) {
            Column({ space: 12 }) {
              Text(this.viewState.errorMessage)
                .fontSize(14)
                .fontColor('#d32f2f');
              Button('重试')
                  .height(32)
                  .fontSize(12)
                  .onClick(() => this.reloadBookmarks());
            }
            .width('100%')
              .layoutWeight(this.viewState.items.length === 0 ? 1 : 0)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            if (this.viewState.items.length > 0) {
              List() {
                ForEach(this.viewState.items, (item: BookmarksPageListItem, index: number) => {
                  ListItem() {
                    this.BookmarkRow(item, index < this.viewState.items.length - 1);
                  }
                }, (item: BookmarksPageListItem) =>
                  `${item.id}:${item.title}:${item.faviconUrl ?? ''}:${item.url ?? ''}`
              );
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Auto);
            }
            } else if (this.viewState.items.length === 0) {
              Column() {
                Text(this.keyword.length > 0 ? '没有匹配的书签' : '暂无书签')
                  .fontSize(14)
                  .fontColor('#666666');
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center);
            } else {
              List() {
                ForEach(this.viewState.items, (item: BookmarksPageListItem, index: number) => {
                  ListItem() {
                    this.BookmarkRow(item, index < this.viewState.items.length - 1);
                  }
                }, (item: BookmarksPageListItem) =>
                  `${item.id}:${item.title}:${item.faviconUrl ?? ''}:${item.url ?? ''}`
              );
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
              .divider({ strokeWidth: 0, color: '#00000000' })
              .onDrop(() => this.dropOnList());
            }
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .border({ width: 1, color: '#e0e0e0' })
          .borderRadius(8)
          .onMouse((event: MouseEvent) => {
            if (event.button !== MouseButton.Right) {
              return;
            }
            event.stopPropagation();
            const rawX = Number(event.windowX);
            const rawY = Number(event.windowY);
            this.showEmptyActionMenuAt(
              Number.isFinite(rawX) ? rawX : Math.max(8, Number(event.displayX)),
              Number.isFinite(rawY) ? rawY : Math.max(8, Number(event.displayY)),
            );
          });
        }
        .width('100%')
        .layoutWeight(1)
        .padding(24)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#ffffff')
        .borderRadius(8)
        .shadow({ radius: 3, color: '#1a000000', offsetX: 0, offsetY: 1 });
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start);

      if (this.actionMenuItemId.length > 0 || this.showPageActionMenu) {
        this.BookmarkActionMenuOverlay();
      }

    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (width > 0) {
        this.viewportWidth = width;
      }
      if (height > 0) {
        this.viewportHeight = height;
      }
    })
    .bindContentCover(
      this.showCreateFolderDialog || this.showRenameDialog || this.showMoveDialog || this.showDeleteDialog,
      this.BookmarkDialogCover,
      ModalTransition.NONE,
    );
  }
}
