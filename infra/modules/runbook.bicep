// ================================================================
// runbook.bicep
// Purpose  : Creates PowerShell runbook container in Automation
//            Account. Actual script content uploaded via
//            deploy.ps1 using az automation runbook replace-content
// ================================================================

param automationAccountName string
param location              string
param tags                  object

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  name:     '${automationAccountName}/SecretCleanupRunbook'
  location: location
  tags:     tags

  properties: {
    runbookType:      'PowerShell'
    logProgress:      true
    logVerbose:       true
    logActivityTrace: 1
    description:      'Weekly cleanup of expired Azure AD App Registration secrets'
    publishContentLink: {
      uri:     'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation/scripts/AzureAutomationTutorial.ps1'
      version: '1.0.0.0'
    }
  }
}

output runbookName string = 'SecretCleanupRunbook'
