import { common, OpenLinkOptions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';

const FOLDER_SELECTION_SYSCAP: string = 'SystemCapability.FileManagement.UserFileService.FolderSelection';

export class DownloadSettingsService {
  /** 每次网页下载都先由系统保存面板确认目标文件。 */
  async chooseDownloadFile(context: object, fileName: string, mimeType: string = ''): Promise<string> {
    const safeName = (fileName.trim() || 'download')
      .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_')
      .slice(0, 120);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [safeName];
    const suffix = this.getFileSuffixChoice(safeName, mimeType);
    if (suffix.length > 0) {
      options.fileSuffixChoices = [suffix];
    }
    const documentPicker = new picker.DocumentViewPicker(context as common.UIAbilityContext);
    const uris = await documentPicker.save(options);
    return uris && uris.length > 0 ? uris[0] : '';
  }

  /**
   * 打开下载文件所在目录。
   *
   * 优先通过标准 viewData Want 定位目录，再兼容 PC 文件管理器链接。
   * 两种系统能力都不可用时，才回退到 DocumentViewPicker(MIXED)。
   */
  async openDirectory(context: object, directoryUri: string): Promise<void> {
    const normalizedDirectoryUri = directoryUri.trim();
    if (normalizedDirectoryUri.length === 0) {
      throw new Error('下载目录地址为空');
    }

    const uiContext = context as common.UIAbilityContext;
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: normalizedDirectoryUri,
      };
      await uiContext.startAbility(want);
      return;
    } catch (_) {
      // 当前设备没有标准目录查看 Ability，继续尝试 PC 文件管理器链接。
    }

    const link: string = 'filemanager://openDirectory';
    const openLinkOptions: OpenLinkOptions = {
      parameters: {
        'fileUri': normalizedDirectoryUri,
      },
    };
    try {
      await uiContext.openLink(link, openLinkOptions);
      return;
    } catch (_) {
      // 当前设备没有目录打开链接时，才使用选择器兜底。
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

  private getFileSuffixChoice(fileName: string, mimeType: string): string {
    const suffixMatch = fileName.match(/(\.[a-z0-9]{1,8})$/i);
    if (suffixMatch && suffixMatch[1]) {
      return `文件类型|${suffixMatch[1]}`;
    }
    const normalizedMime = mimeType.trim().toLowerCase();
    if (normalizedMime === 'application/zip') {
      return '压缩包|.zip';
    }
    if (normalizedMime === 'application/pdf') {
      return 'PDF|.pdf';
    }
    return '';
  }

}
