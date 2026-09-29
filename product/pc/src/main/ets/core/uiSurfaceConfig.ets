export type SettingsUiMode = 'native' | 'html';

export class UiSurfaceConfig {
  private static settingsUiMode: SettingsUiMode = 'native';
  private static fallbackToNativeWhenWebFailed: boolean = true;

  static getSettingsUiMode(): SettingsUiMode {
    return UiSurfaceConfig.settingsUiMode;
  }

  static setSettingsUiMode(mode: SettingsUiMode): void {
    UiSurfaceConfig.settingsUiMode = mode;
  }

  static shouldFallbackToNativeWhenWebFailed(): boolean {
    return UiSurfaceConfig.fallbackToNativeWhenWebFailed;
  }

  static setFallbackToNativeWhenWebFailed(enabled: boolean): void {
    UiSurfaceConfig.fallbackToNativeWhenWebFailed = enabled;
  }
}
