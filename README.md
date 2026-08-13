# 浏览器（Browser）

## 简介

**浏览器**（包名：`com.ohos.browser`）是 OpenHarmony 中预置的 **系统应用**，基于 ArkUI 与 ArkWeb 构建，提供主页导航、多标签浏览、书签与历史、下载管理、设置与隐私、系统交互等能力，并适配手机、平板等设备形态。

本应用为系统预置应用，用户可从桌面图标进入；其他应用也可通过 `http` / `https` 的 `viewData` Want 拉起浏览器打开网页。应用窗口、系统栏等与 **SceneBoard** 协同。

### 核心能力

**网页浏览**
- 基于 ArkWeb（`WebviewController` + 下载委托）加载 HTTPS/HTTP 页面。
- 支持前进、后退、刷新、文本 / 链接 / 图片上下文菜单、图片预览与保存，以及边缘手势返回、页签缩略图快照。
- **SSL 证书异常**：遇到证书错误时默认拒绝加载；用户确认后将该主机加入本地信任列表（可持久化），之后同主机访问可继续；主框架已信任时，同页子资源一并放行。这不是系统证书管理中心，不能导入/查看完整证书链，仅做「异常确认 + 按主机信任」。
- **HTTP / SOCKS 代理**：不支持。无代理设置入口，也不提供应用内代理配置 API；网络走系统默认通路。

**网页权限（业界常见的双层模型）**
- 与 Chrome / Safari 等一致：浏览器应用持有的系统权限，不等于网页自动可用；站点仍需按 **origin（站点源）** 单独判定。
- **应用层权限**：浏览器在 `module.json5` 声明并经用户授权后，才具备定位 / 相机 / 麦克风等系统能力（如 `LOCATION`、`CAMERA`、`MICROPHONE`）。
- **站点层权限**：网页通过 ArkWeb 申请时，按「全局站点策略 + 该 origin 策略」判定；可在设置中按站点允许 / 禁止。同一权限对不同网站默认相互独立。
- 无痕模式下站点敏感权限默认拒绝；会话内短时缓存决策，避免同一站点反复弹窗。

**多标签与导航**
- 支持首页（`MainPage`）、页签管理（`TabsPage`）、浏览页（`BrowsePage`）三页路由。
- 通过 `TabManager` / `BrowserNavigation` 完成标签创建、关闭、恢复与跳转；启动时可恢复上次活跃标签。

**书签、历史与下载**
- **书签**：树形结构（文件夹 + 书签），支持新增、编辑标题/URL、删除（含子节点递归删除）、移动到文件夹、新建文件夹；书签条数上限 100（不含文件夹）；本地 RDB 持久化。
- **历史**：仅记录可浏览的 `http`/`https` 地址；无痕模式不写入；同一站点同一自然日合并为一条（更新访问时间 / 标题 / 图标），跨日新增；搜索词历史最多保留 20 条。
- **下载**：任务队列与进度展示；文件保存到系统 Download 目录，重名自动追加 `(1)`、`(2)`…；图片可写入系统相册。

**设置与隐私**
- 支持搜索引擎切换、站点权限、无痕模式（不落历史 / 书签 / 下载列表，退出时清理 Web 数据）。
- 支持深色 / 浅色主题，与系统配色、字号联动。

**系统交互**
- 通过 `BrowserWindowService` 与 SceneBoard / Window 协同，支持页面沉浸式浏览。
- 支持外部 Want 打开网页、下载通知拉起、扫码服务依赖等系统能力桥接。

## 与主流浏览器能力对比

对照 Chrome / Edge / Safari 及主流手机浏览器的常见能力，结合本仓当前实现，汇总支持情况如下。  
「支持」指应用侧已落地可用；「不支持」指代码未实现、明确裁剪或仅有引擎能力尚未接产品链路。

| 能力                     | 本浏览器 | 说明 / 不支持理由                             |
|------------------------|------|----------------------------------------|
| HTTP/HTTPS 网页浏览        | 支持   | 基于 ArkWeb 加载与渲染                        |
| 前进 / 后退 / 刷新           | 支持   | 应用栈 + Web 历史协同                         |
| 多标签管理                  | 支持   | 应用内标签与路由；非 Chromium 多进程隔离              |
| 书签 / 历史                | 支持   | 本地 RDB；书签树形 CRUD（上限 100）；历史按站点/日合并   |
| 下载管理                   | 支持   | 队列、进度、系统 Download 目录、通知回跳；无 BT/限速等高级调度 |
| 无痕模式                   | 支持   | 独立分区，不落历史/书签/下载列表，退出清理 Web 数据          |
| 搜索引擎切换与跳转              | 支持   | 百度 / Bing / 搜狗 / 360；无 Google 等选项      |
| 页内查找                   | 支持   | ArkWeb 查找能力                            |
| SSL 证书异常确认             | 支持   | 默认拒绝；用户确认后按主机信任并持久化；非完整证书管理中心         |
| 站点权限（定位/相机/麦克风/通知）     | 支持   | 应用权限 + 按 origin 站点策略（双层模型，同业界主流浏览器）    |
| 图片预览 / 保存 / 分享         | 支持   | 上下文菜单与图库写入                             |
| PDF / JSON / XML / TXT 预览 | 支持   | 由 ArkWeb 内置能力预览                         |
| 扫码打开网页                 | 支持   | 依赖 `com.ohos.scanservice`              |
| 外链 Want 打开网页           | 支持   | 仅 `http` / `https`                     |
| 深色模式 / 系统字号            | 支持   | 与系统主题、字号联动                             |
| 网页内音视频播放               | 支持   | ArkWeb HTML5 媒体；页内播放与全屏                |
| HTTP / SOCKS 代理        | 不支持  | 无代理设置 UI 与应用内配置 API                    |
| 扩展 / 插件生态              | 不支持  | 无扩展框架与管理 UI；产品定位为系统基础浏览器               |
| 账号同步（书签/历史/密码上云）       | 不支持  | 仅本地存储，无账号体系                            |
| 密码管理 / 自动填充            | 不支持  | 未接入密码保险箱或 Autofill 产品能力                |
| 翻译 / 阅读模式              | 不支持  | 未接入翻译或阅读模式服务                           |
| 广告拦截 / 高级跟踪防护          | 不支持  | 无规则引擎；仅站点权限与无痕                         |
| PWA 安装 / 添加到主屏         | 不支持  | 未处理 Web App Manifest / 安装流程            |
| 开发者工具                  | 不支持  | 无 DevTools UI                          |
| 打印网页                   | 不支持  | 打印依赖打印框架，当前系统不具备                       |
| 网页视频接入播控中心（AVSession）  | 不支持  | 无 AVSession 上报；构建裁剪了 `AVInputCast`     |
| 画中画（网页视频 PiP）          | 不支持  | 仅有全屏进出钩子，无 PiP 产品链路                    |
| 服务端搜索建议（Suggest）       | 不支持  | 仅本地历史/书签匹配，未接搜索引擎 Suggest API          |
| Safe Browsing / 恶意站拦截库 | 不支持  | 未接入安全浏览服务                              |
| `file://` 等本地协议外链打开    | 不支持  | 对外 Want 与运行时校验仅接受 `http`/`https`       |
| Chromium 式多进程渲染隔离      | 不支持  | 单主进程 + 进程内 ArkWeb，标签不隔离到独立 OS 进程       |

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
| 网页浏览 | BrowsePageView, WebPageController, WebBrowseViewModel, WebPermissionGate, SslHandler | ArkWeb 加载、上下文菜单、错误页、图片预览；SSL 异常确认；站点权限双层判定 |
| 多标签导航 | TabsPageView, TabManager, BrowserNavigation, NavigationController | 标签 CRUD、页间路由、前进后退栈 |
| 书签历史下载 | FeaturePanel, BookmarkRepository, HistoryRepository, DownloadManager | 书签树形增删改/移动/文件夹（上限 100）；历史仅 http(s)、无痕不记、同站同日合并；下载队列 |
| 设置与隐私 | ProfileView, SettingsStore, SslHandler, IncognitoPolicy | 管理页、主题字号、SSL 信任主机、无痕写入拦截 |
| 系统交互 | BrowserWindowService, MainAbility Want, ScanQrService | SceneBoard / 系统栏协同、外链拉起、扫码等 |

### 与其他应用的关系

| 项目 | 说明 |
|------|------|
| 是否允许其他应用调用 | 允许。MainAbility 声明 `exported=true`，外部应用可通过 Want 拉起 |
| 谁能调用 | 应用可通过 `entity.system.browsable` + `http`/`https` URI 拉起 |
| 什么时候能调用 | 应用安装后即可调用；访问定位 / 相机 / 麦克风等站点能力时需用户授权 |
| 支持的 Want 参数 | 桌面入口：`ohos.want.action.home`；外链浏览：`ohos.want.action.viewData`，`uri` 为待打开的 `http`/`https` 地址 |
| 与 SceneBoard 的关系 | 依赖 SceneBoard 承接桌面入口与窗口场景；`BrowserWindowService` 在前后台切换时与 SceneBoard / SystemUI 协同系统栏与安全区 |
| 跨进程依赖 | 扫码依赖 `com.ohos.scanservice`（`module.json5` dependencies）；网页渲染依赖 ArkWeb |

## 编译构建

本工程为多模块 HAP 应用工程，使用 Hvigor 构建，产物为 `com.ohos.browser` 系统应用包。

### 环境要求
- OpenHarmony SDK（本工程 compileSdkVersion 为 "26.0.0"，compatibleSdkVersion 为 23）
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

适用场景：新增全屏路由页、扩展浏览相关能力、补充系统交互或适配新设备形态。下面以 **「新增导航页面」** 为例说明端到端步骤（可类比新增设置子页、独立工具页等）。

> **说明**：当前工程采用 `product + feature + common` 多模块结构，产品入口主要在 `product/entry`。新能力一般按现有分层扩展；若新增产品形态 HAP，可在 `product/` 下增加对应目录并在 `build-profile.json5` 中注册。

**示例：新增导航页面（如 `NavGuidePage`）**

1. **在 Feature 中实现页面 UI / ViewModel**  
   例如在 `feature/home`（或新建 `feature/nav`）下新增：
   - `src/main/ets/NavGuidePageView.ets`：页面布局与交互  
   - `src/main/ets/NavGuideViewModel.ets`：状态与业务逻辑  
   若需持久化（如引导完成标记），在 `common/src/main/ets/model/` 与 `repository/` 扩展字段，并由 `SettingsStore` / Repository 读写。

2. **在产品层增加路由页面壳并注册**  
   - 新增 `product/entry/src/main/ets/pages/NavGuidePage.ets`，内部组合 Feature 中的 View。  
   - 在 `product/entry/src/main/resources/base/profile/main_pages.json` 中声明页面路径（与现有 `MainPage` / `BrowsePage` / `TabsPage` 同级）。

3. **在导航层增加跳转入口**  
   - 在 `feature/browser_core/src/main/ets/BrowserNavigation.ets` 增加打开方法（例如 `openNavGuide()`），内部通过路由桥 `pushUrl` 到 `pages/NavGuidePage`。  
   - 在触发点（首页按钮、`BrowserStore` 门面或 Want 参数）调用该方法。  
   - 如需从页签管理返回时恢复正确分区，参考现有 `openTabs` / `returnFromTabsManager` 对 `incognito` 参数的处理。

4. **确认 Ability / 权限 / 依赖**  
   入口 Ability 已在 `product/entry/src/main/module.json5` 声明；新页面通常只需确认：是否新增权限、是否新增 skills、是否依赖新的 HAR（在 `build-profile.json5` 与 `product/entry/oh-package.json5` 注册）。

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

5. **联调验证**  
   冷启动进入、从首页/浏览页跳转、系统返回键 / 边缘返回、横竖屏与系统栏（`BrowserWindowService`）、无痕分区切换等场景均需覆盖。

**其他常见扩展**（步骤与上类似，落点不同）：
- 扩展书签能力：改 `feature/bookmark` + `BookmarkRepository`，注意 `BOOKMARK_LIMIT`。  
- 扩展下载确认流：改 `feature/download` + `DownloadManager`。  
- 扩展站点权限项：改 `WebPermissionGate` + 设置页 UI。

## 目录

工程按「产品入口 / 特性 HAR / 公共能力」三层组织，关键路径如下：

```text
applications_browser
├─AppScope                                      # 应用级配置与多语言资源
│  ├─app.json5                                  # bundleName、版本号等
│  └─resources/                                 # 全局字符串 / 图标等资源
│     ├─base/
│     └─en_US/
├─common                                        # 公共能力层（HAR）
│  └─src/main/ets/
│     ├─model/                                  # BookmarkItem、HistoryEntry、常量（含 BOOKMARK_LIMIT）
│     ├─repository/                             # RDB：书签 / 历史 / 下载 / 标签 / 设置
│     └─utils/                                  # 日志、路由桥、BrowserUtils、字符串工具
├─feature                                       # 特性层（多个 HAR）
│  ├─browser_core/                              # 门面与核心服务
│  │  └─src/main/ets/
│  │     ├─BrowserStore.ets / BrowserNavigation.ets / BrowserApp.ets
│  │     ├─tab/                                 # TabManager、缩略图
│  │     ├─web/                                 # WebPageController、WebPermissionGate
│  │     ├─download_svc/                        # DownloadManager 与通知 / 路径
│  │     ├─security/                            # SslHandler、IncognitoPolicy
│  │     ├─settings/                            # BrowserWindowService、SettingsStore
│  │     ├─navigation/                          # ScanQr、NavigationController
│  │     └─system/                              # 图库、分享等系统桥
│  ├─commons/                                   # 通用 UI 组件（对话框、图标等）
│  ├─home/                                      # 首页 / 搜索 / 快捷方式
│  ├─tab/                                       # 标签管理页 UI
│  ├─web/                                       # 浏览页 UI（BrowsePageView）
│  ├─bookmark/                                  # 书签 / 历史面板（FeaturePanel）
│  ├─download/                                  # 下载列表 UI
│  ├─settings/                                  # 管理 / 设置页 UI
│  └─security/                                  # 安全隐私相关 UI
├─product                                       # 产品层
│  └─entry/                                     # 入口 HAP
│     └─src/main/
│        ├─ets/
│        │  ├─MainAbility/                      # MainAbility、备份扩展
│        │  └─pages/                            # MainPage / BrowsePage / TabsPage 页面壳
│        ├─module.json5                         # 权限、Ability、skills、依赖
│        └─resources/                           # 页面注册（main_pages.json）、字符串与图标
├─docs/figures/                                 # 架构示意图（含 SceneBoard）
├─lib/                                          # 本地 HAR
├─hvigor/                                       # 构建工具配置
├─signature/                                    # 签名证书与 profile
├─build-profile.json5                           # 工程级配置
├─oh-package.json5
├─README.md                                     # 中文说明文档
└─README_en.md                                  # 英文说明文档
```

## 约束
- **语言版本**：ArkTS
- **运行形态**：系统预置应用（`com.ohos.browser`），依赖 ArkWeb、网络、文件、媒体库、SceneBoard / 窗口等系统能力
- **设备类型**：入口模块 `deviceTypes` 为 `default`；各 Feature HAR 声明 `default`、`tablet`
- **权限**：浏览器所需的主要权限如下（见 `product/entry/src/main/module.json5`）。应用获得权限后，网页仍需按站点 origin 申请；详见上文「网页权限」。

  | 权限 | 授权方式 | 使用场景 |
  |------|---------|--------|
  | ohos.permission.INTERNET | 系统授权 | 网页访问 |
  | ohos.permission.GET_NETWORK_INFO | 系统授权 | 网络状态感知（如下载） |
  | ohos.permission.WRITE_IMAGEVIDEO | 用户授权 | 图片保存到相册 |
  | ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY | 用户授权 | 下载文件写入系统 Download 目录 |
  | ohos.permission.APPROXIMATELY_LOCATION / LOCATION | 用户授权 | 站点定位权限（应用层） |
  | ohos.permission.CAMERA | 用户授权 | 站点相机权限（应用层） |
  | ohos.permission.MICROPHONE | 用户授权 | 站点麦克风权限（应用层） |

- **系统协同**：窗口与系统栏行为依赖 SceneBoard / SystemUI；修改 `BrowserWindowService` 时需验证冷启动、回前台、多任务切换等场景

## 参与贡献

欢迎广大开发者贡献代码、文档等，具体的贡献流程和方式请参见[参与贡献](https://gitcode.com/openharmony/docs/blob/master/zh-cn/contribute/%E5%8F%82%E4%B8%8E%E8%B4%A1%E7%8C%AE.md)。
