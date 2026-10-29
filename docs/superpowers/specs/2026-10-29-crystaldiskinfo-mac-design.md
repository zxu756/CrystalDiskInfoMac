# CrystalDiskInfo Mac — Design

- Date: 2026-10-29
- Status: Draft for approval
- Source of truth: `https://github.com/zxu756/CrystalDiskInfo` (fork, currently identical to upstream `hiyohiyo/CrystalDiskInfo` @ `4fccdb4`)
- Source reference: `/Users/xu/Projects/CrystalDiskInfoSrc`
- Target project: `/Users/xu/Projects/CrystalDiskInfoMac`
- Working app name: **CrystalDiskInfo Mac**

## 1. Intent

Build a native macOS disk-health product in the spirit of CrystalDiskInfo: show every readable local drive, its health, temperature, remaining life, identity, SMART attributes, and history, with a menu-bar presence and alerts.

This is a macOS reimplementation, not a Windows port. The MIT-licensed source is the behavioral reference for SMART semantics, health rules, and UI structure. The Mac app uses `smartctl` over a local process boundary for SMART acquisition and SwiftUI for everything the user sees.

Primary use is this Mac. The first version is a local, ad-hoc-signed `.app`; it is not an App Store product.

## 2. What the source tells us

### 2.1 Architecture

- `AtaSmart.cpp` (13,572 lines) is the SMART engine. It uses Win32 `CreateFile`, `DeviceIoControl`, ATA/SCSI pass-through, NVMe pass-through, WMI, and vendor-specific USB/RAID paths.
- `NVMeInterpreter.cpp` maps the NVMe SMART/Health log into CDI's ATA-like attribute list: critical warning, temperature, available spare, spare threshold, percentage used, data units, host commands, busy time, power cycles, power-on hours, unsafe shutdowns, media errors, error-log entries, composite temperature times, and temperature sensors.
- `DiskInfoDlg*.cpp` is a 507×347 dialog: disk buttons across the top, health/temperature/life cards, an identity grid, a SMART list, and separate Graph, Temperature, Health, Alarm History, and Settings dialogs.
- `DiskInfoDlgTray.cpp` provides the tray icon, temperature/health display, and restore behavior.
- `DiskInfoDlgUpdate.cpp` contains the health, temperature, and life evaluation rules, including NVMe critical-warning/spare/percentage-used checks and ATA threshold checks.

### 2.2 macOS reality

Verified on this Mac (Mac mini M4, macOS 27.0.1, arm64):

- `smartctl 7.5` is installed at `/opt/homebrew/bin/smartctl`.
- `smartctl -j -a /dev/disk0` reads the internal Apple SSD **without sudo**:
  - model `APPLE SSD AP0256Z`
  - SMART passed
  - temperature 34 °C
  - available spare 100, threshold 99
  - percentage used 5
  - power-on hours 1695, power cycles 162, unsafe shutdowns 8
  - media errors 0, error-log entries 0
- `smartctl -j -a /dev/disk4` reads the external Intel NVMe **without sudo**:
  - model `INTEL SSDPEKNW512G8`
  - SMART passed
  - temperature 42 °C, warning limit 77, critical limit 80
  - percentage used 3
  - power-on hours 12235, power cycles 7292, unsafe shutdowns 103
  - media errors 0
- `smartctl --scan` enumerates both NVMe devices through IOKit.
- Some USB/SATA bridges may require a different `-d` device type or elevated privileges. The app must detect and explain that rather than silently omit the drive.

The Windows engine cannot be compiled on macOS. A native replacement is required.

## 3. Goals, non-goals, anti-goals

### Goals

1. Show all local disks that `smartctl` can read, with the internal Apple SSD and external NVMe working out of the box.
2. Reproduce the useful CDI information architecture: disk selector, health, temperature, life, identity, SMART attributes.
3. Evaluate and display Good / Caution / Bad / Unknown using documented, testable rules.
4. Record temperature, life, and health history and show a graph over time.
5. Provide a menu-bar status surface with the hottest drive and quick health access.
6. Send local notifications on health degradation and configurable temperature thresholds.
7. Refresh automatically on a configurable interval, and manually on demand.
8. Keep the app local-only, non-sandboxed, ad-hoc signed, and free of raw-device writes.

### Non-goals for v1

- Compiling or linking the Windows MFC/Win32 code.
- AAM/APM control, RAID controllers, JMicron/ASMedia/Realtek USB RAID, Intel RST/VROC, AMD RAID, or vendor-specific USB memory quirks.
- Raw block-device access, firmware updates, secure erase, TRIM commands, or disk benchmarking.
- Theme packs, sound/voice, multi-language UI, and the full CDI settings catalog.
- App Store distribution, notarization, auto-update, or a privileged helper.
- Guaranteeing identical health semantics for every vendor-specific ATA attribute.

### Anti-goals

- Inventing SMART values when `smartctl` cannot read a device.
- Showing a healthy status for a failed or unreadable drive.
- Running shell strings assembled from disk names; use `Process` arguments.
- Requiring root for the two NVMe drives on this Mac.
- Silently dropping a disk because one SMART field is absent.

## 4. Approaches considered

### A. SwiftUI + `smartctl` JSON — chosen

- Use the installed `smartctl` as a separate executable.
- Parse `smartctl -j -a <device>` into typed models.
- Native SwiftUI/AppKit UI, Swift Charts, MenuBarExtra, UserNotifications.
- Why: strongest SMART coverage per unit of work, no privileged helper for NVMe, already verified on both drives, and the JSON contract is explicit.

Trade-offs: Homebrew dependency; GPLv2 smartctl is a separate process, not linked; some devices may need root/USB bridge handling.

### B. SwiftUI + native IOKit

- Read `IONVMeSMARTInterface`/IOKit directly. No external dependency, but much more code, weaker SATA/USB coverage, and uncertain Apple Silicon behavior. Rejected for v1.

### C. Menu-bar-only MVP

- Health/temperature/notifications only, no full SMART table or history. Rejected because the request is a full CDI-like product.

## 5. Architecture

```
CrystalDiskInfoMac.app
├── SwiftUI app
│   ├── MainWindow
│   ├── DiskList / DiskDetail
│   ├── SmartTableView
│   ├── HistoryChart
│   ├── SettingsSheet
│   └── AboutView
├── MenuBarExtra
├── RefreshScheduler
├── NotificationService
├── HistoryStore
└── Core
    ├── DiskScanner          (diskutil + smartctl)
    ├── SmartctlRunner       (Process, timeout, JSON)
    ├── SmartctlModels       (Codable)
    ├── DiskInfoMapper       (smartctl JSON → domain)
    ├── HealthEvaluator      (Good/Caution/Bad/Unknown)
    └── SettingsStore
```

### Build layout

```
CrystalDiskInfoMac/
├── Package.swift
├── Sources/
│   ├── CrystalDiskInfoMac/
│   │   └── CrystalDiskInfoMacApp.swift
│   ├── CrystalDiskInfoMacCore/
│   │   ├── Models/
│   │   ├── Services/
│   │   ├── ViewModels/
│   │   └── Views/
├── Tests/
│   └── CrystalDiskInfoMacCoreTests/
├── Scripts/
│   ├── build-app.sh
│   ├── Info.plist
│   └── make-icon.swift
├── Resources/
│   └── AppIcon.icns
├── docs/superpowers/specs/
├── LICENSE
├── NOTICE
└── README.md
```

- Same CLT-only SwiftPM + `build-app.sh` approach as CrystalDiskMark Mac: macOS 27+, arm64 only, ad-hoc signing, no Xcode project.
- `smartctl` is **not bundled** in v1. The app detects it in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, then `PATH`; if absent, a setup view explains `brew install smartmontools` and offers Recheck.
- If a future release must be self-contained, bundling smartctl requires GPLv2 compliance and a separate licensing/distribution pass.

## 6. Disk discovery

1. Enumerate physical whole disks with `diskutil list -plist` (or `diskutil info -plist` per candidate). Exclude disk images, APFS synthesized volumes, and non-physical entries.
2. For each `/dev/diskX`, run `smartctl -j -a /dev/diskX`.
3. If that fails with an interface hint, retry with a conservative device type list: `-d sat`, `-d nvme`, `-d auto`. Do not guess vendor RAID modes in v1.
4. Keep a stable `DiskID` derived from serial number + model; fall back to BSD name. A disk reappearing with the same serial keeps its history.
5. A failed read produces a disk row with `Unknown` health and a readable reason, not a missing row.

## 7. Domain model

```swift
struct DiskInfo: Identifiable, Equatable, Sendable {
    let id: String                 // serial/model stable id
    let bsdName: String            // disk0, disk4
    let model: String
    let serial: String
    let firmware: String
    let protocolName: String       // NVMe, SATA, USB...
    let interfaceName: String
    let capacityBytes: UInt64
    let isInternal: Bool
    let smartStatus: SmartStatus   // passed / failed / unknown
    let health: HealthStatus       // good / caution / bad / unknown
    let temperatureCelsius: Int?
    let lifePercent: Int?
    let powerOnHours: Int?
    let powerCycleCount: Int?
    let unsafeShutdowns: Int?
    let mediaErrors: Int?
    let attributes: [SmartAttribute]
    let readError: String?
}

struct SmartAttribute: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let current: Int?
    let worst: Int?
    let threshold: Int?
    let rawValue: UInt64?
    let rawString: String?
    let isPrefailure: Bool
}

enum SmartStatus: String, Sendable { case passed, failed, unknown }
enum HealthStatus: String, Sendable { case good, caution, bad, unknown }
```

### SMART mapping

- NVMe: use `nvme_smart_health_information_log` directly for temperature, spare, percentage used, data units, power cycles, power-on hours, unsafe shutdowns, media errors, error-log entries.
- ATA: use `ata_smart_attributes.table`; preserve id, name, value, worst, threshold, raw value/string, prefailure flag.
- Display the CDI-style NVMe rows even when the underlying field is named differently, but keep the raw field in the tooltip/detail.

## 8. Health, temperature, and life rules

### Health

The evaluator computes every applicable signal, then uses the **maximum severity wins** rule: `Bad > Caution > Unknown > Good`. `Unknown` is used only when SMART itself is unreadable; a readable drive with missing optional sensors still gets a health conclusion from the signals that are present.

- `smart_status.passed == false` → **Bad**.
- Unreadable or unparseable SMART → **Unknown** with the error reason.
- NVMe:
  - `critical_warning != 0` → **Bad** (CDI parity; all bits are critical warnings).
  - `available_spare < available_spare_threshold` → **Bad**.
  - `available_spare == available_spare_threshold && threshold != 100` → **Caution**.
  - `media_errors > 0` → **Caution** unless a higher signal already made it Bad.
  - `percentage_used >= 90` → **Caution**; `>= 100` → **Bad**.
- ATA:
  - Any prefailure attribute with a nonzero threshold and `current <= threshold` → **Bad**.
  - `Reallocated_Sector_Ct`, `Current_Pending_Sector`, or `Offline_Uncorrectable` raw value > 0 → **Caution**.
- Temperature at or above the critical threshold → **Bad**; at or above warning → **Caution**.
- Otherwise **Good**.

### Temperature

- Prefer `temperature.current`; fall back to NVMe log temperature or the ATA temperature attribute.
- Temperature policy:
  - Default: use drive-reported `op_limit_max` / `critical_limit_max` when present; otherwise fall back to global defaults of 50 °C warning and 60 °C critical.
  - A Settings toggle **Use drive-reported limits** (default on) switches all drives to the global defaults when turned off.
  - Global warning/critical values are editable; drives with no reported limits always use them.
  - Notifications use the same effective limits shown in the UI; the effective values are displayed per drive so a user can see why a drive is cautioning.

### smartctl exit status

`smartctl` exit bits encode both I/O failures and health findings; a nonzero exit alone does not mean the read failed. The runner treats a result as usable when JSON contains a device identity plus either `smart_status` or an NVMe/ATA SMART payload. Exit bits and `smartctl.messages` are retained as diagnostics and shown in the disk detail, but do not by themselves force `Unknown`. Only an open failure, timeout, or unparseable/missing payload produces `Unknown`.

### Life

- NVMe: `max(0, 100 - percentage_used)`.
- ATA: use the first available vendor/lifetime attribute among `Percent_Lifetime_Remain`, `Media_Wearout_Indicator`, `SSD_Life_Left`, `Remaining_Lifetime_Perc`, or the CDI-compatible raw-value rules; if none, show `—`.
- Never infer a life percentage from power-on hours.

## 9. History and graphs

- Sample every successful refresh: timestamp, health, temperature, life, power-on hours.
- Store one JSON file per disk under `~/Library/Application Support/CrystalDiskInfoMac/history/`.
- Retain 30 days with a hard cap of 100,000 samples per disk. At the fastest 1-minute refresh, 30 days is ~43,200 samples, so the 30-day graph is not truncated by the cap.
- Graph with Swift Charts: temperature and life lines, range 1 hour / 24 hours / 7 days / 30 days.
- Missing samples are gaps, not zero.
- History survives app restarts and disk reconnection by stable disk id.

## 10. UI

### Main window

- Native macOS window, base size ~960×640 (no bitmap scaling; use real font/layout sizes).
- Top disk selector: horizontal buttons/tabs for each disk, health-colored dot, model/short name.
- Status area: three large cards — Health, Temperature, Life — plus the disk identity grid (model, serial, firmware, protocol, capacity, power-on hours, power cycles, unsafe shutdowns, media errors).
- SMART table: sortable columns ID, Attribute, Current, Worst, Threshold, Raw; color prefailure/threshold states.
- Graph button opens a graph window/sheet; or a segmented **Overview / SMART / History** layout.
- Manual Refresh button and last-refreshed timestamp.
- Error state per disk with the smartctl reason and a Recheck action.
- Dark and light appearance; CDI-inspired status colors (green/amber/red/gray).

### Menu bar

- `MenuBarExtra` with a compact icon; menu shows each disk name, health, temperature, and life.
- Hottest disk temperature in the menu-bar label when enabled.
- Actions: Open CrystalDiskInfo Mac, Refresh, Settings, Quit.

### Notifications

- Local notifications on health transition to Caution/Bad, media-error increase, and temperature crossing warning/critical thresholds.
- Notify on a transition to **Unknown** only after two consecutive failed refreshes; notify on disk removal after the same grace period. Transient single failures and first launches do not notify.
- Persist the last notified state per disk; a drive already Bad/Caution at first launch is shown in the UI but does not produce a notification until its state changes or the user enables a first-run summary.
- Coalesce per disk; do not notify on every refresh.
- Respect a global enable switch and per-category thresholds.

### Settings

- Refresh interval: 1, 5, 10, 30, 60 minutes (default 10).
- Temperature warning/critical thresholds.
- **Use drive-reported limits** toggle (default on). When off, all drives use the global thresholds.
- Show temperature in menu bar.
- Notifications on/off.
- Launch at login (optional, via `SMAppService`).
- History retention: 30 days (fixed in v1, displayed read-only).

## 11. Refresh and process model

- `RefreshScheduler` runs a serial task; no overlapping `smartctl` invocations.
- Each disk query has a 10-second timeout; kill the process and report a timeout.
- Refresh all disks, update the selected disk, append history, evaluate notifications.
- Manual refresh cancels/restarts the schedule but never overlaps.
- If a disk disappears or SMART fails, keep its last info marked stale for two consecutive refreshes; after that show Unknown/Disconnected and notify once. Reappearance restores the row and history.
- App termination cancels in-flight processes.

## 12. Permissions, security, and licensing

- No network, telemetry, analytics, auto-update, or raw writes.
- `smartctl` is invoked as an executable with argument arrays, never through a shell.
- The app runs non-sandboxed and ad-hoc signed for local use. If macOS TCC blocks `/dev/disk` access, show a clear Full Disk Access instruction rather than silently failing.
- v1 has no privileged helper. Devices that require root are reported as `Unknown` with guidance; NVMe on this Mac works without root.
- App code is MIT. `smartctl`/smartmontools is GPLv2 and is **not bundled** in v1; the README and About view state the dependency and attribution.
- The app is not affiliated with CrystalMark; use a new icon and a working title.
- No Windows CDI resources or icons are copied.

## 13. Testing

### Unit tests

- Decode real smartctl JSON fixtures for:
  - internal Apple SSD (NVMe, Apple controller), including its nonzero smartctl exit with usable JSON
  - external Intel NVMe
  - at least one ATA/SATA fixture (synthetic or captured later)
- Disk mapper: identity, capacity, protocol, attributes, missing fields.
- Health rules: good, caution, bad, unknown; severity ordering; NVMe critical warning; spare threshold; media errors; percentage used; ATA threshold; temperature.
- Life rules: NVMe, ATA vendor attributes, unknown.
- Temperature policy: drive limits, global fallback, override toggle, notification bounds.
- History store: append, 30-day retention, 100k cap, reload, stable id.
- Settings store: defaults, bounds, persistence.
- smartctl path discovery and missing-binary state.

### Integration tests

- Run the real `smartctl` against `/dev/disk0` and `/dev/disk4` when available; assert both parse and produce health/temperature.
- Simulate permission denied, timeout, malformed JSON, and disk disappearance.
- Verify no overlapping refreshes.

### UI/render tests

- Main window at 960×640 with a preview model.
- SMART table with NVMe and ATA rows.
- Menu bar extra render.
- Settings sheet render.

### Manual checks

- Internal Apple SSD and external Intel NVMe both appear with correct names/serials/temps.
- Refresh, notification, menu bar, graph, and history survive relaunch.
- Quit during refresh leaves no child process.
- Missing smartctl shows setup guidance.
- Permission-denied disk shows a clear error, not a fake healthy state.

## 14. Milestones

1. Scaffold SwiftPM app, bundle script, icon, blank 960×640 window.
2. Smartctl runner, JSON models, disk discovery, real fixtures, process/timeout tests.
3. Domain mapper, health/life/temperature evaluator, unit tests.
4. Main window: disk selector, status cards, identity grid, SMART table.
5. History store, Swift Charts graph, refresh scheduler.
6. Menu bar extra, notifications, settings, launch at login.
7. QA on internal + external NVMe, error states, cleanup, README/licensing.

## 15. Decisions and open questions

- v1 depends on Homebrew `smartmontools`; self-contained bundling is deferred. If the product must be one-click installable, we need a separate GPL bundling/distribution pass.
- Main window uses a native 960×640 layout rather than a literal 507×347 Windows dialog; the information architecture and status semantics are 1:1, not the pixel geometry.
- Theme packs and language packs are deferred; v1 uses one dark/light adaptive theme and English UI.
- AAM/APM, RAID, USB vendor quirks, and raw-device operations are out of scope.
- REA is used to inspect the original Windows binary/UI behavior and SMART labels where source alone is ambiguous; the Mac app remains a native reimplementation.
