// faviconService：将 ArkWeb 返回的 PixelMap 编码为可持久化的图片 data URI。

import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { normalizeHttpUrlForStorage } from './urlNormalizer';

const MAX_FAVICON_PIXEL_BYTES: number = 4 * 1024 * 1024;

/**
 * Returns the stable cache key for a favicon resource. The icon belongs to
 * the favicon URL, not to a tab or a document URL: two tabs showing the same
 * site should be able to reuse the encoded image, while different favicon
 * paths (or version query strings) remain isolated.
 */
export function normalizeFaviconCacheKey(url: string | undefined): string {
  const source = (url ?? '').trim();
  if (!/^https?:\/\//i.test(source)) {
    return '';
  }
  return normalizeHttpUrlForStorage(source);
}

function hasNonEmptyPixelData(pixels: ArrayBuffer): boolean {
  const bytes = new Uint8Array(pixels);
  for (let index = 0; index < bytes.length; index++) {
    if (bytes[index] !== 0) {
      return true;
    }
  }
  return false;
}

/**
 * Copies the pixel buffer while the ArkWeb callback object is still valid.
 * Keeping the callback-owned PixelMap in UI state is unsafe: ArkWeb can
 * recycle its backing memory after navigation completes.
 */
export function cloneFaviconPixelMap(favicon: PixelMap): PixelMap | undefined {
  try {
    const info = favicon.getImageInfoSync();
    const byteCount = favicon.getPixelBytesNumber();
    if (!info || !info.size || info.size.width <= 0 || info.size.height <= 0 || byteCount <= 0 ||
      byteCount > MAX_FAVICON_PIXEL_BYTES) {
      return undefined;
    }
    const pixels = new ArrayBuffer(byteCount);
    favicon.readPixelsToBufferSync(pixels);
    // ArkWeb can notify again with a correctly sized but empty PixelMap while
    // finishing a navigation. Treat it as missing data so it cannot replace a
    // favicon that was already rendered for the same document.
    if (!hasNonEmptyPixelData(pixels)) {
      return undefined;
    }
    return image.createPixelMapSync(pixels, {
      size: {
        width: info.size.width,
        height: info.size.height,
      },
      srcPixelFormat: info.pixelFormat,
      pixelFormat: info.pixelFormat,
      editable: true,
      alphaType: info.alphaType,
    });
  } catch (_) {
    return undefined;
  }
}

/**
 * ArkWeb 的 favicon 回调只提供 PixelMap。书签数据库不能保存 PixelMap，
 * 因此统一编码为 PNG data URI，使书签图标不依赖站点的 /favicon.ico 是否可访问。
 */
export async function encodeFaviconDataUri(favicon: PixelMap): Promise<string | undefined> {
  let packer: image.ImagePacker | null = null;
  try {
    packer = image.createImagePacker();
    const encodedData = await packer.packToData(favicon, {
      format: 'image/png',
      quality: 100,
    });
    const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(encodedData));
    return base64.length > 0 ? `data:image/png;base64,${base64}` : undefined;
  } catch (_) {
    return undefined;
  } finally {
    if (packer) {
      try {
        await packer.release();
      } catch (_) {
      }
    }
  }
}
