param([string]$Kind='phone', [string]$Target='127.0.0.1:5555', [switch]$Wide)
. (Join-Path $PSScriptRoot '../settings-ui-migration-20260909/helpers.ps1')
$device=$Target
$evidence=Join-Path $PSScriptRoot $Kind
function Ready([string]$name,[string]$id) {
  foreach($attempt in 1..6) {
    Ui $name | Out-Null
    $script:uiNodes=@($script:uiNodes | Where-Object { $_.visible -ne 'false' })
    if($script:uiNodes.id -contains $id) { return }
    Start-Sleep -Milliseconds 250
  }
  throw "Missing UI $id at $name"
}
function RequireText([string]$text) {
  if($script:uiNodes.text -notcontains $text) {throw "Missing text $text"}
}
function CheckPane([string]$name,[string]$detailText) {
  Ui $name -Shot | Out-Null
  RequireText $detailText
  $left=$script:uiNodes | Where-Object { $_.id -eq 'settings-section-appearance' } | Select-Object -First 1
  if($Wide) {
    if(!$left) { throw "Sidebar missing: $name" }
    $leftBounds=[regex]::Match($left.bounds,'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    $back=$script:uiNodes | Where-Object { $_.id -eq 'settings-back' } | Select-Object -Last 1
    $backBounds=[regex]::Match($back.bounds,'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if([int]$backBounds.Groups[1].Value -lt [int]$leftBounds.Groups[3].Value) { throw "Detail overlaps sidebar: $name" }
  } elseif($left) { throw "Phone detail unexpectedly shows sidebar: $name" }
  Write-Output "PASS $Kind $name : $detailText; split=$Wide"
}
Invoke-Device shell aa force-stop com.corrosion.shuangyuime | Out-Null
Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
Ready home settings-section-appearance
IdTap settings-section-appearance
Ready appearance settings-customization
IdTap settings-customization
Ready customization settings-open-customization-structure
CheckPane customization '键盘结构与皮肤'
IdTap settings-open-customization-structure
Ready structure settings-import-structure
CheckPane structure '导入结构包'
IdTap settings-back
Ready returned-from-structure settings-open-customization-skin
IdTap settings-open-customization-skin
Ready skin settings-import-skin
CheckPane skin '导入皮肤包'
Key 2
Ready returned-from-skin settings-open-customization-swipe
IdTap settings-open-customization-swipe
Ready swipe settings-back
Ui swipe-ready | Out-Null
CheckPane swipe '下滑符号映射'
RequireText '导入映射'; RequireText '导出映射'; RequireText '保存'
TextTap '英文键盘'
Ui swipe-english -Shot | Out-Null
RequireText '英文键盘'
TextTap '中文键盘'
Ui swipe-chinese | Out-Null
IdTap settings-back
Ready returned-from-swipe settings-open-customization-skin
IdTap settings-back
Ready returned-from-customization settings-customization
if(!$Wide) {IdTap settings-back; Ready home-before-lexicon settings-section-lexicon}
IdTap settings-section-lexicon
Ready lexicon settings-user-lexicon
IdTap settings-user-lexicon
Ready words settings-choice-ADD
CheckPane words '我的词库'
RequireText '隐藏系统词'; RequireText '保存并立即应用'
IdTap settings-back
Ready lexicon-again settings-user-shortcuts
IdTap settings-user-shortcuts
Ready shortcuts settings-choice-DIRECT
CheckPane shortcuts '自定义直通'
IdTap settings-choice-OPEN_URL
Ui shortcut-url -Shot | Out-Null
if($script:uiNodes.hint -notcontains '完整网址') {throw 'URL field missing'}
IdTap settings-choice-OPEN_DIRECTORY
Ui shortcut-directory -Shot | Out-Null
RequireText '选择目录'
IdTap settings-back
Ready lexicon-after-shortcuts settings-user-lexicon
if($script:uiNodes.id -contains 'settings-category-manager') {
  IdTap settings-category-manager
  Ready categories settings-back
  CheckPane categories '小鹤音形词库分类'
  RequireText '保存更改'; RequireText '重置默认'
  Key 2
  Ready returned-from-categories settings-user-lexicon
}
Read-Settings settings-after-navigation | Out-Null
Write-Output "PASS $Kind all migrated detail routes and nested customization routes"
