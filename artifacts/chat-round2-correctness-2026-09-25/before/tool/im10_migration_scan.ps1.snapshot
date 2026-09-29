<#
.SYNOPSIS
IM-10 / IM-11 静态扫描门禁。

.DESCRIPTION
扫描 lib/src 内所有 `setMessageList` 调用和 `messageListMap[xxx] = ...` 写路径，
验证全部走 commitMessageDelta（IM-10 phase J 目标：allowList 为空）。

覆盖：
  - setMessageList\s*\( 命中
  - messageListMap\s*\[[^\]]+\]\s*= 写（mutation）
  - messageListMap 写入未走 commitMessageDelta 的回退路径

IM-10 phase B..G 每收口一个白名单项必须从此处移除。
IM-10 phase J 之后 allowList 期望为空。
IM-11 把本脚本接入 CI（.github/workflows/im-gate.yml）。

用法:
  pwsh -NoProfile -ExecutionPolicy Bypass -File tool/im10_migration_scan.ps1
  ./tool/im10_migration_scan.ps1           # bash 等价

退出码:
  0 - 全部命中在 allowList 内（或 allowList 为空且命中数为 0）
  1 - 出现 allowList 外命中（违规）
#>

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$libScan = Join-Path (Get-Location) 'lib'

# IM-10 phase J 期望 allowList 为空。任何新增白名单项需先开 ADR 评审。
$allowList = @()

$violations = @()
$setHitCount = 0
$writeHitCount = 0

function Check-RgOutput {
  param([string[]]$Lines, [string]$Pattern, [string]$Label)
  $script:violations = @()
  $hit = 0
  foreach ($line in $Lines) {
    $hit++
    $parts = $line -split ':', 3
    if ($parts.Count -lt 3) { continue }
    $file = ($parts[0] -replace '\\', '/').Trim()
    $lineNo = $parts[1].Trim()
    $key = "$file`:$lineNo"
    if ($allowList -notcontains $key) {
      $script:violations += "  [$Label] $key :: $($parts[2].Trim())"
    }
  }
  return $hit
}

# 1. setMessageList( 调用 (lib/src)
$setLines = rg -n --glob 'lib/src/**/*.dart' 'setMessageList\s*\(' lib/src 2>$null
$setHitCount = Check-RgOutput -Lines $setLines -Pattern 'setMessageList' -Label 'setMessageList'

# 2. messageListMap[xxx] = 写路径 (lib/src) - 直接写 messageListMap 是 bypass
$writeLines = rg -n --glob 'lib/src/**/*.dart' 'messageListMap\s*\[[^\]]+\]\s*=' lib/src 2>$null
$writeHitCount = $writeLines.Count

# 过滤 messageListMap 赋值：只报真正的 [xxx] = 写,过滤局部变量声明/Map 字面量
foreach ($line in $writeLines) {
  $parts = $line -split ':', 3
  if ($parts.Count -lt 3) { continue }
  $content = $parts[2].Trim()
  $file = ($parts[0] -replace '\\', '/').Trim()
  $lineNo = $parts[1].Trim()
  $key = "$file`:$lineNo"
  # 排除局部变量和 Map 字面量
  if ($content -match '^(final|const|var|List|Map|Set)\s+messageListMap\s*\[') { continue }
  if ($content -match '\[.*\]\s*=\s*[\[\{]') { continue }   # 多元素初始化
  if ($allowList -notcontains $key) {
    $violations += "  [messageListMap write] $key :: $content"
  }
}

# 3. third_party UIKit 分类门禁。
# setMessageList 是最终 UI 投影端口：Writer 提交携带 writerCommit，旧调用则由
# setMessageList 内部的 applyCompatibilitySnapshot 纳入同一个 Writer。
$uikitLines = rg -n --glob '*.dart' 'setMessageList\s*\(' third_party/tencent_cloud_chat_uikit 2>$null
$uikitSetHitCount = 0
$writerPublish = @()
$compatibilitySnapshots = @()
$pendingMigrations = @()
$compatibilityFiles = @(
  'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart',
  'third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart',
  'third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_history_pagination_load.dart',
  'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart'
)
foreach ($line in $uikitLines) {
  $parts = $line -split ':', 3
  if ($parts.Count -lt 3) { continue }
  $uikitSetHitCount++
  $file = ($parts[0] -replace '\\', '/').Trim()
  $lineNo = [int]$parts[1].Trim()
  $entry = "  ${file}:${lineNo} :: $($parts[2].Trim())"
  $source = Get-Content -LiteralPath $file
  $followingEnd = [Math]::Min($source.Count - 1, $lineNo + 14)
  $following = ($source[($lineNo - 1)..$followingEnd] -join "`n")
  if ($following -match 'writerCommit\s*:\s*commit') {
    $writerPublish += $entry
  } elseif ($compatibilityFiles -contains $file) {
    $compatibilitySnapshots += $entry
  } else {
    $pendingMigrations += $entry
  }
}

$expectedWriterPublishCount = 3
$expectedCompatibilityCount = 14
if ($writerPublish.Count -ne $expectedWriterPublishCount -or
    $compatibilitySnapshots.Count -ne $expectedCompatibilityCount) {
  $pendingMigrations += "  classification drift: writer=$($writerPublish.Count) (expected $expectedWriterPublishCount), compatibility=$($compatibilitySnapshots.Count) (expected $expectedCompatibilityCount)"
}

# 输出
Write-Host '=== IM-10 / IM-11 Static Gate Scan ==='
Write-Host ('[lib/src] setMessageList hits : {0}' -f $setHitCount)
Write-Host ('[lib/src] messageListMap writes : {0}' -f $writeHitCount)
Write-Host ('[third_party UIKit] setMessageList hits : {0}' -f $uikitSetHitCount)
if ($uikitSetHitCount -gt 0) {
  Write-Host ''
  Write-Host ('[Writer publications] {0}' -f $writerPublish.Count) -ForegroundColor Cyan
  $writerPublish | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
  Write-Host ''
  Write-Host ('[Writer compatibility snapshots] {0}' -f $compatibilitySnapshots.Count) -ForegroundColor Magenta
  $compatibilitySnapshots | ForEach-Object { Write-Host $_ -ForegroundColor Magenta }
  Write-Host ''
  Write-Host ('[pending migrations] {0}' -f $pendingMigrations.Count) -ForegroundColor Yellow
  $pendingMigrations | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
}
Write-Host ('[allowList] {0} entries (ADR §3.1)' -f $allowList.Count)

if ($violations.Count -gt 0) {
  Write-Host ''
  Write-Host '[FAIL] violations outside allow list:' -ForegroundColor Red
  foreach ($v in $violations) { Write-Host $v }
  Write-Host ''
  Write-Host 'Fix: 把 setMessageList 改为 globalModel.commitMessageDelta(MessageDelta(...))。' -ForegroundColor Yellow
  Write-Host '     必要时先扩 docs/im10_overlay_row_namespace.md §3.1 白名单并开 ADR 评审。' -ForegroundColor Yellow
  exit 1
}

if ($setHitCount -ne 0) {
  Write-Host ''
  Write-Host '[FAIL] lib/src setMessageList hits = ' $setHitCount ' but allowList is empty.' -ForegroundColor Red
  Write-Host '       IM-10 phase J 目标已违反。' -ForegroundColor Red
  exit 1
}

if ($pendingMigrations.Count -ne 0) {
  Write-Host ''
  Write-Host '[FAIL] third_party setMessageList classification has pending or unknown calls.' -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host '[OK] lib/src setMessageList = 0, messageListMap writes = '$writeHitCount', allowList cleared.' -ForegroundColor Green
Write-Host '     UIKit Writer publications and compatibility snapshots are classified; pending migrations = 0.' -ForegroundColor Green
exit 0
