param([string]$Target='phone')
. "$PSScriptRoot/../feedback-acceptance-20260915/helpers.ps1" -Target $Target
$evidence=Join-Path $PSScriptRoot $Target
New-Item -ItemType Directory -Force $evidence | Out-Null
Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
Start-Sleep -Milliseconds 1200
Snap 'home'
TextTap '键盘与外观'
Snap 'appearance'
TextTap '键盘结构与皮肤'
Snap 'entry' -Shot
Check 'entry-visible' (@($uiNodes | Where-Object id -eq 'settings-open-skin-editor').Count -eq 1) 'Native settings row present'
IdTap 'settings-open-skin-editor'
Start-Sleep -Milliseconds 3500
Snap 'browser-ready' -Shot
Show
