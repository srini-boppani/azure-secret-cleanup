# ================================================================
# grant-graph-permissions.ps1
# Purpose  : One-time setup - grants Application.ReadWrite.All
#            to the Managed Identity service principal
# Usage    : .\grant-graph-permissions.ps1 -ManagedIdentityClientId "<id>"
#            or set $env:MANAGED_IDENTITY_CLIENT_ID before running
# Run as   : Global Administrator
# ================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityClientId = $env:MANAGED_IDENTITY_CLIENT_ID
)

if (-not $ManagedIdentityClientId) {
    Write-Error "Provide -ManagedIdentityClientId parameter or set MANAGED_IDENTITY_CLIENT_ID env variable."
    exit 1
}

$ErrorActionPreference = "Stop"

# Ensure required modules are present
foreach ($module in @("Microsoft.Graph.Authentication", "Microsoft.Graph.Applications")) {
    if (-not (Get-InstalledModule -Name $module -ErrorAction SilentlyContinue)) {
        if (-not (Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Host "Installing $module..."
            Install-Module $module -Scope CurrentUser -Force -AllowClobber
        }
    }
    Import-Module $module -ErrorAction Stop
}

Write-Host "Connecting to Microsoft Graph (admin login required)..."
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All","Application.Read.All" -NoWelcome

Write-Host "Connected as: $((Get-MgContext).Account)"
Write-Host ""

Write-Host "Looking up Managed Identity: $ManagedIdentityClientId"
$miSp = Get-MgServicePrincipal -Filter "appId eq '$ManagedIdentityClientId'"

if (-not $miSp) {
    Write-Error "Managed Identity not found. Verify Client ID: $ManagedIdentityClientId"
    exit 1
}

Write-Host "Found : $($miSp.DisplayName)"
Write-Host "  Object ID : $($miSp.Id)"
Write-Host ""

$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$roleId  = ($graphSp.AppRoles | Where-Object { $_.Value -eq "Application.ReadWrite.All" }).Id

$existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSp.Id |
            Where-Object { $_.AppRoleId -eq $roleId }

if ($existing) {
    Write-Host "Permission already assigned. No action needed." -ForegroundColor Green
    Disconnect-MgGraph | Out-Null
    exit 0
}

Write-Host "Assigning Application.ReadWrite.All..."
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSp.Id -BodyParameter @{
    PrincipalId = $miSp.Id
    ResourceId  = $graphSp.Id
    AppRoleId   = $roleId
} | Out-Null

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Permission granted successfully!" -ForegroundColor Green
Write-Host "  Identity   : $($miSp.DisplayName)"
Write-Host "  Permission : Application.ReadWrite.All"
Write-Host "=========================================" -ForegroundColor Cyan

Disconnect-MgGraph | Out-Null
