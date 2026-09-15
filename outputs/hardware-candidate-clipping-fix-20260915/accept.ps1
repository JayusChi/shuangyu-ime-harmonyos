param([string]$Target='phone')
. "$PSScriptRoot/../feedback-acceptance-20260915/helpers.ps1" -Target $Target
$evidence=Join-Path $PSScriptRoot $Target
New-Item -ItemType Directory -Force $evidence | Out-Null
function CandidateNodes { @($uiNodes | Where-Object { $_.text -match '^[1-9] ' }) }
function Page([string]$name) {
  Start-Sleep -Milliseconds 1000
  Snap $name -Shot
  $items=@(CandidateNodes)
  Check "$name-five-visible" ($items.Count -eq 5) (($items | ForEach-Object text) -join ', ')
  Check "$name-no-clipping" (@($items | Where-Object { $_.bounds -ne $_.origBounds }).Count -eq 0) 'All five candidate bounds equal unclipped bounds'
  $centers=@($items | ForEach-Object { (Box $_).y })
  Check "$name-horizontal" (($centers | Measure-Object -Maximum).Maximum - ($centers | Measure-Object -Minimum).Minimum -le 1) ($centers -join ', ')
  Check "$name-keyboard-paging-only" (@($uiNodes | Where-Object { $_.hostWindowId -eq $items[0].hostWindowId -and $_.text -in @('展开','‹','›') }).Count -eq 0) 'No expand or touch pager in candidate window'
}
SetMode '实体键盘'
ReadyHost
Start-Sleep -Milliseconds 1800
Keys 'ui'
Page 'page-1'
$first=(@(CandidateNodes) | ForEach-Object text) -join '|'
Key 2060
Page 'page-2'
$second=(@(CandidateNodes) | ForEach-Object text) -join '|'
Check 'next-changes-page' ($first -cne $second) $second
Key 2059
Page 'back-1'
Check 'previous-restores-page' ($first -ceq ((@(CandidateNodes) | ForEach-Object text) -join '|')) $first
Key 2060
Page 'back-2'
$expected=(@(CandidateNodes))[4].text.Substring(2)
Keys '5'
Start-Sleep -Milliseconds 800
Snap 'number-5' -Shot
Check 'fifth-number-commit' ((Chat) -ceq $expected) "Expected $expected, actual $(Chat)"
Keys 'ui'
for($page=1;$page -le 11;$page++) {
  if($page -gt 1){ Key 2060 }
  Page "batch-$page"
  if($page -eq 10){ $tenth=(@(CandidateNodes) | ForEach-Object text) -join '|' }
}
Key 2059
Page 'batch-back-10'
Check 'batch-boundary-previous' ($tenth -ceq ((@(CandidateNodes) | ForEach-Object text) -join '|')) $tenth
$expected+=(@(CandidateNodes))[4].text.Substring(2)
Keys '5'
Start-Sleep -Milliseconds 800
Snap 'batch-number-5' -Shot
Check 'batch-fifth-number-commit' ((Chat) -ceq $expected) "Expected $expected, actual $(Chat)"
SetMode '虚拟键盘'
SetCandidate '输入框下方'
ReadyHost
WaitKeys
VKeys 'ui'
Start-Sleep -Milliseconds 1000
Snap 'touch-pager' -Shot
Check 'touch-pager-preserved' (@($uiNodes | Where-Object { $_.type -eq 'Button' -and $_.text -eq '›' }).Count -ge 1) 'Touch next-page button remains available'
Key 2070
SetCandidate '固定候选栏'
SetMode $(if($Target -eq 'phone'){'自动识别'}else{'虚拟键盘'})
Snap 'restored-input-settings' -Shot
OpenSettings '候选设置'
Snap 'restored-candidate-settings' -Shot
Check 'candidate-count-preserved' (@($uiNodes | Where-Object text -eq '5 项').Count -ge 1) '5 candidates'
