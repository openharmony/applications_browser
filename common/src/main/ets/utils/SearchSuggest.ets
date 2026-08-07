import { BookmarkItem } from '../model/BookmarkItem'
import { HistoryEntry } from '../model/HistoryEntry'

/** 搜索建议项 */
export interface SearchSuggestion {
  /** 展示文本 */
  text: string
  /** 建议类型 */
  kind: 'history' | 'url' | 'search'
  /** 点击后实际跳转地址（标题类建议指向对应 URL） */
  navigateUrl?: string
}

/**
 * 根据输入生成搜索/网址补全建议（历史搜索、浏览历史 URL、书签 URL）
 */
export class SearchSuggest {
  private static normalizeUrl(url: string): string {
    const u = url.trim()
    if (!u) {
      return ''
    }
    if (/^https?:\/\//i.test(u)) {
      return u
    }
    return `https://${u}`
  }

  /** 收集最多 max 条不重复建议 */
  static build(
    query: string,
    searchHistory: string[],
    historyList: HistoryEntry[],
    bookmarks: BookmarkItem[],
    max: number = 8
  ): SearchSuggestion[] {
    const q = query.trim().toLowerCase()
    if (!q) {
      return []
    }
    const out: SearchSuggestion[] = []
    const seen = new Set<string>()

    const push = (text: string, kind: 'history' | 'url' | 'search', navigateUrl?: string): void => {
      const key = text.toLowerCase()
      if (seen.has(key) || !key.includes(q)) {
        return
      }
      seen.add(key)
      out.push({ text, kind, navigateUrl: navigateUrl ?? text })
    }

    for (const item of searchHistory) {
      if (out.length >= max) {
        break
      }
      push(item, 'search')
    }
    for (const h of historyList) {
      if (out.length >= max) {
        break
      }
      push(h.url, 'url')
      if (h.title && h.title.toLowerCase().includes(q)) {
        push(h.title, 'search')
      }
    }
    for (const b of bookmarks) {
      if (out.length >= max || b.isFolder || !b.url) {
        continue
      }
      push(b.url, 'url')
      if (b.title.toLowerCase().includes(q)) {
        push(b.title, 'search')
      }
    }
    if (out.length < max && /^[\w.-]+\./.test(q)) {
      push(SearchSuggest.normalizeUrl(q), 'url')
    }
    return out.slice(0, max)
  }

  /** 浏览页地址栏：仅书签 + 浏览历史匹配（不含搜索历史） */
  static buildBookmarkHistory(
    query: string,
    historyList: HistoryEntry[],
    bookmarks: BookmarkItem[],
    max: number = 8
  ): SearchSuggestion[] {
    const q = query.trim().toLowerCase()
    if (!q) {
      return []
    }
    const out: SearchSuggestion[] = []
    const seen = new Set<string>()

    const push = (text: string, kind: 'history' | 'url' | 'search', navigateUrl: string): void => {
      const displayKey = text.toLowerCase()
      const urlKey = navigateUrl.toLowerCase()
      if (seen.has(urlKey)) {
        return
      }
      if (!displayKey.includes(q) && !urlKey.includes(q)) {
        return
      }
      seen.add(urlKey)
      out.push({ text, kind, navigateUrl })
    }

    for (const h of historyList) {
      if (out.length >= max) {
        break
      }
      push(h.url, 'url', h.url)
      if (h.title && h.title.toLowerCase().includes(q)) {
        push(h.title, 'history', h.url)
      }
    }
    for (const b of bookmarks) {
      if (out.length >= max || b.isFolder || !b.url) {
        continue
      }
      push(b.url, 'url', b.url)
      if (b.title.toLowerCase().includes(q)) {
        push(b.title, 'search', b.url)
      }
    }
    if (out.length < max && /^[\w.-]+\./.test(q)) {
      const guess = SearchSuggest.normalizeUrl(q)
      push(guess, 'url', guess)
    }
    return out.slice(0, max)
  }
}
