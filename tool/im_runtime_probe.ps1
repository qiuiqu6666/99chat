param(
  [Parameter(Mandatory = $true)][string]$DeviceId,
  [string]$PackageName = 'chat.chat99.chatpro',
  [string]$Adb = (Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'),
  [ValidateRange(5, 30)][int]$SampleSeconds = 30,
  [string]$OutputPath = 'test_outputs/im-ux-runtime-probe.json'
)
$ErrorActionPreference = 'Stop'
$appProcessId = (& $Adb -s $DeviceId shell pidof $PackageName).Trim()
if ($appProcessId -notmatch '^\d+$') { throw 'Expected one running app process.' }
$probe = [ordered]@{
  capturedAt = (Get-Date).ToString('o')
  deviceId = $DeviceId
  packageName = $PackageName
  processId = [int]$appProcessId
  scope = 'Read-only sample; user activity is uncontrolled; debug/emulator data is not a release thermal benchmark.'
  package = @(& $Adb -s $DeviceId shell dumpsys package $PackageName |
    Select-String 'versionCode=|versionName=|flags=|lastUpdateTime' |
    ForEach-Object { $_.Line.Trim() })
  memory = @(& $Adb -s $DeviceId shell dumpsys meminfo $PackageName |
    Select-String '^\s*(Native Heap|Dalvik Heap|TOTAL|Java Heap:|Native Heap:|Graphics:|Private Other:|System:)' |
    ForEach-Object { $_.Line.Trim() })
}

# Reuse a locally running DDS connection. Never persist its authentication URI.
$serviceUri = $null
$vm = $null
foreach ($process in Get-CimInstance Win32_Process -Filter "name = 'dart.exe'") {
  if ($process.CommandLine -notmatch 'development-service.*--vm-service-uri=([^\s"]+)') { continue }
  $candidate = [uri]$Matches[1]
  if (-not $candidate.IsLoopback) { continue }
  try {
    $candidateVm = (Invoke-RestMethod -Uri ($candidate.AbsoluteUri + 'getVM') -TimeoutSec 3).result
    if ($candidateVm.pid -eq [int]$appProcessId) {
      $serviceUri = $candidate.AbsoluteUri
      $vm = $candidateVm
      break
    }
  } catch { }
}
if ($serviceUri) {
  function Read-VM([string]$Method) {
    $response = Invoke-RestMethod -Uri ($serviceUri + $Method) -TimeoutSec 20
    if ($response.error) { throw "$Method - $($response.error.code): $($response.error.message)" }
    return $response.result
  }
  $main = $vm.isolates | Where-Object name -eq 'main' | Select-Object -First 1
  $isolateId = [uri]::EscapeDataString($main.id)
  $probe.vmVersion = $vm.version
  $probe.mainIsolateMemory = Read-VM "getMemoryUsage?isolateId=$isolateId"
  $probe.timelineFlags = Read-VM 'getVMTimelineFlags'
  $time = (Read-VM 'getVMTimelineMicros').timestamp
  $extent = $SampleSeconds * 1000000
  try {
    $cpu = Read-VM "getCpuSamples?isolateId=$isolateId&timeOriginMicros=$($time - $extent)&timeExtentMicros=$extent"
    $probe.cpu = [ordered]@{
      sampleCount = $cpu.sampleCount
      samplePeriodMicros = $cpu.samplePeriod
      timeExtentMicros = $cpu.timeExtentMicros
      note = 'Inclusive ticks overlap; sample counts are not frame timings or device CPU percentages.'
      applicationFunctions = @($cpu.functions |
        Where-Object { $_.inclusiveTicks -gt 0 -and $_.function.location.script.uri -match '^package:tencent_cloud_chat_(demo|uikit)/' } |
        Sort-Object inclusiveTicks -Descending | Select-Object -First 40 inclusiveTicks,exclusiveTicks,
        @{n='function';e={$_.function.name}},@{n='file';e={$_.function.location.script.uri}})
    }
  } catch { $probe.cpuUnavailable = $_.Exception.Message }
  $allocation = Read-VM "getAllocationProfile?isolateId=$isolateId"
  $probe.largestClasses = @($allocation.members | Sort-Object bytesCurrent -Descending |
    Select-Object -First 20 @{n='class';e={$_.class.name}},instancesCurrent,bytesCurrent)
  $cacheClass = $allocation.members | Where-Object { $_.class.name -eq 'ImageCache' } | Select-Object -First 1
  if ($cacheClass) {
    $classId = [uri]::EscapeDataString($cacheClass.class.id)
    $instances = Read-VM "getInstances?isolateId=$isolateId&objectId=$classId&limit=1"
    foreach ($instance in $instances.instances) {
      $objectId = [uri]::EscapeDataString($instance.id)
      $cache = Read-VM "getObject?isolateId=$isolateId&objectId=$objectId"
      $probe.imageCache = @($cache.fields | Select-Object @{n='field';e={$_.decl.name}},
        @{n='value';e={$_.value.valueAsString}},@{n='length';e={$_.value.length}})
    }
  }
} else {
  $probe.vmUnavailable = 'No matching local Dart development-service connection; OS memory only.'
}
$probe | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Saved aggregate diagnostics to $OutputPath"
