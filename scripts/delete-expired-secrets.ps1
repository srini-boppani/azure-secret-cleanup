# ================================================================
# delete-expired-secrets.ps1
# Purpose  : Scans all Azure AD App Registrations and removes
#            expired client secrets
# Auth     : Azure CLI token via AzureCLI@2 service connection
# Note     : No hardcoded values - no threshold logic
# ================================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Applications   -ErrorAction Stop

$helperPath = Join-Path (Join-Path $PSScriptRoot "helpers") "graph-auth.ps1"
. $helperPath

$currentDate = [datetime]::UtcNow

Write-Host "========================================="
Write-Host "  Azure AD Secret Cleanup"
Write-Host "  Date : $($currentDate.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
Write-Host "========================================="
Write-Host ""

Connect-ToMicrosoftGraph

Write-Host "Fetching App Registrations..."
$apps = Get-MgApplication -All -Property Id,DisplayName,PasswordCredentials
Write-Host "Total apps found: $($apps.Count)"
Write-Host ""

$toDelete = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($app in $apps) {
    if (-not $app.PasswordCredentials) { continue }
    foreach ($secret in $app.PasswordCredentials) {
        if ($null -eq $secret.EndDateTime) { continue }
        if ($secret.EndDateTime -lt $currentDate) {
            $toDelete.Add([PSCustomObject]@{
                AppId   = $app.Id
                AppName = $app.DisplayName
                KeyId   = $secret.KeyId
                Expiry  = $secret.EndDateTime.ToString("yyyy-MM-dd")
                Days    = [math]::Round(($currentDate - $secret.EndDateTime).TotalDays)
            })
        }
    }
}

Write-Host "Expired secrets found : $($toDelete.Count)"
Write-Host ""

if ($toDelete.Count -eq 0) {
    Write-Host "No expired secrets found. Tenant is clean."
    Disconnect-FromMicrosoftGraph
    exit 0
}

$succeeded  = [System.Collections.Generic.List[PSCustomObject]]::new()
$failed     = [System.Collections.Generic.List[PSCustomObject]]::new()
$maxRetries = 3

Write-Host "-----------------------------------------"
Write-Host "REMOVING EXPIRED SECRETS"
Write-Host "-----------------------------------------"

foreach ($item in $toDelete) {
    $attempt = 0
    $done    = $false
    Write-Host ""
    Write-Host "Processing : $($item.AppName)"
    Write-Host "  KeyId    : $($item.KeyId)"
    Write-Host "  Expired  : $($item.Expiry) ($($item.Days) days overdue)"

    while (-not $done -and $attempt -lt $maxRetries) {
        $attempt++
        try {
            Remove-MgApplicationPassword -ApplicationId $item.AppId -KeyId $item.KeyId -ErrorAction Stop
            Write-Host "  [REMOVED] Successfully deleted."
            $succeeded.Add($item)
            $done = $true
        } catch {
            $errMsg = $_.Exception.Message
            Write-Host "  Attempt $attempt failed: $errMsg"
            if ($attempt -lt $maxRetries) {
                $wait = $attempt * 5
                Write-Host "  Retrying in $wait seconds..."
                Start-Sleep -Seconds $wait
            } else {
                Write-Host "  [FAILED] Giving up after $maxRetries attempts."
                $failed.Add([PSCustomObject]@{
                    AppName = $item.AppName
                    KeyId   = $item.KeyId
                    Error   = $errMsg
                })
            }
        }
    }
}

Disconnect-FromMicrosoftGraph

Write-Host ""
Write-Host "========================================="
Write-Host "SUMMARY"
Write-Host "========================================="
Write-Host "Apps Scanned  : $($apps.Count)"
Write-Host "Expired Found : $($toDelete.Count)"
Write-Host "Removed       : $($succeeded.Count)"
Write-Host "Failed        : $($failed.Count)"
Write-Host "========================================="

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed removals:"
    $failed | ForEach-Object {
        Write-Host "  App   : $($_.AppName)"
        Write-Host "  KeyId : $($_.KeyId)"
        Write-Host "  Error : $($_.Error)"
        Write-Host ""
    }
    exit 1
}
