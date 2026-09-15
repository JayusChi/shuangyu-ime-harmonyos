. (Join-Path $PSScriptRoot 'helpers.ps1')
$evidence=Join-Path $evidence 'phone'
function Snap([string]$name) { Ui $name | Out-Null }
function RequireText([string]$text) { if (!($script:uiNodes | Where-Object {$_.text -ceq $text})) { throw "Missing $text" } }
function BackPage { IdTap settings-back; Snap finish-back }
function Pref([string]$key,[string]$value,[string]$name) {
  Read-Settings $name | Out-Null
  $actual=([xml](Get-Content -LiteralPath (Join-Path $evidence "$name.xml") -Raw)).preferences.string | Where-Object {$_.key -eq $key} | Select-Object -ExpandProperty '#text'
  if ($actual -cne $value) { throw "${name}: $key expected $value, got $actual" }
  "PASS $name $key=$actual"
}
function Flip([string]$name) { Tap ($script:uiNodes | Where-Object {$_.type -eq 'Toggle'} | Select-Object -First 1); Snap $name }
function ScrollDown([string]$name) {
  $scroll=$script:uiNodes | Where-Object {$_.type -eq 'Scroll' -and $_.visible -eq 'true'} | Select-Object -First 1
  $b=[regex]::Match($scroll.bounds,'\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
  if (!$b.Success) { throw 'Missing scroll bounds' }
  $x=[int](([int]$b.Groups[1].Value+[int]$b.Groups[3].Value)/2)
  Invoke-Device shell uitest uiInput swipe $x ([int]$b.Groups[4].Value-130) $x ([int]$b.Groups[2].Value+100) 500 | Out-Null
  Snap $name
}
Snap finish-start
IdTap settings-section-feedback; Snap sound-page
Flip sound-on; Pref key_sound_enabled true sound-on
TextTap '＋'; Snap volume-up; Pref key_sound_volume 17 volume-up
TextTap '−'; Snap volume-restored; Pref key_sound_volume 16 volume-restored
Flip sound-off; Pref key_sound_enabled false sound-off
Ui feedback-final -Shot | Out-Null
BackPage
IdTap settings-section-lexicon; Ui lexicon-final -Shot | Out-Null
Flip learning-off; Pref user_learning_enabled false learning-off
Flip learning-on; Pref user_learning_enabled true learning-on
IdTap settings-clear-learning; Ui clear-confirmation -Shot | Out-Null
RequireText '取消'; TextTap '取消'; Snap clear-cancelled
IdTap settings-category-manager; Ui categories-top -Shot | Out-Null
RequireText '内置词库分类'; RequireText '保存更改'; RequireText '重置默认'
Tap @($script:uiNodes | Where-Object { $_.type -eq 'Toggle' })[3]; Snap category-draft
TextTap '保存更改'; Snap category-saved
Read-Settings category-enabled | Out-Null
$ids=([xml](Get-Content -LiteralPath (Join-Path $evidence 'category-enabled.xml') -Raw)).preferences.string | Where-Object {$_.key -eq 'xiaohe_yinxing_enabled_category_ids'} | Select-Object -ExpandProperty '#text'
if ($ids -notmatch 'two-key-secondary') { throw 'Category setting was not saved' }
Tap @($script:uiNodes | Where-Object { $_.type -eq 'Toggle' })[3]; Snap category-restore-draft
TextTap '保存更改'; Snap category-restored
TextTap '重置默认'; Snap category-reset-preview
TextTap '‹'; Snap category-unsaved-confirm
RequireText '取消'; RequireText '退出'; TextTap '退出'; Snap category-back
IdTap settings-user-shortcuts; Ui shortcuts-final -Shot | Out-Null
RequireText '自定义直通'; RequireText '直通类型'; RequireText '打开网页'; RequireText '打开目录'
TextTap '打开网页'; Snap shortcut-url
if (!($script:uiNodes | Where-Object {$_.hint -eq '完整网址'})) { throw 'URL editor missing' }
TextTap '打开目录'; Snap shortcut-directory; RequireText '选择目录'
TextTap '‹'; Snap shortcut-returned
IdTap settings-user-lexicon; Snap words-final
RequireText '我的词库'; RequireText '隐藏系统词'; RequireText '第 N 位'
ScrollDown words-middle
ScrollDown words-bottom
RequireText '批量导入 / 导出'; RequireText '固定位置词库'; RequireText '添加合并来源'; RequireText '添加覆盖来源'; RequireText '立即导入'
Ui words-import-export -Shot | Out-Null
TextTap '‹'; Snap words-returned
BackPage
IdTap settings-section-appearance; Snap appearance-system-back
Key 2; Snap system-back-home; RequireText '设置'; RequireText '输入设置'
Read-Settings settings-after | Out-Null
Ui home-final -Shot | Out-Null
'PASS sound, volume, learning, clear cancellation, category save/reset-discard, shortcut types, all lexicon management entries and system back'
