# Setup Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [One-Time Setup](#one-time-setup)
3. [Deploying Dev Environment](#deploy-dev)
4. [Deploying Prod Environment](#deploy-prod)
5. [Adding a New Environment](#new-environment)
6. [Verification](#verification)

---

## 1. Prerequisites <a name="prerequisites"></a>

### Required Access

| Access | Level | Purpose |
|---|---|---|
| Azure subscription | Contributor | Deploy Azure resources |
| Azure AD tenant | Global Administrator | Grant Graph API permissions |
| Azure DevOps organization | Project Administrator | Create pipelines and service connections |

### Required Software (on agent machine)

| Software | Version | Purpose |
|---|---|---|
| Windows PowerShell | 5.1 | Run pipeline scripts |
| Azure CLI | Latest | Deploy Bicep and manage resources |
| Git | Latest | Source control |

### Verify Prerequisites
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Check Azure CLI
az --version

# Check Git
git --version
```

---

## 2. One-Time Setup <a name="one-time-setup"></a>

### Step 1 — Clone Repository
```powershell
git clone https://dev.azure.com/<your-org>/<your-project>/_git/<your-repo>
cd <your-repo>
git checkout IAC
```

### Step 2 — Install Agent Dependencies
```powershell
.\setup\install-dependencies.ps1
```

This installs:
- Microsoft.Graph.Authentication
- Microsoft.Graph.Applications
- Pester v5

### Step 3 — Configure Self-Hosted Agent

If agent is not yet configured:

1. Azure DevOps → Project Settings → Agent Pools
2. Create pool named `Srini_Machine`
3. Download agent → extract to `C:\azagent`
4. Run `.\config.cmd` with your ADO org URL and PAT token
5. Verify agent shows **Online** in Azure DevOps

### Step 4 — Create ADO Variable Group

1. Azure DevOps → Pipelines → Library → **+ Variable group**
2. Name: `tenant`
3. Add variable:

| Variable | Value | Mark as secret |
|---|---|---|
| MANAGED_IDENTITY_CLIENT_ID | Leave blank for now — add after first deploy | Yes |

4. Save

### Step 5 — Create Service Connection

1. Azure DevOps → Project Settings → Service Connections
2. **New service connection** → Azure Resource Manager
3. Authentication method: **App Registration (automatic)**
4. Credential: **Workload Identity Federation**
5. Scope: Subscription
6. Name: `sc-secrets-cleanup-dev`
7. Check **Grant access permission to all pipelines**
8. Save

### Step 6 — Assign Contributor Role to Service Connection

1. Azure Portal → Subscriptions → your subscription
2. Access Control (IAM) → Add role assignment
3. Role: **Contributor**
4. Assign to: your service connection app registration
5. Save

### Step 7 — Create Pipeline in Azure DevOps

1. Azure DevOps → Pipelines → **New Pipeline**
2. Azure Repos Git → select your repo
3. Existing Azure Pipelines YAML file
4. Branch: `IAC` | Path: `/pipelines/secret-cleanup.yml`
5. **Save** (do not run yet)

---

## 3. Deploying Dev Environment <a name="deploy-dev"></a>

### Step 1 — Review Dev Parameters

Open `iac/parameters/dev.bicepparam` and confirm:
```bicep
param environment = 'dev'
param location    = 'eastus'      // change to your preferred region
param prefix      = 'scleanup'    // change if needed
```

### Step 2 — Run the Pipeline

1. Azure DevOps → Pipelines → secret-cleanup
2. Click **Run Pipeline**
3. Select parameters:
   - Environment: `dev`
   - Service Connection: `sc-secrets-cleanup-dev`
   - Agent Pool: `Srini_Machine`
4. Click **Run**
5. Watch all 3 stages complete

### Step 3 — Copy Principal ID

From Stage 2 pipeline output, find and copy:
```
Principal ID : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### Step 4 — Grant Graph API Permissions

Run on your machine as **Global Administrator**:
```powershell
.\setup\grant-graph-permissions.ps1 `
    -ManagedIdentityClientId "<principal-id-from-step-3>"
```

### Step 5 — Update Variable Group

1. Azure DevOps → Pipelines → Library → `tenant` variable group
2. Set `MANAGED_IDENTITY_CLIENT_ID` = Principal ID from Step 3
3. Save

### Step 6 — Validate

1. Azure Portal → Automation Accounts → `scleanup-automation-dev`
2. Runbooks → SecretCleanupRunbook → **Start**
3. Watch Output tab — confirm it connects and scans successfully

---

## 4. Deploying Prod Environment <a name="deploy-prod"></a>

### Step 1 — Create Prod Service Connection

Repeat Step 5 from One-Time Setup:
- Name: `sc-secrets-cleanup-prod`
- Assign Contributor role

### Step 2 — Review Prod Parameters

Open `iac/parameters/prod.bicepparam` and confirm:
```bicep
param environment = 'prod'
param location    = 'eastus'
param prefix      = 'scleanup'
```

### Step 3 — Run Pipeline for Prod

1. Azure DevOps → Pipelines → secret-cleanup
2. Click **Run Pipeline**
3. Select:
   - Environment: `prod`
   - Service Connection: `sc-secrets-cleanup-prod`
4. Click **Run**

### Step 4 — Grant Graph Permissions for Prod

Copy Principal ID from Stage 2 output and run:
```powershell
.\setup\grant-graph-permissions.ps1 `
    -ManagedIdentityClientId "<prod-principal-id>"
```

---

## 5. Adding a New Environment <a name="new-environment"></a>

Example: adding `staging` environment.

### Step 1 — Create parameter file

Create `iac/parameters/staging.bicepparam`:
```bicep
using '../main.bicep'

param environment       = 'staging'
param location          = 'eastus'
param prefix            = 'scleanup'
param serviceConnection = 'sc-secrets-cleanup-staging'
param agentPool         = 'Srini_Machine'
param scheduleStartTime = '2099-01-01T04:00:00+00:00'
```

### Step 2 — Add to pipeline parameters

In `pipelines/secret-cleanup.yml` add `staging` to environment values:
```yaml
parameters:
  - name: environment
    values:
      - dev
      - staging    # add this
      - prod
  - name: serviceConnection
    values:
      - sc-secrets-cleanup-dev
      - sc-secrets-cleanup-staging    # add this
      - sc-secrets-cleanup-prod
```

### Step 3 — Create service connection

Create `sc-secrets-cleanup-staging` in ADO Project Settings.

### Step 4 — Run pipeline

Select `staging` environment when running pipeline.

No other files need changing.

---

## 6. Verification <a name="verification"></a>

### Verify Pipeline Completed Successfully

All 3 stages should show green in Azure DevOps pipeline run.

### Verify Resources in Azure Portal

1. Go to Azure Portal → Resource Groups
2. Open `rg-secrets-cleanup-<environment>`
3. Confirm `scleanup-automation-<environment>` exists

### Verify Automation Account Health

1. Automation Account → Overview → State: **Ok**
2. Identity → Status: **On** (System assigned)
3. Runbooks → SecretCleanupRunbook → Status: **Published**
4. Schedules → WeeklySecretCleanup → Enabled: **Yes**

### Verify Graph Permissions

1. Azure Portal → Azure Active Directory
2. Enterprise Applications → search your automation account name
3. Permissions → confirm `Application.ReadWrite.All` is listed

### Test Manual Run

1. Automation Account → Runbooks → SecretCleanupRunbook
2. Click **Start**
3. Job output should show:
   - Connected to Microsoft Graph successfully
   - Apps scanned count
   - Expired secrets found count
   - Summary

If job fails see [troubleshooting.md](troubleshooting.md).