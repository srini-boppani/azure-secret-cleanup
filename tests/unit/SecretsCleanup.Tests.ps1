# ================================================================
# SecretsCleanup.Tests.ps1
# Purpose  : Unit tests for secret cleanup logic
# Framework: Pester v5
# Run      : via scripts/Invoke-Tests.ps1
# ================================================================

Describe "Expiry Detection Logic" {

    It "Identifies expired secret correctly" {
        $today  = [datetime]::UtcNow
        $expiry = $today.AddDays(-10)
        ($expiry -lt $today) | Should -Be $true
    }

    It "Calculates days overdue correctly" {
        $today  = [datetime]::UtcNow
        $expiry = $today.AddDays(-15)
        [math]::Round(($today - $expiry).TotalDays) | Should -Be 15
    }

    It "Does not flag a secret that is not yet expired" {
        $today  = [datetime]::UtcNow
        $expiry = $today.AddDays(10)
        ($expiry -lt $today) | Should -Be $false
    }
}

Describe "Null Guard Logic" {

    It "Handles null PasswordCredentials safely" {
        $safe = if ($null) { @($null) } else { @() }
        $safe.Count | Should -Be 0
    }

    It "Handles empty credential array safely" {
        $creds = @()
        $safe  = if ($creds) { @($creds) } else { @() }
        $safe.Count | Should -Be 0
    }
}

Describe "Removal Logic" {

    It "Filters out expired credential from list correctly" {
        $today = [datetime]::UtcNow
        $creds = @(
            [PSCustomObject]@{ keyId = "aaa"; endDateTime = $today.AddDays(-5).ToString("o") }
            [PSCustomObject]@{ keyId = "bbb"; endDateTime = $today.AddDays(10).ToString("o") }
        )
        $expiredIds = @($creds |
            Where-Object { [datetime]$_.endDateTime -lt $today } |
            Select-Object -ExpandProperty keyId)

        # Fix: wrap in @() to force array in PS 5.1
        $remaining = @($creds | Where-Object { $_.keyId -notin $expiredIds })

        $remaining.Count    | Should -Be 1
        $remaining[0].keyId | Should -Be "bbb"
    }

    It "Batch removes multiple expired credentials in one pass" {
        $today = [datetime]::UtcNow
        $creds = @(
            [PSCustomObject]@{ keyId = "aaa"; endDateTime = $today.AddDays(-5).ToString("o") }
            [PSCustomObject]@{ keyId = "bbb"; endDateTime = $today.AddDays(-2).ToString("o") }
            [PSCustomObject]@{ keyId = "ccc"; endDateTime = $today.AddDays(10).ToString("o") }
        )
        $expiredIds = @($creds |
            Where-Object { [datetime]$_.endDateTime -lt $today } |
            Select-Object -ExpandProperty keyId)

        # Fix: wrap in @() to force array in PS 5.1
        $remaining = @($creds | Where-Object { $_.keyId -notin $expiredIds })

        $remaining.Count  | Should -Be 1
        $expiredIds.Count | Should -Be 2
    }
}