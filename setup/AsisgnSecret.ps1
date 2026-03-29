# AsisgnSecret.ps1
# Purpose : Assigns secrets to App Registrations
$ExpiryDate = (Get-Date).AddMinutes(1)
Get-MgApplication -all|Select -First 3|%{
$PasswordParams = @{
            ApplicationId =$_.Id
            PasswordCredential = @{
                DisplayName = "Secret-for-test"
                EndDateTime   = $ExpiryDate
            }
        }
        
         Add-MgApplicationPassword @PasswordParams
}
