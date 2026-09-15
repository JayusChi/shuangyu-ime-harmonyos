. (Join-Path $PSScriptRoot 'helpers.ps1')
$device = '127.0.0.1:5559'
$evidence = Join-Path $evidence 'computer'
function Snap([string]$name) { Ui $name | Out-Null }
function RequireText([string]$text) { if (!($script:uiNodes | Where-Object { $_.text -ceq $text })) { throw "Missing $text" } }
Snap navigation-start
RequireText '26 键小鹤音形'; RequireText '500 毫秒'
IdTap settings-section-candidates; Ui candidates -Shot | Out-Null
RequireText '固定候选字号'; RequireText '浮动候选字号'
IdTap settings-open-candidate-position; Snap candidate-position
RequireText '固定候选栏'; RequireText '输入框下方'
IdTap settings-section-lexicon; Ui lexicon -Shot | Out-Null
RequireText '学习输入习惯'; RequireText '清除学习记录'; RequireText '我的词库'; RequireText '自定义直通'
IdTap settings-category-manager; Ui categories -Shot | Out-Null
RequireText '内置词库分类'; RequireText '首选'; RequireText '保存更改'; RequireText '重置默认'
TextTap '‹'; Snap category-back
IdTap settings-user-shortcuts; Ui shortcuts -Shot | Out-Null
RequireText '自定义直通'; RequireText '直通类型'; RequireText '打开网页'; RequireText '打开目录'; RequireText '保存并立即应用'
TextTap '‹'; Snap shortcut-back
IdTap settings-user-lexicon; Ui words -Shot | Out-Null
RequireText '我的词库'; RequireText '隐藏系统词'; RequireText '固顶'; RequireText '第 N 位'
TextTap '‹'; Snap words-back
IdTap settings-section-appearance; Snap appearance
IdTap settings-customization; Ui customization -Shot | Out-Null
TextTap '‹'; Snap customization-back
IdTap settings-section-about; Snap about
IdTap settings-open-guide; Ui guide -Shot | Out-Null
RequireText '常用直通码'; RequireText '上滑手势'; RequireText '便捷输入'
IdTap settings-section-input; Ui restored -Shot | Out-Null
Read-Settings settings-after | Out-Null
'PASS split navigation, candidate controls, category manager, shortcuts, user lexicon, customization, guide; read-only settings preserved'
