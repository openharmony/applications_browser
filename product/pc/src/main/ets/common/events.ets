// 简单的事件发射器，用于解耦组件间通信。

type Listener<T> = (payload: T) => void;

export class EventEmitter<T> {
  private listeners: Set<Listener<T>> = new Set();

  on(listener: Listener<T>): void {
    this.listeners.add(listener);
  }

  off(listener: Listener<T>): void {
    this.listeners.delete(listener);
  }

  emit(payload: T): void {
    this.listeners.forEach(listener => listener(payload));
  }
}
