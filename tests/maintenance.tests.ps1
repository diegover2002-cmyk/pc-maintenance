#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for maintenance.ps1

.DESCRIPTION
    Validates script syntax, function availability, and basic functionality
#>

Describe "Maintenance Script Validation" {
    BeforeAll {
        $ScriptPath = Join-Path $PSScriptRoot "..\scripts\maintenance.ps1"
        $SetupPath = Join-Path $PSScriptRoot "..\scripts\setup.ps1"
    }

    Context "Script Syntax Validation" {
        It "maintenance.ps1 has valid PowerShell syntax" {
            $Errors = @()
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $ScriptPath -Raw),
                [ref]$Errors
            )
            $Errors.Count | Should -Be 0
        }

        It "setup.ps1 has valid PowerShell syntax" {
            $Errors = @()
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $SetupPath -Raw),
                [Ref]$Errors
            )
            $Errors.Count | Should -Be 0
        }
    }

    Context "Script File Validation" {
        It "maintenance.ps1 exists" {
            Test-Path $ScriptPath | Should -Be $true
        }

        It "setup.ps1 exists" {
            Test-Path $SetupPath | Should -Be $true
        }

        It "maintenance.ps1 is readable" {
            { Get-Content $ScriptPath -ErrorAction Stop } | Should -Not -Throw
        }

        It "setup.ps1 is readable" {
            { Get-Content $SetupPath -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context "Directory Structure" {
        It "logs directory exists or can be created" {
            $LogDir = Join-Path $PSScriptRoot "..\logs"
            Test-Path $LogDir -PathType Container -ErrorAction SilentlyContinue | Should -Be $true
        }

        It "reports directory exists or can be created" {
            $ReportDir = Join-Path $PSScriptRoot "..\reports"
            Test-Path $ReportDir -PathType Container -ErrorAction SilentlyContinue | Should -Be $true
        }
    }

    Context "Script Parameters" {
        It "maintenance.ps1 accepts -Mode parameter" {
            $Params = Get-Content $ScriptPath -Raw | Select-String "param\(" -A 5
            $Params | Should -Match "Mode|Plan|Apply"
        }

        It "maintenance.ps1 has default mode set" {
            $Params = Get-Content $ScriptPath -Raw | Select-String "Mode.*="
            $Params | Should -Match "Plan"
        }
    }

    Context "Critical Functions Exist" {
        BeforeAll {
            $Content = Get-Content $ScriptPath -Raw
        }

        It "Register-Action function is defined" {
            $Content | Should -Match "function Register-Action"
        }

        It "Write-PlanLine function is defined" {
            $Content | Should -Match "function Write-PlanLine"
        }

        It "Format-Bytes function is defined" {
            $Content | Should -Match "function Format-Bytes"
        }

        It "Write-Log function is defined" {
            $Content | Should -Match "function Write-Log"
        }
    }

    Context "Module Functions Exist" {
        BeforeAll {
            $Content = Get-Content $ScriptPath -Raw
        }

        It "Collect-SecurityActions is defined" {
            $Content | Should -Match "function Collect-SecurityActions"
        }

        It "Collect-CleanupActions is defined" {
            $Content | Should -Match "function Collect-CleanupActions"
        }

        It "Collect-StartupActions is defined" {
            $Content | Should -Match "function Collect-StartupActions"
        }

        It "Collect-FileAnalysisActions is defined" {
            $Content | Should -Match "function Collect-FileAnalysisActions"
        }

        It "Collect-DiskActions is defined" {
            $Content | Should -Match "function Collect-DiskActions"
        }

        It "Collect-DocumentsActions is defined" {
            $Content | Should -Match "function Collect-DocumentsActions"
        }

        It "Collect-DriversActions is defined" {
            $Content | Should -Match "function Collect-DriversActions"
        }

        It "Collect-BackupActions is defined" {
            $Content | Should -Match "function Collect-BackupActions"
        }

        It "Collect-NetworkActions is defined" {
            $Content | Should -Match "function Collect-NetworkActions"
        }

        It "Collect-TemperatureActions is defined" {
            $Content | Should -Match "function Collect-TemperatureActions"
        }

        It "Collect-ProcessActions is defined" {
            $Content | Should -Match "function Collect-ProcessActions"
        }
    }

    Context "Configuration Validation" {
        BeforeAll {
            $Content = Get-Content $ScriptPath -Raw
        }

        It "Has LogRotateDays configuration" {
            $Content | Should -Match "LogRotateDays.*30"
        }

        It "Has MinFreeGB configuration" {
            $Content | Should -Match "MinFreeGB.*15"
        }

        It "Sets strict mode" {
            $Content | Should -Match "Set-StrictMode"
        }

        It "Sets error action preference" {
            $Content | Should -Match "ErrorActionPreference"
        }
    }

    Context "Log and Report Rotation" {
        BeforeAll {
            $Content = Get-Content $ScriptPath -Raw
        }

        It "Includes log rotation logic" {
            $Content | Should -Match "oldLogs.*LogRotateDays"
        }

        It "Includes report rotation logic" {
            $Content | Should -Match "oldReports.*LogRotateDays"
        }

        It "UTF-8 encoding is configured" {
            $Content | Should -Match "UTF8"
        }
    }
}

Describe "Setup Script Validation" {
    BeforeAll {
        $SetupPath = Join-Path $PSScriptRoot "..\scripts\setup.ps1"
    }

    Context "Task Scheduler Registration" {
        BeforeAll {
            $Content = Get-Content $SetupPath -Raw
        }

        It "References Register-ScheduledTask" {
            $Content | Should -Match "Register-ScheduledTask"
        }

        It "Sets execution policy" {
            $Content | Should -Match "ExecutionPolicy"
        }

        It "Runs maintenance.ps1 in Apply mode" {
            $Content | Should -Match "Apply"
        }
    }
}
