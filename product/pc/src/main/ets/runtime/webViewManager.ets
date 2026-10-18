// WebViewManager: create and manage per-tab WebviewController instances and their JSBridge facades.
//
// This file focuses on isolation: each tab should have its own controller + bridge instance.

import webview from '@ohos.web.webview';
import { AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TabId } from '../core/types';
import { JSBridgeFacade, JSBridgeFacadeOptions } from './jsBridgeFacade';
import { WebMicCaptureService } from '../integration/webMicCaptureService';
import { TabMicBridge } from './tabMicMonitor';

const RUNTIME_MEMORY_LOG_DOMAIN: number = 0x0000;
const RUNTIME_MEMORY_LOG_TAG: string = 'RuntimeMemory';

// Keep these values together so device-specific tuning only changes one place.
export const WEB_RUNTIME_NORMAL_LIMIT: number = 20;
export const WEB_RUNTIME_LOW_MEMORY_LIMIT: number = 8;
export const WEB_RUNTIME_CRITICAL_MEMORY_LIMIT: number = 2;

export interface WebRuntime {
  controller: webview.WebviewController;
  jsBridge: JSBridgeFacade;
  micCapture: WebMicCaptureService;
  micBridge: TabMicBridge;
  downloadDelegate?: webview.WebDownloadDelegate;
  /** Monotonic identity for the WebView runtime bound to a tab. */
  revision: number;
}

export class WebViewManager {
  private runtimes: Map<string, WebRuntime> = new Map();
  private runtimeRevisionsByTabId: Map<string, number> = new Map();
  private lastUsedAtByTabId: Map<string, number> = new Map();
  private readonly configuredMaxRuntimeCount: number = WEB_RUNTIME_NORMAL_LIMIT;
  private memoryPressureRuntimeLimit: number = WEB_RUNTIME_NORMAL_LIMIT;
  private memoryPressureLevel: AbilityConstant.MemoryLevel =
    AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE;

  // SDK JS source should be loaded once (e.g. from rawfile) and reused for all tabs.
  private sdkSource: string = '';
  private bridgeDefaultsEnabled: boolean = false;
  private bridgeDefaultsAutoExposeAliases: string[] = ['zz'];
  private bridgeDefaultsOverrideExistingGlobals: boolean = false;
  private bridgeDefaultsInvokerWaitTimeoutMs: number = 3000;
  private bridgeDefaultsDefaultTimeoutMs: number = 10000;

  setSdkSource(source: string): void {
    this.sdkSource = source || '';
    // Update existing runtimes.
    this.runtimes.forEach(rt => rt.jsBridge.setSdkSource(this.sdkSource));
  }

  setBridgeDefaults(defaults: JSBridgeFacadeOptions): void {
    if (!defaults) {
      return;
    }
    if (typeof defaults.enabled === 'boolean') {
      this.bridgeDefaultsEnabled = defaults.enabled;
    }
    if (Array.isArray(defaults.autoExposeAliases)) {
      this.bridgeDefaultsAutoExposeAliases = defaults.autoExposeAliases;
    }
    if (typeof defaults.overrideExistingGlobals === 'boolean') {
      this.bridgeDefaultsOverrideExistingGlobals = defaults.overrideExistingGlobals;
    }
    if (typeof defaults.invokerWaitTimeoutMs === 'number') {
      this.bridgeDefaultsInvokerWaitTimeoutMs = Math.max(0, Math.floor(defaults.invokerWaitTimeoutMs));
    }
    if (typeof defaults.defaultTimeoutMs === 'number') {
      this.bridgeDefaultsDefaultTimeoutMs = Math.max(0, Math.floor(defaults.defaultTimeoutMs));
    }
  }

  getOrCreate(tabId: TabId, options?: JSBridgeFacadeOptions, protectedTabIds: string[] = []): WebRuntime {
    const key = String(tabId);
    const existing = this.runtimes.get(key);
    if (existing) {
      this.touch(key);
      return existing;
    }

    this.prepareForCreate(key, protectedTabIds);

    const controller = new webview.WebviewController();
    const effective: JSBridgeFacadeOptions = {
      enabled: this.bridgeDefaultsEnabled,
      autoExposeAliases: this.bridgeDefaultsAutoExposeAliases,
      overrideExistingGlobals: this.bridgeDefaultsOverrideExistingGlobals,
      invokerWaitTimeoutMs: this.bridgeDefaultsInvokerWaitTimeoutMs,
      defaultTimeoutMs: this.bridgeDefaultsDefaultTimeoutMs,
    };
    if (options) {
      if (typeof options.enabled === 'boolean') {
        effective.enabled = options.enabled;
      }
      if (Array.isArray(options.autoExposeAliases)) {
        effective.autoExposeAliases = options.autoExposeAliases;
      }
      if (typeof options.overrideExistingGlobals === 'boolean') {
        effective.overrideExistingGlobals = options.overrideExistingGlobals;
      }
      if (Array.isArray(options.allowedHosts)) {
        effective.allowedHosts = options.allowedHosts;
      }
      if (Array.isArray(options.capabilities)) {
        effective.capabilities = options.capabilities;
      }
      if (typeof options.invokerWaitTimeoutMs === 'number') {
        effective.invokerWaitTimeoutMs = Math.max(0, Math.floor(options.invokerWaitTimeoutMs));
      }
      if (typeof options.defaultTimeoutMs === 'number') {
        effective.defaultTimeoutMs = Math.max(0, Math.floor(options.defaultTimeoutMs));
      }
    }
    const jsBridge = new JSBridgeFacade(controller, effective);
    jsBridge.setSdkSource(this.sdkSource);
    const micCapture = new WebMicCaptureService();
    const micBridge = new TabMicBridge(micCapture);

    const revision = (this.runtimeRevisionsByTabId.get(key) ?? 0) + 1;
    this.runtimeRevisionsByTabId.set(key, revision);
    const rt: WebRuntime = { controller, jsBridge, micCapture, micBridge, revision };
    this.runtimes.set(key, rt);
    this.touch(key);
    this.logState('RUNTIME_CREATED', key);
    return rt;
  }

  get(tabId: TabId): WebRuntime | null {
    const key = String(tabId);
    const runtime = this.runtimes.get(key) || null;
    if (runtime) {
      this.touch(key);
    }
    return runtime;
  }

  has(tabId: TabId): boolean {
    return this.runtimes.has(String(tabId));
  }

  getRuntimeCount(): number {
    return this.runtimes.size;
  }

  getEffectiveRuntimeLimit(): number {
    return Math.min(this.configuredMaxRuntimeCount, this.memoryPressureRuntimeLimit);
  }

  getMemoryPressureLevel(): AbilityConstant.MemoryLevel {
    return this.memoryPressureLevel;
  }

  /**
   * Updates the dynamic limit and releases the least recently used inactive
   * runtimes. This is intentionally synchronous and only removes manager
   * ownership; ArkUI will unmount the corresponding Web component on the next
   * render pass.
   */
  setMemoryPressureLevel(level: AbilityConstant.MemoryLevel, protectedTabIds: string[] = []): void {
    this.memoryPressureLevel = level;
    this.memoryPressureRuntimeLimit = this.resolveMemoryPressureLimit(level);
    this.enforceRuntimeLimit(this.getEffectiveRuntimeLimit(), protectedTabIds);
    this.logState('MEMORY_PRESSURE_APPLIED', '', protectedTabIds.length);
  }

  /**
   * Ensures room for one new runtime. The requested tab is always protected;
   * callers should pass other tabs that must remain alive for user-visible
   * work such as audio playback or an active permission dialog.
   */
  prepareForCreate(tabId: string, protectedTabIds: string[] = []): void {
    const protectedIds: string[] = protectedTabIds.slice();
    if (protectedIds.indexOf(tabId) < 0) {
      protectedIds.push(tabId);
    }
    const targetCount = this.runtimes.has(tabId)
      ? this.getEffectiveRuntimeLimit()
      : Math.max(0, this.getEffectiveRuntimeLimit() - 1);
    this.enforceRuntimeLimit(targetCount, protectedIds);
  }

  destroy(tabId: TabId): void {
    const key = String(tabId);
    const runtime = this.runtimes.get(key);
    if (runtime) {
      runtime.micCapture.stop();
    }
    this.runtimes.delete(key);
    this.lastUsedAtByTabId.delete(key);
    this.logState('RUNTIME_DESTROYED', key);
  }

  destroyAll(): void {
    this.runtimes.forEach((runtime: WebRuntime) => runtime.micCapture.stop());
    this.runtimes.clear();
    this.lastUsedAtByTabId.clear();
    this.logState('RUNTIMES_DESTROYED_ALL', '');
  }

  private resolveMemoryPressureLimit(level: AbilityConstant.MemoryLevel): number {
    const numericLevel = Number(level);
    // API 21 also exposes background pressure levels (4/5/6). Treat those as
    // their foreground counterparts so backgrounded pages are reclaimed too.
    if (numericLevel === Number(AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) ||
      numericLevel >= 6) {
      return WEB_RUNTIME_CRITICAL_MEMORY_LIMIT;
    }
    if (numericLevel === Number(AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) ||
      numericLevel === 5) {
      return WEB_RUNTIME_LOW_MEMORY_LIMIT;
    }
    return WEB_RUNTIME_NORMAL_LIMIT;
  }

  private touch(tabId: string): void {
    this.lastUsedAtByTabId.set(tabId, Date.now());
  }

  private enforceRuntimeLimit(limit: number, protectedTabIds: string[]): void {
    const target = Math.max(0, Math.floor(limit));
    if (this.runtimes.size <= target) {
      return;
    }

    const protectedIds: string[] = protectedTabIds.map((id: string) => String(id));
    // The first protected id is the requested/current tab. It is the only
    // hard protection; other protected tabs are preferred over ordinary LRU
    // candidates but may still be evicted when the hard limit requires it.
    const hardProtectedId: string | null = protectedIds.length > 0 ? protectedIds[0] : null;
    const candidates: string[] = [];
    this.runtimes.forEach((_runtime: WebRuntime, tabId: string) => {
      if (tabId !== hardProtectedId) {
        candidates.push(tabId);
      }
    });
    candidates.sort((left: string, right: string) => {
      const leftProtected = protectedIds.indexOf(left) >= 0;
      const rightProtected = protectedIds.indexOf(right) >= 0;
      if (leftProtected !== rightProtected) {
        return leftProtected ? 1 : -1;
      }
      const leftUsed = this.lastUsedAtByTabId.get(left) ?? 0;
      const rightUsed = this.lastUsedAtByTabId.get(right) ?? 0;
      if (leftUsed !== rightUsed) {
        return leftUsed - rightUsed;
      }
      return left.localeCompare(right);
    });

    let removed = 0;
    while (this.runtimes.size > target && candidates.length > 0) {
      const tabId = candidates.shift();
      if (!tabId) {
        break;
      }
      const runtime = this.runtimes.get(tabId);
      if (runtime) {
        runtime.micCapture.stop();
      }
      this.runtimes.delete(tabId);
      this.lastUsedAtByTabId.delete(tabId);
      removed += 1;
      hilog.info(RUNTIME_MEMORY_LOG_DOMAIN, RUNTIME_MEMORY_LOG_TAG,
        'RUNTIME_EVICTED tab=%{public}s target=%{public}d remaining=%{public}d',
        tabId, target, this.runtimes.size);
    }

    if (this.runtimes.size > target) {
      hilog.warn(RUNTIME_MEMORY_LOG_DOMAIN, RUNTIME_MEMORY_LOG_TAG,
        'RUNTIME_LIMIT_DEFERRED target=%{public}d current=%{public}d protected=%{public}d',
        target, this.runtimes.size, hardProtectedId ? protectedIds.length : 0);
    }
    if (removed > 0) {
      this.logState('RUNTIME_EVICTION_COMPLETE', '', removed);
    }
  }

  private logState(event: string, tabId: string, extra: number = 0): void {
    hilog.info(RUNTIME_MEMORY_LOG_DOMAIN, RUNTIME_MEMORY_LOG_TAG,
      '%{public}s tab=%{public}s count=%{public}d limit=%{public}d level=%{public}d extra=%{public}d',
      event, tabId, this.runtimes.size, this.getEffectiveRuntimeLimit(), this.memoryPressureLevel, extra);
  }
}
