import webview from '@ohos.web.webview';
import { JSBridgeFacade } from '../../runtime/jsBridgeFacade';
import { JSBridgePolicyManager } from '../../runtime/jsBridgePolicyManager';
import { ScriptStore } from '../../runtime/scriptStore';
import { registerSettingsBridgeHandlers, SETTINGS_BRIDGE_CAPABILITIES } from '../../runtime/settingsBridge';
import { LocalHtmlWebView } from '../components/LocalHtmlWebView';

const SETTINGS_WEB_URL = 'resource://rawfile/settings/index.html';

@Component
export struct WebSettingsPage {
  onFallbackToNative: () => void = () => {};

  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private readonly jsBridge: JSBridgeFacade = new JSBridgeFacade(this.controller, {
    enabled: true,
    autoExposeAliases: ['OHBridge'],
    overrideExistingGlobals: false,
    capabilities: ['browser.ping', 'system.getSystemInfo'].concat(SETTINGS_BRIDGE_CAPABILITIES),
    capabilityGateEnabled: true,
  });
  private bridgeRegistered: boolean = false;

  @State private loadFailed: boolean = false;

  aboutToAppear(): void {
    this.ensureBridgeRegistered();
    const sdk = ScriptStore.getCachedJsBridgeSdk();
    if (sdk) {
      this.jsBridge.setSdkSource(sdk);
    }
  }

  private ensureBridgeRegistered(): void {
    if (this.bridgeRegistered) {
      return;
    }
    registerSettingsBridgeHandlers(this.jsBridge);
    this.bridgeRegistered = true;
  }

  private applyBridgePolicy(url: string): void {
    const policy = JSBridgePolicyManager.getInstance().resolve(url);
    this.jsBridge.setEnabled(policy.enabled);
    this.jsBridge.setAllowedHosts(policy.allowedHosts);
    this.jsBridge.setCapabilityGateEnabled(policy.capabilityGateEnabled);
    this.jsBridge.setCapabilities(policy.capabilities);
  }

  private handlePageBegin(url: string): void {
    this.loadFailed = false;
    this.applyBridgePolicy(url);
    this.jsBridge.onPageBegin(url);
  }

  private handlePageEnd(url: string): void {
    this.applyBridgePolicy(url);
    this.jsBridge.onPageEnd(url);
  }

  private handleLoadError(): void {
    this.loadFailed = true;
    this.onFallbackToNative();
  }

  build() {
    Stack() {
      LocalHtmlWebView({
        src: SETTINGS_WEB_URL,
        controller: this.controller,
        onPageBegin: (url: string) => this.handlePageBegin(url),
        onPageEnd: (url: string) => this.handlePageEnd(url),
        onLoadError: () => this.handleLoadError(),
      });

      if (this.loadFailed) {
        Column({ space: 12 }) {
          Text('设置页加载失败')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text('已切换到原生设置页。')
            .fontSize(13)
            .fontColor('#6b7280');
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#f3f4f6');
      }
    }
    .width('100%')
    .height('100%');
  }
}
