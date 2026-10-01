// BookmarkExportService：导出书签树为 Netscape Bookmark HTML。

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { BookmarkExportSource, BookmarkManager, BookmarkTreeNode } from './bookmarkManager';

export interface BookmarkExportResult {
  fileUri: string;
  totalBookmarks: number;
  totalFolders: number;
}

interface BookmarkTreeStats {
  totalBookmarks: number;
  totalFolders: number;
}

export class BookmarkExportService {
  async exportToPicker(context: object, bookmarkManager?: BookmarkExportSource): Promise<BookmarkExportResult> {
    const manager = bookmarkManager ?? BookmarkManager.getInstance();
    const tree = manager.listTree();
    const html = this.serializeTree(tree);
    const fileUri = await this.saveHtmlWithPicker(context, html);
    const stats = this.countTree(tree);
    return {
      fileUri: fileUri,
      totalBookmarks: stats.totalBookmarks,
      totalFolders: stats.totalFolders,
    };
  }

  serializeTree(tree: BookmarkTreeNode[]): string {
    const lines: string[] = [
      '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
      '<!-- This is an automatically generated file.',
      '     It will be read and overwritten.',
      '     DO NOT EDIT! -->',
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
      '<TITLE>Bookmarks</TITLE>',
      '<H1>Bookmarks</H1>',
      '<DL><p>',
    ];
    this.appendNodes(lines, tree, 1);
    lines.push('</DL><p>');
    return lines.join('\n');
  }

  private async saveHtmlWithPicker(context: object, html: string): Promise<string> {
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [this.buildDefaultFileName()];
      saveOptions.fileSuffixChoices = ['Bookmarks HTML|.html'];

      const documentPicker = new picker.DocumentViewPicker(context as common.UIAbilityContext);
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        throw new Error('未选择导出位置');
      }

      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
      try {
        fs.writeSync(file.fd, html);
      } finally {
        fs.closeSync(file);
      }
      return uris[0];
    } catch (error) {
      const err = error as BusinessError;
      throw new Error(err?.message ? err.message : '导出书签失败');
    }
  }

  private appendNodes(lines: string[], nodes: BookmarkTreeNode[], depth: number): void {
    nodes.forEach((node: BookmarkTreeNode) => {
      const indent = this.indent(depth);
      if (node.type === 'folder') {
        lines.push(
          `${indent}<DT><H3${this.buildTimestampAttributes(node.createdAt, node.updatedAt)}>` +
            `${this.escapeHtml(node.title)}</H3>`,
        );
        lines.push(`${indent}<DL><p>`);
        this.appendNodes(lines, node.children, depth + 1);
        lines.push(`${indent}</DL><p>`);
        return;
      }

      lines.push(
        `${indent}<DT><A${this.buildBookmarkAttributes(node)}>${this.escapeHtml(node.title)}</A>`,
      );
    });
  }

  private buildBookmarkAttributes(node: BookmarkTreeNode): string {
    const attributes: string[] = [];
    if (node.url) {
      attributes.push(` HREF="${this.escapeAttribute(node.url)}"`);
    }

    const timestampAttributes = this.buildTimestampAttributes(node.createdAt, node.updatedAt);
    if (timestampAttributes) {
      attributes.push(timestampAttributes);
    }

    if (node.faviconUrl && node.faviconUrl.trim().length > 0) {
      const faviconUrl = node.faviconUrl.trim();
      if (faviconUrl.startsWith('data:')) {
        attributes.push(` ICON="${this.escapeAttribute(faviconUrl)}"`);
      } else {
        attributes.push(` ICON_URI="${this.escapeAttribute(faviconUrl)}"`);
      }
    }
    return attributes.join('');
  }

  private buildTimestampAttributes(createdAt: number, updatedAt: number): string {
    const attributes: string[] = [];
    if (createdAt > 0) {
      attributes.push(` ADD_DATE="${Math.floor(createdAt / 1000)}"`);
    }
    if (updatedAt > 0) {
      attributes.push(` LAST_MODIFIED="${Math.floor(updatedAt / 1000)}"`);
    }
    return attributes.join('');
  }

  private countTree(tree: BookmarkTreeNode[]): BookmarkTreeStats {
    const stats: BookmarkTreeStats = {
      totalBookmarks: 0,
      totalFolders: 0,
    };

    const visit = (nodes: BookmarkTreeNode[]): void => {
      nodes.forEach((node: BookmarkTreeNode) => {
        if (node.type === 'folder') {
          stats.totalFolders += 1;
          visit(node.children);
          return;
        }
        stats.totalBookmarks += 1;
      });
    };
    visit(tree);
    return stats;
  }

  private buildDefaultFileName(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = this.padNumber(now.getMonth() + 1);
    const date = this.padNumber(now.getDate());
    const hour = this.padNumber(now.getHours());
    const minute = this.padNumber(now.getMinutes());
    const second = this.padNumber(now.getSeconds());
    return `bookmarks_${year}${month}${date}_${hour}${minute}${second}.html`;
  }

  private padNumber(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private indent(depth: number): string {
    return '    '.repeat(depth);
  }

  private escapeHtml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private escapeAttribute(text: string): string {
    return this.escapeHtml(text);
  }
}
