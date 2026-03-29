# ================================================================
# Show-AgentInfo.ps1
# Purpose  : Displays agent environment info for diagnostics
# Called by: Pipeline Diagnose stage
# ================================================================

Write-Host "===== POWERSHELL VERSION ====="
$PSVersionTable

Write-Host ""
Write-Host "===== EXECUTION POLICY ====="
Get-ExecutionPolicy -List

Write-Host ""
Write-Host "===== GRAPH MODULES ====="
Get-Module Microsoft.Graph* -ListAvailable |
    Select-Object Name, Version |
    Format-Table -AutoSize

Write-Host ""
Write-Host "===== AZURE CLI VERSION ====="
az --version

Write-Host ""
Write-Host "===== AGENT USER ====="
whoami
