# PC Maintenance — Claude Context

## Project purpose
PowerShell maintenance script for Windows 11. Handles security, cleanup, startup programs, file analysis, disk, drivers, and backup reminders. Inspired by Terraform's Plan/Apply workflow.

## Architecture

### Core pattern
Every module follows the same structure:
1. A `Collect-XxxActions` function that analyzes the system and calls `Register-Action`
2. `Register-Action` adds entries to `$script:Registry` (global list)
3. In **Plan** mode: only prints what would be done, no changes
4. In **Apply** mode: executes all AUTO-flagged actions from the registry

### Adding a new module
1. Create a `Collect-XxxActions` function
2. Use `Write-PlanLine` for output (with types: ADD, DEL, WARN, KEEP, MANUAL, INFO)
3. Use `Register-Action` to register fixable actions:
   - `Type = "AUTO"` → runs automatically in Apply mode
   - `Type = "MANUAL"` → printed as a reminder, never auto-executed
4. Call the function in the `# Collect all planned actions` block in Main
5. Add the module name to the README table

### Key functions
- `Register-Action` — adds an action to the registry with optional `-Run` scriptblock
- `Write-PlanLine` — colored output with a type prefix (ADD/DEL/WARN/KEEP/MANUAL/INFO)
- `Show-Section` — prints a section header
- `Format-Bytes` — human-readable byte sizes
- `ConvertTo-AsciiSafe` — strips non-ASCII from strings before logging

### Files
- `scripts/maintenance.ps1` — main script, all logic lives here
- `scripts/setup.ps1` — registers the Windows Task Scheduler job (run once)
- `logs/` — auto-created, gitignored, rotated after 30 days
- `reports/` — text reports saved after each run, also copied to Desktop

## Constraints
- Requires PowerShell 5.1+ and **Run as Administrator**
- Target OS: Windows 11 (also tested on Windows 10)
- No external dependencies — only built-in PowerShell cmdlets and WMI/CIM
- `$ErrorActionPreference = "SilentlyContinue"` — modules must not crash the whole script
- Use `.GetNewClosure()` on scriptblocks inside loops to capture loop variables correctly
- Encode all file writes as UTF-8

## Owner's machine (Diego)
- CPU: AMD Ryzen 7 7800X3D
- GPU: AMD Radeon RX 7900 XT
- RAM: Corsair Vengeance DDR5 32GB (2x16GB, 6000MHz)
- Motherboard: MSI PRO B650-S WIFI (MS-7E26)
- OS: Windows 11 Pro

## Running the script
```powershell
# Plan mode (safe, no changes)
.\scripts\maintenance.ps1

# Apply mode (executes AUTO actions)
.\scripts\maintenance.ps1 -Mode Apply
```
