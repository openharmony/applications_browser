import { BookmarkItem } from '../../core/bookmarkManager';

@Component
export struct BookmarkBar {
  @Prop bookmarks: BookmarkItem[] = [];
  @Prop availableWidth: number = 1280;
  @Prop isPrivate: boolean = false;
  // 跨组件拖入：书签文件夹弹出菜单里拖起的书签，drop 时由宿主实时解析。
  // 不用 @Prop 注入——拖拽开始瞬间注入会触发父组件重渲染，可能打断 drag 会话。
  resolveExternalDragSource: () => BookmarkItem | null = (): BookmarkItem | null => null;

  @State private hoveredBookmarkId: string = '';
  @State private overflowHovered: boolean = false;
  @State private failedFaviconKeys: string[] = [];
  @State private dragOverBookmarkId: string = '';

  onOpenBookmark: (bookmark: BookmarkItem) => void = (_: BookmarkItem) => {};
  onOpenFolder: (
    folder: BookmarkItem,
    x: number,
    y: number
  ) => void = (_folder: BookmarkItem, _x: number, _y: number) => {};
  onBookmarkContextMenu: (bookmark: BookmarkItem, x: number, y: number) => void =
    (_bookmark: BookmarkItem, _x: number, _y: number) => {};
  onBookmarkBarContextMenu: (x: number, y: number) => void = (_x: number, _y: number) => {};
  onBookmarkDragStart: (bookmark: BookmarkItem) => void = (_bookmark: BookmarkItem) => {};
  onBookmarkDrop: (source: BookmarkItem, target: BookmarkItem | null, targetIndex: number) => void =
    (_source: BookmarkItem, _target: BookmarkItem | null, _targetIndex: number) => {};

  private readonly horizontalPadding: number = 20;
  private readonly itemGap: number = 4;
  private readonly overflowButtonWidth: number = 48;
  private readonly minBookmarkWidth: number = 40;
  private readonly maxBookmarkWidth: number = 168;

  private getBookmarkTextWidth(title: string): number {
    let width = 0;
    const normalizedTitle = title.trim();
    for (let index = 0; index < normalizedTitle.length; index++) {
      const code = normalizedTitle.charCodeAt(index);
      if ((code >= 0x2E80 && code <= 0x9FFF) || (code >= 0xF900 && code <= 0xFAFF)) {
        width += 12;
      } else if (code >= 65 && code <= 90) {
        width += 8;
      } else {
        width += 7;
      }
    }
    return width;
  }

  private getBookmarkItemWidth(bookmark: BookmarkItem): number {
    const estimatedWidth = 38 + this.getBookmarkTextWidth(bookmark.title);
    return Math.min(this.maxBookmarkWidth, Math.max(this.minBookmarkWidth, estimatedWidth));
  }

  private getFaviconKey(bookmark: BookmarkItem): string {
    return `${bookmark.id}:${bookmark.faviconUrl ?? ''}`;
  }

  // ForEach reuses items whose keys are unchanged, so the key must cover
  // every field the row renders. A rename keeps the id but changes the
  // title — an id-only key leaves the stale title on screen.
  private getBookmarkRowKey(bookmark: BookmarkItem): string {
    return `${bookmark.id}:${bookmark.title}:${bookmark.faviconUrl ?? ''}`;
  }

  private markFaviconFailed(bookmark: BookmarkItem): void {
    const key = this.getFaviconKey(bookmark);
    if (this.failedFaviconKeys.indexOf(key) < 0) {
      this.failedFaviconKeys = this.failedFaviconKeys.concat([key]);
    }
  }

  private canRenderFavicon(bookmark: BookmarkItem): boolean {
    const faviconUrl = bookmark.faviconUrl ? bookmark.faviconUrl.trim() : '';
    return faviconUrl.length > 0 && this.failedFaviconKeys.indexOf(this.getFaviconKey(bookmark)) < 0;
  }

  private getFaviconSource(bookmark: BookmarkItem): string {
    return bookmark.faviconUrl ? bookmark.faviconUrl.trim() : '';
  }

  /**
   * Native MenuItem accepts both a remote/data URI and a local ResourceStr.
   * Keep the overflow menu visually consistent with the inline bar: folders
   * use the folder asset and bookmarks always have a deterministic fallback
   * instead of an icon-less row.
   */
  private getOverflowIcon(bookmark: BookmarkItem): ResourceStr {
    if (bookmark.isFolder) {
      return $r('app.media.home_tab_folder');
    }
    return this.canRenderFavicon(bookmark)
      ? this.getFaviconSource(bookmark)
      : $r('app.media.default_site_icon');
  }

  private resolveMouseCoordinate(value: number, fallback: number): number {
    const normalized = Number(value);
    return Number.isFinite(normalized) && normalized >= 0 ? normalized : Math.max(0, fallback);
  }

  private handleBookmarkMouse(bookmark: BookmarkItem, event: MouseEvent): void {
    if (event.button !== MouseButton.Right) {
      return;
    }
    event.stopPropagation();
    const x = this.resolveMouseCoordinate(Number(event.windowX), Number(event.displayX));
    const y = this.resolveMouseCoordinate(Number(event.windowY), Number(event.displayY));
    this.onBookmarkContextMenu(bookmark, x, y);
  }

  private handleBookmarkDrop(bookmark: BookmarkItem): void {
    let source = this.bookmarks.find((item: BookmarkItem) => item.id === this.draggingBookmarkId) ??
      this.resolveExternalDragSource() ?? undefined;
    if (!source) {
      this.clearDragState();
      return;
    }
    const targetIndex = this.bookmarks.findIndex((item: BookmarkItem) => item.id === bookmark.id);
    this.onBookmarkDrop(source, bookmark, targetIndex);
    this.clearDragState();
    this.dragOverBookmarkId = '';
  }

  @State private draggingBookmarkId: string = '';

  private clearDragState(): void {
    this.draggingBookmarkId = '';
    this.dragOverBookmarkId = '';
  }

  private getBookmarksAvailableWidth(): number {
    return Math.max(0, this.availableWidth - this.horizontalPadding);
  }

  private countFittingBookmarks(availableWidth: number): number {
    let usedWidth = 0;
    let count = 0;
    for (let index = 0; index < this.bookmarks.length; index++) {
      const gap = count > 0 ? this.itemGap : 0;
      const nextWidth = gap + this.getBookmarkItemWidth(this.bookmarks[index]);
      if (usedWidth + nextWidth > availableWidth) {
        break;
      }
      usedWidth += nextWidth;
      count += 1;
    }
    return count;
  }

  private getVisibleBookmarkCount(): number {
    const availableWidth = this.getBookmarksAvailableWidth();
    const countWithoutOverflow = this.countFittingBookmarks(availableWidth);
    if (countWithoutOverflow >= this.bookmarks.length) {
      return this.bookmarks.length;
    }

    const overflowReservedWidth = this.overflowButtonWidth + this.itemGap;
    return this.countFittingBookmarks(Math.max(0, availableWidth - overflowReservedWidth));
  }

  private getVisibleBookmarks(): BookmarkItem[] {
    return this.bookmarks.slice(0, this.getVisibleBookmarkCount());
  }

  private getOverflowBookmarks(): BookmarkItem[] {
    return this.bookmarks.slice(this.getVisibleBookmarkCount());
  }

  private getOverflowMenuWidth(): number {
    return Math.min(320, Math.max(220, this.availableWidth - 24));
  }

  private getItemBackgroundColor(): string {
    return this.isPrivate ? '#2b3039' : '#ffffff';
  }

  private getHoverBackgroundColor(): string {
    return this.isPrivate ? '#3a414d' : '#e8edf3';
  }

  private getBookmarkBackgroundColor(bookmarkId: string): string {
    return this.hoveredBookmarkId === bookmarkId ? this.getHoverBackgroundColor() : this.getItemBackgroundColor();
  }

  private getItemTextColor(): string {
    return this.isPrivate ? '#d7dce5' : '#4b5563';
  }

  private getMutedTextColor(): string {
    return this.isPrivate ? '#9ca3af' : '#6b7280';
  }

  @Builder
  private BookmarkFavicon(bookmark: BookmarkItem, size: number) {
    if (bookmark.isFolder) {
      Image($r('app.media.home_tab_folder'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
        .opacity(this.isPrivate ? 0.88 : 0.72);
    } else if (this.canRenderFavicon(bookmark)) {
      Image(this.getFaviconSource(bookmark))
        .width(size)
        .height(size)
        .borderRadius(3)
        .objectFit(ImageFit.Contain)
        .onError(() => this.markFaviconFailed(bookmark));
    } else {
      Image($r('app.media.default_site_icon'))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
        .opacity(0.72);
    }
  }

  @Builder
  private BookmarkButton(bookmark: BookmarkItem) {
    Row({ space: 6 }) {
      this.BookmarkFavicon(bookmark, 12);

      Text(bookmark.title)
        .layoutWeight(1)
        .fontSize(12)
        .fontColor(this.getItemTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width(this.getBookmarkItemWidth(bookmark))
    .height(28)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.getBookmarkBackgroundColor(bookmark.id))
    .border({ width: this.dragOverBookmarkId === bookmark.id ? 2 : 0, color: '#1976d2' })
    .borderRadius(5)
    .accessibilityText(bookmark.title)
    .onHover((isHover: boolean) => {
      this.hoveredBookmarkId = isHover ? bookmark.id : '';
    })
    .onClick((event: ClickEvent) => {
      const rawX = Number(event.windowX);
      const rawY = Number(event.windowY);
      if (bookmark.isFolder) {
        this.onOpenFolder(bookmark, this.resolveMouseCoordinate(rawX, 0), this.resolveMouseCoordinate(rawY, 36));
      } else {
        this.onOpenBookmark(bookmark);
      }
    })
    .onMouse((event: MouseEvent) => this.handleBookmarkMouse(bookmark, event))
    .draggable(true)
    .onDragStart(() => {
      this.draggingBookmarkId = bookmark.id;
      this.onBookmarkDragStart(bookmark);
    })
    .onDragEnter(() => {
      if (this.draggingBookmarkId !== bookmark.id) {
        this.dragOverBookmarkId = bookmark.id;
      }
    })
    .onDragLeave(() => {
      if (this.dragOverBookmarkId === bookmark.id) {
        this.dragOverBookmarkId = '';
      }
    })
    .onDrop(() => this.handleBookmarkDrop(bookmark))
    .onDragEnd(() => this.clearDragState());
  }

  @Builder
  private OverflowMenu() {
    Menu() {
      ForEach(this.getOverflowBookmarks(), (bookmark: BookmarkItem) => {
        MenuItem({
          startIcon: this.getOverflowIcon(bookmark),
          content: bookmark.isFolder ? `${bookmark.title}  ›` : bookmark.title,
        })
          .onClick(() => bookmark.isFolder ? this.onOpenFolder(bookmark, 0, 36) : this.onOpenBookmark(bookmark));
      }, (bookmark: BookmarkItem) => this.getBookmarkRowKey(bookmark));
    }
    .width(this.getOverflowMenuWidth());
  }

  @Builder
  private OverflowButton() {
    Row({ space: 3 }) {
      Text('»')
        .fontSize(18)
        .fontColor(this.getItemTextColor());

      Text(`${this.getOverflowBookmarks().length}`)
        .fontSize(10)
        .fontColor(this.getMutedTextColor());
    }
    .width(this.overflowButtonWidth)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.overflowHovered ? this.getHoverBackgroundColor() : this.getItemBackgroundColor())
    .borderRadius(5)
    .accessibilityText(`更多书签，共 ${this.getOverflowBookmarks().length} 项`)
    .onHover((isHover: boolean) => {
      this.overflowHovered = isHover;
    })
    .bindMenu(this.OverflowMenu, {
      placement: Placement.BottomRight,
      showInSubWindow: false,
    });
  }

  build() {
    Row({ space: this.itemGap }) {
      ForEach(this.getVisibleBookmarks(), (bookmark: BookmarkItem) => {
        this.BookmarkButton(bookmark);
      }, (bookmark: BookmarkItem) => this.getBookmarkRowKey(bookmark));

      if (this.getOverflowBookmarks().length > 0) {
        this.OverflowButton();
      }
    }
    .layoutWeight(1)
    .height('100%')
    .clip(true)
    .onMouse((event: MouseEvent) => {
      if (event.button !== MouseButton.Right) {
        return;
      }
      event.stopPropagation();
      const x = this.resolveMouseCoordinate(Number(event.windowX), Number(event.displayX));
      const y = this.resolveMouseCoordinate(Number(event.windowY), Number(event.displayY));
      this.onBookmarkBarContextMenu(x, y);
    })
    .onDrop(() => {
      let source = this.bookmarks.find((item: BookmarkItem) => item.id === this.draggingBookmarkId) ??
        this.resolveExternalDragSource() ?? undefined;
      if (source) {
        this.onBookmarkDrop(source, null, this.bookmarks.length);
      }
      this.clearDragState();
    })
    .width('100%')
    .height(36)
    .padding({ left: 10, right: 10, top: 4, bottom: 4 });
  }
}
