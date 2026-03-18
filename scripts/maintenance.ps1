#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PC Maintenance v3.0 - Plan & Apply workflow

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
      Documents    - File audit, semantic classification, content analysis
      Drivers      - Device error detection
      Backup       - Backup reminder check
      Network      - Active adapters, DNS ping, latency check
      Temperature  - CPU thermal zones via ACPI
      Processes    - Top 5 by CPU and RAM, high-memory warnings

.PARAMETER Mode
    Plan  (default) - Show what WOULD be done. Safe, no changes made.
    Apply           - Execute all AUTO-fixable actions.

.PARAMETER Interactive
    Show a module-selection menu before running. Choose which modules to execute.

.EXAMPLE
    .\maintenance.ps1
    .\maintenance.ps1 -Mode Apply
    .\maintenance.ps1 -Interactive
    .\maintenance.ps1 -Interactive -Mode Apply
#>

param(
    [ValidateSet("Plan","Apply")]
    [string]$Mode = "Plan",
    [switch]$Interactive
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
#  ZONE.IDENTIFIER & FILE ANALYSIS HELPERS
# ============================================================

function Read-ZoneIdentifier([string]$FilePath) {
    <#
    .SYNOPSIS
    Reads the Zone.Identifier alternate data stream to determine file origin
    Zone Values: 0=Local, 1=Intranet, 3=Internet (HIGH RISK), 4=Restricted
    #>
    try {
        # Method 1: Direct stream read (PowerShell 5.1+)
        $zoneStream = "${FilePath}:Zone.Identifier"
        $zone = Get-Content $zoneStream -Raw -ErrorAction SilentlyContinue -Encoding ASCII
        if ($zone -match 'ZoneId=(\d+)') {
            return [int]$matches[1]
        }
    }
    catch { }

    return -1  # Unknown if not found
}

function Get-ZoneIdentifierSafe([string]$FilePath) {
    <#
    .SYNOPSIS
    Safe wrapper for Read-ZoneIdentifier with error handling and labeling
    #>
    try {
        $zone = Read-ZoneIdentifier $FilePath
        $zoneMap = @{
            0 = "Local Computer"
            1 = "Intranet"
            3 = "Internet"
            4 = "Restricted"
            -1 = "Unknown"
        }

        return @{
            Zone       = $zone
            ZoneName   = $zoneMap[if ($zone -in $zoneMap.Keys) { $zone } else { -1 }]
            IsInternet = ($zone -eq 3)
            IsRestricted = ($zone -eq 4)
            Risky      = ($zone -in @(3, 4))
        }
    }
    catch {
        return @{ Zone = -1; ZoneName = "Unknown"; IsInternet = $false; IsRestricted = $false; Risky = $false }
    }
}

function Get-FileRiskMetadata([string]$FilePath) {
    <#
    .SYNOPSIS
    Collects comprehensive metadata for file risk assessment
    #>
    try {
        $file = Get-Item $FilePath -ErrorAction Stop
        $hash = (Get-FileHash $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash

        $metadata = @{
            Name           = $file.Name
            Size           = $file.Length
            Extension      = $file.Extension.ToLower()
            CreatedTime    = $file.CreationTime
            ModifiedTime   = $file.LastWriteTime
            ZoneIdentifier = (Read-ZoneIdentifier $FilePath)
            SHA256         = $hash
            IsExecutable   = $false
        }

        # Detection: Executables and scripts
        $dangerousExts = @(".exe", ".msi", ".scr", ".vbs", ".js", ".bat", ".cmd", ".ps1", ".com", ".pif")
        $metadata.IsExecutable = $dangerousExts -contains $metadata.Extension

        # Detection: Code artifact patterns
        if ($metadata.Extension -in @(".ps1", ".bat", ".cmd", ".vbs")) {
            try {
                $content = Get-Content $FilePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $metadata.HasSuspiciousPatterns = @()

                $suspiciousPatterns = @(
                    "Invoke-WebRequest",
                    "DownloadString","DownloadFile",
                    "New-Object.*COM",
                    "WScript.Shell",
                    "rundll32",
                    "cmd /c",
                    "powershell -enc",
                    "IEx",
                    "-NoExit",
                    "-nop",
                    "-enc"
                )

                foreach ($pattern in $suspiciousPatterns) {
                    if ($content -match $pattern) {
                        $metadata.HasSuspiciousPatterns += $pattern
                    }
                }
            }
            catch { }
        }

        # Detection: Digital signature (for executables)
        if ($metadata.IsExecutable -and $metadata.Extension -eq ".exe") {
            try {
                $sig = Get-AuthenticodeSignature $FilePath -ErrorAction SilentlyContinue
                $metadata.Signed = ($sig.Status -eq "Valid")
                if ($sig.SignerCertificate) {
                    $metadata.SignerCompany = ($sig.SignerCertificate.Subject -split ',')[0]
                }
            }
            catch { }
        }

        return $metadata
    }
    catch {
        return @{ Name = [IO.Path]::GetFileName($FilePath); Error = $true }
    }
}

function Calculate-RiskScore($FileMetadata) {
    <#
    .SYNOPSIS
    Computes 0-100 risk score based on file metadata
    Returns: @{ Score=int, Level="LOW"|"MEDIUM"|"HIGH"|"CRITICAL", Reasons=@() }
    #>
    if ($FileMetadata.Error) {
        return @{ Score = 0; Level = "UNKNOWN"; Reasons = @("Could not analyze file") }
    }

    $score = 0
    $reasons = @()

    # --- Extension risk (0-30 points) ---
    $criticalExes = @(".exe", ".msi", ".scr", ".bat", ".cmd", ".vbs", ".ps1")
    if ($FileMetadata.Extension -in $criticalExes) {
        $score += 20
        $reasons += "Executable file type"
    }

    # --- Zone risk (0-25 points) ---
    if ($FileMetadata.ZoneIdentifier -eq 3) {
        $score += 20
        $reasons += "Downloaded from Internet"
    }
    elseif ($FileMetadata.ZoneIdentifier -eq 4) {
        $score += 25
        $reasons += "From restricted zone"
    }

    # --- Size risk (0-15 points) ---
    if ($FileMetadata.Size -gt 100MB) {
        $score += 8
        $reasons += "Large file size (>100MB)"
    }

    # --- Signature risk (0-20 points) ---
    if ($FileMetadata.IsExecutable -and $FileMetadata.Signed -eq $false) {
        $score += 15
        $reasons += "Not digitally signed"
    }

    # --- Suspicious code patterns (0-30 points) ---
    if ($FileMetadata.HasSuspiciousPatterns -and $FileMetadata.HasSuspiciousPatterns.Count -gt 0) {
        $score += 20
        $reasons += "Suspicious code patterns detected: $($FileMetadata.HasSuspiciousPatterns -join ', ')"
    }

    # --- Trust heuristic: Known vendors (reduce score) ---
    $trustedVendors = @("Microsoft", "Adobe", "Google", "Mozilla", "Apple", "Oracle", "Intel", "NVIDIA")
    if ($FileMetadata.SignerCompany) {
        foreach ($vendor in $trustedVendors) {
            if ($FileMetadata.SignerCompany -like "*$vendor*") {
                $score = [Math]::Max(0, $score - 15)
                $reasons += "Signed by trusted vendor"
                break
            }
        }
    }

    # --- Age heuristic: Very old files ---
    $ageMonths = [Math]::Round(((Get-Date) - $FileMetadata.ModifiedTime).TotalDays / 30)
    if ($ageMonths -gt 24) {
        $score += 5
        $reasons += "Not modified in $ageMonths months"
    }

    return @{
        Score   = [Math]::Min(100, $score)
        Level   = if ($score -ge 70) { "CRITICAL" } elseif ($score -ge 45) { "HIGH" } elseif ($score -ge 25) { "MEDIUM" } else { "LOW" }
        Reasons = $reasons
    }
}

function New-SuspiciousFileVault {
    <#
    .SYNOPSIS
    Creates or returns path to the personal quarantine vault for suspicious files
    #>
    $vaultPath = Join-Path $env:USERPROFILE ".suspicious_quarantine"

    if (-not (Test-Path $vaultPath)) {
        $null = New-Item -ItemType Directory -Path $vaultPath -Force -ErrorAction SilentlyContinue
        $null = cmd /c attrib +h "$vaultPath" 2>$null  # Hide folder

        # Create README
        $readmeContent = @"
QUARANTINE FOLDER
=================
This folder contains files flagged as potentially suspicious by PC Maintenance.

FILES ARE NOT DELETED - they are moved here for manual review.

** DO NOT RUN FILES FROM THIS FOLDER unless you are certain they are safe **
** DO NOT connect removable media to copy files from here **

To permanently delete a file:
  Remove-Item "$vaultPath\filename.ext" -Force

To restore a file, manually move it back and unblock it.

See quarantine_log.jsonl for audit trail.
"@
        $readmeContent | Out-File (Join-Path $vaultPath "README.txt") -Encoding UTF8 -Force -ErrorAction SilentlyContinue
    }

    return $vaultPath
}

function Move-SuspiciousFile {
    <#
    .SYNOPSIS
    Moves a suspicious file to the quarantine vault with audit logging
    #>
    param(
        [string]$FilePath,
        [string]$Reason = "Risk assessment flagged"
    )

    $vaultPath = New-SuspiciousFileVault
    try {
        $file = Get-Item $FilePath -ErrorAction Stop

        # Create timestamped subfolder
        $dateFolder = Join-Path $vaultPath (Get-Date -Format "yyyy-MM")
        $null = New-Item -ItemType Directory -Path $dateFolder -Force -ErrorAction SilentlyContinue

        # Avoid collisions
        $destFile = Join-Path $dateFolder $file.Name
        $counter = 1
        while (Test-Path $destFile) {
            $destFile = Join-Path $dateFolder "$($file.BaseName)_$counter$($file.Extension)"
            $counter++
        }

        # Move file
        Move-Item -Path $FilePath -Destination $destFile -Force -ErrorAction SilentlyContinue

        # Log
        $logEntry = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            OriginalPath = $FilePath
            FileName = $file.Name
            FileSize = $file.Length
            Reason = $Reason
            SHA256 = (Get-FileHash $file -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            QuarantinePath = $destFile
        } | ConvertTo-Json -Compress

        Add-Content -Path (Join-Path $vaultPath "quarantine_log.jsonl") -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue

        Write-PlanLine "Quarantined: $($file.Name)" "WARN"
        return $destFile
    }
    catch {
        Write-PlanLine "Failed to quarantine $FilePath : $_" "WARN"
        return $null
    }
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

    # Old report rotation
    $oldReports = @(Get-ChildItem $Cfg.ReportDir -Filter "report_*.txt" -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Cfg.LogRotateDays) })
    if ($oldReports.Count -gt 0) {
        Write-PlanLine "Delete $($oldReports.Count) report(s) older than $($Cfg.LogRotateDays) days" "DEL"
        Register-Action "Cleanup" "AUTO" "Rotate old reports" `
            -Run { $oldReports | Remove-Item -Force -ErrorAction SilentlyContinue }.GetNewClosure()
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
#  MODULE: DOCUMENTS AUDIT
# ============================================================
function Collect-DocumentsActions {
    Show-Section "DOCUMENTS AUDIT"

    $userRoot  = $env:USERPROFILE
    $scanDirs  = @(
        @{ P="$userRoot\Documents"; L="Documents" }
        @{ P="$userRoot\Desktop";   L="Desktop"   }
        @{ P="$userRoot\Downloads"; L="Downloads"  }
        @{ P="$userRoot\Pictures";  L="Pictures"   }
        @{ P="$userRoot\Videos";    L="Videos"     }
        @{ P="$userRoot\Music";     L="Music"      }
    )

    # Extension categories
    $catMap = @{
        Documents = @(".pdf",".doc",".docx",".xls",".xlsx",".ppt",".pptx",".odt",".ods",".odp",".txt",".rtf",".csv",".md")
        Images    = @(".jpg",".jpeg",".png",".gif",".bmp",".tiff",".webp",".svg",".heic",".raw",".cr2",".nef")
        Videos    = @(".mp4",".mkv",".avi",".mov",".wmv",".flv",".webm",".m4v",".ts")
        Audio     = @(".mp3",".flac",".wav",".aac",".ogg",".m4a",".wma")
        Archives  = @(".zip",".rar",".7z",".tar",".gz",".bz2",".iso",".img")
        Executables = @(".exe",".msi",".bat",".ps1",".cmd",".vbs",".jar")
        Code      = @(".py",".js",".ts",".cs",".cpp",".c",".h",".java",".go",".rs",".php",".html",".css",".json",".xml",".yml",".yaml",".sql")
    }

    # Sensitive filename patterns (flag for review, never read contents)
    $sensitivePatterns = @(
        "*password*","*contrase*","*clave*","*passwd*","*secret*","*credential*",
        "*private*key*","*id_rsa*","*token*","*api_key*","*backup_code*",
        "*wallet*","*seed*phrase*","*recovery*code*","*2fa*"
    )

    $grandTotal    = 0L
    $grandCount    = 0
    $allSensitive  = @()
    $allOrphaned   = @()
    $allOldLarge   = @()
    $emptyFoldersByDir = @{}  # BUG FIX: Accumulate empty folders by directory to avoid variable overwrites

    foreach ($dir in $scanDirs) {
        if (-not (Test-Path $dir.P)) { continue }

        $files = @(Get-ChildItem $dir.P -File -Recurse -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) {
            Write-PlanLine "$($dir.L): empty" "KEEP"
            continue
        }

        $totalBytes = [long]($files | Measure-Object -Property Length -Sum).Sum
        $grandTotal += $totalBytes
        $grandCount += $files.Count

        Write-PlanLine "$($dir.L): $($files.Count) files, $(Format-Bytes $totalBytes)" "INFO"

        # --- Category breakdown ---
        $counts = @{}
        $sizes  = @{}
        foreach ($f in $files) {
            $ext = $f.Extension.ToLower()
            $matched = $false
            foreach ($cat in $catMap.Keys) {
                if ($catMap[$cat] -contains $ext) {
                    $counts[$cat] = ($counts[$cat] -as [int]) + 1
                    $sizes[$cat]  = ($sizes[$cat]  -as [long]) + $f.Length
                    $matched = $true
                    break
                }
            }
            if (-not $matched) {
                $counts["Other"] = ($counts["Other"] -as [int]) + 1
                $sizes["Other"]  = ($sizes["Other"]  -as [long]) + $f.Length
            }
        }
        foreach ($cat in ($counts.Keys | Sort-Object)) {
            if ($counts[$cat] -gt 0) {
                $catLabel = $cat
                Write-PlanLine "  ${catLabel}: $($counts[$cat]) files ($(Format-Bytes $sizes[$cat]))" "INFO"
            }
        }

        # --- Executables in user folders (security flag) ---
        $exes = @($files | Where-Object { $_.Extension -in @(".exe",".msi",".bat",".cmd",".vbs") })
        if ($exes.Count -gt 0) {
            Write-PlanLine "  $($exes.Count) executable(s) found in $($dir.L) - review recommended" "WARN"
            $exes | Select-Object -First 5 | ForEach-Object {
                Write-PlanLine "    $($_.Name) ($(Format-Bytes $_.Length))" "INFO"
            }
            if ($exes.Count -gt 5) { Write-PlanLine "    ... and $($exes.Count - 5) more" "INFO" }
            Register-Action "Documents" "MANUAL" "Review executables in $($dir.L)" `
                -Detail "$($exes.Count) .exe/.msi/.bat files - move to a dedicated folder or delete installers"
        }

        # --- Sensitive filename detection ---
        $sensitive = @($files | Where-Object {
            $name = $_.Name.ToLower()
            $hit  = $false
            foreach ($pat in $sensitivePatterns) { if ($name -like $pat) { $hit = $true; break } }
            $hit
        })
        if ($sensitive.Count -gt 0) {
            Write-PlanLine "  $($sensitive.Count) file(s) with sensitive-sounding names in $($dir.L)" "WARN"
            $sensitive | ForEach-Object {
                Write-PlanLine "    $($_.Name)" "WARN"
            }
            $allSensitive += $sensitive
        }

        # --- Old + large files (not accessed in 180 days, > 100 MB) ---
        $cutoff  = (Get-Date).AddDays(-180)
        $oldLarge = @($files | Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Length -gt 100MB } | Sort-Object Length -Descending)
        if ($oldLarge.Count -gt 0) {
            $olBytes = [long]($oldLarge | Measure-Object -Property Length -Sum).Sum
            Write-PlanLine "  $($oldLarge.Count) large file(s) not modified in 6+ months ($(Format-Bytes $olBytes)):" "WARN"
            $oldLarge | Select-Object -First 3 | ForEach-Object {
                $age = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays / 30, 0)
                Write-PlanLine "    $(Format-Bytes $_.Length)  $($_.Name)  [~$age months old]" "INFO"
            }
            if ($oldLarge.Count -gt 3) { Write-PlanLine "    ... and $($oldLarge.Count - 3) more" "INFO" }
            $allOldLarge += $oldLarge
        }

        # --- Empty subfolders ---
        $emptyFolders = @(Get-ChildItem $dir.P -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { @(Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0 })
        if ($emptyFolders.Count -gt 0) {
            Write-PlanLine "  $($emptyFolders.Count) empty subfolder(s) in $($dir.L)" "DEL"
            # BUG FIX: Store by directory name to avoid variable overwrites in closure
            $emptyFoldersByDir[$dir.L] = $emptyFolders
        }
    }

    # BUG FIX: Register delete actions AFTER loop to ensure correct variable captures
    foreach ($dirLabel in $emptyFoldersByDir.Keys) {
        $folderList = $emptyFoldersByDir[$dirLabel]
        $currentDirLabel = $dirLabel  # Capture direction label for this iteration
        Register-Action "Documents" "AUTO" "Delete $($folderList.Count) empty folder(s) in $currentDirLabel" `
            -Run (
                {
                    param($folders)
                    $folders | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
                }.Bind($null, $folderList)
            )
    }

    # --- Semantic document classification ---
    # Scans filenames to identify what kind of personal documents the user has
    $semanticDirs = @("$userRoot\Documents", "$userRoot\Desktop", "$userRoot\Downloads")
    $docExtensions = @(".pdf",".doc",".docx",".xls",".xlsx",".jpg",".jpeg",".png",".txt",".rtf",".csv",".odt",".heic")

    $semanticCategories = [ordered]@{
        "Identidad"       = @("*dni*","*pasaporte*","*passport*","*nie*","*nif*","*carnet*","*id_card*","*cedula*","*identidad*","*documento_nacional*")
        "Certificados"    = @("*certificado*","*certificate*","*diploma*","*titulo*","*titulo_*","*acreditacion*","*homologacion*","*titulo_universitario*","*grado*","*master*","*formacion*","*curso*","*credencial*")
        "Laboral"         = @("*nomina*","*nominas*","*contrato*","*contrato_trabajo*","*alta_laboral*","*baja_laboral*","*finiquito*","*irpf*","*antiguedad*","*vida_laboral*","*cv*","*curriculum*","*resume*")
        "Fiscal/Hacienda" = @("*renta*","*declaracion*","*hacienda*","*irpf*","*aeat*","*modelo_*","*borrador*","*liquidacion*","*tributaria*","*iva*","*autonomo*")
        "Bancario"        = @("*extracto*","*banco*","*transferencia*","*hipoteca*","*prestamo*","*credito*","*iban*","*cuenta_*","*tarjeta*","*movimientos*","*banking*")
        "Facturas/Recibos"= @("*factura*","*invoice*","*recibo*","*ticket*","*albaran*","*presupuesto*","*pago*","*receipt*","*compra*")
        "Seguros"         = @("*seguro*","*poliza*","*insurance*","*cobertura*","*siniestro*","*mutua*","*aseguradora*")
        "Medico/Salud"    = @("*medico*","*hospital*","*receta*","*analitica*","*informe_medico*","*clinica*","*sanitario*","*vacuna*","*historial*","*diagnostico*","*farmacia*")
        "Propiedad"       = @("*escritura*","*catastro*","*registro*","*contrato_alquiler*","*arrendamiento*","*inmueble*","*vivienda*","*vehiculo*","*matricula*","*itv*","*permiso_circulacion*")
        "Educacion"       = @("*expediente*","*matricula*","*beca*","*notas*","*calificaciones*","*universidad*","*colegio*","*instituto*","*tfg*","*tfm*","*tesis*")
        "Fotografias"     = @("*foto*","*photo*","*photo_*","*img_*","*dsc_*","*picture*","*selfie*","*camara*","*screenshot*","*captura*")
        "Instaladores"    = @("*.exe","*.msi","*setup*","*installer*","*install_*","*_setup*")
    }

    Show-Section "DOCUMENTS AUDIT - SEMANTIC CLASSIFICATION"
    Write-PlanLine "Scanning filenames to identify document types..." "INFO"
    Write-PlanLine "(Analysis by filename - file contents are never read)" "INFO"
    Write-PlanLine "" "INFO"

    $semanticResults = @{}
    $semanticSamples = @{}
    $allDocFiles = @()

    foreach ($sDir in $semanticDirs) {
        if (Test-Path $sDir) {
            $allDocFiles += @(Get-ChildItem $sDir -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $docExtensions -contains $_.Extension.ToLower() })
        }
    }

    foreach ($catName in $semanticCategories.Keys) {
        $patterns = $semanticCategories[$catName]
        $matched  = @($allDocFiles | Where-Object {
            $n = $_.BaseName.ToLower() -replace '[_\-\s\.]+', '_'
            $hit = $false
            foreach ($p in $patterns) {
                if ($n -like $p.ToLower() -or $_.Name.ToLower() -like $p.ToLower()) { $hit = $true; break }
            }
            $hit
        })
        if ($matched.Count -gt 0) {
            $semanticResults[$catName] = $matched   # store all files, not just count
            $semanticSamples[$catName] = $matched | Sort-Object LastWriteTime -Descending | Select-Object -First 4
        }
    }

    if ($semanticResults.Count -eq 0) {
        Write-PlanLine "No documents matched known semantic categories" "INFO"
    } else {
        foreach ($catName in $semanticResults.Keys) {
            $count   = $semanticResults[$catName].Count
            $samples = $semanticSamples[$catName]
            $newest  = ($samples | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            $newestStr = if ($newest) { $newest.ToString("yyyy-MM-dd") } else { "?" }
            Write-PlanLine "$catName - $count file(s)  [newest: $newestStr]" "ADD"
            foreach ($s in $samples) {
                $loc = $s.DirectoryName -replace [regex]::Escape($userRoot), "~"
                Write-PlanLine "    $($s.Name)  [$loc]" "INFO"
            }
            if ($count -gt 4) { Write-PlanLine "    ... and $($count - 4) more" "INFO" }
        }

        # --- AUTO: create folder structure and move personal document files ---
        # Only move actual document files (not images/game assets) from Desktop or Downloads
        $moveableExts    = @(".pdf",".doc",".docx",".xls",".xlsx",".odt",".ods",".rtf",".csv")
        $gamePathMarkers = @("\My Games\","\ANIL ","\Pokemon ","\HoI4\","\Hearts of Iron","\Farming Simulator","\iRacing\","\steamapps\","\Assetto Corsa\","\BeamNG\")
        $catToFolder     = @{
            "Identidad"        = "Identidad"
            "Certificados"     = "Certificados"
            "Laboral"          = "Laboral"
            "Fiscal/Hacienda"  = "Fiscal"
            "Bancario"         = "Bancario"
            "Facturas/Recibos" = "Facturas"
            "Seguros"          = "Seguros"
            "Medico/Salud"     = "Medico"
            "Propiedad"        = "Propiedad"
            "Educacion"        = "Educacion"
        }

        $filesToMove = @()   # list of @{File; Dest}
        foreach ($catName in $catToFolder.Keys) {
            if (-not $semanticResults.ContainsKey($catName)) { continue }
            $folderName = $catToFolder[$catName]
            $destFolder = "$userRoot\Documents\$folderName"
            foreach ($f in $semanticResults[$catName]) {
                if ($moveableExts -notcontains $f.Extension.ToLower()) { continue }
                $isGame = $false
                foreach ($marker in $gamePathMarkers) { if ($f.FullName -like "*$marker*") { $isGame = $true; break } }
                if ($isGame) { continue }
                if ($f.DirectoryName -eq $destFolder) { continue }  # already in right place
                $filesToMove += @{ File=$f; Dest=$destFolder; Cat=$catName }
            }
        }

        if ($filesToMove.Count -gt 0) {
            Write-PlanLine "" "INFO"
            Write-PlanLine "Will organize $($filesToMove.Count) personal document(s) into Documents subfolders:" "ADD"
            foreach ($m in $filesToMove) {
                $src = $m.File.DirectoryName -replace [regex]::Escape($userRoot), "~"
                Write-PlanLine "  [$($m.Cat)]  $($m.File.Name)" "ADD"
                Write-PlanLine "    from: $src" "INFO"
                Write-PlanLine "    to:   ~\Documents\$($catToFolder[$m.Cat])\" "INFO"
            }
            $moveList = $filesToMove
            Register-Action "Documents" "AUTO" "Organize $($filesToMove.Count) personal document(s) into subfolders" `
                -Detail "Creates category subfolders in Documents and moves files from Desktop/Downloads" `
                -Run {
                    foreach ($m in $moveList) {
                        $dest = $m.Dest
                        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                        $destFile = Join-Path $dest $m.File.Name
                        # Avoid overwriting: append timestamp if file already exists at dest
                        if (Test-Path $destFile) {
                            $stamp    = Get-Date -Format "yyyyMMdd_HHmmss"
                            $destFile = Join-Path $dest "$($m.File.BaseName)_$stamp$($m.File.Extension)"
                        }
                        Move-Item -Path $m.File.FullName -Destination $destFile -ErrorAction SilentlyContinue
                    }
                }.GetNewClosure()
        } else {
            Write-PlanLine "" "INFO"
            Write-PlanLine "All identified personal documents already in correct subfolders" "KEEP"
        }

        # Flag installers found among documents
        if ($semanticResults.ContainsKey("Instaladores")) {
            $instCount = $semanticResults["Instaladores"].Count
            Register-Action "Documents" "MANUAL" "Remove $instCount installer(s) mixed with documents" `
                -Detail "Executable installer files (.exe/.msi) found among personal documents - move to Downloads or delete after installation"
        }
    }

    # --- Global summary ---
    Write-PlanLine "" "INFO"
    Write-PlanLine "Total across all user folders: $grandCount files, $(Format-Bytes $grandTotal)" "INFO"

    # --- Sensitive files global action ---
    if ($allSensitive.Count -gt 0) {
        Register-Action "Documents" "MANUAL" "Secure $($allSensitive.Count) sensitive-named file(s)" `
            -Detail "Files with names like 'password', 'clave', 'token', etc. - move to encrypted vault (KeePass, BitLocker) or delete if no longer needed"
    }

    # --- Old large files global action ---
    if ($allOldLarge.Count -gt 0) {
        $olTotalBytes = [long]($allOldLarge | Measure-Object -Property Length -Sum).Sum
        Register-Action "Documents" "MANUAL" "Review $($allOldLarge.Count) large old file(s) ($(Format-Bytes $olTotalBytes))" `
            -Detail "Files over 100 MB not modified in 6+ months - archive to external drive or delete"
    }

    # --- Content-based document classification ---
    Show-Section "DOCUMENTS AUDIT - CONTENT ANALYSIS"
    Write-PlanLine "Reading document contents to classify accurately..." "INFO"
    Write-PlanLine "(Scans text inside files - images are skipped)" "INFO"
    Write-PlanLine "" "INFO"

    $contentScanDirs = @("$userRoot\Documents", "$userRoot\Desktop", "$userRoot\Downloads")
    $contentExts     = @(".pdf",".txt",".md",".csv",".docx",".xlsx",".doc",".rtf",".odt")
    $maxFileSizeBytes = 8MB

    # Folder path fragments to exclude (games, mods, dev tools, etc.)
    $contentExcludePaths = @(
        "\My Games\", "\AppData\", "\node_modules\", "\steamapps\",
        "\Hearts of Iron IV\", "\HoI4\", "\ANIL V3.52\", "\Pokemon ",
        "\Farming Simulator", "\iRacing\", "\Assetto Corsa\", "\BeamNG\",
        "\.git\", "\vendor\", "\dist\", "\build\", "\__pycache__\",
        "\Common Redist\", "\Redist\", "\DirectX\", "\VC_redist"
    )

    # Content keyword categories (Spanish + English)
    $contentCats = [ordered]@{
        "Identidad/DNI"   = @("dni","nie","nif","pasaporte","passport","documento nacional","numero de identidad","identity card","\d{8}[A-Za-z]","[XYZxyz]\d{7}[A-Za-z]")
        "Nominas/Laboral" = @("nomina","nómina","salario bruto","salario neto","finiquito","contrato de trabajo","alta en seguridad social","baja voluntaria","trabajador","empleado","empresa","convenio colectivo","pagas extras","retribucion","remuneracion")
        "Fiscal/AEAT"     = @("aeat","agencia tributaria","declaracion de la renta","irpf","modelo 100","modelo 303","base imponible","rendimientos del trabajo","hacienda","liquidacion fiscal","renta 20","cuota integra")
        "Bancario/IBAN"   = @("iban","cuenta corriente","transferencia","extracto","saldo","movimientos","banco","bbva","santander","caixabank","sabadell","bankinter","ing ","openbank","bizum","tarjeta de credito","hipoteca","prestamo","ES\d{2}[\s\d]{20}")
        "Facturas"        = @("factura","invoice","numero de factura","fecha de emision","base imponible","iva 21","iva 10","total a pagar","importe total","euros","proveedor","cliente","cif","n.i.f")
        "Seguros"         = @("poliza","póliza","numero de poliza","tomador","asegurado","cobertura","prima","siniestro","aseguradora","mutua","mapfre","allianz","axa ","zurich","generali","sanitas","adeslas")
        "Medico/Salud"    = @("diagnostico","diagnóstico","historia clinica","informe medico","receta","medicamento","dosis","hospital","clinica","medico","paciente","fecha de consulta","centro de salud","seguridad social","analisis","resultado","prueba")
        "Propiedad"       = @("escritura","catastro","referencia catastral","contrato de arrendamiento","alquiler","arrendatario","arrendador","inmueble","vivienda","finca","registro de la propiedad","permiso de circulacion","itv","bastidor","matricula")
        "Educacion"       = @("certificado de estudios","expediente academico","calificaciones","matricula","beca","universidad","titulo universitario","grado en","master en","tfg","tfm","tesis","nota media","creditos ects","centro educativo")
        "Certificados"    = @("certificado","certificate","certifica que","acredita que","ha superado","ha completado","con fecha","con una duracion","horas lectivas","diploma","titulo de","en nombre de")
    }

    function Get-FileText([System.IO.FileInfo]$f) {
        $ext = $f.Extension.ToLower()
        try {
            if ($ext -eq ".docx" -or $ext -eq ".xlsx" -or $ext -eq ".odt") {
                Add-Type -Assembly System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                $zip    = [System.IO.Compression.ZipFile]::OpenRead($f.FullName)
                $xmlEntry = $zip.Entries | Where-Object { $_.FullName -match "word/document\.xml|xl/sharedStrings\.xml|content\.xml" } | Select-Object -First 1
                if ($xmlEntry) {
                    $reader = New-Object System.IO.StreamReader($xmlEntry.Open())
                    $raw    = $reader.ReadToEnd()
                    $reader.Close()
                    $zip.Dispose()
                    return ($raw -replace '<[^>]+>', ' ') -replace '\s+', ' '
                }
                $zip.Dispose()
                return ""
            } elseif ($ext -eq ".pdf") {
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                $ascii = [System.Text.Encoding]::Latin1.GetString($bytes)
                # Extract readable text runs from PDF binary
                $chunks = [regex]::Matches($ascii, '\(([^\)]{4,200})\)') | ForEach-Object { $_.Groups[1].Value }
                return ($chunks -join ' ') -replace '\s+', ' '
            } elseif ($ext -in @(".txt",".md",".csv",".rtf")) {
                return (Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
            }
        } catch {}
        return ""
    }

    # Collect candidate files (excluding game/dev folders)
    $candidateFiles = @()
    foreach ($sDir in $contentScanDirs) {
        if (-not (Test-Path $sDir)) { continue }
        $allFiles = @(Get-ChildItem $sDir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $contentExts -contains $_.Extension.ToLower() -and $_.Length -lt $maxFileSizeBytes -and $_.Length -gt 0 })
        foreach ($file in $allFiles) {
            $excluded = $false
            $fp = $file.FullName
            foreach ($excl in $contentExcludePaths) {
                if ($fp -like "*$excl*") { $excluded = $true; break }
            }
            if (-not $excluded) { $candidateFiles += $file }
        }
    }

    Write-PlanLine "Scanning $($candidateFiles.Count) document files (max 8 MB each, game/dev folders excluded)..." "INFO"

    $contentResults = [ordered]@{}   # category -> list of file matches
    $scanned = 0

    foreach ($f in $candidateFiles) {
        $text = Get-FileText $f
        if (-not $text -or $text.Length -lt 20) { continue }
        $textLower = $text.ToLower()
        $scanned++

        foreach ($catName in $contentCats.Keys) {
            $keywords = $contentCats[$catName]
            $hits = @()
            foreach ($kw in $keywords) {
                if ($textLower -match $kw) { $hits += $kw; break }
            }
            if ($hits.Count -gt 0) {
                if (-not $contentResults.Contains($catName)) { $contentResults[$catName] = @() }
                $contentResults[$catName] += @{ File=$f; Keyword=$hits[0] }
                break  # one category per file
            }
        }
    }

    Write-PlanLine "Scanned $scanned files with readable content." "INFO"
    Write-PlanLine "" "INFO"

    if ($contentResults.Count -eq 0) {
        Write-PlanLine "No personal document categories identified from content." "KEEP"
    } else {
        foreach ($catName in $contentResults.Keys) {
            $matches = $contentResults[$catName]
            $newest  = ($matches | Sort-Object { $_.File.LastWriteTime } -Descending | Select-Object -First 1).File.LastWriteTime
            Write-PlanLine "$catName - $($matches.Count) file(s)  [newest: $($newest.ToString('yyyy-MM-dd'))]" "ADD"
            $matches | Select-Object -First 4 | ForEach-Object {
                $loc = $_.File.DirectoryName -replace [regex]::Escape($userRoot), "~"
                Write-PlanLine "    $($_.File.Name)  [$loc]" "INFO"
            }
            if ($matches.Count -gt 4) { Write-PlanLine "    ... and $($matches.Count - 4) more" "INFO" }
        }

        $totalContentDocs = ($contentResults.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $catCount = $contentResults.Count
        Write-PlanLine "" "INFO"
        Write-PlanLine "$totalContentDocs document(s) classified across $catCount categories (by content)" "INFO"

        $personalCats = @("Identidad/DNI","Nominas/Laboral","Fiscal/AEAT","Bancario/IBAN","Seguros","Medico/Salud","Propiedad") |
            Where-Object { $contentResults.Contains($_) }
        if ($personalCats.Count -ge 2) {
            Register-Action "Documents" "MANUAL" "Organize $totalContentDocs personal document(s) into subfolders" `
                -Detail "Content scan found: $($personalCats -join ', '). Create category subfolders in Documents and move files from Desktop/Downloads."
        }
    }

    # --- Organization suggestion based on Desktop state ---
    $desktopFiles = @(Get-ChildItem "$env:USERPROFILE\Desktop" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ne ".lnk" })
    if ($desktopFiles.Count -gt 5) {
        Register-Action "Documents" "MANUAL" "Organize Desktop ($($desktopFiles.Count) loose files)" `
            -Detail "Move documents/images/archives to their proper folders. Desktop should contain shortcuts only."
    }
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
#  MODULE: NETWORK
# ============================================================
function Collect-NetworkActions {
    Show-Section "NETWORK"

    # Active adapters
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
    Write-PlanLine "Active network adapters: $($adapters.Count)" "INFO"
    foreach ($a in $adapters) {
        $config = Get-NetIPConfiguration -InterfaceIndex $a.InterfaceIndex -ErrorAction SilentlyContinue
        $ip     = ($config.IPv4Address    | Select-Object -First 1).IPAddress
        $gw     = ($config.IPv4DefaultGateway | Select-Object -First 1).NextHop
        $dns    = (($config.DNSServer | Where-Object { $_.AddressFamily -eq 2 } |
                    Select-Object -First 2 | ForEach-Object { $_.ServerAddresses }) -join ", ")
        Write-PlanLine "  $($a.Name)  [$($a.InterfaceDescription)]" "INFO"
        if ($ip)  { Write-PlanLine "    IP: $ip   GW: $gw" "INFO" }
        if ($dns) { Write-PlanLine "    DNS: $dns" "INFO" }
    }

    # Connectivity — ping public DNS servers
    $targets = @(
        @{ Host = "8.8.8.8";  Label = "Google DNS"     }
        @{ Host = "1.1.1.1";  Label = "Cloudflare DNS" }
        @{ Host = "9.9.9.9";  Label = "Quad9 DNS"      }
    )
    $anyDown = $false
    foreach ($t in $targets) {
        try {
            $ping   = [System.Net.NetworkInformation.Ping]::new()
            $result = $ping.Send($t.Host, 2000)
            if ($result.Status -eq "Success") {
                $ms = $result.RoundtripTime
                if ($ms -gt 100) {
                    Write-PlanLine "$($t.Label) ($($t.Host)): ${ms} ms  HIGH LATENCY" "WARN"
                } else {
                    Write-PlanLine "$($t.Label) ($($t.Host)): ${ms} ms  OK" "KEEP"
                }
            } else {
                Write-PlanLine "$($t.Label) ($($t.Host)): unreachable" "WARN"
                $anyDown = $true
            }
        } catch {
            Write-PlanLine "$($t.Label) ($($t.Host)): ping failed" "WARN"
            $anyDown = $true
        }
    }
    if ($anyDown) {
        Register-Action "Network" "MANUAL" "Internet connectivity issue detected" `
            -Detail "One or more DNS servers unreachable - check network configuration"
    }
}

# ============================================================
#  MODULE: TEMPERATURE
# ============================================================
function Collect-TemperatureActions {
    Show-Section "TEMPERATURE"

    # CPU thermal zones via ACPI (no third-party tools needed)
    try {
        $zones = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
        if ($zones.Count -gt 0) {
            $i = 0
            foreach ($z in $zones) {
                $i++
                $celsius = [math]::Round($z.CurrentTemperature / 10.0 - 273.15, 1)
                $label   = if ($zones.Count -eq 1) { "CPU" } else { "Thermal Zone $i" }
                if ($celsius -gt 90) {
                    Write-PlanLine "$label : ${celsius} C  CRITICAL" "WARN"
                    Register-Action "Temperature" "MANUAL" "$label temperature critical (${celsius} C)" `
                        -Detail "Check CPU cooler seating, thermal paste, and case airflow"
                } elseif ($celsius -gt 75) {
                    Write-PlanLine "$label : ${celsius} C  HIGH" "WARN"
                    Register-Action "Temperature" "MANUAL" "$label temperature high (${celsius} C)" `
                        -Detail "Monitor under load - consider reseating cooler or improving airflow"
                } else {
                    Write-PlanLine "$label : ${celsius} C  OK" "KEEP"
                }
            }
        } else {
            Write-PlanLine "No ACPI thermal zones found on this system" "INFO"
        }
    } catch {
        Write-PlanLine "Could not read CPU temperature (ACPI access failed - run as Administrator)" "WARN"
    }

    # GPU — CIM does not expose AMD/NVIDIA GPU temps without LibreHardwareMonitor
    $lhmPath = "$env:ProgramFiles\LibreHardwareMonitor\LibreHardwareMonitor.exe"
    if (Test-Path $lhmPath) {
        Write-PlanLine "GPU temperature: LibreHardwareMonitor detected but CIM bridge not queried in this version" "INFO"
    } else {
        Write-PlanLine "GPU temperature: requires LibreHardwareMonitor (not found)" "INFO"
        Write-PlanLine "  Get it at: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor" "INFO"
    }
}

# ============================================================
#  MODULE: TOP PROCESSES
# ============================================================
function Collect-ProcessActions {
    Show-Section "TOP PROCESSES"

    $allProcs = @(Get-Process -ErrorAction SilentlyContinue)

    # Top 5 by CPU time
    $byCpu = @($allProcs | Where-Object { $_.CPU -ne $null } |
               Sort-Object CPU -Descending | Select-Object -First 5)
    Write-PlanLine "Top 5 by CPU time:" "INFO"
    foreach ($p in $byCpu) {
        $cpu = [math]::Round($p.CPU, 1)
        $mem = Format-Bytes $p.WorkingSet64
        Write-PlanLine ("  {0,-28} CPU: {1,8}s   RAM: {2}" -f $p.ProcessName, $cpu, $mem) "INFO"
    }

    Write-PlanLine "" "INFO"

    # Top 5 by RAM
    $byRam = @($allProcs | Sort-Object WorkingSet64 -Descending | Select-Object -First 5)
    Write-PlanLine "Top 5 by RAM:" "INFO"
    foreach ($p in $byRam) {
        $mem = Format-Bytes $p.WorkingSet64
        $cpu = [math]::Round($p.CPU, 1)
        Write-PlanLine ("  {0,-28} RAM: {1,8}   CPU: {2}s" -f $p.ProcessName, $mem, $cpu) "INFO"
    }

    # Warn on processes consuming > 2 GB RAM
    $heavy = @($allProcs | Where-Object { $_.WorkingSet64 -gt 2GB })
    if ($heavy.Count -gt 0) {
        Write-PlanLine "" "INFO"
        foreach ($p in $heavy) {
            $mem = Format-Bytes $p.WorkingSet64
            Write-PlanLine "  HIGH MEMORY: $($p.ProcessName) using $mem" "WARN"
            Register-Action "Processes" "MANUAL" "High-memory process: $($p.ProcessName) ($mem)" `
                -Detail "Verify this is expected; restart the app if it looks like a memory leak"
        }
    }
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
# Module registry — ordered list used for collection and interactive menu
$AllModules = [ordered]@{
    "Security"    = { Collect-SecurityActions    }
    "Cleanup"     = { Collect-CleanupActions     }
    "Startup"     = { Collect-StartupActions     }
    "FileAnalysis"= { Collect-FileAnalysisActions}
    "Disk"        = { Collect-DiskActions        }
    "Documents"   = { Collect-DocumentsActions   }
    "Drivers"     = { Collect-DriversActions     }
    "Backup"      = { Collect-BackupActions      }
    "Network"     = { Collect-NetworkActions     }
    "Temperature" = { Collect-TemperatureActions }
    "Processes"   = { Collect-ProcessActions     }
}
$selectedModules = [string[]]$AllModules.Keys

$modeColor = if ($Mode -eq "Plan") { "Cyan" } else { "Green" }
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  PC MAINTENANCE v3.0  --  $($Mode.ToUpper()) MODE" -ForegroundColor $modeColor
Write-Host "  $(Get-Date)  |  $env:COMPUTERNAME  |  $env:USERNAME" -ForegroundColor DarkGray
Write-Host ("=" * 70) -ForegroundColor DarkCyan

# Interactive module selector
if ($Interactive) {
    Write-Host ""
    Write-Host "  SELECT MODULES TO RUN" -ForegroundColor Cyan
    Write-Host "  Enter numbers separated by commas, or press Enter to run all" -ForegroundColor DarkGray
    Write-Host ""
    $idx = 0
    foreach ($modName in $AllModules.Keys) {
        $idx++
        Write-Host ("  [{0,2}] {1}" -f $idx, $modName) -ForegroundColor White
    }
    Write-Host ""
    $userChoice = Read-Host "  Modules"
    if ($userChoice.Trim() -ne "") {
        $moduleKeys = @($AllModules.Keys)
        $parsed = $userChoice -split ',' |
                  ForEach-Object { $_.Trim() } |
                  Where-Object   { $_ -match '^\d+$' } |
                  ForEach-Object { [int]$_ - 1 } |
                  Where-Object   { $_ -ge 0 -and $_ -lt $moduleKeys.Count }
        $selectedModules = @($parsed | ForEach-Object { $moduleKeys[$_] })
    }
    Write-Host ""
    Write-Host "  Running: $($selectedModules -join ', ')" -ForegroundColor DarkGray
}

if ($Mode -eq "Plan" -and -not $Interactive) {
    Write-Host ""
    Write-Host "  Analyzing system... (no changes will be made in Plan mode)" -ForegroundColor DarkGray
}

# --- Collect all planned actions ---
foreach ($modName in $selectedModules) {
    & $AllModules[$modName]
}

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
