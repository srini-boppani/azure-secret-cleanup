# Azure AD Secret Cleanup

> Automated weekly removal of expired client secrets from Azure AD
> App Registrations using Azure Automation and Infrastructure as Code.

---

## Overview

Enterprise Azure AD tenants accumulate expired client secrets on App
Registrations over time. Left unmanaged these cause authentication
failures, security audit findings and compliance violations.

This solution automatically detects and removes expired secrets every
week using a fully serverless architecture — no virtual machines,
no scheduled tasks on local machines, no manual intervention required
after initial setup.

---

## Key Features

- **Fully automated** — runs every Sunday 4AM UTC without human intervention
- **Serverless** — runs entirely in Azure cloud via Azure Automation
- **Zero credentials** — authenticates via System Managed Identity
- **Infrastructure as Code** — all resources deployed via Bicep
- **Multi-environment** — supports dev, prod and any custom environment
- **Pipeline driven** — single Azure DevOps pipeline deploys everything
- **Idempotent** — safe to run multiple times without side effects
- **Auditable** — full job history in Azure Portal

---

## Architecture Summary
```
Azure DevOps Pipeline (manual trigger)
          │
          ▼
Bicep IaC deploys:
  ├── Azure Automation Account
  │     └── System Managed Identity
  ├── PowerShell Runbook
  └── Weekly Schedule (Sunday 4AM UTC)
          │
          ▼ Every Sunday automatically
Azure Automation runs Runbook
          │
          ▼
Managed Identity authenticates to Graph API
          │
          ▼
Scans all App Registrations
          │
          ▼
Removes expired client secrets
```

---

## Quick Start

### Prerequisites
- Azure subscription
- Azure DevOps organization
- Global Administrator access on Azure AD tenant
- Azure CLI installed on agent machine
- PowerShell 5.1 on agent machine

### Deploy in 3 steps

**Step 1 — Configure environment parameters**
```
iac/parameters/dev.bicepparam
```

**Step 2 — Run the pipeline**
```
Azure DevOps → Pipelines → secret-cleanup → Run Pipeline
Select: environment = dev
```

**Step 3 — Grant Graph permissions**
```powershell
.\setup\grant-graph-permissions.ps1 `
    -ManagedIdentityClientId "<principal-id-from-pipeline-output>"
```

Full setup instructions → [docs/setup-guide.md](docs/setup-guide.md)

---

## Repository Structure
```
azure-secret-cleanup/
│
├── iac/                                     # Infrastructure as Code
│   ├── main.bicep                           # Bicep entry point
│   ├── deploy.ps1                           # Deployment orchestration
│   ├── parameters/
│   │   ├── dev.bicepparam                   # Dev environment config
│   │   └── prod.bicepparam                  # Prod environment config
│   └── modules/
│       ├── automationAccount.bicep          # Automation Account + MI
│       ├── runbook.bicep                    # Runbook container
│       └── schedule.bicep                   # Weekly schedule
│
├── pipelines/
│   └── secret-cleanup.yml                   # ADO pipeline definition
│
├── scripts/
│   ├── helpers/
│   │   └── graph-auth.ps1                   # Graph auth helper
│   ├── delete-expired-secrets.ps1           # ADO pipeline version
│   ├── delete-expired-secrets-runbook.ps1   # Azure Automation version
│   ├── Invoke-Tests.ps1                     # Pester test runner
│   ├── Confirm-AzureLogin.ps1              # Login verification
│   ├── Show-AgentInfo.ps1                  # Agent diagnostics
│   └── Verify-Deployment.ps1               # Post-deploy checks
│
├── setup/
│   ├── grant-graph-permissions.ps1          # One-time Graph setup
│   ├── install-dependencies.ps1             # Agent dependencies
│   ├── AsisgnSecret.ps1                     # Test data utility
│   └── Create_Apps.ps1                      # Test data utility
│
├── tests/
│   └── unit/
│       └── SecretsCleanup.Tests.ps1         # Pester unit tests
│
├── docs/
│   ├── architecture.md                      # Architecture deep dive
│   ├── setup-guide.md                       # Full setup instructions
│   └── troubleshooting.md                   # Issue resolution guide
│
├── .gitignore
├── CHANGELOG.md
└── README.md
```

---

## Technology Stack

| Component | Technology | Reason |
|---|---|---|
| Infrastructure | Azure Bicep | Microsoft recommended IaC for Azure |
| Runtime | Azure Automation | Serverless, free tier, native Azure |
| Authentication | System Managed Identity | No secrets, auto-rotated |
| Graph API client | Microsoft.Graph PowerShell | Official Microsoft SDK |
| CI/CD | Azure DevOps Pipelines | Native ADO integration |
| Testing | Pester v5 | Standard PowerShell test framework |
| Agent | Self-hosted Windows | No parallelism cost |

---

## Security Highlights

- No credentials stored in code, pipeline or repository
- Workload Identity Federation on service connection
- System Managed Identity — zero secret management
- Least privilege Graph API permissions
- All sensitive values encrypted in ADO Variable Groups
- Full audit trail via Azure Automation job logs

Full security documentation → [docs/security.md](docs/security.md)

---

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/architecture.md) | Design decisions, component details |
| [Setup Guide](docs/setup-guide.md) | Full deployment walkthrough |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |

---

## License

Internal use only. Not for public distribution.