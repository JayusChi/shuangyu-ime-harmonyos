param([string]$Target='phone')
. "$PSScriptRoot/../feedback-acceptance-20260915/helpers.ps1" -Target $Target
$evidence=Join-Path $PSScriptRoot $Target
function RemoveTestTemplate([string]$kind) {
  $label=$uiNodes | Where-Object text -eq 'roundtrippc' | Select-Object -Last 1
  if(!$label){ throw 'Test template row missing' }
  $rowBox=Box $label
  $button=$uiNodes | Where-Object { $_.text -eq '删除' -and [Math]::Abs((Box $_).y-$rowBox.y) -lt 80 } | Select-Object -Last 1
  Tap $button
  Snap "$kind-remove-dialog"
  TextTap '删除'
  Start-Sleep -Milliseconds 700
  Snap "$kind-restored" -Shot
  Check "$kind-test-template-removed" (@($uiNodes | Where-Object text -eq 'roundtrippc').Count -eq 0) 'Only the test template removed'
}
Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
Start-Sleep -Milliseconds 900
Snap 'restore-home'
TextTap '键盘与外观'
Snap 'restore-appearance'
TextTap '键盘结构与皮肤'
Snap 'restore-entry'
TextTap '键盘皮肤'
Snap 'restore-skin-list'
TextTap $(if($Target -eq 'phone'){'柔和蓝'}else{'我的纯色皮肤'})
Snap 'skin-original-selected'
RemoveTestTemplate 'skin'
Key 2
Snap 'restore-entry-layout'
TextTap '键盘结构'
Snap 'restore-layout-list'
TextTap $(if($Target -eq 'phone'){'默认键盘结构'}else{'我的键盘结构'})
Snap 'layout-original-selected'
RemoveTestTemplate 'layout'
ReadyHost
WaitKeys
Snap 'restored-keyboard' -Shot
Check 'test-space-label-removed' (@($uiNodes | Where-Object text -eq 'qa space').Count -eq 0) 'Original keyboard restored'
