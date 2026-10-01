export type SettingsNavigationMode = 'drawer' | 'rail' | 'sidebar';

export interface SettingsLayoutConfig {
  drawerBreakpoint: number;
  sidebarBreakpoint: number;
  compactContentBreakpoint: number;
  sidebarWidth: number;
  railWidth: number;
  drawerWidth: number;
  contentMaxWidth: number;
  compactContentPadding: number;
  contentPadding: number;
}

// Settings responsive layout values are intentionally kept in one editable block.
export const SETTINGS_LAYOUT_CONFIG: SettingsLayoutConfig = {
  drawerBreakpoint: 560,
  sidebarBreakpoint: 900,
  compactContentBreakpoint: 720,
  sidebarWidth: 240,
  railWidth: 64,
  drawerWidth: 240,
  contentMaxWidth: 800,
  compactContentPadding: 16,
  contentPadding: 24,
};

export class SettingsLayoutPolicy {
  static resolveNavigationMode(viewportWidth: number): SettingsNavigationMode {
    if (viewportWidth < SETTINGS_LAYOUT_CONFIG.drawerBreakpoint) {
      return 'drawer';
    }
    if (viewportWidth < SETTINGS_LAYOUT_CONFIG.sidebarBreakpoint) {
      return 'rail';
    }
    return 'sidebar';
  }

  static useCompactContent(viewportWidth: number): boolean {
    return viewportWidth < SETTINGS_LAYOUT_CONFIG.compactContentBreakpoint;
  }

  static getContentPadding(viewportWidth: number): number {
    return viewportWidth < SETTINGS_LAYOUT_CONFIG.drawerBreakpoint ?
      SETTINGS_LAYOUT_CONFIG.compactContentPadding : SETTINGS_LAYOUT_CONFIG.contentPadding;
  }

  static getNavigationWidth(compact: boolean): number {
    return compact ? SETTINGS_LAYOUT_CONFIG.railWidth : SETTINGS_LAYOUT_CONFIG.sidebarWidth;
  }

  static getDrawerWidth(): number {
    return SETTINGS_LAYOUT_CONFIG.drawerWidth;
  }

  static getContentMaxWidth(): number {
    return SETTINGS_LAYOUT_CONFIG.contentMaxWidth;
  }
}
