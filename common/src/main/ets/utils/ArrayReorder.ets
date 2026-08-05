/** 线性数组重排：从 from 拔出插入 to（与 ShortcutManager.reorder 一致） */
export function reorderArrayIds(ids: string[], from: number, to: number): string[] {
  if (from < 0 || to < 0 || from >= ids.length || to >= ids.length || from === to) {
    return [...ids]
  }
  const next = [...ids]
  const item = next.splice(from, 1)[0]
  next.splice(to, 0, item)
  return next
}
