param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$HapPath = '',
    [string]$EvidenceDir = 'docs\evidence\2026-07-27-stage-11.6.7-revalidation\editor-device',
    [ValidateRange(1, 2)]
    [int]$StartRound = 1,
    [ValidateRange(1, 2)]
    [int]$EndRound = 2
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($env:STAGE1167_SCRIPT_ROOT) { $env:STAGE1167_SCRIPT_ROOT } else { $PSScriptRoot }
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$script:hdc = $hdc
$script:Target = $Target
$bundle = [string]((Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 |
    ConvertFrom-Json).app.bundleName)
$outDir = if ([IO.Path]::IsPathRooted($EvidenceDir)) {
    [IO.Path]::GetFullPath($EvidenceDir)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}
if (-not $outDir.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write device evidence outside the repository: $outDir"
}
New-Item -ItemType Directory -Force $outDir | Out-Null
$logPath = Join-Path $outDir 'editor-a-n-two-rounds.log'
if ([string]::IsNullOrWhiteSpace($HapPath)) {
    $HapPath = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
}
$HapPath = [IO.Path]::GetFullPath($HapPath)
$script:EditorPageButton = '11.6.7 编辑器 A-N'
$script:AllModeButton = '音形全分类'
$script:CoreModeButton = '音形仅 core'
$script:XiaoheModeButton = '切回 xiaohe'
$script:CommandEvent = "$bundle.event.DEBUG_STAGE1167_COMMAND"
$script:SpaceLabel = '空格'
$script:SymbolsLabel = '符/123'
$script:ReturnLabel = '返回'
$script:DoneLabel = '完成'
$script:ScreenWidth = 1320
$script:ScreenHeight = 2856

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if ($exitCode -ne 0) { throw "hdc failed ($exitCode): $($arguments -join ' ')" }
    return $output
}

function Invoke-HdcAllowFail {
    $arguments = @($args)
    return (& $script:hdc -t $script:Target @arguments 2>&1)
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
            $script:Stage1167EditorNodes.Add($node) | Out-Null
        }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:Stage1167EditorNodes = $list
    Visit $json
    return $list.ToArray()
}

function Find-Text([string]$path, [string]$text, [int]$minY = 0, [int]$maxY = $script:ScreenHeight) {
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

function Find-KeyboardText([string]$path, [string]$text) {
    $matches = @()
    $keyboardMinY = [int]($script:ScreenHeight * 0.45)
    foreach ($node in Get-Nodes $path) {
        if ([string]$node.attributes.text -ne $text -or [string]$node.attributes.visible -ne 'true') {
            continue
        }
        $bounds = Get-Bounds $node
        if ($null -ne $bounds -and $bounds.Y1 -ge $keyboardMinY -and $bounds.Y2 -le $script:ScreenHeight) {
            $matches += [pscustomobject]@{ Node = $node; Bounds = $bounds }
        }
    }
    return $matches | Sort-Object { $_.Bounds.Y1 } -Descending | Select-Object -First 1
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

function Dump-Layout([string]$roundDir, [string]$name) {
    $remote = "/data/local/tmp/stage1167_$name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $roundDir "$name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen([string]$roundDir, [string]$name) {
    $remote = "/data/local/tmp/stage1167_$name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    Invoke-Hdc file recv $remote (Join-Path $roundDir "$name.png") | Out-Null
}

function Tap-Node($item, [string]$label) {
    if ($null -eq $item) { throw "node not found: $label" }
    Invoke-Hdc shell uitest uiInput click $item.Bounds.CX $item.Bounds.CY | Out-Null
    Start-Sleep -Milliseconds 360
}

function Open-EditorPage([string]$roundDir, [int]$round) {
    Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-HdcAllowFail shell ime -s $bundle | Out-Null
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Milliseconds 900
    $layout = Dump-Layout $roundDir "round_${round}_index"
    Tap-Node (Find-Text $layout $script:EditorPageButton) 'open stage 11.6.7 editor page'
    Start-Sleep -Milliseconds 500
    return Dump-Layout $roundDir "round_${round}_editor"
}

function Find-FieldVisible([string]$roundDir, [string]$hint, [string]$prefix) {
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        $layout = Dump-Layout $roundDir "${prefix}_field_$attempt"
        $field = Find-Hint $layout $hint
        if ($null -ne $field -and $field.Bounds.Y1 -ge 0 -and
            $field.Bounds.Y2 -le ($script:ScreenHeight - 80)) {
            return [pscustomobject]@{ Layout = $layout; Field = $field }
        }
        $centerX = [int]($script:ScreenWidth / 2)
        # Scroll only inside the application viewport. Starting a gesture in
        # the IME panel either types a key or is ignored; sending Back/Done is
        # also unsafe because Back exits some emulator apps and Done commits.
        $fromY = [int]($script:ScreenHeight * 0.48)
        $toY = [int]($script:ScreenHeight * 0.22)
        Invoke-Hdc shell uitest uiInput swipe $centerX $fromY $centerX $toY 500 | Out-Null
        Start-Sleep -Milliseconds 180
    }
    throw "field not visible after scrolling: $hint"
}

function Scroll-To-Top() {
    param([string]$roundDir, [string]$prefix)
    $centerX = [int]($script:ScreenWidth / 2)
    $fromY = [int]($script:ScreenHeight * 0.22)
    $toY = [int]($script:ScreenHeight * 0.48)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Invoke-Hdc shell uitest uiInput swipe $centerX $fromY $centerX $toY 500 | Out-Null
        Start-Sleep -Milliseconds 180
    }
}

function Focus-Field([string]$roundDir, [string]$caseId, [string]$prefix) {
    $found = Find-FieldVisible $roundDir "11.6.7-$caseId" $prefix
    Tap-Node $found.Field "focus case $caseId"
    Start-Sleep -Milliseconds 800
}

function Tap-KeyboardText([string]$roundDir, [string]$text, [string]$prefix) {
    $layout = Dump-Layout $roundDir "${prefix}_keyboard"
    $item = Find-KeyboardText $layout $text
    Tap-Node $item "keyboard $text"
}

function Dismiss-Keyboard([string]$roundDir, [string]$prefix) {
    $layout = Dump-Layout $roundDir "${prefix}_keyboard"
    $done = Find-KeyboardText $layout $script:DoneLabel
    if ($null -ne $done) {
        Tap-Node $done 'keyboard done'
        Start-Sleep -Milliseconds 300
    }
}

function Enter-Code([string]$roundDir, [string]$code, [string]$prefix) {
    $previous = ''
    foreach ($character in $code.ToCharArray()) {
        $current = ([string]$character).ToUpperInvariant()
        if ($current -eq $previous -and $current -eq 'U') {
            # UITest coalesces two immediate clicks at the same coordinate on this
            # emulator. KEYCODE_U exercises the real IME key event for the second U.
            Invoke-Hdc shell uitest uiInput keyEvent 2037 | Out-Null
            Start-Sleep -Milliseconds 360
        } else {
            Tap-KeyboardText $roundDir $current "${prefix}_$character"
        }
        $previous = $current
    }
    Start-Sleep -Milliseconds 220
}

function Commit-First([string]$roundDir, [string]$prefix) {
    Tap-KeyboardText $roundDir $script:SpaceLabel "${prefix}_space"
    Start-Sleep -Milliseconds 240
}

function Assert-FieldText([string]$roundDir, [string]$caseId, [string]$expected, [string]$message) {
    $found = Find-FieldVisible $roundDir "11.6.7-$caseId" "assert_$caseId"
    $actual = [string]$found.Field.Node.attributes.text
    Assert-True ($actual -ceq $expected) "$message exact final editor text='$actual'"
}

function Tap-Mode([string]$roundDir, [string]$label, [string]$prefix) {
    if ($label -ceq $script:AllModeButton) {
        $command = 'ALL_CATEGORIES'
    } elseif ($label -ceq $script:CoreModeButton) {
        $command = 'CORE_ONLY'
    } elseif ($label -ceq $script:XiaoheModeButton) {
        $command = 'XIAOHE'
    } else {
        throw "unsupported mode command: $label"
    }
    Invoke-Hdc shell cem publish -e $script:CommandEvent -d $command | Out-Null
    Start-Sleep -Milliseconds 900
    Dump-Layout $roundDir "${prefix}_mode" | Out-Null
}

function Wait-VisibleText([string]$roundDir, [string]$text, [string]$prefix) {
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $layout = Dump-Layout $roundDir "${prefix}_wait_$attempt"
        if ($null -ne (Find-Text $layout $text 100 ([int]($script:ScreenHeight * 0.58)))) {
            return
        }
        Start-Sleep -Milliseconds 200
    }
    throw "timed out waiting for text: $text"
}

function Enter-Guide([string]$roundDir, [string]$prefix) {
    Tap-KeyboardText $roundDir $script:SymbolsLabel "${prefix}_symbols"
    Tap-KeyboardText $roundDir '#+=' "${prefix}_symbol_page"
    Tap-KeyboardText $roundDir ';' "${prefix}_semicolon"
    Tap-KeyboardText $roundDir $script:ReturnLabel "${prefix}_return"
    Tap-KeyboardText $roundDir 'G' "${prefix}_g"
}

function Run-Round([int]$round) {
    $roundDir = Join-Path $outDir "round-$round"
    if (Test-Path -LiteralPath $roundDir) {
        Remove-Item -LiteralPath $roundDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force $roundDir | Out-Null
    Open-EditorPage $roundDir $round | Out-Null

    # A-N are independent cases. Run the empty-result user deletion first so
    # a sibling TextInput cannot contribute a platform preview backing value.
    Focus-Field $roundDir 'G' 'g'
    Tap-Mode $roundDir $script:AllModeButton 'g_all'
    Enter-Code $roundDir 'dzqd' 'g'
    Scroll-To-Top $roundDir 'g_to_top'
    Focus-Field $roundDir 'A' 'a'
    Assert-FieldText $roundDir 'G' 'dzqd' 'G user deletion prevented the deleted candidate from committing'
    Scroll-To-Top $roundDir 'a_to_top'
    Focus-Field $roundDir 'A' 'a_refocus'
    Enter-Code $roundDir 'pqr' 'a'
    Focus-Field $roundDir 'B' 'b'
    Scroll-To-Top $roundDir 'b_to_top'
    Assert-FieldText $roundDir 'A' 'pqr' 'A three-code unique remained as raw preview instead of candidate text'
    Focus-Field $roundDir 'B' 'b_refocus'

    Enter-Code $roundDir 'aowk' 'b'
    Focus-Field $roundDir 'C' 'c'
    Assert-FieldText $roundDir 'B' '测' 'B four-code unique committed once'

    Enter-Code $roundDir 'wxyz' 'c'
    Focus-Field $roundDir 'D' 'd'
    Assert-FieldText $roundDir 'C' 'wxyz' 'C multiple candidates remained as raw preview'

    Tap-Mode $roundDir $script:CoreModeButton 'd_core'
    Focus-Field $roundDir 'D' 'd_core_refocus'
    Enter-Code $roundDir 'abcd' 'd'
    Focus-Field $roundDir 'E' 'e'
    Assert-FieldText $roundDir 'D' 'abcd' 'D longer code protected the unique exact candidate as raw preview'

    Tap-Mode $roundDir $script:AllModeButton 'e_all'
    Focus-Field $roundDir 'E' 'e_all_refocus'
    Enter-Code $roundDir 'wxyza' 'e'
    Commit-First $roundDir 'e'
    Focus-Field $roundDir 'F' 'f'
    Assert-FieldText $roundDir 'E' '用户顶屏共享同码同词000001' 'E fifth key was retained and consumed once'

    Tap-Mode $roundDir $script:AllModeButton 'f_all'
    Focus-Field $roundDir 'F' 'f_all_refocus'
    Enter-Code $roundDir 'bcde' 'f_old'
    Tap-Mode $roundDir $script:CoreModeButton 'f_core'
    Enter-Code $roundDir 'a' 'f_new'
    Commit-First $roundDir 'f'
    Focus-Field $roundDir 'H' 'h'
    Assert-FieldText $roundDir 'F' '共享同码同词000001' 'F empty old segment did not commit and retained the fifth key'

    Tap-Mode $roundDir $script:AllModeButton 'h_all'
    Focus-Field $roundDir 'H' 'h_all_refocus'
    Enter-Code $roundDir 'wxyza' 'h'
    Focus-Field $roundDir 'I' 'i'
    Assert-FieldText $roundDir 'H' '用户顶屏a' 'H user fixed rule changed top-screen first choice and retained the fifth key'

    Tap-Mode $roundDir $script:AllModeButton 'i_all'
    Focus-Field $roundDir 'I' 'i_all_refocus'
    Enter-Code $roundDir 'abcd' 'i'
    Tap-Mode $roundDir $script:CoreModeButton 'i_core'
    Assert-FieldText $roundDir 'I' 'abcd' 'I category update itself retained raw preview without candidate commit'

    Focus-Field $roundDir 'J' 'j'
    Enter-Code $roundDir 'wxqr' 'j'
    Commit-First $roundDir 'j'
    Focus-Field $roundDir 'K' 'k'
    Assert-FieldText $roundDir 'J' '正向切分段正向右段' 'J forward split committed longest left and retained right'

    Enter-Code $roundDir 'qrst' 'k'
    Commit-First $roundDir 'k'
    Focus-Field $roundDir 'L' 'l'
    Assert-FieldText $roundDir 'K' 'q反向合法后段' 'K reverse split preserved text order'

    Enter-Code $roundDir 'vutv' 'l'
    Focus-Field $roundDir 'M' 'm'
    Assert-FieldText $roundDir 'L' '' 'L invalid empty code cleared safely'

    Enter-Guide $roundDir 'm'
    Focus-Field $roundDir 'N' 'n'
    Assert-FieldText $roundDir 'M' ';g' 'M guide state remained isolated as guide preview'

    Tap-Mode $roundDir $script:XiaoheModeButton 'n_xiaohe'
    Focus-Field $roundDir 'N' 'n_xiaohe_refocus'
    Enter-Code $roundDir 'nihc' 'n_hello'
    Commit-First $roundDir 'n_hello'
    Enter-Code $roundDir 'uurufa' 'n_ime'
    Commit-First $roundDir 'n_ime'
    Assert-FieldText $roundDir 'N' '你好输入法' 'N xiaohe regression remained isolated'

    Capture-Screen $roundDir "round_${round}_final"
    [ordered]@{
        capturedAt = (Get-Date).ToString('o')
        round = $round
        cases = 14
        result = 'PASS'
    } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $roundDir "round_${round}_result.json") -Encoding UTF8
    Write-Host "STAGE11_6_7_EDITOR_ROUND_${round}=PASS"
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw "Debug HAP not found: $HapPath" }
if ($StartRound -gt $EndRound) { throw "StartRound must not exceed EndRound" }

Start-Transcript -Path $logPath -Force | Out-Null
try {
    $targets = & $hdc list targets 2>&1
    Assert-True (($targets -join "`n") -match [regex]::Escape($Target)) 'target is connected'
    $hap = Get-Item -LiteralPath $HapPath
    $hapHash = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-Hdc install -r $HapPath | Out-Null
    $systemVersion = (Invoke-HdcAllowFail shell param get const.product.software.version) -join "`n"
    $abi = (Invoke-HdcAllowFail shell param get const.product.cpu.abilist) -join "`n"
    $model = (Invoke-HdcAllowFail shell param get const.product.model) -join "`n"
    $resolution = (Invoke-HdcAllowFail shell hidumper -s RenderService -a screen) -join "`n"
    $resolutionMatch = [regex]::Match($resolution, 'render resolution=(\d+)x(\d+)')
    if ($resolutionMatch.Success) {
        $script:ScreenWidth = [int]$resolutionMatch.Groups[1].Value
        $script:ScreenHeight = [int]$resolutionMatch.Groups[2].Value
    }
    Write-Host "SCREEN_METRICS=$($script:ScreenWidth)x$($script:ScreenHeight)"

    for ($round = $StartRound; $round -le $EndRound; $round++) {
        if ($round -gt $StartRound) {
            Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
            Start-Sleep -Milliseconds 500
        }
        Run-Round $round
    }

    $executedRounds = $EndRound - $StartRound + 1
    $reportName = if ($StartRound -eq 1 -and $EndRound -eq 2) {
        'editor-a-n-two-rounds.json'
    } else {
        "editor-a-n-rounds-$StartRound-$EndRound.json"
    }
    $report = [ordered]@{
        capturedAt = (Get-Date).ToString('o')
        serial = $Target
        systemVersion = $systemVersion.Trim()
        abi = $abi.Trim()
        model = $model.Trim()
        resolutionProbe = $resolution.Trim()
        debugHapPath = $HapPath
        debugHapBytes = $hap.Length
        debugHapSha256 = $hapHash
        startRound = $StartRound
        endRound = $EndRound
        rounds = $executedRounds
        casesPerRound = 14
        assertions = @($StartRound..$EndRound | ForEach-Object { "EXTERNAL_TEXTINPUT_A_N_ROUND_${_}_PASS" }) +
            @('FINAL_EDITOR_TEXT_VERIFIED_PASS')
        result = 'PASS'
    }
    $report | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $outDir $reportName) -Encoding UTF8
    Write-Host "STAGE11_6_7_EDITOR_A_N_ROUNDS_${StartRound}_${EndRound}_RESULT=PASS"
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host 'STAGE11_6_7_EDITOR_A_N_TWO_ROUNDS_RESULT=FAIL'
    Stop-Transcript | Out-Null
    exit 1
}
