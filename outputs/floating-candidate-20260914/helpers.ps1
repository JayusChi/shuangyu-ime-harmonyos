$ErrorActionPreference = 'Stop'
$hdc = 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
$device = '127.0.0.1:5555'
$evidence = $PSScriptRoot
function Invoke-Device { & $hdc -t $device @args }
function Nodes($node) {
  if ($node.attributes) { $node.attributes }
  foreach ($child in $node.children) { Nodes $child }
}
function Ui([string]$name, [switch]$Shot) {
  Invoke-Device shell uitest dumpLayout -p /data/local/tmp/feedback-ui.json | Out-Null
  Invoke-Device file recv /data/local/tmp/feedback-ui.json (Join-Path $evidence "$name.json") | Out-Null
  if ($Shot) {
    Invoke-Device shell uitest screenCap -p /data/local/tmp/feedback-ui.png | Out-Null
    Invoke-Device file recv /data/local/tmp/feedback-ui.png (Join-Path $evidence "$name.png") | Out-Null
  }
  $script:uiNodes = @(Nodes (Get-Content (Join-Path $evidence "$name.json") -Raw -Encoding UTF8 | ConvertFrom-Json))
  $script:uiNodes | Where-Object { $_.text -or $_.type -match 'TextInput|TextArea' } | Select-Object text,id,type,bounds,hint
}
function Tap($node) {
  if (!$node) { throw 'Missing UI node' }
  $b = [regex]::Match($node.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
  Invoke-Device shell uitest uiInput click ([int](([int]$b.Groups[1].Value+[int]$b.Groups[3].Value)/2)) ([int](([int]$b.Groups[2].Value+[int]$b.Groups[4].Value)/2)) | Out-Null
}
function TextTap([string]$text) { Tap ($script:uiNodes | Where-Object { $_.text -ceq $text } | Select-Object -Last 1) }
function Fill-Hint([string]$hint, [string]$value) {
  $node=$script:uiNodes | Where-Object { $_.hint -eq $hint } | Select-Object -First 1
  if(!$node) {throw "Missing field $hint"}
  $b=[regex]::Match($node.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
  Invoke-Device shell uitest uiInput inputText ([int](([int]$b.Groups[1].Value+[int]$b.Groups[3].Value)/2)) ([int](([int]$b.Groups[2].Value+[int]$b.Groups[4].Value)/2)) $value | Out-Null
}
function IdTap([string]$id) { Tap ($script:uiNodes | Where-Object { $_.id -eq $id } | Select-Object -First 1) }
function Keys([string]$value) {
  foreach($ch in $value.ToCharArray()) {
    $code = switch -CaseSensitive ($ch) {
      ' ' { 2050 }; ';' { 2062 }; "'" {2063}; '.' {2044}; '+' {2066}; '*' {2010}; '-' {2057}; '/' {2064}; '=' {2058}
      default { if($ch -cmatch '[a-z]') {2017+[int]$ch-97} elseif($ch -match '[0-9]') {2000+[int]$ch-48} else {throw "Unsupported key $ch"} }
    }
    Invoke-Device shell uitest uiInput keyEvent $code | Out-Null
  }
}
function Key([int]$code) { Invoke-Device shell uitest uiInput keyEvent $code | Out-Null }
function VKeys([string]$value) { foreach($ch in $value.ToCharArray()) { TextTap ([string]$ch).ToUpperInvariant() } }
function Read-Settings([string]$name) {
  Invoke-Device file recv /data/app/el2/100/base/com.corrosion.shuangyuime/haps/entry/preferences/ime_settings (Join-Path $evidence "$name.xml") | Out-Null
  ([xml](Get-Content (Join-Path $evidence "$name.xml") -Raw)).preferences.string | Where-Object { $_.key -match 'candidate_font|floating_candidate_font|keyboard_height|haptic|key_sound|candidate_presentation|keyboard_profile|scheme_id|smart_period' } | ForEach-Object { "$($_.key)=$($_.'#text')" }
}
function Choose-Direct([string]$code, [int]$choice, [string]$name) {
  VKeys $code
  Ui "$name-menu" -Shot | Out-Null
  $items = @($uiNodes | Where-Object { $_.text -match '^\d+\.? \[' })
  if($items.Count -lt $choice) { throw "Missing direct candidate: $code/$choice" }
  Write-Output ($code+': '+(($items | ForEach-Object text) -join ' / '))
  Tap $items[$choice-1]
  Ui "$name-applied" | Out-Null
}
function FreshHost {
  Invoke-Device shell aa force-stop com.example.shuangyuime.acceptance | Out-Null
  Invoke-Device shell aa start -a EntryAbility -b com.example.shuangyuime.acceptance | Out-Null
  Start-Sleep -Milliseconds 1800
  Ui host | Out-Null
  Tap ($script:uiNodes | Where-Object { $_.hint -eq 'ACCEPT_CHAT_SEND' } | Select-Object -First 1)
  Start-Sleep -Milliseconds 500
}

