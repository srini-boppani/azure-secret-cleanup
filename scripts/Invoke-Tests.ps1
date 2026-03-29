# ================================================================
# Invoke-Tests.ps1
# Purpose  : Runs Pester unit tests and outputs results
# Requires : Pester v5+
# ================================================================

param(
    [string]$TestsPath   = "tests/unit/",
    [string]$ResultsPath = "test-results.xml"
)

$pesterModule = Get-InstalledModule -Name Pester -ErrorAction SilentlyContinue

if (-not $pesterModule) {
    Write-Error "Pester is not installed. Run setup/install-dependencies.ps1 first."
    exit 1
}

if ($pesterModule.Version -lt "5.0.0") {
    Write-Error "Pester v5+ required. Found v$($pesterModule.Version)."
    exit 1
}

$pesterPath = $pesterModule.InstalledLocation
Import-Module (Join-Path $pesterPath "Pester.psd1") -Force

Write-Host "Pester version : $((Get-Module Pester).Version)"
Write-Host "Running tests from: $TestsPath"
Write-Host ""

$config                       = New-PesterConfiguration
$config.Run.Path              = $TestsPath
$config.Output.Verbosity      = "Detailed"
$config.TestResult.Enabled    = $true
$config.TestResult.OutputPath = $ResultsPath

$config.Run.PassThru = $true
$results = Invoke-Pester -Configuration $config

Write-Host ""
Write-Host "===== TEST RESULTS ====="
Write-Host "Passed  : $($results.PassedCount)"
Write-Host "Failed  : $($results.FailedCount)"
Write-Host "Skipped : $($results.SkippedCount)"
Write-Host "========================"

if ($results.FailedCount -gt 0) {
    Write-Error "$($results.FailedCount) test(s) failed."
    exit 1
}

Write-Host "All tests passed." -ForegroundColor Green