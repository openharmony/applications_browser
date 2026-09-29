// NativeEventBus: shared event emitters for propagating native-side lifecycle/system events
// to the currently active WebView/JSBridge layer.
//
// Keep payloads small and JSON-serializable.

import { EventEmitter } from '../common/events';
import { AbilityConstant } from '@kit.AbilityKit';

export type AppLifecycleState = 'foreground' | 'background';

export interface AppLifecyclePayload {
  state: AppLifecycleState;
  ts: number;
}

export const AppLifecycleEvents = new EventEmitter<AppLifecyclePayload>();

/**
 * System memory pressure notifications are emitted by EntryAbility and
 * consumed by BrowserPage. Keeping this channel separate from lifecycle
 * events avoids coupling the WebView manager to the ability implementation.
 */
export interface MemoryPressurePayload {
  level: AbilityConstant.MemoryLevel;
  ts: number;
}

let currentMemoryPressureLevel: AbilityConstant.MemoryLevel =
  AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE;

export const MemoryPressureEvents = new EventEmitter<MemoryPressurePayload>();

export function emitMemoryPressure(level: AbilityConstant.MemoryLevel): void {
  currentMemoryPressureLevel = level;
  MemoryPressureEvents.emit({ level, ts: Date.now() });
}

export function getCurrentMemoryPressureLevel(): AbilityConstant.MemoryLevel {
  return currentMemoryPressureLevel;
}
