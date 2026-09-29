import request from '@ohos.request';
import uri from '@ohos.uri';
import webview from '@ohos.web.webview';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadStartRequest } from '../core/downloadTypes';

const DOWNLOAD_LOG_DOMAIN: number = 0x0000;
const DOWNLOAD_LOG_TAG: string = 'DownloadTrace';

interface ParsedHttpUrl {
  scheme: string;
  authority: string;
  origin: string;
  urlWithoutHash: string;
}

interface DownloadErrorLike extends Error {
  code?: number | string;
}

interface DownloadServiceTaskHandle {
  task: request.DownloadTask;
}

interface DownloadHostContext {
  filesDir?: string;
  cacheDir?: string;
}

interface OpenedDownloadTarget {
  path: string;
  fd: number;
}

interface ImageFallbackHandle {
  request: http.HttpRequest;
  path: string;
  fd: number;
}

interface ArkWebDownloadHandle {
  item: webview.WebDownloadItem;
  callbacks: DownloadServiceCallbacks;
  path: string;
  guid: string;
}

export interface DownloadServiceCallbacks {
  onProgress?: (receivedBytes: number, totalBytes: number, percentComplete?: number) => void;
  onComplete?: (filePath?: string) => void;
  onFail?: (code: number) => void;
  onPause?: () => void;
  onRemove?: () => void;
}

function sanitizeHeaderValue(value?: string): string {
  return (value ?? '').replace(/[\r\n]/g, '').trim();
}

function parseHttpUrl(rawUrl?: string): ParsedHttpUrl | null {
  const url = (rawUrl ?? '').trim();
  const matched = url.match(/^(https?):\/\/([^\/?#]+)([^#]*)?(?:#.*)?$/i);
  if (!matched || !matched[1] || !matched[2]) {
    return null;
  }
  const scheme = matched[1].toLowerCase();
  // User info must never be copied into Referer or diagnostics.
  const rawAuthority = matched[2];
  const atIndex = rawAuthority.lastIndexOf('@');
  let authority = (atIndex >= 0 ? rawAuthority.substring(atIndex + 1) : rawAuthority).toLowerCase();
  if (scheme === 'http' && authority.endsWith(':80')) {
    authority = authority.substring(0, authority.length - 3);
  } else if (scheme === 'https' && authority.endsWith(':443')) {
    authority = authority.substring(0, authority.length - 4);
  }
  const suffix = matched[3] ?? '';
  return {
    scheme: scheme,
    authority: authority,
    origin: `${scheme}://${authority}`,
    urlWithoutHash: `${scheme}://${authority}${suffix}`,
  };
}

/**
 * Mirrors the browser default strict-origin-when-cross-origin policy closely:
 * same-origin downloads receive the page URL, cross-origin downloads receive
 * only the origin, and HTTPS -> HTTP downgrades receive no Referer.
 */
export function resolveDownloadReferrer(pageUrl?: string, sourceUrl?: string): string | undefined {
  const page = parseHttpUrl(pageUrl);
  const source = parseHttpUrl(sourceUrl);
  if (!page || !source) {
    return undefined;
  }
  if (page.scheme === 'https' && source.scheme === 'http') {
    return undefined;
  }
  if (page.scheme === source.scheme && page.authority === source.authority) {
    return sanitizeHeaderValue(page.urlWithoutHash);
  }
  return `${page.origin}/`;
}

export function composeDownloadRequestHeaders(
  requestInfo: DownloadStartRequest,
  cookieValue: string = '',
  fallbackUserAgent: string = '',
): Record<string, string> {
  const headers: Record<string, string> = {
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
  const userAgent = sanitizeHeaderValue(requestInfo.userAgent) || sanitizeHeaderValue(fallbackUserAgent);
  if (userAgent.length > 0) {
    headers['User-Agent'] = userAgent;
  }
  const referrer = resolveDownloadReferrer(requestInfo.pageUrl, requestInfo.sourceUrl);
  if (referrer) {
    headers['Referer'] = referrer;
  }
  const cookie = sanitizeHeaderValue(cookieValue);
  if (cookie.length > 0) {
    headers['Cookie'] = cookie;
  }
  return headers;
}

function getDownloadOrigin(sourceUrl: string): string {
  return parseHttpUrl(sourceUrl)?.origin ?? 'unsupported';
}

function isDataImageUrl(sourceUrl: string): boolean {
  return /^data:image\/[\w.+-]+(?:;[^,]*)?,/i.test(sourceUrl.trim());
}

export function isImageDownloadRequest(requestInfo: DownloadStartRequest): boolean {
  const mimeType = (requestInfo.mimeType ?? '').trim().toLowerCase();
  if (mimeType.startsWith('image/')) {
    return true;
  }
  if (isDataImageUrl(requestInfo.sourceUrl)) {
    return true;
  }
  const path = (requestInfo.fileName ?? '').split(/[?#]/)[0].toLowerCase();
  return /\.(?:avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/.test(path);
}

function getSafeErrorSummary(error: Object): string {
  const candidate = error as DownloadErrorLike;
  const code = candidate.code !== undefined ? String(candidate.code) : 'unknown';
  const name = sanitizeHeaderValue(candidate.name).substring(0, 80) || 'Error';
  // Do not log message/toString here. Platform errors may embed the request
  // configuration, including Cookie or tokenized download URLs.
  return `name=${name} code=${code}`;
}

async function buildDownloadRequestHeaders(requestInfo: DownloadStartRequest): Promise<Record<string, string>> {
  let fallbackUserAgent = '';
  try {
    fallbackUserAgent = webview.WebviewController.getDefaultUserAgent();
  } catch (_) {
  }

  let cookie = '';
  if (parseHttpUrl(requestInfo.sourceUrl)) {
    try {
      cookie = await webview.WebCookieManager.fetchCookie(requestInfo.sourceUrl, requestInfo.isPrivate === true);
    } catch (_) {
      // No cookie is a normal condition. Keep the download usable for public resources.
    }
  }
  return composeDownloadRequestHeaders(requestInfo, cookie, fallbackUserAgent);
}

export function buildDownloadTargetFilePath(directoryUri?: string, fileName?: string): string | undefined {
  const directory = directoryUri ? directoryUri.trim() : '';
  if (!directory) {
    return undefined;
  }

  const normalizedFileName = (fileName || 'download').trim().replace(/[\\/:*?"<>|]/g, '_');
  if (!normalizedFileName) {
    return undefined;
  }

  try {
    // Picker results are URIs, not filesystem directories. addSegment() keeps
    // the URI authority and encodes spaces/non-ASCII characters correctly.
    return new uri.URI(directory).addSegment(normalizedFileName).toString();
  } catch (_) {
    // Keep plain app paths usable on devices that return a filesystem path.
    if (!/^[a-z][a-z0-9+.-]*:/i.test(directory)) {
      return `${directory.replace(/\/+$/, '')}/${normalizedFileName}`;
    }
    return undefined;
  }
}

export class DownloadService {
  private taskHandles: Map<string, DownloadServiceTaskHandle> = new Map();
  private arkWebHandles: Map<string, ArkWebDownloadHandle> = new Map();
  private arkWebTaskIdByGuid: Map<string, string> = new Map();
  private imageFallbackHandles: Map<string, ImageFallbackHandle> = new Map();
  private imageFallbackTaskIds: Set<string> = new Set();
  private interruptedImageFallbacks: Set<string> = new Set();

  createArkWebDownloadDelegate(onBeforeDownload: (item: webview.WebDownloadItem) => void): webview.WebDownloadDelegate {
    const delegate = new webview.WebDownloadDelegate();
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      onBeforeDownload(item);
    });
    delegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      const handle = this.getArkWebHandle(item);
      if (!handle) {
        return;
      }
      let receivedBytes = 0;
      let totalBytes = 0;
      let percentComplete: number | undefined = undefined;
      try {
        receivedBytes = Math.max(0, item.getReceivedBytes());
        totalBytes = Math.max(0, item.getTotalBytes());
        // ArkWeb exposes the authoritative progress independently of total
        // bytes. Some responses keep totalBytes at zero for most of the
        // transfer, so deriving progress only from byte counts freezes UI at 0.
        percentComplete = Math.min(100, Math.max(0, Math.floor(item.getPercentComplete())));
      } catch (_) {
      }
      this.safeInvoke(() => handle.callbacks.onProgress?.(receivedBytes, totalBytes, percentComplete));
    });
    delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      const handle = this.getArkWebHandle(item);
      if (!handle) {
        return;
      }
      let completedPath = handle.path;
      try {
        const fullPath = item.getFullPath();
        if (fullPath && fullPath.trim().length > 0) {
          completedPath = fullPath;
        }
      } catch (_) {
      }
      hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'ARKWEB_COMPLETE task=%{public}s path=%{public}s',
        this.arkWebTaskIdByGuid.get(handle.guid) ?? '', completedPath);
      this.safeInvoke(() => handle.callbacks.onComplete?.(completedPath));
      this.clearArkWebHandle(handle.guid);
    });
    delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      const handle = this.getArkWebHandle(item);
      if (!handle) {
        return;
      }
      let errorCode = -1;
      try {
        errorCode = Number(item.getLastErrorCode());
      } catch (_) {
      }
      hilog.error(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'ARKWEB_FAILED task=%{public}s code=%{public}d',
        this.arkWebTaskIdByGuid.get(handle.guid) ?? '', errorCode);
      this.safeInvoke(() => handle.callbacks.onFail?.(errorCode));
      this.clearArkWebHandle(handle.guid);
    });
    return delegate;
  }

  startArkWebDownload(browserTaskId: string, hostContext: object, requestInfo: DownloadStartRequest,
    item: webview.WebDownloadItem, callbacks: DownloadServiceCallbacks): void {
    const guid = item.getGuid();
    const path = this.buildArkWebDownloadPath(hostContext, requestInfo);
    const handle: ArkWebDownloadHandle = {
      item: item,
      callbacks: callbacks,
      path: path,
      guid: guid,
    };
    this.arkWebHandles.set(browserTaskId, handle);
    this.arkWebTaskIdByGuid.set(guid, browserTaskId);
    try {
      item.start(path);
      hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'ARKWEB_START task=%{public}s origin=%{public}s path=%{public}s',
        browserTaskId, getDownloadOrigin(requestInfo.sourceUrl), path);
    } catch (error) {
      this.clearArkWebHandle(guid);
      throw new Error(String(error));
    }
  }

  async start(browserTaskId: string, hostContext: object, requestInfo: DownloadStartRequest, callbacks: DownloadServiceCallbacks): Promise<void> {
    let downloadTask: request.DownloadTask;
    const origin = getDownloadOrigin(requestInfo.sourceUrl);
    const imageDownload = isImageDownloadRequest(requestInfo);
    this.interruptedImageFallbacks.delete(browserTaskId);
    try {
      if (isDataImageUrl(requestInfo.sourceUrl)) {
        const savedPath = this.saveDataImage(hostContext, requestInfo);
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
          'IMAGE_DATA_SAVED task=%{public}s path=%{public}s', browserTaskId, savedPath);
        this.safeInvoke(() => callbacks.onProgress?.(1, 1));
        this.safeInvoke(() => callbacks.onComplete?.(savedPath));
        return;
      }
      if (!parseHttpUrl(requestInfo.sourceUrl)) {
        throw new Error('暂不支持该下载地址类型');
      }
      const headers = await buildDownloadRequestHeaders(requestInfo);
      const config: request.DownloadConfig = {
        url: requestInfo.sourceUrl,
        title: requestInfo.fileName,
        description: requestInfo.pageTitle ?? requestInfo.sourceUrl,
        header: headers,
        enableMetered: true,
        enableRoaming: true,
        background: true,
      };
      const targetFilePath = buildDownloadTargetFilePath(requestInfo.downloadDirectoryUri, requestInfo.fileName);
      if (targetFilePath) {
        config.filePath = targetFilePath;
      }
      hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'REQUEST_START task=%{public}s origin=%{public}s private=%{public}s cookie=%{public}s referer=%{public}s ua=%{public}s',
        browserTaskId, origin, String(requestInfo.isPrivate === true), String(headers['Cookie'] !== undefined),
        String(headers['Referer'] !== undefined), String(headers['User-Agent'] !== undefined));
      downloadTask = await request.downloadFile(hostContext as never, config);
    } catch (error) {
      hilog.error(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'REQUEST_START_FAILED task=%{public}s origin=%{public}s error=%{public}s',
        browserTaskId, origin, getSafeErrorSummary(error as Object));
      throw new Error(String(error));
    }

    const handle: DownloadServiceTaskHandle = { task: downloadTask };
    this.taskHandles.set(browserTaskId, handle);

    downloadTask.on('progress', (receivedSize: number, totalSize: number) => {
      this.safeInvoke(() => callbacks.onProgress?.(receivedSize, totalSize));
    });
    downloadTask.on('complete', () => {
      hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'REQUEST_COMPLETE task=%{public}s origin=%{public}s', browserTaskId, origin);
      this.queryFilePath(downloadTask)
        .then((filePath: string | undefined) => {
          this.safeInvoke(() => callbacks.onComplete?.(filePath));
        })
        .finally(() => {
          this.taskHandles.delete(browserTaskId);
        });
    });
    downloadTask.on('pause', () => {
      this.safeInvoke(() => callbacks.onPause?.());
    });
    downloadTask.on('remove', () => {
      this.safeInvoke(() => callbacks.onRemove?.());
      this.taskHandles.delete(browserTaskId);
    });
    downloadTask.on('fail', (code: number) => {
      hilog.error(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
        'REQUEST_FAILED task=%{public}s origin=%{public}s code=%{public}d', browserTaskId, origin, code);
      this.taskHandles.delete(browserTaskId);
      if (!imageDownload) {
        this.safeInvoke(() => callbacks.onFail?.(code));
        return;
      }
      this.startImageFallback(browserTaskId, hostContext, requestInfo, callbacks, code);
    });
  }

  async cancel(browserTaskId: string): Promise<void> {
    const arkWebHandle = this.arkWebHandles.get(browserTaskId);
    if (arkWebHandle) {
      try {
        arkWebHandle.item.cancel();
      } finally {
        this.clearArkWebHandle(arkWebHandle.guid);
      }
      return;
    }
    if (this.imageFallbackTaskIds.has(browserTaskId)) {
      this.stopImageFallback(browserTaskId);
      return;
    }
    const handle = this.taskHandles.get(browserTaskId);
    if (!handle) {
      return;
    }
    try {
      await handle.task.delete();
      this.taskHandles.delete(browserTaskId);
      if (this.imageFallbackTaskIds.has(browserTaskId)) {
        this.stopImageFallback(browserTaskId);
      }
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async pause(browserTaskId: string): Promise<void> {
    const arkWebHandle = this.arkWebHandles.get(browserTaskId);
    if (arkWebHandle) {
      try {
        arkWebHandle.item.pause();
      } catch (error) {
        throw new Error(String(error));
      }
      return;
    }
    if (this.imageFallbackTaskIds.has(browserTaskId)) {
      throw new Error('当前图片下载阶段暂不支持暂停');
    }
    const handle = this.taskHandles.get(browserTaskId);
    if (!handle) {
      return;
    }
    try {
      await handle.task.suspend();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async resume(browserTaskId: string): Promise<void> {
    const arkWebHandle = this.arkWebHandles.get(browserTaskId);
    if (arkWebHandle) {
      try {
        arkWebHandle.item.resume();
      } catch (error) {
        throw new Error(String(error));
      }
      return;
    }
    const handle = this.taskHandles.get(browserTaskId);
    if (!handle) {
      return;
    }
    try {
      await handle.task.restore();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private async queryFilePath(downloadTask: request.DownloadTask): Promise<string | undefined> {
    try {
      const info = await downloadTask.getTaskInfo();
      return info.filePath;
    } catch (_) {
      return undefined;
    }
  }

  private getArkWebHandle(item: webview.WebDownloadItem): ArkWebDownloadHandle | null {
    let guid = '';
    try {
      guid = item.getGuid();
    } catch (_) {
      return null;
    }
    const taskId = this.arkWebTaskIdByGuid.get(guid);
    return taskId ? (this.arkWebHandles.get(taskId) ?? null) : null;
  }

  private clearArkWebHandle(guid: string): void {
    const taskId = this.arkWebTaskIdByGuid.get(guid);
    this.arkWebTaskIdByGuid.delete(guid);
    if (taskId) {
      this.arkWebHandles.delete(taskId);
    }
  }

  private buildArkWebDownloadPath(hostContext: object, requestInfo: DownloadStartRequest): string {
    const candidates: string[] = [];
    const configuredDirectory = (requestInfo.downloadDirectoryUri ?? '').trim();
    if (configuredDirectory.length > 0 && !/^[a-z][a-z0-9+.-]*:/i.test(configuredDirectory)) {
      candidates.push(`${configuredDirectory.replace(/\/+$/, '')}/${this.sanitizeFileName(requestInfo.fileName)}`);
    }
    const context = hostContext as DownloadHostContext;
    const sandboxBase = (context.filesDir ?? context.cacheDir ?? '').trim();
    if (sandboxBase.length > 0) {
      candidates.push(`${sandboxBase.replace(/\/+$/, '')}/downloads/${this.sanitizeFileName(requestInfo.fileName)}`);
    }
    for (let index = 0; index < candidates.length; index++) {
      const candidate = this.resolveUniqueDownloadPath(candidates[index]);
      try {
        this.ensureParentDirectory(candidate);
        return candidate;
      } catch (_) {
      }
    }
    throw new Error('无法创建网页下载保存路径');
  }

  private startImageFallback(browserTaskId: string, hostContext: object, requestInfo: DownloadStartRequest,
    callbacks: DownloadServiceCallbacks, originalErrorCode: number): void {
    this.imageFallbackTaskIds.add(browserTaskId);
    hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
      'IMAGE_FALLBACK_START task=%{public}s origin=%{public}s code=%{public}d',
      browserTaskId, getDownloadOrigin(requestInfo.sourceUrl), originalErrorCode);
    buildDownloadRequestHeaders(requestInfo)
      .then((headers: Record<string, string>) => {
        if (this.interruptedImageFallbacks.has(browserTaskId)) {
          throw new Error('image fallback interrupted');
        }
        return this.downloadHttpImage(browserTaskId, hostContext, requestInfo, headers, callbacks);
      })
      .then((savedPath: string) => {
        if (this.interruptedImageFallbacks.has(browserTaskId)) {
          this.interruptedImageFallbacks.delete(browserTaskId);
          return;
        }
        hilog.info(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
          'IMAGE_FALLBACK_COMPLETE task=%{public}s path=%{public}s', browserTaskId, savedPath);
        this.safeInvoke(() => callbacks.onComplete?.(savedPath));
      })
      .catch((error: Object) => {
        if (this.interruptedImageFallbacks.has(browserTaskId)) {
          this.interruptedImageFallbacks.delete(browserTaskId);
          return;
        }
        hilog.error(DOWNLOAD_LOG_DOMAIN, DOWNLOAD_LOG_TAG,
          'IMAGE_FALLBACK_FAILED task=%{public}s error=%{public}s',
          browserTaskId, getSafeErrorSummary(error));
        this.safeInvoke(() => callbacks.onFail?.(originalErrorCode));
      })
      .finally(() => {
        this.imageFallbackHandles.delete(browserTaskId);
        this.imageFallbackTaskIds.delete(browserTaskId);
      });
  }

  private downloadHttpImage(browserTaskId: string, hostContext: object, requestInfo: DownloadStartRequest,
    headers: Record<string, string>, callbacks: DownloadServiceCallbacks): Promise<string> {
    const target = this.openImageDownloadTarget(hostContext, requestInfo);
    const httpRequest = http.createHttp();
    this.imageFallbackHandles.set(browserTaskId, {
      request: httpRequest,
      path: target.path,
      fd: target.fd,
    });
    let responseCode = 0;
    let responseReady = false;
    let dataEnded = false;
    let settled = false;
    let writeError: Error | null = null;

    return new Promise<string>((resolve, reject) => {
      const finish = (): void => {
        if (settled || !responseReady || !dataEnded) {
          return;
        }
        settled = true;
        this.closeImageTarget(target.fd);
        this.destroyHttpRequest(httpRequest);
        if (writeError) {
          this.removeDownloadTarget(target.path);
          reject(writeError);
          return;
        }
        if (responseCode < 200 || responseCode >= 300) {
          this.removeDownloadTarget(target.path);
          reject(new Error(`http status ${responseCode}`));
          return;
        }
        resolve(target.path);
      };

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        if (writeError || settled) {
          return;
        }
        try {
          fileIo.writeSync(target.fd, data);
        } catch (error) {
          writeError = error as Error;
        }
      });
      httpRequest.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo) => {
        if (progress.receiveSize > 0) {
          this.safeInvoke(() => callbacks.onProgress?.(progress.receiveSize, progress.totalSize));
        }
      });
      httpRequest.on('dataEnd', () => {
        dataEnded = true;
        finish();
      });

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 60000,
        readTimeout: 600000,
      };
      httpRequest.requestInStream(requestInfo.sourceUrl, options)
        .then((code: number) => {
          responseCode = code;
          responseReady = true;
          finish();
        })
        .catch((error: Error) => {
          if (settled) {
            return;
          }
          settled = true;
          this.closeImageTarget(target.fd);
          this.destroyHttpRequest(httpRequest);
          this.removeDownloadTarget(target.path);
          reject(error);
        });
    });
  }

  private saveDataImage(hostContext: object, requestInfo: DownloadStartRequest): string {
    const target = this.openImageDownloadTarget(hostContext, requestInfo);
    let saved = false;
    let saveError: Error | null = null;
    try {
      const commaIndex = requestInfo.sourceUrl.indexOf(',');
      if (commaIndex < 0) {
        throw new Error('invalid data image');
      }
      const header = requestInfo.sourceUrl.substring(0, commaIndex);
      const payload = requestInfo.sourceUrl.substring(commaIndex + 1);
      let bytes: Uint8Array;
      if (/;base64(?:;|$)/i.test(header)) {
        bytes = new util.Base64Helper().decodeSync(payload);
      } else {
        const decoded = decodeURIComponent(payload);
        bytes = new Uint8Array(decoded.length);
        for (let index = 0; index < decoded.length; index++) {
          bytes[index] = decoded.charCodeAt(index) & 0xff;
        }
      }
      fileIo.writeSync(target.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      saved = true;
    } catch (error) {
      saveError = new Error(String(error));
    } finally {
      this.closeImageTarget(target.fd);
      if (!saved) {
        this.removeDownloadTarget(target.path);
      }
    }
    if (saveError) {
      throw saveError;
    }
    return target.path;
  }

  private openImageDownloadTarget(hostContext: object, requestInfo: DownloadStartRequest): OpenedDownloadTarget {
    const candidates: string[] = [];
    const configuredPath = buildDownloadTargetFilePath(requestInfo.downloadDirectoryUri, requestInfo.fileName);
    if (configuredPath) {
      candidates.push(configuredPath);
    }
    const context = hostContext as DownloadHostContext;
    const sandboxBase = (context.filesDir ?? context.cacheDir ?? '').trim();
    if (sandboxBase.length > 0) {
      const directory = `${sandboxBase.replace(/\/+$/, '')}/downloads`;
      this.ensureDirectory(directory);
      const sandboxPath = `${directory}/${this.sanitizeFileName(requestInfo.fileName)}`;
      if (!candidates.includes(sandboxPath)) {
        candidates.push(sandboxPath);
      }
    }

    let lastErrorMessage = 'download target unavailable';
    for (let index = 0; index < candidates.length; index++) {
      const path = this.resolveUniqueDownloadPath(candidates[index]);
      try {
        this.ensureParentDirectory(path);
        const file = fileIo.openSync(path,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        return { path: path, fd: file.fd };
      } catch (error) {
        lastErrorMessage = String(error);
      }
    }
    throw new Error(lastErrorMessage);
  }

  private sanitizeFileName(fileName?: string): string {
    const normalized = (fileName || `image_${Date.now()}`).trim().replace(/[\\/:*?"<>|]/g, '_');
    return normalized.length > 0 ? normalized : `image_${Date.now()}`;
  }

  private resolveUniqueDownloadPath(path: string): string {
    if (!this.downloadTargetExists(path)) {
      return path;
    }
    const separatorIndex = path.lastIndexOf('/');
    const dotIndex = path.lastIndexOf('.');
    const hasExtension = dotIndex > separatorIndex;
    const base = hasExtension ? path.substring(0, dotIndex) : path;
    const extension = hasExtension ? path.substring(dotIndex) : '';
    for (let index = 1; index <= 999; index++) {
      const candidate = `${base} (${index})${extension}`;
      if (!this.downloadTargetExists(candidate)) {
        return candidate;
      }
    }
    return `${base}_${Date.now()}${extension}`;
  }

  private downloadTargetExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private ensureParentDirectory(path: string): void {
    if (/^[a-z][a-z0-9+.-]*:/i.test(path)) {
      return;
    }
    const separatorIndex = path.lastIndexOf('/');
    if (separatorIndex <= 0) {
      return;
    }
    this.ensureDirectory(path.substring(0, separatorIndex));
  }

  private ensureDirectory(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (_) {
      try {
        fileIo.mkdirSync(path, true);
      } catch (_) {
      }
    }
  }

  private closeImageTarget(fd: number): void {
    try {
      fileIo.closeSync(fd);
    } catch (_) {
    }
  }

  private removeDownloadTarget(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_) {
    }
  }

  private destroyHttpRequest(httpRequest: http.HttpRequest): void {
    try {
      httpRequest.off('dataReceive');
      httpRequest.off('dataReceiveProgress');
      httpRequest.off('dataEnd');
    } catch (_) {
    }
    try {
      httpRequest.destroy();
    } catch (_) {
    }
  }

  private stopImageFallback(browserTaskId: string): boolean {
    this.interruptedImageFallbacks.add(browserTaskId);
    const handle = this.imageFallbackHandles.get(browserTaskId);
    if (handle) {
      this.imageFallbackHandles.delete(browserTaskId);
      this.closeImageTarget(handle.fd);
      this.destroyHttpRequest(handle.request);
      this.removeDownloadTarget(handle.path);
    }
    return this.imageFallbackTaskIds.has(browserTaskId);
  }

  private safeInvoke(callback: () => void): void {
    try {
      callback();
    } catch (_) {
    }
  }

}
