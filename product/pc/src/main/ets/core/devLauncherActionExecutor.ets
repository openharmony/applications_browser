// DevLauncherActionExecutor：统一执行 DevLauncher 的 route / url / op 动作。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookmarkExportService } from './bookmarkExportService';
import { JSBridgePolicyManager, JSBridgePolicyMode } from '../runtime/jsBridgePolicyManager';
import { AppRoute, AppRouter } from './appRouter';
import { BookmarkManager } from './bookmarkManager';
import { DevLauncherEntry, DevLauncherExecutionResult } from './devLauncherTypes';
import { UIAbilityContextWrapper } from './UIAbilityContextWrapper';
import { DebugGate } from './debugGate';

const DOMAIN = 0x0000;

export class DevLauncherActionExecutor {
  private readonly bookmarkExportService: BookmarkExportService = new BookmarkExportService();

  async execute(entry: DevLauncherEntry): Promise<DevLauncherExecutionResult> {
    if (!DebugGate.getInstance().canOpenDevLauncher()) {
      return {
        statusMessage: '当前构建未启用开发工具',
      };
    }

    if (entry.type === 'url') {
      return {
        nextPendingUrl: String(entry.value),
        nextRoute: AppRouter.browser,
      };
    }

    if (entry.type === 'route') {
      return {
        nextRoute: entry.value as AppRoute,
      };
    }

    return this.executeOperation(String(entry.value));
  }

  private async executeOperation(operation: string): Promise<DevLauncherExecutionResult> {
    if (operation === 'log_hello') {
      hilog.info(DOMAIN, 'DevLauncher', 'hello from DevLauncherActionExecutor');
      return {
        statusMessage: '已写入一条调试日志',
      };
    }

    if (operation === 'jsbridge_mode_openall') {
      if (!DebugGate.getInstance().canUseUnsafeDebugCapabilities()) {
        return {
          statusMessage: '当前构建不允许开放全部 JSBridge 能力',
        };
      }
      JSBridgePolicyManager.getInstance().setMode(JSBridgePolicyMode.OpenAll);
      hilog.info(DOMAIN, 'DevLauncher', 'JSBridgePolicyMode -> OpenAll');
      return {
        statusMessage: 'JSBridge 策略已切换为 OpenAll',
      };
    }

    if (operation === 'jsbridge_mode_internal') {
      JSBridgePolicyManager.getInstance().setMode(JSBridgePolicyMode.InternalOnly);
      hilog.info(DOMAIN, 'DevLauncher', 'JSBridgePolicyMode -> InternalOnly');
      return {
        statusMessage: 'JSBridge 策略已切换为 InternalOnly',
      };
    }

    if (operation === 'export_bookmarks_html') {
      const context = UIAbilityContextWrapper.getCurrentContext();
      if (!context) {
        return {
          statusMessage: '未获取到 UIAbilityContext，无法导出书签',
        };
      }

      const bookmarkManager: BookmarkManager = BookmarkManager.getInstance();
      const result = await this.bookmarkExportService.exportToPicker(context, bookmarkManager);
      hilog.info(
        DOMAIN,
        'DevLauncher',
        'Exported bookmarks html. folders=%{public}d bookmarks=%{public}d uri=%{public}s',
        result.totalFolders,
        result.totalBookmarks,
        result.fileUri,
      );
      return {
        nextRoute: AppRouter.bookmarks,
        statusMessage:
          `书签已导出：文件夹 ${result.totalFolders} 个，` +
            `书签 ${result.totalBookmarks} 条，保存到 ${result.fileUri}。`,
      };
    }

    return {
      statusMessage: `未识别的调试操作：${operation}`,
    };
  }
}
