
import { AppMode, DebugGate } from '../../core/debugGate';
import { AppRoute, AppRouter } from '../../core/appRouter';
import { DevLauncherActionExecutor } from '../../core/devLauncherActionExecutor';
import { DevLauncherCategory, DevLauncherEntry, DevLauncherRiskLevel } from '../../core/devLauncherTypes';

import { DEV_LAUNCHER_ENTRIES } from './devLauncherEntries';

import { JSBridgePolicyManager, JSBridgePolicyMode } from '../../runtime/jsBridgePolicyManager';

@Component
export struct DevLauncherPage {
  @Link route: AppRoute;
  @Link pendingUrl: string;
  @State private filterText: string = '';
  @State private operationMessage: string = '';

  private readonly debugGate: DebugGate = DebugGate.getInstance();
  private readonly actionExecutor: DevLauncherActionExecutor = new DevLauncherActionExecutor();
  private readonly categories: DevLauncherCategory[] = ['page', 'site', 'bookmark', 'toggle', 'diagnostic', 'danger'];

  private async handleEntryClick(entry: DevLauncherEntry): Promise<void> {
    try {
      const result = await this.actionExecutor.execute(entry);
      if (result.nextPendingUrl !== undefined) {
        this.pendingUrl = result.nextPendingUrl;
      }
      if (result.nextRoute !== undefined) {
        this.route = result.nextRoute;
      }
      this.operationMessage = result.statusMessage ?? '';
    } catch (error) {
      const err = error as Error;
      this.operationMessage = err.message ? `执行失败：${err.message}` : '执行失败';
    }
  }

  private getAppModeText(): string {
    const mode = this.debugGate.getAppMode();
    if (mode === 'dev') return 'DEV';
    if (mode === 'internal') return 'INTERNAL';
    return 'PROD';
  }

  private getJsBridgeModeText(): string {
    const mode = JSBridgePolicyManager.getInstance().getMode();
    if (mode === JSBridgePolicyMode.OpenAll) return 'OpenAll';
    if (mode === JSBridgePolicyMode.Allowlist) return 'Allowlist';
    return 'InternalOnly';
  }

  private getCategoryTitle(category: DevLauncherCategory): string {
    if (category === 'page') return '页面入口';
    if (category === 'site') return '站点入口';
    if (category === 'bookmark') return '书签调试';
    if (category === 'toggle') return '能力开关';
    if (category === 'diagnostic') return '诊断工具';
    return '高风险操作';
  }

  private getRiskLabel(riskLevel: DevLauncherRiskLevel): string {
    if (riskLevel === 'high') return '高风险';
    if (riskLevel === 'medium') return '中风险';
    return '低风险';
  }

  private getRiskColor(riskLevel: DevLauncherRiskLevel): string {
    if (riskLevel === 'high') return '#dc2626';
    if (riskLevel === 'medium') return '#d97706';
    return '#2563eb';
  }

  private isEntryVisible(entry: DevLauncherEntry): boolean {
    const visibleModes = entry.visibleInModes;
    if (!visibleModes || visibleModes.length === 0) {
      return true;
    }

    const mode: AppMode = this.debugGate.getAppMode();
    return visibleModes.includes(mode);
  }

  private matchesFilter(entry: DevLauncherEntry): boolean {
    const keyword = this.filterText.trim().toLowerCase();
    if (!keyword) {
      return true;
    }

    const title = entry.title.toLowerCase();
    const subtitle = entry.subtitle ? entry.subtitle.toLowerCase() : '';
    const value = String(entry.value).toLowerCase();
    return title.includes(keyword) || subtitle.includes(keyword) || value.includes(keyword);
  }

  private getEntriesByCategory(category: DevLauncherCategory): DevLauncherEntry[] {
    const pinned: DevLauncherEntry[] = [];
    const normal: DevLauncherEntry[] = [];

    DEV_LAUNCHER_ENTRIES.forEach((entry: DevLauncherEntry) => {
      if (entry.category !== category) {
        return;
      }
      if (!this.isEntryVisible(entry) || !this.matchesFilter(entry)) {
        return;
      }

      if (entry.pinned) {
        pinned.push(entry);
      } else {
        normal.push(entry);
      }
    });

    const result: DevLauncherEntry[] = [];
    pinned.forEach(item => result.push(item));
    normal.forEach(item => result.push(item));
    return result;
  }

  @Builder
  private InfoChip(label: string, value: string) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#6b7280');

      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1f2937');
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#f3f4f6')
    .borderRadius(12);
  }

  @Builder
  private EntryCard(entry: DevLauncherEntry) {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(entry.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827');

          Text(this.getRiskLabel(entry.riskLevel))
            .fontSize(10)
            .fontColor(this.getRiskColor(entry.riskLevel))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#ffffff')
            .borderRadius(8)
            .border({ width: 1, color: this.getRiskColor(entry.riskLevel) + '33' });

          if (entry.pinned) {
            Text('常用')
              .fontSize(10)
              .fontColor('#2563eb');
          }
        }

        if (entry.subtitle) {
          Text(entry.subtitle)
            .fontSize(12)
            .fontColor('#6b7280');
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Text('打开')
        .fontSize(12)
        .fontColor('#2563eb');
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .border({ width: 1, color: '#e5e7eb' })
    .onClick(() => this.handleEntryClick(entry));
  }

  @Builder
  private CategorySection(category: DevLauncherCategory) {
    if (this.getEntriesByCategory(category).length > 0) {
      Column({ space: 10 }) {
        Text(this.getCategoryTitle(category))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#374151');

        Column({ space: 10 }) {
          ForEach(this.getEntriesByCategory(category), (entry: DevLauncherEntry) => {
            this.EntryCard(entry);
          }, (entry: DevLauncherEntry) => entry.id);
        }
      }
      .width('100%');
    }
  }



  build() {
    Column() {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Button('返回')
            .onClick(() => (this.route = AppRouter.Browser));
          Text('开发调试入口')
            .fontSize(20)
            .fontWeight(FontWeight.Medium);
        }
        .width('100%');

        Row({ space: 8 }) {
          this.InfoChip('模式', this.getAppModeText());
          this.InfoChip('JSBridge', this.getJsBridgeModeText());
          this.InfoChip('入口数', `${DEV_LAUNCHER_ENTRIES.length}`);
        }
        .width('100%');

        TextInput({ text: this.filterText, placeholder: '搜索调试项标题、描述或地址' })
          .fontSize(14)
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .border({ width: 1, color: '#e5e7eb' })
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.filterText = value;
          });

        if (this.operationMessage.trim().length > 0) {
          Text(this.operationMessage)
            .width('100%')
            .fontSize(12)
            .fontColor('#1f2937')
            .padding(12)
            .backgroundColor('#e0f2fe')
            .borderRadius(12);
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })
      .backgroundColor('#f8fafc');

      Scroll() {
        Column({ space: 18 }) {
          ForEach(this.categories, (category: DevLauncherCategory) => {
            this.CategorySection(category);
          }, (category: DevLauncherCategory) => category);
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 24 });
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%');
    }
    .backgroundColor('#f3f4f6')
    .width('100%')
    .height('100%');
  }
}
