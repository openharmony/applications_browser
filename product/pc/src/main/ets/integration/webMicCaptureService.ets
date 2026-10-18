import { audio } from '@kit.AudioKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIAbilityContextWrapper } from '../core/UIAbilityContextWrapper';
import { PermissionService } from './permissionService';

const MIC_LOG_DOMAIN: number = 0x0000;
const MIC_LOG_TAG: string = 'MicTrace';

export type WebMicCaptureState = 'idle' | 'starting' | 'ready' | 'error';

/**
 * PC 端网页麦克风旁路。
 *
 * 手机端已验证 ArkWeb 的 audioBus 在部分系统版本会出现“权限已允许但
 * getUserMedia 没有有效 PCM”的问题，因此这里由 AudioCapturer 采集，再
 * 通过每个 WebView Runtime 自己的 JS Proxy 送回页面。
 */
export class WebMicCaptureService {
  private readonly captureAllowed: boolean;
  private capturer: audio.AudioCapturer | undefined;
  private state: WebMicCaptureState = 'idle';
  private errorMessage: string = '';
  private chunks: Uint8Array[] = [];
  private queuedBytes: number = 0;
  private readonly maxQueuedBytes: number = 48000 * 2;
  private readCallback: ((buffer: ArrayBuffer) => void) | undefined;
  private startToken: number = 0;
  private readonly base64Helper: util.Base64Helper = new util.Base64Helper();
  private readonly permissionService: PermissionService = new PermissionService();
  private hasReceivedPcm: boolean = false;
  private pullCount: number = 0;

  constructor(captureAllowed: boolean = true) {
    this.captureAllowed = captureAllowed;
  }

  getState(): string {
    if (this.state === 'error') {
      return `error:${this.errorMessage}`;
    }
    return this.state;
  }

  start(origin: string): string {
    if (!this.captureAllowed) {
      this.fail('private_mode_denied');
      this.log('START_DENIED', 'reason=private_mode');
      return this.getState();
    }
    if (this.state === 'ready' || this.state === 'starting') {
      return this.getState();
    }
    this.state = 'starting';
    this.errorMessage = '';
    this.hasReceivedPcm = false;
    this.pullCount = 0;
    const token = ++this.startToken;
    this.log('START_REQUEST', `originLength=${origin.length}`);
    void this.startAsync(origin, token);
    return 'starting';
  }

  stop(): void {
    this.startToken++;
    this.releaseCapturer();
    this.chunks = [];
    this.queuedBytes = 0;
    this.state = 'idle';
    this.errorMessage = '';
    this.hasReceivedPcm = false;
    this.pullCount = 0;
    this.log('STOP_REQUEST', 'state=idle');
  }

  pullPcmBase64(maxBytes: number): string {
    if (this.state !== 'ready' || this.queuedBytes <= 0 || maxBytes <= 0) {
      return '';
    }
    const take = Math.min(Math.floor(maxBytes), this.queuedBytes);
    const output = new Uint8Array(take);
    let offset = 0;
    while (offset < take && this.chunks.length > 0) {
      const head = this.chunks[0];
      const need = take - offset;
      if (head.byteLength <= need) {
        output.set(head, offset);
        offset += head.byteLength;
        this.chunks.shift();
        this.queuedBytes -= head.byteLength;
        continue;
      }
      output.set(head.subarray(0, need), offset);
      this.chunks[0] = head.slice(need);
      this.queuedBytes -= need;
      offset += need;
    }
    if (offset <= 0) {
      return '';
    }
    this.pullCount++;
    if (this.pullCount === 1 || this.pullCount % 100 === 0) {
      this.log('PCM_PULL', `count=${this.pullCount} bytes=${offset} queued=${this.queuedBytes}`);
    }
    try {
      return this.base64Helper.encodeToStringSync(offset === output.byteLength ? output : output.slice(0, offset));
    } catch (error) {
      this.log('BASE64_FAILED', String((error as BusinessError).code ?? 'unknown'));
      return '';
    }
  }

  private async startAsync(origin: string, token: number): Promise<void> {
    let localCapturer: audio.AudioCapturer | undefined;
    let localReadCallback: ((buffer: ArrayBuffer) => void) | undefined;
    try {
      const context = UIAbilityContextWrapper.getCurrentContext();
      if (!context) {
        this.fail('context_unavailable');
        return;
      }
      const granted = await this.permissionService.ensureForSitePermission(context, 'microphone');
      if (token !== this.startToken) {
        return;
      }
      this.log('PERMISSION_RESULT', `granted=${String(granted)}`);
      if (!granted) {
        this.fail('permission_denied');
        return;
      }

      this.releaseCapturer();
      const options: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0,
        },
      };
      const capturer = await audio.createAudioCapturer(options);
      localCapturer = capturer;
      if (token !== this.startToken) {
        await capturer.release();
        localCapturer = undefined;
        return;
      }
      const readCallback = (buffer: ArrayBuffer): void => this.enqueue(buffer);
      localReadCallback = readCallback;
      this.readCallback = readCallback;
      capturer.on('readData', readCallback);
      await capturer.start();
      if (token !== this.startToken) {
        this.releaseExternalCapturer(capturer, readCallback);
        if (this.readCallback === readCallback) {
          this.readCallback = undefined;
        }
        localCapturer = undefined;
        return;
      }
      this.capturer = capturer;
      localCapturer = undefined;
      localReadCallback = undefined;
      this.state = 'ready';
      this.log('CAPTURER_READY', `originLength=${origin.length} pcmReceived=${String(this.hasReceivedPcm)}`);
    } catch (error) {
      if (localCapturer && this.capturer !== localCapturer) {
        this.releaseExternalCapturer(localCapturer, localReadCallback);
        if (this.readCallback === localReadCallback) {
          this.readCallback = undefined;
        }
      }
      if (token !== this.startToken) {
        return;
      }
      const businessError = error as BusinessError;
      const code = businessError.code ?? 'unknown';
      this.fail(`capture_${String(code)}`);
      this.log('CAPTURER_FAILED', String(code));
    }
  }

  private enqueue(buffer: ArrayBuffer): void {
    if (!buffer || buffer.byteLength <= 0) {
      return;
    }
    const source = new Uint8Array(buffer);
    const copy = source.slice();
    this.chunks.push(copy);
    this.queuedBytes += copy.byteLength;
    if (!this.hasReceivedPcm) {
      this.hasReceivedPcm = true;
      this.log('PCM_RECEIVED', `bytes=${copy.byteLength}`);
    }
    while (this.queuedBytes > this.maxQueuedBytes && this.chunks.length > 0) {
      const removed = this.chunks.shift();
      if (removed) {
        this.queuedBytes -= removed.byteLength;
      }
    }
  }

  private fail(message: string): void {
    this.releaseCapturer();
    this.chunks = [];
    this.queuedBytes = 0;
    this.state = 'error';
    this.errorMessage = message;
  }

  private releaseCapturer(): void {
    const capturer = this.capturer;
    const callback = this.readCallback;
    this.capturer = undefined;
    this.readCallback = undefined;
    if (!capturer) {
      return;
    }
    this.releaseExternalCapturer(capturer, callback);
  }

  private releaseExternalCapturer(
    capturer: audio.AudioCapturer,
    callback: ((buffer: ArrayBuffer) => void) | undefined,
  ): void {
    try {
      if (callback) {
        capturer.off('readData', callback);
      }
    } catch (_) {
      // The capturer may already be released by the platform.
    }
    void capturer.stop().then(() => capturer.release()).catch(() => {
      try {
        void capturer.release();
      } catch (_) {
        // Ignore a second release on teardown.
      }
    });
  }

  private log(stage: string, detail: string): void {
    hilog.info(MIC_LOG_DOMAIN, MIC_LOG_TAG, '%{public}s detail=%{public}s', stage, detail);
  }
}
