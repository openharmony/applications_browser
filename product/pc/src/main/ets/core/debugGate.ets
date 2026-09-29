// DebugGate：控制开发调试入口在不同模式下的可见性与启动行为。

import { AppRoute } from './appRouter';
import BuildProfile from 'BuildProfile';

export type AppMode = 'prod' | 'internal' | 'dev';

export class DebugGate {
  private static instance: DebugGate = new DebugGate();

  private readonly appMode: AppMode = BuildProfile.DEBUG ? 'dev' : 'prod';
  private readonly startupRoute: AppRoute = 'browser';

  static getInstance(): DebugGate {
    return DebugGate.instance;
  }

  getAppMode(): AppMode {
    return this.appMode;
  }

  canOpenDevLauncher(): boolean {
    return this.appMode === 'dev' || this.appMode === 'internal';
  }

  canUseUnsafeDebugCapabilities(): boolean {
    return BuildProfile.DEBUG && this.appMode === 'dev';
  }

  shouldShowHomeDevEntry(): boolean {
    return this.canOpenDevLauncher();
  }

  shouldLaunchToDevLauncher(): boolean {
    return this.canOpenDevLauncher() && this.startupRoute === 'dev';
  }
}
