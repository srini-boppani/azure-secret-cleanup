# ================================================================
# Confirm-AzureLogin.ps1
# Purpose  : Verifies Azure CLI is authenticated correctly
# Called by: Pipeline Diagnose stage via AzureCLI@2 task
# ================================================================

Write-Host "===== AZURE LOGIN ====="
az account show --query "{Subscription:name, TenantId:tenantId}" -o table

if ($LASTEXITCODE -ne 0) {
    Write-Error "Azure CLI login verification failed."
    exit 1
}

Write-Host "Azure login verified successfully."
