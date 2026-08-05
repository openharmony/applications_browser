# Browser

## Introduction

**Browser** (bundle name: `com.ohos.browser`) is a pre-installed **system application** in OpenHarmony. Built with ArkUI and ArkWeb, it provides home navigation, multi-tab browsing, bookmarks and history, download management, settings and privacy, and system interaction capabilities, and adapts to phone and tablet form factors.

This application is a system preset app. Users can open it from the desktop icon; other apps can also launch it via `http` / `https` `viewData` Want to open web pages. Window and system-bar behavior coordinates with **SceneBoard**.

### Core Capabilities

**Web Browsing**
- Loads HTTPS/HTTP pages via ArkWeb (`WebviewController` + download delegate).
- Supports back, forward, refresh, SSL handling, text / link / image context menus, and image preview / save.
- Supports edge gesture back and tab thumbnail snapshots.

**Multi-tab and Navigation**
- Supports three routed pages: home (`MainPage`), tab manager (`TabsPage`), and browse (`BrowsePage`).
- Uses `TabManager` / `BrowserNavigation` for tab create, close, restore, and routing; can restore the last active tab on launch.

**Bookmarks, History, and Downloads**
- Provides tree-structured bookmarks, history grouped by date, and a download queue with progress.
- Downloads are saved to the system Download directory, with automatic `(1)`, `(2)`, … suffixes for duplicates; images can be published to the system gallery.

**Settings and Privacy**
- Supports search-engine switching, site permissions, and incognito mode (no history / bookmarks / download list; Web data cleared on exit).
- Supports light / dark theme synced with system color mode and font size.

**System Interaction**
- Uses `BrowserWindowService` with SceneBoard / Window to manage immersive system bars, safe areas, orientation, and foreground/background re-pinning.
- Bridges system capabilities such as external Want open, download notification launch, and scan-service dependency.

**Event and call flow**:
1. The launcher or another app starts `MainAbility` with bundleName `com.ohos.browser` (home entry or `http`/`https` Want).
2. `MainAbility` binds context, initializes window and theme, and loads `MainPage`; WebEngine init is deferred to avoid blocking the first frame.
3. Business APIs go through the `BrowserStore` facade to `TabManager` / `DownloadManager` and related services; `common` repositories write to `browser.db`.
4. Window and system-bar state are coordinated with SceneBoard via `BrowserWindowService`, including SystemUI repair on foreground/background switches.

> For example, a typical external-link flow:
> - Another app launches `MainAbility` with `viewData` + an `https` URI;
> - `MainAbility.captureExternalBrowseWant` parses the URL and queues it via `BrowserNavigation`;
> - After init, `BrowsePage` opens and ArkWeb loads the target page.

## Architecture

Browser uses a layered and modular design organized by product form, business features, and common capabilities, and collaborates with SceneBoard and other system capabilities, as shown below:
![Architecture](./docs/figures/Browser_en.png)

### Application Layered Design

The overall structure is divided into product, feature, and common layers:

| Layer | Main Directories / Components | Description |
|------| ----------------------------- |-------------|
| Product | `product/entry` | Phone / tablet entry HAP; Ability, page shells, permissions, and resources |
| Feature | `feature/browser_core`, `feature/home`, `feature/tab`, `feature/web`, `feature/bookmark`, `feature/download`, `feature/settings`, `feature/security`, `feature/commons` | Browsing, tabs/navigation, bookmarks/history/downloads, settings/privacy, system interaction |
| Common | `common` | Models, RDB persistence, router bridge, logging, and utilities |

**Feature module description**:

| Capability | Modules | Description |
|------------|---------|-------------|
| Web browsing | BrowsePageView, WebPageController, WebBrowseViewModel | ArkWeb loading, context menus, error pages, image preview |
| Tabs / navigation | TabsPageView, TabManager, BrowserNavigation, NavigationController | Tab CRUD, page routing, back/forward stack |
| Bookmarks / history / downloads | FeaturePanel, BookmarkRepository, HistoryRepository, DownloadManager | Panels, download confirm flow, and task queue |
| Settings / privacy | ProfileView, SettingsStore, SslHandler, IncognitoPolicy | Profile page, theme/font, SSL, incognito policy |
| System interaction | BrowserWindowService, MainAbility Want, ScanQrService | SceneBoard / system-bar coordination, external Want, scan |

### Relationship with Other Applications

| Item | Description |
|------|-------------|
| Can other apps call it? | Yes. MainAbility declares `exported=true` and can be started via Want |
| Who can call | Launcher / SceneBoard via home skill; other apps via `entity.system.browsable` + `http`/`https` URI |
| When | After install; site location / camera / microphone still require user grants |
| Supported Want | Home: `ohos.want.action.home`; browse: `ohos.want.action.viewData` with `http`/`https` `uri` |
| SceneBoard | Depends on SceneBoard for launcher entry and window scenes; `BrowserWindowService` coordinates system bars and safe areas with SceneBoard / SystemUI |
| Cross-process | Scan depends on `com.ohos.scanservice`; rendering depends on ArkWeb |

## Build

This project is a multi-module HAP application built with Hvigor. The output is the `com.ohos.browser` system application package.

### Environment Requirements
- OpenHarmony SDK (`compileSdkVersion` / `compatibleSdkVersion` / `targetSdkVersion` are all 23)
- DevEco Studio or the command-line Hvigor toolchain
- System signing certificates (see `signature/`)

### Build Commands

Run the following in the project root:

```bash
# Open the project in DevEco Studio and Build, or use the hvigor CLI
hvigorw assembleHap
```

## Browser Development

Browser is developed in **ArkTS**, with UI based on the ArkUI Stage model. The main UI is hosted by `MainAbility`, browsing business lives in `feature/*`, and models/database consistency is maintained by `common`. Development reference: [ArkUI Development Overview](https://gitcode.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-ui-development-overview.md), [ArkWeb Guide](https://gitcode.com/openharmony/docs/tree/master/en/application-dev/web).

### Development Based on Existing Modules

Applicable scenarios: customize existing capabilities, such as adjusting home shortcuts, extending download confirm flow, modifying system-bar coordination, or trimming a Feature.

**Adjusting or trimming existing modules**

1. Locate the change by business boundary: `product/entry` (entry and page shells), `feature/web` (browse UI), `feature/browser_core` (facade and services), `feature/bookmark` / `download`, or `common`.
2. Adjusting the browse path:
   - Page shell: `product/entry/src/main/ets/pages/BrowsePage.ets`
   - Browse UI: `feature/web/src/main/ets/BrowsePageView.ets`
   - Web control: `feature/browser_core/src/main/ets/web/WebPageController.ets`

    For example, Ability loads the main page and defers WebEngine init:
    ```typescript
    // MainAbility.ets — onWindowStageCreate is the main-window entry
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
3. Adjusting tabs / routing:
   - Tab management: `feature/browser_core/src/main/ets/tab/TabManager.ets`
   - Navigation: `feature/browser_core/src/main/ets/BrowserNavigation.ets`
4. Adjusting system interaction / SceneBoard coordination:
   - Window and system bars: `feature/browser_core/src/main/ets/settings/BrowserWindowService.ets`
   - External Want parsing: `product/entry/src/main/ets/MainAbility/MainAbility.ets`
5. Adjusting UI components:
   - Home / browse / bookmark UI under corresponding `feature/*/src/main/ets/`
   - Shared dialogs and Toast under `feature/commons/`

Common edit points:

| Goal | Path |
|------|------|
| Entry Ability | `product/entry/src/main/ets/MainAbility/MainAbility.ets` |
| Home / profile shell | `product/entry/src/main/ets/pages/MainPage.ets` |
| Browse page | `feature/web/src/main/ets/BrowsePageView.ets` |
| UI facade | `feature/browser_core/src/main/ets/BrowserStore.ets` |
| Window / SceneBoard | `feature/browser_core/src/main/ets/settings/BrowserWindowService.ets` |
| Models and RDB | `common/src/main/ets/model/`, `common/src/main/ets/repository/` |

### Developing New Capabilities

Applicable scenarios: add browsing capabilities, extend full-screen routes, enrich system interaction, or adapt new form factors.

> **Note**: This project uses a `product + feature + common` multi-module structure. The product entry is mainly `product/entry`. Extend along existing layers; for a new form-factor HAP, add a directory under `product/` and register it in `build-profile.json5`.

**Step 1: Extend business capabilities (most common)**

1. Add page / ViewModel / service logic in the corresponding `feature/` HAR.
2. For persistence, extend model + Repository in `common`.
3. For cross-page calls, add a thin API on `BrowserStore`.
4. Register / declare dependencies in `build-profile.json5` and `product/entry/oh-package.json5`.

**Step 2: Confirm Ability entry**

Entry is already declared in `product/entry/src/main/module.json5`. When extending, usually confirm permissions, Ability, skills, and inter-app dependencies:

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

**Step 3: Customize UI**

After business and Ability configuration, extend home, browse, tabs, or panels using the UI modification approach in the previous section.

To add an independent page:
1. Add the page under the corresponding module `pages/` or Feature;
2. Register it in `resources/base/profile/main_pages.json` if needed;
3. Launch it via `BrowserNavigation` or Want.

## Directory
```text
applications_browser
├─AppScope                              # App-level config and resources
│  ├─app.json5                          # bundleName, version, etc.
│  └─resources/                         # Global strings / icons
├─common                                # Common capabilities
│  └─src/main/ets/
│     ├─model/                          # Shared models and constants
│     ├─repository/                     # RDB access and BrowserDatabase
│     └─utils/                          # Logging, router bridge, utilities
├─feature                               # Feature layer
│  ├─browser_core/                      # Facade, tabs, downloads, Web, window services
│  ├─commons/                           # Shared UI widgets
│  ├─home/                              # Home / search / shortcuts
│  ├─tab/                               # Tab manager UI
│  ├─web/                               # Browse page UI
│  ├─bookmark/                          # Bookmarks / history / FeaturePanel
│  ├─download/                          # Download UI
│  ├─settings/                          # Profile page
│  └─security/                          # Security and privacy UI
├─product                               # Product layer
│  └─entry/                             # Entry HAP
│     └─src/main/ets/
│        ├─MainAbility/                 # Main Ability, backup extension
│        └─pages/                       # MainPage / BrowsePage / TabsPage
├─docs/figures/                         # Architecture diagrams
├─lib/                                  # Local HAR
├─hvigor                                # Build tooling
├─signature                             # Signing certs and profile
├─build-profile.json5                   # SDK / signing / product config
├─oh-package.json5
├─README.md                             # Chinese docs
└─README_en.md                          # English docs
```

## Constraints
- **Language**: ArkTS
- **Runtime**: preinstalled system app (`com.ohos.browser`); depends on ArkWeb, network, file, media library, SceneBoard / window capabilities
- **Device types**: entry `deviceTypes` is `default`; Feature HARs declare `default`, `tablet`
- **Permissions**: main permissions (see `product/entry/src/main/module.json5`)

  | Permission | Grant mode | Scenario |
  |------------|------------|----------|
  | ohos.permission.INTERNET | system | Web access |
  | ohos.permission.GET_NETWORK_INFO | system | Network awareness (e.g. downloads) |
  | ohos.permission.WRITE_IMAGEVIDEO | user | Save images to gallery |
  | ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY | user | Write downloads to system Download dir |
  | ohos.permission.APPROXIMATELY_LOCATION / LOCATION | user | Site location |
  | ohos.permission.CAMERA | user | Site camera |
  | ohos.permission.MICROPHONE | user | Site microphone |

- **System coordination**: window and system-bar behavior depends on SceneBoard / SystemUI; validate cold start, resume, and multitasking when changing `BrowserWindowService`

## Contributing

Contributions of code and docs are welcome. See [Contributing](https://gitcode.com/openharmony/docs/blob/master/zh-cn/contribute/%E5%8F%82%E4%B8%8E%E8%B4%A1%E7%8C%AE.md).
