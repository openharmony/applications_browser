import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';

const FOLDER_SELECTION_SYSCAP: string = 'SystemCapability.FileManagement.UserFileService.FolderSelection';

export class DownloadSettingsService {
  /**
   * 打开下载文件所在目录。
   *
   * 通过 openLink 拉起系统文件管理器并定位到目标目录（API 12+）。
   * link 使用 'filemanager://openDirectory'，目录 URI 通过
   * parameters.fileUri 传入。若设备没有匹配的文件管理器，
   * 回退到 DocumentViewPicker(MIXED) 保证功能仍然可用。
   */
  async openDirectory(context: object, directoryUri: string): Promise<void> {
    const normalizedDirectoryUri = directoryUri.trim();
    if (normalizedDirectoryUri.length === 0) {
      throw new Error('下载目录地址为空');
    }

    const uiContext = context as common.UIAbilityContext;
    const link: string = 'filemanager://openDirectory';
    const openLinkOptions: OpenLinkOptions = {
      parameters: {
        'fileUri': normalizedDirectoryUri
      }
    };

    try {
      await uiContext.openLink(link, openLinkOptions);
      return;
    } catch (_) {
      // 设备没有注册 filemanager://openDirectory 时，使用公开的文件选择器兜底。
    }

    if (!canIUse(FOLDER_SELECTION_SYSCAP)) {
      throw new Error('当前设备不支持打开下载目录');
    }

    const options = new picker.DocumentSelectOptions();
    // 2in1/PC 的文件选择器支持 MIXED，目录中的文件和子目录都会展示。
    // 该模式不会改变下载文件，只用于把系统文件选择器定位到目标目录。
    options.selectMode = picker.DocumentSelectMode.MIXED;
    options.maxSelectNumber = 1;
    options.defaultFilePathUri = normalizedDirectoryUri;
    const documentPicker = new picker.DocumentViewPicker(uiContext);
    await documentPicker.select(options);
  }

  async chooseDownloadDirectory(context: object, currentDirectoryUri: string = ''): Promise<string> {
    try {
      if (!canIUse(FOLDER_SELECTION_SYSCAP)) {
        throw new Error('当前设备不支持选择下载目录，请使用系统默认目录');
      }
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      if (currentDirectoryUri.trim().length > 0) {
        options.defaultFilePathUri = currentDirectoryUri.trim();
      }
      const documentPicker = new picker.DocumentViewPicker(context as common.UIAbilityContext);
      const uris = await documentPicker.select(options);
      return uris && uris.length > 0 ? uris[0] : '';
    } catch (error) {
      const businessError = error as BusinessError;
      throw new Error(businessError?.message ? businessError.message : '选择下载目录失败');
    }
  }

  getDirectoryDisplayName(directoryUri: string): string {
    const normalized = directoryUri.trim().replace(/\/+$/, '');
    if (!normalized) {
      return '系统默认下载目录';
    }
    const segments = normalized.split('/');
    const lastSegment = segments.length > 0 ? segments[segments.length - 1] : normalized;
    try {
      return decodeURIComponent(lastSegment) || normalized;
    } catch (_) {
      return lastSegment || normalized;
    }
  }
}
