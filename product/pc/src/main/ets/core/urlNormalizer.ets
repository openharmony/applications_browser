// urlNormalizer：统一浏览链路中的 URL 比较与存储规范化。

export function normalizeHttpUrlForStorage(url: string): string {
  return normalizeHttpUrl(url, false);
}

export function normalizeHttpUrlForNavigation(url: string): string {
  return normalizeHttpUrl(url, true);
}

export function extractUrlScheme(url: string): string {
  const matched = url.trim().match(/^([a-z][a-z0-9+.-]*):/i);
  return matched && matched[1] ? matched[1].toLowerCase() : '';
}

/** URLs ArkWeb can render directly without delegating to another application. */
export function isWebViewLoadableUrl(url: string): boolean {
  const raw = url.trim();
  const normalized = raw.toLowerCase();
  if (normalized.length === 0) {
    return false;
  }
  if (normalized.startsWith('http://') || normalized.startsWith('https://') ||
    normalized.startsWith('about:') || normalized.startsWith('file://') ||
    normalized.startsWith('resource://')) {
    return true;
  }
  return raw.startsWith('/');
}

/**
 * Native-app pseudo protocols must not replace the current document. Sites
 * commonly probe them and start an HTTP installer download after a timeout.
 * Letting ArkWeb navigate produces ERR_UNKNOWN_URL_SCHEME and destroys that
 * fallback flow (for example androws:// on sj.qq.com).
 */
export function isExternalAppSchemeUrl(url: string): boolean {
  const raw = url.trim();
  if (raw.length === 0 || isWebViewLoadableUrl(raw)) {
    return false;
  }
  const normalized = raw.toLowerCase();
  if (normalized.startsWith('javascript:') || normalized.startsWith('data:') ||
    normalized.startsWith('blob:')) {
    return false;
  }
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
}

function normalizeHttpUrl(url: string, keepHash: boolean): string {
  const trimmedUrl = url.trim();
  const matched = trimmedUrl.match(/^(https?):\/\/([^\/?#:]+)(?::(\d+))?([^?#]*)(\?[^#]*)?(#.*)?$/i);
  if (!matched) {
    return trimmedUrl;
  }

  const scheme = matched[1].toLowerCase();
  const host = matched[2].toLowerCase();
  const port = matched[3] ? matched[3] : '';
  const path = matched[4] && matched[4] !== '/' ? matched[4] : '';
  const query = matched[5] ? matched[5] : '';
  const hash = keepHash && matched[6] ? matched[6] : '';
  const normalizedPort = (scheme === 'http' && port === '80') || (scheme === 'https' && port === '443') ? '' : port;
  return `${scheme}://${host}${normalizedPort ? ':' + normalizedPort : ''}${path}${query}${hash}`;
}

export function isSameHttpNavigationUrl(left: string | undefined, right: string): boolean {
  if (left === undefined) {
    return false;
  }
  if (left === right) {
    return true;
  }
  return normalizeHttpUrlForNavigation(left) === normalizeHttpUrlForNavigation(right);
}

/**
 * Favicon belongs to the loaded document, not to an in-page anchor. A hash
 * change must therefore retain the icon that was already received for the
 * current document.
 */
export function isSameHttpDocumentUrl(left: string | undefined, right: string): boolean {
  if (left === undefined) {
    return false;
  }
  if (left === right) {
    return true;
  }
  return normalizeHttpUrlForStorage(left) === normalizeHttpUrlForStorage(right);
}
