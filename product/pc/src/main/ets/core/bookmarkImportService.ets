// BookmarkImportService：读取并解析 Netscape 书签 HTML。

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import {
  BookmarkImportResult,
  BookmarkImportTarget,
  BookmarkManager,
  ImportedBookmarkEntry,
  ImportedBookmarkFolder,
  ImportedBookmarkItem,
} from './bookmarkManager';

export interface BookmarkImportPreview {
  entries: ImportedBookmarkEntry[];
  totalBookmarks: number;
  totalFolders: number;
}

interface MutableImportedBookmarkFolder extends ImportedBookmarkFolder {
  children: ImportedBookmarkEntry[];
}

export class BookmarkImportService {
  private readonly tokenPattern: RegExp =
    /<DT>\s*<H3\b[^>]*>[\s\S]*?<\/H3>|<DT>\s*<A\b[^>]*>[\s\S]*?<\/A>|<DL\b[^>]*>|<\/DL>/gi;

  async importFromPicker(context: object, bookmarkManager?: BookmarkImportTarget): Promise<BookmarkImportResult> {
    const fileUri = await this.pickHtmlFile(context);
    return this.importFromUri(fileUri, bookmarkManager);
  }

  async importFromUri(fileUri: string, bookmarkManager?: BookmarkImportTarget): Promise<BookmarkImportResult> {
    const html = this.readHtmlFile(fileUri);
    const preview = this.parseHtml(html);
    return (bookmarkManager ?? BookmarkManager.getInstance()).importEntries(preview.entries);
  }

  async importFromRawFile(
    context: object,
    rawFilePath: string,
    bookmarkManager?: BookmarkImportTarget,
  ): Promise<BookmarkImportResult> {
    const html = await this.readRawFile(context, rawFilePath);
    const preview = this.parseHtml(html);
    return (bookmarkManager ?? BookmarkManager.getInstance()).importEntries(preview.entries);
  }

  parseHtml(html: string): BookmarkImportPreview {
    const root: MutableImportedBookmarkFolder = {
      type: 'folder',
      title: '',
      children: [],
      sortOrder: 0,
    };
    const stack: MutableImportedBookmarkFolder[] = [root];
    let pendingFolder: MutableImportedBookmarkFolder | null = null;
    let totalBookmarks = 0;
    let totalFolders = 0;
    let nextSortOrderByParent: Map<MutableImportedBookmarkFolder, number> = new Map();
    nextSortOrderByParent.set(root, 0);

    const matches = html.match(this.tokenPattern);
    if (!matches) {
      return {
        entries: [],
        totalBookmarks: 0,
        totalFolders: 0,
      };
    }

    matches.forEach((token: string) => {
      const normalizedToken = token.trim();
      const currentFolder = stack[stack.length - 1];
      if (/^<DT>\s*<H3\b/i.test(normalizedToken)) {
        const folderTitle = this.extractElementText(normalizedToken, 'H3');
        const folder: MutableImportedBookmarkFolder = {
          type: 'folder',
          title: folderTitle,
          children: [],
          createdAt: this.extractTimestamp(normalizedToken, 'ADD_DATE'),
          updatedAt: this.extractTimestamp(normalizedToken, 'LAST_MODIFIED'),
          sortOrder: this.getNextSortOrder(currentFolder, nextSortOrderByParent),
        };
        currentFolder.children.push(folder);
        pendingFolder = folder;
        nextSortOrderByParent.set(folder, 0);
        totalFolders += 1;
        return;
      }

      if (/^<DT>\s*<A\b/i.test(normalizedToken)) {
        const href = this.extractAttribute(normalizedToken, 'HREF');
        if (!href) {
          return;
        }
        const bookmark: ImportedBookmarkItem = {
          type: 'bookmark',
          url: href,
          title: this.extractElementText(normalizedToken, 'A'),
          faviconUrl: this.extractFavicon(normalizedToken),
          createdAt: this.extractTimestamp(normalizedToken, 'ADD_DATE'),
          updatedAt: this.extractTimestamp(normalizedToken, 'LAST_MODIFIED'),
          sortOrder: this.getNextSortOrder(currentFolder, nextSortOrderByParent),
        };
        currentFolder.children.push(bookmark);
        totalBookmarks += 1;
        pendingFolder = null;
        return;
      }

      if (/^<DL\b/i.test(normalizedToken)) {
        if (pendingFolder) {
          stack.push(pendingFolder);
          pendingFolder = null;
        }
        return;
      }

      if (/^<\/DL>/i.test(normalizedToken)) {
        pendingFolder = null;
        if (stack.length > 1) {
          stack.pop();
        }
      }
    });

    return {
      entries: root.children,
      totalBookmarks: totalBookmarks,
      totalFolders: totalFolders,
    };
  }

  private async pickHtmlFile(context: object): Promise<string> {
    try {
      const documentPicker = new picker.DocumentViewPicker(context as common.UIAbilityContext);
      const uris = await documentPicker.select();
      if (!uris || uris.length === 0) {
        throw new Error('未选择书签文件');
      }
      return uris[0];
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(err?.message ? err.message : '选择书签文件失败');
    }
  }

  private readHtmlFile(fileUri: string): string {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      if (stat.size <= 0) {
        return '';
      }
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer, { offset: 0 });
      return this.stripUtf8Bom(this.decodeUtf8(new Uint8Array(buffer)));
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(err?.message ? err.message : '读取书签文件失败');
    } finally {
      if (file) {
        this.closeFileSafely(file);
      }
    }
  }

  private closeFileSafely(file: fs.File): void {
    try {
      fs.closeSync(file);
    } catch (_) {
    }
  }

  private async readRawFile(context: object, rawFilePath: string): Promise<string> {
    try {
      const hostContext = context as common.UIAbilityContext;
      const data = await hostContext.resourceManager.getRawFileContent(rawFilePath);
      return this.decodeUtf8(data);
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(err?.message ? err.message : '读取内置书签文件失败');
    }
  }

  private getNextSortOrder(
    folder: MutableImportedBookmarkFolder,
    nextSortOrderByParent: Map<MutableImportedBookmarkFolder, number>,
  ): number {
    const next = nextSortOrderByParent.get(folder) ?? 0;
    nextSortOrderByParent.set(folder, next + 1);
    return next;
  }

  private extractElementText(token: string, tagName: string): string {
    const regex = new RegExp(`<${tagName}\\b[^>]*>([\\s\\S]*?)<\\/${tagName}>`, 'i');
    const matched = token.match(regex);
    if (!matched || matched.length < 2) {
      return '';
    }
    return this.decodeHtmlEntities(this.stripTags(matched[1]).trim());
  }

  private extractAttribute(token: string, attributeName: string): string {
    const regex = new RegExp(`(?:^|\\s)${attributeName}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i');
    const matched = token.match(regex);
    if (!matched) {
      return '';
    }
    const value = matched[1] ?? matched[2] ?? matched[3] ?? '';
    return this.decodeHtmlEntities(value.trim());
  }

  private extractFavicon(token: string): string | undefined {
    const iconUri = this.extractAttribute(token, 'ICON_URI');
    if (iconUri) {
      return iconUri;
    }
    const icon = this.extractAttribute(token, 'ICON');
    return icon ? icon : undefined;
  }

  private extractTimestamp(token: string, attributeName: string): number | undefined {
    const value = this.extractAttribute(token, attributeName);
    if (!value) {
      return undefined;
    }
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric <= 0) {
      return undefined;
    }
    return numeric > 1_000_000_000_000 ? numeric : numeric * 1000;
  }

  private stripTags(text: string): string {
    return text.replace(/<[^>]+>/g, '');
  }

  private decodeHtmlEntities(text: string): string {
    if (!text.includes('&')) {
      return text;
    }
    return text
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, '\'')
      .replace(/&#x([0-9a-f]+);/gi, (_: string, hex: string) => String.fromCharCode(parseInt(hex, 16)))
      .replace(/&#(\d+);/g, (_: string, decimal: string) => String.fromCharCode(parseInt(decimal, 10)));
  }

  private decodeUtf8(data: Uint8Array): string {
    let result = '';
    let index = 0;

    while (index < data.length) {
      const byte1 = data[index];
      if ((byte1 & 0x80) === 0) {
        result += String.fromCharCode(byte1);
        index += 1;
        continue;
      }

      if ((byte1 & 0xE0) === 0xC0 && index + 1 < data.length) {
        const byte2 = data[index + 1];
        const codePoint = ((byte1 & 0x1F) << 6) | (byte2 & 0x3F);
        result += String.fromCharCode(codePoint);
        index += 2;
        continue;
      }

      if ((byte1 & 0xF0) === 0xE0 && index + 2 < data.length) {
        const byte2 = data[index + 1];
        const byte3 = data[index + 2];
        const codePoint = ((byte1 & 0x0F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F);
        result += String.fromCharCode(codePoint);
        index += 3;
        continue;
      }

      if ((byte1 & 0xF8) === 0xF0 && index + 3 < data.length) {
        const byte2 = data[index + 1];
        const byte3 = data[index + 2];
        const byte4 = data[index + 3];
        const codePoint =
          ((byte1 & 0x07) << 18) |
          ((byte2 & 0x3F) << 12) |
          ((byte3 & 0x3F) << 6) |
          (byte4 & 0x3F);
        const adjusted = codePoint - 0x10000;
        result += String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
        index += 4;
        continue;
      }

      result += '\uFFFD';
      index += 1;
    }

    return result;
  }

  private stripUtf8Bom(text: string): string {
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
      return text.slice(1);
    }
    return text;
  }
}
