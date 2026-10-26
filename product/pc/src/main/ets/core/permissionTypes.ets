export type SitePermissionType =
  | 'camera'
  | 'microphone'
  | 'location'
  | 'notifications'
  | 'clipboard-read'
  | 'clipboard-write';

export type SitePermissionSettingDecision = 'allow' | 'deny' | 'ask';

export type SitePermissionPromptDecision = 'allow' | 'deny';

export type SitePermissionResultSource = 'prompt' | 'stored';

export type SitePermissionSettingSource = 'user' | 'policy' | 'default';

export interface SitePermissionRequestMetadata {
  pageUrl?: string;
  siteTitle?: string;
  tabId?: string;
  isPrivate?: boolean;
}

export interface SitePermissionRequestDraft {
  origin: string;
  permissionType: SitePermissionType;
  requestId?: string;
  title?: string;
  message?: string;
  allowRememberChoice?: boolean;
  rememberChoiceDefault?: boolean;
  isSecureContext?: boolean;
  requestedAt?: number;
  metadata?: SitePermissionRequestMetadata;
}

export interface SitePermissionRequest {
  requestId: string;
  origin: string;
  permissionType: SitePermissionType;
  title: string;
  message: string;
  allowRememberChoice: boolean;
  rememberChoiceDefault: boolean;
  isSecureContext: boolean;
  requestedAt: number;
  metadata?: SitePermissionRequestMetadata;
}

export interface SitePermissionPromptResult {
  requestId: string;
  origin: string;
  permissionType: SitePermissionType;
  decision: SitePermissionPromptDecision;
  rememberChoice: boolean;
  decidedAt: number;
  source: SitePermissionResultSource;
}

export interface SitePermissionSetting {
  origin: string;
  permissionType: SitePermissionType;
  decision: SitePermissionSettingDecision;
  updatedAt: number;
  source: SitePermissionSettingSource;
}

export function normalizeSiteOrigin(origin: string): string {
  const normalized = origin.trim().toLowerCase();
  if (normalized.length === 0) {
    return '';
  }
  if (normalized.endsWith('/')) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

export function extractSiteOriginFromUrl(url: string): string {
  const normalizedUrl = url.trim();
  if (normalizedUrl.length === 0) {
    return '';
  }

  const match = normalizedUrl.match(/^([a-z][a-z0-9+.-]*:\/\/[^/?#]+)/i);
  if (match && match[1]) {
    return normalizeSiteOrigin(match[1]);
  }

  const schemeIndex = normalizedUrl.indexOf(':');
  if (schemeIndex > 0) {
    return normalizeSiteOrigin(normalizedUrl.substring(0, schemeIndex + 1));
  }

  return normalizeSiteOrigin(normalizedUrl);
}

export function buildSitePermissionRequestKey(origin: string, permissionType: SitePermissionType): string {
  return `${normalizeSiteOrigin(origin)}::${permissionType}`;
}

export function getSitePermissionTitle(permissionType: SitePermissionType): string {
  switch (permissionType) {
    case 'camera':
      return '摄像头权限请求';
    case 'microphone':
      return '麦克风权限请求';
    case 'location':
      return '定位权限请求';
    case 'notifications':
      return '通知权限请求';
    case 'clipboard-read':
      return '剪贴板读取权限请求';
    case 'clipboard-write':
      return '剪贴板写入权限请求';
    default:
      return '站点权限请求';
  }
}

export function getSitePermissionLabel(permissionType: SitePermissionType): string {
  switch (permissionType) {
    case 'camera':
      return '摄像头';
    case 'microphone':
      return '麦克风';
    case 'location':
      return '定位';
    case 'notifications':
      return '通知';
    case 'clipboard-read':
      return '读取剪贴板';
    case 'clipboard-write':
      return '写入剪贴板';
    default:
      return '权限';
  }
}

export function getSitePermissionMessage(origin: string, permissionType: SitePermissionType): string {
  const label = getSitePermissionLabel(permissionType);
  const normalizedOrigin = normalizeSiteOrigin(origin);
  if (normalizedOrigin.length === 0) {
    return `当前站点正在请求${label}权限。`;
  }
  return `${normalizedOrigin} 正在请求${label}权限。`;
}

export function mapProtectedResourceToSitePermissionType(resource: string): SitePermissionType | null {
  const normalized = resource.trim().toUpperCase();
  if (normalized === 'TYPE_VIDEO_CAPTURE' || normalized.endsWith('VIDEO_CAPTURE')) {
    return 'camera';
  }
  if (normalized === 'TYPE_AUDIO_CAPTURE' || normalized.endsWith('AUDIO_CAPTURE')) {
    return 'microphone';
  }
  return null;
}

export function createSitePermissionRequest(draft: SitePermissionRequestDraft): SitePermissionRequest {
  const requestedAt = draft.requestedAt !== undefined ? draft.requestedAt : Date.now();
  const requestId = draft.requestId !== undefined && draft.requestId.trim().length > 0
    ? draft.requestId.trim()
    : `${draft.permissionType}:${requestedAt}`;
  const origin = normalizeSiteOrigin(draft.origin);
  const title = draft.title !== undefined && draft.title.trim().length > 0
    ? draft.title.trim()
    : getSitePermissionTitle(draft.permissionType);
  const message = draft.message !== undefined && draft.message.trim().length > 0
    ? draft.message.trim()
    : getSitePermissionMessage(origin, draft.permissionType);

  return {
    requestId: requestId,
    origin: origin,
    permissionType: draft.permissionType,
    title: title,
    message: message,
    allowRememberChoice: draft.allowRememberChoice !== undefined ? draft.allowRememberChoice : true,
    rememberChoiceDefault: draft.rememberChoiceDefault !== undefined ? draft.rememberChoiceDefault : false,
    isSecureContext: draft.isSecureContext !== undefined ? draft.isSecureContext : true,
    requestedAt: requestedAt,
    metadata: draft.metadata,
  };
}
