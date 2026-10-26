import { SettingsShellPage } from '../ui/pages/SettingsShellPage';
import { WindowManager } from '../core/windowManager';

@Entry
@Component
struct ClearDataWindow {
  private windowManager: WindowManager = WindowManager.getInstance();

  build() {
    Stack() {
      SettingsShellPage({
        initialSectionId: 'clear-data',
        onBack: () => {
          this.windowManager.close(this.getUIContext()).catch(() => {
          });
        },
      })
        .width('100%')
        .height('100%');
    }
    .width('100%')
    .height('100%');
  }
}
