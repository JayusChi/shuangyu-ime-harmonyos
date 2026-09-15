param([string]$DeviceTarget = '127.0.0.1:5555', [string]$Surface = 'phone')
. outputs/browser-fullscreen-fix-20260911/helpers.ps1
$device=$DeviceTarget
$evidence="outputs/browser-fullscreen-fix-20260911/$Surface"
New-Item -ItemType Directory -Path $evidence -Force | Out-Null

function Ready([string]$name) {
  if($Surface -eq 'phone') { Wait-Keyboard $name }
  else { Start-Sleep -Milliseconds 2500; Ui "$name-ready" | Out-Null }
}
function Type-Code([string]$code) {
  if($Surface -eq 'phone') { VKeys $code } else { Keys $code }
}
function Lookup-Choice([string]$name, [string]$label) {
  Type-Code 'oix'
  Ui "$name-menu" -Shot | Out-Null
  Tap ($uiNodes | Where-Object text -match ([regex]::Escape("「查」：$label")) | Select-Object -Last 1)
}
function Assert-Host([string]$name,[string]$expected) {
  Ui $name -Shot | Out-Null
  $field=$uiNodes | Where-Object hint -eq 'ACCEPT_CHAT_SEND' | Select-Object -First 1
  $pass=$null -ne $field -and $field.text -ceq $expected
  [pscustomobject]@{name=$name;expected=$expected;actual=$field.text;passed=$pass} |
    ConvertTo-Json | Set-Content "$evidence/$name-status.json" -Encoding utf8
  if(!$pass) {throw "Unexpected host text: $name / $($field.text)"}
}

# Force-stop the app as well as the system browser for a real cold UIAbility launch.
Invoke-Device shell aa force-stop com.corrosion.shuangyuime | Out-Null
Invoke-Device shell aa force-stop com.huawei.hmos.browser | Out-Null
FreshHost
Ready 'home'
Type-Code 'xhgw'
Wait-Web 'cold-home' '小鹤双拼　小鹤音形　'
TextTap '关闭'
Assert-Host 'home-return' ''

Invoke-Device shell aa force-stop com.corrosion.shuangyuime | Out-Null
FreshHost
Ready 'cursor'
Type-Code 'ni'
if($Surface -eq 'phone') { TextTap '空格' } else { Key 2050 }
Ui 'cursor-committed' | Out-Null
Lookup-Choice 'cursor' '你'
Wait-Web 'cold-cursor' '汉字：你'
Invoke-Device shell aa start -a EntryAbility -b com.example.shuangyuime.acceptance | Out-Null
Assert-Host 'cursor-return' '你'

# Keep the private web ability alive in the background, then send the same URL again.
Tap ($uiNodes | Where-Object hint -eq 'ACCEPT_CHAT_SEND' | Select-Object -First 1)
Ready 'repeat'
Lookup-Choice 'repeat' '你'
Wait-Web 'repeat-cursor' '汉字：你'
TextTap '刷新'
Wait-Web 'refresh-cursor' '汉字：你'
Invoke-Device shell aa start -a EntryAbility -b com.example.shuangyuime.acceptance | Out-Null
Ui 'change-host' | Out-Null
Fill-Hint 'ACCEPT_CHAT_SEND' '鹤'
Ready 'change'
Lookup-Choice 'change' '鹤'
Wait-Web 'warm-changed-character' '汉字：鹤'
TextTap '关闭'
Assert-Host 'repeat-return' '你鹤'

FreshHost
Ready 'copy'
Fill-Hint 'ACCEPT_SEARCH' '鹤'
Invoke-Device shell uitest uiInput keyEvent 2072 2017 | Out-Null
Invoke-Device shell uitest uiInput keyEvent 2072 2019 | Out-Null
Invoke-Device shell aa force-stop com.corrosion.shuangyuime | Out-Null
FreshHost
Ready 'clipboard'
Lookup-Choice 'clipboard' '剪贴板'
$deadline=(Get-Date).AddSeconds(20)
do {
  Ui 'clipboard-paste-wait' | Out-Null
  $pasteReady=@($uiNodes | Where-Object text -eq '粘贴查形').Count -gt 0
} while(!$pasteReady -and (Get-Date) -lt $deadline)
if(!$pasteReady) {throw 'Paste permission page did not appear'}
Ui 'clipboard-paste' -Shot | Out-Null
TextTap '粘贴'
Wait-Web 'cold-clipboard' '汉字：鹤'
"ACCEPT_WEB_RESULT=PASS surface=$Surface"
