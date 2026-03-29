// ================================================================
// main.bicep
// Purpose  : Entry point for all IaC deployments
//            Calls all modules and passes parameters
// Deploy   : via infra/deploy.ps1 in pipeline
// ================================================================

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────
@description('Environment name - used in resource naming')
param environment string = 'dev'

@description('Azure region for all resources')
param location string = 'eastus'

@description('Resource prefix for naming')
param prefix string = 'scleanup'

@description('Start time for weekly schedule - must be future date')
param scheduleStartTime string

// ── Variables ─────────────────────────────────────────────────
var automationAccountName = '${prefix}-automation-${environment}'

var tags = {
  Environment : environment
  Solution    : 'SecretsCleanup'
  ManagedBy   : 'Bicep-IaC'
}

// ── Module: Automation Account ────────────────────────────────
module automation 'modules/automationAccount.bicep' = {
  name: 'deploy-automation-account'
  params: {
    name:     automationAccountName
    location: location
    tags:     tags
  }
}

// ── Module: Runbook ───────────────────────────────────────────
module runbook 'modules/runbook.bicep' = {
  name: 'deploy-runbook'
  params: {
    automationAccountName: automation.outputs.accountName
    location:              location
    tags:                  tags
  }
}

// ── Module: Schedule ──────────────────────────────────────────
module schedule 'modules/schedule.bicep' = {
  name: 'deploy-schedule'
  params: {
    automationAccountName: automation.outputs.accountName
    scheduleStartTime:     scheduleStartTime
  }
}

// ── Outputs ───────────────────────────────────────────────────
output automationAccountName string = automation.outputs.accountName
output principalId           string = automation.outputs.principalId
output runbookName           string = runbook.outputs.runbookName
output scheduleName          string = schedule.outputs.scheduleName
