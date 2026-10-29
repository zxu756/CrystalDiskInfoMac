# CrystalDiskInfo Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS CrystalDiskInfo-style disk-health product using SwiftUI and the installed `smartctl` JSON backend.

**Architecture:** A SwiftUI app owns the disk list, health/temperature/life cards, identity grid, SMART table, history chart, menu-bar extra, notifications, and settings. A core module discovers physical disks with `diskutil`, runs `smartctl -j -a` as a subprocess, maps the JSON into a domain model, evaluates health, and stores history. v1 uses Homebrew `smartmontools`; `smartctl` is not bundled.

**Tech Stack:** Swift 6.4, SwiftUI, Swift Charts, MenuBarExtra, UserNotifications, ServiceManagement, SwiftPM, Swift Testing, macOS 27 arm64, ad-hoc signing.

**Spec:** `/Users/xu/Projects/CrystalDiskInfoMac/docs/superpowers/specs/2026-10-29-crystaldiskinfo-mac-design.md`

## Global Constraints

- Platform: macOS 27.0+, arm64 only. No Intel, universal, App Store, notarization, or auto-update.
- Build: Command Line Tools only; SwiftPM + `build-app.sh`; no `xcodebuild`, no `.xcodeproj`.
- App: `CrystalDiskInfo Mac`, bundle id `local.xu.CrystalDiskInfoMac`, version `0.1.0`, non-sandboxed, ad-hoc signed.
- SMART backend: `smartctl` from Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, then `PATH`); minimum 7.4. Do not bundle smartctl in v1.
- SMART exit semantics: usable JSON with identity + SMART payload is parsed even when smartctl exits nonzero (disk0 exits 4). Exit bits/messages are diagnostics, not automatic failure.
- Health: compute all signals, then `Bad > Caution > Unknown > Good`. NVMe critical warning => Bad; spare below threshold => Bad; spare equal threshold (threshold != 100) => Caution; media errors => Caution; percentage used >=90 Caution, >=100 Bad.
- Temperature: drive-reported warning/critical limits by default; global 50/60 fallback; “Use drive-reported limits” toggle off makes global values authoritative.
- History: 30 days, hard cap 100,000 samples per disk; missing samples are gaps.
- Notifications: transition-based; Unknown/removal only after two consecutive failed refreshes; no first-launch notification for a pre-existing Bad state.
- UI: native 960×640 main window, no bitmap scaling; one dark/light adaptive theme, English UI.
- Non-goals: AAM/APM, RAID, USB RAID/vendor quirks, raw writes, privileged helper, themes, languages, sound.
- App code MIT; smartctl is GPLv2 and remains a separate user-installed executable.

## Review Focus

1. **Nonzero smartctl exit with usable JSON:** disk0 must appear with health/temperature/SMART data even though smartctl exits 4; only open failure, timeout, or unparseable JSON is Unknown.
2. **Health precedence:** critical warning/spare/media/percentage/temperature signals must combine by maximum severity; tests must pin the order.
3. **Temperature limits:** drive-reported limits, global fallback, and the override toggle must produce the displayed/notified effective thresholds.
4. **Missing smartctl / permission failure:** clear setup or permission guidance, no fabricated healthy values, no missing disk silently.
5. **History and notifications:** 30-day history at 1-minute refresh is not truncated; Unknown/removal notifications do not spam on first launch or transient failures.

## File Structure

```
CrystalDiskInfoMac/
├── Package.swift
├── Sources/
│   ├── CrystalDiskInfoMac/
│   │   └── CrystalDiskInfoMacApp.swift
│   ├── CrystalDiskInfoMacCore/
│   │   ├── Models/
│   │   │   ├── SmartctlModels.swift
│   │   │   ├── DiskInfo.swift
│   │   │   ├── HealthStatus.swift
│   │   │   ├── AppSettings.swift
│   │   │   └── HistorySample.swift
│   │   ├── Services/
│   │   │   ├── SmartctlRunner.swift
│   │   │   ├── DiskutilLister.swift
│   │   │   ├── DiskScanner.swift
│   │   │   ├── DiskMapper.swift
│   │   │   ├── HealthEvaluator.swift
│   │   │   ├── HistoryStore.swift
│   │   │   ├── NotificationService.swift
│   │   │   ├── NotificationPolicy.swift
│   │   │   └── SettingsStore.swift
│   │   ├── ViewModels/
│   │   │   └── DiskMonitor.swift
│   │   ├── Theme.swift
│   │   └── Views/
│   │       ├── MainView.swift
│   │       ├── DiskSelectorView.swift
│   │       ├── StatusCardsView.swift
│   │       ├── IdentityGridView.swift
│   │       ├── SmartTableView.swift
│   │       ├── HistoryChartView.swift
│   │       ├── SettingsView.swift
│   │       ├── SmartctlSetupView.swift
│   │       ├── MenuBarView.swift
│   │       └── AboutView.swift
├── Tests/
│   ├── CrystalDiskInfoMacCoreTests/
│   └── Fixtures/
│       ├── disk0-apple-nvme.json
│       ├── disk4-intel-nvme.json
│       └── diskutil-list.plist
├── Scripts/
│   ├── Info.plist
│   ├── build-app.sh
│   └── make-icon.swift
├── Resources/
│   └── AppIcon.icns
├── docs/
│   ├── superpowers/specs/2026-10-29-crystaldiskinfo-mac-design.md
│   ├── superpowers/plans/2026-10-29-crystaldiskinfo-mac.md
│   └── reference/rea-cdi-audit.md
├── LICENSE
├── NOTICE
├── README.md
└── .gitignore
```

---

### Task 1: Scaffold the app, bundle, and blank window

**Files:**
- Create: `Package.swift`
- Create: `Sources/CrystalDiskInfoMac/CrystalDiskInfoMacApp.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Views/MainView.swift` (placeholder)
- Create: `Sources/CrystalDiskInfoMacCore/Models/HealthStatus.swift`
- Create: `Scripts/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `.gitignore`, `LICENSE`, `NOTICE`, `README.md`
- Create: `Tests/CrystalDiskInfoMacCoreTests/ViewRenderTests.swift`

**Interfaces:**
- Produces: `CrystalDiskInfoMacCore` library, `CrystalDiskInfoMac` executable, `MainView()` placeholder, `HealthStatus`.
- Produces: `build-app.sh` assembling `build/CrystalDiskInfoMac.app`.

- [ ] **Step 1: Init repo and directories**

```bash
cd /Users/xu/Projects/CrystalDiskInfoMac
git init -b main
mkdir -p Sources/CrystalDiskInfoMac Sources/CrystalDiskInfoMacCore/{Models,Services,ViewModels,Views} Tests/CrystalDiskInfoMacCoreTests Tests/Fixtures Scripts Resources docs/reference
```

- [ ] **Step 2: Write `Package.swift`**

Use `swift-tools-version: 6.0`, `platforms: [.macOS("27.0")]`, `swiftLanguageModes: [.v5]`, library `CrystalDiskInfoMacCore`, executable `CrystalDiskInfoMac`, test target. Add the same CLT Swift Testing macros plugin workaround used by CrystalDiskMark Mac (`-load-plugin-library` for `libTestingMacros.dylib` when present).

- [ ] **Step 3: Add `HealthStatus`**

```swift
public enum HealthStatus: String, Codable, CaseIterable, Sendable {
    case good, caution, bad, unknown
}
```

- [ ] **Step 4: Placeholder window**

`MainView()` (temporary placeholder) is a 960×640 dark rectangle with `CrystalDiskInfo Mac`; Task 9 replaces it with `MainView(model:)`. `CrystalDiskInfoMacApp` uses `@main`, `WindowGroup`, `.defaultSize(width: 960, height: 640)`, `.windowResizability(.contentSize)`.

- [ ] **Step 5: `Info.plist` and `build-app.sh`**

Bundle metadata: id `local.xu.CrystalDiskInfoMac`, name, executable, version 0.1.0, `LSMinimumSystemVersion` 27.0, `NSHighResolutionCapable`, `NSRemovableVolumesUsageDescription`, copyright/attribution. Script checks arm64, builds release arm64, assembles `.app`, copies icon if present, signs app, verifies.

- [ ] **Step 6: Verify**

```bash
swift build
Scripts/build-app.sh
open build/CrystalDiskInfoMac.app
```

Expected: 960×640 dark window titled `CrystalDiskInfo Mac`.

- [ ] **Step 7: Commit**

```bash
git add .
git commit -m "chore: scaffold CrystalDiskInfo Mac app"
```

---

### Task 2: Reference audit, fixtures, and REA evidence

**Files:**
- Create: `docs/reference/rea-cdi-audit.md`
- Create: `Tests/Fixtures/disk0-apple-nvme.json`
- Create: `Tests/Fixtures/disk4-intel-nvme.json`
- Create: `Tests/Fixtures/diskutil-list.plist`

**Interfaces:**
- Produces: committed JSON fixtures for both NVMe drives, with serials redacted.
- Produces: a reference note mapping CDI attribute names/health rules to the Mac rules.

- [ ] **Step 1: Capture real smartctl JSON**

```bash
smartctl -j -a /dev/disk0 > /tmp/disk0.json
smartctl -j -a /dev/disk4 > /tmp/disk4.json
cp /tmp/disk0.json Tests/Fixtures/disk0-apple-nvme.json
cp /tmp/disk4.json Tests/Fixtures/disk4-intel-nvme.json
/usr/sbin/diskutil list -plist > Tests/Fixtures/diskutil-list.plist
```

Redact serial numbers in the JSON fixtures (`"serial_number": "REDACTED"`); keep model names, status, NVMe log, and exit status. Verify disk0 fixture contains `"exit_status": 4` and a complete `nvme_smart_health_information_log`.

- [ ] **Step 2: REA/source audit**

Use REA on the official Windows `DiskInfo.exe` if downloadable from Crystal Dew World or the local source tree if the binary is available: native strings/attribute labels, health status strings, temperature/life rules. If no binary is available, audit `AtaSmart.cpp`, `NVMeInterpreter.cpp`, and `DiskInfoDlgUpdate.cpp` directly. Record in `rea-cdi-audit.md`:
- NVMe attribute IDs/names (1–17+ sensors)
- ATA attribute IDs used for life/health
- critical-warning/spare/percentage/temperature rules
- UI labels and info fields
- any Mac divergence (health precedence, temperature policy, unsupported RAID/AAM)

- [ ] **Step 3: Verify fixtures are parseable**

```bash
swift -e 'import Foundation; for p in ["Tests/Fixtures/disk0-apple-nvme.json","Tests/Fixtures/disk4-intel-nvme.json"] { let d = try Data(contentsOf: URL(fileURLWithPath:p)); _ = try JSONSerialization.jsonObject(with:d); print("ok", p) }'
```

- [ ] **Step 4: Commit**

```bash
git add docs/reference Tests/Fixtures
git commit -m "docs: add CDI reference audit and SMART fixtures"
```

---

### Task 3: Smartctl JSON models and decoder

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Models/SmartctlModels.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/SmartctlModelsTests.swift`

**Interfaces:**
- Produces: `SmartctlReport`, `SmartctlDevice`, `SmartctlCapacity`, `SmartctlStatus`, `SmartctlTemperature`, `SmartctlPowerOnTime`, `SmartctlMeta`, `NVMeSmartLog`, `AtaSmartAttributes`, `AtaSmartAttribute`.
- Produces: `SmartctlReport.decode(_ data: Data) throws`.
- Fields use snake_case JSON keys with explicit `CodingKeys`; missing optional fields are `nil`.

- [ ] **Step 1: Write failing tests**

Cover:
- both fixtures decode; disk0 model `APPLE SSD AP0256Z`; disk4 model `INTEL SSDPEKNW512G8`;
- disk0 `smartctl.exitStatus == 4`, `smartStatus.passed == true`, `nvme.temperature == 34`, `percentageUsed == 5`, `powerOnHours == 1695`;
- disk4 `temperature.current == 42`, `opLimitMax == 77`, `criticalLimitMax == 80`, `percentageUsed == 3`;
- absent ATA table is `nil`, not an error;
- malformed JSON throws.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter SmartctlModelsTests` → FAIL (types missing).

- [ ] **Step 3: Implement models**

Define the top-level `smartctl` metadata with `exit_status`/`messages`, `device`, `model_name`, `serial_number`, `firmware_version`, `user_capacity.bytes`, `rotation_rate`, `smart_status.passed`, `temperature.current/op_limit_max/critical_limit_max`, `power_on_time.hours`, `power_cycle_count`, `nvme_smart_health_information_log`, `ata_smart_attributes.table`, and ATA raw/flags. Do not require message objects to have every key.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter SmartctlModelsTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Models/SmartctlModels.swift Tests/CrystalDiskInfoMacCoreTests/SmartctlModelsTests.swift
git commit -m "feat: decode smartctl JSON reports"
```

---

### Task 4: Smartctl runner, path discovery, timeout, and exit semantics

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Services/SmartctlRunner.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/SmartctlRunnerTests.swift`

**Interfaces:**
- Produces `SmartctlResult` with `report`, `exitStatus`, `stderr`, `rawJSON`.
- Produces `protocol SmartctlRunning` with `discover() throws -> URL`, `version() throws -> String`, `read(bsdName:) throws -> SmartctlResult`.
- Produces `SmartctlError` cases `notInstalled`, `unsupportedVersion`, `timeout`, `launchFailed`, `invalidJSON`, `deviceUnreadable`.
- `read` uses `/usr/bin/env`? No: `Process.executableURL = smartctlURL`; args `["-j", "-a", "/dev/\(bsdName)"]`; no shell.
- 10-second timeout; terminate then kill.
- Usable JSON is accepted regardless of nonzero exit; a missing/unparseable payload throws.

- [ ] **Step 1: Write failing tests**

Cover:
- discovery finds `/opt/homebrew/bin/smartctl` when injected path exists; missing path throws `notInstalled`;
- version parse `smartctl 7.5 ...` and reject 7.3;
- fake executable returns the disk0 fixture plus exit 4; `read` returns report with exit 4 (must NOT throw);
- fake executable prints malformed JSON → `invalidJSON`;
- fake executable sleeps 2s with a 0.1s timeout in an injectable timeout → `timeout`;
- `read` uses argument arrays, never a shell string (inspect recorded args via a fake runner).
- retry hint: when first invocation returns no JSON and stderr contains `Unable to detect device type`, runner tries `-d sat`, then `-d nvme`; a fake script records attempts.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter SmartctlRunnerTests` → FAIL.

- [ ] **Step 3: Implement runner**

Use `Process`, `Pipe`, `terminationHandler`, and a semaphore/async wait. Capture bounded stdout/stderr. Parse JSON with `SmartctlReport.decode`. Treat JSON with identity + SMART as success even if exit != 0. Add `-d` retries only for detection-message failures. Store `exitStatus` from `smartctl.exit_status` if present, else process status.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter SmartctlRunnerTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Services/SmartctlRunner.swift Tests/CrystalDiskInfoMacCoreTests/SmartctlRunnerTests.swift
git commit -m "feat: add smartctl process runner"
```

---

### Task 5: Diskutil physical-disk enumeration

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Services/DiskutilLister.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/DiskutilListerTests.swift`

**Interfaces:**
- Produces `DiskCandidate` with `bsdName`, `isInternal`, `capacityBytes`, `mediaName`, `protocol`.
- Produces `protocol DiskListing` with `physicalDisks() throws -> [DiskCandidate]`.
- Produces `DiskutilLister` using `/usr/sbin/diskutil list -plist` and `/usr/sbin/diskutil info -plist /dev/diskX`.

- [ ] **Step 1: Write failing tests**

Use a synthetic `diskutil-list.plist` fixture / injected command output. Assert:
- physical whole disks `disk0` and `disk4` are candidates;
- APFS synthesized volumes and disk images are excluded;
- internal flag, capacity, media name, and protocol map correctly;
- malformed plist throws.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter DiskutilListerTests` → FAIL.

- [ ] **Step 3: Implement lister**

Decode plist with `PropertyListSerialization`/`PropertyListDecoder` into a minimal schema. `diskutil info -plist` keys: `DeviceNode`, `Internal`, `VirtualOrPhysical`, `TotalSize`, `MediaName`, `Protocol`. Filter `VirtualOrPhysical == "Physical"` and whole-disk node names. Keep order stable (disk number ascending).

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter DiskutilListerTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Services/DiskutilLister.swift Tests/CrystalDiskInfoMacCoreTests/DiskutilListerTests.swift
git commit -m "feat: enumerate physical disks with diskutil"
```

---

### Task 6: Domain mapping, health, temperature, and life

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Models/DiskInfo.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/DiskMapper.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/HealthEvaluator.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/HealthEvaluatorTests.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/DiskMapperTests.swift`

**Interfaces:**
- Produces `DiskInfo` and `SmartAttribute` exactly as in the spec.
- Produces `TemperaturePolicy` with `useDriveLimits`, `warningCelsius`, `criticalCelsius`.
- Produces `HealthEvaluation` with `status`, `reasons`, `effectiveWarning`, `effectiveCritical`, `lifePercent`, `temperatureCelsius`.
- Produces `HealthEvaluator.evaluate(report:policy:) -> HealthEvaluation`.
- Produces `DiskMapper.map(candidate:report:policy:) -> DiskInfo`.

- [ ] **Step 1: Write failing tests**

Cover:
- disk0 maps to NVMe, health Good at 34 °C, life 95, power-on 1695;
- disk4 maps to Intel, health Good at 42 °C, life 97, power-on 12235;
- NVMe critical warning 1 → Bad;
- spare 5/threshold 10 → Bad; spare 10/threshold 10 → Caution; threshold 100 → Good;
- media errors 1 → Caution; percentage used 90 → Caution; 100 → Bad;
- temperature 78 with drive warning 77 → Caution; 80 → Bad;
- global override policy at 50/60 → 55 Caution, 60 Bad, regardless of drive limits;
- ATA prefailure current <= threshold → Bad; reallocated/pending > 0 → Caution;
- missing SMART → Unknown; missing optional fields → nil, not zero.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter HealthEvaluatorTests` and `--filter DiskMapperTests` → FAIL.

- [ ] **Step 3: Implement mapping and evaluation**

Use maximum severity. Map NVMe log to CDI-style attributes (critical warning, temp, spare, spare threshold, percentage used, data units, host commands, busy time, cycles, hours, unsafe shutdowns, media errors, error-log entries, temperature sensors). Map ATA attributes directly. Compute life and effective limits. Keep reasons as short human strings for the UI and tests.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter HealthEvaluatorTests` and `--filter DiskMapperTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Models/DiskInfo.swift Sources/CrystalDiskInfoMacCore/Services/DiskMapper.swift Sources/CrystalDiskInfoMacCore/Services/HealthEvaluator.swift Tests/CrystalDiskInfoMacCoreTests/HealthEvaluatorTests.swift Tests/CrystalDiskInfoMacCoreTests/DiskMapperTests.swift
git commit -m "feat: map SMART data and evaluate disk health"
```

---

### Task 7: History store

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Models/HistorySample.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/HistoryStore.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces `HistorySample` with `timestamp`, `health`, `temperatureCelsius`, `lifePercent`, `powerOnHours`.
- Produces `protocol HistoryStoring` with `append(_:for:)`, `samples(for:)`, `prune(now:)`.
- Produces `JSONHistoryStore` writing one JSON file per stable disk id under an injected directory.

- [ ] **Step 1: Write failing tests**

Cover:
- append/reload round trip;
- two disk ids remain isolated;
- samples older than 30 days are pruned;
- 100,000 hard cap is enforced;
- corrupt file is backed up/ignored and does not crash;
- writes are atomic.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter HistoryStoreTests` → FAIL.

- [ ] **Step 3: Implement store**

Use `FileManager` + `JSONEncoder`/`JSONDecoder` with `.atomic` writes. Stable id = serial + model, sanitized for a filename. Prune on append and on load. Do not store raw SMART dumps in history.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter HistoryStoreTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Models/HistorySample.swift Sources/CrystalDiskInfoMacCore/Services/HistoryStore.swift Tests/CrystalDiskInfoMacCoreTests/HistoryStoreTests.swift
git commit -m "feat: persist disk health history"
```

---

### Task 8: Monitor, refresh scheduling, settings, and notification policy

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Models/AppSettings.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/SettingsStore.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/DiskScanner.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/NotificationService.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Services/NotificationPolicy.swift`
- Create: `Sources/CrystalDiskInfoMacCore/ViewModels/DiskMonitor.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/DiskMonitorTests.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/NotificationPolicyTests.swift`

**Interfaces:**
- Produces `AppSettings` with `refreshMinutes`, `temperaturePolicy`, `showMenuBarTemperature`, `notificationsEnabled`, `launchAtLogin`.
- Produces `SettingsStore` load/save.
- Produces `DiskScanner.scan() -> [DiskInfo]` composing lister + runner + mapper.
- Produces `NotificationPolicy` that compares previous/current states and decides notifications.
- Produces `@MainActor DiskMonitor` with `disks`, `selectedDiskID`, `isRefreshing`, `lastRefresh`, `errorMessage`, `refresh()`, `selectDisk(id:)`.

- [ ] **Step 1: Write failing tests**

Cover:
- mock scanner returns disk0/disk4; monitor selects disk0 and exposes both;
- refresh appends history and updates lastRefresh;
- overlapping refresh calls do not run two scans;
- missing smartctl sets an actionable `errorMessage` and keeps prior disks;
- notification policy: Good→Bad notifies; first-launch Bad does not; single Unknown does not, second consecutive does; removal after two misses notifies once; repeated Bad does not re-notify;
- temperature crossing uses effective limits;
- settings round trip and invalid values fall back.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter DiskMonitorTests` and `--filter NotificationPolicyTests` → FAIL.

- [ ] **Step 3: Implement monitor and policy**

Use a serial task/actor for refresh. Persist last notified state per disk in `SettingsStore`/UserDefaults. Use `UNUserNotificationCenter` behind a protocol for tests; request authorization lazily. Keep the selected disk stable across refreshes. Do not remove a disk until two consecutive failures/grace.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter DiskMonitorTests` and `--filter NotificationPolicyTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Models/AppSettings.swift Sources/CrystalDiskInfoMacCore/Services/{SettingsStore,DiskScanner,NotificationService,NotificationPolicy}.swift Sources/CrystalDiskInfoMacCore/ViewModels/DiskMonitor.swift Tests/CrystalDiskInfoMacCoreTests/{DiskMonitorTests,NotificationPolicyTests}.swift
git commit -m "feat: add disk monitor, settings, and notifications"
```

---

### Task 9: Main window — disk selector, status cards, identity grid

**Files:**
- Modify: `Sources/CrystalDiskInfoMacCore/Views/MainView.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Views/DiskSelectorView.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Views/StatusCardsView.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Views/IdentityGridView.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Theme.swift`
- Modify: `Sources/CrystalDiskInfoMac/CrystalDiskInfoMacApp.swift`
- Modify: `Tests/CrystalDiskInfoMacCoreTests/ViewRenderTests.swift`

**Interfaces:**
- Produces `MainView(model: DiskMonitor)` at 960×640.
- Produces disk selector, health/temperature/life cards, identity grid, refresh button, last-refresh label, error banner.
- Produces `DiskMonitor.preview` with disk0/disk4 sample data.

- [ ] **Step 1: Write failing render test**

Render `MainView(model: .preview)` at 960×640; assert non-nil image and size.

- [ ] **Step 2: Run test to verify failure**

`swift test --filter ViewRenderTests` → FAIL.

- [ ] **Step 3: Implement UI**

Top disk selector with health-colored dots; three large cards; identity grid in a `Grid`; refresh in toolbar; selected disk name/title; error banner for read/smartctl failures. Use native font/layout sizes (no `.scaleEffect`). Dark/light adaptive colors; status colors green/amber/red/gray.

- [ ] **Step 4: Run test to verify pass**

`swift test --filter ViewRenderTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Views Sources/CrystalDiskInfoMacCore/Theme.swift Sources/CrystalDiskInfoMac/CrystalDiskInfoMacApp.swift Tests/CrystalDiskInfoMacCoreTests/ViewRenderTests.swift
git commit -m "feat: add CrystalDiskInfo Mac main window"
```

---

### Task 10: SMART table

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Views/SmartTableView.swift`
- Modify: `Sources/CrystalDiskInfoMacCore/Views/MainView.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/SmartTableTests.swift`

**Interfaces:**
- Produces `SmartTableView(attributes: [SmartAttribute])` with sortable columns ID, Attribute, Current, Worst, Threshold, Raw.
- Produces `SmartTableRow` formatting for nil values (`—`), NVMe and ATA rows.
- Tooltip includes the raw string and prefailure state.

- [ ] **Step 1: Write failing tests**

Cover:
- NVMe attribute count and order from disk0 fixture;
- ATA fixture rows map;
- nil current/worst/threshold render `—`;
- raw value/string preserved;
- prefailure + current <= threshold row is marked warning.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter SmartTableTests` → FAIL.

- [ ] **Step 3: Implement table**

Use SwiftUI `Table` with sortable columns. Keep the selected row readable; hover tooltips. Do not invent threshold values.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter SmartTableTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Views/SmartTableView.swift Sources/CrystalDiskInfoMacCore/Views/MainView.swift Tests/CrystalDiskInfoMacCoreTests/SmartTableTests.swift
git commit -m "feat: add sortable SMART attribute table"
```

---

### Task 11: History graph

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Views/HistoryChartView.swift`
- Modify: `Sources/CrystalDiskInfoMacCore/Views/MainView.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/HistoryChartTests.swift`

**Interfaces:**
- Produces `HistoryChartView(samples: [HistorySample])` with range selector 1h/24h/7d/30d and temperature/life lines.
- Produces `HistoryWindow` filtering.
- Produces gaps for missing samples; no zero filling.

- [ ] **Step 1: Write failing tests**

Cover:
- range filtering boundaries;
- temperature/life series counts;
- missing samples remain gaps;
- empty history shows an empty state;
- 30-day sample at 1-minute interval is not truncated.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter HistoryChartTests` → FAIL.

- [ ] **Step 3: Implement chart**

Use `Charts` `LineMark`/`PointMark`; two y-axes or separate small charts for temperature and life; legend; range picker. Use native rendering.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter HistoryChartTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Views/HistoryChartView.swift Sources/CrystalDiskInfoMacCore/Views/MainView.swift Tests/CrystalDiskInfoMacCoreTests/HistoryChartTests.swift
git commit -m "feat: add disk history chart"
```

---

### Task 12: Menu bar extra and notifications

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Views/MenuBarView.swift`
- Modify: `Sources/CrystalDiskInfoMac/CrystalDiskInfoMacApp.swift`
- Modify: `Sources/CrystalDiskInfoMacCore/Services/NotificationService.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/MenuBarTests.swift`

**Interfaces:**
- Produces `MenuBarExtra` with per-disk health/temp/life and actions Open, Refresh, Settings, Quit.
- Produces menu bar label showing hottest temperature when enabled.
- Produces notification permission request and delivery via `UNUserNotificationCenter`.

- [ ] **Step 1: Write failing tests**

Cover:
- menu bar view renders with two disks;
- hottest temperature label selects the highest valid temperature;
- no temperature shows a neutral icon;
- notification request authorization is requested once;
- notification content includes disk name, old/new health or temperature, and is not sent when disabled.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter MenuBarTests` → FAIL.

- [ ] **Step 3: Implement menu bar and notifications**

Use `MenuBarExtra("CrystalDiskInfo Mac", systemImage: ...)` and `menuBarExtraStyle(.menu)`. Add a settings toggle for temperature in label. Notification service is injectable and idempotent.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter MenuBarTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Views/MenuBarView.swift Sources/CrystalDiskInfoMac/CrystalDiskInfoMacApp.swift Sources/CrystalDiskInfoMacCore/Services/NotificationService.swift Tests/CrystalDiskInfoMacCoreTests/MenuBarTests.swift
git commit -m "feat: add menu bar and notifications"
```

---

### Task 13: Settings, permissions, and error states

**Files:**
- Create: `Sources/CrystalDiskInfoMacCore/Views/SettingsView.swift`
- Create: `Sources/CrystalDiskInfoMacCore/Views/SmartctlSetupView.swift`
- Modify: `Sources/CrystalDiskInfoMacCore/Views/MainView.swift`
- Modify: `Sources/CrystalDiskInfoMacCore/ViewModels/DiskMonitor.swift`
- Create: `Tests/CrystalDiskInfoMacCoreTests/SettingsViewTests.swift`

**Interfaces:**
- Produces `SettingsView(settings:onSave:onCancel:)` with refresh interval, temperature policy toggle/thresholds, menu bar temperature, notifications, launch at login, history retention (read-only), smartctl status.
- Produces `SmartctlSetupView` for missing binary with `brew install smartmontools` and Recheck.
- Produces permission error instructions when smartctl cannot open a device.

- [ ] **Step 1: Write failing tests**

Cover:
- settings round trip;
- temperature override toggle affects effective limits;
- missing smartctl shows setup text and disables scan;
- permission failure shows the device-specific reason and leaves other disks intact;
- settings view renders at 560×480;
- launch-at-login failure is surfaced, not silent.

- [ ] **Step 2: Run tests to verify failure**

`swift test --filter SettingsViewTests` → FAIL.

- [ ] **Step 3: Implement settings and error states**

Use a sheet with Form; `SMAppService.mainApp` for launch at login behind a protocol for tests. Include “Full Disk Access / permissions” guidance when a read fails. Do not fabricate data.

- [ ] **Step 4: Run tests to verify pass**

`swift test --filter SettingsViewTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskInfoMacCore/Views/SettingsView.swift Sources/CrystalDiskInfoMacCore/Views/SmartctlSetupView.swift Sources/CrystalDiskInfoMacCore/Views/MainView.swift Sources/CrystalDiskInfoMacCore/ViewModels/DiskMonitor.swift Tests/CrystalDiskInfoMacCoreTests/SettingsViewTests.swift
git commit -m "feat: add settings and smartctl error states"
```

---

### Task 14: Icon, documentation, final build, and QA

**Files:**
- Create: `Scripts/make-icon.swift`
- Create: `Resources/AppIcon.icns`
- Modify: `Scripts/build-app.sh`
- Modify: `README.md`, `NOTICE`, `LICENSE`, `.gitignore`

**Interfaces:**
- Produces a 1024×1024 disk-health icon, `AppIcon.icns`, a signed app, and documentation.

- [ ] **Step 1: Generate icon**

Use AppKit/CoreGraphics: dark rounded square, three health-colored drive bars/platters, no CDI logo. Convert with `iconutil`. Build script copies it.

- [ ] **Step 2: Build and verify**

```bash
swift test
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/CrystalDiskInfoMac.app
```

There is no C++ engine in this project; `swift test` is the full automated suite.

- [ ] **Step 3: Run real integration test**

Run `smartctl -j -a /dev/disk0` and `/dev/disk4` through the app’s runner; verify both appear, disk0 exit status 4 still maps, health/temp/life match the fixtures.

- [ ] **Step 4: Manual QA**

- Internal Apple SSD + external Intel NVMe visible.
- Refresh, auto-refresh, graph range, history persistence after relaunch.
- Menu bar temperature and actions.
- Notifications on a simulated health/temperature transition (use test injection or a temporary threshold).
- Missing smartctl by temporarily pointing PATH away; clear setup state.
- Permission failure by pointing at a protected/unreadable device; no fake health.
- Quit during refresh leaves no child process.

- [ ] **Step 5: Update README/NOTICE and commit**

README includes build/run/test, smartctl dependency and install command, supported/unsupported devices, health rules, history retention, permissions, and attribution. NOTICE lists CrystalDiskInfo (MIT, hiyohiyo), smartmontools (GPLv2, separate executable), and states no affiliation.

```bash
git add Scripts/make-icon.swift Resources/AppIcon.icns Scripts/build-app.sh README.md NOTICE LICENSE .gitignore
git commit -m "chore: add icon, docs, and final QA"
```

---

## Self-Review Notes

- Spec coverage: discovery, smartctl exit semantics, mapping, health/temperature/life, history, refresh, UI, menu bar, notifications, settings, permissions, packaging, and QA are mapped to tasks.
- Type consistency: `SmartctlReport` → `DiskMapper` → `DiskInfo`; `DiskMonitor` consumes scanner/history/notifications; views consume `DiskInfo`/`HistorySample`.
- Review Focus tests are in Tasks 3, 4, 6, 7, 8, 12, and 13.
- Deferred by design: themes, languages, AAM/APM, RAID, USB vendor quirks, smartctl bundling, privileged helper, App Store/notarization.
