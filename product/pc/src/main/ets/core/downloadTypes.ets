export type DownloadTaskState = 'created' | 'pending' | 'downloading' | 'paused' | 'completed' | 'failed' | 'canceled';

export type DownloadTaskFilter = 'all' | 'active' | 'completed' | 'failed';

export type DownloadIndicatorState = 'idle' | 'downloading' | 'completed_notice' | 'failed_notice' | 'session_history';

export interface DownloadStartRequest {
  sourceUrl: string;
  fileName?: string;
  mimeType?: string;
  pageUrl?: string;
  pageTitle?: string;
  /** User-Agent captured from the Web download event. Kept in memory only. */
  userAgent?: string;
  totalBytes?: number;
  isPrivate?: boolean;
  downloadDirectoryUri?: string;
  /** 用户在本次下载确认中选择的目标文件 URI。 */
  downloadFileUri?: string;
}

export interface WebDownloadStartInput {
  sourceUrl: string;
  contentDisposition?: string;
  suggestedFileName?: string;
  mimeType?: string;
  pageUrl?: string;
  pageTitle?: string;
  userAgent?: string;
  contentLength?: number;
  isPrivate?: boolean;
  downloadFileUri?: string;
}

export interface DownloadTask {
  id: string;
  sourceUrl: string;
  pageUrl?: string;
  pageTitle?: string;
  fileName: string;
  mimeType?: string;
  isPrivate: boolean;
  totalBytes?: number;
  receivedBytes: number;
  progress: number;
  state: DownloadTaskState;
  filePath?: string;
  errorCode?: string;
  errorMessage?: string;
  createdAt: number;
  updatedAt: number;
  completedAt?: number;
  canResume: boolean;
  canRetry: boolean;
  /**
   * UI-only flag. It is never persisted and is populated by DownloadManager
   * when a task-level operation is in flight.
   */
  actionBusy?: boolean;
  actionLabel?: string;
}

export interface DownloadTaskQuery {
  filter?: DownloadTaskFilter;
  keyword?: string;
  includePrivate?: boolean;
}

export interface DownloadTaskUpdate {
  receivedBytes?: number;
  totalBytes?: number;
  progress?: number;
  state?: DownloadTaskState;
  filePath?: string;
  errorCode?: string;
  errorMessage?: string;
  canResume?: boolean;
  canRetry?: boolean;
  completedAt?: number;
}

export interface DownloadIndicatorSnapshot {
  primaryState: DownloadIndicatorState;
  activeTaskCount: number;
  failedTaskCount: number;
  completedTaskCount: number;
  aggregateProgress: number;
  hasActiveTasks: boolean;
  /** True after a non-private download starts during the current app process. */
  hasSessionDownloadActivity: boolean;
}

export function createDownloadTask(request: DownloadStartRequest, id: string): DownloadTask {
  const now = Date.now();
  return {
    id: id,
    sourceUrl: request.sourceUrl,
    pageUrl: request.pageUrl,
    pageTitle: request.pageTitle,
    fileName: buildDownloadFileName(request.sourceUrl, request.fileName),
    mimeType: request.mimeType,
    isPrivate: request.isPrivate === true,
    totalBytes: request.totalBytes,
    receivedBytes: 0,
    progress: 0,
    state: 'created',
    createdAt: now,
    updatedAt: now,
    canResume: false,
    canRetry: false,
  };
}

export function buildDownloadStartRequest(input: WebDownloadStartInput): DownloadStartRequest {
  const fileNameFromHeader = extractFileNameFromContentDisposition(input.contentDisposition);
  const suggestedFileName = fileNameFromHeader || input.suggestedFileName;
  const resolvedMimeType = inferImageMimeType(input.sourceUrl, input.mimeType);
  const fileName = appendImageExtensionIfNeeded(
    buildDownloadFileName(input.sourceUrl, suggestedFileName),
    input.sourceUrl,
    resolvedMimeType,
  );
  return {
    sourceUrl: input.sourceUrl,
    fileName: fileName,
    mimeType: resolvedMimeType || input.mimeType,
    pageUrl: input.pageUrl,
    pageTitle: input.pageTitle,
    userAgent: input.userAgent,
    totalBytes: input.contentLength !== undefined && input.contentLength > 0 ? input.contentLength : undefined,
    isPrivate: input.isPrivate === true,
    downloadFileUri: input.downloadFileUri,
  };
}

export function appendImageExtensionIfNeeded(fileName: string, sourceUrl: string, mimeType?: string): string {
  const normalizedName = fileName.trim() || 'download';
  if (/\.[a-z0-9]{2,8}$/i.test(normalizedName)) {
    return normalizedName;
  }
  const normalizedMime = inferImageMimeType(sourceUrl, mimeType);
  const extension = getImageExtensionForMimeType(normalizedMime);
  return extension.length > 0 ? `${normalizedName}.${extension}` : normalizedName;
}

/**
 * Resolves an exact image MIME type from the response hint, URL extension, or
 * common image-format query parameters used by image CDNs.
 */
export function inferImageMimeType(sourceUrl: string, mimeType?: string): string {
  const normalizedMime = (mimeType ?? '').trim().toLowerCase();
  if (normalizedMime.startsWith('image/') && normalizedMime !== 'image/*') {
    return normalizedMime;
  }

  const dataMime = sourceUrl.trim().match(/^data:(image\/[\w.+-]+)(?:;[^,]*)?,/i);
  if (dataMime && dataMime[1]) {
    return dataMime[1].toLowerCase();
  }

  const extension = inferImageExtension(sourceUrl);
  if (extension.length > 0) {
    return getImageMimeTypeForExtension(extension);
  }
  return normalizedMime;
}

/** Builds a stable image filename for save-image actions, including CDN URLs. */
export function buildImageDownloadFileName(sourceUrl: string, suggestedFileName?: string): string {
  const preferred = (suggestedFileName ?? '').trim();
  let baseName = preferred;
  if (baseName.length === 0) {
    baseName = extractImageNameCandidate(sourceUrl);
  }
  if (baseName.length === 0) {
    baseName = 'downloaded-image';
  }
  baseName = sanitizeImageBaseName(baseName);
  return appendImageExtensionIfNeeded(baseName, sourceUrl, inferImageMimeType(sourceUrl, 'image/*'));
}

function extractImageNameCandidate(sourceUrl: string): string {
  const url = sourceUrl.trim();
  const pathMatch = url.match(/\/([^\/?#]+)(?:\?[^#]*)?(?:#.*)?$/);
  const pathName = pathMatch && pathMatch[1] ? decodeUrlComponent(pathMatch[1]) : '';
  const pathCandidate = extractNamedValue(pathName);
  if (pathCandidate.length > 0) {
    return pathCandidate;
  }

  const queryIndex = url.indexOf('?');
  if (queryIndex >= 0) {
    const queryEnd = url.indexOf('#', queryIndex);
    const query = url.substring(queryIndex + 1, queryEnd >= 0 ? queryEnd : url.length);
    const queryCandidate = extractNamedValue(query);
    if (queryCandidate.length > 0) {
      return queryCandidate;
    }
  }
  if (pathName.length > 0 && !/[=&]/.test(pathName) && !isGenericImageName(pathName)) {
    return pathName;
  }
  return '';
}

function isGenericImageName(value: string): boolean {
  if (/\.[a-z0-9]{2,8}$/i.test(value.trim())) {
    return false;
  }
  const normalized = value.trim().toLowerCase().replace(/\.[a-z0-9]{2,8}$/i, '');
  return normalized === 'image' || normalized === 'img' || normalized === 'file' ||
    normalized === 'download' || normalized === 'resource';
}

function extractNamedValue(parameters: string): string {
  const preferredKeys: string[] = ['filename', 'file', 'name', 'image', 'img', 'id', 'u', 'key'];
  const entries = parameters.split('&');
  for (let index = 0; index < entries.length; index++) {
    const separator = entries[index].indexOf('=');
    if (separator <= 0) {
      continue;
    }
    const key = entries[index].substring(0, separator).trim().toLowerCase();
    if (!preferredKeys.includes(key)) {
      continue;
    }
    const value = decodeUrlComponent(entries[index].substring(separator + 1).trim());
    if (value.length > 0 && value.toLowerCase() !== 'auto') {
      return value;
    }
  }
  return '';
}

function sanitizeImageBaseName(value: string): string {
  let sanitized = decodeUrlComponent(value).trim();
  const extensionMatch = sanitized.match(/\.[a-z0-9]{2,8}$/i);
  if (extensionMatch && extensionMatch[0]) {
    sanitized = sanitized.substring(0, sanitized.length - extensionMatch[0].length);
  }
  sanitized = sanitized.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_');
  sanitized = sanitized.replace(/[\s,]+/g, '_').replace(/_+/g, '_');
  sanitized = sanitized.replace(/^[_\.]+|[_\.]+$/g, '');
  return sanitized.substring(0, 120);
}

function inferImageExtension(sourceUrl: string): string {
  const url = sourceUrl.trim();
  const pathMatch = url.match(/\/([^\/?#]+)(?:[?#].*)?$/);
  const pathName = pathMatch && pathMatch[1] ? pathMatch[1] : '';
  const pathExtension = pathName.match(/\.([a-z0-9]{2,8})$/i);
  if (pathExtension && pathExtension[1]) {
    const extension = normalizeImageExtension(pathExtension[1]);
    if (extension.length > 0) {
      return extension;
    }
  }

  const formatMatch = url.match(/[?&](?:f|format|fmt|type|ext)=([^&#?]+)/i);
  if (!formatMatch || !formatMatch[1]) {
    return '';
  }
  return normalizeImageExtension(decodeUrlComponent(formatMatch[1]).split(/[.;_\s-]/)[0]);
}

function normalizeImageExtension(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/^image\//, '');
  if (normalized === 'jpeg' || normalized === 'jpg' || normalized === 'jpe') {
    return 'jpg';
  }
  if (normalized === 'png' || normalized === 'gif' || normalized === 'webp' ||
    normalized === 'bmp' || normalized === 'avif' || normalized === 'heic' ||
    normalized === 'heif' || normalized === 'svg' || normalized === 'svg+xml') {
    return normalized === 'svg+xml' ? 'svg' : normalized;
  }
  return '';
}

function getImageMimeTypeForExtension(extension: string): string {
  if (extension === 'jpg') {
    return 'image/jpeg';
  }
  if (extension === 'svg') {
    return 'image/svg+xml';
  }
  return `image/${extension}`;
}

function decodeUrlComponent(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function getImageExtensionForMimeType(mimeType: string): string {
  if (mimeType === 'image/jpeg' || mimeType === 'image/jpg') {
    return 'jpg';
  }
  if (mimeType === 'image/png') {
    return 'png';
  }
  if (mimeType === 'image/gif') {
    return 'gif';
  }
  if (mimeType === 'image/webp') {
    return 'webp';
  }
  if (mimeType === 'image/bmp') {
    return 'bmp';
  }
  if (mimeType === 'image/avif') {
    return 'avif';
  }
  if (mimeType === 'image/svg+xml') {
    return 'svg';
  }
  if (mimeType === 'image/svg') {
    return 'svg';
  }
  if (mimeType === 'image/heic') {
    return 'heic';
  }
  if (mimeType === 'image/heif') {
    return 'heif';
  }
  return '';
}

export function cloneDownloadTask(task: DownloadTask): DownloadTask {
  return {
    id: task.id,
    sourceUrl: task.sourceUrl,
    pageUrl: task.pageUrl,
    pageTitle: task.pageTitle,
    fileName: task.fileName,
    mimeType: task.mimeType,
    isPrivate: task.isPrivate,
    totalBytes: task.totalBytes,
    receivedBytes: task.receivedBytes,
    progress: task.progress,
    state: task.state,
    filePath: task.filePath,
    errorCode: task.errorCode,
    errorMessage: task.errorMessage,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
    completedAt: task.completedAt,
    canResume: task.canResume,
    canRetry: task.canRetry,
    actionBusy: task.actionBusy,
    actionLabel: task.actionLabel,
  };
}

/**
 * 下载列表固定按任务创建时间倒序排列。
 *
 * updatedAt 会在进度和状态变化时持续更新，不能参与列表排序，否则并发下载时
 * 列表会随着回调顺序反复重排。同一毫秒创建的任务使用不可变的任务 ID 兜底，
 * 保证每次刷新都得到一致顺序。
 */
export function compareDownloadTasksByCreatedAtDesc(left: DownloadTask, right: DownloadTask): number {
  if (left.createdAt !== right.createdAt) {
    return right.createdAt - left.createdAt;
  }
  if (left.id === right.id) {
    return 0;
  }
  return left.id < right.id ? 1 : -1;
}

export function matchesDownloadTask(task: DownloadTask, query?: DownloadTaskQuery): boolean {
  if (task.isPrivate && query?.includePrivate !== true) {
    return false;
  }

  if (!query) {
    return true;
  }

  if (query.filter && query.filter !== 'all') {
    if (query.filter === 'active' && !isActiveDownloadState(task.state)) {
      return false;
    }
    if (query.filter === 'completed' && task.state !== 'completed') {
      return false;
    }
    if (query.filter === 'failed' && task.state !== 'failed') {
      return false;
    }
  }

  const keyword = query.keyword ? query.keyword.trim().toLowerCase() : '';
  if (!keyword) {
    return true;
  }

  const fileName = task.fileName.toLowerCase();
  const sourceUrl = task.sourceUrl.toLowerCase();
  const pageTitle = task.pageTitle ? task.pageTitle.toLowerCase() : '';
  return fileName.includes(keyword) || sourceUrl.includes(keyword) || pageTitle.includes(keyword);
}

export function isActiveDownloadState(state: DownloadTaskState): boolean {
  return state === 'created' || state === 'pending' || state === 'downloading' || state === 'paused';
}

export function createIdleDownloadIndicatorSnapshot(): DownloadIndicatorSnapshot {
  return {
    primaryState: 'idle',
    activeTaskCount: 0,
    failedTaskCount: 0,
    completedTaskCount: 0,
    aggregateProgress: 0,
    hasActiveTasks: false,
    hasSessionDownloadActivity: false,
  };
}

export function buildDownloadFileName(sourceUrl: string, suggestedFileName?: string): string {
  const preferred = suggestedFileName ? suggestedFileName.trim() : '';
  if (preferred.length > 0) {
    return preferred;
  }

  const matched = sourceUrl.match(/\/([^\/?#]+)(?:[?#].*)?$/);
  if (matched && matched[1] && matched[1].trim().length > 0) {
    return matched[1].trim();
  }
  return 'download';
}

export function extractFileNameFromContentDisposition(contentDisposition?: string): string {
  const raw = contentDisposition ? contentDisposition.trim() : '';
  if (raw.length === 0) {
    return '';
  }

  const utf8Match = raw.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf8Match && utf8Match[1]) {
    try {
      return decodeURIComponent(utf8Match[1].trim().replace(/^"|"$/g, ''));
    } catch (_) {
      return utf8Match[1].trim().replace(/^"|"$/g, '');
    }
  }

  const simpleMatch = raw.match(/filename=([^;]+)/i);
  if (simpleMatch && simpleMatch[1]) {
    return simpleMatch[1].trim().replace(/^"|"$/g, '');
  }
  return '';
}

export function getDownloadTaskStateText(state: DownloadTaskState): string {
  if (state === 'created') {
    return '已创建';
  }
  if (state === 'pending') {
    return '等待中';
  }
  if (state === 'downloading') {
    return '下载中';
  }
  if (state === 'paused') {
    return '已暂停';
  }
  if (state === 'completed') {
    return '已完成';
  }
  if (state === 'failed') {
    return '失败';
  }
  return '已取消';
}

export function formatDownloadBytes(bytes?: number): string {
  if (bytes === undefined || bytes < 0) {
    return '--';
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}
