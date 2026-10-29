# CrystalDiskInfo Mac

A native macOS disk-health app inspired by CrystalDiskInfo.

It discovers local physical disks, reads SMART data through `smartctl`, and
shows health, temperature, life, identity, SMART attributes, and history.

## Requirements

- macOS 27+, arm64
- `smartctl` from Homebrew:

```sh
brew install smartmontools
```

The app detects `/opt/homebrew/bin/smartctl`, `/usr/local/bin/smartctl`,
`/usr/bin/smartctl`, then `PATH`. It does not bundle smartctl.

## Build

```sh
swift build
Scripts/build-app.sh
open build/CrystalDiskInfoMac.app
```

## Test

```sh
swift test
```

## Notes

- Not affiliated with CrystalMark.
- CrystalDiskInfo is MIT; smartctl is GPLv2 and stays a separate executable.
- Some devices or USB bridges may require additional permissions or a different
  smartctl device type; the app reports those failures instead of inventing data.
