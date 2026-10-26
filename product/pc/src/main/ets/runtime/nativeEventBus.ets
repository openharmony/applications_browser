// NativeEventBus: shared event emitters for application lifecycle and system events.
//
// Keep payloads small and JSON-serializable.

import { EventEmitter } from '../common/events';
import { AbilityConstant } from '@kit.AbilityKit';

export type AppLifecycleState = 'foreground' | 'background';

export interface AppLifecyclePayload {
  state: AppLifecycleState;
  ts: number;
}

export const appLifecycleEvents = new EventEmitter<AppLifecyclePayload>();

/**
 * EntryAbility emits memory pressure changes; BrowserPage adjusts live WebView runtimes.
 */
export interface MemoryPressurePayload {
  level: AbilityConstant.MemoryLevel;
  ts: number;
}

let currentMemoryPressureLevel: AbilityConstant.MemoryLevel =
  AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE;

export const memoryPressureEvents = new EventEmitter<MemoryPressurePayload>();

export function emitMemoryPressure(level: AbilityConstant.MemoryLevel): void {
  currentMemoryPressureLevel = level;
  memoryPressureEvents.emit({ level, ts: Date.now() });
}

export function getCurrentMemoryPressureLevel(): AbilityConstant.MemoryLevel {
  return currentMemoryPressureLevel;
}
