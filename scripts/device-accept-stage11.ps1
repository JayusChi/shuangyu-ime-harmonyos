param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\stage11\device'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$appProfile = Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundle = [string]$appProfile.app.bundleName
$hap = (Resolve-Path (Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap')).Path
$outDir = [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir 'stage11_device_acceptance.log'

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    foreach ($line in $output) { Write-Host $line }
    if ($LASTEXITCODE -ne 0) { throw "hdc failed: $($arguments -join ' ')" }
    return $output
}

function Invoke-HdcAllowFail {
    $arguments = @($args)
    & $script:hdc -t $script:Target @arguments 2>&1 | ForEach-Object { Write-Host $_ }
}

function Dump-Layout {
    param([string]$Name)
    $remote = "/data/local/tmp/$Name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $outDir "$Name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen {
    param([string]$Name)
    $remote = "/data/local/tmp/$Name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    $local = Join-Path $outDir "$Name.png"
    Invoke-Hdc file recv $remote $local | Out-Null
}

function Assert-LayoutContains {
    param([string]$Path, [string]$Text, [string]$Message)
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -notmatch [regex]::Escape($Text)) { throw "ASSERT FAILED: $Message" }
    Write-Host "PASS: $Message"
}

function Get-Nodes {
    param([string]$Path)
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[object]
    function Walk-Node($node) {
        if ($null -ne $node -and $null -ne $node.attributes) { $script:Stage11Nodes.Add($node) | Out-Null }
        foreach ($child in @($node.children)) { Walk-Node $child }
    }
    $script:Stage11Nodes = $list
    Walk-Node $json
    return $list.ToArray()
}

function Get-Bounds {
    param($Node)
    $match = [regex]::Match([string]$Node.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { return $null }
    return [PSCustomObject]@{
        Left = [int]$match.Groups[1].Value
        Top = [int]$match.Groups[2].Value
        Right = [int]$match.Groups[3].Value
        Bottom = [int]$match.Groups[4].Value
        CX = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Find-VisibleNodeById {
    param([string]$Path, [string]$Id)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.id -eq $Id -and [string]$node.attributes.visible -eq 'true') { return $node }
    }
    return $null
}

function Find-VisibleNodeByType {
    param([string]$Path, [string]$Type)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.type -eq $Type -and [string]$node.attributes.visible -eq 'true') { return $node }
    }
    return $null
}

function Assert-TitleBelowStatusBar {
    param([string]$Path, [string]$Title)
    $titleNode = Find-TextNode $Path $Title
    $statusNode = Find-VisibleNodeById $Path 'StatusBarBox'
    if ($null -eq $titleNode -or $null -eq $statusNode) { throw "ASSERT FAILED: safe-area nodes missing for $Title" }
    $titleBounds = Get-Bounds $titleNode
    $statusBounds = Get-Bounds $statusNode
    if ($titleBounds.Top -le $statusBounds.Bottom) {
        throw "ASSERT FAILED: title overlaps status bar ($($titleBounds.Top) <= $($statusBounds.Bottom))"
    }
    Write-Host "PASS: $Title is below the top system avoid area"
}

function Assert-LastInputAboveScrollBottom {
    param([string]$Path)
    $scrollNode = Find-VisibleNodeByType $Path 'Scroll'
    $textAreaNode = Find-VisibleNodeByType $Path 'TextArea'
    if ($null -eq $scrollNode -or $null -eq $textAreaNode) { throw 'ASSERT FAILED: bottom safe-area nodes missing' }
    $scrollBounds = Get-Bounds $scrollNode
    $textAreaBounds = Get-Bounds $textAreaNode
    if ($textAreaBounds.Bottom -gt $scrollBounds.Bottom) {
        throw "ASSERT FAILED: last input overlaps bottom gesture area ($($textAreaBounds.Bottom) > $($scrollBounds.Bottom))"
    }
    Write-Host 'PASS: last Debug input remains above the bottom gesture safe area'
}

function Find-TextNode {
    param([string]$Path, [string]$Text)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.text -eq $Text -and [string]$node.attributes.visible -eq 'true') { return $node }
    }
    return $null
}

function Find-TextPrefixNode {
    param([string]$Path, [string]$Prefix)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.text -like "$Prefix*" -and [string]$node.attributes.visible -eq 'true') { return $node }
    }
    return $null
}

function Find-VisibleToggle {
    param([string]$Path)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.type -eq 'Toggle' -and [string]$node.attributes.visible -eq 'true') { return $node }
    }
    return $null
}

function Find-VisibleToggleForText {
    param([string]$Path, [string]$Text)
    $label = Find-TextNode $Path $Text
    if ($null -eq $label) { return $null }
    $labelBounds = Get-Bounds $label
    $bestToggle = $null
    $bestDistance = [int]::MaxValue
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.type -ne 'Toggle' -or [string]$node.attributes.visible -ne 'true') { continue }
        $bounds = Get-Bounds $node
        if ($null -eq $bounds) { continue }
        $distance = [Math]::Abs($bounds.CY - $labelBounds.CY)
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestToggle = $node
        }
    }
    return $bestToggle
}

function Find-HintNode {
    param([string]$Path, [string]$Hint)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.hint -eq $Hint -and [string]$node.attributes.visible -eq 'true') { return $node }
    }
    return $null
}

function Tap-Node {
    param($Node, [string]$Label)
    $bounds = Get-Bounds $Node
    if ($null -eq $bounds) { throw "Missing bounds for $Label" }
    Write-Host "tap $Label at ($($bounds.CX),$($bounds.CY))"
    Invoke-Hdc shell uitest uiInput click $bounds.CX $bounds.CY | Out-Null
    Start-Sleep -Milliseconds 500
}

function Tap-Text {
    param([string]$Path, [string]$Text, [string]$Label)
    $node = Find-TextNode $Path $Text
    if ($null -eq $node) { throw "Text node not found for $Label" }
    Tap-Node $node $Label
}

function Assert-ChoiceSelected {
    param([string]$Path, [string]$Text, [string]$Message)
    $node = Find-TextNode $Path $Text
    if ($null -eq $node) { throw "ASSERT FAILED: $Message (node missing)" }
    $background = [string]$node.attributes.backgroundColor
    if ($background -notmatch 'DCEBFF|1E4A80') { throw "ASSERT FAILED: $Message (background=$background)" }
    Write-Host "PASS: $Message"
}

function Convert-CodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

if (-not (Test-Path -LiteralPath $hdc)) { throw "hdc not found: $hdc" }
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    $hash = Get-FileHash -LiteralPath $hap -Algorithm SHA256
    Write-Host "HAP=$hap"
    Write-Host "HAP_SHA256=$($hash.Hash)"
    Invoke-Hdc list targets -v | Out-Null
    Invoke-Hdc install -r $hap | Out-Null
    Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
    Invoke-Hdc shell bm clean -n $bundle -d | Out-Null
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-HdcAllowFail shell ime -s $bundle | Out-Null
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $homeLayout = Dump-Layout 'stage11_settings_home'
    Capture-Screen 'stage11_settings_home'
    $titleText = Convert-CodePoints @(0x53CC,0x7FBD,0x8F93,0x5165,0x6CD5)
    $inputSettingsText = Convert-CodePoints @(0x8F93,0x5165,0x8BBE,0x7F6E)
    $xiaoheText = Convert-CodePoints @(0x5C0F,0x9E64,0x53CC,0x62FC)
    $followSystemText = Convert-CodePoints @(0x8DDF,0x968F,0x7CFB,0x7EDF)
    $stage10Title = Convert-CodePoints @(0x9636,0x6BB5,0x20,0x31,0x30,0x20,0xB7,0x20,0x8F93,0x5165,0x6846,0x7C7B,0x578B,0x9A8C,0x6536)
    $darkText = Convert-CodePoints @(0x6DF1,0x8272)
    $lightText = Convert-CodePoints @(0x6D45,0x8272)
    $compactText = Convert-CodePoints @(0x7D27,0x51D1)
    $standardText = Convert-CodePoints @(0x6807,0x51C6)
    $tallText = Convert-CodePoints @(0x8F83,0x9AD8)
    $largeText = Convert-CodePoints @(0x5927)
    $strongText = Convert-CodePoints @(0x5F3A)
    $clearModelText = Convert-CodePoints @(0x6E05,0x7A7A,0x7528,0x6237,0x8BCD,0x9891)
    $learningText = Convert-CodePoints @(0x7528,0x6237,0x5B66,0x4E60)
    $keySoundText = Convert-CodePoints @(0x6309,0x952E,0x97F3)
    $cancelText = Convert-CodePoints @(0x53D6,0x6D88)
    $debugText = Convert-CodePoints @(0x8C03,0x8BD5,0x4E0E,0x9A8C,0x6536)
    $normalHint = Convert-CodePoints @(0x666E,0x901A,0x6587,0x672C,0xFF1A,0x9ED8,0x8BA4,0x4E2D,0x6587)
    $firstCandidateText = Convert-CodePoints @(0x4F60)
    $hideText = Convert-CodePoints @(0x9690,0x85CF)
    $modelText = Convert-CodePoints @(0x6A21,0x578B)
    $clearText = Convert-CodePoints @(0x6E05,0x7A7A)
    $initialHomeContent = Get-Content -LiteralPath $homeLayout -Raw -Encoding UTF8
    if ($initialHomeContent -match '"pagePath":"pages/DebugIndex"') {
        $settingsEntry = Find-VisibleNodeByType $homeLayout 'Button'
        if ($null -eq $settingsEntry) {
            throw 'ASSERT FAILED: DebugIndex settings entry is missing'
        }
        Tap-Node $settingsEntry 'open formal settings from DebugIndex'
        $homeLayout = Dump-Layout 'stage11_settings_home_after_debug_index'
        Capture-Screen 'stage11_settings_home_after_debug_index'
    }
    Assert-LayoutContains $homeLayout $titleText 'formal default page is settings home'
    Assert-TitleBelowStatusBar $homeLayout $titleText
    Assert-LayoutContains $homeLayout $inputSettingsText 'input settings group is visible'
    Assert-LayoutContains $homeLayout $xiaoheText 'only the installed xiaohe scheme is listed'
    Assert-LayoutContains $homeLayout $followSystemText 'theme choices are available'
    if ((Get-Content -LiteralPath $homeLayout -Raw -Encoding UTF8) -match [regex]::Escape($stage10Title)) {
        throw 'Stage 10 acceptance page must not be the default page.'
    }

    $learningToggle = Find-VisibleToggleForText $homeLayout $learningText
    if ($null -eq $learningToggle -or [string]$learningToggle.attributes.checked -ne 'true') {
        throw 'User learning toggle default is not enabled.'
    }
    Tap-Node $learningToggle 'disable user learning'
    $learningOff = Dump-Layout 'stage11_learning_off'
    $learningToggle = Find-VisibleToggleForText $learningOff $learningText
    if ($null -eq $learningToggle -or [string]$learningToggle.attributes.checked -ne 'false') {
        throw 'User learning toggle did not turn off.'
    }
    Write-Host 'PASS: user learning setting changes immediately'

    Tap-Text $learningOff $darkText 'select dark theme'
    $darkLayout = Dump-Layout 'stage11_theme_dark'
    Capture-Screen 'stage11_theme_dark'
    Assert-ChoiceSelected $darkLayout $darkText 'dark theme is selected'
    Tap-Text $darkLayout $lightText 'select light theme'
    $lightLayout = Dump-Layout 'stage11_theme_light'
    Capture-Screen 'stage11_theme_light'
    Assert-ChoiceSelected $lightLayout $lightText 'light theme is selected'
    Tap-Text $lightLayout $darkText 'select persisted dark theme'
    $choiceLayout = Dump-Layout 'stage11_theme_dark_final'

    Tap-Text $choiceLayout $compactText 'select compact height'
    $compactLayout = Dump-Layout 'stage11_height_compact'
    Assert-ChoiceSelected $compactLayout $compactText 'compact height setting is selected'
    Tap-Text $compactLayout $standardText 'select standard height'
    $standardLayout = Dump-Layout 'stage11_height_standard'
    Assert-ChoiceSelected $standardLayout $standardText 'standard height setting is selected'
    Tap-Text $standardLayout $tallText 'select tall height'
    $tallLayout = Dump-Layout 'stage11_height_tall'
    Assert-ChoiceSelected $tallLayout $tallText 'tall height setting is selected'

    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 700
    $feedbackPage = Dump-Layout 'stage11_feedback_page'
    Tap-Text $feedbackPage $largeText 'select large candidate font'
    $largeLayout = Dump-Layout 'stage11_candidate_large'
    Assert-ChoiceSelected $largeLayout $largeText 'large candidate font setting is selected'
    Tap-Text $largeLayout $strongText 'select strong haptic'
    $strongLayout = Dump-Layout 'stage11_haptic_strong'
    Assert-ChoiceSelected $strongLayout $strongText 'strong haptic setting is selected'
    $soundToggle = Find-VisibleToggleForText $strongLayout $keySoundText
    if ($null -eq $soundToggle) { throw 'Key sound toggle not found.' }
    if ([string]$soundToggle.attributes.checked -ne 'true') {
        Tap-Node $soundToggle 'enable key sound'
    }
    $soundOn = Dump-Layout 'stage11_sound_on'
    $soundToggle = Find-VisibleToggleForText $soundOn $keySoundText
    if ($null -eq $soundToggle -or [string]$soundToggle.attributes.checked -ne 'true') {
        throw 'Key sound toggle did not turn on.'
    }
    Write-Host 'PASS: key sound setting changes immediately'

    Tap-Text $soundOn $clearModelText 'open clear user model confirmation'
    $clearDialog = Dump-Layout 'stage11_clear_confirmation'
    Assert-LayoutContains $clearDialog $cancelText 'clear user model requires confirmation'
    Tap-Text $clearDialog $cancelText 'cancel clear user model'

    Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $restart = Dump-Layout 'stage11_settings_restart'
    if ((Get-Content -LiteralPath $restart -Raw -Encoding UTF8) -match '"pagePath":"pages/DebugIndex"') {
        $settingsEntry = Find-VisibleNodeByType $restart 'Button'
        if ($null -eq $settingsEntry) {
            throw 'ASSERT FAILED: DebugIndex settings entry is missing after process restart'
        }
        Tap-Node $settingsEntry 'reopen formal settings after process restart'
        $restart = Dump-Layout 'stage11_settings_restart_after_debug_index'
    }
    Assert-LayoutContains $restart $titleText 'settings home survives process restart'
    Assert-ChoiceSelected $restart $darkText 'dark theme persists after restart'
    Assert-ChoiceSelected $restart $tallText 'keyboard height persists after restart'
    $restartLearningToggle = Find-VisibleToggleForText $restart $learningText
    if ($null -eq $restartLearningToggle -or [string]$restartLearningToggle.attributes.checked -ne 'false') {
        throw 'User learning setting did not persist after restart.'
    }
    Write-Host 'PASS: user learning setting persists after restart'
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 700
    $restartFeedback = Dump-Layout 'stage11_settings_restart_feedback'
    Assert-ChoiceSelected $restartFeedback $largeText 'candidate font persists after restart'
    Assert-ChoiceSelected $restartFeedback $strongText 'haptic level persists after restart'
    $restartSoundToggle = Find-VisibleToggleForText $restartFeedback $keySoundText
    if ($null -eq $restartSoundToggle -or [string]$restartSoundToggle.attributes.checked -ne 'true') {
        throw 'Key sound setting did not persist after restart.'
    }
    Write-Host 'PASS: key sound setting persists after restart'

    for ($index = 0; $index -lt 4; $index++) {
        Invoke-Hdc shell uitest uiInput swipe 660 500 660 2450 900 | Out-Null
        Start-Sleep -Milliseconds 250
    }
    $topAgain = Dump-Layout 'stage11_before_clear_top'
    $learningToggle = Find-VisibleToggleForText $topAgain $learningText
    if ($null -eq $learningToggle) { throw 'User learning toggle not found before clear workflow.' }
    if ([string]$learningToggle.attributes.checked -ne 'true') {
        Tap-Node $learningToggle 'enable learning for clear workflow'
    }
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 600
    $debugEntryPage = Dump-Layout 'stage11_clear_debug_entry'
    Tap-Text $debugEntryPage $debugText 'open debug page for user model clear workflow'
    Start-Sleep -Milliseconds 700
    $debugPage = Dump-Layout 'stage11_clear_debug_page'
    Capture-Screen 'stage11_debug_fixed_light_from_dark_settings'
    Assert-TitleBelowStatusBar $debugPage $stage10Title
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 450 1000 | Out-Null
    Start-Sleep -Milliseconds 700
    $debugBottom = Dump-Layout 'stage11_debug_safe_bottom'
    Capture-Screen 'stage11_debug_safe_bottom'
    Assert-LastInputAboveScrollBottom $debugBottom
    Invoke-Hdc shell uitest uiInput swipe 660 450 660 2450 1000 | Out-Null
    Start-Sleep -Milliseconds 700
    $debugPage = Dump-Layout 'stage11_clear_debug_page_top_restored'
    $normalInput = Find-HintNode $debugPage $normalHint
    if ($null -eq $normalInput) { throw 'Normal input field not found for clear workflow.' }
    Tap-Node $normalInput 'focus normal input for clear workflow'
    Start-Sleep -Milliseconds 800
    $keyboard = Dump-Layout 'stage11_clear_keyboard'
    if ($null -ne (Find-TextNode $keyboard '回归') -or $null -ne (Find-TextPrefixNode $keyboard $modelText)) {
        throw 'Formal keyboard exposes regression or model-debug controls.'
    }
    Write-Host 'PASS: formal keyboard excludes interactive debug controls'
    Tap-Text $keyboard 'n' 'type n for user model clear workflow'
    $keyboardN = Dump-Layout 'stage11_clear_keyboard_n'
    Tap-Text $keyboardN 'i' 'type i for user model clear workflow'
    $candidateLayout = Dump-Layout 'stage11_clear_candidate'
    Tap-Text $candidateLayout $firstCandidateText 'commit candidate before clear'
    $committedLayout = Dump-Layout 'stage11_clear_committed'
    Tap-Text $committedLayout $hideText 'hide keyboard before clear'
    Invoke-Hdc shell uitest uiInput keyEvent Back | Out-Null
    Start-Sleep -Milliseconds 700
    Capture-Screen 'stage11_return_dark_after_debug'
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 600
    $clearPage = Dump-Layout 'stage11_clear_action_page'
    Tap-Text $clearPage $clearModelText 'open clear confirmation for real clear'
    $realClearDialog = Dump-Layout 'stage11_real_clear_confirmation'
    Tap-Text $realClearDialog $clearText 'confirm real user model clear'
    Start-Sleep -Milliseconds 700
    $afterClearPage = Dump-Layout 'stage11_after_clear_settings'
    Tap-Text $afterClearPage $debugText 'reopen debug page after clear'
    Start-Sleep -Milliseconds 700
    $debugAfterClear = Dump-Layout 'stage11_debug_after_clear'
    $normalInput = Find-HintNode $debugAfterClear $normalHint
    if ($null -eq $normalInput) { throw 'Normal input field not found after clear.' }
    Tap-Node $normalInput 'focus normal input after clear'
    Start-Sleep -Milliseconds 800
    $keyboardAfterClear = Dump-Layout 'stage11_keyboard_after_clear'
    if ($null -ne (Find-TextNode $keyboardAfterClear '回归') -or $null -ne (Find-TextPrefixNode $keyboardAfterClear $modelText)) {
        throw 'Formal keyboard exposes debug controls after model clear.'
    }
    Tap-Text $keyboardAfterClear 'n' 'type n after model clear'
    $keyboardAfterClearN = Dump-Layout 'stage11_keyboard_after_clear_n'
    Tap-Text $keyboardAfterClearN 'i' 'type i after model clear'
    $candidateAfterClear = Dump-Layout 'stage11_candidate_after_clear'
    Assert-LayoutContains $candidateAfterClear $firstCandidateText 'production candidates remain available after model clear'

    Write-Host 'PHYSICAL_HAPTIC_RESULT=NOT_TESTED_REQUIRES_ARM64_DEVICE'
    Write-Host 'PHYSICAL_KEY_SOUND_RESULT=NOT_OBJECTIVELY_CAPTURED'
    Write-Host 'STAGE11_DEVICE_ACCEPTANCE_RESULT=PASS'
} finally {
    Stop-Transcript | Out-Null
}
