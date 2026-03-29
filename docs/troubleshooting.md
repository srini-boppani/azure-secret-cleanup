# Troubleshooting Guide

## Table of Contents
1. [Pipeline Issues](#pipeline)
2. [Deployment Issues](#deployment)
3. [Runbook Issues](#runbook)
4. [Authentication Issues](#auth)
5. [Agent Issues](#agent)
6. [Module Issues](#modules)
7. [Diagnostic Commands](#diagnostics)

---

## 1. Pipeline Issues <a name="pipeline"></a>

---

### Tests failing in Validate stage

**Symptom:**
```
[-] Filters out expired credential from list correctly
Expected 1, but got $null
```

**Cause:**
PowerShell 5.1 returns a single object instead of array
when Where-Object finds one result. `.Count` returns null.

**Fix:**
Wrap Where-Object results in `@()`:
```powershell
$remaining = @($creds | Where-Object { $_.keyId -notin $expiredIds })
```

---

### Pester not found or wrong version

**Symptom:**
```
New-PesterConfiguration : The term is not recognized
```

**Cause:**
Windows PowerShell 5.1 ships with built-in Pester v4.
`New-PesterConfiguration` requires Pester v5.

**Fix:**
```powershell
# Force install Pester v5 from gallery
Install-Module Pester -Force -AllowClobber -SkipPublisherCheck -Scope CurrentUser

# Verify version
(Get-InstalledModule Pester).Version
```

---

### YAML targetType error

**Symptom:**
```
Invalid target type 'scriptPath'. Value must be 'filepath' or 'inline'
```

**Cause:**
PowerShell@2 task uses `targetType: filePath` and `filePath:`
not `scriptPath`.

**Fix:**
```yaml
- task: PowerShell@2
  inputs:
    targetType: filePath        # not scriptPath
    filePath: 'scripts/...'    # not scriptPath:
```

Note: AzureCLI@2 uses different keys:
```yaml
- task: AzureCLI@2
  inputs:
    scriptLocation: scriptPath  # correct for AzureCLI@2
    scriptPath: 'scripts/...'   # correct for AzureCLI@2
```

---

### No parallelism available

**Symptom:**
```
No hosted parallelism has been purchased or granted
```

**Cause:**
Microsoft-hosted agents require a parallelism grant for
new free accounts.

**Fix:**
Use self-hosted agent instead:
```yaml
pool:
  name: Srini_Machine    # your self-hosted pool name
```

Or request free parallelism:
```
https://aka.ms/azpipelines-parallelism-request
```

---

## 2. Deployment Issues <a name="deployment"></a>

---

### Automation Account already exists error

**Symptom:**
```
Only one account is allowed for your subscription per Region.
If Deleted recently, please restore the same account.
```

**Cause:**
Azure soft-deletes Automation Accounts. The deleted account
still counts against the one-per-region limit.

**Fix — Restore the account:**
```powershell
az rest --method POST `
    --url "https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.Automation/locations/eastus/deletedAutomationAccounts/<account-name>/recover?api-version=2024-10-23"
```

Then re-run the pipeline — Bicep Incremental mode will
update the restored account.

---

### Bicep deployment fails with BadRequest

**Symptom:**
```
ERROR: {"code":"BadRequest","message":"..."}
```

**Cause:**
Could be multiple issues — API version mismatch, invalid
parameter values, or resource constraint.

**Diagnose:**
```powershell
# Check last deployment operations
az deployment operation group list `
    --resource-group rg-secrets-cleanup-dev `
    --name main `
    --query "[?properties.provisioningState=='Failed']" `
    -o json
```

---

### scheduleStartTime error

**Symptom:**
```
The schedule start time must be in the future
```

**Cause:**
Bicep validator reads `scheduleStartTime` from bicepparam
file — the placeholder date is fine but the dynamic value
from `deploy.ps1` must be in the future.

**Fix:**
Ensure `deploy.ps1` Step 1 runs before Bicep deploy.
The script calculates next Sunday dynamically.

---

### Service connection has no subscription

**Symptom:**
Service connection dropdown shows no subscriptions.

**Cause:**
Azure DevOps account and Azure Portal account are different
Microsoft accounts.

**Fix:**
Sign into Azure DevOps with the same account that owns
the Azure subscription. Or add the ADO account as
Contributor on the subscription.

---

## 3. Runbook Issues <a name="runbook"></a>

---

### Runbook stuck at "Preparing modules for first use"

**Symptom:**
Job shows Output: "Connecting to Microsoft Graph..."
then stops with no further output for 10+ minutes.

**Cause:**
Microsoft.Graph modules are not installed in the
Automation Account.

**Fix:**
Re-run the pipeline — Step 6 installs modules automatically.
Or install manually:
1. Azure Portal → Automation Account → Modules
2. Add a module → Browse from gallery
3. Search: `Microsoft.Graph.Authentication`
4. Runtime: 5.1 → Import
5. Wait for Available status
6. Repeat for `Microsoft.Graph.Applications`

---

### Runbook shows 0 apps found

**Symptom:**
```
Total apps found: 0
```

**Cause:**
Graph permissions not granted to Managed Identity.
The API call succeeds but returns empty results without permission.

**Fix:**
```powershell
.\setup\grant-graph-permissions.ps1 `
    -ManagedIdentityClientId "<principal-id>"
```

Must be run as Global Administrator.

---

### Runbook fails with 403 Forbidden

**Symptom:**
```
Remove-MgApplicationPassword : Forbidden
StatusCode: 403
```

**Cause:**
`Application.ReadWrite.All` permission not granted or
not admin consented.

**Fix:**
Re-run `grant-graph-permissions.ps1` as Global Admin.
Then verify in Azure Portal:
Enterprise Applications → your Managed Identity →
Permissions → Admin consent granted.

---

### Runbook fails on Remove-MgApplicationPassword

**Symptom:**
```
[FAILED] App: MyApp | Error: Resource not found
```

**Cause:**
The app or secret was already deleted between the scan
and the removal attempt. Race condition on large tenants.

**Impact:**
Non-critical. The secret no longer exists so the cleanup
goal is achieved. The retry logic handles transient errors.

**Action:**
No action needed. Check `$failed.Count` in summary —
if count is low this is expected behavior.

---

## 4. Authentication Issues <a name="auth"></a>

---

### Managed Identity authentication failed (IMDS)

**Symptom:**
```
ManagedIdentityCredential authentication failed:
All Managed Identity sources are unavailable.
MSAL was not able to detect the Azure Instance Metadata Service
```

**Cause:**
`Connect-MgGraph -Identity` was called from a machine
(self-hosted agent or local machine) instead of from
inside Azure infrastructure.

The IMDS endpoint `169.254.169.254` is only available
inside Azure VMs, Azure Functions, Azure Automation etc.

**Fix:**
This script (`delete-expired-secrets-runbook.ps1`) must
only run inside Azure Automation — not via ADO pipeline
directly.

For ADO pipeline execution use:
`scripts/delete-expired-secrets.ps1` (uses az CLI token)

---

### Azure CLI token acquisition fails

**Symptom:**
```
Failed to get access token from Azure CLI.
Ensure AzureCLI@2 task ran before this script.
```

**Cause:**
The script `delete-expired-secrets.ps1` calls
`az account get-access-token` but Azure CLI is not
authenticated. The `AzureCLI@2` task must run first.

**Fix:**
Ensure the task in YAML uses `AzureCLI@2` not `PowerShell@2`:
```yaml
- task: AzureCLI@2    # correct - provides az login context
  inputs:
    azureSubscription: 'sc-secrets-cleanup-dev'
    scriptLocation: scriptPath
    scriptPath: 'scripts/delete-expired-secrets.ps1'
```

---

### Device login error

**Symptom:**
```
Device information is missing.
Status: Response_Status.Status_Unexpected
```

**Cause:**
Azure CLI session expired on local machine.

**Fix:**
```powershell
az logout
az login
az account set --subscription "<subscription-id>"
```

---

## 5. Agent Issues <a name="agent"></a>

---

### Agent offline

**Symptom:**
Pipeline queued but never starts. ADO shows agent as offline.

**Fix:**
Check agent service on your machine:
```powershell
# Check status
Get-Service -Name "vstsagent*" | Select-Object Name, Status

# Start if stopped
Get-Service -Name "vstsagent*" | Start-Service
```

Or restart via Services (services.msc) on your machine.

---

### Agent runs as wrong user

**Symptom:**
Modules installed for one user but agent runs as another.

**Fix:**
Install modules for all users or ensure agent service
runs as the same user that installed modules:
```powershell
Install-Module Microsoft.Graph.Authentication `
    -Scope AllUsers -Force -AllowClobber
```

---

### Join-Path with 3 arguments fails

**Symptom:**
```
A positional parameter cannot be found that accepts argument 'graph-auth.ps1'
```

**Cause:**
PowerShell 5.1 does not support 3-argument Join-Path.
This is a PS7+ feature.

**Fix:**
```powershell
# Wrong - PS7 only
$path = Join-Path $PSScriptRoot "helpers" "graph-auth.ps1"

# Correct - PS 5.1 compatible
$path = Join-Path (Join-Path $PSScriptRoot "helpers") "graph-auth.ps1"
```

---

## 6. Module Issues <a name="modules"></a>

---

### Module install times out in pipeline

**Symptom:**
```
Module install timed out after 600 seconds: Microsoft.Graph.Applications
```

**Cause:**
Module installation in Azure Automation can take longer
than expected depending on module size and Azure load.

**Fix:**
Increase timeout in `deploy.ps1` Step 6:
```powershell
$maxAttempts = 30    # increase from 20
```

Or install manually via Portal and re-run pipeline —
Step 6 skips already-installed modules.

---

### Module shows Failed state

**Symptom:**
Module in Automation Account shows state: Failed

**Cause:**
Usually a network issue during gallery download or
incompatible module version.

**Fix:**
1. Azure Portal → Automation Account → Modules
2. Delete the failed module
3. Re-run pipeline — Step 6 reinstalls

---

### az automation account module not recognized

**Symptom:**
```
'module' is misspelled or not recognized by the system
```

**Cause:**
The `az automation account module` subcommand does not
exist in the available preview extension version.

**Fix:**
Use REST API instead (already implemented in `deploy.ps1`):
```powershell
$url = "https://management.azure.com/subscriptions/$subId/..."
az rest --method PUT --url $url --body "@$tempFile"
```

---

## 7. Diagnostic Commands <a name="diagnostics"></a>

### Check all deployed resources
```powershell
az group show `
    --name rg-secrets-cleanup-dev `
    --query "properties.provisioningState" -o tsv

az automation account show `
    --name scleanup-automation-dev `
    --resource-group rg-secrets-cleanup-dev `
    --query "state" --only-show-errors -o tsv
```

### Check runbook state
```powershell
az automation runbook show `
    --automation-account-name scleanup-automation-dev `
    --resource-group rg-secrets-cleanup-dev `
    --name SecretCleanupRunbook `
    --query "state" --only-show-errors -o tsv
```

### Check schedule next run
```powershell
az automation schedule show `
    --automation-account-name scleanup-automation-dev `
    --resource-group rg-secrets-cleanup-dev `
    --name WeeklySecretCleanup `
    --query "nextRun" --only-show-errors -o tsv
```

### Check Graph permissions on Managed Identity
```powershell
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

Connect-MgGraph -Scopes "Application.Read.All" -NoWelcome

$principalId = "<managed-identity-principal-id>"

Get-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $principalId |
    Select-Object AppRoleId, PrincipalDisplayName, ResourceDisplayName
```

### Run verify script locally
```powershell
$env:PARAM_FILE = "iac/parameters/dev.bicepparam"
.\scripts\Verify-Deployment.ps1
```

### Check deleted Automation Accounts
```powershell
$subId = az account show --query id -o tsv
az rest --method GET `
    --url "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Automation/deletedAutomationAccounts?api-version=2023-11-01" `
    -o json
```

### Restore soft-deleted Automation Account
```powershell
$subId       = az account show --query id -o tsv
$accountName = "scleanup-automation-dev"
$location    = "eastus"

az rest --method POST `
    --url "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Automation/locations/$location/deletedAutomationAccounts/$accountName/recover?api-version=2024-10-23"
```

### View recent runbook job output
```powershell
$subId         = az account show --query id -o tsv
$resourceGroup = "rg-secrets-cleanup-dev"
$accountName   = "scleanup-automation-dev"

# Get latest job
$jobsUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$accountName/jobs?api-version=2023-11-01&`$top=1"
az rest --method GET --url $jobsUrl -o json
```