#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PC Maintenance v2.0 - Plan & Apply workflow

.DESCRIPTION
    Inspired by HashiCorp Terraform:
      Plan  : Analyze system, show ALL proposed actions. No changes made.
      Apply : Execute all AUTO-fixable actions from the plan.

    Modules:
      Security     - Defender, Windows Update, Firewall
      Cleanup      - Temp files, browser caches, Recycle Bin, WU cache
      Startup      - Classify and disable non-essential startup programs
      File Analysis- Desktop clutter, Downloads age/size, duplicate detection
      Disk         - Space check, SSD TRIM
      Drivers      - Device error detection
      Backup       - Backup reminder check

.PARAMETER Mode
    Plan  (default) - Show what WOULD be done. Safe, no changes made.
    Apply           - Execute all AUTO-fixable actions.

.EXAMPLE
    .\maintenance.ps1
    .\maintenance.ps1 -Mode Apply
#>

param(
    [ValidateSet("Plan","Apply")]
    [string]$Mode = "Plan"
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# ============================================================
#  CONFIG
# ============================================================
$Cfg = @{
    LogDir          = (Join-Path $PSScriptRoot "..\logs")
    ReportDir       = (Join-Path $PSScriptRoot "..\reports")
    MinFreeGB       = 15
    TempAgeDays     = 7
    LogRotateDays   = 30
    DownloadAgeDays = 60
    DesktopMaxFiles = 20
    LargeFileMB     = 500
    BackupDirs      = @("$env:USERPROFILE\Documents","$env:USERPROFILE\Desktop")
    DupScanDirs     = @("$env:USERPROFILE\Downloads","$env:USERPROFILE\Desktop")
}
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $Cfg.LogDir "maintenance_${Timestamp}.log"

foreach ($d in @($Cfg.LogDir, $Cfg.ReportDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# ============================================================
#  STARTUP PROGRAM CLASSIFICATION
# ============================================================
$StartupDB = @{
    # Gaming (safe to disable - open manually when needed)
    "Steam"              = @{Cat="Gaming";    Auto=$true }
    "Discord"            = @{Cat="Gaming";    Auto=$true }
    "EpicGamesLauncher"  = @{Cat="Gaming";    Auto=$true }
    "Battle.net"         = @{Cat="Gaming";    Auto=$true }
    "RiotClient"         = @{Cat="Gaming";    Auto=$true }
    "FACEIT"             = @{Cat="Gaming";    Auto=$true }
    "EADM"               = @{Cat="Gaming";    Auto=$true }
    "com.blitz.app"      = @{Cat="Gaming";    Auto=$true }
    "electron.app.Yprac" = @{Cat="Gaming";    Auto=$true }
    "Trading Paints"     = @{Cat="Gaming";    Auto=$true }
    # Media / Browser
    "Spotify"            = @{Cat="Media";     Auto=$true }
    "AceStream"          = @{Cat="Media";     Auto=$true }
    "Opera Stable"       = @{Cat="Browser";   Auto=$true }
    "Microsoft.Lists"    = @{Cat="Office";    Auto=$true }
    # Dev (user choice - disable if not needed at boot)
    "Docker Desktop"     = @{Cat="Dev";       Auto=$false}
    # System / Security (NEVER disable)
    "SecurityHealth"     = @{Cat="System";    Auto=$false}
    "RtkAudUService"     = @{Cat="Hardware";  Auto=$false}
    "AMDNoiseSuppression"= @{Cat="Hardware";  Auto=$false}
    "Riot Vanguard"      = @{Cat="AntiCheat"; Auto=$false}
    "KeePass 2 PreLoad"  = @{Cat="Security";  Auto=$false}
    "Greenshot"          = @{Cat="Tools";     Auto=$false}
    "OneDrive"           = @{Cat="Cloud";     Auto=$false}
    "Teams"              = @{Cat="Work";      Auto=$false}
    # Citrix / Work environment (keep)
    "deviceTRUST Client User" = @{Cat="Work"; Auto=$false}
    "InstallHelper"      = @{Cat="Work";      Auto=$false}
    "AnalyticsSrv"       = @{Cat="Work";      Auto=$false}
    "ConnectionCenter"   = @{Cat="Work";      Auto=$false}
    "Redirector"         = @{Cat="Work";      Auto=$false}
    "CtxsDPS"            = @{Cat="Work";      Auto=$false}
}
# Wildcard patterns that are safe to disable
$StartupAutoPatterns = @("MicrosoftEdgeAutoLaunch_*", "AF_uuid_*", "AF_counter_*")

# ============================================================
#  HELPERS
# ============================================================
function Format-Bytes([long]$B) {
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    if ($B -ge 1GB) { return ("{0:N1} GB"  -f ($B/1GB)).ToString($ci) }
    if ($B -ge 1MB) { return ("{0:N1} MB"  -f ($B/1MB)).ToString($ci) }
    if ($B -ge 1KB) { return ("{0:N0} KB"  -f ($B/1KB)).ToString($ci) }
    return "$B B"
}

function ConvertTo-AsciiSafe([string]$s) {
    if (-not $s) { return "" }
    return [System.Text.RegularExpressions.Regex]::Replace($s, '[^\x20-\x7E]', '?')
}

function Write-Log([string]$Msg, [string]$Level = "INFO") {
    $safe = ConvertTo-AsciiSafe $Msg
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'HH:mm:ss')][$Level] $safe" -Encoding UTF8 -ErrorAction SilentlyContinue
}

$PlanColors = @{
    ADD    = "Green"
    DEL    = "Yellow"
    WARN   = "Red"
    KEEP   = "DarkGray"
    MANUAL = "Magenta"
    INFO   = "Cyan"
}
$PlanPrefix = @{
    ADD    = "  + "
    DEL    = "  - "
    WARN   = "  ! "
    KEEP   = "  = "
    MANUAL = "  ? "
    INFO   = "    "
}

function Write-PlanLine([string]$Msg, [string]$Type = "INFO") {
    $col = if ($PlanColors[$Type]) { $PlanColors[$Type] } else { "White" }
    $pre = if ($PlanPrefix[$Type]) { $PlanPrefix[$Type] } else { "    " }
    Write-Host "$pre$Msg" -ForegroundColor $col
    Write-Log "$pre$Msg" $Type
}

function Show-Section([string]$Title) {
    Write-Host ""
    Write-Host "  [ $Title ]" -ForegroundColor White
    Write-Host ("  " + ("-" * 56)) -ForegroundColor DarkGray
}

# ============================================================
#  ACTION REGISTRY
# ============================================================
$script:Registry = [System.Collections.Generic.List[hashtable]]::new()

function Register-Action {
    param(
        [string]$Module,
        [ValidateSet("AUTO","MANUAL")]
        [string]$Type,
        [string]$Label,
        [string]$Detail      = "",
        [long]  $Bytes       = 0,
        [scriptblock]$Run    = {}
    )
    $script:Registry.Add(@{
        Module = $Module
        Type   = $Type
        Label  = $Label
        Detail = $Detail
        Bytes  = $Bytes
        Run    = $Run
        OK     = $null
        Output = ""
    })
}

# ============================================================
#  MODULE: SECURITY
# ============================================================
function Collect-SecurityActions {
    Show-Section "SECURITY"

    # Defender
    try {
        $def = Get-MpComputerStatus -ErrorAction Stop
        if ($def.AntivirusEnabled) {
            Write-PlanLine "Windows Defender: enabled" "KEEP"
        } else {
            Write-PlanLine "Windows Defender is DISABLED" "WARN"
            Register-Action "Security" "MANUAL" "Enable Windows Defender" `
                -Detail "Open Windows Security and enable Defender"
        }
        if (-not $def.RealTimeProtectionEnabled) {
            Write-PlanLine "Real-time protection: OFF" "WARN"
            Register-Action "Security" "MANUAL" "Enable real-time protection" `
                -Detail "Open Windows Security > Virus & threat protection"
        } else {
            Write-PlanLine "Real-time protection: ON" "KEEP"
        }
        $age = $def.AntivirusSignatureAge
        if ($age -gt 3) {
            Write-PlanLine "Defender definitions: $age days old - update recommended" "WARN"
            Register-Action "Security" "AUTO" "Update Defender signatures" `
                -Run { Update-MpSignature -ErrorAction SilentlyContinue }
        } else {
            Write-PlanLine "Defender definitions: $age day(s) old - OK" "KEEP"
        }
    } catch { Write-PlanLine "Could not read Defender status" "WARN" }

    # Windows Update
    try {
        $pending = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software'").Updates
        if ($pending.Count -eq 0) {
            Write-PlanLine "Windows Update: no pending updates" "KEEP"
        } else {
            Write-PlanLine "$($pending.Count) pending Windows Update(s):" "MANUAL"
            foreach ($u in $pending) {
                $title = ConvertTo-AsciiSafe $u.Title
                Write-PlanLine "  $title" "INFO"
                Register-Action "Security" "MANUAL" "Install update: $title" `
                    -Detail "Run Windows Update to install"
            }
        }
    } catch { Write-PlanLine "Could not check Windows Update" "WARN" }

    # Firewall
    try {
        foreach ($p in (Get-NetFirewallProfile -ErrorAction Stop)) {
            if ($p.Enabled) {
                Write-PlanLine "Firewall [$($p.Name)]: ON" "KEEP"
            } else {
                Write-PlanLine "Firewall [$($p.Name)]: OFF - manual action required" "WARN"
                $pName = $p.Name
                Register-Action "Security" "MANUAL" "Enable Firewall profile: $pName" `
                    -Detail "Open Windows Security > Firewall & network protection"
            }
        }
    } catch { Write-PlanLine "Could not check Firewall" "WARN" }
}

# ============================================================
#  MODULE: CLEANUP
# ============================================================
function Measure-FolderOld([string]$Path, [int]$AgeDays) {
    if (-not (Test-Path $Path)) { return @{Count=0; Bytes=0L; Files=@()} }
    $cutoff = (Get-Date).AddDays(-$AgeDays)
    $files  = @(Get-ChildItem $Path -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff })
    $bytes  = [long]($files | Measure-Object -Property Length -Sum).Sum
    @{ Count=$files.Count; Bytes=$bytes; Files=$files }
}

function Measure-FolderAll([string]$Path) {
    if (-not (Test-Path $Path)) { return @{Count=0; Bytes=0L} }
    $files = @(Get-ChildItem $Path -File -Recurse -ErrorAction SilentlyContinue)
    $bytes = [long]($files | Measure-Object -Property Length -Sum).Sum
    @{ Count=$files.Count; Bytes=$bytes }
}

function Collect-CleanupActions {
    Show-Section "CLEANUP"

    # Temp folders
    $tempTargets = @(
        @{P=$env:TEMP;             Age=$Cfg.TempAgeDays; L="User Temp"}
        @{P="C:\Windows\Temp";     Age=$Cfg.TempAgeDays; L="Windows Temp"}
        @{P="C:\Windows\Prefetch"; Age=14;               L="Prefetch cache"}
    )
    foreach ($t in $tempTargets) {
        $m = Measure-FolderOld $t.P $t.Age
        if ($m.Count -gt 0) {
            Write-PlanLine "Delete $($m.Count) file(s) from $($t.L) ($(Format-Bytes $m.Bytes))" "DEL"
            $files = $m.Files
            Register-Action "Cleanup" "AUTO" "Clean $($t.L)" `
                -Detail "$($m.Count) files" -Bytes $m.Bytes `
                -Run { $files | Remove-Item -Force -ErrorAction SilentlyContinue }.GetNewClosure()
        } else {
            Write-PlanLine "$($t.L): clean" "KEEP"
        }
    }

    # Browser caches
    $browsers = @(
        @{P="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; L="Chrome cache"}
        @{P="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data"; L="Edge cache"}
    )
    foreach ($b in $browsers) {
        if (Test-Path $b.P) {
            $m = Measure-FolderAll $b.P
            if ($m.Bytes -gt 10MB) {
                Write-PlanLine "Clear $($b.L) ($(Format-Bytes $m.Bytes))" "DEL"
                $bPath  = $b.P
                $bLabel = $b.L
                $bBytes = $m.Bytes
                Register-Action "Cleanup" "AUTO" "Clear $bLabel" `
                    -Detail (Format-Bytes $bBytes) -Bytes $bBytes `
                    -Run { Remove-Item "$bPath\*" -Recurse -Force -ErrorAction SilentlyContinue }.GetNewClosure()
            } else {
                Write-PlanLine "$($b.L): $(Format-Bytes $m.Bytes) - skipping (< 10 MB)" "KEEP"
            }
        }
    }

    # Recycle Bin
    try {
        $rb    = (New-Object -ComObject Shell.Application).Namespace(0xa)
        $count = @($rb.Items()).Count
        if ($count -gt 0) {
            Write-PlanLine "Empty Recycle Bin ($count item(s))" "DEL"
            Register-Action "Cleanup" "AUTO" "Empty Recycle Bin" `
                -Detail "$count items" `
                -Run { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
        } else {
            Write-PlanLine "Recycle Bin: empty" "KEEP"
        }
    } catch { Write-PlanLine "Could not check Recycle Bin" "WARN" }

    # Windows Update cache
    $wuPath = "C:\Windows\SoftwareDistribution\Download"
    $m      = Measure-FolderAll $wuPath
    if ($m.Bytes -gt 0) {
        Write-PlanLine "Clear Windows Update download cache ($(Format-Bytes $m.Bytes))" "DEL"
        $wuBytes = $m.Bytes
        Register-Action "Cleanup" "AUTO" "Clear Windows Update cache" `
            -Bytes $wuBytes `
            -Run {
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                Remove-Item "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Start-Service wuauserv -ErrorAction SilentlyContinue
            }.GetNewClosure()
    } else {
        Write-PlanLine "Windows Update cache: empty" "KEEP"
    }

    # Old log rotation
    $oldLogs = @(Get-ChildItem $Cfg.LogDir -Filter "*.log" -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Cfg.LogRotateDays) })
    if ($oldLogs.Count -gt 0) {
        Write-PlanLine "Delete $($oldLogs.Count) log(s) older than $($Cfg.LogRotateDays) days" "DEL"
        Register-Action "Cleanup" "AUTO" "Rotate old logs" `
            -Run { $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue }.GetNewClosure()
    }
}

# ============================================================
#  MODULE: STARTUP PROGRAMS
# ============================================================
function Get-StartupItems {
    $approvedPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    )
    $runPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )

    # Build disabled lookup
    $disabled = @{}
    foreach ($ap in $approvedPaths) {
        if (-not (Test-Path $ap)) { continue }
        $v = Get-ItemProperty $ap -ErrorAction SilentlyContinue
        if (-not $v) { continue }
        $v.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
            $bytes = $_.Value
            if ($bytes -is [byte[]] -and $bytes.Length -gt 0 -and $bytes[0] -eq 3) {
                $disabled[$_.Name] = $true
            }
        }
    }

    $items = @()
    foreach ($rp in $runPaths) {
        if (-not (Test-Path $rp)) { continue }
        $props = Get-ItemProperty $rp -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
            if (-not $disabled[$_.Name]) {
                $items += @{ Name=$_.Name; Cmd=$_.Value }
            }
        }
    }
    return $items
}

function Collect-StartupActions {
    Show-Section "STARTUP PROGRAMS"

    $items     = Get-StartupItems
    $toDisable = @()
    $keep      = @()
    $unknown   = @()

    foreach ($item in $items) {
        $info = $StartupDB[$item.Name]
        if ($info) {
            if ($info.Auto) { $toDisable += $item } else { $keep += $item }
        } else {
            # Check wildcard patterns
            $matched = $false
            foreach ($pat in $StartupAutoPatterns) {
                if ($item.Name -like $pat) {
                    $toDisable += $item
                    $matched = $true
                    break
                }
            }
            if (-not $matched) { $unknown += $item }
        }
    }

    Write-PlanLine "Active startup programs: $($items.Count) total" "INFO"

    if ($keep.Count -gt 0) {
        $keepNames = ($keep | ForEach-Object {
            $cat = if ($StartupDB[$_.Name]) { $StartupDB[$_.Name].Cat } else { "?" }
            "$($_.Name) [$cat]"
        }) -join ", "
        Write-PlanLine "Keeping $($keep.Count) essential program(s):" "KEEP"
        $keep | ForEach-Object {
            $cat = if ($StartupDB[$_.Name]) { $StartupDB[$_.Name].Cat } else { "?" }
            Write-PlanLine "  $($_.Name) [$cat]" "KEEP"
        }
    }

    if ($toDisable.Count -gt 0) {
        Write-PlanLine "Will disable $($toDisable.Count) non-essential startup program(s):" "DEL"
        foreach ($item in $toDisable) {
            $info = $StartupDB[$item.Name]
            $cat  = if ($info) { $info.Cat } else { "Auto" }
            $cmd  = ConvertTo-AsciiSafe $item.Cmd
            if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0,60) + "..." }
            Write-PlanLine "  Disable: $($item.Name) [$cat]" "DEL"
            $iName = $item.Name
            Register-Action "Startup" "AUTO" "Disable startup: $($item.Name) [$cat]" `
                -Detail $cmd `
                -Run {
                    $ap    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
                    $bytes = [byte[]](0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
                    if (-not (Test-Path $ap)) { New-Item $ap -Force | Out-Null }
                    Set-ItemProperty $ap -Name $iName -Value $bytes -Type Binary -ErrorAction SilentlyContinue
                }.GetNewClosure()
        }
    }

    if ($unknown.Count -gt 0) {
        Write-PlanLine "$($unknown.Count) unrecognized program(s) - review manually:" "MANUAL"
        foreach ($item in $unknown) {
            $cmd = ConvertTo-AsciiSafe $item.Cmd
            if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0,60) + "..." }
            Write-PlanLine "  Review: $($item.Name)" "MANUAL"
            Write-PlanLine "    Cmd: $cmd" "INFO"
            Register-Action "Startup" "MANUAL" "Review unknown startup: $($item.Name)" `
                -Detail $cmd
        }
    }
}

# ============================================================
#  MODULE: FILE ANALYSIS
# ============================================================
function Test-OnSystemDrive([string]$Path) {
    $sysDrive = $env:SystemDrive.TrimEnd('\').ToUpper()
    return $Path.ToUpper().StartsWith($sysDrive)
}

function Collect-FileAnalysisActions {
    Show-Section "FILE ANALYSIS"

    $sysDrive = $env:SystemDrive.TrimEnd('\').ToUpper()
    Write-PlanLine "Scope: system drive only ($sysDrive\)" "INFO"

    # Desktop clutter
    $desktop      = "$env:USERPROFILE\Desktop"
    if (-not (Test-OnSystemDrive $desktop)) {
        Write-PlanLine "Skipping Desktop: not on system drive ($desktop)" "WARN"
        return
    }
    $desktopItems = @(Get-ChildItem $desktop -File -ErrorAction SilentlyContinue)
    $shortcuts    = @($desktopItems | Where-Object { $_.Extension -eq ".lnk" })
    $loose        = @($desktopItems | Where-Object { $_.Extension -ne ".lnk" })
    Write-PlanLine "Desktop: $($desktopItems.Count) files ($($shortcuts.Count) shortcuts, $($loose.Count) loose)" "INFO"
    if ($desktopItems.Count -gt $Cfg.DesktopMaxFiles) {
        Write-PlanLine "Desktop cluttered ($($desktopItems.Count) items > threshold $($Cfg.DesktopMaxFiles))" "MANUAL"
        Register-Action "Files" "MANUAL" "Organize Desktop ($($desktopItems.Count) items)" `
            -Detail "Move loose files to Documents or sub-folders. Ideal: shortcuts only."
    }
    if ($loose.Count -gt 0) {
        Write-PlanLine "Loose files on Desktop (not shortcuts):" "WARN"
        $loose | Select-Object -First 8 | ForEach-Object {
            Write-PlanLine "  $($_.Name) ($(Format-Bytes $_.Length))" "INFO"
        }
        if ($loose.Count -gt 8) { Write-PlanLine "  ... and $($loose.Count-8) more" "INFO" }
    }

    # Downloads - old files
    $dlPath = "$env:USERPROFILE\Downloads"
    if (-not (Test-OnSystemDrive $dlPath)) {
        Write-PlanLine "Skipping Downloads: not on system drive ($dlPath)" "WARN"
    } elseif (Test-Path $dlPath) {
        $allDL    = @(Get-ChildItem $dlPath -File -ErrorAction SilentlyContinue)
        $dlSize   = [long]($allDL | Measure-Object -Property Length -Sum).Sum
        Write-PlanLine "Downloads: $($allDL.Count) files, $(Format-Bytes $dlSize) total" "INFO"

        $oldDL    = @($allDL | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Cfg.DownloadAgeDays) })
        $oldBytes = [long]($oldDL | Measure-Object -Property Length -Sum).Sum
        if ($oldDL.Count -gt 0) {
            Write-PlanLine "Delete $($oldDL.Count) file(s) older than $($Cfg.DownloadAgeDays) days in Downloads ($(Format-Bytes $oldBytes))" "DEL"
            $filesToDel = $oldDL
            Register-Action "Files" "AUTO" "Delete old Downloads (>$($Cfg.DownloadAgeDays) days)" `
                -Detail "$($oldDL.Count) files" -Bytes $oldBytes `
                -Run { $filesToDel | Remove-Item -Force -ErrorAction SilentlyContinue }.GetNewClosure()
        } else {
            Write-PlanLine "Downloads: no files older than $($Cfg.DownloadAgeDays) days" "KEEP"
        }

        # Large files
        $large = @($allDL | Where-Object { $_.Length -gt ($Cfg.LargeFileMB * 1MB) } | Sort-Object Length -Descending)
        if ($large.Count -gt 0) {
            Write-PlanLine "$($large.Count) large file(s) > $($Cfg.LargeFileMB) MB in Downloads:" "WARN"
            $large | Select-Object -First 5 | ForEach-Object {
                Write-PlanLine "  $(Format-Bytes $_.Length)  $($_.Name)" "INFO"
            }
            Register-Action "Files" "MANUAL" "Review $($large.Count) large file(s) in Downloads" `
                -Detail "Files above $($Cfg.LargeFileMB) MB - delete installers/ISOs you no longer need"
        }
    }

    # Duplicate detection (MD5 hash, files < 500 MB)
    $safeDupDirs = @($Cfg.DupScanDirs | Where-Object { Test-OnSystemDrive $_ })
    $skipped     = @($Cfg.DupScanDirs | Where-Object { -not (Test-OnSystemDrive $_) })
    foreach ($s in $skipped) { Write-PlanLine "Skipping dup scan dir (not system drive): $s" "WARN" }
    Write-PlanLine "Scanning for duplicate files in: $($safeDupDirs -join ', ')..." "INFO"
    $candidates = @()
    foreach ($dir in $safeDupDirs) {
        if (Test-Path $dir) {
            $candidates += @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
                             Where-Object { $_.Length -gt 0 -and $_.Length -lt 500MB })
        }
    }

    $dupes = @()
    if ($candidates.Count -gt 1) {
        $bySize = $candidates | Group-Object Length | Where-Object { $_.Count -gt 1 }
        foreach ($grp in $bySize) {
            $hashed = $grp.Group | ForEach-Object {
                @{ F=$_; H=(Get-FileHash $_.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash }
            }
            $byHash = $hashed | Where-Object { $_.H } | Group-Object H | Where-Object { $_.Count -gt 1 }
            foreach ($hg in $byHash) {
                $sorted = $hg.Group | Sort-Object { $_.F.LastWriteTime } -Descending
                $dupes += $sorted | Select-Object -Skip 1  # keep newest, delete rest
            }
        }
    }

    if ($dupes.Count -gt 0) {
        $dupBytes = [long]($dupes | ForEach-Object { $_.F.Length } | Measure-Object -Sum).Sum
        Write-PlanLine "$($dupes.Count) duplicate file(s) found ($(Format-Bytes $dupBytes) recoverable):" "DEL"
        $dupes | Select-Object -First 5 | ForEach-Object {
            Write-PlanLine "  $($_.F.FullName) ($(Format-Bytes $_.F.Length))" "DEL"
        }
        if ($dupes.Count -gt 5) { Write-PlanLine "  ... and $($dupes.Count-5) more" "INFO" }
        $dupList  = $dupes
        $dupTotal = $dupBytes
        Register-Action "Files" "MANUAL" "Delete $($dupes.Count) duplicate file(s)" `
            -Detail "Keeping newest copy of each - review list before deleting manually"
    } else {
        Write-PlanLine "No duplicate files found in scanned directories" "KEEP"
    }
}

# ============================================================
#  MODULE: DISK
# ============================================================
function Collect-DiskActions {
    Show-Section "DISK"

    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($null -eq $d.Used) { continue }
        $total = $d.Used + $d.Free
        if ($total -lt 0.1GB) { continue }
        $freeGB  = [math]::Round($d.Free / 1GB, 1)
        $usedPct = [math]::Round($d.Used / $total * 100, 0)
        $filled  = [int]($usedPct / 5)
        $bar     = "[" + ("#" * $filled) + (" " * (20-$filled)) + "] $usedPct%"
        if ($freeGB -lt $Cfg.MinFreeGB) {
            Write-PlanLine "Drive $($d.Name): $bar  $freeGB GB free -- LOW SPACE!" "WARN"
            $dn = $d.Name; $fg = $freeGB
            Register-Action "Disk" "MANUAL" "Low disk space on drive $dn" `
                -Detail "Only $fg GB free (threshold: $($Cfg.MinFreeGB) GB) - clean up large files"
        } else {
            Write-PlanLine "Drive $($d.Name): $bar  $freeGB GB free" "KEEP"
        }
    }

    # SSD TRIM
    try {
        $vols = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" })
        foreach ($vol in $vols) {
            $type = "Unknown"
            try {
                $diskNum = (Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop).DiskNumber
                $phys    = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq $diskNum }
                if ($phys) { $type = $phys.MediaType }
            } catch {}

            if ($type -in @("SSD","Unspecified")) {
                Write-PlanLine "Drive $($vol.DriveLetter): (SSD) - will run TRIM" "ADD"
                $dl = $vol.DriveLetter
                Register-Action "Disk" "AUTO" "TRIM SSD $($vol.DriveLetter):" `
                    -Run { Optimize-Volume -DriveLetter $dl -ReTrim -ErrorAction SilentlyContinue }.GetNewClosure()
            } elseif ($type -eq "HDD") {
                Write-PlanLine "Drive $($vol.DriveLetter): (HDD) - defrag available manually" "MANUAL"
                Register-Action "Disk" "MANUAL" "Defragment HDD $($vol.DriveLetter):" `
                    -Detail "Run: Optimize-Volume -DriveLetter $($vol.DriveLetter) -Defrag"
            }
        }
    } catch { Write-PlanLine "Could not enumerate volumes for TRIM check" "WARN" }
}

# ============================================================
#  MODULE: DRIVERS
# ============================================================
function Collect-DriversActions {
    Show-Section "DRIVERS"
    try {
        $bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
        if ($bad.Count -eq 0) {
            Write-PlanLine "All device drivers: no errors detected" "KEEP"
        } else {
            Write-PlanLine "$($bad.Count) driver(s) with errors:" "WARN"
            foreach ($d in $bad) {
                $name = ConvertTo-AsciiSafe $d.Name
                Write-PlanLine "  $name [Error code $($d.ConfigManagerErrorCode)]" "WARN"
                Register-Action "Drivers" "MANUAL" "Fix driver: $name" `
                    -Detail "Error code $($d.ConfigManagerErrorCode) - update via Device Manager"
            }
        }
    } catch { Write-PlanLine "Driver check failed" "WARN" }
}

# ============================================================
#  MODULE: BACKUP
# ============================================================
function Collect-BackupActions {
    Show-Section "BACKUP"
    foreach ($dir in $Cfg.BackupDirs) {
        if (-not (Test-Path $dir)) {
            Write-PlanLine "Directory not found: $dir" "WARN"
            continue
        }
        $newest = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) {
            $days = [math]::Round(((Get-Date) - $newest.LastWriteTime).TotalDays, 1)
            if ($days -gt 7) {
                Write-PlanLine "$dir - last change: $days days ago - BACKUP RECOMMENDED" "WARN"
                Register-Action "Backup" "MANUAL" "Backup: $dir" `
                    -Detail "Last change $days days ago - copy to external drive or cloud"
            } else {
                Write-PlanLine "$dir - last change: $days day(s) ago - OK" "KEEP"
            }
        }
    }
    Register-Action "Backup" "MANUAL" "Verify off-site or cloud backup strategy" `
        -Detail "External drive, OneDrive, Google Drive, etc."
}

# ============================================================
#  REPORT GENERATOR
# ============================================================
function Export-Report([string]$Phase) {
    $auto   = @($script:Registry | Where-Object { $_['Type'] -eq "AUTO" })
    $manual = @($script:Registry | Where-Object { $_['Type'] -eq "MANUAL" })
    $bytes  = [long]($auto | ForEach-Object { $_['Bytes'] } | Measure-Object -Sum).Sum

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("PC MAINTENANCE REPORT - $Phase")
    [void]$sb.AppendLine("Generated : $(Get-Date)")
    [void]$sb.AppendLine("Machine   : $env:COMPUTERNAME  |  User: $env:USERNAME")
    [void]$sb.AppendLine(("=" * 60))
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("SUMMARY")
    [void]$sb.AppendLine("  Mode               : $Phase")
    [void]$sb.AppendLine("  Auto actions       : $($auto.Count)")
    [void]$sb.AppendLine("  Manual items       : $($manual.Count)")
    [void]$sb.AppendLine("  Space freed/saved  : $(Format-Bytes $bytes)")
    [void]$sb.AppendLine("")

    # Group by module
    $modules = ($script:Registry | ForEach-Object { $_['Module'] } | Select-Object -Unique | Sort-Object)
    foreach ($mod in $modules) {
        [void]$sb.AppendLine(("=" * 60))
        [void]$sb.AppendLine($mod.ToUpper())
        foreach ($a in ($script:Registry | Where-Object { $_['Module'] -eq $mod })) {
            $sym  = if ($a['Type'] -eq "AUTO") { "+" } else { "?" }
            $res  = if ($a['Output']) { "  -> $($a['Output'])" } else { "" }
            [void]$sb.AppendLine("  [$sym] $($a['Label'])$res")
            if ($a['Detail']) { [void]$sb.AppendLine("      $($a['Detail'])") }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(("=" * 60))
    [void]$sb.AppendLine("MANUAL ACTIONS REQUIRED")
    foreach ($a in $manual) {
        [void]$sb.AppendLine("  [!] [$($a['Module'])] $($a['Label'])")
        if ($a['Detail']) { [void]$sb.AppendLine("      $($a['Detail'])") }
    }

    $content  = $sb.ToString()
    $rPath    = Join-Path $Cfg.ReportDir "report_${Phase}_${Timestamp}.txt"
    $desktop  = "$env:USERPROFILE\Desktop\PC_Maintenance_Report.txt"

    [System.IO.File]::WriteAllText($rPath,   $content, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($desktop, $content, [System.Text.Encoding]::UTF8)

    return $rPath
}

# ============================================================
#  MAIN
# ============================================================
$modeColor = if ($Mode -eq "Plan") { "Cyan" } else { "Green" }
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  PC MAINTENANCE v2.0  --  $($Mode.ToUpper()) MODE" -ForegroundColor $modeColor
Write-Host "  $(Get-Date)  |  $env:COMPUTERNAME  |  $env:USERNAME" -ForegroundColor DarkGray
Write-Host ("=" * 70) -ForegroundColor DarkCyan

if ($Mode -eq "Plan") {
    Write-Host ""
    Write-Host "  Analyzing system... (no changes will be made in Plan mode)" -ForegroundColor DarkGray
}

# --- Collect all planned actions (always runs regardless of mode) ---
Collect-SecurityActions
Collect-CleanupActions
Collect-StartupActions
Collect-FileAnalysisActions
Collect-DiskActions
Collect-DriversActions
Collect-BackupActions

# --- Plan summary ---
$autoList   = @($script:Registry | Where-Object { $_['Type'] -eq "AUTO" })
$manualList = @($script:Registry | Where-Object { $_['Type'] -eq "MANUAL" })
$totalBytes = [long]($autoList | ForEach-Object { $_['Bytes'] } | Measure-Object -Sum).Sum

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  PLAN SUMMARY" -ForegroundColor White
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  AUTO-fixable actions : $($autoList.Count)" -ForegroundColor Green
Write-Host "  Manual items needed  : $($manualList.Count)" -ForegroundColor Yellow
Write-Host "  Estimated space freed: $(Format-Bytes $totalBytes)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Breakdown by module:" -ForegroundColor DarkGray
$script:Registry | Group-Object { $_['Module'] } | Sort-Object Name | ForEach-Object {
    $a = @($_.Group | Where-Object { $_['Type'] -eq "AUTO" }).Count
    $m = @($_.Group | Where-Object { $_['Type'] -eq "MANUAL" }).Count
    $b = [long]($_.Group | ForEach-Object { $_['Bytes'] } | Measure-Object -Sum).Sum
    $bStr = if ($b -gt 0) { "  [$(Format-Bytes $b)]" } else { "" }
    Write-Host ("  {0,-12} {1} auto, {2} manual{3}" -f $_.Name, $a, $m, $bStr) -ForegroundColor White
}
Write-Host ""

$rPath = Export-Report -Phase $Mode
Write-Log "Report exported: $rPath" "OK"
Write-Host "  Report: $env:USERPROFILE\Desktop\PC_Maintenance_Report.txt" -ForegroundColor DarkGray
Write-Host ""

if ($Mode -eq "Plan") {
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  No changes were made." -ForegroundColor DarkGray
    Write-Host "  To execute all $($autoList.Count) auto-fixable actions, run:" -ForegroundColor White
    Write-Host ""
    Write-Host "    .\maintenance.ps1 -Mode Apply" -ForegroundColor Yellow
    Write-Host ""
} else {
    # ----------------------------------------------------------------
    # APPLY
    # ----------------------------------------------------------------
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  APPLYING $($autoList.Count) ACTIONS" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""

    $i = 0
    foreach ($action in $autoList) {
        $i++
        $label = $action['Label']
        Write-Host "  [$i/$($autoList.Count)] [$($action['Module'])] $label" -ForegroundColor White
        try {
            & $action['Run']
            $action['OK']     = $true
            $action['Output'] = "OK"
            Write-Host "    OK" -ForegroundColor Green
            Write-Log "APPLY OK: [$($action['Module'])] $label" "OK"
        } catch {
            $action['OK']     = $false
            $action['Output'] = "FAILED: $_"
            Write-Host "    FAILED: $_" -ForegroundColor Red
            Write-Log "APPLY FAILED: [$($action['Module'])] $label -- $_" "ERR"
        }
    }

    $rPath   = Export-Report -Phase "Apply_Results"
    $success = @($autoList | Where-Object { $_['OK'] -eq $true }).Count
    $failed  = @($autoList | Where-Object { $_['OK'] -eq $false }).Count

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  ALL TASKS FINISHED" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Succeeded : $success" -ForegroundColor Green
    if ($failed -gt 0) { Write-Host "  Failed    : $failed" -ForegroundColor Red }
    Write-Host "  Log file  : $LogFile" -ForegroundColor DarkGray
    Write-Host "  Report    : $env:USERPROFILE\Desktop\PC_Maintenance_Report.txt" -ForegroundColor Cyan
    Write-Host ""

    if ($manualList.Count -gt 0) {
        Write-Host "  $($manualList.Count) item(s) require your attention:" -ForegroundColor Yellow
        foreach ($a in $manualList) {
            Write-Host "  [!] [$($a['Module'])] $($a['Label'])" -ForegroundColor Yellow
            if ($a['Detail']) { Write-Host "      $($a['Detail'])" -ForegroundColor DarkGray }
        }
        Write-Host ""
    }
}
