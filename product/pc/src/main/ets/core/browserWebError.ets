import { isSameHttpNavigationUrl } from './urlNormalizer';

export type BrowserWebErrorKind = 'network' | 'http' | 'ssl' | 'renderer';

export interface BrowserWebErrorState {
  tabId: string;
  kind: BrowserWebErrorKind;
  url: string;
  title: string;
  message: string;
  errorCode: string;
  retryable: boolean;
  occurredAt: number;
}

export interface BrowserWebErrorInput {
  tabId: string;
  kind: BrowserWebErrorKind;
  url: string;
  errorCode?: string;
  detail?: string;
  statusCode?: number;
  occurredAt?: number;
}

export interface BrowserResponseHeader {
  headerKey: string;
  headerValue: string;
}

function normalizeErrorDetail(value: string | undefined): string {
  const detail = (value ?? '').trim();
  return detail.length > 180 ? detail.substring(0, 180) : detail;
}

function getHttpTitle(statusCode: number): string {
  if (statusCode === 401 || statusCode === 403) {
    return '此网页拒绝了访问';
  }
  if (statusCode === 404) {
    return '找不到此网页';
  }
  if (statusCode >= 500) {
    return '网站暂时无法处理此请求';
  }
  return '网页请求失败';
}

function getHttpMessage(statusCode: number, detail: string): string {
  if (detail.length > 0) {
    return detail;
  }
  if (statusCode >= 500) {
    return '服务器遇到问题，请稍后重试。';
  }
  if (statusCode === 401 || statusCode === 403) {
    return '服务器拒绝了当前请求。';
  }
  return '服务器返回了错误响应，请检查地址后重试。';
}

export function createBrowserWebError(input: BrowserWebErrorInput): BrowserWebErrorState {
  const detail = normalizeErrorDetail(input.detail);
  const statusCode = input.statusCode ?? 0;
  let title = '无法访问此网站';
  let message = detail.length > 0 ? detail : '请检查网络连接，然后重试。';
  let errorCode = (input.errorCode ?? '').trim();
  let retryable = true;

  if (input.kind === 'http') {
    title = getHttpTitle(statusCode);
    message = getHttpMessage(statusCode, detail);
    errorCode = errorCode.length > 0 ? errorCode : `HTTP ${String(statusCode)}`;
  } else if (input.kind === 'ssl') {
    title = '您的连接不是私密连接';
    message = '此网站的安全证书存在问题。为保护您的信息，已停止加载此页面。';
    errorCode = errorCode.length > 0 ? errorCode : 'SSL_ERROR';
  } else if (input.kind === 'renderer') {
    title = '此网页没有响应';
    message = detail.length > 0 ? detail : '网页进程没有及时响应，可以重新加载页面。';
    errorCode = errorCode.length > 0 ? errorCode : 'RENDERER_UNRESPONSIVE';
  } else {
    errorCode = errorCode.length > 0 ? errorCode : 'NETWORK_ERROR';
  }

  return {
    tabId: input.tabId,
    kind: input.kind,
    url: input.url,
    title,
    message,
    errorCode,
    retryable,
    occurredAt: input.occurredAt ?? Date.now(),
  };
}

function errorPriority(kind: BrowserWebErrorKind): number {
  if (kind === 'ssl') {
    return 4;
  }
  if (kind === 'network') {
    return 3;
  }
  if (kind === 'http') {
    return 2;
  }
  return 1;
}

export function upsertBrowserWebError(
  states: BrowserWebErrorState[],
  next: BrowserWebErrorState,
): BrowserWebErrorState[] {
  const current = states.find((item: BrowserWebErrorState) => item.tabId === next.tabId);
  if (current && errorPriority(current.kind) > errorPriority(next.kind)) {
    return states;
  }
  return states
    .filter((item: BrowserWebErrorState) => item.tabId !== next.tabId)
    .concat([next]);
}

export function clearBrowserWebError(
  states: BrowserWebErrorState[],
  tabId: string,
  kind?: BrowserWebErrorKind,
): BrowserWebErrorState[] {
  return states.filter((item: BrowserWebErrorState) => {
    return item.tabId !== tabId || (kind !== undefined && item.kind !== kind);
  });
}

export function findBrowserWebError(
  states: BrowserWebErrorState[],
  tabId: string,
): BrowserWebErrorState | null {
  return states.find((item: BrowserWebErrorState) => item.tabId === tabId) ?? null;
}

export function isCurrentMainFrameNavigation(
  isMainFrame: boolean,
  requestUrl: string,
  navigationUrls: string[],
): boolean {
  if (!isMainFrame) {
    return false;
  }
  const request = requestUrl.trim();
  if (request.length === 0) {
    return false;
  }
  return navigationUrls.some((url: string) => {
    const candidate = url.trim();
    if (candidate.length === 0) {
      return false;
    }
    if (candidate === request) {
      return true;
    }
    return isSameHttpNavigationUrl(candidate, request);
  });
}

export function hasHttpResponseBody(responseData: string, headers: BrowserResponseHeader[]): boolean {
  if (responseData.trim().length > 0) {
    return true;
  }
  return headers.some((header: BrowserResponseHeader) => {
    const key = header.headerKey.trim().toLowerCase();
    const value = header.headerValue.trim().toLowerCase();
    if (key === 'content-length') {
      return Number(value) > 0;
    }
    return key === 'transfer-encoding' && value.length > 0;
  });
}
