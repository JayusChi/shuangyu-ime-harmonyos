param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$HapPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$appProfile = Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundle = [string]$appProfile.app.bundleName
$outDir = Join-Path $repoRoot 'docs\evidence\2026-07-23-stage-11.6.6-actions\editor-device'
New-Item -ItemType Directory -Force $outDir | Out-Null
$logPath = Join-Path $outDir 'editor-device-acceptance.log'
if ([string]::IsNullOrWhiteSpace($HapPath)) {
    $HapPath = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
}
$HapPath = [IO.Path]::GetFullPath($HapPath)
$script:NormalInputHint = -join ([char[]]@(0x666E, 0x901A, 0x6587, 0x672C, 0xFF1A, 0x9ED8, 0x8BA4, 0x4E2D, 0x6587))
$script:DebugAcceptanceLabel = -join ([char[]]@(0x8C03, 0x8BD5, 0x4E0E, 0x9A8C, 0x6536))
$script:ReturnLabel = -join ([char[]]@(0x8FD4, 0x56DE))
$script:ChineseLabel = [string][char]0x4E2D
$script:EnglishLabel = [string][char]0x82F1
$script:DateCandidateLabel = (-join ([char[]]@(0x65E5, 0x671F))) + ' ISO'
$script:EmojiCandidateLabel = 'Emoji ' + (-join ([char[]]@(0x8FB9, 0x754C)))
$script:EmojiCluster = -join ([char[]]@(0xD83E, 0xDDD1, 0x200D, 0xD83D, 0xDCBB))

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if ($exitCode -ne 0) { throw "hdc failed ($exitCode): $($arguments -join ' ')" }
    return $output
}

function Invoke-HdcQuiet {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "hdc failed ($exitCode): $($arguments -join ' ')" }
    return $output
}

function Invoke-HdcAllowFail {
    $arguments = @($args)
    & $script:hdc -t $script:Target @arguments 2>&1 | ForEach-Object { Write-Host $_ }
}

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERT FAILED: $message" }
    Write-Host "PASS: $message"
}

function Get-Bounds($node) {
    $match = [regex]::Match([string]$node.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        X1 = [int]$match.Groups[1].Value
        Y1 = [int]$match.Groups[2].Value
        X2 = [int]$match.Groups[3].Value
        Y2 = [int]$match.Groups[4].Value
        CX = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Get-Nodes([string]$path) {
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) {
            $script:Stage1166EditorNodes.Add($node) | Out-Null
        }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:Stage1166EditorNodes = $list
    Visit $json
    return $list.ToArray()
}

function Find-Text([string]$path, [string]$text, [int]$minY = 0, [int]$maxY = 3000) {
    $matches = @()
    foreach ($node in Get-Nodes $path) {
        if ([string]$node.attributes.text -ne $text -or [string]$node.attributes.visible -ne 'true') {
            continue
        }
        $bounds = Get-Bounds $node
        if ($null -ne $bounds -and $bounds.Y1 -ge $minY -and $bounds.Y2 -le $maxY) {
            $matches += [pscustomobject]@{ Node = $node; Bounds = $bounds }
        }
    }
    return $matches | Sort-Object { $_.Bounds.Y1 }, { $_.Bounds.X1 } | Select-Object -First 1
}

function Find-Hint([string]$path, [string]$hint) {
    foreach ($node in Get-Nodes $path) {
        if ([string]$node.attributes.hint -eq $hint -and [string]$node.attributes.visible -eq 'true') {
            $bounds = Get-Bounds $node
            if ($null -ne $bounds) {
                return [pscustomobject]@{ Node = $node; Bounds = $bounds }
            }
        }
    }
    return $null
}

function Dump-Layout([string]$name) {
    $remote = "/data/local/tmp/$name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $outDir "$name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen([string]$name) {
    $remote = "/data/local/tmp/$name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    $local = Join-Path $outDir "$name.png"
    Invoke-Hdc file recv $remote $local | Out-Null
}

function Tap-Node($item, [string]$label) {
    if ($null -eq $item) { throw "node not found: $label" }
    Write-Host "tap $label at ($($item.Bounds.CX),$($item.Bounds.CY))"
    Invoke-Hdc shell uitest uiInput click $item.Bounds.CX $item.Bounds.CY | Out-Null
    Start-Sleep -Milliseconds 300
}

function Tap-Text([string]$layout, [string]$text, [int]$minY, [int]$maxY, [string]$label) {
    Tap-Node (Find-Text $layout $text $minY $maxY) $label
}

function Assert-InputText([string]$layout, [string]$expected, [string]$message) {
    $input = Find-Hint $layout $script:NormalInputHint
    Assert-True ($null -ne $input) "$message input remains visible"
    $actual = [string]$input.Node.attributes.text
    Assert-True ($actual -ceq $expected) "$message exact text: $actual"
}

function Open-ExternalEditor {
    Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-HdcAllowFail shell ime -s $bundle | Out-Null
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $debugEntry = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        $page = Dump-Layout "editor_settings_$attempt"
        $debugEntry = Find-Text $page $script:DebugAcceptanceLabel
        if ($null -ne $debugEntry) { break }
        Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
        Start-Sleep -Milliseconds 400
    }
    Tap-Node $debugEntry 'open external editor acceptance page'
    Start-Sleep -Seconds 1
    for ($i = 0; $i -lt 5; $i++) {
        Invoke-Hdc shell uitest uiInput swipe 660 500 660 2500 1000 | Out-Null
        Start-Sleep -Milliseconds 250
    }
    $input = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $page = Dump-Layout "editor_page_$attempt"
        $input = Find-Hint $page $script:NormalInputHint
        if ($null -ne $input) { break }
        Invoke-Hdc shell uitest uiInput swipe 660 500 660 2500 1000 | Out-Null
    }
    Tap-Node $input 'focus external TextInput'
    Start-Sleep -Seconds 1
    return Dump-Layout 'editor_keyboard_initial'
}

function Enter-GuideCode([string]$keyboardLayout, [string]$code, [string]$prefix) {
    Tap-Text $keyboardLayout '#+=' 1500 1950 "open symbols for $prefix"
    $symbols = Dump-Layout "${prefix}_symbols"
    Tap-Text $symbols ';' 800 1800 "enter guide prefix for $prefix"
    $guidedSymbols = Dump-Layout "${prefix}_guide_prefix"
    Tap-Text $guidedSymbols $script:ReturnLabel 1500 1950 "return to Chinese letters for $prefix"
    $letters = Dump-Layout "${prefix}_letters"
    foreach ($key in $code.ToCharArray()) {
        Tap-Text $letters ([string]$key) 800 1800 "type $key for $prefix"
    }
    Start-Sleep -Milliseconds 500
    return Dump-Layout "${prefix}_candidates"
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw "Debug HAP not found: $HapPath" }

Start-Transcript -Path $logPath -Force | Out-Null
try {
    $targets = & $hdc list targets 2>&1
    Assert-True (($targets -join "`n") -match [regex]::Escape($Target)) 'target is connected'
    $hap = Get-Item -LiteralPath $HapPath
    $hapHash = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-Hdc install -r $HapPath | Out-Null
    Invoke-Hdc shell hilog -r | Out-Null
    $deviceDate = ((Invoke-Hdc shell date '+%Y-%m-%d') | Select-Object -Last 1).Trim()
    Assert-True ($deviceDate -match '^\d{4}-\d{2}-\d{2}$') 'device date is ISO-readable'

    $initial = Open-ExternalEditor
    Assert-True ($null -ne (Find-Text $initial $script:ChineseLabel 1500 1950)) 'fixture IME starts in Chinese input state'

    $dateCandidates = Enter-GuideCode $initial 'di' 'date'
    Assert-True ($null -ne (Find-Text $dateCandidates $script:DateCandidateLabel 700 1200)) 'date action candidate crossed Rust/C++/ArkTS'
    Tap-Text $dateCandidates $script:DateCandidateLabel 700 1200 'execute date action'
    Start-Sleep -Milliseconds 600
    $dateCommitted = Dump-Layout 'date_committed'
    Assert-InputText $dateCommitted $deviceDate 'date action committed to external editor'
    Capture-Screen 'date_committed'

    $emojiCandidates = Enter-GuideCode $dateCommitted 'pe' 'emoji_pair'
    Assert-True ($null -ne (Find-Text $emojiCandidates $script:EmojiCandidateLabel 700 1200)) 'non-BMP pair action candidate is visible'
    Tap-Text $emojiCandidates $script:EmojiCandidateLabel 700 1200 'execute non-BMP pair action'
    Start-Sleep -Milliseconds 600
    $pairCommitted = Dump-Layout 'emoji_pair_committed'
    $emojiPair = $script:EmojiCluster + $script:EmojiCluster
    Assert-InputText $pairCommitted "$deviceDate$emojiPair" 'pair action inserted exactly once'
    Capture-Screen 'emoji_pair_committed'

    $probeKey = if ($null -ne (Find-Text $pairCommitted 'x' 800 1800)) { 'x' } else { 'X' }
    Tap-Text $pairCommitted $probeKey 800 1800 'insert caret probe'
    Start-Sleep -Milliseconds 500
    $caretVerified = Dump-Layout 'emoji_pair_caret_verified'
    $expectedCaretText = "$deviceDate" + $script:EmojiCluster + 'x' + $script:EmojiCluster
    Assert-InputText $caretVerified $expectedCaretText 'UTF-16 offset positioned caret between emoji clusters'
    Capture-Screen 'emoji_pair_caret_verified'

    $hilog = Invoke-HdcQuiet shell hilog -x
    $pairLog = @($hilog | Where-Object { $_ -match 'pair cursor positioned:' })
    $pairLog | Set-Content -LiteralPath (Join-Path $outDir 'pair-cursor-hilog.txt') -Encoding UTF8
    Assert-True ($pairLog.Count -gt 0) 'IME logged successful editor cursor positioning'

    $report = [ordered]@{
        capturedAt = (Get-Date).ToString('o')
        serial = $Target
        debugHapPath = $HapPath
        debugHapBytes = $hap.Length
        debugHapSha256 = $hapHash
        deviceDate = $deviceDate
        dateCommittedText = $deviceDate
        pairInsertedText = "$deviceDate$emojiPair"
        caretProbeText = $expectedCaretText
        utf16PairOffset = 5
        pairCursorLog = ($pairLog -join "`n")
        assertions = @(
            'DATE_ACTION_EXTERNAL_EDITOR_COMMIT_PASS',
            'PAIR_INSERT_EXACTLY_ONCE_PASS',
            'UTF16_NON_BMP_CURSOR_POSITION_PASS'
        )
        result = 'PASS'
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir 'editor-device-acceptance.json') -Encoding UTF8
    Write-Host 'STAGE11_6_6_EDITOR_DEVICE_ACTION_RESULT=PASS'
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host 'STAGE11_6_6_EDITOR_DEVICE_ACTION_RESULT=FAIL'
    Stop-Transcript | Out-Null
    exit 1
}
