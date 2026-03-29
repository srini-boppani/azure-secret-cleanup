# Create_Apps.ps1
# Purpose : Creates App Registrations for testing
# 1. Configuration
$BaseName = "Janitor-Test-App"
$TotalApps = 10
$ShortExpiryMinutes = 5
$LongExpiryDays = 7

# 2. Connection
Connect-MgGraph -Scopes "Application.ReadWrite.All"

for ($i = 1; $i -le $TotalApps; $i++) {
    # Logic for Expiry Dates
    if ($i -le 5) {
        $ExpiryDate = (Get-Date).AddMinutes($ShortExpiryMinutes)
        $Label = "ShortLived"
    } else {
        $ExpiryDate = (Get-Date).AddDays($LongExpiryDays)
        $Label = "NextWeek"
    }

    $AppName = "$BaseName-$Label-$i"
    
    try {
        # --- PHASE 1: SEARCH & DESTROY ---
        # Look for existing apps with this name to prevent duplicates
        $ExistingApp = Get-MgApplication -Filter "displayName eq '$AppName'"
        if ($ExistingApp) {
            Write-Host "🗑️ Found existing app '$AppName'. Deleting..." -ForegroundColor Gray
            Remove-MgApplication -ApplicationId $ExistingApp.Id
        }

        # --- PHASE 2: INDIVIDUAL CREATION ---
        Write-Host "🚀 Creating New App [$i/$TotalApps]: $AppName" -ForegroundColor Cyan
        $NewApp = New-MgApplication -DisplayName $AppName

        # --- PHASE 3: ADD INDIVIDUAL SECRET ---
        $PasswordParams = @{
            ApplicationId = $NewApp.Id
            PasswordCredential = @{
                DisplayName = "Secret-for-$AppName"
                EndDateTime   = $ExpiryDate
            }
        }
        
        $SecretResult = Add-MgApplicationPassword @PasswordParams
        Write-Host "   ✅ App Created: $($NewApp.AppId)" -ForegroundColor Green
        Write-Host "   🔑 Secret Added (Expires: $($ExpiryDate.ToString('yyyy-MM-dd HH:mm:ss')))" -ForegroundColor Yellow
    }
    catch {
        Write-Error "   ❌ Error processing $AppName : $($_.Exception.Message)"
    }
}