# ================================================================
# Verify-Deployment.ps1
# Purpose  : Verifies all Azure Automation resources deployed
#            correctly after Bicep deployment
# Called by: Pipeline Verify stage via AzureCLI@2 task
# ================================================================

$ErrorActionPreference = "Stop"

# ── Config ────────────────────────────────────────────────────
if ($env:RESOURCE_GROUP)          { $resourceGroup         = $env:RESOURCE_GROUP }
else                              { $resourceGroup         = "rg-secrets-cleanup-dev" }

if ($env:AUTOMATION_ACCOUNT_NAME) { $automationAccountName = $env:AUTOMATION_ACCOUNT_NAME }
else                              { $automationAccountName = "scleanup-automation-dev" }

if ($env:RUNBOOK_NAME)            { $runbookName           = $env:RUNBOOK_NAME }
else                              { $runbookName           = "SecretCleanupRunbook" }

if ($env:SCHEDULE_NAME)           { $scheduleName          = $env:SCHEDULE_NAME }
else                              { $scheduleName          = "WeeklySecretCleanup" }

$allPassed   = $true
$principalId = $null

Write-Host "========================================="
Write-Host "  Verifying Deployment"
Write-Host "  Resource Group     : $resourceGroup"
Write-Host "  Automation Account : $automationAccountName"
Write-Host "========================================="
Write-Host ""

# ── Check 1: Resource Group ───────────────────────────────────
Write-Host "Check 1: Resource Group..."
$rgState = az group show `
    --name  $resourceGroup `
    --query "properties.provisioningState" `
    -o tsv 2>$null

if ($rgState -eq "Succeeded") {
    Write-Host "  [PASS] Resource group exists: $resourceGroup" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Resource group not found: $resourceGroup" -ForegroundColor Red
    $allPassed = $false
}

# ── Check 2: Automation Account ───────────────────────────────
Write-Host ""
Write-Host "Check 2: Automation Account..."
$aaState = az automation account show `
    --name             $automationAccountName `
    --resource-group   $resourceGroup `
    --query            "state" `
    --only-show-errors `
    -o tsv

if ($aaState -eq "Ok") {
    Write-Host "  [PASS] Automation Account ready: $automationAccountName" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Automation Account not ready. State: $aaState" -ForegroundColor Red
    $allPassed = $false
}

# ── Check 3: Managed Identity ─────────────────────────────────
Write-Host ""
Write-Host "Check 3: Managed Identity..."
$principalId = az automation account show `
    --name             $automationAccountName `
    --resource-group   $resourceGroup `
    --query            "identity.principalId" `
    --only-show-errors `
    -o tsv

if ($principalId) {
    Write-Host "  [PASS] Managed Identity assigned" -ForegroundColor Green
    Write-Host "  Principal ID : $principalId"
} else {
    Write-Host "  [FAIL] Managed Identity not found" -ForegroundColor Red
    $allPassed = $false
}

# ── Check 4: Runbook ──────────────────────────────────────────
Write-Host ""
Write-Host "Check 4: Runbook..."
$runbookState = az automation runbook show `
    --automation-account-name $automationAccountName `
    --resource-group          $resourceGroup `
    --name                    $runbookName `
    --query                   "state" `
    --only-show-errors `
    -o tsv

if ($runbookState -eq "Published") {
    Write-Host "  [PASS] Runbook published: $runbookName" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Runbook not published. State: $runbookState" -ForegroundColor Red
    $allPassed = $false
}

# ── Check 5: Schedule ─────────────────────────────────────────
Write-Host ""
Write-Host "Check 5: Schedule..."
$scheduleEnabled = az automation schedule show `
    --automation-account-name $automationAccountName `
    --resource-group          $resourceGroup `
    --name                    $scheduleName `
    --query                   "isEnabled" `
    --only-show-errors `
    -o tsv

if ($scheduleEnabled -eq "true") {
    Write-Host "  [PASS] Schedule active: $scheduleName" -ForegroundColor Green

    $nextRun = az automation schedule show `
        --automation-account-name $automationAccountName `
        --resource-group          $resourceGroup `
        --name                    $scheduleName `
        --query                   "nextRun" `
        --only-show-errors `
        -o tsv

    Write-Host "  Next Run : $nextRun"
} else {
    Write-Host "  [FAIL] Schedule not active. State: $scheduleEnabled" -ForegroundColor Red
    $allPassed = $false
}

# ── Check 6: Job Schedule Link ────────────────────────────────
Write-Host ""
Write-Host "Check 6: Schedule linked to Runbook..."
$subId       = az account show --query id -o tsv
$existingUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccountName/jobSchedules?api-version=2023-11-01"
$existingRaw = az rest --method GET --url $existingUrl -o json | ConvertFrom-Json
$existing    = @($existingRaw.value | Where-Object { $_.properties.schedule.name -eq $scheduleName })

if ($existing.Count -gt 0) {
    Write-Host "  [PASS] Schedule linked to runbook" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Schedule not linked to runbook" -ForegroundColor Red
    $allPassed = $false
}

# ── Check 7: Graph Modules ────────────────────────────────────
Write-Host ""
Write-Host "Check 7: Graph Modules..."

$requiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Applications"
)

foreach ($moduleName in $requiredModules) {
    $moduleUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccountName/modules/$moduleName`?api-version=2023-11-01"

    # Temporarily suspend Stop preference so NotFound doesnt break script
    $previousPreference    = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"

    $moduleRaw = az rest --method GET --url $moduleUrl -o json 2>&1
    $exitCode  = $LASTEXITCODE

    $ErrorActionPreference = $previousPreference

    if ($exitCode -eq 0) {
        $moduleState = ($moduleRaw | ConvertFrom-Json).properties.provisioningState
        if ($moduleState -eq "Succeeded") {
            Write-Host "  [YES] Installed     : $moduleName" -ForegroundColor Green
        } else {
            Write-Host "  [NO]  Not ready     : $moduleName (State: $moduleState)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [NO]  Not installed : $moduleName" -ForegroundColor Yellow
    }
}

# ── Summary ───────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================="
Write-Host "VERIFICATION SUMMARY"
Write-Host "========================================="

if ($allPassed) {
    Write-Host "All checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "-----------------------------------------"
    Write-Host "MANUAL STEP REQUIRED"
    Write-Host "-----------------------------------------"
    Write-Host "Grant Graph API permissions:"
    Write-Host ""
    Write-Host "  .\setup\grant-graph-permissions.ps1 ``"
    Write-Host "      -ManagedIdentityClientId '$principalId'"
    Write-Host "-----------------------------------------"
} else {
    Write-Host "One or more checks FAILED." -ForegroundColor Red
    Write-Host "Review errors above and re-run pipeline."
    exit 1
}

Write-Host "========================================="