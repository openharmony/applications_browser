import { getBrowserContext } from './BrowserContext'
import { SitePermissionId } from '../model/BrowserSettings'

/**
 * 国际化字符串统一入口（非 UI 层通过 resourceManager 解析 Resource）
 * 资源定义见 resources/base 与 resources/en_US 的 string.json
 */
export class BrowserStrings {
  /** 将 $r() 资源解析为当前语言的 plain string（不可使用 Resource.toString()） */
  static txt(res: Resource, ...args: Array<string | number>): string {
    const ctx = getBrowserContext()
    if (ctx === null) {
      return ''
    }
    try {
      const resId = res.id
      if (args.length > 0) {
        return ctx.resourceManager.getStringSync(resId, ...args)
      }
      return ctx.resourceManager.getStringSync(resId)
    } catch (_e) {
      return ''
    }
  }

  /** 获取「新标签页」文案 */
  static newTab(): string {
    return BrowserStrings.txt($r('app.string.new_tab'))
  }

  /** 获取书签根目录名称 */
  static bookmarkRoot(): string {
    return BrowserStrings.txt($r('app.string.bookmark_root'))
  }

  /** 获取「新建书签」文案 */
  static newBookmark(): string {
    return BrowserStrings.txt($r('app.string.new_bookmark'))
  }

  /** 获取「新建文件夹」文案 */
  static newFolder(): string {
    return BrowserStrings.txt($r('app.string.new_folder'))
  }

  /** 根据快捷方式 ID 获取本地化标题 */
  static shortcutTitle(id: string): string {
    switch (id) {
      case 'bookmarks':
        return BrowserStrings.txt($r('app.string.shortcut_bookmarks'))
      case 'history':
        return BrowserStrings.txt($r('app.string.shortcut_history'))
      case 'downloads':
        return BrowserStrings.txt($r('app.string.shortcut_downloads'))
      case 'baidu':
        return BrowserStrings.txt($r('app.string.shortcut_baidu'))
      case 'quark':
        return BrowserStrings.txt($r('app.string.shortcut_quark'))
      case 'bing':
        return BrowserStrings.txt($r('app.string.shortcut_bing'))
      case 'sogou':
        return BrowserStrings.txt($r('app.string.shortcut_sogou'))
      case '360':
        return BrowserStrings.txt($r('app.string.shortcut_360'))
      default:
        return id
    }
  }

  /** 根据搜索引擎 ID 获取显示名称 */
  static engineName(id: string): string {
    return BrowserStrings.shortcutTitle(id === '360' ? '360' : id)
  }

  /** 根据字体大小档位 key 获取显示标签 */
  static fontSizeLabel(key: string): string {
    switch (BrowserStrings.normalizeFontSizeKey(key)) {
      case 'system':
        return BrowserStrings.txt($r('app.string.font_size_system'))
      case 'small':
        return BrowserStrings.txt($r('app.string.font_size_small'))
      case 'large':
        return BrowserStrings.txt($r('app.string.font_size_large'))
      default:
        return BrowserStrings.txt($r('app.string.font_size_medium'))
    }
  }

  /** 归一化字体档位（未知值回退跟随系统） */
  static normalizeFontSizeKey(key: string | undefined): string {
    if (key === 'small' || key === 'medium' || key === 'large' || key === 'system') {
      return key
    }
    return 'system'
  }

  /** 返回所有字体大小档位 key 列表 */
  static fontSizeKeys(): string[] {
    return ['system', 'small', 'medium', 'large']
  }

  /** 归一化主题偏好（未知值回退浅色） */
  static normalizeThemeModeKey(key: string | undefined): string {
    if (key === 'system' || key === 'light' || key === 'dark') {
      return key
    }
    return 'light'
  }

  /** 返回所有主题偏好 key 列表 */
  static themeModeKeys(): string[] {
    return ['system', 'light', 'dark']
  }

  /** 根据主题偏好 key 获取显示标签 */
  static themeModeLabel(key: string): string {
    switch (BrowserStrings.normalizeThemeModeKey(key)) {
      case 'system':
        return BrowserStrings.txt($r('app.string.theme_mode_system'))
      case 'dark':
        return BrowserStrings.txt($r('app.string.theme_mode_dark'))
      default:
        return BrowserStrings.txt($r('app.string.theme_mode_light'))
    }
  }

  /** 根据索引获取字体大小档位 key */
  static fontSizeKeyAt(index: number): string {
    const keys = BrowserStrings.fontSizeKeys()
    return keys[index] ?? 'system'
  }

  /** 根据字体大小 key 获取 Select 组件索引 */
  static fontSizeIndex(key: string): number {
    const keys = BrowserStrings.fontSizeKeys()
    const normalized = BrowserStrings.normalizeFontSizeKey(key)
    const idx = keys.indexOf(normalized)
    return idx >= 0 ? idx : 0
  }

  /** 根据网站权限策略 key 获取显示标签（已移除询问模式，只保留允许/禁止） */
  static sitePermissionLabel(key: string): string {
    if (key === 'allow') {
      return BrowserStrings.txt($r('app.string.perm_allow'))
    }
    return BrowserStrings.txt($r('app.string.perm_deny'))
  }

  /** 返回所有网站权限策略 key 列表（已移除询问模式） */
  static sitePermissionKeys(): string[] {
    return ['allow', 'deny']
  }

  /** 根据索引获取网站权限策略 key */
  static sitePermissionKeyAt(index: number): string {
    const keys = BrowserStrings.sitePermissionKeys()
    return keys[index] ?? 'deny'
  }

  /** 根据网站权限策略 key 获取 Select 组件索引 */
  static sitePermissionIndex(key: string): number {
    const keys = BrowserStrings.sitePermissionKeys()
    const idx = keys.indexOf(key)
    return idx >= 0 ? idx : 1
  }

  /** 网站权限项显示名称 */
  static permCategoryLabel(permId: SitePermissionId): string {
    if (permId === 'location') {
      return BrowserStrings.txt($r('app.string.perm_location'))
    }
    if (permId === 'camera') {
      return BrowserStrings.txt($r('app.string.perm_camera'))
    }
    if (permId === 'microphone') {
      return BrowserStrings.txt($r('app.string.perm_microphone'))
    }
    return BrowserStrings.txt($r('app.string.perm_notification'))
  }

  /** 网站权限被禁止时的提示（引导用户到浏览器设置修改） */
  static sitePermissionDeniedToast(permId: SitePermissionId): string {
    return BrowserStrings.txt($r('app.string.perm_site_denied_fmt'), BrowserStrings.permCategoryLabel(permId))
  }

  /** 浏览器缺少应用权限、无法将网站权限设为允许时的提示 */
  static appPermissionMissingCannotAllowToast(permId: SitePermissionId): string {
    return BrowserStrings.txt($r('app.string.perm_app_missing_cannot_allow_fmt'),
      BrowserStrings.permCategoryLabel(permId))
  }

  /** 根据网页长按菜单 actionId 获取操作名称 */
  static webContextAction(actionId: string): string {
    switch (actionId) {
      case 'copy_image':
        return BrowserStrings.txt($r('app.string.copy'))
      case 'save_image':
        return BrowserStrings.txt($r('app.string.save_image'))
      case 'share_image':
        return BrowserStrings.txt($r('app.string.share_image'))
      case 'open_in_new_tab':
        return BrowserStrings.txt($r('app.string.open_in_new_tab'))
      case 'copy_link':
        return BrowserStrings.txt($r('app.string.copy_link'))
      default:
        return actionId
    }
  }

  /** 根据字体大小档位 key 获取 Web textZoomRatio（100 为默认，仅浏览器档位） */
  static fontSizeTextZoomRatio(key: string): number {
    switch (BrowserStrings.normalizeFontSizeKey(key)) {
      case 'system':
        return 100
      case 'small':
        return 85
      case 'large':
        return 115
      default:
        return 100
    }
  }

  /** 浏览器 UI 字号相对系数（跟随系统档位为 1，不再叠加浏览器倍率） */
  static fontSizeUiScale(key: string): number {
    switch (BrowserStrings.normalizeFontSizeKey(key)) {
      case 'system':
        return 1
      case 'small':
        return 0.85
      case 'large':
        return 1.15
      default:
        return 1
    }
  }

  /**
   * Web 文本缩放：
   * - 跟随系统：100% × 系统 fontSizeScale
   * - 小/中/大：固定浏览器档位（不叠加系统比例）
   */
  static computeWebTextZoomRatio(fontSizeKey: string, systemFontSizeScale: number): number {
    const key = BrowserStrings.normalizeFontSizeKey(fontSizeKey)
    if (key === 'system') {
      const sys = systemFontSizeScale > 0 ? systemFontSizeScale : 1
      return Math.max(50, Math.min(300, Math.round(100 * sys)))
    }
    const tier = BrowserStrings.fontSizeTextZoomRatio(key)
    return Math.max(50, Math.min(300, tier))
  }

  /** 根据批量操作 action 获取按钮标签 */
  static batchActionLabel(action: string): string {
    switch (action) {
      case 'delete':
        return BrowserStrings.txt($r('app.string.delete'))
      case 'select_all':
        return BrowserStrings.txt($r('app.string.select_all'))
      case 'move':
        return BrowserStrings.txt($r('app.string.move_to_label'))
      case 'edit':
        return BrowserStrings.txt($r('app.string.edit'))
      case 'more':
        return BrowserStrings.txt($r('app.string.more'))
      case 'share':
        return BrowserStrings.txt($r('app.string.share_action'))
      case 'rename':
        return BrowserStrings.txt($r('app.string.rename'))
      case 'multi_select':
        return BrowserStrings.txt($r('app.string.batch_multi_select'))
      default:
        return BrowserStrings.txt($r('app.string.more'))
    }
  }

  /** 获取「已在新标签页打开」类 Toast 文案 */
  static openedInNewTabs(count: number): string {
    if (count > 1) {
      return BrowserStrings.txt($r('app.string.opened_in_n_tabs'), count)
    }
    return BrowserStrings.txt($r('app.string.opened_in_new_tab'))
  }

  /** 获取浏览页默认标题 */
  static browsePageTitleDefault(): string {
    return BrowserStrings.txt($r('app.string.browse_page_title_default'))
  }

  /** 获取文件已存在提示文案 */
  static fileExistsMessage(fileName: string): string {
    return BrowserStrings.txt($r('app.string.file_exists_message'), fileName)
  }

  /** 获取重名文件建议保存名提示文案 */
  static renameSaveWith(suggestedName: string): string {
    return BrowserStrings.txt($r('app.string.rename_save_with'), suggestedName)
  }

  /** 获取书签数量达上限提示文案 */
  static bookmarkLimitMessage(limit: number): string {
    return BrowserStrings.txt($r('app.string.bookmark_limit_message'), limit)
  }

  /** 标签页数量达上限提示 */
  static tabLimitReached(): string {
    return BrowserStrings.txt($r('app.string.tab_limit_reached'))
  }

  /** 获取历史记录日期分组标题（月/日） */
  static historySectionDate(month: number, day: number): string {
    return BrowserStrings.txt($r('app.string.history_date_section'), month, day)
  }

  /** 获取历史记录日期分组标题（年/月/日，用于非今年） */
  static historySectionFullDate(year: number, month: number, day: number): string {
    return BrowserStrings.txt($r('app.string.history_date_section_full'), year, month, day)
  }

  /** 获取「已选 N 项」文案 */
  static selectedCount(count: number): string {
    return BrowserStrings.txt($r('app.string.selected_count'), count)
  }

  /** 获取「N 条内容」计数文案 */
  static contentCount(count: number): string {
    return BrowserStrings.txt($r('app.string.content_count'), count)
  }

  /** 获取「N 个书签」计数文案 */
  static bookmarkCount(count: number): string {
    return BrowserStrings.txt($r('app.string.bookmark_count'), count)
  }

  /** 获取「已移动到文件夹」Toast 文案 */
  static movedTo(folderLabel: string): string {
    return BrowserStrings.txt($r('app.string.moved_to'), folderLabel)
  }

  /** 获取快捷方式已添加到首页的 Toast 文案 */
  static shortcutAdded(title: string): string {
    return BrowserStrings.txt($r('app.string.shortcut_added_to_home'), title)
  }

  /** 获取「今天」日期标签 */
  static todayLabel(): string {
    return BrowserStrings.txt($r('app.string.today'))
  }

  /** 获取「昨天」日期标签 */
  static yesterdayLabel(): string {
    return BrowserStrings.txt($r('app.string.yesterday'))
  }

  /** 获取 URL 必填校验提示 */
  static urlInputRequired(): string {
    return BrowserStrings.txt($r('app.string.url_input_required'))
  }

  /** 获取 URL 格式无效提示 */
  static urlFormatInvalid(): string {
    return BrowserStrings.txt($r('app.string.url_format_invalid'))
  }

  /** 获取 URL 过长提示 */
  static urlTooLong(): string {
    return BrowserStrings.txt($r('app.string.url_too_long'))
  }

  /** 获取通用输入过长提示 */
  static inputTooLong(): string {
    return BrowserStrings.txt($r('app.string.input_too_long'))
  }

  /** 下载通知进度文案：文件名 · 百分比 */
  static downloadNotificationProgressText(fileName: string, progress: number): string {
    return BrowserStrings.txt($r('app.string.download_notification_progress_text'), fileName, progress)
  }

  /** 下载通知完成文案：文件名 · 已完成 */
  static downloadNotificationDoneText(fileName: string): string {
    return BrowserStrings.txt($r('app.string.download_notification_done_text'), fileName)
  }

  /** 下载完成 Tip：【文件名】下载已完成 */
  static downloadCompleteToast(fileName: string): string {
    return BrowserStrings.txt($r('app.string.download_complete_toast'), fileName)
  }
}
