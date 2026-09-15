. (Join-Path $PSScriptRoot 'helpers.ps1')
$evidence = Join-Path $evidence 'phone'
function Snap([string]$name) { Ui $name | Out-Null }
function RequireText([string]$text) { if (!($script:uiNodes | Where-Object { $_.text -ceq $text })) { throw "Missing $text" } }
function BackPage { IdTap settings-back; Snap back-display }
function Pref([string]$key,[string]$value,[string]$name) {
  Read-Settings $name | Out-Null
  $actual = ([xml](Get-Content -LiteralPath (Join-Path $evidence "$name.xml") -Raw)).preferences.string |
    Where-Object { $_.key -eq $key } | Select-Object -ExpandProperty '#text'
  if ($actual -cne $value) { throw "${name}: $key expected $value, got $actual" }
  "PASS $name $key=$actual"
}
function Flip([string]$label,[string]$name) {
  $title=$script:uiNodes | Where-Object {$_.text -ceq $label} | Select-Object -First 1
  if (!$title) { throw "Missing switch $label" }
  $top=[int]([regex]::Match($title.bounds,'\[\d+,(\d+)\]').Groups[1].Value)
  Tap ($script:uiNodes | Where-Object {$_.type -eq 'Toggle'} | Where-Object {
    $y=[int]([regex]::Match($_.bounds,'\[\d+,(\d+)\]').Groups[1].Value)
    $y -ge $top-80 -and $y -le $top+150
  } | Select-Object -First 1)
  Snap $name
}
function Step([int]$index,[string]$symbol,[string]$name) {
  Tap @($script:uiNodes | Where-Object {$_.text -ceq $symbol})[$index]
  Snap $name
}
Snap display-start
IdTap settings-section-candidates; Ui candidates-final -Shot | Out-Null
Step 0 '＋' fixed-up; RequireText '16 号'; Pref candidate_font_size 16 fixed-up
Pref floating_candidate_font_size 17 fixed-independent
Step 0 '−' fixed-restored; Pref candidate_font_size 15 fixed-restored
Step 1 '＋' floating-up; RequireText '18 号'; Pref floating_candidate_font_size 18 floating-up
Pref candidate_font_size 15 floating-independent
Step 1 '−' floating-restored; Pref floating_candidate_font_size 17 floating-restored
IdTap settings-open-candidate-position; Snap positions
IdTap settings-option-floating; Snap position-floating; Pref candidate_presentation_mode floating position-floating
BackPage; Ui floating-preview -Shot | Out-Null
IdTap settings-open-candidate-position; Snap positions-restore
IdTap settings-option-bar; Snap position-bar; Pref candidate_presentation_mode bar position-bar
BackPage; BackPage
RequireText '固定候选栏 · 15 号'
IdTap settings-section-appearance; Snap appearance-final
Step 0 '＋' height-up; RequireText '1.05×'
Step 0 '−' height-restored; Pref keyboard_height_mode standard height-restored
Flip '底部工具栏' lift-off; Pref keyboard_lift_layer_enabled false lift-off
Flip '底部工具栏' lift-on; Pref keyboard_lift_layer_enabled true lift-on
IdTap settings-open-theme; Snap themes
IdTap settings-option-dark; Ui dark-options -Shot | Out-Null; Pref theme_mode dark dark-theme
BackPage; BackPage
RequireText '深色 · 高度 1.00×'; Ui dark-home -Shot | Out-Null
IdTap settings-section-appearance; Snap appearance-dark
IdTap settings-open-theme; Snap themes-dark
IdTap settings-option-light; Snap light-options; Pref theme_mode light light-theme
IdTap settings-option-followSystem; Snap theme-restored; Pref theme_mode followSystem theme-restored
BackPage; BackPage
IdTap settings-section-feedback; Snap feedback
IdTap settings-open-haptic; Snap haptic-options
foreach($level in @('off','medium','strong','light')) {
  IdTap "settings-option-$level"; Snap "haptic-$level"; Pref haptic_level $level "haptic-$level"
}
BackPage
IdTap settings-open-long-press; Snap long-press-options
foreach($duration in @('200','500','700','300')) {
  IdTap "settings-option-$duration"; Snap "long-press-$duration"; Pref long_press_duration_ms $duration "long-press-$duration"
}
BackPage
Flip '按键音' sound-on; Pref key_sound_enabled true sound-on
Step 0 '＋' volume-up; Pref key_sound_volume 17 volume-up
Step 0 '−' volume-restored; Pref key_sound_volume 16 volume-restored
Flip '按键音' sound-off; Pref key_sound_enabled false sound-off
Ui feedback-final -Shot | Out-Null
BackPage
IdTap settings-section-lexicon; Ui lexicon-final -Shot | Out-Null
Flip '学习输入习惯' learning-off; Pref user_learning_enabled false learning-off
Flip '学习输入习惯' learning-on; Pref user_learning_enabled true learning-on
IdTap settings-clear-learning; Ui clear-confirmation -Shot | Out-Null
RequireText '取消'; TextTap '取消'; Snap clear-cancelled
Read-Settings display-restored | Out-Null
'PASS candidate position, independent fonts, height, toolbar, three themes, haptic, long press, sound/volume, learning switch and clear cancellation'


