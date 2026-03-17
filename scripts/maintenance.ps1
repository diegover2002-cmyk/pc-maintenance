#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PC Maintenance Script for Windows 11
    Automates: security checks, cleanup, performance tuning, and backup reminders.

.DESCRIPTION
    Run this script periodically (or via Task Scheduler using setup.ps1) to keep
    your Windows 11 PC healthy.

.NOTES
    Author   : pc-maintenance project
    Requires : PowerShell 5.1+ / Windows 11
    Run as   : Administrator
#>

# ─────────────────────────────────────────────
#  CONFIG  (edit these values as needed)
# ─────────────────────────────────────────────
$LogDir        = "$PSScriptRoot\..\logs"
$LogFile       = "$LogDir\maintenance_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$BackupDirs    = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop")   # folders to check for backup
$MinFreeGB     = 15          # warn if free disk space drops below this (GB)
$MaxTempAgeDays = 7          # delete temp files older than this many days
$MaxLogAgeDays  = 30         # rotate logs older than this many days

# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    switch ($Level) {
        "OK"   { Write-Host $line -ForegroundColor Green  }
        "WARN" { Write-Host $line -ForegroundColor Yellow }
        "ERR"  { Write-Host $line -ForegroundColor Red    }
        default{ Write-Host $line -ForegroundColor Cyan   }
    }
}

function Write-Section {
    param([string]$Title)
    $sep = "=" * 60
    Write-Log ""
    Write-Log $sep
    Write-Log "  $Title"
    Write-Log $sep
}

# ─────────────────────────────────────────────
#  INIT
# ─────────────────────────────────────────────
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

Write-Log "╔══════════════════════════════════════════╗"
Write-Log "║      PC MAINTENANCE SCRIPT STARTED       ║"
Write-Log "╚══════════════════════════════════════════╝"
Write-Log "Machine : $env:COMPUTERNAME"
Write-Log "User    : $env:USERNAME"
Write-Log "Date    : $(Get-Date)"

# ─────────────────────────────────────────────
#  1. SECURITY
# ─────────────────────────────────────────────
Write-Section "1. SECURITY CHECKS"

# Windows Defender status
try {
    $defender = Get-MpComputerStatus -ErrorAction Stop
    if ($defender.AntivirusEnabled) {
        Write-Log "Windows Defender: ENABLED" "OK"
    } else {
        Write-Log "Windows Defender: DISABLED — please enable it!" "WARN"
    }
    if ($defender.AntivirusSignatureAge -gt 3) {
        Write-Log "Defender definitions are $($defender.AntivirusSignatureAge) days old — consider updating" "WARN"
    } else {
        Write-Log "Defender definitions: up to date ($($defender.AntivirusSignatureAge) days old)" "OK"
    }
    if ($defender.RealTimeProtectionEnabled) {
        Write-Log "Real-time protection: ON" "OK"
    } else {
        Write-Log "Real-time protection: OFF" "WARN"
    }
} catch {
    Write-Log "Could not retrieve Defender status: $_" "ERR"
}

# Windows Update — list pending updates
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $pending = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
    $count = $pending.Updates.Count
    if ($count -eq 0) {
        Write-Log "Windows Update: no pending updates" "OK"
    } else {
        Write-Log "Windows Update: $count pending update(s) found — run Windows Update!" "WARN"
        foreach ($u in $pending.Updates) {
            Write-Log "  · $($u.Title)" "WARN"
        }
    }
} catch {
    Write-Log "Could not check Windows Update: $_" "ERR"
}

# Firewall
try {
    $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
    foreach ($p in $fwProfiles) {
        $state = if ($p.Enabled) { "ON" } else { "OFF — WARNING!" }
        $level = if ($p.Enabled) { "OK" } else { "WARN" }
        Write-Log "Firewall [$($p.Name)]: $state" $level
    }
} catch {
    Write-Log "Could not check Firewall: $_" "ERR"
}

# ─────────────────────────────────────────────
#  2. CLEANUP
# ─────────────────────────────────────────────
Write-Section "2. CLEANUP"

$totalFreed = 0

function Remove-OldFiles {
    param([string]$Path, [int]$AgeDays, [string]$Label)
    if (-not (Test-Path $Path)) { return }
    $cutoff = (Get-Date).AddDays(-$AgeDays)
    $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -lt $cutoff }
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($size / 1MB, 2)
    $script:totalFreed += $size
    $files | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "$Label : removed $($files.Count) files ($sizeMB MB freed)" "OK"
}

# User temp
Remove-OldFiles -Path $env:TEMP -AgeDays $MaxTempAgeDays -Label "User TEMP ($env:TEMP)"

# Windows temp
Remove-OldFiles -Path "C:\Windows\Temp" -AgeDays $MaxTempAgeDays -Label "Windows TEMP (C:\Windows\Temp)"

# Prefetch (safe to clean)
Remove-OldFiles -Path "C:\Windows\Prefetch" -AgeDays 14 -Label "Prefetch"

# Empty Recycle Bin
try {
    Clear-RecycleBin -Force -ErrorAction Stop
    Write-Log "Recycle Bin: emptied" "OK"
} catch {
    Write-Log "Recycle Bin: could not empty — $_" "ERR"
}

# Windows Update cache (SoftwareDistribution\Download)
$wuCache = "C:\Windows\SoftwareDistribution\Download"
if (Test-Path $wuCache) {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    $wuFiles = Get-ChildItem $wuCache -Recurse -File -ErrorAction SilentlyContinue
    $wuSize  = ($wuFiles | Measure-Object -Property Length -Sum).Sum
    $totalFreed += $wuSize
    Remove-Item "$wuCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Write-Log "Windows Update cache: $([math]::Round($wuSize/1MB,2)) MB freed" "OK"
}

$totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
Write-Log "Total space freed this run: $totalFreedMB MB" "OK"

# Rotate old log files
Get-ChildItem -Path $LogDir -Filter "*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$MaxLogAgeDays) } |
    Remove-Item -Force
Write-Log "Log rotation: removed logs older than $MaxLogAgeDays days" "OK"

# ─────────────────────────────────────────────
#  3. DISK SPACE
# ─────────────────────────────────────────────
Write-Section "3. DISK SPACE"

$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
foreach ($d in $drives) {
    if ($d.Used -eq $null) { continue }
    $totalGB = [math]::Round(($d.Used + $d.Free) / 1GB, 1)
    $freeGB  = [math]::Round($d.Free / 1GB, 1)
    $usedPct = if ($totalGB -gt 0) { [math]::Round($d.Used / ($d.Used + $d.Free) * 100, 1) } else { 0 }
    $level   = if ($freeGB -lt $MinFreeGB) { "WARN" } else { "OK" }
    Write-Log "Drive $($d.Name): $freeGB GB free / $totalGB GB total ($usedPct% used)" $level
}

# ─────────────────────────────────────────────
#  4. PERFORMANCE — STARTUP PROGRAMS
# ─────────────────────────────────────────────
Write-Section "4. PERFORMANCE — STARTUP PROGRAMS"

$startupPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

$startupItems = @()
foreach ($path in $startupPaths) {
    if (Test-Path $path) {
        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        $props.PSObject.Properties |
            Where-Object { $_.Name -notmatch "^PS" } |
            ForEach-Object { $startupItems += $_.Name }
    }
}

Write-Log "Startup programs found: $($startupItems.Count)" "INFO"
foreach ($item in $startupItems) {
    Write-Log "  · $item" "INFO"
}
if ($startupItems.Count -gt 10) {
    Write-Log "You have many startup programs. Consider disabling unused ones via Task Manager > Startup." "WARN"
}

# ─────────────────────────────────────────────
#  5. PERFORMANCE — DISK OPTIMIZATION (SSD/HDD)
# ─────────────────────────────────────────────
Write-Section "5. DISK OPTIMIZATION"

try {
    $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
    foreach ($vol in $volumes) {
        $letter = "$($vol.DriveLetter):"
        # Detect SSD vs HDD via Get-PhysicalDisk
        $diskType = "Unknown"
        try {
            $partition = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop
            $disk      = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
            $physical  = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $disk.Number }
            $diskType  = $physical.MediaType
        } catch {}

        if ($diskType -eq "SSD" -or $diskType -eq "Unspecified") {
            # For SSDs: run TRIM (Optimize-Volume with -ReTrim)
            Write-Log "Drive $letter ($diskType): running TRIM..." "INFO"
            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -Verbose 2>&1 |
                ForEach-Object { Write-Log "  $_" "INFO" }
            Write-Log "Drive $letter: TRIM completed" "OK"
        } else {
            # For HDDs: defragment
            Write-Log "Drive $letter (HDD): running defragmentation analysis..." "INFO"
            Optimize-Volume -DriveLetter $vol.DriveLetter -Analyze -Verbose 2>&1 |
                ForEach-Object { Write-Log "  $_" "INFO" }
            Write-Log "Drive $letter: analysis done (run with -Defrag flag for full defrag)" "OK"
        }
    }
} catch {
    Write-Log "Disk optimization skipped: $_" "WARN"
}

# ─────────────────────────────────────────────
#  6. DRIVERS CHECK
# ─────────────────────────────────────────────
Write-Section "6. DRIVERS CHECK"

try {
    $problematic = Get-WmiObject Win32_PnPEntity -ErrorAction Stop |
                   Where-Object { $_.ConfigManagerErrorCode -ne 0 }
    if ($problematic.Count -eq 0) {
        Write-Log "All device drivers: OK (no errors detected)" "OK"
    } else {
        Write-Log "$($problematic.Count) driver(s) with issues found:" "WARN"
        foreach ($d in $problematic) {
            Write-Log "  · $($d.Name) [Error code: $($d.ConfigManagerErrorCode)]" "WARN"
        }
    }
} catch {
    Write-Log "Driver check failed: $_" "ERR"
}

# ─────────────────────────────────────────────
#  7. BACKUP REMINDER
# ─────────────────────────────────────────────
Write-Section "7. BACKUP CHECK"

foreach ($dir in $BackupDirs) {
    if (-not (Test-Path $dir)) {
        Write-Log "Backup dir not found: $dir" "WARN"
        continue
    }
    $recent = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if ($recent) {
        $age = (Get-Date) - $recent.LastWriteTime
        Write-Log "$dir — last modified file: $([math]::Round($age.TotalDays,1)) day(s) ago" "INFO"
        if ($age.TotalDays -gt 7) {
            Write-Log "  ⚠ No recent changes detected. Have you backed up recently?" "WARN"
        }
    }
}

Write-Log ""
Write-Log "Reminder: back up your files regularly to an external drive or cloud storage!" "WARN"

# ─────────────────────────────────────────────
#  SUMMARY
# ─────────────────────────────────────────────
Write-Section "SUMMARY"
Write-Log "Maintenance completed at $(Get-Date)" "OK"
Write-Log "Log saved to: $LogFile" "OK"
Write-Log ""
Write-Log "╔══════════════════════════════════════════╗"
Write-Log "║         ALL TASKS FINISHED ✓             ║"
Write-Log "╚══════════════════════════════════════════╝"
