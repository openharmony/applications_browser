import { AddressSuggestion } from '../../core/addressSuggestionTypes';

@Component
export struct AddressSuggestionPanel {
  @Prop suggestions: AddressSuggestion[] = [];
  @Prop selectedSuggestionId: string = '';
  @Prop maxPanelHeight: number = 320;

  onSelectSuggestion: (suggestion: AddressSuggestion) => void = (_: AddressSuggestion): void => {};

  private isSelected(suggestionId: string): boolean {
    return this.selectedSuggestionId.length > 0 && this.selectedSuggestionId === suggestionId;
  }

  /**
   * 图标优先级：历史记录 > 收藏夹 > 网页自身 favicon > 默认搜索图标。
   * type='history'/'bookmark' 是数据源直接标记；iconKind 是去重后补判的
   * 成员归属（primary 'url' 行可能实际命中收藏/历史）。
   */
  private getSuggestionIcon(suggestion: AddressSuggestion): ResourceStr {
    if (suggestion.type === 'history' || suggestion.iconKind === 'history') {
      return $r('app.media.settings_menu_history');
    }
    if (suggestion.type === 'bookmark' || suggestion.iconKind === 'bookmark') {
      return $r('app.media.icon_gray_folder');
    }
    if (suggestion.iconUrl && suggestion.iconUrl.length > 0) {
      return suggestion.iconUrl;
    }
    return $r('app.media.home_search');
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        ForEach(this.suggestions, (suggestion: AddressSuggestion) => {
          Row({ space: 10 }) {
            Image(this.getSuggestionIcon(suggestion))
              .width(18)
              .height(18)
              .objectFit(ImageFit.Contain)
              .opacity(0.86);

            Column({ space: 2 }) {
              Text(suggestion.title)
                .fontSize(13)
                .fontColor('#111827')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              Text(suggestion.subtitle)
                .fontSize(11)
                .fontColor('#6b7280')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 11, bottom: 11 })
          .backgroundColor(this.isSelected(suggestion.id) ? '#eff6ff' : '#ffffff')
          .border({ width: { bottom: 1 }, color: '#eef2f7' })
          .onClick((): void => this.onSelectSuggestion(suggestion));
        }, (suggestion: AddressSuggestion): string => suggestion.id);
      }
      .width('100%');
    }
    .scrollBar(BarState.Auto)
    .width('100%')
    .constraintSize({ maxHeight: this.maxPanelHeight })
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .clip(true)
    .border({ width: 1, color: '#dbe3f0' })
    .onClick(() => {});
  }
}
