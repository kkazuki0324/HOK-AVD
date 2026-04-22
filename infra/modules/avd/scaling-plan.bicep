// ============================================================================
// AVD Scaling Plan - スケジュールベースの VM 起動 / 停止
// ============================================================================
// Pooled:  ランプアップ → ピーク → ランプダウン → オフピーク
// Personal: 時間帯ごとに起動 / 切断時の自動停止を制御
// ============================================================================

@description('リソースのデプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('Spoke の識別名')
param spokeName string

@description('対象 Host Pool の Resource ID')
param hostPoolId string

@description('ホストプールタイプ')
@allowed(['Pooled', 'Personal'])
param hostPoolType string

@description('タイムゾーン')
param timeZone string = 'Tokyo Standard Time'

@description('ランプアップ開始時刻 (時)')
param rampUpStartHour int = 7

@description('ランプアップ開始時刻 (分)')
param rampUpStartMinute int = 30

@description('ピーク開始時刻 (時)')
param peakStartHour int = 8

@description('ピーク開始時刻 (分)')
param peakStartMinute int = 0

@description('ランプダウン開始時刻 (時)')
param rampDownStartHour int = 17

@description('ランプダウン開始時刻 (分)')
param rampDownStartMinute int = 30

@description('オフピーク開始時刻 (時)')
param offPeakStartHour int = 18

@description('オフピーク開始時刻 (分)')
param offPeakStartMinute int = 0

@description('タグ')
param tags object = {}

// ======================== Scaling Plan (共通) ========================

resource scalingPlan 'Microsoft.DesktopVirtualization/scalingPlans@2024-04-08-preview' = {
  name: '${prefix}-${spokeName}-sp'
  location: location
  tags: tags
  properties: {
    friendlyName: '${prefix} ${spokeName} スケーリングプラン (朝8時起動 / 18時停止)'
    description: '平日 ${peakStartHour}:${padLeft(string(peakStartMinute), 2, '0')} に起動、${offPeakStartHour}:${padLeft(string(offPeakStartMinute), 2, '0')} に停止'
    timeZone: timeZone
    hostPoolType: hostPoolType
    exclusionTag: 'excludeFromScaling'
    schedules: hostPoolType == 'Pooled'
      ? [
          {
            name: 'weekday-schedule'
            daysOfWeek: [
              'Monday'
              'Tuesday'
              'Wednesday'
              'Thursday'
              'Friday'
            ]
            rampUpStartTime: {
              hour: rampUpStartHour
              minute: rampUpStartMinute
            }
            rampUpLoadBalancingAlgorithm: 'BreadthFirst'
            rampUpMinimumHostsPct: 100
            rampUpCapacityThresholdPct: 80
            peakStartTime: {
              hour: peakStartHour
              minute: peakStartMinute
            }
            peakLoadBalancingAlgorithm: 'BreadthFirst'
            rampDownStartTime: {
              hour: rampDownStartHour
              minute: rampDownStartMinute
            }
            rampDownLoadBalancingAlgorithm: 'DepthFirst'
            rampDownMinimumHostsPct: 0
            rampDownCapacityThresholdPct: 90
            rampDownForceLogoffUsers: true
            rampDownWaitTimeMinutes: 30
            rampDownNotificationMessage: '業務時間終了に伴い、30分後にログオフされます。作業を保存してください。'
            rampDownStopHostsWhen: 'ZeroSessions'
            offPeakStartTime: {
              hour: offPeakStartHour
              minute: offPeakStartMinute
            }
            offPeakLoadBalancingAlgorithm: 'DepthFirst'
          }
        ]
      : []
    hostPoolReferences: [
      {
        hostPoolArmPath: hostPoolId
        scalingPlanEnabled: true
      }
    ]
  }
}

// ======================== Personal スケジュール (子リソース) ========================

resource personalWeekdaySchedule 'Microsoft.DesktopVirtualization/scalingPlans/personalSchedules@2024-04-08-preview' = if (hostPoolType == 'Personal') {
  parent: scalingPlan
  name: 'weekday-schedule'
  properties: {
    daysOfWeek: [
      'Monday'
      'Tuesday'
      'Wednesday'
      'Thursday'
      'Friday'
    ]
    // ランプアップ: VM を事前起動
    rampUpStartTime: {
      hour: rampUpStartHour
      minute: rampUpStartMinute
    }
    rampUpAutoStartHosts: 'All'
    rampUpStartVMOnConnect: 'Enable'
    rampUpActionOnDisconnect: 'None'
    rampUpMinutesToWaitOnDisconnect: 0
    rampUpActionOnLogoff: 'None'
    rampUpMinutesToWaitOnLogoff: 0
    // ピーク: 通常業務時間
    peakStartTime: {
      hour: peakStartHour
      minute: peakStartMinute
    }
    peakStartVMOnConnect: 'Enable'
    peakActionOnDisconnect: 'None'
    peakMinutesToWaitOnDisconnect: 0
    peakActionOnLogoff: 'None'
    peakMinutesToWaitOnLogoff: 0
    // ランプダウン: 切断/ログオフ時に自動停止
    rampDownStartTime: {
      hour: rampDownStartHour
      minute: rampDownStartMinute
    }
    rampDownStartVMOnConnect: 'Enable'
    rampDownActionOnDisconnect: 'Deallocate'
    rampDownMinutesToWaitOnDisconnect: 30
    rampDownActionOnLogoff: 'Deallocate'
    rampDownMinutesToWaitOnLogoff: 30
    // オフピーク: 即座に停止
    offPeakStartTime: {
      hour: offPeakStartHour
      minute: offPeakStartMinute
    }
    offPeakStartVMOnConnect: 'Enable'
    offPeakActionOnDisconnect: 'Deallocate'
    offPeakMinutesToWaitOnDisconnect: 5
    offPeakActionOnLogoff: 'Deallocate'
    offPeakMinutesToWaitOnLogoff: 5
  }
}

// ======================== Outputs ========================

output scalingPlanId string = scalingPlan.id
output scalingPlanName string = scalingPlan.name
