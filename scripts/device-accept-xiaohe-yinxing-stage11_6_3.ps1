param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [switch]$SkipInstall,
    [string]$EvidenceDir = 'docs\evidence\2026-07-22-stage-11.6.3-formal\device',
    [string]$ResultName = 'STAGE11_6_3_X86_64_DEVICE_RESULT',
    [string]$CaseRegex = '^PASS . ([A-J]) ',
    [string]$FailureCaseRegex = '^FAIL . ([A-J]) ',
    [int]$ExpectedCaseCount = 10,
    [int]$ScrollCount = 5,
    [int]$PageWaitSeconds = 8
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$hap = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
$formal = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'
$outDir = Join-Path $repoRoot $EvidenceDir
$bundleName = 'com.corrosion.shuangyuime'
New-Item -ItemType Directory -Force $outDir | Out-Null
$logPath = Join-Path $outDir 'device-acceptance.log'

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if ($exitCode -ne 0) { throw "hdc failed ($exitCode): $($arguments -join ' ')" }
    return $output
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

function Get-Texts([string]$path) {
    $root = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = [Collections.Generic.List[string]]::new()
    function Visit($node) {
        if ($null -ne $node.attributes -and -not [string]::IsNullOrEmpty([string]$node.attributes.text)) {
            $script:Stage1163Texts.Add([string]$node.attributes.text) | Out-Null
        }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:Stage1163Texts = $list
    Visit $root
    return $list.ToArray()
}

function Get-TextBounds([string]$path, [string]$expectedText) {
    $root = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Stage1163TextBounds = $null
    function Visit($node) {
        if ($null -ne $script:Stage1163TextBounds) { return }
        if ($null -ne $node.attributes -and [string]$node.attributes.text -eq $expectedText) {
            $match = [regex]::Match([string]$node.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
            if ($match.Success) {
                $script:Stage1163TextBounds = [ordered]@{
                    X1 = [int]$match.Groups[1].Value
                    Y1 = [int]$match.Groups[2].Value
                    X2 = [int]$match.Groups[3].Value
                    Y2 = [int]$match.Groups[4].Value
                }
                return
            }
        }
        foreach ($child in @($node.children)) { Visit $child }
    }
    Visit $root
    if ($null -eq $script:Stage1163TextBounds) {
        throw "Unable to locate text bounds: $expectedText"
    }
    return $script:Stage1163TextBounds
}

function Get-RootBounds([string]$path) {
    $root = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $match = [regex]::Match([string]$root.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Unable to parse root bounds: $path" }
    return [ordered]@{
        X1 = [int]$match.Groups[1].Value
        Y1 = [int]$match.Groups[2].Value
        X2 = [int]$match.Groups[3].Value
        Y2 = [int]$match.Groups[4].Value
    }
}

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERT FAILED: $message" }
    Write-Host "PASS: $message"
}

function Run-Page([int]$run) {
    Invoke-Hdc shell aa force-stop $bundleName | Out-Null
    Invoke-Hdc shell aa start -b $bundleName -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $indexLayout = Dump-Layout "run${run}-index"
    $entryLabel = -join @(
        [char]0x7801, [char]0x8868, [char]0x8fd0, [char]0x884c,
        [char]0x65f6, [char]0x9a8c, [char]0x6536
    )
    $entry = Get-TextBounds $indexLayout $entryLabel
    $entryX = [int](($entry.X1 + $entry.X2) / 2)
    $entryY = [int](($entry.Y1 + $entry.Y2) / 2)
    Invoke-Hdc shell uitest uiInput click $entryX $entryY | Out-Null
    Start-Sleep -Seconds $PageWaitSeconds

    $allTexts = [Collections.Generic.List[string]]::new()
    $labels = [Collections.Generic.HashSet[string]]::new()
    $top = Dump-Layout "run${run}-top"
    foreach ($text in Get-Texts $top) {
        $allTexts.Add($text) | Out-Null
        if ($text -match $CaseRegex) { $labels.Add($matches[1]) | Out-Null }
    }
    $overallPassed = (Get-Texts $top | Where-Object { $_ -match 'PASS.*ms$' }).Count -gt 0
    Capture-Screen "run${run}-top"

    $rootBounds = Get-RootBounds $top
    $swipeX = [int](($rootBounds.X1 + $rootBounds.X2) / 2)
    $swipeStartY = [int]($rootBounds.Y2 * 0.82)
    $swipeEndY = [int]($rootBounds.Y2 * 0.20)

    for ($index = 1; $index -le $ScrollCount; $index++) {
        Invoke-Hdc shell uitest uiInput swipe $swipeX $swipeStartY $swipeX $swipeEndY 900 | Out-Null
        Start-Sleep -Milliseconds 350
        $layout = Dump-Layout "run${run}-scroll-$index"
        foreach ($text in Get-Texts $layout) {
            if (-not $allTexts.Contains($text)) { $allTexts.Add($text) | Out-Null }
            if ($text -match $CaseRegex) { $labels.Add($matches[1]) | Out-Null }
            if ($text -match $FailureCaseRegex) { throw "run $run case $($matches[1]) failed" }
        }
        if ($index -in @(2, 4, 5)) { Capture-Screen "run${run}-scroll-$index" }
    }
    Assert-True $overallPassed "run $run overall PASS"
    Assert-True ($labels.Count -eq $ExpectedCaseCount) "run $run observed all expected PASS labels"
    return [ordered]@{
        run = $run
        passLabels = @($labels | Sort-Object)
        visibleTexts = @($allTexts)
    }
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
if (-not (Test-Path -LiteralPath $hap -PathType Leaf)) { throw "Debug HAP not found: $hap" }
Start-Transcript -Path $logPath -Force | Out-Null
try {
    $targets = Invoke-Hdc list targets -v
    Assert-True (($targets -join "`n") -match [regex]::Escape($Target)) 'target is connected'
    $uname = (Invoke-Hdc shell uname -a) -join ' '
    $model = ((Invoke-Hdc shell param get const.product.model) -join ' ').Trim()
    $version = ((Invoke-Hdc shell param get const.product.software.version) -join ' ').Trim()
    $abi = ((Invoke-Hdc shell param get const.product.cpu.abilist) -join ' ').Trim()
    $screen = (Invoke-Hdc shell hidumper -s RenderService -a screen) -join "`n"
    $resolution = [regex]::Match($screen, 'render resolution=(\d+x\d+)').Groups[1].Value
    Assert-True ($abi -eq 'x86_64') 'device ABI is x86_64'
    Assert-True ($resolution -in @('1320x2856', '2880x1920')) 'device resolution is a supported automation profile'

    $hapItem = Get-Item -LiteralPath $hap
    $formalItem = Get-Item -LiteralPath $formal
    $hapHash = (Get-FileHash -LiteralPath $hap -Algorithm SHA256).Hash.ToLowerInvariant()
    $formalHash = (Get-FileHash -LiteralPath $formal -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True ($formalItem.Length -eq 25397952) 'formal bundle size is frozen'
    Assert-True ($formalHash -eq '00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30') 'formal bundle hash is frozen'
    if (-not $SkipInstall) { Invoke-Hdc install -r $hap | Out-Null }

    $first = Run-Page 1
    $second = Run-Page 2
    Assert-True (($first.passLabels -join ',') -eq ($second.passLabels -join ',')) 'force-stop/restart preserves acceptance results'

    $report = [ordered]@{
        capturedAt = (Get-Date).ToString('o')
        serial = $Target
        model = $model
        harmonyVersion = $version
        abi = $abi
        resolution = $resolution
        uname = $uname
        hdcPath = $hdc
        debugHapPath = $hapItem.FullName
        debugHapBytes = $hapItem.Length
        debugHapSha256 = $hapHash
        injectedBundlePath = $formalItem.FullName
        injectedBundleBytes = $formalItem.Length
        injectedBundleSha256 = $formalHash
        runs = @($first, $second)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outDir 'device-acceptance.json') -Encoding UTF8
    Write-Host "$ResultName=PASS"
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host "$ResultName=FAIL"
    Stop-Transcript | Out-Null
    exit 1
}
