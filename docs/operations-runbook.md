# Operations Runbook

## Table of Contents
1. [Overview](#overview)
2. [Regular Operations](#regular-operations)
3. [Manual Operations](#manual-operations)
4. [Deployment Operations](#deployment-operations)
5. [Monitoring and Alerting](#monitoring)
6. [Incident Response](#incident-response)
7. [Maintenance](#maintenance)
8. [Contacts and Escalation](#contacts)

---

## 1. Overview <a name="overview"></a>

### Purpose
This runbook provides operational procedures for the Azure AD Secret
Cleanup solution. It covers day-to-day monitoring, manual interventions,
deployment procedures and incident response.

### Solution Summary

| Property | Value |
|---|---|
| Solution Name | Azure AD Secret Cleanup |
| Run Frequency | Every Sunday 4AM UTC |
| Azure Resource | Automation Account |
| Authentication | System Managed Identity |
| Deployment | Azure DevOps Pipeline |
| Repository | Azure DevOps + GitHub |

### Operational Responsibilities

| Task | Frequency | Owner |
|---|---|---|
| Monitor weekly job results | Weekly | Operations |
| Review failed jobs | As needed | Operations |
| Deploy code changes | As needed | DevOps |
| Renew service connection | Yearly (if using secret) | DevOps |
| Review Graph permissions | Quarterly | Security |
| Validate test results | Each deployment | DevOps |

---

## 2. Regular Operations <a name="regular-operations"></a>

### Weekly Job Monitoring

Every Monday check that Sunday's job completed successfully:

**Step 1 — Check job status**
1. Azure Portal → Automation Accounts → `scleanup-automation-<env>`
2. Click **Jobs** in left menu
3. Find most recent job (Sunday)
4. Confirm Status = **Completed**

**Step 2 — Review job output**
1. Click the completed job
2. Click **Output** tab
3. Review summary:
```
=========================================
SUMMARY
=========================================
Apps Scanned  : <number>
Expired Found : <number>
Removed       : <number>
Failed        : <number>
=========================================
```

**Step 3 — Action based on results**

| Result | Action |
|---|---|
| Status = Completed, Failed = 0 | No action needed |
| Status = Completed, Failed > 0 | Review failed items, investigate manually |
| Status = Failed | Follow Incident Response procedure |
| No job found for Sunday | Check schedule is active, follow Incident Response |

---

### Checking Schedule Status

Verify the weekly schedule is still active:

1. Automation Account → **Schedules**
2. Find `WeeklySecretCleanup`
3. Confirm:
   - Enabled: **Yes**
   - Next Run: shows upcoming Sunday date
   - Frequency: **Weekly**

If schedule is disabled see [Re-enabling a disabled schedule](#re-enable-schedule).

---

## 3. Manual Operations <a name="manual-operations"></a>

### Triggering a Manual Runbook Run

Use this to test after changes or investigate issues:

**Via Azure Portal:**
1. Automation Account → Runbooks → `SecretCleanupRunbook`
2. Click **Start**
3. Click **Yes** to confirm
4. You are redirected to the Job page automatically
5. Click **Output** tab → click **Refresh** to see live output
6. Wait for Status to change to `Completed` or `Failed`

**Via PowerShell:**
```powershell
az automation runbook start `
    --automation-account-name "scleanup-automation-<env>" `
    --resource-group          "rg-secrets-cleanup-<env>" `
    --name                    "SecretCleanupRunbook" `
    --only-show-errors
```

---

### Viewing Job History

See all past runs:

1. Automation Account → **Jobs**
2. Filter by:
   - Runbook name: `SecretCleanupRunbook`
   - Status: Failed (to see only failures)
   - Time range: last 30 days

**Job Status meanings:**

| Status | Meaning |
|---|---|
| Completed | Ran successfully |
| Failed | Script threw an error |
| Stopped | Manually stopped |
| Suspended | Waiting for input |
| Running | Currently executing |
| Queued | Waiting to start |

---

### Exporting Job Output

To save job output for audit or review:

1. Job page → Output tab
2. Click **Export output** button (top of page)
3. Saves as text file

---

### Re-enabling a Disabled Schedule <a name="re-enable-schedule"></a>

If the schedule was accidentally disabled:

**Via Portal:**
1. Automation Account → Schedules → `WeeklySecretCleanup`
2. Click **Enable**

**Via PowerShell:**
```powershell
az automation schedule update `
    --automation-account-name "scleanup-automation-<env>" `
    --resource-group          "rg-secrets-cleanup-<env>" `
    --name                    "WeeklySecretCleanup" `
    --is-enabled              true `
    --only-show-errors
```

---

### Updating the Runbook Script

When the cleanup logic needs to change:

1. Edit `scripts/delete-expired-secrets-runbook.ps1` in repository
2. Commit and push to `main` branch
3. Run the pipeline — Step 4 automatically re-uploads and republishes
4. Trigger a manual run to validate the change

> Never edit the runbook directly in Azure Portal — changes will be
> overwritten on next pipeline run.

---

### Granting Graph Permissions to a New Environment

Run as **Global Administrator**:
```powershell
.\setup\grant-graph-permissions.ps1 `
    -ManagedIdentityClientId "<principal-id>"
```

Principal ID found at:
Azure Portal → Automation Account → Identity → Object (principal) ID

---

### Verifying Graph Permissions Are Active
```powershell
# Connect as admin
Connect-MgGraph -Scopes "Application.Read.All" -NoWelcome

# Get the service principal for the Managed Identity
$sp = Get-MgServicePrincipal -Filter "displayName eq 'scleanup-automation-<env>'"

# List role assignments
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id |
    Select-Object AppRoleId, PrincipalDisplayName

Disconnect-MgGraph
```

Expected output includes `Application.ReadWrite.All` role ID.

---

## 4. Deployment Operations <a name="deployment-operations"></a>

### Running a Deployment

**Prerequisites before deploying:**
- [ ] Agent machine is online
- [ ] Service connection is verified in ADO
- [ ] Code changes are reviewed and merged to target branch
- [ ] Variable group `tenant` is configured

**Steps:**
1. Azure DevOps → Pipelines → `secret-cleanup`
2. Click **Run Pipeline**
3. Select parameters:

| Parameter | Dev | Prod |
|---|---|---|
| environment | dev | prod |
| serviceConnection | sc-secrets-cleanup-dev | sc-secrets-cleanup-prod |
| agentPool | Srini_Machine | Srini_Machine |

4. Click **Run**
5. Monitor all 3 stages

**Post-deployment checklist:**
- [ ] Stage 1 Validate: all tests passed
- [ ] Stage 2 DeployInfra: all steps completed
- [ ] Stage 3 Verify: all checks passed
- [ ] Manual runbook test completed successfully
- [ ] Graph permissions verified

---

### Rolling Back a Deployment

Since Bicep uses Incremental mode there is no automatic rollback.
To roll back a change:

1. Revert the commit in the repository
2. Push the revert to main
3. Run the pipeline — Bicep will redeploy the previous state

For runbook-only changes:
1. Revert `scripts/delete-expired-secrets-runbook.ps1`
2. Push the revert
3. Run pipeline — Step 4 re-uploads the previous script version

---

### Deploying to a New Environment

1. Create `iac/parameters/<env>.bicepparam`
2. Create service connection `sc-secrets-cleanup-<env>` in ADO
3. Add environment to pipeline parameters in `pipelines/secret-cleanup.yml`
4. Assign Contributor role to service connection
5. Run pipeline with new environment selected
6. Grant Graph permissions to new Managed Identity
7. Validate with manual runbook run

Full details: [docs/setup-guide.md — Adding a New Environment](setup-guide.md#new-environment)

---

## 5. Monitoring and Alerting <a name="monitoring"></a>

### Current Monitoring Approach

Job results are visible in Azure Automation portal.
No automated alerting is configured in this version.

### Recommended Monitoring Setup (Future)

For production workloads consider adding:

**Option 1 — Azure Monitor Alert**
1. Automation Account → Alerts → New alert rule
2. Condition: Automation Job Failed
3. Action: Email notification or Teams webhook

**Option 2 — Log Analytics Workspace**
1. Connect Automation Account to Log Analytics
2. Create alert query:
```kusto
AzureDiagnostics
| where ResourceType == "AUTOMATIONACCOUNTS"
| where ResultType == "Failed"
| where RunbookName_s == "SecretCleanupRunbook"
```

### Key Metrics to Monitor

| Metric | Healthy | Investigate |
|---|---|---|
| Job status | Completed | Failed or missing |
| Apps scanned | > 0 | 0 (possible auth issue) |
| Removal failures | 0 | > 0 |
| Job duration | < 5 mins | > 15 mins |

---

## 6. Incident Response <a name="incident-response"></a>

### Runbook Job Failed

**Severity:** Medium

**Initial triage:**
1. Check job Exception tab for error message
2. Check job All Logs tab for full trace

**Common causes and fixes:**

| Error | Cause | Fix |
|---|---|---|
| IMDS unavailable | Wrong script version | Ensure runbook uses `Connect-MgGraph -Identity` |
| Insufficient privileges | Graph permissions missing | Run `grant-graph-permissions.ps1` |
| Module not found | Graph modules not installed | Re-run pipeline or install via Portal |
| Apps found: 0 | Permission not consented | Wait 10 mins after granting permissions |
| Timeout | Too many apps or slow Graph API | Increase retry wait time in script |

**Escalation:** If job fails for 2 consecutive weeks escalate to
DevOps team for investigation.

---

### Schedule Not Triggering

**Severity:** High — cleanup not running

**Steps:**
1. Check schedule is enabled:
   Automation Account → Schedules → WeeklySecretCleanup → Enabled = Yes
2. Check schedule-runbook link exists:
   Automation Account → Schedules → WeeklySecretCleanup → Linked runbooks
3. Check Automation Account state:
   Overview → State = Ok
4. If all look correct trigger a manual run to validate

**Fix if link is missing:**
Re-run the pipeline — Step 5 recreates the job schedule link.

---

### Pipeline Failing

**Severity:** Medium — deployment blocked

**Steps:**
1. Check which stage failed in Azure DevOps pipeline run
2. Review logs for the failed task
3. Common fixes:

| Stage | Common cause | Fix |
|---|---|---|
| Validate | Test logic error | Fix failing test |
| DeployInfra | Service connection permission | Add Contributor role |
| DeployInfra | Soft-deleted account | Recover deleted account |
| Verify | Resource not ready | Wait and re-run |

---

### Automation Account Accidentally Deleted

**Severity:** High

**Steps:**
1. Check if soft-deleted (recoverable):
```powershell
az rest --method GET `
    --url "https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.Automation/deletedAutomationAccounts?api-version=2024-10-23" `
    -o json
```

2. If found in soft-deleted state — recover:
```powershell
az rest --method POST `
    --url "https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.Automation/locations/<location>/deletedAutomationAccounts/<account-name>/recover?api-version=2024-10-23"
```

3. Re-run pipeline to ensure all resources are correctly configured
4. Re-grant Graph permissions
5. Validate with manual run

---

## 7. Maintenance <a name="maintenance"></a>

### Monthly Checks

- [ ] Review Azure Automation job history — any patterns of failure?
- [ ] Verify schedule next run date is correct
- [ ] Check Graph module versions — update if major version available
- [ ] Review Azure DevOps agent is up to date

### Quarterly Checks

- [ ] Review Graph API permissions — still least privilege?
- [ ] Review service connection — still valid?
- [ ] Review pipeline run history — any recurring issues?
- [ ] Test disaster recovery — delete and redeploy to confirm pipeline works

### Updating Graph Modules in Automation Account

When new major versions of Microsoft.Graph modules are released:

1. Automation Account → Modules → select module → Delete
2. Add module → Browse gallery → import new version
3. Wait for Available status
4. Trigger manual runbook run to validate

Or re-run pipeline — Step 6 will update if not already latest.

### Updating Azure CLI on Agent Machine
```powershell
az upgrade
```

### Rotating Service Connection (if using client secret)

> Note: This solution uses Workload Identity Federation which has
> no secrets to rotate. This section applies only if service
> connection type is changed to client secret in future.

1. ADO → Project Settings → Service Connections
2. Click service connection → Edit
3. Generate new credentials
4. Save and verify

---

## 8. Contacts and Escalation <a name="contacts"></a>

### Escalation Path
```
Level 1: Operations team
  └── Monitor weekly jobs
  └── Trigger manual runs
  └── Basic troubleshooting

Level 2: DevOps team
  └── Pipeline issues
  └── Code changes
  └── Infrastructure changes

Level 3: Security team
  └── Permission issues
  └── Audit requirements
  └── Compliance concerns
```

### Useful Links

| Resource | URL |
|---|---|
| Azure Portal | https://portal.azure.com |
| Azure DevOps | https://dev.azure.com |
| Microsoft Graph Explorer | https://developer.microsoft.com/graph/graph-explorer |
| Azure Automation docs | https://docs.microsoft.com/azure/automation |
| Bicep docs | https://docs.microsoft.com/azure/azure-resource-manager/bicep |
| Microsoft Graph PowerShell docs | https://docs.microsoft.com/powershell/microsoftgraph |

### Quick Reference Commands
```powershell
# Check automation account status
az automation account show `
    --name           "scleanup-automation-<env>" `
    --resource-group "rg-secrets-cleanup-<env>" `
    --query          "state" `
    --only-show-errors `
    -o tsv

# List recent jobs
az automation job list `
    --automation-account-name "scleanup-automation-<env>" `
    --resource-group          "rg-secrets-cleanup-<env>" `
    --only-show-errors `
    -o table

# Check schedule status
az automation schedule show `
    --automation-account-name "scleanup-automation-<env>" `
    --resource-group          "rg-secrets-cleanup-<env>" `
    --name                    "WeeklySecretCleanup" `
    --query                   "{Enabled:isEnabled,NextRun:nextRun}" `
    --only-show-errors `
    -o table

# Start runbook manually
az automation runbook start `
    --automation-account-name "scleanup-automation-<env>" `
    --resource-group          "rg-secrets-cleanup-<env>" `
    --name                    "SecretCleanupRunbook" `
    --only-show-errors
```