> **⚡ Vibecoded** — This project was built almost entirely with the help of LLMs (large language models). The architecture, code structure, and documentation were all generated, iterated, and refined through AI-assisted development. It works well for its purpose, but like anything vibecoded, there may be edge cases, quirks, or assumptions baked in that a fully hand-crafted project might handle differently. Read the code with that in mind — and if something looks weird, it probably made sense to the model at 2am.

---

# SiteSiren — Developer Documentation

> A native macOS menu-bar utility that blocks distracting websites system-wide and plays a configurable audio alert the moment a blocked domain is accessed.

---

## Table of Contents

1. [What the App Does](#1-what-the-app-does)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Project Structure](#3-project-structure)
4. [Build System](#4-build-system)
5. [Targets & Frameworks](#5-targets--frameworks)
6. [Shared Layer — Code Used by Both Targets](#6-shared-layer--code-used-by-both-targets)
7. [SiteSiren Main App — Core Managers](#7-sitesiren-main-app--core-managers)
8. [SiteSiren Main App — UI Layer](#8-sitesiren-main-app--ui-layer)
9. [SiteSirenFilter — System Extension](#9-sitesirenfilter--system-extension)
10. [How Blocking Works — Two Modes](#10-how-blocking-works--two-modes)
11. [IPC — How the Two Processes Talk](#11-ipc--how-the-two-processes-talk)
12. [Data Flow — End to End](#12-data-flow--end-to-end)
13. [Persistence & Storage](#13-persistence--storage)
14. [Entitlements & Sandbox](#14-entitlements--sandbox)
15. [Unit Tests](#15-unit-tests)
16. [Logging & Diagnostics](#16-logging--diagnostics)
17. [Known Limitations](#17-known-limitations)

---

## 1. What the App Does

**SiteSiren** is a pure-native macOS app (no server, no cloud, no analytics) that:

- **Blocks websites system-wide** — not just inside one browser. It intercepts connections before they reach the network.
- **Plays an audio siren** the instant a blocked domain is hit. The sound, volume, playback style, and cooldown are all configurable.
- **Lives in the menu bar** as a small bell icon. It runs silently in the background even when the Settings window is closed.
- **Starts at login** via Apple's `SMAppService` (no LaunchDaemon, no root).
- **Is 100% local** — blocked domain list, events, and audio config all stay on the device.

---

## 2. High-Level Architecture

SiteSiren is made of **two processes** — a main UI app and a system extension — that communicate through two IPC channels.

```
┌──────────────────────────────────────────────────────────────────────┐
│                         macOS Host System                            │
│   Safari · Chrome · Firefox · Arc · Brave · Any App                 │
│                     (Outbound network traffic)                        │
└──────────────────────────────┬───────────────────────────────────────┘
                               │ HTTP / HTTPS connection
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  BLOCKING LAYER  (Personal Mode — PAC Proxy, no signing required)    │
│  ─────────────────────────────────────────────────────────────────   │
│  LocalFilterEngine (in-process, port 8282)                           │
│  • macOS routes traffic here via PAC script (networksetup)           │
│  • CONNECT (HTTPS) or GET/POST (HTTP) parsed per connection          │
│  • If host matches blocked list → HTTP 403 + onBlockDetected()       │
│  • If not matched → transparently forwards to real server            │
│                                                                      │
│  OR                                                                  │
│                                                                      │
│  SiteSirenFilter (NEFilterDataProvider System Extension)             │
│  • Intercepts at OS socket layer (needs paid Apple Dev account)      │
│  • handleNewFlow() / handleOutboundData() → .drop() or .allow()      │
│  • Posts Darwin notification + logs BlockEvent to shared container   │
└──────────────────────────────┬───────────────────────────────────────┘
                               │ Darwin IPC (sub-ms, kernel-level)
                               │ + Shared App Group files
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│               SiteSiren.app (Main App — Menu Bar Extra)              │
│                                                                      │
│  AppDelegate          — wires all managers at startup                │
│  ProtectionManager    — controls LocalFilterEngine lifecycle         │
│  BlockedDomainManager — domain list CRUD + persistence + export      │
│  AudioManager         — AVAudioPlayer + cooldown debounce            │
│  ActivityStore        — recent 100 block events (in-memory + disk)   │
│  AppSettings          — SMAppService launch-at-login                 │
│  MenuBarController    — NSStatusItem + NSPopover + Settings window   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. Project Structure

```
blissful-salk/
├── project.yml                  ← XcodeGen spec (single source of truth for project)
├── SiteSiren.xcodeproj          ← Generated by XcodeGen (do not edit manually)
│
├── Shared/                      ← Compiled into BOTH targets
│   ├── AppConstants.swift       ← All string identifiers, notification names, defaults
│   ├── DomainRule.swift         ← Domain model: normalization + subdomain matching
│   ├── BlockEvent.swift         ← Blocked-access event model (id, domain, timestamp, process)
│   ├── AudioConfig.swift        ← Audio preferences model (Codable)
│   ├── SharedStore.swift        ← Shared storage layer (App Group files + UserDefaults + Darwin IPC)
│   └── TLSInspector.swift       ← Zero-allocation raw TLS/HTTP packet parser for SNI and Host headers
│
├── SiteSiren/                   ← Main App target
│   ├── App/
│   │   ├── SiteSirenApp.swift   ← SwiftUI App entry point; wires AppDelegate
│   │   ├── AppDelegate.swift    ← Creates and connects all managers; owns MenuBarController
│   │   └── MenuBarController.swift ← NSStatusItem, NSPopover, settings window management
│   ├── Core/
│   │   ├── LocalFilterEngine.swift    ← PAC proxy server (NWListener on 127.0.0.1:8282)
│   │   ├── ProtectionManager.swift    ← ON/OFF control + Darwin listener for rule changes
│   │   ├── BlockedDomainManager.swift ← Add/remove/search/import/export domain rules
│   │   ├── AudioManager.swift         ← AVAudioPlayer + security-scoped bookmarks + cooldown
│   │   ├── ActivityStore.swift        ← In-memory store of last 100 block events
│   │   └── AppSettings.swift          ← SMAppService launch-at-login toggle
│   ├── UI/
│   │   ├── MenuBarPopoverView.swift       ← Quick-access popover (status, counts, quick actions)
│   │   ├── SettingsView.swift             ← TabView container for the 4-tab settings window
│   │   ├── ProtectionSectionView.swift    ← Tab 1: protection toggle, PAC info, launch-at-login
│   │   ├── BlockedSitesSectionView.swift  ← Tab 2: domain list, search, add, backup/restore
│   │   ├── AudioSectionView.swift         ← Tab 3: audio file, volume, loop, cooldown
│   │   ├── ActivitySectionView.swift      ← Tab 4: real-time block event log + test button
│   │   └── Components/
│   │       ├── StatusBadge.swift          ← Dynamic active/paused indicator badge
│   │       └── SetupGuideSheet.swift      ← In-app walkthrough for System Settings approval
│   └── Resources/
│       ├── Assets.xcassets        ← App icons and SF Symbols
│       ├── DefaultAudio.aiff      ← Bundled fallback alert sound
│       └── Info.plist             ← LSUIElement=true (hides from Dock), extension description
│
├── SiteSirenFilter/             ← Network Extension target (optional, paid dev account)
│   ├── main.swift               ← Calls NEProvider.startSystemExtensionMode()
│   ├── SiteSirenFilterDataProvider.swift ← NEFilterDataProvider subclass
│   ├── Info.plist               ← NEProviderClasses dict required by the OS
│   └── SiteSirenFilter.entitlements ← content-filter-provider + App Group entitlements
│
└── SiteSirenTests/              ← Unit test suite (22 tests, no network required)
    ├── DomainNormalizationTests.swift
    ├── DomainMatchingTests.swift
    ├── DuplicateDomainTests.swift
    ├── EventCooldownTests.swift
    ├── AudioConfigPersistenceTests.swift
    ├── SettingsPersistenceTests.swift
    └── TLSInspectorTests.swift
```

---

## 4. Build System

The project is defined in `project.yml` and uses **XcodeGen** to generate `SiteSiren.xcodeproj`. Never edit the `.xcodeproj` directly.

| Setting | Value |
|---|---|
| Minimum macOS | 14.0 (Sonoma) |
| Swift version | 5.0 |
| Xcode version | 16.0 |
| Bundle ID prefix | `com.personal` |
| Code signing style | Automatic |

**Common commands:**
```bash
# Regenerate .xcodeproj from project.yml
xcodegen generate

# Build
xcodebuild build -project SiteSiren.xcodeproj -scheme SiteSiren -destination "platform=macOS"

# Run all 22 unit tests (no signing needed)
xcodebuild test -project SiteSiren.xcodeproj -scheme SiteSiren \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## 5. Targets & Frameworks

### SiteSiren (Main App)

| Framework | Why it's used |
|---|---|
| `SwiftUI` | All UI views |
| `AppKit` | `NSStatusItem`, `NSPopover`, `NSSavePanel`, `NSSound` |
| `AVFoundation` | `AVAudioPlayer` for siren playback |
| `NetworkExtension` | `NEFilterManager` (for the optional paid-account mode) |
| `SystemExtensions` | `OSSystemExtensionManager` (install/uninstall NEFilter extension) |
| `ServiceManagement` | `SMAppService` for launch-at-login |
| `Network` | `NWListener`, `NWConnection` — the PAC proxy server |

### SiteSirenFilter (System Extension)

| Framework | Why it's used |
|---|---|
| `NetworkExtension` | `NEFilterDataProvider`, `NEFilterSettings` |
| `Network` | `NWHostEndpoint` for remote endpoint inspection |

---

## 6. Shared Layer — Code Used by Both Targets

All files in `Shared/` are compiled into both the main app and the system extension. They are the backbone of cross-process consistency.

### `AppConstants.swift`

A simple `enum` (no cases, used as namespace) holding all hardcoded strings:

- **Bundle IDs**: `com.personal.SiteSiren`, `com.personal.SiteSiren.filter`
- **App Group ID**: `group.com.personal.SiteSiren` (the shared sandbox container)
- **Darwin notification names** (two):
  - `com.personal.SiteSiren.domainBlocked` — filter → app: "I blocked something"
  - `com.personal.SiteSiren.rulesUpdated` — app → filter: "your rules list changed"
- **File names**: `blocked_domains.json`, `block_events.json`
- **UserDefaults keys**: `SiteSirenAudioConfig`, `SiteSirenProtectionEnabled`
- **Defaults**: cooldown 2.0 s, volume 1.0, max 100 history events

---

### `DomainRule.swift`

A `Codable`, `Identifiable`, `Hashable` struct representing a single blocked domain entry.

**Key behaviors:**

**`DomainRule.normalize(_ input: String) -> String?`**
Cleans any user-entered string into a canonical bare domain. Steps:
1. Lowercases and trims whitespace.
2. If the string contains `://` it's parsed as a URL; otherwise `https://` is prepended and then parsed.
3. Extracts the `host` component (drops scheme, path, query).
4. Strips port (`:443`, `:8080`, etc.).
5. Strips trailing dots (FQDN format).
6. Strips leading `www.`.
7. Validates: must contain `.`, no spaces, not start/end with `.`, at least 3 chars.

**Examples:**
```
"https://www.youtube.com/watch?v=abc" → "youtube.com"
"m.youtube.com"                       → "m.youtube.com"  (subdomain preserved)
"REDDIT.COM/"                         → "reddit.com"
"accounts.google.com:443"            → "accounts.google.com"
```

**`DomainRule.matches(candidate:ruleDomain:) -> Bool`**
Checks if a live connection target matches a blocked rule:
- Exact match: `youtube.com == youtube.com` → `true`
- Subdomain match: `music.youtube.com` ends with `.youtube.com` → `true`
- Not a substring match: `notyoutube.com` → `false`

---

### `BlockEvent.swift`

A `Codable`, `Identifiable` struct representing one blocked access attempt:

```swift
struct BlockEvent: Codable, Identifiable {
    let id: UUID
    let domain: String
    let timestamp: Date
    let processName: String?   // e.g. "Safari", "Chrome", "curl"
    let remoteAddress: String? // optional raw IP
}
```

---

### `AudioConfig.swift`

A `Codable` struct holding user audio preferences:

| Property | Type | Default | Meaning |
|---|---|---|---|
| `bookmarkData` | `Data?` | nil | Security-scoped bookmark to custom audio file |
| `customFileName` | `String?` | nil | Display name of custom file |
| `volume` | `Float` | 1.0 | Playback volume (0.0–1.0) |
| `loopAudio` | `Bool` | false | Whether to loop continuously |
| `cooldownSeconds` | `Double` | 2.0 | Minimum gap between audio triggers |

---

### `SharedStore.swift`

A singleton (`SharedStore.shared`) that is the **single source of truth for all persistent data**. Both the main app and the filter extension read/write here.

**Directory resolution:**
1. Tries `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` → the signed App Group shared container.
2. Falls back to `~/Library/Application Support/SiteSiren/` for local/unsigned development.

**What it stores:**

| Data | Storage | File / Key |
|---|---|---|
| Blocked domain rules | JSON file | `blocked_domains.json` |
| Block event history | JSON file | `block_events.json` (capped at 100 entries) |
| Audio config | `UserDefaults` (App Group suite) | `SiteSirenAudioConfig` |
| Protection on/off | `UserDefaults` | `SiteSirenProtectionEnabled` |

All file writes use `queue.sync` on a private serial `DispatchQueue` with `.atomic` write option to prevent race conditions between processes.

**Darwin Notification helpers:**
```swift
SharedStore.postBlockEventOccurred()  // filter → app
SharedStore.postRulesUpdated()        // app → filter
```
These use `CFNotificationCenterGetDarwinNotifyCenter()` — a kernel-level IPC channel that crosses the sandbox boundary between the system extension and the main app.

---

### `TLSInspector.swift`

A stateless enum with zero-allocation byte-level parsers. Used by the NEFilter extension to inspect raw outbound packets.

**`TLSInspector.extractSNI(from data: Data) -> String?`**
Manually walks a TLS 1.x `ClientHello` record byte-by-byte:
- Verifies `data[0] == 0x16` (Handshake record) and `data[5] == 0x01` (ClientHello type).
- Skips version, random, session ID, cipher suites, compression methods.
- Walks extensions list looking for type `0x0000` (server_name).
- Extracts the `host_name` entry (NameType 0) and decodes it as UTF-8.

This extracts the destination hostname from HTTPS traffic **without decrypting anything** — no MITM, no root CA injection.

**`TLSInspector.extractHTTPHost(from data: Data) -> String?`**
For plain HTTP: reads up to 1024 bytes as ASCII, confirms it starts with a valid HTTP method, then scans lines for a `Host:` header and returns the value.

**`TLSInspector.extractHostname(from data: Data) -> String?`**
Tries SNI first, falls back to HTTP Host.

---

## 7. SiteSiren Main App — Core Managers

### `AppDelegate.swift`

The root object of the app. Created by `SiteSirenApp.swift` using `@NSApplicationDelegateAdaptor`.

**What it does at launch:**
1. Creates instances of all 5 managers: `ProtectionManager`, `BlockedDomainManager`, `AudioManager`, `AppSettings`, `ActivityStore`.
2. Wires cross-dependencies:
   - `protectionManager.audioManager = audioManager` (so the filter can trigger sound)
   - `protectionManager.activityStore = activityStore` (so the filter can update the log)
   - `domainManager.onRulesUpdated = { protectionManager.refreshPAC() }` (so adding a domain instantly updates the PAC script)
3. Creates `MenuBarController` and passes all managers into it.

`applicationShouldTerminateAfterLastWindowClosed` returns `false` — the app stays alive as a menu bar agent when the settings window is closed.

`applicationWillTerminate` calls `protectionManager.shutdown()` to disable the PAC proxy cleanly before exit.

---

### `LocalFilterEngine.swift`

> **This is the default blocking mechanism** — works with a free Apple ID, no paid developer account needed.

A full **HTTP/HTTPS proxy server** that runs locally on `127.0.0.1:8282` and is registered with macOS as the system PAC (Proxy Auto-Configuration) server.

**How it works:**

1. **PAC Script Registration** — on `start()`, `LocalFilterEngine` calls `networksetup -setautoproxyurl <service> http://127.0.0.1:8282/proxy.pac` for every active network interface (Wi-Fi, Ethernet, etc.). macOS now routes all browser and app connections through this server first.

2. **Dynamic PAC Script Serving** — when the browser requests `http://127.0.0.1:8282/proxy.pac`, the engine generates a JavaScript PAC function on-the-fly:
   ```javascript
   function FindProxyForURL(url, host) {
       var blocked = ["youtube.com", "reddit.com", ...];
       var h = (host || "").toLowerCase();
       for (var i = 0; i < blocked.length; i++) {
           var d = blocked[i].toLowerCase();
           if (h === d || (h.length > d.length && h.slice(-d.length - 1) === ("." + d))) {
               return "PROXY 127.0.0.1:8282";  // blocked → route through our proxy
           }
       }
       return "DIRECT";  // not blocked → go normally
   }
   ```
   The PAC URL includes a timestamp query param (e.g. `?v=1726829183`) so browsers cannot cache a stale version.

3. **Connection Handling** — connections routed to the proxy by the PAC function:
   - **HTTPS (`CONNECT` method)**: The browser sends `CONNECT youtube.com:443 HTTP/1.1`. The engine extracts the host, checks against the in-memory domain rule cache. If blocked → responds `HTTP 403 Forbidden`. If allowed → establishes a real TCP connection to the target and **bidirectionally pipes data** between client and server (acting as a transparent tunnel; TLS remains end-to-end encrypted).
   - **HTTP (GET/POST/etc.)**: Extracts `Host` header or parses the target URL. If blocked → `403`. If allowed → forwards the full request.

4. **In-memory domain cache** — `cachedRules: [DomainRule]` is loaded from disk via `SharedStore` at startup and on every `refreshPAC()` call. Per-connection matching uses only this in-memory array — no disk I/O per request.

5. **PAC Refresh** — `refreshPAC()` reloads the in-memory cache, generates a new timestamped PAC URL, then does a `off → on` toggle of the proxy setting to force all browsers to immediately re-fetch the PAC file and flush their connection pools.

6. **Cleanup on stop** — `disableSystemPAC()` calls `networksetup -setautoproxystate <service> off` for all interfaces.

---

### `ProtectionManager.swift`

An `@MainActor ObservableObject` that is the on/off switch for the entire protection system.

**State:**
- `isProtectionEnabled: Bool` — persisted in `SharedStore` / `UserDefaults`.
- `status: FilterExtensionStatus` — `.active` or `.paused`. Drives the `StatusBadge` UI.

**Key methods:**
- `enableProtection()` → calls `localFilter.start()`, updates status, persists state, posts `rulesUpdated` Darwin notification.
- `disableProtection()` → calls `localFilter.stop()`, same sync.
- `toggleProtection()` → calls one of the above.
- `refreshPAC()` → delegates to `localFilter.refreshPAC()`.
- `simulateBlock(domain:)` → creates a fake `BlockEvent` and triggers `audioManager.handleBlockEvent()` — useful for testing the siren from the Activity tab.

**Darwin observer:** Listens for `rulesUpdated` notifications. This means if a future companion CLI tool writes new domain rules to `SharedStore`, `ProtectionManager` will pick them up automatically without restarting.

---

### `BlockedDomainManager.swift`

An `@MainActor ObservableObject` managing the list of blocked domains.

**State:**
- `blockedDomains: [DomainRule]` — the full list, published for SwiftUI.
- `searchText: String` — drives `filteredDomains` computed property (live search).
- `errorMessage: String?` — displayed inline in the UI on validation failures.

**Key methods:**

| Method | What it does |
|---|---|
| `addDomain(_ rawInput)` | Normalizes via `DomainRule.normalize()`, rejects duplicates, appends to list, saves + syncs |
| `removeDomain(_ rule)` | Removes by UUID, saves + syncs |
| `exportAsJSON()` | Encodes `[DomainRule]` as pretty-printed JSON string |
| `exportAsText()` | Returns newline-separated domain strings |
| `importFromText(_ content)` | Splits by newline, calls `addDomain` per line, returns `(added, skipped)` |
| `importFromJSON(_ jsonString)` | Decodes `[DomainRule]`, calls `addDomain` per entry |

After every mutation, `saveAndSync()` calls:
1. `SharedStore.shared.saveBlockedDomains(blockedDomains)` — persists to disk.
2. `SharedStore.postRulesUpdated()` — Darwin notification to filter extension.
3. `onRulesUpdated?()` — callback to `ProtectionManager.refreshPAC()`.

---

### `AudioManager.swift`

An `@MainActor ObservableObject, AVAudioPlayerDelegate` that handles all sound playback.

**State:**
- `config: AudioConfig` — loaded from `SharedStore` at init.
- `isPlaying: Bool` — drives the "Stop Playing" button in popover and Settings.
- `audioStatusMessage: String?` — shows "Audio file unavailable" warning when file is missing.

**Audio file resolution:**
`resolveAudioURL()` tries:
1. Resolve the security-scoped bookmark (`config.bookmarkData`) to get the user's custom file. Re-saves a fresh bookmark if the existing one is stale.
2. Falls back to the bundled `DefaultAudio.aiff` in the app bundle.

If neither is available, the app falls back to `NSSound.beep()`.

**Security-scoped bookmarks** are how a sandboxed app remembers access to a file the user chose even after restart. When the user picks a file, `url.bookmarkData(options: .withSecurityScope)` is called and the raw `Data` is stored in `AudioConfig`. On playback, `URL(resolvingBookmarkData:options:.withSecurityScope)` re-derives the URL and `url.startAccessingSecurityScopedResource()` re-opens the sandbox permission.

**Cooldown/debouncing:**
```swift
func handleBlockEvent(domain: String) {
    let elapsed = Date().timeIntervalSince(lastTriggerTime)
    if elapsed < config.cooldownSeconds { return }   // suppress
    lastTriggerTime = Date()
    playAlert(isUserPreview: false)
}
```
Multiple blocked sub-resources on a single page load (images, scripts, APIs) all arrive within milliseconds. Without debouncing, the siren would play 20+ times per page. The cooldown (default 2 seconds, configurable 0.5–10 s) ensures it plays once per "burst".

---

### `ActivityStore.swift`

A lightweight `@MainActor ObservableObject` that keeps the last 100 `BlockEvent`s in memory for the Activity tab.

- `events: [BlockEvent]` — published, loaded from `SharedStore` on `refresh()`.
- `refresh()` — re-reads from `SharedStore.loadBlockEvents()`.
- `clearHistory()` — deletes events from both memory and disk via `SharedStore.clearBlockEvents()`.

---

### `AppSettings.swift`

An `@MainActor ObservableObject` wrapping Apple's `SMAppService` for **launch at login**.

- `launchAtLogin: Bool` — `@Published`. Setting it to `true` calls `SMAppService.mainApp.register()`. Setting it to `false` calls `SMAppService.mainApp.unregister()`.
- The current state is loaded from `SMAppService.mainApp.status` at init.

---

## 8. SiteSiren Main App — UI Layer

All UI is written in **SwiftUI** and uses `@ObservedObject` bindings into the five core managers.

### Entry Point & Window Management

**`SiteSirenApp.swift`**
A `@main SwiftUI App` that uses `@NSApplicationDelegateAdaptor(AppDelegate.self)` to bridge AppKit. It renders an empty `Settings {}` body because the actual UI is created imperatively by `MenuBarController`.

**`MenuBarController.swift`**
Owns the `NSStatusItem` (the bell icon in the menu bar) and the `NSPopover`.
- On click, toggles the popover open/closed.
- On "Manage Blocked Sites" / "Settings" button press in the popover, opens the settings `NSWindow` with a specific `SettingsTab` pre-selected.
- `LSUIElement = true` in `Info.plist` hides the app from the Dock and App Switcher.
- Observes `audioManager.$isPlaying` via Combine to swap the menu bar icon between `bell.badge.fill` and `speaker.wave.3.fill` while audio is playing.

---

### Settings Window — 4 Tabs

**`SettingsView.swift`**
A `TabView` container. The `SettingsTab` enum defines the four tabs:

| Tab | Enum case | Icon |
|---|---|---|
| Protection | `.protection` | `shield.lefthalf.filled` |
| Blocked Websites | `.blockedSites` | `network.badge.shield.half.filled` |
| Audio | `.audio` | `speaker.wave.3.fill` |
| Activity | `.activity` | `clock.arrow.circlepath` |

The selected tab is a `@Binding<SettingsTab>` so `MenuBarController` can deep-link to a specific tab.

---

**`ProtectionSectionView.swift`** — Tab 1

- Shows current protection status and `StatusBadge`.
- A `Toggle` that calls `protectionManager.toggleProtection()`.
- An informational section explaining the PAC proxy approach.
- A `Toggle` for launch at login bound to `appSettings.launchAtLogin`.

---

**`BlockedSitesSectionView.swift`** — Tab 2

- A live `TextField` search bar bound to `domainManager.searchText`. The list updates automatically via `domainManager.filteredDomains`.
- A `Menu` button for Backup/Restore (export JSON, export plain text, import from file via `NSOpenPanel` / `NSSavePanel`).
- A `List` showing each `DomainRule` with a Remove button.
- An add-domain `TextField` + "Add Website" button that calls `domainManager.addDomain()`.

---

**`AudioSectionView.swift`** — Tab 3

- Shows the current audio file name.
- "Preview" / "Stop" button.
- "Choose Audio File..." opens `NSOpenPanel` filtering for audio/video types (MP3, M4A, MP4, WAV, AIFF, AAC, MOV).
- "Reset to Default Siren" clears `config.bookmarkData`.
- Volume `Slider` (0–100%), Playback Mode radio group (Play Once / Loop), Cooldown `Slider` (0.5–10.0 s in 0.5 steps).

---

**`ActivitySectionView.swift`** — Tab 4

- Shows a time-stamped list of the last 100 blocked connection events (domain, time, process name).
- "Test Siren Alert" button calls `protectionManager.simulateBlock(domain:)` — lets you verify audio without actually visiting a blocked site.
- "Clear History" button calls `activityStore.clearHistory()`.

---

### `MenuBarPopoverView.swift`

A compact `280 pt` wide popover that appears on clicking the status bar icon. Shows:
- App name + `StatusBadge`.
- Number of blocked sites and current audio file name.
- A red "Stop Playing Audio" button if `audioManager.isPlaying`.
- Quick-action buttons: Manage Blocked Sites, Choose Audio, Settings, Pause/Resume Protection, Quit.

---

## 9. SiteSirenFilter — System Extension

> **Optional.** Only available with a paid Apple Developer account ($99/year). The default app mode uses `LocalFilterEngine` instead and does not require this target.

### `main.swift`

```swift
NEProvider.startSystemExtensionMode()
```
The entire entry point. The OS loads this binary into a restricted sandbox and calls into `SiteSirenFilterDataProvider`.

### `SiteSirenFilterDataProvider.swift`

Subclasses `NEFilterDataProvider`, which is called by the macOS kernel for every outbound network socket.

**Startup (`startFilter`):**
1. `reloadRules()` — reads `isProtectionEnabled` and `blockedDomains` from `SharedStore`.
2. `registerDarwinObserver()` — listens for `rulesUpdated` Darwin notifications; calls `reloadRules()` when received.
3. Applies `NEFilterSettings(rules: [], defaultAction: .filterData)` — tells the OS: "send every flow to me for inspection".

**Per-connection: `handleNewFlow(_ flow)`**
1. Checks if flow metadata already has a hostname (URL, `remoteHostname`, or `NWHostEndpoint`).
2. If yes — check against `blockedRules`. If blocked → `.drop()`. If allowed → `.allow()`.
3. If hostname is not yet known (raw TCP to port 80/443) → returns `.filterDataVerdict(peekOutboundBytes: 1024)` to request the first 1 KB of outbound data.

**Per-packet: `handleOutboundData(from flow, readBytes)`**
1. Passes `readBytes` to `TLSInspector.extractHostname()` to get SNI (HTTPS) or Host header (HTTP).
2. Checks against rules. Block or allow.
3. If no hostname found yet and offset < 2048, peeks another 1 KB.

**`handleBlockedFlow`:**
1. Extracts the process name from the flow's `audit_token_t` via `proc_name()`.
2. Creates a `BlockEvent` and writes it to `SharedStore.recordBlockEvent()`.
3. Posts `SharedStore.postBlockEventOccurred()` → Darwin notification → main app wakes up, plays audio, refreshes activity list.

**Thread safety:** `blockedRules` and `isFilterActive` are protected by `NSLock` (`rulesLock`). Darwin callback arrives on an arbitrary thread; `reloadRules()` acquires the lock before reading from `SharedStore`.

---

## 10. How Blocking Works — Two Modes

| | Personal Mode (Default, Free) | Network Extension Mode (Paid) |
|---|---|---|
| **Mechanism** | PAC proxy via `LocalFilterEngine` | `NEFilterDataProvider` (kernel socket intercept) |
| **Developer account** | Free personal Apple ID | Paid Apple Developer Program ($99/year) |
| **How traffic is intercepted** | macOS routes traffic through `127.0.0.1:8282` per PAC instructions | OS calls the extension for every socket before connection |
| **HTTPS inspection** | Host extracted from CONNECT tunnel header (domain visible, content encrypted) | TLS SNI parsed from ClientHello (no decryption) |
| **Privacy** | Zero MITM, zero decryption | Zero MITM, zero decryption |
| **Block response** | HTTP 403 returned to browser | `.drop()` verdict; TCP connection dropped |
| **Limitation** | Browser extensions that override system proxy (some VPNs) may bypass | Encrypted Client Hello (ECH) can hide SNI |

---

## 11. IPC — How the Two Processes Talk

The main app and the filter extension run in separate sandboxes. They communicate through two mechanisms:

### Shared App Group Container

Filesystem directory accessible to both processes via `FileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.personal.SiteSiren")`. This is where `blocked_domains.json` and `block_events.json` live.

Both processes use `SharedStore.shared` (the same singleton code compiled into both targets) to read and write these files, protected by a serial `DispatchQueue`.

### Darwin Notifications (Kernel IPC)

`CFNotificationCenterGetDarwinNotifyCenter()` is a system-wide notification bus that crosses sandbox/process boundaries instantly (sub-millisecond). Used for two signals:

| Notification | Direction | Trigger |
|---|---|---|
| `com.personal.SiteSiren.domainBlocked` | Filter → App | A blocked domain was hit; app plays audio and refreshes activity |
| `com.personal.SiteSiren.rulesUpdated` | App → Filter | Domain list changed; filter reloads its in-memory rules |

No data is carried in the notification itself — both processes then read/write the shared file store for the actual data.

---

## 12. Data Flow — End to End

Here is what happens from the moment the user visits a blocked site to the audio playing:

```
1. Browser opens youtube.com
   ↓
2. macOS consults PAC script at http://127.0.0.1:8282/proxy.pac
   → script returns "PROXY 127.0.0.1:8282"
   ↓
3. Browser sends CONNECT youtube.com:443 to LocalFilterEngine
   ↓
4. LocalFilterEngine.processInitialRequest()
   - Reads cachedRules (in-memory, no disk I/O)
   - DomainRule.matches("youtube.com", "youtube.com") → true
   ↓
5. LocalFilterEngine.handleBlockedRequest()
   - Responds HTTP 403 to browser
   - Calls onBlockDetected?("youtube.com") on main thread
   ↓
6. ProtectionManager receives onBlockDetected
   - Creates BlockEvent, writes to SharedStore (disk)
   - Calls audioManager.handleBlockEvent("youtube.com")
   - Calls activityStore.refresh()
   ↓
7. AudioManager.handleBlockEvent()
   - Checks cooldown: Date() - lastTriggerTime >= cooldownSeconds?
   - If yes: resolveAudioURL() → security-scoped bookmark or DefaultAudio.aiff
   - AVAudioPlayer.play() → siren sounds
   ↓
8. ActivityStore.refresh()
   - Reloads BlockEvent list from SharedStore
   - SwiftUI Activity tab updates live via @Published
```

---

## 13. Persistence & Storage

| What | Where | Format | Access |
|---|---|---|---|
| Blocked domain rules | App Group container / `~/Library/Application Support/SiteSiren/` | `blocked_domains.json` (JSON array of `DomainRule`) | Both targets via `SharedStore` |
| Block event history | Same directory | `block_events.json` (JSON array of `BlockEvent`, max 100) | Both targets via `SharedStore` |
| Audio config | App Group `UserDefaults` suite | `SiteSirenAudioConfig` key, JSON-encoded `AudioConfig` | Main app only |
| Protection on/off | App Group `UserDefaults` suite | `SiteSirenProtectionEnabled` key, Bool | Both targets |
| Custom audio file path | Inside `AudioConfig.bookmarkData` (stored in UserDefaults) | Security-scoped `Data` bookmark | Main app only |

---

## 14. Entitlements & Sandbox

### Main App (`SiteSiren.entitlements`)

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | Required for Mac App Store / notarization |
| `com.apple.security.network.client` | Outbound TCP connections (the PAC proxy forward path) |
| `com.apple.security.network.server` | NWListener on port 8282 |
| `com.apple.security.files.user-selected.read-only` | Access to user-picked audio files before bookmark is created |

### Filter Extension (`SiteSirenFilter.entitlements`)

| Entitlement | Why |
|---|---|
| `com.apple.developer.networking.networkextension` with `content-filter-provider` | Required to subclass `NEFilterDataProvider` |
| `com.apple.security.application-groups` | Access to the shared App Group container |

Both targets have `ENABLE_HARDENED_RUNTIME = YES` set in `project.yml`, required for notarization.

---

## 15. Unit Tests

The test suite in `SiteSirenTests/` covers 7 areas and 22+ test cases. All tests run offline with no signing.

| Test file | What it tests |
|---|---|
| `DomainNormalizationTests` | `DomainRule.normalize()`: URL schemes, trailing slashes, `www.` stripping, port stripping, FQDN dots |
| `DomainMatchingTests` | `DomainRule.matches()`: subdomain matching, exact match, boundary conditions (`notyoutube.com` does not match `youtube.com`) |
| `DuplicateDomainTests` | `BlockedDomainManager.addDomain()` rejects duplicates and returns `.failure(.duplicateDomain)` |
| `EventCooldownTests` | `AudioManager.handleBlockEvent()` suppresses repeated triggers within `cooldownSeconds` |
| `AudioConfigPersistenceTests` | `AudioConfig` encodes/decodes correctly via `JSONCodable`; `SharedStore` round-trips it via `UserDefaults` |
| `SettingsPersistenceTests` | `SharedStore` saves and loads `[DomainRule]` correctly; event list is capped at 100 |
| `TLSInspectorTests` | `TLSInspector.extractSNI()` correctly parses crafted TLS ClientHello bytes; `extractHTTPHost()` extracts correct Host header |

**Run command:**
```bash
xcodebuild test -project SiteSiren.xcodeproj -scheme SiteSiren \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

---

## 16. Logging & Diagnostics

All components log to macOS Unified Logging via `os.Logger`:

| Component | Subsystem | Category |
|---|---|---|
| Main app | `com.personal.SiteSiren` | `AppDelegate`, `ProtectionManager`, `BlockedDomainManager`, `AudioManager`, `LocalFilterEngine`, `SharedStore` |
| Filter extension | `com.personal.SiteSiren.filter` | `FilterDataProvider` |

**View live logs:**
```bash
log stream --predicate 'subsystem CONTAINS "com.personal.SiteSiren"' --info --debug
```

Block events are logged at `.notice` level, including the matched domain, rule, and process name.

---

## 17. Known Limitations

| Issue | Why it happens | Impact |
|---|---|---|
| **Encrypted Client Hello (ECH)** | When both browser and server support ECH, the TLS SNI is itself encrypted using a pre-fetched HTTPS DNS record. The plain SNI is unavailable. | The NEFilter extension cannot extract the domain; blocking requires IP-level filtering. PAC mode is unaffected (uses CONNECT host header). |
| **Browser proxy-override extensions** | Some Chrome/Firefox extensions (certain VPN extensions) set their own proxy and bypass the system PAC entirely. | In PAC mode only, those extensions can bypass SiteSiren. NEFilter mode is not affected (operates at the OS socket layer). |
| **In-flight HTTP/2 or HTTP/3 connections** | If a connection to a blocked domain was established before the domain was added to the list, the existing open socket continues. | Only new connections are blocked. Refresh or reopen the browser tab to trigger a new socket. |
| **Full-tunnel VPN ordering** | A full-tunnel VPN may capture traffic into its virtual adapter before the system proxy or network extension applies. | Traffic may bypass SiteSiren while the VPN is active. In `System Settings → Network → Filters`, ensure SiteSiren is ordered above conflicting filters. |
| **Privacy guarantee** | SiteSiren does not install root CA certificates and does not decrypt HTTPS traffic. It only inspects the domain name from the CONNECT tunnel or TLS SNI. | Secure banking, passwords, and HTTPS payload remain strictly confidential and uninspected. |
