import { SiteSettingsManager } from './siteSettingsManager';
import {
  buildSitePermissionRequestKey,
  createSitePermissionRequest,
  SitePermissionPromptDecision,
  SitePermissionPromptResult,
  SitePermissionRequest,
  SitePermissionRequestDraft,
} from './permissionTypes';

type PermissionPromptListener = (request: SitePermissionRequest | null) => void;
type PermissionResultListener = (result: SitePermissionPromptResult) => void;

// Temporary rollout switch. Keep site-level prompts disabled while the
// settings UI is being validated; platform permission dialogs remain active.
export const SITE_PERMISSION_PROMPT_ENABLED: boolean = false;

interface PendingPermissionRequestEntry {
  key: string;
  request: SitePermissionRequest;
  resolvers: Array<(result: SitePermissionPromptResult) => void>;
}

interface PrivatePermissionSessionSetting {
  decision: SitePermissionPromptDecision;
  updatedAt: number;
}

export class PermissionManager {
  private static instance: PermissionManager = new PermissionManager();
  private siteSettingsManager: SiteSettingsManager = SiteSettingsManager.getInstance();
  private activeEntry: PendingPermissionRequestEntry | null = null;
  private queue: PendingPermissionRequestEntry[] = [];
  private promptListeners: Set<PermissionPromptListener> = new Set();
  private resultListeners: Set<PermissionResultListener> = new Set();
  private privateSessionSettings: Map<string, PrivatePermissionSessionSetting> = new Map();

  static getInstance(): PermissionManager {
    return PermissionManager.instance;
  }

  getActiveRequest(): SitePermissionRequest | null {
    if (!this.activeEntry) {
      return null;
    }
    return this.cloneRequest(this.activeEntry.request);
  }

  requestPermission(draft: SitePermissionRequestDraft): Promise<SitePermissionPromptResult> {
    const request = createSitePermissionRequest(draft);
    const isPrivateRequest = request.metadata?.isPrivate === true;
    const baseKey = buildSitePermissionRequestKey(request.origin, request.permissionType);
    const requestKey = isPrivateRequest ? `${baseKey}::private` : baseKey;

    if (isPrivateRequest) {
      const privateSessionSetting = this.privateSessionSettings.get(requestKey);
      if (privateSessionSetting) {
        return Promise.resolve(this.buildResult(request, privateSessionSetting.decision, true, 'stored'));
      }
    }

    const storedSetting = this.siteSettingsManager.getPermissionSetting(request.origin, request.permissionType);
    if (!isPrivateRequest && storedSetting && storedSetting.decision !== 'ask') {
      const decision = storedSetting.decision === 'allow' ? 'allow' : 'deny';
      return Promise.resolve(this.buildResult(request, decision, false, 'stored'));
    }

    const key = requestKey;
    if (this.activeEntry && this.activeEntry.key === key) {
      return new Promise((resolve) => {
        this.activeEntry!.resolvers.push(resolve);
      });
    }

    const queuedEntry = this.findQueuedEntry(key);
    if (queuedEntry) {
      return new Promise((resolve) => {
        queuedEntry.resolvers.push(resolve);
      });
    }

    const entry: PendingPermissionRequestEntry = {
      key: key,
      request: request,
      resolvers: [],
    };

    return new Promise((resolve) => {
      entry.resolvers.push(resolve);
      this.queue.push(entry);
      this.tryOpenNextPrompt();
    });
  }

  resolveActiveRequest(decision: SitePermissionPromptDecision, rememberChoice: boolean): void {
    if (!this.activeEntry) {
      return;
    }

    const entry = this.activeEntry;
    const isPrivateRequest = entry.request.metadata?.isPrivate === true;
    if (rememberChoice && isPrivateRequest) {
      this.privateSessionSettings.set(entry.key, {
        decision: decision,
        updatedAt: Date.now(),
      });
    } else if (rememberChoice) {
      this.siteSettingsManager.setPermissionSetting(entry.request.origin, entry.request.permissionType, decision, 'user');
    }

    const result = this.buildResult(entry.request, decision, rememberChoice, 'prompt');
    this.activeEntry = null;
    this.notifyPromptListeners(null);
    entry.resolvers.forEach((resolve) => resolve(result));
    this.notifyResultListeners(result);
    this.tryOpenNextPrompt();
  }

  dismissActiveRequest(): void {
    this.resolveActiveRequest('deny', false);
  }

  clearPrivateSessionSettings(): void {
    this.privateSessionSettings.clear();

    const privateEntries: PendingPermissionRequestEntry[] = [];
    if (this.activeEntry && this.activeEntry.request.metadata?.isPrivate === true) {
      privateEntries.push(this.activeEntry);
      this.activeEntry = null;
      this.notifyPromptListeners(null);
    }

    const retainedQueue: PendingPermissionRequestEntry[] = [];
    this.queue.forEach((entry: PendingPermissionRequestEntry) => {
      if (entry.request.metadata?.isPrivate === true) {
        privateEntries.push(entry);
      } else {
        retainedQueue.push(entry);
      }
    });
    this.queue = retainedQueue;

    privateEntries.forEach((entry: PendingPermissionRequestEntry) => {
      const result = this.buildResult(entry.request, 'deny', false, 'prompt');
      entry.resolvers.forEach((resolve) => resolve(result));
      this.notifyResultListeners(result);
    });
    this.tryOpenNextPrompt();
  }

  addPromptListener(listener: PermissionPromptListener): void {
    this.promptListeners.add(listener);
  }

  removePromptListener(listener: PermissionPromptListener): void {
    this.promptListeners.delete(listener);
  }

  addResultListener(listener: PermissionResultListener): void {
    this.resultListeners.add(listener);
  }

  removeResultListener(listener: PermissionResultListener): void {
    this.resultListeners.delete(listener);
  }

  private tryOpenNextPrompt(): void {
    if (this.activeEntry || this.queue.length === 0) {
      return;
    }
    const nextEntry = this.queue.shift();
    if (!nextEntry) {
      return;
    }
    this.activeEntry = nextEntry;
    this.notifyPromptListeners(this.activeEntry.request);
  }

  private findQueuedEntry(key: string): PendingPermissionRequestEntry | null {
    for (let index = 0; index < this.queue.length; index++) {
      if (this.queue[index].key === key) {
        return this.queue[index];
      }
    }
    return null;
  }

  private buildResult(
    request: SitePermissionRequest,
    decision: SitePermissionPromptDecision,
    rememberChoice: boolean,
    source: 'prompt' | 'stored'
  ): SitePermissionPromptResult {
    return {
      requestId: request.requestId,
      origin: request.origin,
      permissionType: request.permissionType,
      decision: decision,
      rememberChoice: rememberChoice,
      decidedAt: Date.now(),
      source: source,
    };
  }

  private notifyPromptListeners(request: SitePermissionRequest | null): void {
    const snapshot = request ? this.cloneRequest(request) : null;
    this.promptListeners.forEach((listener) => listener(snapshot));
  }

  private notifyResultListeners(result: SitePermissionPromptResult): void {
    const snapshot = this.cloneResult(result);
    this.resultListeners.forEach((listener) => listener(snapshot));
  }

  private cloneRequest(request: SitePermissionRequest): SitePermissionRequest {
    return {
      requestId: request.requestId,
      origin: request.origin,
      permissionType: request.permissionType,
      title: request.title,
      message: request.message,
      allowRememberChoice: request.allowRememberChoice,
      rememberChoiceDefault: request.rememberChoiceDefault,
      isSecureContext: request.isSecureContext,
      requestedAt: request.requestedAt,
      metadata: request.metadata,
    };
  }

  private cloneResult(result: SitePermissionPromptResult): SitePermissionPromptResult {
    return {
      requestId: result.requestId,
      origin: result.origin,
      permissionType: result.permissionType,
      decision: result.decision,
      rememberChoice: result.rememberChoice,
      decidedAt: result.decidedAt,
      source: result.source,
    };
  }
}
