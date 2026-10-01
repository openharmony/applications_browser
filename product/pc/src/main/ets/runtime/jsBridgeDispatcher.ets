// JSBridgeDispatcher: routes JS->Native calls to ArkTS handlers and returns JSON payloads.
//
// Design goals:
// - ArkTS-friendly: avoid dynamic object dictionaries; use Map/Set
// - Browser-grade: capability gate + basic validation

export interface DispatchResult {
  ok: boolean;
  // JSON literal string to be embedded into JS (e.g. '{"a":1}')
  payloadJson: string;
}

export type MethodHandler = (paramsJson: string, url: string) => Promise<DispatchResult>;

export class JSBridgeDispatcher {
  private handlers: Map<string, MethodHandler> = new Map();
  private allowedMethods: Set<string> = new Set();
  private gateEnabled: boolean = true;

  setGateEnabled(on: boolean): void {
    this.gateEnabled = !!on;
  }

  setAllowedMethods(methods: string[]): void {
    this.allowedMethods = new Set((methods || []).map(m => String(m || '').trim()).filter(Boolean));
  }

  register(method: string, handler: MethodHandler): void {
    const m = String(method || '').trim();
    if (!m) {
      return;
    }
    this.handlers.set(m, handler);
  }

  unregister(method: string): void {
    this.handlers.delete(String(method || '').trim());
  }

  async dispatch(method: string, paramsJson: string, url: string): Promise<DispatchResult> {
    const m = String(method || '').trim();
    if (!m) {
      return JSBridgeDispatcher.fail(-32602, 'invalid_method');
    }

    // Capability gate: when enabled and allowedMethods is non-empty, method must be explicitly allowed.
    if (this.gateEnabled && this.allowedMethods.size > 0 && !this.allowedMethods.has(m)) {
      return JSBridgeDispatcher.fail(-32601, 'not_implemented');
    }

    const handler = this.handlers.get(m);
    if (!handler) {
      return JSBridgeDispatcher.fail(-32601, 'method_not_found');
    }

    try {
      return await handler(paramsJson || '{}', url || '');
    } catch (e) {
      const msg = (e instanceof Error && e.message) ? e.message : 'handler_error';
      return JSBridgeDispatcher.fail(-32002, msg);
    }
  }

  static ok(payload: string): DispatchResult {
    const json = payload && payload.trim() ? payload : 'null';
    const res: DispatchResult = { ok: true, payloadJson: json };
    return res;
  }

  static fail(code: number, message: string): DispatchResult {
    const c = Number.isFinite(code) ? Math.trunc(code) : -1;
    const m = String(message || 'Error');
    // Avoid untyped object literals in ArkTS.
    const payload = `{"code":${c},"message":${JSON.stringify(m)}}`;
    const res: DispatchResult = { ok: false, payloadJson: payload };
    return res;
  }
}
