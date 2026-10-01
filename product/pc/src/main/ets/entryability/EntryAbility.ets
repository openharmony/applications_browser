import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import webview from '@ohos.web.webview';
import { AppStorageV2 } from '@kit.ArkUI';
import { UIAbilityContextWrapper } from '../core/UIAbilityContextWrapper';
import { HistoryManager } from '../core/historyManager';
import { BookmarkManager } from '../core/bookmarkManager';
import { SiteSettingsManager } from '../core/siteSettingsManager';
import { SessionManager } from '../core/sessionManager';
import { SettingsManager } from '../core/settingsManager';
import { DownloadManager } from '../core/downloadManager';
import { ScriptStore } from '../runtime/scriptStore';
import { SearchEngineConfigProvider } from '../core/searchEngineConfig';
import {
  appLifecycleEvents,
  AppLifecyclePayload,
  emitMemoryPressure,
} from '../runtime/nativeEventBus';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private consumeExternalUrl(want: Want): void {
    const uri = want.uri ? want.uri.trim() : '';
    if (!/^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(uri)) {
      return;
    }
    AppStorage.setOrCreate('browserPendingUrl', uri);
    AppStorage.setOrCreate('browserRoute', 'browser');
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.consumeExternalUrl(want);
    try {
      // 最佳实践：在加载任何 Web 组件之前初始化 ArkWeb 引擎。
      webview.WebviewController.initializeWebEngine();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize web engine. Cause: %{public}s', JSON.stringify(err));
    }

    // Preload JSBridge SDK source from rawfile once and cache it for all tabs.
    // Note: if this fails, JSBridge can still work when pages provide SDK themselves.
    try {
      // getRawFileContent is async; we do not block ability creation.
      this.context.resourceManager.getRawFileContent('jsbridge/index.global.js')
        .then((data: Uint8Array) => {
          try {
            // ASCII fast-path: zz-jsbridge-sdk dist is expected to be ASCII-only.
            // If you bundle non-ASCII scripts later, replace with a proper UTF-8 decoder.
            let text = '';
            for (let i = 0; i < data.length; i++) {
              text += String.fromCharCode(data[i]);
            }
            ScriptStore.setCachedJsBridgeSdk(text);
            hilog.info(DOMAIN, 'JSBridge', 'Preloaded JSBridge SDK, bytes=%{public}d', data.length);
          } catch (e) {
            hilog.error(DOMAIN, 'JSBridge', 'Decode JSBridge SDK failed: %{public}s', JSON.stringify(e));
          }
        })
        .catch((e: object) => {
          hilog.error(DOMAIN, 'JSBridge', 'Load JSBridge SDK failed: %{public}s', JSON.stringify(e));
        });
    } catch (e) {
      hilog.error(DOMAIN, 'JSBridge', 'Preload JSBridge SDK exception: %{public}s', JSON.stringify(e));
    }

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    
    // 初始化历史记录管理器
    try {
      const historyManager = HistoryManager.getInstance();
      historyManager.init(this.context)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'HistoryManager initialized successfully');
        })
        .catch((err: object) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to initialize HistoryManager. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize HistoryManager. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      const siteSettingsManager = SiteSettingsManager.getInstance();
      siteSettingsManager.init(this.context)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'SiteSettingsManager initialized successfully');
        })
        .catch((err: object) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to initialize SiteSettingsManager. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize SiteSettingsManager. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      const bookmarkManager = BookmarkManager.getInstance();
      bookmarkManager.init(this.context)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'BookmarkManager initialized successfully');
        })
        .catch((err: object) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to initialize BookmarkManager. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize BookmarkManager. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      const settingsManager = SettingsManager.getInstance();
      settingsManager.init(this.context)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'SettingsManager initialized successfully');
        })
        .catch((err: object) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to initialize SettingsManager. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize SettingsManager. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      const sessionManager = SessionManager.getInstance();
      sessionManager.init(this.context)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'SessionManager initialized successfully');
        })
        .catch((err: object) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to initialize SessionManager. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize SessionManager. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      const downloadManager = DownloadManager.getInstance();
      downloadManager.init(this.context)
        .then(() => {
          hilog.info(DOMAIN, 'testTag', 'DownloadManager initialized successfully');
        })
        .catch((err: object) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to initialize DownloadManager. Cause: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to initialize DownloadManager. Cause: %{public}s', JSON.stringify(err));
    }
    
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    
    // 存储UIAbilityContext到AppStorageV2，供其他组件使用
    AppStorageV2.connect(UIAbilityContextWrapper, 'uiAbilityContext', () => UIAbilityContextWrapper.create(this.context));
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.consumeExternalUrl(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗口创建完成，为该 Ability 加载主页面。
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    AppStorage.setOrCreate('browserWindowStage', windowStage);
    SearchEngineConfigProvider.load(this.context)
      .catch((err: object) => {
        hilog.error(DOMAIN, 'SearchEngine', 'Load config failed: %{public}s', JSON.stringify(err));
      })
      .finally(() => {
        windowStage.loadContent('pages/Index', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
            return;
          }
          hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
        });
      });
  }

  onWindowStageDestroy(): void {
    // 主窗口销毁，释放 UI 相关资源。
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability 切到前台。
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');

    try {
      const p: AppLifecyclePayload = { state: 'foreground', ts: Date.now() };
      appLifecycleEvents.emit(p);
    } catch (_) {
    }
  }

  onBackground(): void {
    // Ability 切到后台。
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');

    try {
      const p: AppLifecyclePayload = { state: 'background', ts: Date.now() };
      appLifecycleEvents.emit(p);
    } catch (_) {
    }
  }

  /**
   * The system reports device-wide memory pressure through this callback.
   * BrowserPage consumes the event and lets WebViewManager evict inactive
   * runtimes according to its dynamic limit.
   */
  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    hilog.warn(DOMAIN, 'RuntimeMemory', 'MEMORY_LEVEL level=%{public}d', level);
    emitMemoryPressure(level);
  }
}
