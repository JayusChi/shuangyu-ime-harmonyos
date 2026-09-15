. (Join-Path $PSScriptRoot '../settings-ui-migration-20260909/helpers.ps1')
$evidence=Join-Path $PSScriptRoot 'phone'
function Ready([string]$name,[string]$id) {
  foreach($attempt in 1..6) { Ui $name | Out-Null; if($script:uiNodes.id -contains $id){return}; Start-Sleep -Milliseconds 250 }
  throw "Missing $id at $name"
}
function Pref([string]$key,[string]$expected,[string]$name) {
  Read-Settings $name | Out-Null
  $value=(([xml](Get-Content (Join-Path $evidence "$name.xml") -Raw)).preferences.string | Where-Object key -eq $key).'#text'
  if($value -cne $expected) {throw "$key expected $expected; got $value"}
  Write-Output "PASS $name $key=$value"
}
function ScrollDown([string]$name) {
  $scroll=$script:uiNodes | Where-Object type -eq 'Scroll' | Select-Object -Last 1
  $b=[regex]::Match($scroll.bounds,'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
  $x=([int]$b.Groups[1].Value+[int]$b.Groups[3].Value)/2
  Invoke-Device shell uitest uiInput swipe $x ([int]$b.Groups[4].Value-180) $x ([int]$b.Groups[2].Value+160) 450 | Out-Null
  Ui $name | Out-Null
}
Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
Ready final-home settings-section-appearance
IdTap settings-section-appearance
Ready final-appearance settings-customization
IdTap settings-customization
Ready final-customization settings-open-customization-structure
Ui customization-final -Shot | Out-Null
IdTap settings-open-customization-structure
Ready final-structure settings-import-structure
TextTap '宽空格布局'
Ui structure-selected | Out-Null
Pref keyboard_structure_id builtin.wide-space structure-selected
TextTap '默认键盘结构'
Ui structure-restored | Out-Null
Pref keyboard_structure_id builtin.default structure-restored
Ui structure-final -Shot | Out-Null
IdTap settings-back
Ready final-skin-entry settings-open-customization-skin
IdTap settings-open-customization-skin
Ready final-skin settings-import-skin
TextTap '柔和蓝'
Ui skin-selected | Out-Null
Pref keyboard_skin_id builtin.soft-blue skin-selected
TextTap '默认皮肤（跟随系统）'
Ui skin-restored | Out-Null
Pref keyboard_skin_id builtin.follow-system skin-restored
IdTap settings-back
Ready final-swipe-entry settings-open-customization-swipe
IdTap settings-open-customization-swipe
Ready final-swipe settings-back
Ui swipe-final -Shot | Out-Null
TextTap '保存'
Ui swipe-saved | Out-Null
Read-Settings swipe-saved | Out-Null
TextTap '导入映射'
Ui swipe-import-picker -Shot | Out-Null
Key 2
Ready returned-from-import settings-back
Ui swipe-after-picker | Out-Null
if($script:uiNodes.text -notcontains '下滑符号映射'){throw 'Import cancel did not return to swipe page'}
IdTap settings-back
Ready final-overview-back settings-open-customization-skin
IdTap settings-back
Ready final-theme-entry settings-open-theme
IdTap settings-open-theme
Ready final-themes settings-option-dark
IdTap settings-option-dark
Ui theme-dark | Out-Null
IdTap settings-back
Ready appearance-dark settings-customization
IdTap settings-customization
Ready customization-dark settings-open-customization-skin
Ui customization-dark -Shot | Out-Null
IdTap settings-open-customization-skin
Ready skin-dark settings-import-skin
Ui skin-dark -Shot | Out-Null
IdTap settings-back
Ready customization-dark-back settings-open-customization-swipe
IdTap settings-back
Ready appearance-dark-back settings-customization
IdTap settings-back
Ready home-dark settings-section-lexicon
IdTap settings-section-lexicon
Ready lexicon-dark settings-user-shortcuts
IdTap settings-user-shortcuts
Ready shortcuts-dark settings-choice-OPEN_URL
IdTap settings-choice-OPEN_URL
Ui shortcuts-dark -Shot | Out-Null
IdTap settings-back
Ready lexicon-dark-back settings-user-lexicon
IdTap settings-user-lexicon
Ready words-dark settings-choice-ADD
Ui words-dark -Shot | Out-Null
foreach($i in 1..5) {
  if($script:uiNodes.text -contains '添加覆盖来源'){break}
  ScrollDown "words-scroll-$i"
}
Ui words-transfer-sources-dark -Shot | Out-Null
foreach($label in @('合并导入','覆盖导入','导出到文本框','添加合并来源','添加覆盖来源','立即导入')) {
  if($script:uiNodes.text -notcontains $label) {throw "Missing old action $label"}
}
TextTap '导出到文本框'
Ui words-exported -Shot | Out-Null
IdTap settings-back
Ready lexicon-dark-final settings-user-lexicon
IdTap settings-back
Ready home-restore settings-section-appearance
IdTap settings-section-appearance
Ready appearance-restore settings-open-theme
IdTap settings-open-theme
Ready theme-restore settings-option-followSystem
IdTap settings-option-followSystem
Ui theme-restored | Out-Null
IdTap settings-back
Ready appearance-final settings-customization
IdTap settings-back
Ready home-final settings-section-appearance
Read-Settings settings-after | Out-Null
'PASS final package: structure/skin selection and restore, swipe save, import cancel, dark nested pages, lexicon transfer/source controls and export'
