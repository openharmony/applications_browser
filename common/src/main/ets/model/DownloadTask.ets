/** 下载任务状态枚举 */
export type DownloadStatus = 'pending' | 'running' | 'paused' | 'done' | 'failed' | 'deleted' | 'queued'

/** 下载任务实体，对应 download_tasks 表 */
export interface DownloadTask {
  /** 下载任务唯一标识 */
  id: string
  /** 本地保存的文件名 */
  fileName: string
  /** 下载来源 URL */
  sourceUrl: string
  /** 本地存储路径（非图片或图片落盘兜底） */
  localPath: string
  /** 图片在系统图库中的资源 URI（图片主存储位置） */
  galleryUri: string
  /** 当前下载状态 */
  status: DownloadStatus
  /** 下载进度（0–100） */
  progress: number
  /** 文件大小（字节） */
  fileSize: number
  /** MIME 类型 */
  mimeType: string
  /** 失败时的错误信息 */
  errorMessage: string
  /** 创建时间戳（毫秒） */
  createdAt: number
  /** 最后更新时间戳（毫秒） */
  updatedAt: number
}

/** 创建下载任务时的输入参数 */
export interface CreateDownloadTaskInput {
  /** 下载任务唯一标识 */
  id: string
  /** 本地保存的文件名 */
  fileName: string
  /** 下载来源 URL */
  sourceUrl: string
  /** 本地存储路径 */
  localPath?: string
  /** 图库资源 URI（图片） */
  galleryUri?: string
  /** 初始下载状态 */
  status?: DownloadStatus
  /** 下载进度（0–100） */
  progress?: number
  /** 文件大小（字节） */
  fileSize?: number
  /** MIME 类型 */
  mimeType?: string
  /** 失败时的错误信息 */
  errorMessage?: string
  /** 创建时间戳（毫秒） */
  createdAt?: number
  /** 最后更新时间戳（毫秒） */
  updatedAt?: number
}

/** 根据输入参数创建下载任务实体，并填充默认值 */
export function createDownloadTask(input: CreateDownloadTaskInput): DownloadTask {
  const now = Date.now()
  return {
    localPath: input.localPath ?? '',
    galleryUri: input.galleryUri ?? '',
    status: input.status ?? 'pending',
    progress: input.progress ?? 0,
    fileSize: input.fileSize ?? 0,
    mimeType: input.mimeType ?? '',
    errorMessage: input.errorMessage ?? '',
    createdAt: input.createdAt ?? now,
    updatedAt: input.updatedAt ?? now,
    id: input.id,
    fileName: input.fileName,
    sourceUrl: input.sourceUrl
  }
}

/** 将字节数格式化为 UI 展示用的文件大小文本 */
export function formatFileSizeText(bytes: number): string {
  if (bytes <= 0) {
    return ''
  }
  if (bytes >= 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
  }
  if (bytes >= 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`
  }
  if (bytes >= 1024) {
    return `${(bytes / 1024).toFixed(2)} KB`
  }
  return `${bytes} B`
}

/** 将数据库中的状态字符串解析为 DownloadStatus，非法值回退为 pending */
export function parseDownloadStatus(raw: string): DownloadStatus {
  if (raw === 'running' || raw === 'paused' || raw === 'done' || raw === 'failed' ||
    raw === 'deleted' || raw === 'queued') {
    return raw
  }
  return 'pending'
}
