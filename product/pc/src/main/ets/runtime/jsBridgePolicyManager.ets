// JSBridgePolicyManager: decides whether JSBridge should be enabled for a given URL,
// and which capabilities should be exposed.
//
// Browser default: disabled. Only enable for internal pages / explicit allowlist.

export enum JSBridgePolicyMode {
  InternalOnly = 0,
  Allowlist = 1,
  OpenAll = 2,
}

export class JSBridgePolicy {
  public enabled: boolean;
  public allowedHosts: string[];
  public capabilities: string[];
  public capabilityGateEnabled: boolean;

  constructor(enabled: boolean, allowedHosts: string[], capabilities: string[], capabilityGateEnabled: boolean) {
    this.enabled = enabled;
    this.allowedHosts = allowedHosts;
    this.capabilities = capabilities;
    this.capabilityGateEnabled = capabilityGateEnabled;
  }

  static disabled(): JSBridgePolicy {
    return new JSBridgePolicy(false, [], [], true);
  }
}

export class JSBridgePolicyManager {
  private static instance: JSBridgePolicyManager | null = null;

  static getInstance(): JSBridgePolicyManager {
    if (JSBridgePolicyManager.instance) {
      return JSBridgePolicyManager.instance;
    }
    JSBridgePolicyManager.instance = new JSBridgePolicyManager();
    return JSBridgePolicyManager.instance;
  }

  private mode: JSBridgePolicyMode = JSBridgePolicyMode.InternalOnly;
  private allowlistHosts: Set<string> = new Set();

  setMode(mode: JSBridgePolicyMode): void {
    this.mode = mode;
  }

  getMode(): JSBridgePolicyMode {
    return this.mode;
  }

  setAllowlistHosts(hosts: string[]): void {
    this.allowlistHosts = new Set((hosts || []).map(h => String(h || '').trim().toLowerCase()).filter(Boolean));
  }

  resolve(url: string): JSBridgePolicy {
    const u = String(url || '');

    if (this.mode === JSBridgePolicyMode.OpenAll) {
      // Full open: enable bridge for all pages. Do NOT enable capability gate.
      // (JS side setCapabilities({}) => no gate; Native dispatcher gate disabled too.)
      return new JSBridgePolicy(true, [], [], false);
    }

    // Internal rawfile JSBridge test pages.
    if (u.startsWith('resource://rawfile/jsbridge/')) {
      return new JSBridgePolicy(true, [], ['browser.ping', 'system.getSystemInfo'], true);
    }

    // Internal settings WebUI pages.
    if (u.startsWith('resource://rawfile/settings/')) {
      return new JSBridgePolicy(true, [], [
        'browser.ping',
        'system.getSystemInfo',
        'settings.getSnapshot',
        'settings.update',
        'settings.setDefaultSearchEngine',
        'privacy.clearBrowsingData',
      ], true);
    }

    if (this.mode === JSBridgePolicyMode.Allowlist) {
      const host = JSBridgePolicyManager.extractHost(u);
      if (host && this.allowlistHosts.has(host)) {
        // Allowlisted websites: enable bridge, but keep capabilities minimal.
        // Expand per product needs.
        return new JSBridgePolicy(true, [host], ['browser.ping', 'system.getSystemInfo'], true);
      }
    }

    return JSBridgePolicy.disabled();
  }

  private static extractHost(url: string): string {
    try {
      const m = String(url || '').match(/^https?:\/\/([^\/]+)/i);
      if (!m || !m[1]) {
        return '';
      }
      return String(m[1]).split(':')[0].toLowerCase();
    } catch (_) {
      return '';
    }
  }
}
