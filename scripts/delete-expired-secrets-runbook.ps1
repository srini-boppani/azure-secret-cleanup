# ================================================================
# delete-expired-secrets-runbook.ps1
# Purpose  : Runs inside Azure Automation Account
#            Scans all Azure AD App Registrations and removes
#            expired client secrets
# Auth     : System Assigned Managed Identity
#            No Azure CLI needed - Connect-MgGraph -Identity
# Note     : This is different from delete-expired-secrets.ps1
#            which runs via ADO pipeline on local machine
# ================================================================

$ErrorActionPreference = "Stop"

# ── Connect to Graph via Managed Identity ─────────────────────
# No client ID needed for System Assigned Managed Identity
# Azure Automation provides identity automatically
Write-Output "Connecting to Microsoft Graph via Managed Identity..."

try {
    Connect-MgGraph -Identity -NoWelcome
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    throw
}

$context = Get-MgContext
Write-Output "Connected successfully."
Write-Output "  Auth Type  : $($context.AuthType)"
Write-Output "  Client ID  : $($context.ClientId)"
Write-Output ""

# ── Scan for expired secrets ───────────────────────────────────
$currentDate = [datetime]::UtcNow

Write-Output "========================================="
Write-Output "  Azure AD Secret Cleanup - Runbook"
Write-Output "  Date : $($currentDate.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
Write-Output "========================================="
Write-Output ""

Write-Output "Fetching App Registrations..."
$apps = Get-MgApplication -All -Property Id,DisplayName,PasswordCredentials
Write-Output "Total apps found: $($apps.Count)"
Write-Output ""

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

Write-Output "Expired secrets found : $($toDelete.Count)"
Write-Output ""

if ($toDelete.Count -eq 0) {
    Write-Output "No expired secrets found. Tenant is clean."
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 0
}

# ── Remove expired secrets ────────────────────────────────────
$succeeded  = [System.Collections.Generic.List[PSCustomObject]]::new()
$failed     = [System.Collections.Generic.List[PSCustomObject]]::new()
$maxRetries = 3

Write-Output "-----------------------------------------"
Write-Output "REMOVING EXPIRED SECRETS"
Write-Output "-----------------------------------------"

foreach ($item in $toDelete) {
    $attempt = 0
    $done    = $false

    Write-Output ""
    Write-Output "Processing : $($item.AppName)"
    Write-Output "  KeyId    : $($item.KeyId)"
    Write-Output "  Expired  : $($item.Expiry) ($($item.Days) days overdue)"

    while (-not $done -and $attempt -lt $maxRetries) {
        $attempt++
        try {
            Remove-MgApplicationPassword `
                -ApplicationId $item.AppId `
                -KeyId         $item.KeyId `
                -ErrorAction   Stop
            Write-Output "  [REMOVED] Successfully deleted."
            $succeeded.Add($item)
            $done = $true
        } catch {
            $errMsg = $_.Exception.Message
            Write-Output "  Attempt $attempt failed: $errMsg"
            if ($attempt -lt $maxRetries) {
                $wait = $attempt * 5
                Write-Output "  Retrying in $wait seconds..."
                Start-Sleep -Seconds $wait
            } else {
                Write-Output "  [FAILED] Giving up after $maxRetries attempts."
                $failed.Add([PSCustomObject]@{
                    AppName = $item.AppName
                    KeyId   = $item.KeyId
                    Error   = $errMsg
                })
            }
        }
    }
}

# ── Disconnect ────────────────────────────────────────────────
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

# ── Summary ───────────────────────────────────────────────────
Write-Output ""
Write-Output "========================================="
Write-Output "SUMMARY"
Write-Output "========================================="
Write-Output "Apps Scanned  : $($apps.Count)"
Write-Output "Expired Found : $($toDelete.Count)"
Write-Output "Removed       : $($succeeded.Count)"
Write-Output "Failed        : $($failed.Count)"
Write-Output "========================================="

if ($failed.Count -gt 0) {
    Write-Output ""
    Write-Output "Failed removals:"
    $failed | ForEach-Object {
        Write-Output "  App   : $($_.AppName)"
        Write-Output "  KeyId : $($_.KeyId)"
        Write-Output "  Error : $($_.Error)"
        Write-Output ""
    }
    # Exit with error so Azure Automation marks job as Failed
    throw "Secret cleanup completed with $($failed.Count) failure(s)."
}

Write-Output "All expired secrets removed successfully."