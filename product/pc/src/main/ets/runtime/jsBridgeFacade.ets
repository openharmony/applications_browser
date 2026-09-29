// JSBridgeFacade: per-WebView JSBridge controller.
//
// Goals for desktop browser:
// - Avoid polluting third-party pages (minimize globals / avoid overriding existing globals)
// - Inject early and idempotently (pageBegin + pageEnd fallback)
// - Isolate per WebView instance (per tab)

import webview from '@ohos.web.webview';
import { JSBridgeDispatcher, DispatchResult } from './jsBridgeDispatcher';

export interface JSBridgeFacadeOptions {
  enabled?: boolean;
  // Which globals the SDK is allowed to expose automatically.
  // Recommended for browser: ['OHBridge'] or []
  autoExposeAliases?: string[];
  // When false, do not override existing globals on the page.
  overrideExistingGlobals?: boolean;
  // If provided, only inject/bind for allowed hosts.
  allowedHosts?: string[];
  // Capabilities list: allowed method names.
  // Note: ArkTS has limitations around index signatures / mapped types.
  capabilities?: string[];
  // When false, disable capability gate (allow calling any registered method).
  capabilityGateEnabled?: boolean;
  // Timeouts passed to SDK internal setters (ms)
  defaultTimeoutMs?: number;
  invokerWaitTimeoutMs?: number;
}

interface ZzBridgeSdkConfig {
  autoExposeAliases: string[];
  overrideExistingGlobals: boolean;
}

class OHNativeBridgeProxy {
  private host: JSBridgeFacade;

  constructor(host: JSBridgeFacade) {
    this.host = host;
  }

  postMessage(id: string, method: string, paramsJson: string): void {
    // Delegate to host; keep the proxy object minimal.
    this.host.handleProxyMessage(id, method, paramsJson);
  }
}

// Some ArkWeb SDK versions do not expose deleteJavaScriptRegister on the typed WebviewController.
// Keep a minimal compatibility surface via an interface cast.
interface WebviewControllerCompat {
  deleteJavaScriptRegister(name: string): void;
}

// Note: In some SDK versions, JavaScript proxy registration may only take effect after a refresh.
// We keep the initial setup simple (3-arg register), and refresh once after registration.

export class JSBridgeFacade {
  private controller: webview.WebviewController;

  private enabled: boolean;
  private autoExposeAliases: string[];
  private overrideExistingGlobals: boolean;
  private allowedHosts: Set<string>;

  private capabilities: Set<string>;
  private dispatcher: JSBridgeDispatcher = new JSBridgeDispatcher();
  private capabilityGateEnabled: boolean = true;
  private defaultTimeoutMs: number;
  private invokerWaitTimeoutMs: number;

  // Cached SDK source (should be provided by native/runtime layer).
  private sdkSource: string = '';
  private proxyRegistered: boolean = false;
  private proxyPermissionJson: string = '';
  private proxyWildcardSupported: boolean = true;
  private currentUrl: string = 'about:blank';
  private proxyObj: OHNativeBridgeProxy | null = null;
  private proxyRefreshNeeded: boolean = false;

  constructor(controller: webview.WebviewController, options: JSBridgeFacadeOptions) {
    this.controller = controller;
    this.enabled = options.enabled === true;
    this.autoExposeAliases = Array.isArray(options.autoExposeAliases) ? options.autoExposeAliases : ['OHBridge'];
    this.overrideExistingGlobals = options.overrideExistingGlobals === true;
    this.allowedHosts = new Set((options.allowedHosts || []).map(h => String(h || '').trim().toLowerCase()).filter(Boolean));

    this.capabilityGateEnabled = options.capabilityGateEnabled !== false;
    this.capabilities = new Set((options.capabilities || []).map(m => String(m || '').trim()).filter(Boolean));
    this.dispatcher.setAllowedMethods(Array.from(this.capabilities.values()));
    this.dispatcher.setGateEnabled(this.capabilityGateEnabled);
    this.defaultTimeoutMs = typeof options.defaultTimeoutMs === 'number' ? Math.max(0, Math.floor(options.defaultTimeoutMs)) : 10000;
    this.invokerWaitTimeoutMs = typeof options.invokerWaitTimeoutMs === 'number' ? Math.max(0, Math.floor(options.invokerWaitTimeoutMs)) : 3000;

    this.registerBuiltinHandlers();
    this.ensureMinimumCapabilities();
  }

  // Called by OHNativeBridgeProxy (registered via registerJavaScriptProxy).
  // Keep it public so ArkTS visibility rules allow the proxy object to invoke it,
  // but treat it as an internal API.
  handleProxyMessage(id: string, method: string, paramsJson: string): void {
    if (!this.enabled) return;
    const url = this.currentUrl;
    if (!this.isUrlAllowed(url)) return;

    this.dispatcher.dispatch(method, paramsJson, url)
      .then((res: DispatchResult) => this.sendResponse(id, res))
      .catch((_e: Error) => {
        this.sendResponse(id, JSBridgeDispatcher.fail(-32002, 'dispatcher_error'));
      });
  }

  setEnabled(on: boolean): void {
    const next = !!on;
    // If JSBridge is disabled by policy, unregister JS proxy to minimize exposure.
    if (!next && this.enabled) {
      this.unregisterProxy();
    }
    this.enabled = next;
    this.ensureMinimumCapabilities();
  }

  setSdkSource(source: string): void {
    this.sdkSource = source || '';
  }

  setAllowedHosts(hosts: string[]): void {
    this.allowedHosts = new Set((hosts || []).map(h => String(h || '').trim().toLowerCase()).filter(Boolean));
  }

  setCapabilityGateEnabled(on: boolean): void {
    this.capabilityGateEnabled = !!on;
    this.dispatcher.setGateEnabled(this.capabilityGateEnabled);
    this.ensureMinimumCapabilities();
  }

  setCapabilities(methods: string[]): void {
    this.capabilities = new Set((methods || []).map(m => String(m || '').trim()).filter(Boolean));
    this.dispatcher.setAllowedMethods(Array.from(this.capabilities.values()));
    this.ensureMinimumCapabilities();
  }

  private ensureMinimumCapabilities(): void {
    // If JSBridge is enabled but caller did not provide any capabilities,
    // expose a minimal non-sensitive set to avoid ready(waitForCapabilities) hanging.
    if (!this.enabled) return;
    if (!this.capabilityGateEnabled) return;
    if (this.capabilities.size > 0) return;
    this.capabilities.add('browser.ping');
    this.capabilities.add('system.getSystemInfo');
    this.dispatcher.setAllowedMethods(Array.from(this.capabilities.values()));
  }

  registerMethod(method: string, handler: (paramsJson: string, url: string) => Promise<DispatchResult>): void {
    this.dispatcher.register(method, handler);
  }

  unregisterMethod(method: string): void {
    this.dispatcher.unregister(method);
  }

  // Native -> H5 event emission (browser-grade, best-effort).
  // dataJson must be a JSON literal string (e.g. '{"a":1}' or 'null').
  emitEvent(name: string, dataJson: string = 'null'): void {
    if (!this.enabled) return;
    const url = this.currentUrl;
    if (!this.isUrlAllowed(url)) return;

    const nameJson = JSON.stringify(String(name || ''));
    const payload = (dataJson && dataJson.trim()) ? dataJson : 'null';
    const script = `;(function(){\n` +
      `  try {\n` +
      `    if (typeof window.__ZZ_DISPATCH_EVENT__ === 'function') {\n` +
      `      window.__ZZ_DISPATCH_EVENT__(${nameJson}, ${payload});\n` +
      `      return;\n` +
      `    }\n` +
      `  } catch (_) {}\n` +
      `  try {\n` +
      `    var b = window.__ZZ_BRIDGE_API__ && window.__ZZ_BRIDGE_API__._bridge;\n` +
      `    if (b && typeof b.emit === 'function') { b.emit(${nameJson}, ${payload}); return; }\n` +
      `  } catch (_) {}\n` +
      `  // If binder isn't installed yet, queue events so they can be flushed later.\n` +
      `  try {\n` +
      `    if (!window.__ZZ_PENDING_EVENTS__) window.__ZZ_PENDING_EVENTS__ = [];\n` +
      `    window.__ZZ_PENDING_EVENTS__.push({ name: ${nameJson}, data: ${payload} });\n` +
      `  } catch (_) {}\n` +
      `  try { if (typeof window.__ZZ_FLUSH_EVENTS__ === 'function') window.__ZZ_FLUSH_EVENTS__(); } catch (_) {}\n` +
      `})();`;

    this.runJavaScriptSafely(script);
  }

  // Call onPageBegin as early as possible.
  onPageBegin(url: string): void {
    this.currentUrl = url || 'about:blank';
    this.tryInstall(url, /*isFallback*/ false);
  }

  // Call onPageEnd as a fallback in case early injection is not supported/reliable.
  onPageEnd(url: string): void {
    this.currentUrl = url || this.currentUrl;
    this.tryInstall(url, /*isFallback*/ true);

    // Some runtimes inject the proxy only after a page reload.
    // Refresh once (idempotent) after registering JS proxy.
    if (this.proxyRefreshNeeded) {
      this.proxyRefreshNeeded = false;
      try {
        this.controller.refresh();
      } catch (_) {
      }
    }
  }

  private isUrlAllowed(url: string): boolean {
    // Internal pages are treated as trusted once JSBridge is enabled by policy.
    // Policy manager should still control when enabled=true.
    if (url.startsWith('about:') || url.startsWith('file://') || url.startsWith('resource://')) {
      return true;
    }
    if (this.allowedHosts.size === 0) return true;
    // URL parsing in ArkTS runtime may differ; keep it simple and defensive.
    try {
      const m = String(url || '').match(/^https?:\/\/([^\/]+)/i);
      if (!m || !m[1]) return false;
      const host = String(m[1]).split(':')[0].toLowerCase();
      return this.allowedHosts.has(host);
    } catch (_) {
      return false;
    }
  }

  private tryInstall(url: string, isFallback: boolean): void {
    if (!this.enabled) return;
    if (!this.isUrlAllowed(url)) return;

    // 1) Ensure JS->Native proxy exists.
    this.ensureProxyRegistered();

    // 2) Inject SDK (guarded) + binder.
    // In a real product, prefer documentStart/preload; pageBegin is a pragmatic fallback.
    this.injectScripts(isFallback);
  }

  private ensureProxyRegistered(): void {
    const permission = this.buildJavaScriptProxyPermission(this.currentUrl, this.proxyWildcardSupported);
    if (this.proxyRegistered && this.proxyPermissionJson === permission) return;

    // Re-register when policy changes (e.g. InternalOnly -> OpenAll) so https pages can receive proxy.
    if (this.proxyRegistered) {
      this.unregisterProxy();
    }

    this.proxyRegistered = true;
    this.proxyPermissionJson = permission;

    // JS->Native channel: pages can call OHNativeBridge directly.
    // Therefore, all security checks must be enforced in this proxy handler.
    // We use a multi-arg postMessage(id, method, paramsJson) to avoid ArkTS-side dynamic JSON parsing.
    this.proxyObj = new OHNativeBridgeProxy(this);
    // Signature (commonly): registerJavaScriptProxy(obj, name, syncMethodList, asyncMethodList?, permission?)
    // NOTE: permission is required to make JSProxy available on non-rawfile pages in many runtimes.
    try {
      this.controller.registerJavaScriptProxy(this.proxyObj, 'OHNativeBridge', ['postMessage'], [], permission);
    } catch (_) {
      // Fallback for runtimes that do not accept wildcard hosts.
      this.proxyWildcardSupported = false;
      const safePermission = this.buildJavaScriptProxyPermission(this.currentUrl, false);
      this.proxyPermissionJson = safePermission;
      try {
        this.controller.registerJavaScriptProxy(this.proxyObj, 'OHNativeBridge', ['postMessage'], [], safePermission);
      } catch (_) {
        this.proxyRegistered = false;
        this.proxyPermissionJson = '';
        this.proxyObj = null;
        this.proxyRefreshNeeded = false;
        return;
      }
    }

    // Some runtimes inject the proxy only after a refresh; keep it as a one-shot fallback.
    this.proxyRefreshNeeded = true;
  }

  private unregisterProxy(): void {
    try {
      const c = this.controller as WebviewControllerCompat;
      if (c && typeof c.deleteJavaScriptRegister === 'function') {
        c.deleteJavaScriptRegister('OHNativeBridge');
      }
    } catch (_) {
    }
    this.proxyRegistered = false;
    this.proxyPermissionJson = '';
    this.proxyObj = null;
    this.proxyRefreshNeeded = false;
  }

  private buildJavaScriptProxyPermission(url: string, includeWildcard: boolean = true): string {
    // Permission JSON is a string; build it manually to avoid ArkTS object-literal restrictions.
    // Reference shape:
    // {"javascriptProxyPermission":{"urlPermissionList":[...],"methodList":[{"methodName":"postMessage","urlPermissionList":[...]}]}}

    const perms: string[] = [];
    // Always allow internal rawfile pages.
    perms.push('{"scheme":"resource","host":"rawfile","port":"","path":""}');

    // OpenAll mode: capability gate disabled implies we want broad JSProxy availability.
    // Note: wildcard host behavior depends on platform; keep a fallback by also allowing current host.
    if (!this.capabilityGateEnabled && includeWildcard) {
      perms.push('{"scheme":"https","host":"*","port":"","path":""}');
      perms.push('{"scheme":"http","host":"*","port":"","path":""}');
    } else if (this.allowedHosts.size > 0) {
      this.allowedHosts.forEach((h: string) => {
        const host = String(h || '').trim().toLowerCase();
        if (!host) return;
        perms.push('{"scheme":"https","host":' + JSON.stringify(host) + ',"port":"","path":""}');
        perms.push('{"scheme":"http","host":' + JSON.stringify(host) + ',"port":"","path":""}');
      });
    }

    // Always allow the current page's host (helps when wildcard is unsupported, or when
    // policy enables JSBridge for a single host without using allowedHosts).
    try {
      const m = String(url || '').match(/^(https?):\/\/([^\/]+)/i);
      if (m && m[1] && m[2]) {
        const scheme = String(m[1]).toLowerCase();
        const host = String(m[2]).split(':')[0].toLowerCase();
        if (scheme && host) {
          perms.push('{"scheme":' + JSON.stringify(scheme) + ',"host":' + JSON.stringify(host) + ',"port":"","path":""}');
        }
      }
    } catch (_) {
    }

    const urlPermJson = '[' + perms.join(',') + ']';
    const methodListJson = '[{"methodName":"postMessage","urlPermissionList":' + urlPermJson + '}]';
    return '{"javascriptProxyPermission":{"urlPermissionList":' + urlPermJson + ',"methodList":' + methodListJson + '}}';
  }

  private injectScripts(isFallback: boolean): void {
    // If sdkSource is not provided, we can still inject binder to bind to a page-provided SDK.
    const sdk = this.sdkSource;
    const guardedSdk = sdk ? this.buildGuardedSdkScript(sdk) : '';
    const binder = this.buildBinderScript();

    // On fallback injection, we only re-run binder (idempotent) to reduce overhead.
    const script = isFallback ? binder : (guardedSdk + '\n' + binder);
    if (!script.trim()) return;

    this.runJavaScriptSafely(script);
  }

  private buildGuardedSdkScript(sdkSource: string): string {
    const cfg: ZzBridgeSdkConfig = {
      autoExposeAliases: this.autoExposeAliases,
      overrideExistingGlobals: this.overrideExistingGlobals,
    };
    const cfgJson = JSON.stringify(cfg);
    // Wrap the whole SDK in an IIFE so "return" can short-circuit execution when already installed.
    // Also set __ZZ_BRIDGE_SDK_CONFIG__ before SDK runs so it can honor alias/override settings.
    return `;(function(){\n` +
      `  try { window.__ZZ_BRIDGE_SDK_CONFIG__ = ${cfgJson}; } catch (_) {}\n` +
      `  try { if (window.__ZZ_BRIDGE_API__) return; } catch (_) {}\n` +
      `  ${sdkSource}\n` +
      `})();`;
  }

  private buildBinderScript(): string {
    const capsJson = this.capabilityGateEnabled ? this.buildCapabilitiesJson() : '{}';
    const defaultTimeout = JSON.stringify(this.defaultTimeoutMs);
    const invokerWait = JSON.stringify(this.invokerWaitTimeoutMs);

    // Idempotent binder:
    // - bind invoker to OHNativeBridge.postMessage
    // - set timeouts
    // - sync capabilities
    // - keep re-binding if __ZZ_BRIDGE_API__ is overwritten
    return `;(function(){\n` +
      `  function bindOnce(api){\n` +
      `    try {\n` +
      `      if (!api || !api._bridge) return false;\n` +
      `      var b = api._bridge;\n` +
      `      if (typeof b.setInvoker === 'function') {\n` +
      `        // Always (re)bind invoker: policies/tokens/capabilities may change per navigation.\n` +
      `        b.setInvoker(function(payload){\n` +
      `          try {\n` +
      `            if (!window.OHNativeBridge || typeof window.OHNativeBridge.postMessage !== 'function') {\n` +
      `              // Fail fast to avoid hanging until TIMEOUT when JSProxy is not available due to permission/policy.\n` +
      `              try {\n` +
      `                var rid = payload && payload.id ? String(payload.id) : '';\n` +
      `                if (rid && b && typeof b.resolveWechatStyle === 'function') {\n` +
      `                  b.resolveWechatStyle(rid, {"code":-32000,"message":"OHNativeBridge not available"}, false);\n` +
      `                }\n` +
      `              } catch (_) {}\n` +
      `              return;\n` +
      `            }\n` +
      `            var id = payload && payload.id ? String(payload.id) : '';\n` +
      `            var method = payload && payload.method ? String(payload.method) : '';\n` +
      `            var paramsJson = '{}';\n` +
      `            try { paramsJson = JSON.stringify((payload && payload.params) || {}); } catch (_) {}\n` +
      `            window.OHNativeBridge.postMessage(id, method, paramsJson);\n` +
      `          } catch (_) {}\n` +
      `        });\n` +
      `        b._nativeInvokerBound = true;\n` +
      `      }\n` +
      `      try { if (typeof b.setDefaultTimeout === 'function') b.setDefaultTimeout(${defaultTimeout}); } catch (_) {}\n` +
      `      try { if (typeof b.setInvokerWaitTimeout === 'function') b.setInvokerWaitTimeout(${invokerWait}); } catch (_) {}\n` +
      `      try { if (typeof b.setCapabilities === 'function') b.setCapabilities(${capsJson}); } catch (_) {}\n` +
      `      // Install a stable Native->H5 event dispatcher with queueing.\n` +
      `      try {\n` +
      `        if (!window.__ZZ_PENDING_EVENTS__) window.__ZZ_PENDING_EVENTS__ = [];\n` +
      `        if (typeof window.__ZZ_DISPATCH_EVENT__ !== 'function') {\n` +
      `          window.__ZZ_DISPATCH_EVENT__ = function(name, data){\n` +
      `            try {\n` +
      `              var b2 = window.__ZZ_BRIDGE_API__ && window.__ZZ_BRIDGE_API__._bridge;\n` +
      `              if (b2 && typeof b2.emit === 'function') { b2.emit(String(name||''), data); return; }\n` +
      `            } catch (_) {}\n` +
      `            try { window.__ZZ_PENDING_EVENTS__.push({ name: String(name||''), data: data }); } catch (_) {}\n` +
      `          };\n` +
      `        }\n` +
      `        if (typeof window.__ZZ_FLUSH_EVENTS__ !== 'function') {\n` +
      `          window.__ZZ_FLUSH_EVENTS__ = function(){\n` +
      `            try {\n` +
      `              var b3 = window.__ZZ_BRIDGE_API__ && window.__ZZ_BRIDGE_API__._bridge;\n` +
      `              if (!b3 || typeof b3.emit !== 'function') return;\n` +
      `              var q = window.__ZZ_PENDING_EVENTS__ || [];\n` +
      `              if (!q.length) return;\n` +
      `              window.__ZZ_PENDING_EVENTS__ = [];\n` +
      `              for (var i=0;i<q.length;i++){\n` +
      `                try { b3.emit(String(q[i].name||''), q[i].data); } catch (_) {}\n` +
      `              }\n` +
      `            } catch (_) {}\n` +
      `          };\n` +
      `        }\n` +
      `        // Flush once bridge is ready, in case native emits early.\n` +
      `        if (b && typeof b.on === 'function') {\n` +
      `          b.on('bridge:ready', function(){ try { window.__ZZ_FLUSH_EVENTS__(); } catch (_) {} });\n` +
      `        }\n` +
      `        // Also flush immediately: bridge:ready may have already fired before we registered the listener.\n` +
      `        try { window.__ZZ_FLUSH_EVENTS__(); } catch (_) {}\n` +
      `      } catch (_) {}\n` +
      `      return true;\n` +
      `    } catch (_) { return false; }\n` +
      `  }\n` +
      `  function tryBind(){ return bindOnce(window.__ZZ_BRIDGE_API__); }\n` +
      `  try {\n` +
      `    var cur = window.__ZZ_BRIDGE_API__;\n` +
      `    Object.defineProperty(window, '__ZZ_BRIDGE_API__', {\n` +
      `      configurable: true,\n` +
      `      get: function(){ return cur; },\n` +
      `      set: function(v){ cur = v; tryBind(); }\n` +
      `    });\n` +
      `  } catch (_) {}\n` +
      `  if (!tryBind()) {\n` +
      `    var start = Date.now();\n` +
      `    var timer = setInterval(function(){\n` +
      `      var ok = tryBind();\n` +
      `      if (ok || (Date.now() - start) > 8000) clearInterval(timer);\n` +
      `    }, 120);\n` +
      `  }\n` +
      `})();`;
  }

  private buildCapabilitiesJson(): string {
    // Build a JSON object string like: {"a":true,"b":true}
    // Avoid dynamic object writes in ArkTS code.
    const keys: string[] = [];
    this.capabilities.forEach((k: string) => {
      const s = String(k || '').trim();
      if (s) keys.push(s);
    });
    if (keys.length === 0) return '{}';

    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      parts.push(JSON.stringify(keys[i]) + ':true');
    }
    return '{' + parts.join(',') + '}';
  }

  private sendResponse(id: string, result: DispatchResult): void {
    const idJson = JSON.stringify(String(id || ''));
    const payloadJson = result && result.payloadJson ? result.payloadJson : 'null';
    const isSuccess = result && result.ok ? 'true' : 'false';
    const script = `;(function(){\n` +
      `  try {\n` +
      `    var api = window.__ZZ_BRIDGE_API__;\n` +
      `    var b = api && api._bridge;\n` +
      `    if (b && typeof b.resolveWechatStyle === 'function') {\n` +
      `      b.resolveWechatStyle(${idJson}, ${payloadJson}, ${isSuccess});\n` +
      `      return;\n` +
      `    }\n` +
      `    if (b && typeof b.resolve === 'function') {\n` +
      `      var wrapped = ${isSuccess} ? { ok: true, data: ${payloadJson} } : { ok: false, code: (${payloadJson}).code || -1, message: (${payloadJson}).message || 'Error' };\n` +
      `      b.resolve(${idJson}, wrapped);\n` +
      `      return;\n` +
      `    }\n` +
      `  } catch (_) {}\n` +
      `})();`;

    this.runJavaScriptSafely(script);
  }

  private runJavaScriptSafely(script: string): void {
    try {
      this.controller.runJavaScript(script);
    } catch (_) {
    }
  }

  private registerBuiltinHandlers(): void {
    this.dispatcher.register('browser.ping', async (_paramsJson: string, _url: string) => {
      const payload = `{"pong":true,"ts":${Date.now()}}`;
      return JSBridgeDispatcher.ok(payload);
    });

    this.dispatcher.register('system.getSystemInfo', async (_paramsJson: string, _url: string) => {
      const payload = `{"platform":"openharmony","app":"oh_browser","version":"1.0.0"}`;
      return JSBridgeDispatcher.ok(payload);
    });
  }
}
