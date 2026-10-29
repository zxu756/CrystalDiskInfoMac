# CrystalDiskInfo Reference Audit

Date: 2026-10-29
Source: `https://github.com/zxu756/CrystalDiskInfo` (fork @ `4fccdb4`, identical to upstream at audit time)
Windows binary: official CrystalDiskInfo 9.9.3 `DiskInfo64.exe` (x86_64 PE)
REA report: Ghidra provider, PE SHA-256 `68b4415df84c7173b686303030b184b87cc135c0ad46e246e2bae24e4f652e5d`

## REA evidence

REA opened the Windows PE and searched the Ghidra string inventory. Relevant observed strings:

- `Temperature` (24 strings), including `AlarmTemperature`, `ShowTemperatureIconOnly`, `TEMPERATURE`, `TemperatureIcon`, `temperatureUnknown`.
- `Health Status` (2 large export templates containing `%TEMPERATURE%` and `%DISK_STATUS%`).
- `ReallocatedSectorsCount`.
- `Available Spare` — `NG: Available spare capacity has fallen below the threshold.`
- `Percentage Used` was not present as a literal string in the Ghidra inventory; the NVMe mapping is source-derived.
- The export templates confirm the CDI information fields: model, firmware, serial, capacity, interface, standard, transfer mode, power-on hours/count, host reads/writes, temperature, health status, features, drive letter.

The Windows UI also exposes AAM/APM, RAID, tray, graph, alarm history, and theme/language settings; these are not v1 Mac scope.

## Source rules consulted

- `AtaSmart.cpp` (13,572 lines): Windows SMART acquisition; NVMe log conversion; ATA attribute evaluation.
- `NVMeInterpreter.cpp`: NVMe SMART/Health log mapping.
- `DiskInfoDlgUpdate.cpp`: health icons and temperature/life status.
- `DiskInfo.rc`: 507×347 main dialog, disk buttons, health/temperature/life cards, identity fields, SMART list.
- `DiskInfoDlgTray.cpp`: tray/temperature/health behavior.

## NVMe mapping (CDI ATA-like IDs)

| ID | Meaning |
|---|---|
| 1 | Critical Warning |
| 2 | Temperature |
| 3 | Available Spare |
| 4 | Available Spare Threshold |
| 5 | Percentage Used |
| 6 | Data Units Read |
| 7 | Data Units Written |
| 8 | Host Read Commands |
| 9 | Host Write Commands |
| 10 | Controller Busy Time |
| 11 | Power Cycles |
| 12 | Power On Hours |
| 13 | Unsafe Shutdowns |
| 14 | Media Errors |
| 15 | Number of Error Log Entries |
| 16 | Warning Composite Temperature Time |
| 17 | Critical Composite Temperature Time |
| 18–25 | Temperature Sensor 1–8 |
| 26–29 | Thermal Management Temperature 1–4 |

## Mac divergence decisions

1. **Health precedence**: compute all signals, then `Bad > Caution > Unknown > Good`. CDI’s NVMe path treats a nonzero critical warning as Bad; we preserve that and keep spare/media/percentage as additional Caution/Bad signals.
2. **Temperature**: CDI has a per-model `AlarmTemperature` (default 60 for HDD, 50 for SSD in the source). The Mac app uses drive-reported limits when present, otherwise global 50/60, with a Settings toggle to make global values authoritative.
3. **smartctl exit status**: disk0 exits 4 while returning complete identity and SMART data. The Mac runner parses usable JSON and treats exit bits as diagnostics, not failure. Only open failure, timeout, or unparseable payload is Unknown.
4. **Unsupported Windows paths**: AAM/APM, RAID, vendor USB bridges, and tray sound are out of v1; the Mac app reports unsupported/unreadable devices rather than guessing.
5. **UI**: information architecture and status semantics are replicated; the Mac window uses native 960×640 layout rather than the 507×347 Windows dialog geometry.

## Fixtures

- `Tests/Fixtures/disk0-apple-nvme.json`: internal Apple SSD, smartctl exit 4, complete NVMe log.
- `Tests/Fixtures/disk4-intel-nvme.json`: external Intel NVMe, smartctl exit 0, complete NVMe log.
- `Tests/Fixtures/diskutil-list.plist`: physical-disk enumeration input.

Serial numbers are redacted in the JSON fixtures.
