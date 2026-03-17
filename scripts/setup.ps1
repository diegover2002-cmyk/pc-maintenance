#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers the maintenance script as a Windows Scheduled Task.

.DESCRIPTION
    Run this ONCE after cloning the repo.
    It creates a task that runs maintenance.ps1 automatically every week
    on Sundays at 10:00 AM (or any schedule you choose below).

.NOTES
    Requires: Administrator privileges
#>

# ── CONFIG ──────────────────────────────────────────────────────────────────
$TaskName    = "PC-Maintenance-Weekly"
$TaskDesc    = "Weekly automated PC maintenance (security, cleanup, performance)"
$ScriptPath  = "$PSScriptRoot\maintenance.ps1"

# Schedule: every Sunday at 10:00 AM
$TriggerDay  = "Sunday"
$TriggerTime = "10:00"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n=== PC Maintenance — Setup ===" -ForegroundColor Cyan

# Verify script exists
if (-not (Test-Path $ScriptPath)) {
    Write-Host "[ERROR] maintenance.ps1 not found at: $ScriptPath" -ForegroundColor Red
    Write-Host "Make sure you run setup.ps1 from the 'scripts' folder." -ForegroundColor Yellow
    exit 1
}

# Remove existing task if present
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing task '$TaskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Build trigger (weekly)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $TriggerDay -At $TriggerTime

# Build action — run PowerShell as admin with bypass for execution policy
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`" -Mode Apply"

# Run as SYSTEM so it always has admin rights, even when no user is logged in
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

# Settings
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 1 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

# Register
Register-ScheduledTask `
    -TaskName   $TaskName `
    -Description $TaskDesc `
    -Trigger    $trigger `
    -Action     $action `
    -Principal  $principal `
    -Settings   $settings `
    -Force | Out-Null

Write-Host "`n[OK] Task '$TaskName' registered successfully!" -ForegroundColor Green
Write-Host "     Schedule : Every $TriggerDay at $TriggerTime" -ForegroundColor Cyan
Write-Host "     Script   : $ScriptPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run the maintenance manually RIGHT NOW, execute:" -ForegroundColor White
Write-Host "  .\maintenance.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "To view/edit the task, open Task Scheduler and look for '$TaskName'." -ForegroundColor White
