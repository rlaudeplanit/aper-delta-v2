###################################################
# frontdoor.ps1 - Legacy Wrapper -> launch.ps1
###################################################
$TargetScript = Join-Path $PSScriptRoot "launch.ps1"
if (Test-Path $TargetScript) {
    & $TargetScript @args
} else {
    Write-Host "ERROR: launch.ps1 not found in $PSScriptRoot" -ForegroundColor Red
}
