import { audio } from '@kit.AudioKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { BrowserLog } from 'common'
import { WebPermissionGate } from './WebPermissionGate'

/** 原生麦克风采集状态（供 JSBridge 同步查询） */
export type WebMicCaptureState = 'idle' | 'starting' | 'ready' | 'error'

/**
 * 网页麦克风旁路采集：绕过 ArkWeb ohos_audio_capturer_source
 * （日志：audioBus 拒绝 frameCount:4800 / 约 100ms，导致 getUserMedia 有流无声）。
 * 原生 AudioCapturer 采 PCM，经 JSBridge 喂给页面 AudioContext MediaStream。
 */
export class WebMicCaptureService {
  private static instance: WebMicCaptureService | null = null
  private capturer: audio.AudioCapturer | undefined = undefined
  private state: WebMicCaptureState = 'idle'
  private errorMsg: string = ''
  private pcmChunks: Uint8Array[] = []
  private queuedBytes: number = 0
  private readonly maxQueuedBytes: number = 48000 * 2 // 约 1s @48kHz mono S16
  private readCb: ((buffer: ArrayBuffer) => void) | undefined = undefined
  private startToken: number = 0
  private readonly base64 = new util.Base64Helper()

  static getInstance(): WebMicCaptureService {
    if (WebMicCaptureService.instance === null) {
      WebMicCaptureService.instance = new WebMicCaptureService()
    }
    return WebMicCaptureService.instance
  }

  getState(): string {
    if (this.state === 'error') {
      return `error:${this.errorMsg}`
    }
    return this.state
  }

  /** 同步入口：触发异步启动，立即返回当前/过渡状态 */
  start(origin: string): string {
    if (this.state === 'ready') {
      return 'ready'
    }
    if (this.state === 'starting') {
      return 'starting'
    }
    this.state = 'starting'
    this.errorMsg = ''
    const token = ++this.startToken
    void this.startAsync(origin, token)
    return 'starting'
  }

  stop(): void {
    this.startToken++
    this.releaseCapturer()
    this.pcmChunks = []
    this.queuedBytes = 0
    this.state = 'idle'
    this.errorMsg = ''
    BrowserLog.info('[WebMic] stopped')
  }

  /**
   * 取出最多 maxBytes 字节的 PCM（S16LE mono 48kHz），Base64 返回；无数据返回空串。
   */
  pullPcmBase64(maxBytes: number): string {
    if (this.state !== 'ready' || this.queuedBytes <= 0 || maxBytes <= 0) {
      return ''
    }
    const take = Math.min(maxBytes, this.queuedBytes)
    const out = new Uint8Array(take)
    let offset = 0
    while (offset < take && this.pcmChunks.length > 0) {
      const head = this.pcmChunks[0]
      const need = take - offset
      if (head.byteLength <= need) {
        for (let i = 0; i < head.byteLength; i++) {
          out[offset + i] = head[i]
        }
        offset += head.byteLength
        this.pcmChunks.shift()
        this.queuedBytes -= head.byteLength
      } else {
        for (let i = 0; i < need; i++) {
          out[offset + i] = head[i]
        }
        const restLen = head.byteLength - need
        const restCopy = new Uint8Array(restLen)
        for (let i = 0; i < restLen; i++) {
          restCopy[i] = head[need + i]
        }
        this.pcmChunks[0] = restCopy
        this.queuedBytes -= need
        offset += need
      }
    }
    if (offset <= 0) {
      return ''
    }
    let encoded: Uint8Array = out
    if (offset < take) {
      encoded = new Uint8Array(offset)
      for (let i = 0; i < offset; i++) {
        encoded[i] = out[i]
      }
    }
    try {
      return this.base64.encodeToStringSync(encoded)
    } catch (err) {
      BrowserLog.warn(`[WebMic] base64 encode failed: ${JSON.stringify(err)}`)
      return ''
    }
  }

  private async startAsync(origin: string, token: number): Promise<void> {
    try {
      const allowed = await WebPermissionGate.getInstance().ensureWebMicrophone(origin)
      if (token !== this.startToken) {
        return
      }
      if (!allowed) {
        this.fail('denied')
        return
      }
      await WebPermissionGate.prepareMicrophoneAudioSession()
      if (token !== this.startToken) {
        return
      }
      this.releaseCapturer()
      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      }
      const capturerInfo: audio.AudioCapturerInfo = {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
      const options: audio.AudioCapturerOptions = {
        streamInfo: streamInfo,
        capturerInfo: capturerInfo
      }
      const capturer = await audio.createAudioCapturer(options)
      if (token !== this.startToken) {
        try {
          await capturer.release()
        } catch (_e) {
          // ignore
        }
        return
      }
      this.readCb = (buffer: ArrayBuffer): void => {
        this.enqueuePcm(buffer)
      }
      capturer.on('readData', this.readCb)
      await capturer.start()
      if (token !== this.startToken) {
        try {
          capturer.off('readData', this.readCb)
          await capturer.stop()
          await capturer.release()
        } catch (_e) {
          // ignore
        }
        return
      }
      this.capturer = capturer
      this.state = 'ready'
      BrowserLog.info('[WebMic] capturer ready origin=' + origin.slice(0, 80))
    } catch (err) {
      if (token !== this.startToken) {
        return
      }
      const msg = `${(err as BusinessError).code ?? ''}:${(err as BusinessError).message ?? JSON.stringify(err)}`
      BrowserLog.warn(`[WebMic] start failed: ${msg}`)
      this.fail(msg.length > 0 ? msg : 'start_failed')
    }
  }

  private enqueuePcm(buffer: ArrayBuffer): void {
    if (!buffer || buffer.byteLength <= 0) {
      return
    }
    const src = new Uint8Array(buffer)
    const copy = new Uint8Array(src.byteLength)
    for (let i = 0; i < src.byteLength; i++) {
      copy[i] = src[i]
    }
    this.pcmChunks.push(copy)
    this.queuedBytes += copy.byteLength
    while (this.queuedBytes > this.maxQueuedBytes && this.pcmChunks.length > 0) {
      const drop = this.pcmChunks.shift()
      if (drop !== undefined) {
        this.queuedBytes -= drop.byteLength
      }
    }
  }

  private fail(msg: string): void {
    this.releaseCapturer()
    this.pcmChunks = []
    this.queuedBytes = 0
    this.state = 'error'
    this.errorMsg = msg
  }

  private releaseCapturer(): void {
    const c = this.capturer
    const cb = this.readCb
    this.capturer = undefined
    this.readCb = undefined
    if (c === undefined) {
      return
    }
    try {
      if (cb !== undefined) {
        c.off('readData', cb)
      }
    } catch (_e) {
      // ignore
    }
    void c.stop().then(() => {
      return c.release()
    }).catch((_e: BusinessError) => {
      try {
        void c.release()
      } catch (_e2) {
        // ignore
      }
    })
  }
}
