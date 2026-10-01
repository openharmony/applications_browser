// BookmarksPage：管理书签、文件夹与 HTML 导入导出。

import { AppRoute, AppRouter } from '../../core/appRouter';
import { BookmarksPageListItem, BookmarksPageViewState, BookmarksViewModel } from '../viewmodels/BookmarksViewModel';

@Component
export struct BookmarksPage {
  @Link route: AppRoute;
  @Link pendingUrl: string;

  private viewModel: BookmarksViewModel = new BookmarksViewModel();
  private bookmarksListener: (state: BookmarksPageViewState) => void = (state: BookmarksPageViewState) => {
    this.applyState(state);
  };

  @State private viewState: BookmarksPageViewState = {
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
  @State private keyword: string = '';
  @State private newFolderName: string = '';
  @State private isImporting: boolean = false;
  @State private isExporting: boolean = false;
  @State private statusMessage: string = '';
  @State private failedFaviconKeys: string[] = [];

  aboutToAppear(): void {
    this.applyState(this.viewModel.getInitialState());
    this.reloadBookmarks();
    this.viewModel.addListener(this.bookmarksListener);
  }

  aboutToDisappear(): void {
    this.viewModel.removeListener(this.bookmarksListener);
  }

  private applyState(state: BookmarksPageViewState): void {
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
      this.pendingUrl = item.url;
      this.route = AppRouter.browser;
    }
  }

  private removeItem(item: BookmarksPageListItem): void {
    this.applyState(this.buildPendingState());
    this.viewModel.removeNode(item.id)
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private reloadBookmarks(): void {
    this.applyState(this.buildPendingState());
    this.viewModel.load()
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private buildErrorState(error: Error): BookmarksPageViewState {
    return {
      bookmarks: [],
      items: [],
      keyword: this.keyword,
      parentId: this.viewState.parentId,
      parentTitle: this.viewState.parentTitle,
      isRootFolder: this.viewState.isRootFolder,
      totalCount: 0,
      folderCount: this.viewState.folderCount,
      isLoading: false,
      errorMessage: error.message && error.message.length > 0 ? error.message : '书签加载失败',
    };
  }

  private goRoot(): void {
    this.applyState(this.buildPendingState(''));
    this.viewModel.goRoot()
      .then((state: BookmarksPageViewState) => this.applyState(state))
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
  }

  private createFolder(): void {
    const folderName = this.newFolderName.trim();
    if (folderName.length === 0) {
      return;
    }

    this.applyState(this.buildPendingState());
    this.viewModel.createFolder(folderName)
      .then((state: BookmarksPageViewState) => {
        this.newFolderName = '';
        this.applyState(state);
      })
      .catch((error: Error) => this.applyState(this.buildErrorState(error)));
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
        `新增书签 ${result.importedBookmarks} 条，更新书签 ${result.updatedBookmarks} 条，` +
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
        `导出完成：文件夹 ${result.totalFolders} 个，书签 ${result.totalBookmarks} 条，` +
        `已保存到 ${result.fileUri}。`;
    } catch (error) {
      const err = error as Error;
      this.statusMessage = err.message ? `导出失败：${err.message}` : '导出失败';
    } finally {
      this.isExporting = false;
    }
  }

  @Builder
  private BookmarkFavicon(item: BookmarksPageListItem) {
    Row() {
      if (item.type === 'folder') {
        Text('[]')
          .fontSize(10)
          .fontColor('#a16207');
      } else if (this.canRenderFavicon(item)) {
        Image(this.getFaviconSource(item))
          .width(16)
          .height(16)
          .borderRadius(4)
          .objectFit(ImageFit.Contain)
          .onError(() => this.markFaviconFailed(item));
      } else {
        Text('o')
          .fontSize(10)
          .fontColor('#4b5563');
      }
    }
    .width(24)
    .height(24)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(item.type === 'folder' ? '#fef3c7' : '#f3f4f6');
  }

  @Builder
  private BookmarkListRow(item: BookmarksPageListItem) {
    Row({ space: 10 }) {
      this.BookmarkFavicon(item);

      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        if (item.type === 'folder') {
          Text(`文件夹 · ${item.childCount} 项`)
            .fontSize(12)
            .fontColor('#92400e')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        } else {
          Text(item.url ?? '')
            .fontSize(12)
            .fontColor('#6b7280')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Button(item.type === 'folder' ? '打开' : '访问')
        .fontSize(12)
        .height(30)
        .backgroundColor('#dbeafe')
        .fontColor('#2563eb')
        .borderRadius(15)
        .onClick(() => this.openItem(item));

      Button('删除')
        .fontSize(12)
        .height(30)
        .backgroundColor('#f3f4f6')
        .fontColor('#374151')
        .borderRadius(15)
        .onClick(() => this.removeItem(item));
    }
    .width('100%')
    .padding({ left: 14 + item.depth * 18, right: 14, top: 14, bottom: 14 })
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .border({ width: 1, color: '#e5e7eb' })
    .onClick(() => this.openItem(item));
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Button('返回')
          .height(34)
          .backgroundColor('#f3f4f6')
          .fontColor('#374151')
          .borderRadius(17)
          .onClick(() => {
            this.route = AppRouter.browser;
          });

        Text(`书签 ${this.viewState.totalCount}`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827');

        Text(`文件夹 ${this.viewState.folderCount}`)
          .fontSize(12)
          .fontColor('#6b7280');
      }
      .width('100%');

      Row({ space: 10 }) {
        Text(this.viewState.parentTitle)
          .fontSize(13)
          .fontColor('#374151')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);

        if (!this.viewState.isRootFolder) {
          Button('全部书签')
            .fontSize(12)
            .height(30)
            .backgroundColor('#f3f4f6')
            .fontColor('#374151')
            .borderRadius(15)
            .onClick(() => this.goRoot());
        }
      }
      .width('100%');

      Row({ space: 10 }) {
        TextInput({ text: this.keyword, placeholder: '搜索书签或文件夹' })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#ffffff')
          .borderRadius(20)
          .padding({ left: 14, right: 14 })
          .border({ width: 1, color: '#dbe3f0' })
          .onChange((value: string) => this.setKeyword(value));

        Button(this.isImporting ? '导入中' : '导入 HTML')
          .height(40)
          .fontSize(12)
          .backgroundColor('#dbeafe')
          .fontColor('#2563eb')
          .borderRadius(20)
          .enabled(!this.isImporting)
          .onClick(() => {
            this.importBookmarks();
          });

        Button(this.isExporting ? '导出中' : '导出 HTML')
          .height(40)
          .fontSize(12)
          .backgroundColor('#ecfccb')
          .fontColor('#3f6212')
          .borderRadius(20)
          .enabled(!this.isExporting)
          .onClick(() => {
            this.exportBookmarks();
          });
      }
      .width('100%');

      Row({ space: 10 }) {
        TextInput({ text: this.newFolderName, placeholder: '新文件夹名称' })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .backgroundColor('#ffffff')
          .borderRadius(19)
          .padding({ left: 14, right: 14 })
          .border({ width: 1, color: '#dbe3f0' })
          .onChange((value: string) => {
            this.newFolderName = value;
          });

        Button('新建')
          .fontSize(12)
          .height(34)
          .backgroundColor('#2563eb')
          .fontColor('#ffffff')
          .borderRadius(17)
          .onClick(() => this.createFolder());
      }
      .width('100%');

      if (this.statusMessage.trim().length > 0) {
        Text(this.statusMessage)
          .width('100%')
          .fontSize(12)
          .fontColor('#1f2937')
          .padding(12)
          .backgroundColor('#eef2ff')
          .borderRadius(12);
      }

      if (this.viewState.isLoading) {
        Column({ space: 8 }) {
          Text('正在加载书签')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text('请稍候')
            .fontSize(13)
            .fontColor('#6b7280');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else if (this.viewState.errorMessage.length > 0) {
        Column({ space: 8 }) {
          Text(this.viewState.errorMessage)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#991b1b');

          Button('重试')
            .height(32)
            .fontSize(12)
            .backgroundColor('#fee2e2')
            .fontColor('#991b1b')
            .borderRadius(16)
            .onClick(() => this.reloadBookmarks());
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else if (this.viewState.items.length === 0) {
        Column({ space: 8 }) {
          Text('还没有可展示的书签')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text(
            this.viewState.isRootFolder
              ? '在浏览页收藏当前页面，或导入带文件夹层级的 bookmarks.html。'
              : '这个文件夹还没有内容。'
          )
            .fontSize(13)
            .fontColor('#6b7280');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        List({ space: 10 }) {
          ForEach(this.viewState.items, (item: BookmarksPageListItem) => {
            ListItem() {
              this.BookmarkListRow(item);
            }
          }, (item: BookmarksPageListItem) => `${item.id}:${item.title}:${item.faviconUrl ?? ''}:${item.url ?? ''}`);
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0, color: '#00000000' });
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#f7f8fa');
  }
}
