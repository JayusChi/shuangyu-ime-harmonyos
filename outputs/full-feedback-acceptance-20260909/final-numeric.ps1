. (Join-Path $PSScriptRoot 'helpers.ps1')
$evidence=Join-Path $evidence final-phone
New-Item -ItemType Directory -Force $evidence | Out-Null
FreshHost
Ui ready | Out-Null
Tap ($uiNodes | Where-Object {$_.hint -eq 'ACCEPT_CHAT_SEND'} | Select-Object -First 1)
Ui refocused | Out-Null
TextTap 'ϟ12'
Ui numeric | Out-Null
$committed=''
$cases=@(
  @{name='money';raw='=1234.5';candidates=@('壹仟贰佰叁拾肆元伍角整');select='=';text='壹仟贰佰叁拾肆元伍角整'},
  @{name='month';raw='=2026.8.';candidates=@('2026年8月');select='=';text='2026年8月'},
  @{name='date';raw='=2026.5.5';candidates=@('2026年5月5日','2026-05-05');select='粘贴';text='2026-05-05'},
  @{name='calc';raw='=123+5*6';candidates=@('123+5*6=153','153');select='粘贴';text='153'}
)
foreach($case in $cases) {
  foreach($c in $case.raw.ToCharArray()) { TextTap ([string]$c) }
  Ui ($case.name+'-candidates') -Shot | Out-Null
  $actual=@($uiNodes | Where-Object {$_.text -match '^\d+\.? '} | ForEach-Object {$_.text -replace '^\d+\.? ',''})
  if(($actual -join '|') -cne ($case.candidates -join '|')) { throw "$($case.name): wrong candidates $($actual -join '|')" }
  TextTap $case.select
  Ui ($case.name+'-committed') -Shot | Out-Null
  $committed+=$case.text
  $field=$uiNodes | Where-Object {$_.hint -eq 'ACCEPT_CHAT_SEND'} | Select-Object -First 1
  if($field.text -cne $committed) {throw "$($case.name): wrong commit $($field.text)"}
  "PASS $($case.name): candidates and commit"
}
TextTap '='
TextTap '='
Ui double-equals -Shot | Out-Null
$committed+='='
if(($uiNodes | Where-Object {$_.hint -eq 'ACCEPT_CHAT_SEND'} | Select-Object -First 1).text -cne $committed) {throw 'Double equals failed'}
'PASS double equals'
TextTap '='
TextTap '返回'
Ui alphabet | Out-Null
VKeys 'hello'
Ui english-candidate -Shot | Out-Null
if(!($uiNodes | Where-Object {$_.text -ceq '1 hello'})) {throw 'English candidate stale'}
TextTap '空格'
Ui english-committed -Shot | Out-Null
$committed+='hello'
if(($uiNodes | Where-Object {$_.hint -eq 'ACCEPT_CHAT_SEND'} | Select-Object -First 1).text -cne $committed) {throw 'English commit failed'}
'PASS temporary English'
