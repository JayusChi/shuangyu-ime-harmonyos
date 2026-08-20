param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [switch]$SkipStage11Regression,
    [switch]$OnlyPartialCommit
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$appProfile = Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundle = [string]$appProfile.app.bundleName
$outDir = Join-Path $repoRoot 'docs\evidence\stage11_5\device'
New-Item -ItemType Directory -Force $outDir | Out-Null
$logPath = Join-Path $outDir 'stage11_5_device_acceptance.log'

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
    & $script:hdc -t $script:Target @arguments 2>&1 | ForEach-Object { Write-Host $_ }
}

function Get-Bounds($node) {
    $match = [regex]::Match([string]$node.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        X1=[int]$match.Groups[1].Value; Y1=[int]$match.Groups[2].Value
        X2=[int]$match.Groups[3].Value; Y2=[int]$match.Groups[4].Value
        CX=[int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY=[int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Get-Nodes([string]$path) {
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) { $script:Stage115Nodes.Add($node) | Out-Null }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:Stage115Nodes = $list
    Visit $json
    return $list.ToArray()
}

function Find-Text([string]$path, [string]$text, [int]$minY=0, [int]$maxY=3000) {
    $matches = @()
    foreach ($node in Get-Nodes $path) {
        if ([string]$node.attributes.text -ne $text -or [string]$node.attributes.visible -ne 'true') { continue }
        $bounds = Get-Bounds $node
        if ($null -ne $bounds -and $bounds.Y1 -ge $minY -and $bounds.Y2 -le $maxY) {
            $matches += [pscustomobject]@{ Node=$node; Bounds=$bounds }
        }
    }
    return $matches | Sort-Object { $_.Bounds.Y1 }, { $_.Bounds.X1 } | Select-Object -First 1
}

function Find-Hint([string]$path, [string]$hint) {
    foreach ($node in Get-Nodes $path) {
        if ([string]$node.attributes.hint -eq $hint -and [string]$node.attributes.visible -eq 'true') {
            $bounds = Get-Bounds $node
            if ($null -ne $bounds) { return [pscustomobject]@{ Node=$node; Bounds=$bounds } }
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
    Start-Sleep -Milliseconds 220
}

function Tap-Text([string]$layout, [string]$text, [int]$minY, [int]$maxY, [string]$label) {
    Tap-Node (Find-Text $layout $text $minY $maxY) $label
}

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERT FAILED: $message" }
    Write-Host "PASS: $message"
}

function Open-DebugNormalInput([string]$prefix) {
    Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-HdcAllowFail shell ime -s $bundle | Out-Null
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $debugEntry = $null
    for ($attempt=1; $attempt -le 8; $attempt++) {
        $page = Dump-Layout "${prefix}_settings_$attempt"
        $debugEntry = Find-Text $page '调试与验收'
        if ($null -ne $debugEntry) { break }
        Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
        Start-Sleep -Milliseconds 400
    }
    Tap-Node $debugEntry 'open debug acceptance page'
    Start-Sleep -Seconds 1
    for ($i=0; $i -lt 5; $i++) {
        Invoke-Hdc shell uitest uiInput swipe 660 500 660 2500 1000 | Out-Null
        Start-Sleep -Milliseconds 250
    }
    $input = $null
    for ($attempt=1; $attempt -le 4; $attempt++) {
        $page = Dump-Layout "${prefix}_debug_$attempt"
        $input = Find-Hint $page '普通文本：默认中文'
        if ($null -ne $input) { break }
        Invoke-Hdc shell uitest uiInput swipe 660 500 660 2500 1000 | Out-Null
    }
    Tap-Node $input 'focus normal production input'
    Start-Sleep -Seconds 1
    return Dump-Layout "${prefix}_keyboard"
}

$script:AccumulatedText = ''
$script:KeyboardReference = ''
function Type-And-Commit([string]$raw, [string]$candidate, [string]$prefix) {
    foreach ($key in $raw.ToCharArray()) {
        Tap-Text $script:KeyboardReference ([string]$key) 1700 2500 "type $key for $prefix"
    }
    Start-Sleep -Milliseconds 450
    $candidateLayout = Dump-Layout "${prefix}_candidates"
    Assert-True ($null -ne (Find-Text $candidateLayout $candidate 1500 2150)) "$candidate is visible for $raw"
    Tap-Text $candidateLayout $candidate 1500 2150 "commit $candidate"
    Start-Sleep -Milliseconds 450
    $committed = Dump-Layout "${prefix}_committed"
    $script:AccumulatedText += $candidate
    $input = Find-Hint $committed '普通文本：默认中文'
    Assert-True ($null -ne $input -and [string]$input.Node.attributes.text -eq $script:AccumulatedText) "$candidate committed to TextInput"
    Capture-Screen "${prefix}_committed"
}

if (-not (Test-Path -LiteralPath $hdc)) { throw "hdc not found: $hdc" }
Start-Transcript -Path $logPath -Force | Out-Null
try {
    if (-not $SkipStage11Regression) {
        & (Join-Path $PSScriptRoot 'device-accept-stage11.ps1') -Target $Target -DevEcoRoot $DevEcoRoot
        if ($LASTEXITCODE -ne 0) { throw 'Stage 11 device regression failed' }
    }

    $script:KeyboardReference = Open-DebugNormalInput 'stage11_5_initial'
    Assert-True ($null -ne (Find-Text $script:KeyboardReference '中' 2450 2800)) 'production engine starts in Chinese mode'
    if (-not $OnlyPartialCommit) {
        Type-And-Commit 'nihc' '你好' 'stage11_5_daily'
        Type-And-Commit 'uurufa' '输入法' 'stage11_5_multiword'
        Type-And-Commit 'ybhh' '银行' 'stage11_5_polyphone'
        Type-And-Commit 'yixbyiyi' '一心一意' 'stage11_5_idiom'
        Type-And-Commit 'buyskeqi' '不用客气' 'stage11_5_phrase'
        Type-And-Commit 'jbtmtmqibuco' '今天天气不错' 'stage11_5_sentence'
    }

    foreach ($key in 'uurufa'.ToCharArray()) {
        Tap-Text $script:KeyboardReference ([string]$key) 1700 2500 "type $key for partial commit"
    }
    $partial = Dump-Layout 'stage11_5_partial_candidates'
    for ($page=2; $page -le 8 -and $null -eq (Find-Text $partial '输入' 1500 2150); $page++) {
        Tap-Text $partial '›' 1700 2000 "open partial candidate page $page"
        $partial = Dump-Layout "stage11_5_partial_candidates_page_$page"
    }
    Tap-Text $partial '输入' 1500 2150 'commit partial candidate 输入'
    $remaining = Dump-Layout 'stage11_5_partial_remaining'
    Assert-True ($null -ne (Find-Text $remaining '法' 1500 2150)) 'remaining fa continues converting after partial commit'
    Tap-Text $remaining '法' 1500 2150 'commit remaining 法'
    $script:AccumulatedText += '输入法'
    $partialCommitted = Dump-Layout 'stage11_5_partial_committed'
    $partialInput = Find-Hint $partialCommitted '普通文本：默认中文'
    Assert-True ($null -ne $partialInput -and [string]$partialInput.Node.attributes.text -eq $script:AccumulatedText) 'partial and remaining candidates commit exact text'

    if (-not $OnlyPartialCommit) {
        Tap-Text $partialCommitted '隐藏' 2450 2700 'hide production keyboard before restart'
        Start-Sleep -Milliseconds 700
        $script:AccumulatedText = ''
        $script:KeyboardReference = Open-DebugNormalInput 'stage11_5_restart'
        Type-And-Commit 'nihc' '你好' 'stage11_5_restart_query'
    }
    Write-Host 'ARM64_PHYSICAL_DEVICE_RESULT=NOT_RUN_USER_EXEMPTED'
    Write-Host 'STAGE11_5_DEVICE_ACCEPTANCE_RESULT=PASS'
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host 'STAGE11_5_DEVICE_ACCEPTANCE_RESULT=FAIL'
    Stop-Transcript | Out-Null
    exit 1
}
