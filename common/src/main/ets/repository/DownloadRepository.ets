import { relationalStore } from '@kit.ArkData'
import { BrowserDatabase } from './BrowserDatabase'
import { DownloadTask, createDownloadTask, CreateDownloadTaskInput, parseDownloadStatus } from '../model/DownloadTask'

/** 下载任务元数据持久化，对应 download_tasks 表 */
export class DownloadRepository {
  private static instance: DownloadRepository | null = null

  /** 获取下载任务仓库单例实例 */
  static getInstance(): DownloadRepository {
    if (DownloadRepository.instance === null) {
      DownloadRepository.instance = new DownloadRepository()
    }
    return DownloadRepository.instance
  }

  /** 不再写入示例下载；清理历史版本遗留的测试任务 */
  async seedDefaultsIfEmpty(): Promise<void> {
    await this.removeLegacySeedDownloads()
  }

  /** 删除旧版内置示例下载（d1–d4） */
  async removeLegacySeedDownloads(): Promise<void> {
    const legacyIds = ['d1', 'd2', 'd3', 'd4']
    for (let i = 0; i < legacyIds.length; i++) {
      await this.deleteById(legacyIds[i])
    }
  }

  /** 查询全部下载任务并按创建时间降序返回 */
  async findAll(): Promise<DownloadTask[]> {
    const store = BrowserDatabase.getInstance().getStore()
    const rs = await store.querySql('SELECT * FROM download_tasks ORDER BY created_at DESC')
    const list: DownloadTask[] = []
    try {
      while (rs.goToNextRow()) {
        list.push(this.rowToTask(rs))
      }
    } finally {
      rs.close()
    }
    return list
  }

  /** 插入或更新下载任务记录 */
  async upsert(task: DownloadTask): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    task.updatedAt = Date.now()
    const bucket: relationalStore.ValuesBucket = {
      id: task.id,
      file_name: task.fileName,
      source_url: task.sourceUrl,
      local_path: task.localPath || null,
      gallery_uri: task.galleryUri || null,
      status: task.status,
      progress: task.progress,
      file_size: task.fileSize,
      mime_type: task.mimeType || null,
      error_message: task.errorMessage || null,
      created_at: task.createdAt,
      updated_at: task.updatedAt
    }
    const existing = await this.findById(task.id)
    if (existing) {
      const predicates = new relationalStore.RdbPredicates('download_tasks')
      predicates.equalTo('id', task.id)
      await store.update(bucket, predicates)
    } else {
      await store.insert('download_tasks', bucket)
    }
  }

  /** 按 ID 删除下载任务 */
  async deleteById(id: string): Promise<void> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('download_tasks')
    predicates.equalTo('id', id)
    await store.delete(predicates)
  }

  /** 按 ID 查询下载任务，不存在则返回 null */
  async findById(id: string): Promise<DownloadTask | null> {
    const store = BrowserDatabase.getInstance().getStore()
    const predicates = new relationalStore.RdbPredicates('download_tasks')
    predicates.equalTo('id', id)
    const rs = await store.query(predicates)
    try {
      if (rs.goToFirstRow()) {
        return this.rowToTask(rs)
      }
      return null
    } finally {
      rs.close()
    }
  }

  /** 将查询结果行映射为下载任务模型 */
  private rowToTask(rs: relationalStore.ResultSet): DownloadTask {
    const taskInput: CreateDownloadTaskInput = {
      id: rs.getString(rs.getColumnIndex('id')),
      fileName: rs.getString(rs.getColumnIndex('file_name')),
      sourceUrl: rs.getString(rs.getColumnIndex('source_url')),
      localPath: rs.getString(rs.getColumnIndex('local_path')) ?? '',
      galleryUri: this.readOptionalString(rs, 'gallery_uri'),
      status: parseDownloadStatus(rs.getString(rs.getColumnIndex('status'))),
      progress: rs.getLong(rs.getColumnIndex('progress')),
      fileSize: rs.getLong(rs.getColumnIndex('file_size')),
      mimeType: rs.getString(rs.getColumnIndex('mime_type')) ?? '',
      errorMessage: rs.getString(rs.getColumnIndex('error_message')) ?? '',
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
    }
    return createDownloadTask(taskInput)
  }

  /** 读取可选列（旧库无该列时返回空串） */
  private readOptionalString(rs: relationalStore.ResultSet, column: string): string {
    try {
      const idx = rs.getColumnIndex(column)
      if (idx < 0) {
        return ''
      }
      return rs.getString(idx) ?? ''
    } catch (_err) {
      return ''
    }
  }
}
