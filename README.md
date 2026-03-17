# 🖥️ PC Maintenance — Windows 11

Automated maintenance script for Windows 11 that handles **security checks, disk cleanup, performance tuning, driver verification, and backup reminders** — all in one run.

---

## 📋 What it does

| # | Task | Details |
|---|------|---------|
| 1 | 🛡️ **Security** | Checks Windows Defender status, pending Windows Updates, and Firewall profiles |
| 2 | 🧹 **Cleanup** | Deletes temp files, clears Recycle Bin, purges Windows Update cache, rotates old logs |
| 3 | 💾 **Disk Space** | Reports free/used space on all fixed drives, warns if below threshold |
| 4 | ⚡ **Startup Programs** | Lists all startup entries, warns if there are too many |
| 5 | 🔧 **Disk Optimization** | Runs TRIM on SSDs or defrag analysis on HDDs |
| 6 | 🖱️ **Drivers** | Detects devices with driver errors (ConfigManagerErrorCode ≠ 0) |
| 7 | 📦 **Backup Reminder** | Checks modification dates on key folders, reminds you to back up |

Everything is logged to the `logs/` folder with timestamps.

---

## 🚀 Quick Start

### 1. Clone the repo

```powershell
git clone https://github.com/YOUR_USERNAME/pc-maintenance.git
cd pc-maintenance
```

### 2. Allow PowerShell scripts (one-time)

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 3. Register the weekly scheduled task

```powershell
cd scripts
.\setup.ps1
```

This registers a Windows Task Scheduler job that runs every **Sunday at 10:00 AM** automatically.

### 4. Run manually anytime

```powershell
cd scripts
.\maintenance.ps1
```

---

## ⚙️ Configuration

Open `scripts/maintenance.ps1` and edit the `CONFIG` block at the top:

```powershell
$BackupDirs     = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop")
$MinFreeGB      = 15       # warn if free space drops below this (GB)
$MaxTempAgeDays = 7        # delete temp files older than N days
$MaxLogAgeDays  = 30       # keep logs for N days
```

To change the schedule, edit `scripts/setup.ps1`:

```powershell
$TriggerDay  = "Sunday"   # Monday, Tuesday, ... Sunday
$TriggerTime = "10:00"    # 24h format
```

Then re-run `.\setup.ps1` to apply changes.

---

## 📁 Project Structure

```
pc-maintenance/
├── scripts/
│   ├── maintenance.ps1   ← main script (all tasks)
│   └── setup.ps1         ← registers the scheduled task (run once)
├── logs/                 ← auto-created, gitignored
├── .gitignore
└── README.md
```

---

## 🤖 Using with Claude Code

You can use [Claude Code](https://claude.ai/code) to modify or extend this project from your terminal:

```bash
# Install Claude Code (requires Node.js 18+)
npm install -g @anthropic-ai/claude-code

# Open the project
cd pc-maintenance
claude
```

Then ask things like:
- *"Add a task that checks CPU temperature"*
- *"Make the cleanup also clear browser caches"*
- *"Send me a Windows notification when maintenance finishes"*

---

## 📝 Logs

Logs are saved to `logs/maintenance_YYYYMMDD_HHMMSS.log` and automatically deleted after 30 days.

Example:

```
[2026-03-17 10:00:01][OK]   Windows Defender: ENABLED
[2026-03-17 10:00:02][OK]   Defender definitions: up to date (1 days old)
[2026-03-17 10:00:03][WARN] Windows Update: 3 pending update(s) found
[2026-03-17 10:00:05][OK]   User TEMP: removed 142 files (38.4 MB freed)
[2026-03-17 10:00:06][OK]   Recycle Bin: emptied
[2026-03-17 10:00:07][OK]   Total space freed this run: 214.7 MB
```

---

## ⚠️ Requirements

- Windows 11 (works on Windows 10 too)
- PowerShell 5.1 or later
- **Run as Administrator** (required for cleanup and security checks)

---

## 📄 License

MIT — use freely, modify as you like.
