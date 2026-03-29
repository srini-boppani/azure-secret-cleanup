# ================================================================
# install-dependencies.ps1
# Purpose  : Installs and verifies all required PowerShell modules
# Run      : Once on any new agent machine before running pipeline
# ================================================================

$ErrorActionPreference = "Stop"

# ── Standard modules ──────────────────────────────────────────
$modules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Applications"
)

Write-Host "Checking and installing required PowerShell modules..."
Write-Host ""

foreach ($module in $modules) {
    $installed = Get-InstalledModule -Name $module -ErrorAction SilentlyContinue
    if ($installed) {
        Write-Host "  Already installed : $module (v$($installed.Version))" -ForegroundColor Green
    } else {
        $available = Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue
        if ($available) {
            Write-Host "  Found (non-gallery): $module (v$($available[0].Version))" -ForegroundColor Yellow
        } else {
            Write-Host "  Not found. Installing $module from PSGallery..."
            try {
                Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
                Write-Host "  Installed : $module" -ForegroundColor Green
            } catch {
                Write-Error "  Failed to install $module : $($_.Exception.Message)"
                exit 1
            }
        }
    }
    try {
        Import-Module -Name $module -ErrorAction Stop
        Write-Host "  Load test passed  : $module" -ForegroundColor Green
    } catch {
        Write-Error "  Load test FAILED for $module : $($_.Exception.Message)"
        exit 1
    }
    Write-Host ""
}

# ── Pester v5 — must be explicitly installed ──────────────────
# Windows PowerShell 5.1 ships with Pester v4 built-in
# New-PesterConfiguration requires Pester v5+
# We force install v5 from gallery regardless of what is already present

Write-Host "Checking Pester version..."

$pesterInstalled = Get-InstalledModule -Name Pester -ErrorAction SilentlyContinue

if ($pesterInstalled -and $pesterInstalled.Version -ge "5.0.0") {
    Write-Host "  Pester v5 already installed (v$($pesterInstalled.Version))" -ForegroundColor Green
} else {
    Write-Host "  Installing Pester v5 from PSGallery (overriding built-in v4)..."
    Install-Module -Name Pester -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -Repository PSGallery
    Write-Host "  Pester v5 installed." -ForegroundColor Green
}

# Force load the gallery version not the built-in v4
$pesterPath = (Get-InstalledModule -Name Pester).InstalledLocation
Import-Module (Join-Path $pesterPath "Pester.psd1") -Force

$loadedVersion = (Get-Module Pester).Version
Write-Host "  Pester loaded     : v$loadedVersion" -ForegroundColor Green

if ($loadedVersion -lt "5.0.0") {
    Write-Error "Pester v5+ required but v$loadedVersion was loaded. Check module install."
    exit 1
}

Write-Host ""
Write-Host "All dependencies installed and verified." -ForegroundColor Cyan