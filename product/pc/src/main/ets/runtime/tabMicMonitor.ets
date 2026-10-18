import { WebMicCaptureService } from '../integration/webMicCaptureService';

export const TAB_MIC_BRIDGE_NAME: string = 'ohTabMicBridge';
export const TAB_MIC_METHODS: string[] = [
  'startNativeMic',
  'stopNativeMic',
  'getNativeMicState',
  'pullMicPcm',
];

export class TabMicBridge {
  private readonly service: WebMicCaptureService;

  constructor(service: WebMicCaptureService) {
    this.service = service;
  }

  startNativeMic(origin: string): string {
    return this.service.start((origin ?? '').trim());
  }

  stopNativeMic(): string {
    this.service.stop();
    return 'idle';
  }

  getNativeMicState(): string {
    return this.service.getState();
  }

  pullMicPcm(maxBytes: string): string {
    const parsed = Number.parseInt(maxBytes, 10);
    const limit = Number.isFinite(parsed) && parsed > 0 ? parsed : 4096;
    return this.service.pullPcmBase64(limit);
  }
}
