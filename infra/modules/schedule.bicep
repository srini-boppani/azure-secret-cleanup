// ================================================================
// schedule.bicep
// Purpose  : Creates weekly schedule in Automation Account
//            Job schedule link created via deploy.ps1 to avoid
//            GUID naming issues with jobSchedules in Bicep
// ================================================================

param automationAccountName string
param scheduleStartTime     string

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  name: '${automationAccountName}/WeeklySecretCleanup'

  properties: {
    description: 'Runs secret cleanup every Sunday at 4AM UTC'
    startTime:   scheduleStartTime
    expiryTime:  '9999-12-31T00:00:00+00:00'
    interval:    1
    frequency:   'Week'
    timeZone:    'UTC'
    advancedSchedule: {
      weekDays: [
        'Sunday'
      ]
    }
  }
}

output scheduleName string = 'WeeklySecretCleanup'
