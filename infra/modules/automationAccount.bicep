// ================================================================
// automationAccount.bicep
// Purpose  : Creates Azure Automation Account with System Managed
//            Identity for running PowerShell runbooks
// Free tier : 500 mins/month included - weekly job uses ~22 mins
// ================================================================

param name     string
param location string
param tags     object

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name:     name
  location: location
  tags:     tags

  // SystemAssigned creates Managed Identity automatically
  // No client ID to manage - Azure handles everything
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    sku: {
      name: 'Free'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
    publicNetworkAccess: true
    disableLocalAuth:    false
  }
}

// ── Outputs ───────────────────────────────────────────────────
// accountName  - used to deploy runbook and schedule into this account
// principalId  - use this manually to run grant-graph-permissions.ps1
output accountName  string = automationAccount.name
output accountId    string = automationAccount.id
output principalId  string = automationAccount.identity.principalId
output tenantId     string = automationAccount.identity.tenantId
