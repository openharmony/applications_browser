# 浏览器（Browser）

## 简介

**浏览器**（包名：`com.ohos.browser`）是 OpenHarmony 中预置的 **系统应用**，基于 ArkUI 与 ArkWeb 构建，提供主页导航、多标签浏览、书签与历史、下载管理、设置与隐私、系统交互等能力，并适配手机、平板等设备形态。

本应用为系统预置应用，用户可从桌面图标进入；其他应用也可通过 `http` / `https` 的 `viewData` Want 拉起浏览器打开网页。应用窗口、系统栏等与 **SceneBoard** 协同。

### 核心能力

**网页浏览**
- 基于 ArkWeb（`WebviewController` + 下载委托）加载 HTTPS/HTTP 页面。
- 支持前进、后退、刷新、SSL 证书处理、文本 / 链接 / 图片上下文菜单、图片预览与保存。
- 支持边缘手势返回、页签缩略图快照。

**多标签与导航**
- 支持首页（`MainPage`）、页签管理（`TabsPage`）、浏览页（`BrowsePage`）三页路由。
- 通过 `TabManager` / `BrowserNavigation` 完成标签创建、关闭、恢复与跳转；启动时可恢复上次活跃标签。

**书签、历史与下载**
- 提供书签树形管理、历史按日期分组、下载任务队列与进度展示。
- 下载文件保存到系统 Download 目录，重名自动追加 `(1)`、`(2)`… 后缀；图片可写入系统相册。

**设置与隐私**
- 支持搜索引擎切换、站点权限、无痕模式（不落历史 / 书签 / 下载列表，退出时清理 Web 数据）。
- 支持深色 / 浅色主题，与系统配色、字号联动。

**系统交互**
- 通过 `BrowserWindowService` 与 SceneBoard / Window 协同，处理沉浸式系统栏、安全区、方向与前后台补钉。
- 支持外部 Want 打开网页、下载通知拉起、扫码服务依赖等系统能力桥接。

**事件与调用关系**：
1. 桌面或其它应用按 bundleName `com.ohos.browser` 拉起 `MainAbility`（桌面入口或 `http`/`https` Want）。
2. `MainAbility` 绑定上下文、初始化窗口与主题，加载 `MainPage`；延迟初始化 WebEngine，避免阻塞首帧。
3. 业务经 `BrowserStore` 门面委托 `TabManager` / `DownloadManager` 等服务，数据由 `common` 层 Repository 写入 `browser.db`。
4. 窗口与系统栏状态通过 `BrowserWindowService` 与 SceneBoard 协同，前后台切换时补齐 SystemUI 状态。

> 例如，一次典型的外链打开流程：
> - 其它应用以 `viewData` + `https` URI 拉起 `MainAbility`；
> - `MainAbility.captureExternalBrowseWant` 解析 URL 并交给 `BrowserNavigation` 排队；
> - 初始化完成后进入 `BrowsePage`，由 ArkWeb 加载目标页面。

## 架构说明

浏览器采用分层与模块化设计，按产品形态、业务特性与公共能力组织代码，并与 SceneBoard 等系统能力协同，如图：
![架构说明](./docs/figures/Browser.png)

### 应用层分层设计

整体可划分为产品层、特性层、公共层：

| 层次 | 主要目录 / 组件 | 说明 |
|------| -------------- |------|
| 产品层 | `product/entry` | 支持手机、平板等形态入口；Ability、页面壳、权限与资源 |
| 特性层 | `feature/browser_core`、`feature/home`、`feature/tab`、`feature/web`、`feature/bookmark`、`feature/download`、`feature/settings`、`feature/security`、`feature/commons` | 网页浏览、多标签导航、书签历史下载、设置隐私、系统交互 |
| 公共层 | `common` | 数据模型、RDB 持久化、路由桥、日志与通用工具 |

**特性层模块说明**：

| 核心能力 | 模块 | 说明 |
|--------|------|------|
| 网页浏览 | BrowsePageView, WebPageController, WebBrowseViewModel | ArkWeb 加载、上下文菜单、错误页、图片预览 |
| 多标签导航 | TabsPageView, TabManager, BrowserNavigation, NavigationController | 标签 CRUD、页间路由、前进后退栈 |
| 书签历史下载 | FeaturePanel, BookmarkRepository, HistoryRepository, DownloadManager | 书签 / 历史面板、下载确认与任务队列 |
| 设置与隐私 | ProfileView, SettingsStore, SslHandler, IncognitoPolicy | 管理页、主题字号、SSL、无痕策略 |
| 系统交互 | BrowserWindowService, MainAbility Want, ScanQrService | SceneBoard / 系统栏协同、外链拉起、扫码等 |

### 与其他应用的关系

| 项目 | 说明 |
|------|------|
| 是否允许其他应用调用 | 允许。MainAbility 声明 `exported=true`，外部应用可通过 Want 拉起 |
| 谁能调用 | 桌面 / SceneBoard 通过 home skill 拉起；其它应用可通过 `entity.system.browsable` + `http`/`https` URI 拉起 |
| 什么时候能调用 | 应用安装后即可调用；访问定位 / 相机 / 麦克风等站点能力时需用户授权 |
| 支持的 Want 参数 | 桌面入口：`ohos.want.action.home`；外链浏览：`ohos.want.action.viewData`，`uri` 为待打开的 `http`/`https` 地址 |
| 与 SceneBoard 的关系 | 依赖 SceneBoard 承接桌面入口与窗口场景；`BrowserWindowService` 在前后台切换时与 SceneBoard / SystemUI 协同系统栏与安全区 |
| 跨进程依赖 | 扫码依赖 `com.ohos.scanservice`（`module.json5` dependencies）；网页渲染依赖 ArkWeb |

## 编译构建

本工程为多模块 HAP 应用工程，使用 Hvigor 构建，产物为 `com.ohos.browser` 系统应用包。

### 环境要求
- OpenHarmony SDK（本工程 `compileSdkVersion` / `compatibleSdkVersion` / `targetSdkVersion` 均为 23）
- DevEco Studio 或命令行 Hvigor 工具链
- 系统签名证书（见 `signature/`）

### 编译命令

在工程根目录执行：

```bash
# 使用 DevEco Studio 打开工程后执行 Build，或使用 hvigor 命令行
hvigorw assembleHap
```

## 浏览器开发

浏览器采用 **ArkTS** 语言开发，UI 基于 ArkUI Stage 模型。应用通过 `MainAbility` 承载主界面，通过 `feature/*` 完成浏览业务，并通过 `common` 保持模型与数据库一致。开发可参考：[ArkUI 开发概述](https://gitcode.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/arkts-ui-development-overview.md)、[ArkWeb 开发指南](https://gitcode.com/openharmony/docs/tree/master/zh-cn/application-dev/web)。

### 基于已有模块的开发

适用场景：对已有能力做功能定制，例如调整首页快捷方式、扩展下载确认流、修改系统栏协同、裁剪某 Feature 等。

**对已有模块的功能修改与裁剪**

1. 明确改动点：按业务边界定位到 `product/entry`（入口与页面壳）、`feature/web`（浏览 UI）、`feature/browser_core`（门面与服务）、`feature/bookmark` / `download`（书签下载）或 `common`（公共能力）。
2. 修改浏览链路：
   - 页面壳位于 `product/entry/src/main/ets/pages/BrowsePage.ets`
   - 浏览 UI 位于 `feature/web/src/main/ets/BrowsePageView.ets`
   - Web 控制位于 `feature/browser_core/src/main/ets/web/WebPageController.ets`

    例如，入口 Ability 在窗口创建时加载主页面并延迟初始化 WebEngine：
    ```typescript
    // MainAbility.ets — onWindowStageCreate 是主窗口入口
    onWindowStageCreate(windowStage: window.WindowStage): void {
      BrowserWindowService.getInstance().attachStage(windowStage, this.context);
      windowStage.loadContent('pages/MainPage', (err) => {
        if (err.code) {
          return;
        }
        BrowserWindowService.getInstance().onContentLoaded();
        setTimeout(() => {
          webview.WebviewController.initializeWebEngine();
          webview.WebviewController.enableWholeWebPageDrawing();
        }, 0);
      });
    }
    ```
3. 修改标签 / 路由：
   - 标签管理位于 `feature/browser_core/src/main/ets/tab/TabManager.ets`
   - 页面跳转位于 `feature/browser_core/src/main/ets/BrowserNavigation.ets`
4. 修改系统交互 / SceneBoard 协同：
   - 窗口与系统栏位于 `feature/browser_core/src/main/ets/settings/BrowserWindowService.ets`
   - 外链 Want 解析位于 `product/entry/src/main/ets/MainAbility/MainAbility.ets`
5. 修改 UI 组件：
   - 首页、浏览、书签等 UI 位于对应 `feature/*/src/main/ets/`
   - 通用对话框、Toast 等位于 `feature/commons/`

常用修改入口：

| 目标 | 路径 |
|------|------|
| 应用入口 Ability | `product/entry/src/main/ets/MainAbility/MainAbility.ets` |
| 首页 / 管理页壳 | `product/entry/src/main/ets/pages/MainPage.ets` |
| 浏览页 | `feature/web/src/main/ets/BrowsePageView.ets` |
| UI 门面 | `feature/browser_core/src/main/ets/BrowserStore.ets` |
| 窗口 / SceneBoard 协同 | `feature/browser_core/src/main/ets/settings/BrowserWindowService.ets` |
| 模型与 RDB | `common/src/main/ets/model/`、`common/src/main/ets/repository/` |

### 新特性能力的开发

适用场景：新增浏览相关能力、扩展全屏路由页、补充系统交互或适配新设备形态。

> **说明**：当前工程采用 `product + feature + common` 多模块结构，产品入口主要在 `product/entry`。新能力一般按现有分层扩展；若新增产品形态 HAP，可在 `product/` 下增加对应目录并在 `build-profile.json5` 中注册。

**步骤1：扩展业务能力（最常见）**

1. 在对应 `feature/` HAR 中补充页面、ViewModel 或服务逻辑。
2. 如涉及持久化，在 `common` 中扩展 model + Repository。
3. 如涉及跨页面调用，在 `BrowserStore` 增加薄封装 API。
4. 在 `build-profile.json5` 与 `product/entry/oh-package.json5` 中注册 / 声明依赖。

**步骤2：配置 / 确认 Ability 入口**

本工程入口已在 `product/entry/src/main/module.json5` 中声明，扩展能力时通常只需确认权限、Ability、skills 与跨应用依赖是否满足新场景：

```json
{
  "module": {
    "name": "entry",
    "type": "entry",
    "mainElement": "MainAbility",
    "deviceTypes": [
      "default"
    ],
    "abilities": [
      {
        "name": "MainAbility",
        "srcEntry": "./ets/MainAbility/MainAbility.ets",
        "exported": true
      }
    ]
  }
}
```

**步骤3：定制 UI**

在完成业务能力与 Ability 配置后，按上一节对「已有模块的功能修改与裁剪」中的 UI 组件修改方式扩展首页、浏览页、标签页或面板即可。

若需新增独立页面：
1. 在对应模块 `pages/` 或 Feature 下新增页面文件；
2. 如需系统路由注册，在 `resources/base/profile/main_pages.json` 中声明；
3. 由 `BrowserNavigation` 或 Want 路由拉起。

## 目录
```text
applications_browser
├─AppScope                              # 应用级配置与多语言资源
│  ├─app.json5                          # bundleName、版本号等
│  └─resources/                         # 全局字符串 / 图标等资源
├─common                                # 公共能力层
│  └─src/main/ets/
│     ├─model/                          # 公共数据模型与常量
│     ├─repository/                     # RDB 访问与 BrowserDatabase
│     └─utils/                          # 日志、路由桥、通用工具
├─feature                               # 特性层
│  ├─browser_core/                      # 门面、标签、下载、Web、窗口等核心服务
│  ├─commons/                           # 通用 UI 组件
│  ├─home/                              # 首页 / 搜索 / 快捷方式
│  ├─tab/                               # 标签管理 UI
│  ├─web/                               # 浏览页 UI
│  ├─bookmark/                          # 书签 / 历史 / FeaturePanel
│  ├─download/                          # 下载 UI
│  ├─settings/                          # 管理页
│  └─security/                          # 安全隐私 UI
├─product                               # 产品层
│  └─entry/                             # 入口 HAP
│     └─src/main/ets/
│        ├─MainAbility/                 # 主 Ability、备份扩展
│        └─pages/                       # MainPage / BrowsePage / TabsPage
├─docs/figures/                         # 架构示意图
├─lib/                                  # 本地 HAR
├─hvigor                                # 构建工具配置
├─signature                             # 签名证书与 profile
├─build-profile.json5                   # 工程级 SDK / 签名 / product 配置
├─oh-package.json5
├─README.md                             # 中文说明文档
└─README_en.md                          # 英文说明文档
```

## 约束
- **语言版本**：ArkTS
- **运行形态**：系统预置应用（`com.ohos.browser`），依赖 ArkWeb、网络、文件、媒体库、SceneBoard / 窗口等系统能力
- **设备类型**：入口模块 `deviceTypes` 为 `default`；各 Feature HAR 声明 `default`、`tablet`
- **权限**：浏览器所需的主要权限如下（见 `product/entry/src/main/module.json5`）

  | 权限 | 授权方式 | 使用场景 |
  |------|---------|--------|
  | ohos.permission.INTERNET | 系统授权 | 网页访问 |
  | ohos.permission.GET_NETWORK_INFO | 系统授权 | 网络状态感知（如下载） |
  | ohos.permission.WRITE_IMAGEVIDEO | 用户授权 | 图片保存到相册 |
  | ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY | 用户授权 | 下载文件写入系统 Download 目录 |
  | ohos.permission.APPROXIMATELY_LOCATION / LOCATION | 用户授权 | 站点定位权限 |
  | ohos.permission.CAMERA | 用户授权 | 站点相机权限 |
  | ohos.permission.MICROPHONE | 用户授权 | 站点麦克风权限 |

- **系统协同**：窗口与系统栏行为依赖 SceneBoard / SystemUI；修改 `BrowserWindowService` 时需验证冷启动、回前台、多任务切换等场景

## 参与贡献

欢迎广大开发者贡献代码、文档等，具体的贡献流程和方式请参见[参与贡献](https://gitcode.com/openharmony/docs/blob/master/zh-cn/contribute/%E5%8F%82%E4%B8%8E%E8%B4%A1%E7%8C%AE.md)。
