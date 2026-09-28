###################################################
# frontdoor.ps1 - The Interface (Stable Flow)
###################################################
$RScript = Join-Path $PSScriptRoot ".engine\worker.R"

# ── Dynamically find Rscript — picks the latest installed R version automatically ──
$RBase = "C:\Program Files\R"

if (Test-Path $RBase) {
  # Get all Rscript.exe paths, sort by version folder name descending, pick the latest
  $RScriptExePath = Get-ChildItem -Path $RBase -Recurse -Filter "Rscript.exe" |
    Where-Object { $_.FullName -like "*\x64\*" } |
    Sort-Object { $_.FullName } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
} else {
  # Fallback — try system PATH (works if R is already on PATH)
  $RCmd = Get-Command Rscript -ErrorAction SilentlyContinue
  if ($RCmd) {
    $RScriptExePath = $RCmd.Source
  } else {
    $RScriptExePath = $null
  }
}

if ([string]::IsNullOrWhiteSpace($RScriptExePath) -or !(Test-Path $RScriptExePath)) {
  Write-Host "ERROR: Rscript.exe not found. Please install R from https://cran.r-project.org/" -ForegroundColor Red
  Write-Host "Press any key to exit..."
  [void][System.Console]::ReadKey($true)
  exit 1
}

Write-Host "Using R: $RScriptExePath" -ForegroundColor DarkGray

Write-Host "--- Performance Data Engine ---" -ForegroundColor Cyan

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
$comp1       = "NONE"
$comp2       = "NONE"
$toolType    = "jmeter"
$labelFilter = "NONE"

###################################################
# REGISTER MODE
###################################################
if ($choice -eq "2") {
    $opMode = "register"

    # Tool type selection
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

    # Folder input — expects CSV files following the filename naming standard
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

    Write-Host "`nSelect Tool Type for Report:" -ForegroundColor Yellow
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

    # --- Display recent runs ---
    & $RScriptExePath --vanilla $RScript `
        "--opMode=menu" `
        "--active_tool=$toolType"

    # --- Collect up to 2 Run IDs or Sequence Numbers (Baseline + Current) ---
    $runIds = @()
    Write-Host "`nEnter up to 2 Run IDs or Sequence Numbers: Baseline first, then Current." -ForegroundColor Yellow
    Write-Host "Press ENTER on an empty line when done (at least 1 required)." -ForegroundColor DarkGray

    while ($runIds.Count -lt 2) {
        $currentCount = $runIds.Count + 1
        $label = if ($currentCount -eq 1) { "Baseline" } else { "Current" }
        $inputRun = (Read-Host "Enter $label Run ID or Sequence #$currentCount").Trim()

        if ([string]::IsNullOrWhiteSpace($inputRun)) {
            if ($runIds.Count -ge 1) { break }
            else { Write-Host "At least one Run ID is required to generate a report." -ForegroundColor Red }
        } else {
            $runIds += $inputRun
        }
    }

    $comp1 = if ($runIds.Count -ge 1) { $runIds[0] } else { "NONE" }
    $comp2 = if ($runIds.Count -ge 2) { $runIds[1] } else { "NONE" }

    Write-Host ""
    $inputFilter = (Read-Host "Enter transaction label filter pattern (e.g. TRX, TRN) or press Enter to include all").Trim()
    if (-not [string]::IsNullOrWhiteSpace($inputFilter)) {
        $labelFilter = $inputFilter
    }
}

###################################################
# EXECUTE WORKER
###################################################
Write-Output "`nLaunching Worker..."

if ($opMode -eq "register") {
    & $RScriptExePath --vanilla $RScript `
        "--opMode=$opMode" `
        "--rawResultsFolder=$rawResultsFolder" `
        "--active_tool=$toolType"
} else {
    & $RScriptExePath --vanilla $RScript `
        "--opMode=$opMode" `
        "--comp1=$comp1" `
        "--comp2=$comp2" `
        "--active_tool=$toolType" `
        "--labelFilterParam=$labelFilter"
}

Write-Output "`nProcess complete. Press any key to exit..."
[void][System.Console]::ReadKey($true)