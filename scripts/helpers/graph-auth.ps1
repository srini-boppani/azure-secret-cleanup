# ================================================================
# graph-auth.ps1
# Purpose  : Shared helper for Microsoft Graph authentication
# Auth     : Azure CLI token injected by AzureCLI@2 pipeline task
# Usage    : Dot-source this file, then call Connect-ToMicrosoftGraph
# Note     : No credentials stored here
# ================================================================

function Connect-ToMicrosoftGraph {
    [CmdletBinding()]
    param()

    Write-Host "Acquiring Graph token via Azure CLI..."

    $tokenJson = az account get-access-token --resource https://graph.microsoft.com | ConvertFrom-Json

    if (-not $tokenJson.accessToken) {
        throw "Failed to acquire Graph token. Ensure AzureCLI@2 task runs before this script."
    }

    $secureToken = ConvertTo-SecureString $tokenJson.accessToken -AsPlainText -Force
    Connect-MgGraph -AccessToken $secureToken -NoWelcome

    $context = Get-MgContext
    Write-Host "Connected to Microsoft Graph."
    Write-Host "  Auth Type : $($context.AuthType)"
    Write-Host "  Client ID : $($context.ClientId)"
    Write-Host ""
}

function Disconnect-FromMicrosoftGraph {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
