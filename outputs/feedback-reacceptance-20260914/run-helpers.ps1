param([string]$Target='phone')
. "$PSScriptRoot/helpers.ps1"
$device=if($Target -eq 'computer'){'127.0.0.1:5557'}else{'127.0.0.1:5555'}
$evidence=Join-Path $PSScriptRoot $Target
function Snap([string]$name,[switch]$Shot){ Ui $name -Shot:$Shot | Out-Null }
function Show { $uiNodes | Where-Object { $_.text -or $_.hint } | ForEach-Object { "$($_.text) | $($_.hint) | $($_.bounds)" } }
function LoadUi([string]$name) { $script:uiNodes=@(Nodes (Get-Content "$evidence/$name.json" -Raw -Encoding UTF8 | ConvertFrom-Json)) }
function Box($n) { if(!$n){throw 'Missing node'}; $v=@([regex]::Matches($n.bounds,'\d+')|ForEach-Object {[int]$_.Value}); @{x=[int](($v[0]+$v[2])/2);y=[int](($v[1]+$v[3])/2);left=$v[0];top=$v[1];right=$v[2];bottom=$v[3];width=$v[2]-$v[0];height=$v[3]-$v[1]} }
function Chat { ($uiNodes | Where-Object hint -eq 'ACCEPT_CHAT_SEND' | Select-Object -First 1).text }
function Check([string]$name,[bool]$ok,[string]$detail) {
  $row=[pscustomobject]@{name=$name;pass=$ok;detail=$detail;time=(Get-Date).ToString('o')}
  $row | ConvertTo-Json -Compress | Add-Content "$evidence/checks.jsonl" -Encoding UTF8
  if(!$ok){throw "FAIL $name : $detail"}; Write-Output "PASS $name : $detail"
}
function Setup([string]$name,[hashtable]$values) {
  Read-Settings "settings-$name-before" | Out-Null
  $xml=[xml](Get-Content "$evidence/settings-$name-before.xml" -Raw -Encoding UTF8)
  foreach($key in $values.Keys) {
    $item=$xml.preferences.string | Where-Object key -eq $key
    if(!$item){$item=$xml.CreateElement('string');$item.SetAttribute('key',$key);$xml.preferences.AppendChild($item)|Out-Null}
    $item.InnerText=[string]$values[$key]
  }
  $local=Join-Path $evidence "settings-$name.xml"
  $xml.Save($local)
  Invoke-Device shell aa force-stop com.example.shuangyuime.acceptance | Out-Null
  Invoke-Device shell aa force-stop com.corrosion.shuangyuime | Out-Null
  $sent=Invoke-Device file send $local /data/local/tmp/feedback-ime-settings.xml
  if($sent -notmatch 'FileTransfer finish'){throw "Settings transfer failed: $sent"}
  $copied=Invoke-Device shell cp /data/local/tmp/feedback-ime-settings.xml /data/app/el2/100/base/com.corrosion.shuangyuime/haps/entry/preferences/ime_settings
  if($copied){throw "Settings copy failed: $copied"}
  Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
  Start-Sleep -Milliseconds 700
  FreshHost
  Start-Sleep -Milliseconds 1500
  Snap "$name-ready"
}
function DeleteIcon {
  $m=Box ($uiNodes | Where-Object text -ceq 'M' | Select-Object -Last 1)
  $uiNodes | Where-Object { $_.type -eq 'Image' -and (Box $_).left -gt $m.right -and [Math]::Abs((Box $_).y-$m.y) -lt 100 } | Select-Object -First 1
}
function SwipeDelete {
  $b=Box (DeleteIcon)
  Invoke-Device shell uitest uiInput swipe $b.x $b.y $b.x ($b.y+100) 600 | Out-Null
}
function TapDelete { Tap (DeleteIcon) }
function SaveDisplay { Invoke-Device shell hidumper -s DisplayManagerService -a '-a' | Set-Content "$evidence/display.txt" }
function OpenSettings([string]$section) {
  Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
  Start-Sleep -Milliseconds 600
  Snap settings-navigation-home
  if(!($uiNodes | Where-Object text -eq $section)) { TextTap '‹'; Snap settings-navigation-back }
  TextTap $section
  Snap settings-navigation-section
}
function SetCandidate([string]$label) {
  OpenSettings '候选设置'
  TextTap '候选位置'
  Snap candidate-options
  TextTap $label
  Snap candidate-selected
}
function SetMode([string]$label) {
  OpenSettings '输入设置'
  TextTap '键盘使用方式'
  Snap mode-options
  TextTap $label
  Snap mode-selected
}
function ReadyHost {
  FreshHost
  Start-Sleep -Milliseconds 1300
  Snap host-ready
}
function WaitKeys {
  for($try=0;$try -lt 6;$try++) {
    Snap keyboard-ready
    if($uiNodes | Where-Object text -ceq 'Q'){return}
    Start-Sleep -Milliseconds 900
  }
  throw 'Virtual keyboard did not become ready'
}
