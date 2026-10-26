import { Tab } from './types';

export type AddressSuggestionType = 'search' | 'url' | 'bookmark' | 'history' | 'tab';

export interface AddressSuggestion {
  id: string;
  type: AddressSuggestionType;
  title: string;
  subtitle: string;
  targetUrl: string;
  /** Present for type='tab' so selecting an open-tab result switches tabs. */
  targetTabId?: string;
  /** 网页图标（data URI 或网络 URL），仅在既不属于历史也不属于收藏时展示。 */
  iconUrl?: string;
  /**
   * 成员归属图标：联想去重后幸存的行可能是 primary 'url' 行，但该网址实际
   * 命中了收藏夹/历史记录，此时由 SuggestionService 补写归属，供列表选图标。
   */
  iconKind?: 'history' | 'bookmark';
}

export interface AddressSuggestionContext {
  tabs: Tab[];
  limit: number;
}
