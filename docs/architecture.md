# Architecture

## Table of Contents
1. [Solution Overview](#overview)
2. [Component Design](#components)
3. [Authentication Architecture](#authentication)
4. [Infrastructure Design](#infrastructure)
5. [Pipeline Design](#pipeline)
6. [Data Flow](#dataflow)
7. [Design Decisions](#decisions)
8. [Security Architecture](#security)
9. [Cost Architecture](#cost)
10. [Future Roadmap](#roadmap)

---

## 1. Solution Overview <a name="overview"></a>

### Problem Statement

Azure AD App Registrations use client secrets for authentication.
These secrets have expiry dates. When secrets expire:

- Applications that use them stop authenticating
- Security audits flag expired credentials as findings
- Manual cleanup is time-consuming and error-prone
- Expired secrets accumulate and create compliance risk

### Solution Approach

An automated serverless job that runs weekly, scans all App
Registrations in the tenant and permanently removes any client
secrets that have passed their expiry date.

### Scope

| In Scope | Out of Scope |
|---|---|
| Removing expired client secrets | Certificate management |
| All App Registrations in tenant | Service Principal secrets |
| Weekly automated execution | Expiry notifications (separate flow) |
| Multi-environment support | Secret rotation |

---

## 2. Component Design <a name="components"></a>

### Azure Automation Account

The central compute resource. Hosts the runbook and executes it
on the defined schedule.
```
Automation Account: <prefix>-automation-<environment>
├── System Managed Identity
│     └── Granted: Application.ReadWrite.All (Graph API)
├── Runbook: SecretCleanupRunbook
│     └── Type: PowerShell 5.1
│     └── Content: delete-expired-secrets-runbook.ps1
├── Schedule: WeeklySecretCleanup
│     └── Frequency: Weekly
│     └── Day: Sunday
│     └── Time: 04:00 UTC
│     └── Expiry: Never
└── Modules:
      ├── Microsoft.Graph.Authentication
      └── Microsoft.Graph.Applications
```

**Why Automation Account over Azure Functions:**

| Criteria | Automation Account | Azure Functions |
|---|---|---|
| Free tier | 500 mins/month | 1M executions/month |
| PowerShell native | Yes | Requires custom setup |
| Built-in scheduling | Yes | Requires Timer trigger |
| Job history UI | Built-in | Requires App Insights |
| Setup complexity | Low | Medium |
| Weekly job fit | Excellent | Good |

For a weekly PowerShell job, Automation Account is the
natural fit with built-in scheduling and job history.

---

### System Managed Identity

The identity used by the Automation Account to authenticate
to Microsoft Graph API.
```
System Managed Identity
├── Created automatically with Automation Account
├── No client secret - Azure manages credentials
├── Principal ID used for role assignments
└── Granted: Application.ReadWrite.All on Graph API
```

**Why System Managed Identity over User Managed Identity:**

System Managed Identity is tied to the lifecycle of the
Automation Account. When the account is deleted the identity
is deleted automatically. No orphaned identities.

---

### Microsoft Graph API

Used to read and modify App Registrations.
```
Endpoints used:
GET  /v1.0/applications
     ?$select=id,displayName,passwordCredentials
     &$top=999
     Reads all App Registrations with their secrets

DELETE via:
POST /v1.0/applications/{id}/removePassword
     Removes a specific expired secret by KeyId
```

**Permission used:** `Application.ReadWrite.All`

This is the minimum permission required to remove password
credentials from App Registrations. More granular permissions
are not available in the Microsoft Graph API at this time.

---

### Azure DevOps Pipeline

Orchestrates the entire deployment process.
```
Trigger: Manual only
Stages:
  1. Validate   → unit tests must pass
  2. Deploy     → Bicep + runbook + modules
  3. Verify     → confirms all resources healthy
```

The pipeline is the only way infrastructure changes are
deployed — no manual portal changes.

---

## 3. Authentication Architecture <a name="authentication"></a>

### Two Authentication Layers
```
Layer 1: Pipeline → Azure
─────────────────────────
Azure DevOps Pipeline
        │
        │ Workload Identity Federation
        │ (OIDC token - no secret)
        ▼
Azure Subscription
        │
        │ Contributor role
        ▼
Can deploy resources, run az commands

Layer 2: Runbook → Graph API
────────────────────────────
Azure Automation Runbook
        │
        │ Connect-MgGraph -Identity
        │ (IMDS endpoint - no secret)
        ▼
System Managed Identity
        │
        │ Application.ReadWrite.All
        ▼
Microsoft Graph API
```

### Why No Secrets Anywhere

| Authentication point | Method | Secret required? |
|---|---|---|
| Pipeline → Azure | Workload Identity Federation | No |
| Pipeline → ADO Variable Group | Encrypted storage | Read-only at runtime |
| Runbook → Graph API | System Managed Identity | No |
| Runbook → Azure metadata | IMDS endpoint | No |

---

## 4. Infrastructure Design <a name="infrastructure"></a>

### Bicep Module Structure
```
iac/main.bicep
├── Receives all parameters from bicepparam
├── Defines resource naming conventions
├── Calls modules in dependency order
└── Exposes outputs for deploy.ps1

iac/modules/automationAccount.bicep
├── Creates Automation Account
├── Enables System Managed Identity
└── Outputs: accountName, principalId

iac/modules/runbook.bicep
├── Creates runbook container
├── Sets PowerShell 5.1 runtime
└── Content uploaded separately by deploy.ps1

iac/modules/schedule.bicep
├── Creates weekly schedule
├── Start time passed dynamically
└── Never expires
```

### Naming Convention

All resource names follow this pattern:
```
<prefix>-<resource>-<environment>

Examples:
scleanup-automation-dev
scleanup-automation-prod

Resource Groups:
rg-secrets-cleanup-dev
rg-secrets-cleanup-prod
```

Prefix and environment are defined in bicepparam — no
hardcoded names anywhere in Bicep or scripts.

### Deployment Mode

All Bicep deployments use `Incremental` mode:
```
Incremental mode behavior:
─────────────────────────
Resource exists and matches Bicep → no change
Resource exists but config differs → update only that resource
Resource does not exist → create it
No existing resources deleted

Result: Safe to run pipeline multiple times
```

---

## 5. Pipeline Design <a name="pipeline"></a>

### Stage Gate Pattern
```
Validate → DeployInfra → Verify

Each stage only runs if previous stage succeeded.
If tests fail → infrastructure never deploys.
If deploy fails → verify never runs.
```

### Environment Selection

Environment is selected at runtime via pipeline parameter:
```
Run Pipeline
    │
    ▼
Select: environment = dev | prod
    │
    ▼
Pipeline passes: PARAM_FILE = iac/parameters/<env>.bicepparam
    │
    ▼
deploy.ps1 reads all values from bicepparam
    │
    ▼
Resources named and deployed for selected environment
```

### Single Source of Truth
```
iac/parameters/dev.bicepparam
    │
    │ read by
    ├── deploy.ps1         → derives resource names
    └── Verify-Deployment.ps1 → derives resource names to check
```

No resource names defined in pipeline YAML.
No resource names defined in scripts directly.
All derived from one bicepparam file per environment.

---

## 6. Data Flow <a name="dataflow"></a>

### Deployment Flow
```
Developer
    │ git push
    ▼
Azure DevOps Repo (IAC branch)
    │ manual trigger
    ▼
Pipeline: Validate Stage
    │ unit tests pass
    ▼
Pipeline: Deploy Stage
    │
    ├── az group create
    ├── az deployment group create (Bicep)
    ├── az automation runbook replace-content
    ├── az automation runbook publish
    ├── az rest PUT jobSchedules
    └── az rest PUT modules (x2)
    │
    ▼
Azure Resources Created/Updated
    │
    ▼
Pipeline: Verify Stage
    │ all checks pass
    ▼
Manual: grant-graph-permissions.ps1
    │
    ▼
Deployment Complete
```

### Runtime Flow (Every Sunday 4AM UTC)
```
Azure Scheduler
    │ triggers
    ▼
Azure Automation Job created
    │
    ▼
Runbook starts in Azure sandbox
    │
    ├── Connect-MgGraph -Identity
    ├── Get-MgApplication -All
    ├── Filter: EndDateTime < UtcNow
    ├── Remove-MgApplicationPassword (per expired secret)
    └── Write-Output summary
    │
    ▼
Job completes
    │
    ▼
Job status visible in Azure Portal
Job logs retained for 30 days
```

---

## 7. Design Decisions <a name="decisions"></a>

### Decision 1 — Azure Automation over Azure Functions

**Chosen:** Azure Automation Account
**Rejected:** Azure Functions

**Reason:** Azure Automation has built-in scheduling, native
PowerShell support, built-in job history UI and fits within
the free tier for a weekly job. Azure Functions would require
additional setup for scheduling and monitoring.

---

### Decision 2 — System vs User Managed Identity

**Chosen:** System Managed Identity
**Rejected:** User Assigned Managed Identity

**Reason:** System Managed Identity is lifecycle-bound to the
Automation Account. No orphaned identities when resources are
deleted. Simpler — no separate identity resource to manage.

---

### Decision 3 — Bicep over ARM Templates

**Chosen:** Bicep
**Rejected:** ARM Templates (JSON)

**Reason:** Bicep is the Microsoft-recommended modern IaC
language for Azure. Cleaner syntax, better tooling, compiles
to ARM. Easier to read, review and maintain.

---

### Decision 4 — PowerShell 5.1 over PowerShell 7

**Chosen:** PowerShell 5.1 (pwsh: false)
**Rejected:** PowerShell 7

**Reason:** Agent machine runs Windows PowerShell 5.1.
Azure Automation free tier supports PowerShell 5.1 runbooks.
Keeping consistent runtime avoids compatibility issues.

---

### Decision 5 — No Expiry Threshold Warning

**Chosen:** Remove expired secrets only
**Rejected:** Also warn about expiring-soon secrets

**Reason:** Expiry notifications are handled by a separate
flow. This solution has a single responsibility — remove
what is already expired. Keeping scope narrow reduces risk.

---

### Decision 6 — Job Schedule Link via REST API

**Chosen:** az rest PUT jobSchedules
**Rejected:** az automation job-schedule create

**Reason:** The az automation extension does not include a
job-schedule subcommand in the available preview version.
The REST API approach is more reliable and version-independent.

---

## 8. Security Architecture <a name="security"></a>

### Threat Model

| Threat | Mitigation |
|---|---|
| Credential theft | No credentials exist — Managed Identity |
| Secret exposure in logs | No secrets printed — tokens never logged |
| Unauthorized pipeline run | Manual trigger only — no auto-run on push |
| Overprivileged identity | Application.ReadWrite.All only — minimum needed |
| Infrastructure drift | IaC only — no manual portal changes |
| Malicious code in repo | Branch protection + PR review |
| Token interception | Short-lived tokens — 60-90 min expiry |
| Agent compromise | Self-hosted agent — isolated machine |

### Defense in Depth
```
Layer 1: No secrets to steal
  → System Managed Identity
  → Workload Identity Federation
  → No passwords in any file

Layer 2: Least privilege
  → Application.ReadWrite.All only
  → Contributor on subscription for pipeline only
  → No owner-level permissions

Layer 3: Audit trail
  → All runbook executions logged
  → Pipeline run history in ADO
  → Azure Activity Log captures all resource changes

Layer 4: Code integrity
  → All changes via pipeline
  → No manual portal deployments
  → IaC is the source of truth
```

---

## 9. Cost Architecture <a name="cost"></a>

### Azure Resources Monthly Cost

| Resource | Free Tier | Monthly Usage | Cost |
|---|---|---|---|
| Automation Account | 500 mins free | ~22 mins (weekly ~5 min job) | $0 |
| System Managed Identity | Always free | 1 identity | $0 |
| Runbook execution | Included | 4-5 runs/month | $0 |
| Job logs storage | Included | Minimal | $0 |
| Graph API calls | Always free | ~200 calls/week | $0 |

**Total monthly cost: $0**

### Azure DevOps Cost

| Component | Free Tier | Usage | Cost |
|---|---|---|---|
| Self-hosted agent | Unlimited | 1 agent | $0 |
| Pipeline runs | Unlimited (self-hosted) | As needed | $0 |
| Repo storage | 250GB | Minimal | $0 |

**Total: $0**

---

## 10. Future Roadmap <a name="roadmap"></a>

### Phase 1 — Current
- Weekly automated secret cleanup
- IaC deployment via ADO pipeline
- Multi-environment support
- System Managed Identity auth

### Phase 2 — Planned
- Email/Teams notification on job completion
- Dashboard showing cleanup statistics
- Certificate expiry handling
- Configurable schedule per environment

### Phase 3 — Future
- Cross-tenant support
- Self-service portal for visibility
- Integration with ITSM for ticket creation
- Automated secret rotation (not just removal)