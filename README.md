# PC Maintenance — Windows 11

Automated maintenance suite for Windows 11 with a **Plan / Apply** workflow inspired by Terraform:
run once to see *exactly* what would change, then run again to apply it.

---

## Modules

| # | Module | What it checks / does |
|---|--------|-----------------------|
| 1 | **Security** | Windows Defender status & definition age, pending Windows Updates, Firewall profiles |
| 2 | **Cleanup** | Temp files, browser caches (Chrome/Edge), Recycle Bin, Windows Update cache, log rotation |
| 3 | **Startup Programs** | Classifies startup entries by category, auto-disables known non-essential ones, flags unknowns |
| 4 | **File Analysis** | Desktop clutter, Downloads age/size audit, large file warnings, MD5 duplicate detection |
| 5 | **Disk** | Free space on all fixed drives (warns below threshold), TRIM on SSDs |
| 6 | **Drivers** | Detects devices with driver errors via `ConfigManagerErrorCode` |
| 7 | **Backup** | Checks last-modified date on Documents & Desktop, reminds you to back up |

All actions are classified as `AUTO` (safe to apply automatically) or `MANUAL` (requires human decision).

---

## Quick Start

### 1. Clone

```powershell
git clone https://github.com/diegover2002-cmyk/pc-maintenance.git
cd pc-maintenance
```

### 2. Allow PowerShell scripts (one-time)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 3. Register the weekly scheduled task (one-time)

```powershell
cd scripts
.\setup.ps1
```

Registers a Task Scheduler job that runs every **Sunday at 10:00 AM** silently as SYSTEM.

---

## Usage

```powershell
# Plan mode (default) — analyze system, show all proposed actions. No changes made.
.\scripts\maintenance.ps1

# Apply mode — execute all AUTO-fixable actions from the plan.
.\scripts\maintenance.ps1 -Mode Apply
```

After each run a plain-text report is saved to:
- `reports/report_<mode>_<timestamp>.txt`
- `Desktop\PC_Maintenance_Report.txt` (overwritten each run)

---

## Configuration

Edit the `$Cfg` block at the top of `scripts/maintenance.ps1`:

```powershell
$Cfg = @{
    MinFreeGB       = 15     # warn if free disk space drops below this (GB)
    TempAgeDays     = 7      # delete temp files older than N days
    LogRotateDays   = 30     # rotate logs older than N days
    DownloadAgeDays = 60     # flag Downloads files older than N days
    DesktopMaxFiles = 20     # warn if Desktop has more than N files
    LargeFileMB     = 500    # flag individual files larger than N MB
    BackupDirs      = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop")
    DupScanDirs     = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")
}
```

To change the schedule, edit `scripts/setup.ps1`:

```powershell
$TriggerDay  = "Sunday"   # Monday, Tuesday, ... Sunday
$TriggerTime = "10:00"    # 24h format
```

Re-run `.\setup.ps1` to apply schedule changes.

> **Note:** File Analysis only operates on paths located on the system drive (`$env:SystemDrive`).
> Paths on other drives are skipped with a warning.

---

## Project Structure

```
pc-maintenance/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── scripts/
│   ├── maintenance.ps1   <- main script (all modules)
│   └── setup.ps1         <- registers the scheduled task (run once)
├── logs/                 <- auto-created, gitignored
├── reports/              <- auto-created, gitignored
├── CHANGELOG.md
└── README.md
```

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later (7+ recommended)
- **Run as Administrator**

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

---

## License

MIT — use freely, modify as you like.
