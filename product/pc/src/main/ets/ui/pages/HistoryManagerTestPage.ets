import { HistoryManager, HistoryItem } from '../../core/historyManager';
import relationalStore from '@ohos.data.relationalStore';

const historyManager = HistoryManager.getInstance();

@Entry
@Component
export struct HistoryManagerTestPage {
  @State testResults: string[] = [];
  @State isTesting: boolean = false;
  @State manualUrl: string = '';
  @State manualTitle: string = '';
  @State searchKeyword: string = '';
  @State searchResults: HistoryItem[] = [];
  @State showSearchResults: boolean = false;
  @State deleteIdInput: string = '';

  build() {
    Column() {
      Text('HistoryManager 测试页面1')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })

      Button('运行完整测试')
        .type(ButtonType.Capsule)
        .width('100%')
        .height(40)
        .onClick(() => this.runFullTest())
        .enabled(!this.isTesting)

      Button('初始化数据库')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .margin({ top: 10 })
        .onClick(() => this.initDatabase())
        .enabled(!this.isTesting)

      Button('添加测试数据')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .margin({ top: 10 })
        .onClick(() => this.addTestData())
        .enabled(!this.isTesting)

      Divider().margin({ top: 20, bottom: 10 })

      Text('手动添加网址')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 10 })

      TextInput({
        placeholder: '输入网址 (如: https://www.example.com)',
        text: this.manualUrl
      })
        .width('100%')
        .height(40)
        .backgroundColor(0xffffff)
        .borderRadius(5)
        .margin({ bottom: 10 })
        .onChange((value: string) => {
          this.manualUrl = value;
        })

      TextInput({
        placeholder: '输入标题 (可选)',
        text: this.manualTitle
      })
        .width('100%')
        .height(40)
        .backgroundColor(0xffffff)
        .borderRadius(5)
        .margin({ bottom: 10 })
        .onChange((value: string) => {
          this.manualTitle = value;
        })

      Button('添加指定网址')
        .type(ButtonType.Capsule)
        .width('100%')
        .height(40)
        .onClick(() => this.addManualUrl())
        .enabled(!this.isTesting && this.manualUrl.trim() !== '')

      Divider().margin({ top: 20, bottom: 10 })

      Text('搜索历史记录')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 10 })

      Row({ space: 10 }) {
        TextInput({
          placeholder: '输入关键词搜索历史记录',
          text: this.searchKeyword
        })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(0xffffff)
          .borderRadius(5)
          .onChange((value: string) => {
            this.searchKeyword = value;
          })

        Button('搜索')
          .type(ButtonType.Capsule)
          .width(80)
          .height(40)
          .onClick(() => this.searchHistory())
          .enabled(!this.isTesting)
      }

      // 搜索结果显示区域
      if (this.showSearchResults) {
        Column() {
          Text(`搜索结果 (共 ${this.searchResults.length} 条)`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 10, bottom: 5 })

          if (this.searchResults.length > 0) {
            List() {
              ForEach(this.searchResults, (item: HistoryItem) => {
                ListItem() {
                  Column() {
                    Text(item.title)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                    Text(item.url)
                      .fontSize(12)
                      .opacity(0.6)
                      .margin({ top: 2 })
                    Text(`ID: ${item.id}`)
                      .fontSize(12)
                      .opacity(0.6)
                      .margin({ top: 2 })
                    Text(`访问时间: ${new Date(item.visitTime).toLocaleString()}`)
                      .fontSize(12)
                      .opacity(0.6)
                      .margin({ top: 2 })
                    if (item.visitCount) {
                      Text(`访问次数: ${item.visitCount}`)
                        .fontSize(12)
                        .opacity(0.6)
                        .margin({ top: 2 })
                    }
                    Button(`删除记录 (ID: ${item.id})`)
                      .type(ButtonType.Capsule)
                      .width('auto')
                      .height(30)
                      .fontSize(12)
                      .margin({ top: 5 })
                      .backgroundColor(0xff4444)
                      .onClick(() => this.deleteHistoryById(item.id))
                  }
                  .padding(10)
                  .backgroundColor(0xffffff)
                  .borderRadius(5)
                  .width('100%')
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
            .margin({ top: 5 })
          } else {
            Text('没有找到匹配的历史记录')
              .fontSize(14)
              .opacity(0.6)
              .margin({ top: 20 })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(0xeeeeee)
        .borderRadius(10)
        .padding(10)
        .margin({ top: 10 })
      }

      Divider().margin({ top: 20, bottom: 10 })

      Button('查询所有历史')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .margin({ top: 10 })
        .onClick(() => this.queryAllHistory())
        .enabled(!this.isTesting)

      Button('清空所有历史')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .margin({ top: 10 })
        .onClick(() => this.clearAllHistory())
        .enabled(!this.isTesting)

      Divider().margin({ top: 20, bottom: 10 })

      Text('根据ID删除历史记录')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 10 })

      Row({ space: 10 }) {
        TextInput({
          placeholder: '输入记录ID'
        })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(0xffffff)
          .borderRadius(5)
          .onChange((value: string) => {
            this.deleteIdInput = value;
          })

        Button('删除')
          .type(ButtonType.Capsule)
          .width(80)
          .height(40)
          .onClick(() => this.deleteHistoryByIdFromInput())
          .enabled(!this.isTesting && this.deleteIdInput.trim() !== '')
      }

      Divider().margin(10)

      Text('测试结果:')
        .fontWeight(FontWeight.Bold)

      Scroll() {
        Column() {
          ForEach(this.testResults, (result: string) => {
            Text(result)
              .fontSize(12)
              .margin({ bottom: 5 })
              .maxLines(3)
          })
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(0xeeeeee)
      .borderRadius(10)
      .padding(10)
      .margin({ top: 10 })
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  // 运行完整测试
  private async runFullTest() {
    this.isTesting = true;
    this.testResults = [];
    this.testResults.unshift('=== 开始运行完整测试 ===');

    try {
      // 1. 初始化数据库
      await this.initDatabase();

      // 2. 清空所有历史
      await this.clearAllHistory();

      // 3. 添加测试数据
      await this.addTestData();

      // 4. 查询所有历史
      await this.queryAllHistory();

      // 5. 测试搜索功能
      await this.testSearchHistory();

      // 6. 测试按URL查询
      await this.testQueryByUrl();

      // 7. 测试获取最近记录
      await this.testGetRecentHistory();

      this.testResults.unshift('=== 所有测试完成 ===');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 测试失败: ${errorMessage}`);
    } finally {
      this.isTesting = false;
    }
  }

  // 初始化数据库（已在EntryAbility中初始化，此处不需要重复调用）
  private async initDatabase() {
    this.testResults.unshift('🔄 初始化数据库...');
    this.testResults.unshift('✅ 数据库已在应用启动时初始化');
  }

  // 添加测试数据
  private async addTestData() {
    this.testResults.unshift('🔄 添加测试数据...');
    try {
      await historyManager.addHistory({ url: 'https://www.example.com', title: 'Example网站', visitTime: Date.now() });
      await historyManager.addHistory({ url: 'https://www.test.com', title: 'Test网站', visitTime: Date.now() + 1000 });
      await historyManager.addHistory({ url: 'https://www.google.com', title: 'Google', visitTime: Date.now() + 2000 });
      this.testResults.unshift('✅ 测试数据添加成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 添加测试数据失败: ${errorMessage}`);
    }
  }

  // 查询所有历史
  private async queryAllHistory() {
    this.testResults.unshift('🔄 查询所有历史记录...');
    try {
      const history = await historyManager.queryAllHistory();
      this.testResults.unshift(`✅ 查询到 ${history.length} 条历史记录`);
      
      if (history.length > 0) {
        history.forEach((item, index) => {
          this.testResults.unshift(`   ${index + 1}. ${item.title} (${item.url}) [ID: ${item.id}]`);
        });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 查询历史记录失败: ${errorMessage}`);
    }
  }

  // 清空所有历史
  private async clearAllHistory() {
    this.testResults.unshift('🔄 清空所有历史记录...');
    try {
      await historyManager.clearAllHistory();
      this.testResults.unshift('✅ 所有历史记录已清空');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 清空历史记录失败: ${errorMessage}`);
    }
  }

  // 测试搜索功能
  private async testSearchHistory() {
    this.testResults.unshift('🔄 测试搜索功能...');
    try {
      const results = await historyManager.searchHistory('example');
      this.testResults.unshift(`✅ 搜索到 ${results.length} 条匹配记录`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 搜索功能测试失败: ${errorMessage}`);
    }
  }

  // 测试按URL查询
  private async testQueryByUrl() {
    this.testResults.unshift('🔄 测试按URL查询...');
    try {
      const result = await historyManager.queryHistoryByUrl('https://www.example.com');
      this.testResults.unshift(result ? `✅ 找到匹配记录: ${result.title}` : '❌ 未找到匹配记录');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 按URL查询测试失败: ${errorMessage}`);
    }
  }

  // 测试获取最近记录
  private async testGetRecentHistory() {
    this.testResults.unshift('🔄 测试获取最近记录...');
    try {
      const results = await historyManager.getRecentHistory(2);
      this.testResults.unshift(`✅ 获取到 ${results.length} 条最近记录`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 获取最近记录测试失败: ${errorMessage}`);
    }
  }

  // 手动添加指定网址
  private async addManualUrl() {
    if (!this.manualUrl.trim()) {
      this.testResults.unshift('⚠️  请输入有效的网址');
      return;
    }

    this.testResults.unshift(`🔄 添加指定网址: ${this.manualUrl}...`);
    try {
      // 使用手动输入的URL和标题，如果标题为空则使用URL作为标题
      const url = this.manualUrl.trim();
      const title = this.manualTitle.trim() || url;
      
      await historyManager.addHistory({ url: url, title: title, visitTime: Date.now() });
      
      this.testResults.unshift(`✅ 成功添加网址: ${title}`);
      
      // 清空输入框
      this.manualUrl = '';
      this.manualTitle = '';
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 添加网址失败: ${errorMessage}`);
    }
  }

  // 搜索历史记录
  private async searchHistory() {
    if (!this.searchKeyword.trim()) {
      this.testResults.unshift('⚠️  请输入搜索关键词');
      return;
    }

    this.testResults.unshift(`🔄 搜索历史记录: ${this.searchKeyword}...`);
    try {
      const results = await historyManager.searchHistory(this.searchKeyword);
      this.searchResults = results;
      this.showSearchResults = true;
      
      this.testResults.unshift(`✅ 搜索完成，找到 ${results.length} 条记录`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 搜索失败: ${errorMessage}`);
    }
  }

  // 根据ID删除历史记录
  private async deleteHistoryById(id?: number) {
    if (!id) {
      this.testResults.unshift('⚠️  无效的记录ID');
      return;
    }

    this.testResults.unshift(`🔄 根据ID删除历史记录: ${id}...`);
    try {
      await historyManager.deleteHistoryById(id);
      this.testResults.unshift(`✅ 成功删除ID为 ${id} 的历史记录`);
      
      // 如果当前显示搜索结果，更新搜索结果列表
      if (this.showSearchResults) {
        const results = await historyManager.searchHistory(this.searchKeyword);
        this.searchResults = results;
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.testResults.unshift(`❌ 删除历史记录失败: ${errorMessage}`);
    }
  }

  // 从输入框中获取ID并删除历史记录
  private async deleteHistoryByIdFromInput() {
    if (!this.deleteIdInput.trim()) {
      this.testResults.unshift('⚠️  请输入有效的记录ID');
      return;
    }

    const id = parseInt(this.deleteIdInput.trim(), 10);
    if (isNaN(id)) {
      this.testResults.unshift('⚠️  请输入有效的数字ID');
      return;
    }

    await this.deleteHistoryById(id);
    // 清空输入框
    this.deleteIdInput = '';
  }
}