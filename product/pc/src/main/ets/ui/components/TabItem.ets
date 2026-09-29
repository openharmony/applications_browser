// TabItem：单个标签项展示组件。

import { hilog } from '@kit.PerformanceAnalysisKit';

export type TabDisplayMode = 'normal' | 'compact' | 'iconOnly';
export type TabClosePresentation = 'hidden' | 'trailing';

// Keep a 24px hit target while rendering the glyph at a readable 16px size.
// This matches the compact close affordance used by desktop browsers without
// consuming excessive tab width in compact/icon-only layouts.
const TAB_CLOSE_BUTTON_SIZE: number = 24;
// The audio affordance is a fixed-width sibling of the close button, so its
// width has to participate in the tab width budget below. Otherwise a compact
// tab that starts playing audio pushes the title into negative space.
const TAB_AUDIO_BUTTON_SIZE: number = 20;
const TAB_AUDIO_ICON_SIZE: number = 14;
const TAB_FAVICON_CONTAINER_SIZE: number = 16;
const TAB_NORMAL_SIDE_PADDING: number = 14;
const TAB_COMPACT_SIDE_PADDING: number = 10;
const TAB_CONTENT_GAP: number = 6;
const TAB_MIN_TITLE_WIDTH: number = 12;
const FAVICON_LOG_DOMAIN: number = 0x0000;
const FAVICON_LOG_TAG: string = 'FaviconTrace';

@Component
export struct TabItem {
  @Prop tabId: string = '';
  @Prop title: string = '标签页';
  @Prop @Watch('handleFaviconUrlChanged') faviconUrl: string = '';
  @Prop @Watch('handleRuntimeFaviconChanged') favicon: PixelMap | null = null;
  @Prop runtimeFaviconSource: 'fallback' | 'callback' = 'callback';
  @Prop @Watch('handleFaviconDataUriChanged') faviconDataUri: string = '';
  @Prop tabWidth: number = 232;
  @Prop displayMode: TabDisplayMode = 'normal';
  @Prop closePresentation: TabClosePresentation = 'hidden';
  @Prop isActive: boolean = false;
  @Prop @Watch('handleLoadingChanged') isLoading: boolean = false;
  @Prop isPrivate: boolean = false;
  @Prop audible: boolean = false;
  @Prop muted: boolean = false;
  @Prop canClose: boolean = true;

  @State private failedRuntimeFavicon: boolean = false;
  @State private failedFaviconUrl: string = '';
  @State private failedFaviconDataUri: string = '';
  private lastRenderTrace: string = '';
  private lastRuntimeFavicon: PixelMap | null = null;

  private handleFaviconUrlChanged(): void {
    // A different navigation must be allowed to use its own fallback source.
    this.failedRuntimeFavicon = false;
    this.failedFaviconUrl = '';
    this.traceFaviconImage('PROP_URL_CHANGED');
  }

  private handleRuntimeFaviconChanged(): void {
    // A fresh app-owned PixelMap must not inherit a rendering failure from a
    // previous document.
    if (this.favicon === this.lastRuntimeFavicon) {
      // Parent rebuilds (for example DATA_URI_SET) can invoke @Watch even
      // though the PixelMap identity did not change. Retrying it would produce
      // repeated UI_RUNTIME_ERROR events and needless icon churn.
      this.traceFaviconImage('PROP_RUNTIME_REBOUND', 'samePixelMap=true');
      return;
    }
    this.lastRuntimeFavicon = this.favicon;
    this.failedRuntimeFavicon = false;
    this.traceFaviconImage('PROP_RUNTIME_CHANGED');
  }

  private handleFaviconDataUriChanged(): void {
    this.failedFaviconDataUri = '';
    // Data URI is retained for bookmark persistence only. It is deliberately
    // not a tab-strip render source because ArkUI data-URI decoding is not
    // consistent and a late encode completion must not hide a visible icon.
    this.traceFaviconImage('PROP_DATA_CHANGED', `dataUriLength=${this.faviconDataUri.length}`);
  }

  private handleLoadingChanged(): void {
    if (this.isLoading) {
      // Reloading the same URL is still a new navigation. Retry both sources
      // instead of carrying a transient image failure into that navigation.
      this.failedRuntimeFavicon = false;
      this.failedFaviconUrl = '';
      this.traceFaviconImage('PROP_LOADING_CHANGED', 'loading=true resetFailures=true');
    }
  }

  onSelect: () => void = () => {};
  onClose: () => void = () => {};
  onPointerMouse: (event: MouseEvent) => void = (_event: MouseEvent): void => {};
  onToggleMute: () => void = () => {};
  onHoverIn: () => void = () => {};
  onHoverOut: () => void = () => {};

  private getFaviconBackground(): string {
    if (this.isLoading || this.favicon !== null) {
      return '#00000000';
    }
    if (this.isPrivate) {
      return '#ede9fe';
    }
    if (this.isActive) {
      return '#eff6ff';
    }
    return '#f3f4f6';
  }

  private shouldShowRuntimeFavicon(): boolean {
    // PixelMaps returned by ArkWeb are not a safe long-lived ArkUI source.
    // ArkUI may rebind an Image when another tab is added, while the native
    // PixelMap backing store can already have been recycled. The presentation
    // layer therefore uses the stable URL/data-URI sources below instead.
    return false;
  }

  private shouldShowFaviconUrl(): boolean {
    const source = this.faviconUrl.trim();
    // Keep the URL mounted as a stable base and as a fallback if ArkUI rejects
    // the callback-owned PixelMap. It must not be hidden merely because a
    // runtime copy was delivered: that copy can become invalid after a
    // component rebind while the remote image remains perfectly usable.
    return /^https?:\/\//i.test(source) && this.failedFaviconUrl !== source;
  }

  private shouldShowFaviconDataUri(): boolean {
    const source = this.faviconDataUri.trim();
    return source.length > 0 && source !== this.failedFaviconDataUri;
  }

  private shouldShowDataUriFallback(): boolean {
    return this.shouldShowFaviconDataUri();
  }

  private shouldShowCloseButton(): boolean {
    return this.canClose && this.closePresentation === 'trailing';
  }

  private getHorizontalPadding(): number {
    return this.displayMode === 'normal' ? TAB_NORMAL_SIDE_PADDING : TAB_COMPACT_SIDE_PADDING;
  }

  private getRightPadding(): number {
    // The close affordance is intentionally kept close to the trailing edge,
    // while tabs without a close button retain the normal symmetric padding.
    return this.shouldShowCloseButton() ? 6 : this.getHorizontalPadding();
  }

  private shouldShowAudioButton(): boolean {
    // The muted state is deliberately sticky: a muted page keeps its control
    // mounted even while it is silent, so the user always has a way back to the
    // unmuted state from the tab strip.
    if (!this.audible && !this.muted) {
      return false;
    }
    // Decide from the tab width alone. Deriving this from the leading content
    // width would make the two calculations circular, and the audio control
    // outranks the title when space is tight.
    const chromeWidth = this.getHorizontalPadding() + this.getRightPadding() +
      (this.shouldShowCloseButton() ? TAB_CLOSE_BUTTON_SIZE + TAB_CONTENT_GAP : 0);
    return this.tabWidth - chromeWidth >= TAB_AUDIO_BUTTON_SIZE;
  }

  private getAudioReservedWidth(): number {
    return this.shouldShowAudioButton() ? TAB_AUDIO_BUTTON_SIZE + TAB_CONTENT_GAP : 0;
  }

  private getLeadingContentWidth(): number {
    const leftPadding = this.getHorizontalPadding();
    const rightPadding = this.getRightPadding();
    const closeWidth = this.shouldShowCloseButton() ? TAB_CLOSE_BUTTON_SIZE : 0;
    const closeGap = this.shouldShowCloseButton() ? TAB_CONTENT_GAP : 0;
    const available = this.tabWidth - leftPadding - rightPadding - closeWidth - closeGap -
      this.getAudioReservedWidth();
    return available > 0 ? available : 0;
  }

  private shouldShowFavicon(): boolean {
    return this.getLeadingContentWidth() >= TAB_FAVICON_CONTAINER_SIZE;
  }

  private traceFaviconImage(stage: string, detail: string = ''): void {
    let runtimeInfo = 'none';
    if (this.favicon !== null) {
      try {
        const info = this.favicon.getImageInfoSync();
        runtimeInfo = `${info.size.width}x${info.size.height} bytes=${this.favicon.getPixelBytesNumber()} ` +
          `format=${info.pixelFormat} alpha=${info.alphaType} editable=${this.favicon.isEditable}`;
      } catch (_) {
        runtimeInfo = 'unavailable';
      }
    }
    hilog.info(FAVICON_LOG_DOMAIN, FAVICON_LOG_TAG,
      '%{public}s tab=%{public}s runtime=%{public}s urlLength=%{public}d loading=%{public}s ' +
      'runtimeInfo=%{public}s %{public}s',
      stage, this.tabId, String(this.favicon !== null), this.faviconUrl.length, String(this.isLoading),
      runtimeInfo, detail);
  }

  private getRenderSourceSummary(): string {
    const sources: string[] = [];
    if (this.shouldShowFaviconUrl()) {
      sources.push('url');
    } else if (this.shouldShowRuntimeFavicon()) {
      sources.push('runtime');
    } else if (this.shouldShowDataUriFallback()) {
      sources.push('data');
    } else {
      sources.push('default');
    }
    if (this.isLoading) {
      sources.push('loading');
    }
    return sources.join('+');
  }

  private traceRenderIfChanged(): void {
    const signature = `${this.faviconUrl}|${this.faviconDataUri.length}|${this.favicon !== null ? 'runtime' : 'none'}|` +
      `${this.isLoading ? 'loading' : 'idle'}|${this.failedFaviconUrl}|${this.failedRuntimeFavicon}|` +
      `${this.getRenderSourceSummary()}`;
    if (signature === this.lastRenderTrace) {
      return;
    }
    this.lastRenderTrace = signature;
    this.traceFaviconImage('TAB_RENDER',
      `source=${this.getRenderSourceSummary()} dataUriLength=${this.faviconDataUri.length} ` +
      `failedUrl=${this.failedFaviconUrl.length > 0 ? this.failedFaviconUrl : 'none'} ` +
      `failedRuntime=${this.failedRuntimeFavicon}`);
  }

  aboutToAppear(): void {
    this.traceFaviconImage('TAB_APPEAR',
      `title=${this.title} audible=${this.audible} muted=${this.muted} tabWidth=${this.tabWidth} ` +
      `displayMode=${this.displayMode} audioButton=${this.shouldShowAudioButton()}`);
    this.traceRenderIfChanged();
  }

  aboutToDisappear(): void {
    this.traceFaviconImage('TAB_DISAPPEAR');
  }

  private shouldShowTitle(): boolean {
    if (this.displayMode === 'iconOnly' && !this.shouldShowCloseButton()) {
      return false;
    }

    let remainingWidth = this.getLeadingContentWidth();
    if (this.shouldShowFavicon()) {
      remainingWidth = remainingWidth - TAB_FAVICON_CONTAINER_SIZE - TAB_CONTENT_GAP;
    }
    return remainingWidth >= TAB_MIN_TITLE_WIDTH;
  }

  @Builder
  private CloseButton() {
    Stack({ alignContent: Alignment.Center }) {
      Text('×')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#7a8390')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height('100%');
    }
      .width(TAB_CLOSE_BUTTON_SIZE)
      .height(TAB_CLOSE_BUTTON_SIZE)
      .backgroundColor('#00000000')
      .borderRadius(TAB_CLOSE_BUTTON_SIZE / 2)
      .onClick(() => this.onClose());
  }

  @Builder
  private AudioButton() {
    Stack({ alignContent: Alignment.Center }) {
      // Two baked SVG variants instead of a recoloured glyph: ArkUI tints SVG
      // fills inconsistently across API levels, and the muted/unmuted shapes
      // already carry the state without relying on a runtime colour swap.
      Image(this.muted ? $r('app.media.tab_audio_muted') : $r('app.media.tab_audio_playing'))
        .width(TAB_AUDIO_ICON_SIZE)
        .height(TAB_AUDIO_ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .draggable(false);
    }
      .width(TAB_AUDIO_BUTTON_SIZE)
      .height(TAB_AUDIO_BUTTON_SIZE)
      .backgroundColor('#00000000')
      .borderRadius(TAB_AUDIO_BUTTON_SIZE / 2)
      .onClick(() => this.onToggleMute());
  }

  @Builder
  private DefaultSiteIcon() {
    Image($r('app.media.default_site_icon'))
      .width(14)
      .height(14)
      .objectFit(ImageFit.Contain)
      .opacity(this.isPrivate ? 0.88 : 0.76);
  }

  @Builder
  private FaviconView() {
    // Render exactly one asynchronous favicon source. Keeping URL, PixelMap
    // and data URI images mounted together lets a late failure or callback
    // cover the current icon and makes source switches visibly flicker.
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        // Keep a static icon under every asynchronous source. ArkUI may not
        // report every remote-image decoding failure, so hiding this base icon
        // can otherwise leave a blank favicon slot.
        this.DefaultSiteIcon();

        // Put the progress ring behind a slightly smaller icon. The ring is
        // still visible around the edge, while the favicon remains readable
        // as soon as either source has loaded.
        if (this.isLoading) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.isActive ? '#2563eb' : '#6b7280')
            .enableLoading(true);
        }

        // Render one stable source at a time. Once the callback has been
        // encoded, the data URI wins over the remote URL; this prevents two
        // asynchronous Image nodes from racing and avoids a stale PixelMap
        // blanking an otherwise valid favicon when a new tab is opened.
        if (this.shouldShowDataUriFallback()) {
          Image(this.faviconDataUri.trim())
            .width(12)
            .height(12)
            .borderRadius(3)
            .objectFit(ImageFit.Contain)
            .onComplete((event) => {
              this.traceFaviconImage('UI_DATA_COMPLETE', `${event?.width ?? 0}x${event?.height ?? 0}`);
            })
            .onError(() => {
              this.failedFaviconDataUri = this.faviconDataUri.trim();
              this.traceFaviconImage('UI_DATA_ERROR');
            });
        } else if (this.shouldShowFaviconUrl()) {
          Image(this.faviconUrl.trim())
            .width(12)
            .height(12)
            .borderRadius(3)
            .objectFit(ImageFit.Contain)
            .onError(() => {
              this.failedFaviconUrl = this.faviconUrl.trim();
              this.traceFaviconImage('UI_URL_ERROR');
            })
            .onComplete((event) => {
              this.traceFaviconImage('UI_URL_COMPLETE', `${event?.width ?? 0}x${event?.height ?? 0}`);
            });
        }

      }
      .width(14)
      .height(14);
    }
    .width(TAB_FAVICON_CONTAINER_SIZE)
    .height(TAB_FAVICON_CONTAINER_SIZE)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.getFaviconBackground());
  }

  build() {
    Row() {
      Row({ space: TAB_CONTENT_GAP }) {
        if (this.shouldShowFavicon()) {
          this.FaviconView();
        }

        if (this.shouldShowTitle()) {
          Text(this.title)
            .layoutWeight(1)
            .fontSize(13)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.isActive ? '#3d434d' : '#6e7684');
        }

        if (this.shouldShowAudioButton()) {
          this.AudioButton();
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .constraintSize({ minWidth: 0 });

      if (this.shouldShowCloseButton()) {
        this.CloseButton();
      }
    }
    .padding({ left: this.getHorizontalPadding(), right: this.getRightPadding(), top: 7, bottom: 7 })
    .width(this.tabWidth)
    .height(32)
    .backgroundColor(this.isActive ? '#ffffff' : '#f0f0f1')
    .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 0, bottomRight: 0 })
    .opacity(this.isActive ? 1 : 0.9)
    .justifyContent(FlexAlign.SpaceBetween)
    .onClick(() => this.onSelect())
    .onMouse((event: MouseEvent) => this.onPointerMouse(event))
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.onHoverIn();
        return;
      }
      this.onHoverOut();
    });
  }
}
