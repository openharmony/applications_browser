// HistoryManager：管理浏览历史记录与查询能力。

import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';

// 历史记录数据结构
export interface HistoryItem {
  id?: number;
  url: string;
  title: string;
  visitTime: number;
  visitCount?: number;
}

export class HistoryManager {
  private static instance: HistoryManager;
  private rdbStore: relationalStore.RdbStore | null = null;
  private readonly DB_NAME = 'browser_history.db';
  private readonly TABLE_NAME = 'history';
  private isInitialized = false;
  private initPromise: Promise<void> | null = null;
  private mutationTail: Promise<void> = Promise.resolve();

  private constructor() {}

  // 单例模式
  static getInstance(): HistoryManager {
    if (!HistoryManager.instance) {
      HistoryManager.instance = new HistoryManager();
    }
    return HistoryManager.instance;
  }

  // 初始化数据库 - 使用ArkData关系型数据库
  async init(context: object): Promise<void> {
    if (this.isInitialized && this.rdbStore) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.initInternal(context)
      .then((): void => {
        this.isInitialized = true;
        console.log('HistoryManager 初始化成功（使用ArkData数据库）');
      })
      .finally((): void => {
        this.initPromise = null;
      });
    return this.initPromise;
  }

  private async initInternal(context: object): Promise<void> {
    try {
      // 创建数据库配置
      const config: relationalStore.StoreConfig = {
        name: this.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };

      // 获取RdbStore实例 - 使用类型断言处理上下文
      this.rdbStore = await new Promise((resolve, reject) => {
        const onStoreReady = (err: BusinessError | null, store: relationalStore.RdbStore | null): void => {
          if (err || !store) {
            reject(err || new Error('Failed to get rdb store'));
          } else {
            resolve(store);
          }
        };
        relationalStore.getRdbStore(context as never, config, onStoreReady);
      });

      // 创建历史记录表
      await this.createTable();
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to initialize database: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 创建历史记录表
  private async createTable(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }

    const createTableSql = `
      CREATE TABLE IF NOT EXISTS ${this.TABLE_NAME} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        visitTime INTEGER NOT NULL,
        visitCount INTEGER DEFAULT 1
      );
    `;

    try {
      await this.rdbStore.executeSql(createTableSql);
      await this.createIndexes();
      console.log('历史记录表创建成功');
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create table: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  private async createIndexes(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized');
    }
    try {
      const visitTimeIndexSql =
        `CREATE INDEX IF NOT EXISTS idx_history_visit_time ON ${this.TABLE_NAME}(visitTime DESC);`;
      await this.rdbStore.executeSql(visitTimeIndexSql);
      await this.rdbStore.executeSql(`CREATE INDEX IF NOT EXISTS idx_history_title ON ${this.TABLE_NAME}(title);`);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to create history indexes: ${errorMessage}`);
    }
  }

  // 添加或更新历史记录
  async addHistory(item: HistoryItem): Promise<number> {
    const operation = this.mutationTail.then(
      () => this.addHistoryInternal(item),
      () => this.addHistoryInternal(item),
    );
    this.mutationTail = operation.then(() => undefined, () => undefined);
    return operation;
  }

  private async addHistoryInternal(item: HistoryItem): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      // 检查是否已存在该URL
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('url', item.url);
      let resultSet: relationalStore.ResultSet | null = null;
      let id: number = -1;
      try {
        resultSet = await this.rdbStore.query(predicates, ['id', 'visitCount']);

        if (resultSet.goToFirstRow()) {
          // 更新现有记录
          const existingId = resultSet.getLong(resultSet.getColumnIndex('id'));
          const existingCount = resultSet.getLong(resultSet.getColumnIndex('visitCount'));
          const updateValues: relationalStore.ValuesBucket = {
            title: item.title,
            visitTime: item.visitTime,
            visitCount: existingCount + 1
          };
          const updatePredicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
          updatePredicates.equalTo('id', existingId);
          await this.rdbStore.update(updateValues, updatePredicates);
          id = existingId;
        } else {
          // 插入新记录
          const valuesBucket: relationalStore.ValuesBucket = {
            url: item.url,
            title: item.title,
            visitTime: item.visitTime,
            visitCount: 1
          };
          const insertResult = await this.rdbStore.insert(this.TABLE_NAME, valuesBucket);
          id = insertResult as number;
        }
      } finally {
        if (resultSet) {
          this.closeResultSetSafely(resultSet);
        }
      }

      return id;
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to add history: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 根据ID删除历史记录
  async deleteHistoryById(id: number): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('id', id);
      await this.rdbStore.delete(predicates);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete history by id: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 根据URL删除历史记录
  async deleteHistoryByUrl(url: string): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('url', url);
      await this.rdbStore.delete(predicates);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to delete history by url: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 清空所有历史记录
  // 串接在 mutationTail 之后：与挂起的 addHistory 变更保持串行，避免 DELETE
  // 执行后仍有排队中的 addHistory 把记录插回（“清完又回来”竞态）。
  async clearAllHistory(): Promise<void> {
    const operation = this.mutationTail.then(
      () => this.clearAllHistoryInternal(),
      () => this.clearAllHistoryInternal(),
    );
    this.mutationTail = operation.then(() => undefined, () => undefined);
    return operation;
  }

  private async clearAllHistoryInternal(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      await this.rdbStore.executeSql(`DELETE FROM ${this.TABLE_NAME}`);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to clear all history: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 查询所有历史记录（按访问时间倒序）
  async queryAllHistory(): Promise<HistoryItem[]> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.orderByDesc('visitTime');
      const resultSet = await this.rdbStore.query(predicates);
      return this.resultSetToHistoryItems(resultSet);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to query all history: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 根据URL查询历史记录
  async queryHistoryByUrl(url: string): Promise<HistoryItem | null> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.equalTo('url', url);
      const resultSet = await this.rdbStore.query(predicates);
      const items = this.resultSetToHistoryItems(resultSet);
      return items.length > 0 ? items[0] : null;
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to query history by url: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 根据关键词搜索历史记录
  async searchHistory(keyword: string, limit?: number): Promise<HistoryItem[]> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      const normalizedKeyword = keyword.trim();
      if (normalizedKeyword.length === 0) {
        return [];
      }
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.beginWrap();
      predicates.like('url', `%${this.escapeLikeKeyword(normalizedKeyword)}%`);
      predicates.or();
      predicates.like('title', `%${this.escapeLikeKeyword(normalizedKeyword)}%`);
      predicates.endWrap();
      predicates.orderByDesc('visitTime');
      this.applyLimit(predicates, limit);
      const resultSet = await this.rdbStore.query(predicates);
      return this.resultSetToHistoryItems(resultSet);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to search history: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 获取最近的历史记录（限制数量）
  async getRecentHistory(limit: number = 20): Promise<HistoryItem[]> {
    if (!this.rdbStore) {
      throw new Error('RdbStore is not initialized. Call init() first.');
    }

    try {
      const predicates = new relationalStore.RdbPredicates(this.TABLE_NAME);
      predicates.orderByDesc('visitTime');
      this.applyLimit(predicates, limit);
      const resultSet = await this.rdbStore.query(predicates);
      return this.resultSetToHistoryItems(resultSet);
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to get recent history: ${errorMessage}`);
      throw new Error(errorMessage);
    }
  }

  // 将ResultSet转换为HistoryItem数组
  private resultSetToHistoryItems(resultSet: relationalStore.ResultSet): HistoryItem[] {
    const items: HistoryItem[] = [];

    try {
      const rowCount = resultSet.rowCount;
      if (rowCount > 0) {
        resultSet.goToFirstRow();
        do {
          const id = resultSet.getLong(resultSet.getColumnIndex('id'));
          const url = resultSet.getString(resultSet.getColumnIndex('url'));
          const title = resultSet.getString(resultSet.getColumnIndex('title'));
          const visitTime = resultSet.getLong(resultSet.getColumnIndex('visitTime'));
          const visitCount = resultSet.getLong(resultSet.getColumnIndex('visitCount'));

          items.push({
            id,
            url,
            title,
            visitTime,
            visitCount
          });
        } while (resultSet.goToNextRow());
      }
    } catch (error) {
      const errorMessage = (error as BusinessError).message || 'Unknown error';
      console.error(`Failed to convert resultSet: ${errorMessage}`);
      throw new Error(errorMessage);
    } finally {
      this.closeResultSetSafely(resultSet);
    }

    return items;
  }

  private closeResultSetSafely(resultSet: relationalStore.ResultSet): void {
    try {
      resultSet.close();
    } catch (_) {
    }
  }

  private applyLimit(predicates: relationalStore.RdbPredicates, limit?: number): void {
    if (limit === undefined || limit <= 0) {
      return;
    }
    predicates.limitAs(Math.floor(limit));
  }

  private escapeLikeKeyword(keyword: string): string {
    return keyword.replace(/[%_]/g, '');
  }

}
