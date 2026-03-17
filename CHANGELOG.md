# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [2.1.0] - 2026-03-17

### Added
- `Test-OnSystemDrive` helper function to validate paths against `$env:SystemDrive`
- FILE ANALYSIS module now prints its scope at startup: `Scope: system drive only (C:\)`

### Changed
- Desktop, Downloads, and `DupScanDirs` are all validated before any scan or action is
  registered — paths outside the system drive emit a `WARN` and are skipped
- Duplicate scan no longer processes off-drive directories even if added to `DupScanDirs` config

---

## [2.0.1] - 2026-03-17

### Fixed
- **setup.ps1**: Inline `# comment` after backtick broke PowerShell line continuation in
  `New-ScheduledTaskSettingsSet`, silently dropping `-MultipleInstances IgnoreNew` from
  the registered scheduled task
- **setup.ps1**: Added `-WindowStyle Hidden` to the scheduled task action so the weekly
  run no longer opens a visible console window on Sunday mornings
- **maintenance.ps1**: Replaced deprecated `Get-WmiObject` with `Get-CimInstance` in the
  Drivers module for PowerShell 7+ compatibility
- **maintenance.ps1**: Changed duplicate file deletion from `AUTO` to `MANUAL` to prevent
  unintended destructive deletions without user review
- **maintenance.ps1**: Changed report file encoding from `ASCII` to `UTF-8` so device and
  file names with non-ASCII characters are preserved correctly

---

## [2.0.0] - 2026-03-17

### Added
- **Plan / Apply workflow** inspired by Terraform: run without arguments to see everything
  the script *would* do (no changes made), then re-run with `-Mode Apply` to execute
- **Action Registry**: all proposed changes are stored in a structured list before execution,
  enabling a clean summary and report at the end
- **FILE ANALYSIS module**: Desktop clutter detection, Downloads age/size audit, large file
  warnings (> 500 MB), and MD5 duplicate detection across Downloads and Desktop
- **STARTUP PROGRAMS module**: classifies startup entries by category (Gaming, Media, Work,
  System, Security…), auto-disables known non-essential entries, flags unknowns for manual review
- **Browser cache cleanup**: Chrome and Edge cache folders cleared when over 10 MB
- **Report generation**: full plain-text report written to `reports/` and copied to Desktop
  after every run
- `$StartupDB` lookup table with per-entry `Auto` flag to control which startup programs
  are safe to disable automatically
- `$StartupAutoPatterns` wildcard list for auto-disabling known noisy startup patterns
  (e.g. `MicrosoftEdgeAutoLaunch_*`)
- Colored console output with Terraform-style prefix symbols (`+`, `-`, `!`, `=`, `?`)

### Changed
- Script renamed from single-task runner to full maintenance suite with modular architecture
- Each module now follows Collect → Register → (optionally Apply) pattern
- `Write-Log` and `Write-PlanLine` unified for consistent console + file output

### Removed
- Simple sequential task execution without plan preview

---

## [1.0.0] - 2026-03-17

### Added
- Initial release: automated Windows 11 maintenance script
- Security checks: Windows Defender status, pending Windows Updates, Firewall profiles
- Cleanup: temp files (`%TEMP%`, `C:\Windows\Temp`, Prefetch), Recycle Bin, Windows Update cache, log rotation
- Disk space monitoring with configurable free-space threshold (default 15 GB)
- Startup program count check (warns if > 10 entries)
- Disk optimization: TRIM on SSDs, defrag analysis on HDDs
- Driver health check via WMI (`ConfigManagerErrorCode`)
- Backup reminder based on last-modified date of Documents and Desktop
- Weekly scheduled task via `setup.ps1` (every Sunday 10:00 AM, runs as SYSTEM)
- Timestamped log files with 30-day auto-rotation

[Unreleased]: https://github.com/diegover2002-cmyk/pc-maintenance/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/diegover2002-cmyk/pc-maintenance/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/diegover2002-cmyk/pc-maintenance/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/diegover2002-cmyk/pc-maintenance/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/diegover2002-cmyk/pc-maintenance/releases/tag/v1.0.0
