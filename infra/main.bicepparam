// ================================================================
// main.bicepparam
// Purpose  : Provides parameter values to main.bicep
//            No sensitive values here - safe for repo
// Note     : scheduleStartTime is NOT here - calculated dynamically
//            by deploy.ps1 at runtime
// ================================================================

using './main.bicep'

param environment = 'dev'
param location    = 'eastus'
param prefix      = 'scleanup'
param scheduleStartTime = '2099-01-01T04:00:00+00:00'

// scheduleStartTime is intentionally omitted here
// deploy.ps1 calculates next Sunday dynamically and passes it
// as an override at deployment time
