# 浏览器（Browser）

## 简介

**浏览器**（包名：`com.ohos.browser`）是 OpenHarmony 中预置的 **系统应用**，基于 ArkUI 与 ArkWeb 构建，提供主页导航、多标签浏览、书签与历史、下载管理、设置与隐私、系统交互等能力，并适配手机、平板等设备形态。

本应用为系统预置应用，用户可从桌面图标进入；外部应用也可通过 `http` / `https` 的 `viewData` Want 拉起浏览器打开网页。应用窗口、系统栏等与 **SceneBoard** 协同。

### 核心能力

**网页浏览**
- 基于 ArkWeb（WebviewController + 下载委托）加载 HTTPS/HTTP 页面。
- 支持前进、后退、刷新、SSL 证书处理、文本 / 链接 / 图片上下文菜单、图片预览与保存，以及边缘手势返回、页签缩略图快照。

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

对照业界主流桌面与手机浏览器的常见能力，结合本仓当前实现，汇总支持情况如下。  
「支持」指应用侧已落地可用；「不支持」指代码未实现、明确裁剪或仅有引擎能力尚未接产品链路。

| 能力                     | 本浏览器 | 描述                                                                                |
|------------------------|------|-----------------------------------------------------------------------------------|
| HTTP/HTTPS 网页浏览        | 支持   | 基于 ArkWeb 加载与渲染                                                                   |
| 前进 / 后退 / 刷新           | 支持   | 应用栈 + Web 历史协同                                                                    |
| 多标签管理                  | 支持   | 应用内标签与路由；非多进程渲染隔离                                                                 |
| 书签 / 历史                | 支持   | 本地 RDB；书签树形 CRUD（上限 100）；历史按站点/日合并                                                |
| 下载管理                   | 支持   | 队列、进度、系统 Download 目录、通知回跳；无 P2P 下载 / 限速等高级调度                                      |
| 无痕模式                   | 支持   | 独立分区，不落历史/书签/下载列表，退出清理 Web 数据                                                     |
| 搜索引擎切换与跳转              | 支持   | 内置百度、Bing、搜狗、360                                                                  |
| 页内查找                   | 支持   | ArkWeb 查找能力                                                                       |
| SSL 证书异常确认             | 支持   | HTTPS证书有问题时（过期、域名对不上、内网自签证书等），浏览器优先拦截。用户选择“继续访问”后，浏览器记住主机信息，下次不再提示，页面上的子资源也会一并放行。 |
| 站点权限（定位/相机/麦克风/通知）     | 支持   | 与主流浏览器一致，通知类权限授予浏览器后即可用于所有网页，定位、相机、麦克风等敏感权限在浏览器授权后，每个网站仍需授权（默认禁止），无痕模式下默认不授予。     |
| 图片预览 / 保存 / 分享         | 支持   | 上下文菜单与图库写入                                                                        |
| PDF / JSON / XML / TXT 预览 | 支持   | 由 ArkWeb 内置能力预览                                                                   |
| 扫码打开网页                 | 支持   | 依赖 `com.ohos.scanservice`                                                         |
| 外链 Want 打开网页           | 支持   | 仅 `http` / `https`                                                                |
| 深色模式 / 系统字号            | 支持   | 与系统主题、字号联动                                                                        |
| 网页内音视频播放               | 支持   | ArkWeb HTML5 媒体；页内播放与全屏                                                           |
| HTTP / SOCKS 代理        | 不支持  | 无代理设置 UI 与应用内配置 API                                                               |
| 扩展 / 插件生态              | 不支持  | 无扩展框架与管理 UI；产品定位为系统基础浏览器                                                          |
| 账号同步（书签/历史/密码上云）       | 不支持  | 仅本地存储，无账号体系                                                                       |
| 密码管理 / 自动填充            | 不支持  | 未接入系统密码保险箱或表单自动填充能力                                                               |
| 翻译 / 阅读模式              | 不支持  | 未接入翻译或阅读模式服务                                                                      |
| 广告拦截 / 高级跟踪防护          | 不支持  | 无规则引擎；仅站点权限与无痕                                                                    |
| PWA 安装 / 添加到主屏         | 不支持  | 未处理 Web App Manifest / 安装流程                                                       |
| 开发者工具                  | 不支持  | 无网页调试 / 检查界面                                                                      |
| 打印网页                   | 不支持  | 打印依赖打印框架，当前系统不具备                                                                  |
| 网页视频接入播控中心（AVSession）  | 不支持  | 无 AVSession 上报；构建裁剪了 `AVInputCast`                                                |
| 画中画（网页视频）              | 不支持  | 仅有全屏进出钩子，无画中画产品链路                                                                 |
| 服务端搜索建议                | 不支持  | 仅本地历史/书签匹配，未接搜索引擎建议接口                                                             |
| 恶意网址拦截                 | 不支持  | 未接入恶意网址拦截服务                                                                       |
| `file://` 等本地协议外链打开    | 不支持  | 对外 Want 与运行时校验仅接受 `http`/`https`                                                  |
| 多进程渲染隔离                | 不支持  | 单主进程 + 进程内 ArkWeb，标签不隔离到独立 OS 进程                                                  |

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

**特性层模块说明**（展开到 L3 能力点）：

| 核心能力 | 所在模块 | 说明（涉及功能） |
|--------|---------|----------------|
| 网页浏览 | 浏览页界面、网页控制、站点权限、证书处理 | 页面加载与渲染；前进 / 后退 / 刷新；链接与图片菜单；错误页；图片预览与保存。证书异常确认（默认拦截，确认后按主机记住）。站点权限（定位 / 相机 / 麦克风 / 通知：浏览器有权限 ≠ 所有网页都有权限，各网站还须单独申请） |
| 多标签导航 | 标签管理页、标签服务、页面导航 | 标签管理（创建 / 关闭 / 切换 / 排序；普通与无痕分区各自上限 100）。页面路由（首页 / 页签管理页 / 浏览页）。前进后退栈；启动时可恢复上次活跃标签 |
| 书签历史下载 | 功能面板、书签与历史数据、下载服务 | 书签管理（新增 / 编辑 / 删除 / 移动 / 建文件夹；书签上限 100）。历史记录（仅 http/https；无痕不记；同站同日合并；按日期分组；可删可清空；本地持久保存，无按天数自动清理）。下载管理（队列与进度；写入系统下载目录；取消 / 重试；重名加后缀） |
| 设置与隐私 | 管理页、设置存储、证书与无痕策略 | 管理页；主题与字号。搜索引擎切换。按网站允许 / 禁止站点权限。已信任主机管理。无痕策略（不写入历史 / 书签 / 下载列表，退出清理网页数据） |
| 系统交互 | 窗口服务、应用入口拉起、扫码服务 | 与桌面窗口 / 系统栏协同（含沉浸式浏览）。外部应用拉起打开网页。扫码打开网页。下载完成通知回跳 |

### 与外部应用的关系

| 项目 | 说明 |
|------|------|
| 是否允许外部应用调用 | 允许。MainAbility 声明 `exported=true`，外部应用可通过 Want 拉起 |
| 谁能调用 | 应用可通过 `entity.system.browsable` + `http`/`https` URI 拉起 |
| 什么时候能调用 | 应用安装后即可调用；访问定位 / 相机 / 麦克风等站点能力时需用户授权 |
| 支持的 Want 参数 | 桌面入口：`ohos.want.action.home`；外链浏览：`ohos.want.action.viewData`，`uri` 为待打开的 `http`/`https` 地址 |
| 与 SceneBoard 的关系 | 依赖 SceneBoard 承接桌面入口与窗口场景；`BrowserWindowService` 在前后台切换时与 SceneBoard / SystemUI 协同系统栏与安全区 |
| 跨进程依赖 | 扫码依赖 `com.ohos.scanservice`（`module.json5` dependencies）；网页渲染依赖 ArkWeb |

## 编译构建

本工程为多模块 HAP 应用工程，使用 Hvigor 构建，产物为 `com.ohos.browser` 系统应用包。

### 环境要求
- OpenHarmony SDK（本工程 compileSdkVersion 为 "26.0.0"，compatibleSdkVersion和targetSdkVersion 为 23）
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
      "default",
      "tablet"
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

**其余常见扩展**（步骤与上类似，落点不同）：
- 扩展书签能力：改 `feature/bookmark` + `BookmarkRepository`，注意 `BOOKMARK_LIMIT`。  
- 扩展下载确认流：改 `feature/download` + `DownloadManager`。  
- 扩展站点权限项：改 `WebPermissionGate` + 设置页 UI。

## 目录

工程按「产品入口 / 特性模块 / 公共能力」三层组织。

```text
applications_browser
├─AppScope                                      # 应用级配置：包名、版本、全局文案与图标等
│  ├─app.json5                                  # 应用标识与版本信息
│  └─resources/                                 # 多语言字符串、图标等全局资源
├─common                                        # 公共能力：多特性共用的数据与工具
│  └─src/main/ets/
│     ├─model/                                  # 书签、历史、下载、标签等数据模型与上限常量
│     ├─repository/                             # 本地数据库访问：书签 / 历史 / 下载 / 标签 / 设置
│     └─utils/                                  # 日志、页面跳转桥接、通用工具与文案组装
├─feature                                       # 特性层：按业务拆分的功能模块
│  ├─browser_core/                              # 浏览核心：对外门面、导航与各类后台服务
│  │  └─src/main/ets/
│  │     ├─BrowserStore.ets / BrowserNavigation.ets / BrowserApp.ets   # 统一状态门面、页面跳转、应用启动初始化
│  │     ├─tab/                                 # 多标签：创建 / 关闭 / 切换 / 排序、缩略图
│  │     ├─web/                                 # 网页控制：加载控制、站点权限判定
│  │     ├─download_svc/                        # 下载服务：任务队列、进度、通知、落盘路径
│  │     ├─security/                            # 安全隐私：证书异常确认、无痕写入拦截
│  │     ├─settings/                            # 设置与窗口：偏好存储、系统栏 / 沉浸式协同
│  │     ├─navigation/                          # 导航辅助：扫码打开网页、路由控制
│  │     └─system/                              # 系统能力桥接：图库写入、分享可用性等
│  ├─commons/                                   # 通用界面零件：对话框、图标、提示等
│  ├─home/                                      # 首页：搜索入口、快捷方式
│  ├─tab/                                       # 标签管理页界面
│  ├─web/                                       # 浏览页界面：网页展示与操作栏
│  ├─bookmark/                                  # 书签与历史面板：增删改查、按日分组
│  ├─download/                                  # 下载列表界面：进度展示与任务操作
│  ├─settings/                                  # 管理 / 设置页界面：引擎、权限、主题等
│  └─security/                                  # 安全隐私相关界面
├─product                                       # 产品层：可安装的应用入口
│  └─entry/                                     # 入口包：Ability、页面壳、权限声明
│     └─src/main/
│        ├─ets/
│        │  ├─MainAbility/                      # 应用入口生命周期、备份扩展
│        │  └─pages/                            # 首页 / 浏览页 / 标签页等页面壳
│        ├─module.json5                         # 权限、入口组件、技能与跨应用依赖
│        └─resources/                           # 页面注册、字符串与图标资源
├─docs/figures/                                 # 文档插图：架构示意图等
├─lib/                                          # 本地依赖库
├─hvigor/                                       # 构建工具配置
├─signature/                                    # 签名证书与签名配置
├─build-profile.json5                           # 工程级配置
├─oh-package.json5                              # 包依赖声明
├─README.md                                     # 中文说明文档
└─README_en.md                                  # 英文说明文档
```

## 约束
- **语言版本**：ArkTS
- **运行形态**：系统预置应用（`com.ohos.browser`），依赖 ArkWeb、网络、文件、媒体库、SceneBoard / 窗口等系统能力
- **设备类型**：入口模块 `deviceTypes` 与各 Feature HAR 均声明为 `default`、`tablet`
- **权限**：浏览器所需的主要权限如下（见 `product/entry/src/main/module.json5`）。注意：这里列的是给**浏览器应用**的系统权限；网页要用定位 / 相机 / 麦克风等，还须按站点再申请，详见上文「网页权限」。

  | 权限 | 授权方式 | 使用场景 |
  |------|---------|--------|
  | ohos.permission.INTERNET | 系统授权 | 网页访问 |
  | ohos.permission.GET_NETWORK_INFO | 系统授权 | 网络状态感知（如下载） |
  | ohos.permission.WRITE_IMAGEVIDEO | 用户授权 | 图片保存到相册 |
  | ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY | 用户授权 | 下载文件写入系统 Download 目录 |
  | ohos.permission.APPROXIMATELY_LOCATION / LOCATION | 用户授权 | 先给浏览器定位能力；具体网页还要再申请 |
  | ohos.permission.CAMERA | 用户授权 | 先给浏览器相机能力；具体网页还要再申请 |
  | ohos.permission.MICROPHONE | 用户授权 | 先给浏览器麦克风能力；具体网页还要再申请 |

- **系统协同**：窗口与系统栏行为依赖 SceneBoard / SystemUI；修改 `BrowserWindowService` 时需验证冷启动、回前台、多任务切换等场景

## 参与贡献

欢迎广大开发者贡献代码、文档等，具体的贡献流程和方式请参见[参与贡献](https://gitcode.com/openharmony/docs/blob/master/zh-cn/contribute/%E5%8F%82%E4%B8%8E%E8%B4%A1%E7%8C%AE.md)。
