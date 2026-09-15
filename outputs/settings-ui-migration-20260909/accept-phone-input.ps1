. (Join-Path $PSScriptRoot 'helpers.ps1')
$evidence = Join-Path $evidence 'phone'
function Snap([string]$name) {
  for ($attempt=0; $attempt -lt 6; $attempt++) {
    Ui $name | Out-Null
    if ($script:uiNodes | Where-Object { $_.id -like 'settings-*' }) { return }
  }
  throw "Settings screen did not settle: $name"
}
function RequireText([string]$text) {
  if (!($script:uiNodes | Where-Object { $_.text -ceq $text })) { throw "Missing text: $text" }
}
function Pref([string]$key,[string]$value,[string]$name) {
  Read-Settings $name | Out-Null
  $actual = ([xml](Get-Content -LiteralPath (Join-Path $evidence "$name.xml") -Raw)).preferences.string |
    Where-Object { $_.key -eq $key } | Select-Object -ExpandProperty '#text'
  if ($actual -cne $value) { throw "${name}: $key expected $value, got $actual" }
  "PASS $name $key=$actual"
}
function BackPage { IdTap settings-back; Snap back }
function Flip([string]$label,[string]$name) {
  $title = $script:uiNodes | Where-Object { $_.text -ceq $label } | Select-Object -First 1
  if (!$title) { throw "Missing switch label $label" }
  $top=[int]([regex]::Match($title.bounds,'\[\d+,(\d+)\]').Groups[1].Value)
  $toggle = $script:uiNodes | Where-Object { $_.type -eq 'Toggle' } | Where-Object {
    $y=[int]([regex]::Match($_.bounds,'\[\d+,(\d+)\]').Groups[1].Value)
    $y -ge $top -and $y -le $top+150
  } | Select-Object -First 1
  Tap $toggle; Snap $name
}
Snap input-test-start
RequireText '26 键小鹤音形'
IdTap settings-section-input; Snap input-final
RequireText '小鹤音形'
if ($script:uiNodes | Where-Object { $_.text -eq '学习输入习惯' }) { throw 'Learning still in input settings' }
IdTap settings-open-device; Snap devices
foreach($mode in @('HARDWARE','AUTO','TOUCH')) {
  IdTap "settings-option-$mode"; Snap "device-$mode"
  Pref input_presentation_preference $mode "device-$mode"
}
BackPage
IdTap settings-open-scheme; Snap schemes
IdTap settings-open-profiles-shuangpin; Snap double-layouts
foreach($profile in @('xiaohe-18','xiaohe-26')) {
  IdTap "settings-option-$profile"; Snap $profile; Pref keyboard_profile_id $profile $profile
}
BackPage
IdTap settings-open-profiles-pinyin; Snap pinyin-layouts
foreach($profile in @('pinyin-9','quanpin-26')) {
  IdTap "settings-option-$profile"; Snap $profile; Pref keyboard_profile_id $profile $profile
}
BackPage; BackPage
RequireText '拼音'
RequireText '拼写纠错'
Flip '拼写纠错' correction-on; Pref quanpin_spelling_correction_enabled true correction-on
Flip '拼写纠错' correction-off; Pref quanpin_spelling_correction_enabled false correction-off
IdTap settings-open-fuzzy; Snap fuzzy-all
foreach($label in @('n / l','z / zh','c / ch','s / sh','in / ing','en / eng','an / ang','ian / iang')) { RequireText $label }
Flip 'n / l' fuzzy-on; Pref quanpin_fuzzy_options '["n_l"]' fuzzy-on
Flip 'n / l' fuzzy-off; Pref quanpin_fuzzy_options '[]' fuzzy-off
BackPage
IdTap settings-open-scheme; Snap restore-scheme
IdTap settings-open-profiles-yinxing; Snap yinxing-layout
IdTap settings-option-xiaohe-yinxing-26; Snap yinxing-restored
Pref keyboard_profile_id xiaohe-yinxing-26 yinxing-restored
BackPage; BackPage
RequireText '小鹤音形'
RequireText '切分模式'
Flip '切分模式' split-off; Pref code_table_reverse_split_enabled false split-off
Flip '切分模式' split-on; Pref code_table_reverse_split_enabled true split-on
Flip '上屏后联想' association-on; Pref local_association_enabled true association-on
Flip '上屏后联想' association-off; Pref local_association_enabled false association-off
IdTap settings-open-ai; Snap ai-retained
RequireText '当前版本尚未开通云端 AI 服务，云端功能保持关闭。'
if (@($script:uiNodes | Where-Object {$_.type -eq 'Toggle'}).Count -ne 1) { throw 'AI toggle missing' }
BackPage
IdTap settings-open-punctuation; Snap punctuation
foreach($value in @('0','500','800','1000','300')) {
  IdTap "settings-option-$value"; Snap "punctuation-$value"; Pref smart_period_timeout_ms $value "punctuation-$value"
}
Ui punctuation-final -Shot | Out-Null
BackPage; BackPage
RequireText '26 键小鹤音形'
Ui home-after-schemes -Shot | Out-Null
'PASS all five keyboard profiles, three device modes, input switches, eight fuzzy entries, AI entry and punctuation durations'
