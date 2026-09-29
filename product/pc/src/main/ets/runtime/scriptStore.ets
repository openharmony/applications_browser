// ScriptStore: load and cache rawfile scripts (e.g. JSBridge SDK).
//
// Notes:
// - Keep this module free of UI dependencies.
// - ResourceManager APIs differ across SDK versions; this file provides a single entry point.

export class ScriptStore {
  private static sdkCached: string | null = null;

  static getCachedJsBridgeSdk(): string | null {
    return ScriptStore.sdkCached;
  }

  static setCachedJsBridgeSdk(source: string): void {
    ScriptStore.sdkCached = source;
  }

  // TODO: implement rawfile loading using the project's chosen context/resourceManager API.
  // Expected path: 'jsbridge/index.global.js' under entry/src/main/resources/rawfile.
  //
  // Suggested implementation (depends on SDK):
  // - const bytes = await context.resourceManager.getRawFileContent('jsbridge/index.global.js')
  // - decode bytes to string (UTF-8)
  // - cache and return
  static async loadJsBridgeSdkFromRawfile(): Promise<string> {
    if (ScriptStore.sdkCached) return ScriptStore.sdkCached;
    // Placeholder to keep compilation deterministic.
    // Integrator should replace with real rawfile reading.
    ScriptStore.sdkCached = '';
    return ScriptStore.sdkCached;
  }
}

