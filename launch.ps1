[CmdletBinding()]
param(
    [string]$opMode = "",
    [string]$current = "",
    [string]$base = "NONE",
    [string]$comp1 = "",
    [string]$comp2 = "",
    [string]$rawResultsFolder = "NONE",
    [string]$toolType = "jmeter",
    [string]$labelFilter = "NONE",
    [string]$outputFolder = "NONE",
    [switch]$ci,
    [switch]$failOnSla,
    [switch]$nonInteractive
)

###################################################
# launch.ps1 - APER Delta Interactive / CI Launcher (Windows)
###################################################
$RScript = Join-Path $PSScriptRoot ".engine\engine.R"

# Determine execution mode (interactive vs headless)
$isInteractive = ($PSBoundParameters.Count -eq 0 -and -not $nonInteractive)

# ── Dynamically find Rscript — picks the latest installed R version automatically ──
$RBase = "C:\Program Files\R"

if (Test-Path $RBase) {
  $RScriptExePath = Get-ChildItem -Path $RBase -Recurse -Filter "Rscript.exe" |
    Where-Object { $_.FullName -like "*\x64\*" } |
    Sort-Object { $_.FullName } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
} else {
  $RCmd = Get-Command Rscript -ErrorAction SilentlyContinue
  if ($RCmd) {
    $RScriptExePath = $RCmd.Source
  } else {
    $RScriptExePath = $null
  }
}

if ([string]::IsNullOrWhiteSpace($RScriptExePath) -or !(Test-Path $RScriptExePath)) {
  Write-Host "ERROR: Rscript.exe not found. Please install R from https://cran.r-project.org/" -ForegroundColor Red
  if ($isInteractive) {
    Write-Host "Press any key to exit..."
    [void][System.Console]::ReadKey($true)
  }
  exit 1
}

Write-Host "Using R: $RScriptExePath" -ForegroundColor DarkGray

if ($isInteractive) {
    Write-Host "--- APER Delta - Performance Data Engine ---" -ForegroundColor Cyan

    # 1. Select Operation
    Write-Host "Operations:" -ForegroundColor Yellow
    Write-Host "1. Generate Report (Math & HTML) [Default]"
    Write-Host "2. Register Data (Save to DuckDB Vault)"

    $choice = ""
    while ($true) {
        $inputChoice = (Read-Host "Select tool [1 or 2, or press Enter for default]").Trim()
        if ([string]::IsNullOrWhiteSpace($inputChoice)) {
            $choice = "1"
            break
        }
        if ($inputChoice -match "^[1-2]$") {
            $choice = $inputChoice
            break
        }
        Write-Host "Invalid choice! Please enter 1, 2, or just press Enter." -ForegroundColor Red
    }

    # 2. Collect info and initialize default variables cleanly
    $rawResultsFolder = "NONE"
    $currentRun       = "NONE"
    $baseRun          = "NONE"
    $toolType         = "jmeter"
    $labelFilter      = "NONE"

    ###################################################
    # REGISTER MODE
    ###################################################
    if ($choice -eq "2") {
        $opMode = "register"

        Write-Host "`nSelect Tool Type:" -ForegroundColor Yellow
        Write-Host "1. JMeter (Default)"
        Write-Host "2. NeoLoad"

        while ($true) {
            $toolChoice = (Read-Host "Enter choice (1 or 2, or press Enter for default)").Trim()
            if ([string]::IsNullOrWhiteSpace($toolChoice) -or $toolChoice -eq "1") {
                $toolType = "jmeter"
                break
            }
            if ($toolChoice -eq "2") {
                $toolType = "neoload"
                break
            }
            Write-Host "Invalid choice! Please enter 1, 2, or press Enter." -ForegroundColor Red
        }

        while ([string]::IsNullOrWhiteSpace($rawResultsFolder) -or $rawResultsFolder -eq "NONE") {
            Write-Host ""
            Write-Host "Required CSV Naming Convention in Target Folder:" -ForegroundColor Cyan
            Write-Host "<ProjectName>_<TestType>_<AppName>_<BuildId>_<Timestamp>.csv" -ForegroundColor DarkGray
            Write-Host "e.g., ProjectXYZ_Sanity_DemoApp_123456_20260809-1027.csv" -ForegroundColor DarkGray
            Write-Host ""
            $rawResultsFolder = Read-Host "Enter FULL folder path containing CSV results"
            if ([string]::IsNullOrWhiteSpace($rawResultsFolder)) { Write-Host "Full path is required!" -ForegroundColor Red }
        }

    ###################################################
    # REPORT MODE
    ###################################################
    } else {
        $opMode = "report"
        $toolType = "jmeter"

        & $RScriptExePath --vanilla $RScript "--opMode=menu"

        Write-Host "`nReport Run Selection (Current and Base):" -ForegroundColor Yellow

        $inputCurrent = ""
        while ([string]::IsNullOrWhiteSpace($inputCurrent)) {
            $inputCurrent = (Read-Host "1. Enter CURRENT Run ID or Sequence Number (Required)").Trim()
            if ([string]::IsNullOrWhiteSpace($inputCurrent)) {
                Write-Host "Current Run ID is required to generate a report." -ForegroundColor Red
            }
        }

        $inputBase = (Read-Host "2. Enter BASELINE Run ID or Sequence Number (Optional, press Enter for standalone)").Trim()

        $currentRun = $inputCurrent
        $baseRun    = if (-not [string]::IsNullOrWhiteSpace($inputBase)) { $inputBase } else { "NONE" }

        Write-Host ""
        $inputFilter = (Read-Host "Enter transaction label filter pattern (e.g. TRX, TRN) or press Enter to include all").Trim()
        if (-not [string]::IsNullOrWhiteSpace($inputFilter)) {
            $labelFilter = $inputFilter
        }
    }
} else {
    # Non-interactive / Headless / CI Mode
    if ([string]::IsNullOrWhiteSpace($opMode)) {
        if ($rawResultsFolder -ne "NONE") {
            $opMode = "register"
        } else {
            $opMode = "report"
        }
    }

    if ([string]::IsNullOrWhiteSpace($current)) {
        if (-not [string]::IsNullOrWhiteSpace($comp2)) {
            $currentRun = $comp2
            $baseRun    = if (-not [string]::IsNullOrWhiteSpace($comp1)) { $comp1 } else { "NONE" }
        } elseif (-not [string]::IsNullOrWhiteSpace($comp1)) {
            $currentRun = $comp1
            $baseRun    = "NONE"
        } else {
            $currentRun = "NONE"
        }
    } else {
        $currentRun = $current
        $baseRun    = $base
    }
}

###################################################
# EXECUTE ENGINE
###################################################
Write-Output "`nLaunching APER Delta Engine..."

$rArgs = @("--vanilla", $RScript, "--opMode=$opMode")

if ($opMode -eq "register") {
    $rArgs += "--rawResultsFolder=$rawResultsFolder"
    $rArgs += "--active_tool=$toolType"
} else {
    $rArgs += "--current=$currentRun"
    $rArgs += "--base=$baseRun"
    $rArgs += "--active_tool=$toolType"
    $rArgs += "--labelFilterParam=$labelFilter"
}

if ($outputFolder -ne "NONE") {
    $rArgs += "--outputFolder=$outputFolder"
}

if ($ci -or $failOnSla) {
    $rArgs += "--ci"
}

& $RScriptExePath $rArgs
$rExitCode = $LASTEXITCODE

if ($isInteractive) {
    Write-Output "`nProcess complete. Press any key to exit..."
    [void][System.Console]::ReadKey($true)
} else {
    exit $rExitCode
}
