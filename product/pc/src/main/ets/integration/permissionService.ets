import { SitePermissionType } from '../core/permissionTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class PermissionService {
  private nextRequestCode: number = 1000;
  private static readonly LOG_DOMAIN: number = 0x0000;
  private static readonly LOG_TAG: string = 'PermissionTrace';
  private static readonly COMPAT_LOG_TAG: string = 'FaviconTrace';

  async ensureForSitePermission(hostContext: object | undefined, permissionType: SitePermissionType): Promise<boolean> {
    const permissions = this.getSystemPermissions(permissionType);
    if (permissions.length === 0) {
      return true;
    }
    return this.requestSystemPermissions(hostContext, permissions);
  }

  async ensureForPasteboard(hostContext: object | undefined): Promise<boolean> {
    return this.requestSystemPermissions(hostContext, ['ohos.permission.READ_PASTEBOARD']);
  }

  private async requestSystemPermissions(hostContext: object | undefined, permissions: string[]): Promise<boolean> {
    const context = hostContext as common.UIAbilityContext | undefined;
    if (!context) {
      this.trace('REQUEST_UNAVAILABLE', permissions, 'reason=no_host_context');
      return false;
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = await this.getAccessTokenId();
      if (tokenId <= 0) {
        this.trace('REQUEST_UNAVAILABLE', permissions, 'reason=token_id_unavailable');
        return false;
      }

      const verifyBefore = await this.verifyAllWithAtManager(atManager, tokenId, permissions);
      this.trace('VERIFY_BEFORE', permissions,
        `tokenId=${tokenId} results=${verifyBefore.map((value: number) => String(value)).join(',')}`);
      const pendingPermissions: string[] = [];
      verifyBefore.forEach((value: number, index: number) => {
        if (value !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          pendingPermissions.push(permissions[index]);
        }
      });

      if (pendingPermissions.length === 0) {
        this.trace('ALREADY_GRANTED', permissions, 'requestSkipped=true');
        return this.prepareCaptureRuntime(context, permissions);
      }

      const requestCode = this.nextRequestCode++;
      this.trace('SYSTEM_PERMISSION_REQUEST_BEGIN', pendingPermissions,
        `requestCode=${requestCode} tokenId=${tokenId} api=abilityAccessCtrl`);
      const result = await atManager.requestPermissionsFromUser(
        context,
        pendingPermissions as Permissions[],
      );
      const authResults: number[] = result && Array.isArray(result.authResults) ? result.authResults : [];
      this.trace('SYSTEM_PERMISSION_RESULT', pendingPermissions,
        `requestCode=${requestCode} authResults=${authResults.map((value: number) => String(value)).join(',') || 'empty'}`);

      // The post-request AT state is authoritative; callback values alone can
      // be incomplete on some platform versions.
      const verifyAfter = await this.verifyAllWithAtManager(atManager, tokenId, permissions);
      const granted = verifyAfter.length === permissions.length &&
        verifyAfter.every((value: number) => value === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      this.trace(granted ? 'SYSTEM_PERMISSION_GRANTED' : 'SYSTEM_PERMISSION_DENIED', permissions,
        `tokenId=${tokenId} verifyAfter=${verifyAfter.map((value: number) => String(value)).join(',')} ` +
        `authResults=${authResults.map((value: number) => String(value)).join(',') || 'empty'}`);
      if (!granted) {
        return false;
      }
      return this.prepareCaptureRuntime(context, permissions);
    } catch (error) {
      const detail = this.describeError(error as BusinessError);
      this.trace('REQUEST_FAILED', permissions, `reason=exception ${detail}`);
      return false;
    }
  }

  private async getAccessTokenId(): Promise<number> {
    const bundleInfo = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
    );
    return bundleInfo.appInfo.accessTokenId;
  }

  private async verifyAllWithAtManager(
    atManager: abilityAccessCtrl.AtManager,
    tokenId: number,
    permissions: string[],
  ): Promise<number[]> {
    const results: number[] = [];
    for (let index = 0; index < permissions.length; index++) {
      try {
        results.push(await atManager.checkAccessToken(tokenId, permissions[index] as Permissions));
      } catch (error) {
        results.push(abilityAccessCtrl.GrantStatus.PERMISSION_DENIED);
        this.trace('VERIFY_FAILED', [permissions[index]], this.describeError(error as BusinessError));
      }
    }
    return results;
  }

  private describeError(error: BusinessError): string {
    const value = error as BusinessError;
    const code = value.code;
    const message = value.message;
    return `code=${code ?? 'unknown'} message=${message ?? 'unknown'}`;
  }

  private trace(stage: string, permissions: string[], detail: string): void {
    const message = `${stage} permissions=${permissions.join(',')} ${detail}`;
    // Emit under both tags. Some device log viewers only expose the tag used
    // by the browser's existing diagnostics, while others filter by the new
    // permission-specific tag.
    hilog.info(PermissionService.LOG_DOMAIN, PermissionService.LOG_TAG,
      'PermissionTrace %{public}s', message);
    hilog.info(PermissionService.LOG_DOMAIN, PermissionService.COMPAT_LOG_TAG,
      'PermissionTrace %{public}s', message);
  }

  private getSystemPermissions(permissionType: SitePermissionType): string[] {
    if (permissionType === 'location') {
      return ['ohos.permission.LOCATION'];
    }
    if (permissionType === 'camera') {
      return ['ohos.permission.CAMERA'];
    }
    if (permissionType === 'microphone') {
      return ['ohos.permission.MICROPHONE'];
    }
    return [];
  }

  /**
   * 准备 ArkWeb 原生媒体采集所依赖的系统级状态。
   * 这不是 PCM 旁路，也不会改写网页的 getUserMedia；网页仍通过
   * onPermissionRequest -> request.grant(TYPE_*_CAPTURE) 走 ArkWeb 原生链路。
   */
  private async prepareCaptureRuntime(
    context: common.UIAbilityContext,
    permissions: string[],
  ): Promise<boolean> {
    const needsCamera = permissions.indexOf('ohos.permission.CAMERA') >= 0;
    const needsMicrophone = permissions.indexOf('ohos.permission.MICROPHONE') >= 0;
    if (!needsCamera && !needsMicrophone) {
      return true;
    }

    const atManager = abilityAccessCtrl.createAtManager();
    if (needsCamera) {
      const ready = await this.requestCaptureGlobalSwitch(
        context, atManager, abilityAccessCtrl.SwitchType.CAMERA, 'camera');
      if (!ready) {
        return false;
      }
    }
    if (needsMicrophone) {
      const ready = await this.requestCaptureGlobalSwitch(
        context, atManager, abilityAccessCtrl.SwitchType.MICROPHONE, 'microphone');
      if (!ready) {
        return false;
      }
      // 音频会话激活失败不直接拒绝 ArkWeb 授权：部分系统版本没有完整
      // AudioSession 能力，但原生 Web 采集仍可能正常工作。
      await this.prepareMicrophoneAudioSession();
    }
    return true;
  }

  private async requestCaptureGlobalSwitch(
    context: common.UIAbilityContext,
    atManager: abilityAccessCtrl.AtManager,
    switchType: abilityAccessCtrl.SwitchType,
    permissionName: string,
  ): Promise<boolean> {
    try {
      const opened = await atManager.requestGlobalSwitch(context, switchType);
      this.trace('CAPTURE_GLOBAL_SWITCH', [permissionName], `opened=${String(opened)}`);
      return opened === true;
    } catch (error) {
      const businessError = error as BusinessError;
      // 12100013：全局开关已经打开，属于成功状态。
      if (businessError.code === 12100013) {
        this.trace('CAPTURE_GLOBAL_SWITCH_ALREADY_ON', [permissionName], 'code=12100013');
        return true;
      }
      this.trace('CAPTURE_GLOBAL_SWITCH_FAILED', [permissionName], this.describeError(businessError));
      // 部分设备/API 版本没有公开全局开关接口。此时不阻断标准 ArkWeb
      // 链路，最终是否能采集由 request.grant 后的 Web 内核决定。
      return true;
    }
  }

  private async prepareMicrophoneAudioSession(): Promise<void> {
    try {
      const sessionManager = audio.getAudioManager().getSessionManager();
      if (sessionManager.isAudioSessionActivated()) {
        this.trace('MICROPHONE_AUDIO_SESSION_READY', ['ohos.permission.MICROPHONE'], 'alreadyActive=true');
        return;
      }
      const strategy: audio.AudioSessionStrategy = {
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS,
      };
      await sessionManager.activateAudioSession(strategy);
      this.trace('MICROPHONE_AUDIO_SESSION_READY', ['ohos.permission.MICROPHONE'], 'activated=true');
    } catch (error) {
      this.trace('MICROPHONE_AUDIO_SESSION_FAILED', ['ohos.permission.MICROPHONE'],
        this.describeError(error as BusinessError));
    }
  }
}
