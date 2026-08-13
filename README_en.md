# Browser

## Introduction

**Browser** (bundle name: `com.ohos.browser`) is a pre-installed **system application** in OpenHarmony. Built with ArkUI and ArkWeb, it provides home navigation, multi-tab browsing, bookmarks and history, download management, settings and privacy, and system interaction capabilities, and adapts to phone and tablet form factors.

This application is a system preset app. Users can open it from the desktop icon; other apps can also launch it via `http` / `https` `viewData` Want to open web pages. Window and system-bar behavior coordinates with **SceneBoard**.

### Core Capabilities

**Web Browsing**
- Loads HTTPS/HTTP pages via ArkWeb (`WebviewController` + download delegate).
- Supports back, forward, refresh, text / link / image context menus, image preview / save, edge gesture back, and tab thumbnail snapshots.
- **SSL certificate errors**: loading is denied by default. After the user confirms, the host is added to a local trusted-host list (persisted); later visits to the same host can proceed. When the main frame host is trusted, same-page subresources are allowed as well. This is not a full system certificate manager—no import / full chain viewing—only “error confirmation + trust by host”.
- **HTTP / SOCKS proxy**: not supported. There is no proxy settings UI and no in-app proxy configuration API; networking uses the system default path.

**Site permissions (industry-standard two-layer model)**
- Same idea as Chrome / Safari: holding a system permission in the browser app does **not** mean every web page can use it; each site is still decided by **origin**.
- **App-level permissions**: the browser must declare and obtain system grants (e.g. `LOCATION`, `CAMERA`, `MICROPHONE`) via `module.json5` and user consent.
- **Site-level permissions**: when a page requests access through ArkWeb, the decision uses global site policy + per-origin policy. Users can allow / deny per site in Settings. The same permission is independent across different origins by default.
- In incognito mode, sensitive site permissions are denied by default; short session caching avoids repeated prompts for the same origin.

**Multi-tab and Navigation**
- Supports three routed pages: home (`MainPage`), tab manager (`TabsPage`), and browse (`BrowsePage`).
- Uses `TabManager` / `BrowserNavigation` for tab create, close, restore, and routing; can restore the last active tab on launch.

**Bookmarks, History, and Downloads**
- **Bookmarks**: tree structure (folders + items); create, edit title/URL, delete (recursive for children), move to folder, create folder; bookmark count cap 100 (folders excluded); local RDB persistence.
- **History**: only recordable `http`/`https` URLs; skipped in incognito; same site on the same calendar day merges into one entry (updates visit time / title / icon), new day creates a new row; search-keyword history keeps at most 20 items.
- **Downloads**: queue and progress UI; files go to the system Download directory with automatic `(1)`, `(2)`, … suffixes; images can be published to the system gallery.

**Settings and Privacy**
- Supports search-engine switching, site permissions, and incognito mode (no history / bookmarks / download list; Web data cleared on exit).
- Supports light / dark theme synced with system color mode and font size.

**System Interaction**
- Through collaboration between `BrowserWindowService` and SceneBoard / Window, the browser supports immersive page browsing.
- Bridges system capabilities such as external Want open, download notification launch, and scan-service dependency.

## Comparison with Mainstream Browsers

The table below compares common capabilities of Chrome / Edge / Safari and typical mobile browsers with this repository’s current implementation.  
“Supported” means the app has a usable product path; “Not supported” means not implemented, explicitly trimmed, or engine-only without an app integration path.

| Capability | This browser | Notes / reason if unsupported |
|------------|--------------|-------------------------------|
| HTTP/HTTPS browsing | Supported | ArkWeb load and render |
| Back / forward / refresh | Supported | App stack + Web history |
| Multi-tab management | Supported | In-app tabs and routing; not Chromium multi-process isolation |
| Bookmarks / history | Supported | Local RDB; bookmark tree CRUD (cap 100); history merged by site/day |
| Downloads | Supported | Queue, progress, system Download dir, notification deep-link; no BT / advanced scheduling |
| Incognito | Supported | Separate partition; no history/bookmarks/download list; Web data cleared on exit |
| Search engine switch & navigate | Supported | Baidu / Bing / Sogou / 360; no Google option |
| Find in page | Supported | ArkWeb find |
| SSL error confirmation | Supported | Deny by default; user may trust host (persisted); not a full certificate manager |
| Site permissions (location/camera/mic/notification) | Supported | App permission + per-origin policy (two-layer model, same as mainstream browsers) |
| Image preview / save / share | Supported | Context menus and gallery write |
| PDF / JSON / XML / TXT preview | Supported | Preview via ArkWeb built-in capability |
| Scan QR to open URL | Supported | Depends on `com.ohos.scanservice` |
| External Want to open pages | Supported | `http` / `https` only |
| Dark mode / system font scale | Supported | Synced with system theme and font size |
| In-page audio/video playback | Supported | ArkWeb HTML5 media; in-page play and fullscreen |
| HTTP / SOCKS proxy | Not supported | No proxy settings UI or in-app configuration API |
| Extensions / plugins | Not supported | No extension framework or management UI; positioned as a system basic browser |
| Account sync (bookmarks/history/passwords) | Not supported | Local storage only; no account system |
| Password manager / autofill | Not supported | No password vault or Autofill product integration |
| Translate / reader mode | Not supported | No translation or reader-mode service |
| Ad block / advanced tracking protection | Not supported | No rule engine; only site permissions and incognito |
| PWA install / add to Home | Not supported | No Web App Manifest / install flow |
| Developer tools | Not supported | No DevTools UI |
| Print page | Not supported | Printing depends on the system print framework, which is not available on the current system |
| Web media in system media session (AVSession) | Not supported | No AVSession reporting; `AVInputCast` syscap removed at build |
| Picture-in-Picture for web video | Not supported | Fullscreen enter/exit hooks only; no PiP product path |
| Server-side search suggestions | Not supported | Local history/bookmark match only; no Suggest API |
| Safe Browsing / malware URL list | Not supported | No Safe Browsing service |
| Open via local schemes (`file://`, etc.) | Not supported | External Want and runtime checks accept `http`/`https` only |
| Chromium-style multi-process render isolation | Not supported | Single main process + in-process ArkWeb; tabs are not separate OS processes |

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
| Web browsing | BrowsePageView, WebPageController, WebBrowseViewModel, WebPermissionGate, SslHandler | ArkWeb loading, context menus, error pages, image preview; SSL confirmation; two-layer site permission gate |
| Tabs / navigation | TabsPageView, TabManager, BrowserNavigation, NavigationController | Tab CRUD, page routing, back/forward stack |
| Bookmarks / history / downloads | FeaturePanel, BookmarkRepository, HistoryRepository, DownloadManager | Bookmark tree CRUD/move/folders (cap 100); history http(s) only, skipped in incognito, merged by site/day; download queue |
| Settings / privacy | ProfileView, SettingsStore, SslHandler, IncognitoPolicy | Profile page, theme/font, trusted SSL hosts, incognito write policy |
| System interaction | BrowserWindowService, MainAbility Want, ScanQrService | SceneBoard / system-bar coordination, external Want, scan |

### Relationship with Other Applications

| Item | Description |
|------|-------------|
| Can other apps call it? | Yes. MainAbility declares `exported=true` and can be started via Want |
| Who can call | apps via `entity.system.browsable` + `http`/`https` URI |
| When | After install; site location / camera / microphone still require user grants |
| Supported Want | Home: `ohos.want.action.home`; browse: `ohos.want.action.viewData` with `http`/`https` `uri` |
| SceneBoard | Depends on SceneBoard for launcher entry and window scenes; `BrowserWindowService` coordinates system bars and safe areas with SceneBoard / SystemUI |
| Cross-process | Scan depends on `com.ohos.scanservice`; rendering depends on ArkWeb |

## Build

This project is a multi-module HAP application built with Hvigor. The output is the `com.ohos.browser` system application package.

### Environment Requirements
- OpenHarmony SDK (this project uses compileSdkVersion "26.0.0", compatibleSdkVersion 23)
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

Applicable scenarios: add a full-screen routed page, extend browsing features, enrich system interaction, or adapt new form factors. The walkthrough below uses **“add a navigation page”** as an end-to-end example (similar for a settings sub-page or standalone utility page).

> **Note**: This project uses a `product + feature + common` multi-module structure. The product entry is mainly `product/entry`. Extend along existing layers; for a new form-factor HAP, add a directory under `product/` and register it in `build-profile.json5`.

**Example: add a navigation page (e.g. `NavGuidePage`)**

1. **Implement UI / ViewModel in a Feature HAR**  
   For example under `feature/home` (or a new `feature/nav`):
   - `src/main/ets/NavGuidePageView.ets` — layout and interaction  
   - `src/main/ets/NavGuideViewModel.ets` — state and logic  
   If persistence is needed (e.g. “guide completed”), extend `common/src/main/ets/model/` and `repository/`, and read/write via `SettingsStore` / Repository.

2. **Add a product-layer page shell and register it**  
   - Add `product/entry/src/main/ets/pages/NavGuidePage.ets` that composes the Feature view.  
   - Declare the page in `product/entry/src/main/resources/base/profile/main_pages.json` (alongside `MainPage` / `BrowsePage` / `TabsPage`).

3. **Add a navigation entry**  
   - Add an open API on `feature/browser_core/src/main/ets/BrowserNavigation.ets` (e.g. `openNavGuide()`), using the router bridge to `pushUrl` `pages/NavGuidePage`.  
   - Call it from the trigger (home button, `BrowserStore` facade, or Want params).  
   - If returning from the tabs manager must restore the correct partition, follow the existing `openTabs` / `returnFromTabsManager` handling of `incognito`.

4. **Confirm Ability / permissions / dependencies**  
   Entry Ability is already declared in `product/entry/src/main/module.json5`. For a new page, usually confirm whether new permissions, skills, or HAR dependencies are required (`build-profile.json5` and `product/entry/oh-package.json5`).

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

5. **Verify**  
   Cover cold start, navigation from home/browse, system back / edge back, orientation and system bars (`BrowserWindowService`), and incognito partition switching.

**Other common extensions** (same flow, different touchpoints):
- Bookmark features: `feature/bookmark` + `BookmarkRepository` (respect `BOOKMARK_LIMIT`).  
- Download confirm flow: `feature/download` + `DownloadManager`.  
- Extra site permission types: `WebPermissionGate` + settings UI.

## Directory

The project is organized as product entry / feature HARs / common capabilities. Key paths:

```text
applications_browser
├─AppScope                                      # App-level config and resources
│  ├─app.json5                                  # bundleName, version, etc.
│  └─resources/                                 # Global strings / icons
│     ├─base/
│     └─en_US/
├─common                                        # Common capabilities (HAR)
│  └─src/main/ets/
│     ├─model/                                  # BookmarkItem, HistoryEntry, constants (BOOKMARK_LIMIT)
│     ├─repository/                             # RDB: bookmarks / history / downloads / tabs / settings
│     └─utils/                                  # Logging, router bridge, BrowserUtils, strings
├─feature                                       # Feature layer (multiple HARs)
│  ├─browser_core/                              # Facade and core services
│  │  └─src/main/ets/
│  │     ├─BrowserStore.ets / BrowserNavigation.ets / BrowserApp.ets
│  │     ├─tab/                                 # TabManager, thumbnails
│  │     ├─web/                                 # WebPageController, WebPermissionGate
│  │     ├─download_svc/                        # DownloadManager, notifications / paths
│  │     ├─security/                            # SslHandler, IncognitoPolicy
│  │     ├─settings/                            # BrowserWindowService, SettingsStore
│  │     ├─navigation/                          # ScanQr, NavigationController
│  │     └─system/                              # Gallery, share bridges
│  ├─commons/                                   # Shared UI widgets (dialogs, icons)
│  ├─home/                                      # Home / search / shortcuts
│  ├─tab/                                       # Tab manager UI
│  ├─web/                                       # Browse page UI (BrowsePageView)
│  ├─bookmark/                                  # Bookmarks / history panels (FeaturePanel)
│  ├─download/                                  # Download list UI
│  ├─settings/                                  # Profile / settings UI
│  └─security/                                  # Security and privacy UI
├─product                                       # Product layer
│  └─entry/                                     # Entry HAP
│     └─src/main/
│        ├─ets/
│        │  ├─MainAbility/                      # MainAbility, backup extension
│        │  └─pages/                            # MainPage / BrowsePage / TabsPage shells
│        ├─module.json5                         # Permissions, Ability, skills, dependencies
│        └─resources/                           # Page registry (main_pages.json), strings, icons
├─docs/figures/                                 # Architecture diagrams (includes SceneBoard)
├─lib/                                          # Local HAR
├─hvigor/                                       # Build tooling
├─signature/                                    # Signing certs and profile
├─build-profile.json5                           # config
├─oh-package.json5
├─README.md                                     # Chinese docs
└─README_en.md                                  # English docs
```

## Constraints
- **Language**: ArkTS
- **Runtime**: preinstalled system app (`com.ohos.browser`); depends on ArkWeb, network, file, media library, SceneBoard / window capabilities
- **Device types**: entry `deviceTypes` is `default`; Feature HARs declare `default`, `tablet`
- **Permissions**: main permissions (see `product/entry/src/main/module.json5`). App grants do not auto-enable site access; sites still need per-origin approval—see “Site permissions” above.

  | Permission | Grant mode | Scenario |
  |------------|------------|----------|
  | ohos.permission.INTERNET | system | Web access |
  | ohos.permission.GET_NETWORK_INFO | system | Network awareness (e.g. downloads) |
  | ohos.permission.WRITE_IMAGEVIDEO | user | Save images to gallery |
  | ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY | user | Write downloads to system Download dir |
  | ohos.permission.APPROXIMATELY_LOCATION / LOCATION | user | Site location (app layer) |
  | ohos.permission.CAMERA | user | Site camera (app layer) |
  | ohos.permission.MICROPHONE | user | Site microphone (app layer) |

- **System coordination**: window and system-bar behavior depends on SceneBoard / SystemUI; validate cold start, resume, and multitasking when changing `BrowserWindowService`

## Contributing

Contributions of code and docs are welcome. See [Contributing](https://gitcode.com/openharmony/docs/blob/master/zh-cn/contribute/%E5%8F%82%E4%B8%8E%E8%B4%A1%E7%8C%AE.md).
