# ================================================================
# deploy.ps1
# Purpose  : Deploys all IaC resources via Bicep
#            Called by Azure DevOps pipeline DeployInfra stage
# Does     : 0. Checks Azure CLI extensions
#            1. Calculates next Sunday as schedule start time
#            2. Creates resource group if not exists
#            3. Deploys Bicep template
#            4. Uploads and publishes runbook content
#            5. Links schedule to runbook
#            6. Prints outputs for manual permission assignment
# Does NOT : Grant Graph API permissions (done manually)
# ================================================================

$ErrorActionPreference = "Stop"

# ── Config - from pipeline variables (PS 5.1 compatible) ──────
if ($env:RESOURCE_GROUP)  { $resourceGroup = $env:RESOURCE_GROUP }
else                      { $resourceGroup = "dev" }

if ($env:LOCATION)        { $location = $env:LOCATION }
else                      { $location = "eastus" }

if ($env:RUNBOOK_SCRIPT)  { $runbookScript = $env:RUNBOOK_SCRIPT }
else                      { $runbookScript = "scripts/delete-expired-secrets-runbook.ps1" }

if ($env:TEMPLATE_FILE)   { $templateFile = $env:TEMPLATE_FILE }
else                      { $templateFile = "infra/main.bicep" }

if ($env:PARAM_FILE)      { $paramFile = $env:PARAM_FILE }
else                      { $paramFile = "infra/main.bicepparam" }

Write-Host "========================================="
Write-Host "  Azure Secrets Cleanup - IaC Deploy"
Write-Host "========================================="
Write-Host "  Resource Group : $resourceGroup"
Write-Host "  Location       : $location"
Write-Host "  Template       : $templateFile"
Write-Host "  Runbook Script : $runbookScript"
Write-Host "========================================="
Write-Host ""

# ── Step 0: Check Azure CLI Extensions ────────────────────────
Write-Host "Step 0: Checking Azure CLI extensions..."

$extensions = az extension list --query "[].name" -o json | ConvertFrom-Json
if (-not $extensions) { $extensions = @() }

if ($extensions -notcontains "automation") {
    Write-Host "  Installing Azure CLI automation extension..."
    az extension add --name automation
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install automation extension."
        exit 1
    }
    Write-Host "  Extension installed." -ForegroundColor Green
} else {
    Write-Host "  Automation extension already installed." -ForegroundColor Green
}
Write-Host ""

# ── Step 1: Calculate Next Sunday ─────────────────────────────
Write-Host "Step 1: Calculating next Sunday schedule time..."

$today           = [datetime]::UtcNow
$dayOfWeek       = [int]$today.DayOfWeek
$daysUntilSunday = (7 - $dayOfWeek) % 7

if ($daysUntilSunday -eq 0) {
    $daysUntilSunday = 7
}

$nextSunday        = $today.AddDays($daysUntilSunday).Date.AddHours(4)
$scheduleStartTime = $nextSunday.ToString("yyyy-MM-ddTHH:mm:ss+00:00")

Write-Host "  Today          : $($today.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
Write-Host "  Next Sunday    : $scheduleStartTime"
Write-Host ""

# ── Step 2: Create Resource Group ─────────────────────────────
Write-Host "Step 2: Creating resource group if not exists..."

az group create --name $resourceGroup --location $location --tags Solution=SecretsCleanup ManagedBy=Bicep Environment=dev

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create resource group: $resourceGroup"
    exit 1
}

Write-Host "  Resource group ready: $resourceGroup" -ForegroundColor Green
Write-Host ""

# ── Step 3: Deploy Bicep ──────────────────────────────────────
Write-Host "Step 3: Deploying Bicep template..."

$deployOutput = az deployment group create --resource-group $resourceGroup --template-file $templateFile --parameters $paramFile --parameters scheduleStartTime=$scheduleStartTime --mode Incremental --query "properties.outputs" --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Bicep deployment failed."
    exit 1
}

$automationAccountName = $deployOutput.automationAccountName.value
$principalId           = $deployOutput.principalId.value
$runbookName           = $deployOutput.runbookName.value
$scheduleName          = $deployOutput.scheduleName.value

Write-Host "  Bicep deployment successful." -ForegroundColor Green
Write-Host "  Automation Account : $automationAccountName"
Write-Host "  Runbook            : $runbookName"
Write-Host "  Schedule           : $scheduleName"
Write-Host ""

# ── Step 4: Upload Runbook Content ────────────────────────────
Write-Host "Step 4: Uploading runbook script content..."

if (-not (Test-Path $runbookScript)) {
    Write-Error "Runbook script not found at: $runbookScript"
    exit 1
}

az automation runbook replace-content --automation-account-name $automationAccountName --resource-group $resourceGroup --name $runbookName --content @$runbookScript

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to upload runbook content."
    exit 1
}

Write-Host "  Runbook content uploaded." -ForegroundColor Green

Write-Host "  Publishing runbook..."

az automation runbook publish --automation-account-name $automationAccountName --resource-group $resourceGroup --name $runbookName

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to publish runbook."
    exit 1
}

Write-Host "  Runbook published and active." -ForegroundColor Green
Write-Host ""

# ── Step 5: Link Schedule to Runbook via REST API ─────────────
Write-Host "Step 5: Linking schedule to runbook..."

$subId = az account show --query id -o tsv

$existingUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccountName/jobSchedules?api-version=2023-11-01"

$existingRaw = az rest --method GET --url $existingUrl -o json | ConvertFrom-Json
$existing    = @($existingRaw.value | Where-Object { $_.properties.schedule.name -eq $scheduleName })

if ($existing.Count -gt 0) {
    Write-Host "  Schedule already linked to runbook. Skipping." -ForegroundColor Yellow
} else {
    $guid   = [System.Guid]::NewGuid().ToString()
    $putUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccountName/jobSchedules/$($guid)?api-version=2023-11-01"

    $bodyObject = @{
        properties = @{
            schedule   = @{ name = $scheduleName }
            runbook    = @{ name = $runbookName }
            parameters = @{}
        }
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    $bodyObject | ConvertTo-Json -Depth 5 | Set-Content -Path $tempFile -Encoding UTF8

    az rest --method PUT --url $putUrl --body "@$tempFile" --headers "Content-Type=application/json"

    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to link schedule to runbook."
        exit 1
    }
    Write-Host "  Schedule linked to runbook successfully." -ForegroundColor Green
}
Write-Host ""

# ── Step 6: Install Graph Modules in Automation Account ───────
Write-Host "Step 6: Installing required PowerShell modules..."
Write-Host "  Note: Each module may take 2-3 minutes to install."
Write-Host ""

$subId = az account show --query id -o tsv

$modules = @(
    @{
        Name       = "Microsoft.Graph.Authentication"
        GalleryUrl = "https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication"
    },
    @{
        Name       = "Microsoft.Graph.Applications"
        GalleryUrl = "https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Applications"
    }
)

foreach ($module in $modules) {
    Write-Host "  Processing: $($module.Name)..."

    $moduleUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccountName/modules/$($module.Name)?api-version=2023-11-01"

    # ── Check current state ────────────────────────────────────
    $previousPreference    = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $existingRaw           = az rest --method GET --url $moduleUrl -o json 2>&1
    $existingExitCode      = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference

    if ($existingExitCode -eq 0) {
        $existingState = ($existingRaw | ConvertFrom-Json).properties.provisioningState
    } else {
        $existingState = "NotFound"
    }

    Write-Host "  Current state: $existingState"

    # ── Skip if already installed ──────────────────────────────
    if ($existingState -eq "Succeeded") {
        Write-Host "  Already installed: $($module.Name)" -ForegroundColor Green
        Write-Host ""
        continue
    }

    # ── Install via REST API ───────────────────────────────────
    Write-Host "  Installing: $($module.Name)..."

    $bodyObject = @{
        properties = @{
            contentLink = @{
                uri = $module.GalleryUrl
            }
        }
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    $bodyObject | ConvertTo-Json -Depth 5 | Set-Content -Path $tempFile -Encoding UTF8

    $previousPreference    = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    az rest --method PUT --url $moduleUrl --body "@$tempFile" --headers "Content-Type=application/json" -o json 2>&1 | Out-Null
    $installExitCode       = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference

    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    if ($installExitCode -ne 0) {
        Write-Error "Failed to start module installation: $($module.Name)"
        exit 1
    }

    Write-Host "  Install started. Waiting for completion..."

    # ── Wait for install to complete ───────────────────────────
    $maxAttempts = 20
    $attempt     = 0
    $installed   = $false

    while (-not $installed -and $attempt -lt $maxAttempts) {
        $attempt++
        Start-Sleep -Seconds 30

        $previousPreference    = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $checkRaw              = az rest --method GET --url $moduleUrl -o json 2>&1
        $checkExitCode         = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference

        if ($checkExitCode -eq 0) {
            $state = ($checkRaw | ConvertFrom-Json).properties.provisioningState
        } else {
            $state = "Unknown"
        }

        Write-Host "  Attempt $attempt/$maxAttempts - State: $state"

        if ($state -eq "Succeeded") {
            $installed = $true
            Write-Host "  [INSTALLED] $($module.Name)" -ForegroundColor Green
        } elseif ($state -eq "Failed") {
            Write-Error "Module installation failed: $($module.Name)"
            exit 1
        }
    }

    if (-not $installed) {
        Write-Error "Module install timed out after $($maxAttempts * 30) seconds: $($module.Name)"
        exit 1
    }

    Write-Host ""
}

Write-Host "  All modules ready." -ForegroundColor Green
Write-Host ""

# ── Step 7: Print Summary and Manual Steps ────────────────────
Write-Host "========================================="
Write-Host "DEPLOYMENT COMPLETE"
Write-Host "========================================="
Write-Host "Automation Account : $automationAccountName"
Write-Host "Resource Group     : $resourceGroup"
Write-Host "Runbook            : $runbookName"
Write-Host "Schedule           : $scheduleName"
Write-Host "Next Run           : Every Sunday 4AM UTC"
Write-Host ""
Write-Host "========================================="
Write-Host "ACTION REQUIRED - MANUAL STEP"
Write-Host "========================================="
Write-Host "Grant Graph API permissions to Managed Identity."
Write-Host ""
Write-Host "Principal ID : $principalId"
Write-Host ""
Write-Host "Run this command on your machine:"
Write-Host ""
Write-Host "  .\setup\grant-graph-permissions.ps1 ``"
Write-Host "      -ManagedIdentityClientId '$principalId'"
Write-Host ""
Write-Host "After permissions granted:"
Write-Host "  Monitor jobs at Azure Portal:"
Write-Host "  Automation Accounts -> $automationAccountName -> Jobs"
Write-Host "========================================="
