/** 应用初始化门禁：标签写操作须等 DB 加载完成；完整 init 由 BrowserApp.ensureInitialized 保证 */
export class AppInitGate {
  private static gate: Promise<void> = Promise.resolve()
  private static ready: boolean = false

  /** 绑定 BrowserApp 初始化 Promise（EntryAbility onCreate 调用） */
  static bind(initPromise: Promise<void>): void {
    AppInitGate.gate = initPromise.then(() => {
      AppInitGate.ready = true
    }).catch(() => {
      AppInitGate.ready = false
    })
  }

  /** DB 已加载后可执行标签写操作（init 流程内部在 loadFromRepository 后调用） */
  static markReady(): void {
    if (AppInitGate.ready) {
      return
    }
    AppInitGate.ready = true
    AppInitGate.gate = Promise.resolve()
  }

  /** 等待 DB 就绪（非完整 BrowserApp init） */
  static whenReady(): Promise<void> {
    return AppInitGate.gate
  }

  /** 是否已可写标签 */
  static isReady(): boolean {
    return AppInitGate.ready
  }
}
