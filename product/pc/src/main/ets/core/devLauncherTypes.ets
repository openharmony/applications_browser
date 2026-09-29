// DevLauncher 相关共享类型定义。

import { AppRoute } from './appRouter';
import { AppMode } from './debugGate';

export type DevLauncherEntryType = 'route' | 'url' | 'op';
export type DevLauncherCategory = 'page' | 'site' | 'bookmark' | 'toggle' | 'diagnostic' | 'danger';
export type DevLauncherRiskLevel = 'low' | 'medium' | 'high';

export interface DevLauncherEntry {
  id: string;
  title: string;
  subtitle?: string;
  category: DevLauncherCategory;
  type: DevLauncherEntryType;
  value: string | AppRoute;
  riskLevel: DevLauncherRiskLevel;
  requiresConfirm?: boolean;
  visibleInModes?: AppMode[];
  pinned?: boolean;
}

export interface DevLauncherExecutionResult {
  nextRoute?: AppRoute;
  nextPendingUrl?: string;
  statusMessage?: string;
}
