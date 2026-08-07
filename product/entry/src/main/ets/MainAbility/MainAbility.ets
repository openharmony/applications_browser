import { AbilityConstant, Configuration, ConfigurationConstant, EnvironmentCallback, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BrowserStore } from 'browser_core';
import { BrowserNavigation } from 'browser_core';
import { BrowserWindowService } from 'browser_core';
import { IncognitoWebDataCleaner } from 'browser_core';
import { DownloadNetworkWatcher } from 'browser_core';
import { DownloadNotificationActionHandler } from 'browser_core';
import { DownloadNotificationEventBridge } from 'browser_core';
import { AppPermissionService } from 'browser_core';
import { BrowserApp } from 'browser_core';
import { SystemFontSync } from 'browser_core';
import { SystemThemeSync } from 'browser_core';
import { TabThumbnailRetryService } from 'browser_core';
import { DownloadManager, ShareService } from 'browser_core';

const DOMAIN = 0x0000;

/** 浏览器应用主 Ability（MainAbility 目录），负责系统启动初始化与加载入口页 */
export default class MainAbility extends UIAbility {
  private lastConfigDirection: ConfigurationConstant.Direction = ConfigurationConstant.Direction.DIRECTION_NOT_SET;
  private envCallbackId: number = -1;
  private regressionSmsPending: boolean = false;
  private regressionSmsTitle: string = 'RegressionTitle';
  private regressionSmsUrl: string = 'https://example.com/regression';

  /** Ability 创建时绑定上下文并初始化浏览器服务 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    BrowserStore.bindContext(this.context);
    DownloadNotificationEventBridge.getInstance().ensureSubscribed();
    this.readRegressionSmsWant(want);
    this.captureExternalBrowseWant(want);
    this.lastConfigDirection = this.context.config.direction ?? ConfigurationConstant.Direction.DIRECTION_NOT_SET;
    BrowserWindowService.getInstance().initOrientationFromContext(this.context);
    SystemFontSync.syncFromConfiguration(this.context.config);
    SystemFontSync.registerSettingsObserver();
    SystemThemeSync.syncFromConfiguration(this.context.config);
    this.registerEnvironmentListener();
    DownloadNotificationActionHandler.handleWant(want);
    hilog.info(DOMAIN, 'BrowserApp', '%{public}s', 'Ability onCreate');
  }

  /** 热启动 / 通知栏拉起：处理下载通知与外部 http(s) Want */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    DownloadNotificationActionHandler.handleWant(want);
    this.captureExternalBrowseWant(want);
  }

  /** Ability 销毁时的生命周期回调 */
  onDestroy(): void {
    SystemFontSync.unregisterSettingsObserver();
    this.unregisterEnvironmentListener();
    DownloadNotificationEventBridge.getInstance().dispose()
    DownloadManager.getInstance().shutdown()
    DownloadNetworkWatcher.getInstance().stop()
    TabThumbnailRetryService.getInstance().stop()
    IncognitoWebDataCleaner.getInstance().purgeIncognitoWebData();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /** 主窗口创建时加载 MainPage 作为根页面 */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    BrowserWindowService.getInstance().attachStage(windowStage, this.context);

    windowStage.loadContent('pages/MainPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      BrowserWindowService.getInstance().onContentLoaded();
      this.runRegressionSmsIfNeeded();
      // 窗口首帧就绪后再申请通知等权限（init 阶段弹窗无效）
      setTimeout(() => {
        void BrowserApp.getInstance().ensureInitialized(this.context).then((): Promise<void> => {
          return AppPermissionService.getInstance().syncSitePermissionsWithAppGrants()
        })
      }, 800);
      // 首帧后再初始化 WebEngine，避免阻塞 Ability 生命周期
      setTimeout(() => {
        try {
          webview.WebviewController.initializeWebEngine();
          webview.WebviewController.enableWholeWebPageDrawing();
        } catch (webErr) {
          hilog.error(DOMAIN, 'BrowserApp', 'WebEngine init failed: %{public}s', JSON.stringify(webErr));
        }
      }, 0);
    });
  }

  /** 主窗口销毁时释放 UI 相关资源 */
  onWindowStageDestroy(): void {
    DownloadNotificationEventBridge.getInstance().dispose()
    DownloadManager.getInstance().shutdown()
    TabThumbnailRetryService.getInstance().stop()
    IncognitoWebDataCleaner.getInstance().purgeIncognitoWebData();
    BrowserWindowService.getInstance().detachWindow();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /** 系统配置变更：字体与屏幕方向分开处理，避免 followSystem 字体回调误触横屏 */
  onConfigurationUpdate(newConfig: Configuration): void {
    SystemFontSync.syncFromConfiguration(newConfig);
    SystemThemeSync.syncFromConfiguration(newConfig);
    if (newConfig.direction !== undefined && newConfig.direction !== this.lastConfigDirection) {
      this.lastConfigDirection = newConfig.direction;
      BrowserWindowService.getInstance().onDirectionChanged(newConfig.direction);
    }
  }

  /** Ability 切换到前台（多任务切回时刷新系统字号，补齐 nonFollowSystem 下无 configuration 回调的情况） */
  onForeground(): void {
    BrowserWindowService.getInstance().onAbilityForeground()
    BrowserWindowService.getInstance().syncSystemBarForTheme()
    SystemFontSync.syncFromConfiguration(this.context.config)
    // 多任务切回不会走 Router onPageShow，且此刻 Web 往往尚未 OnWindowShow；延迟 tick 再强制应用 textZoom
    SystemFontSync.scheduleForegroundWebZoomApply()
    AppPermissionService.getInstance().refreshAllOnForeground()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  /** Ability 切换到后台 */
  onBackground(): void {
    BrowserWindowService.getInstance().onAbilityBackground()
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /** 全局环境变更（系统字体/主题等），补充 onConfigurationUpdate */
  private registerEnvironmentListener(): void {
    try {
      const envCallback: EnvironmentCallback = {
        onConfigurationUpdated: (config: Configuration) => {
          SystemFontSync.syncFromConfiguration(config);
          SystemThemeSync.syncFromConfiguration(config);
        },
        onMemoryLevel: (_level: number) => {
        }
      };
      this.envCallbackId = this.context.getApplicationContext().on('environment', envCallback);
    } catch (err) {
      hilog.warn(DOMAIN, 'BrowserApp', 'environment listener failed: %{public}s', JSON.stringify(err));
    }
  }

  private unregisterEnvironmentListener(): void {
    if (this.envCallbackId < 0) {
      return;
    }
    try {
      this.context.getApplicationContext().off('environment', this.envCallbackId);
    } catch (_err) {
    }
    this.envCallbackId = -1;
  }

  /** 解析设置/文件管理器等隐式 Want：want.uri 为待打开的 http(s) 或本地 file */
  private captureExternalBrowseWant(want: Want): void {
    const uri = (want.uri ?? '').trim()
    if (uri.length === 0) {
      return
    }
    hilog.info(DOMAIN, 'BrowserApp', 'External want uri=%{public}s action=%{public}s type=%{public}s',
      uri.slice(0, 120), want.action ?? '', want.type ?? '')
    BrowserNavigation.queueExternalBrowseUrl(uri)
  }

  /** 读取 aa 回归参数：--ps regressionSms 1 --ps regressionSmsUrl ... */
  private readRegressionSmsWant(want: Want): void {
    const params = want.parameters
    if (!params) {
      return
    }
    const flag = params['regressionSms']
    if (flag !== '1' && flag !== 1 && flag !== true) {
      return
    }
    this.regressionSmsPending = true
    const title = params['regressionSmsTitle']
    const url = params['regressionSmsUrl']
    if (typeof title === 'string' && title.trim().length > 0) {
      this.regressionSmsTitle = title.trim()
    }
    if (typeof url === 'string' && url.trim().length > 0) {
      this.regressionSmsUrl = url.trim()
    }
  }

  /** 自动化回归：触发分享→短信（与 ShareService.tryLaunchMmsText 同路径） */
  private runRegressionSmsIfNeeded(): void {
    if (!this.regressionSmsPending) {
      return
    }
    this.regressionSmsPending = false
    setTimeout(() => {
      void ShareService.getInstance().shareLinkViaSms(this.regressionSmsTitle, this.regressionSmsUrl)
    }, 1500)
  }
}
