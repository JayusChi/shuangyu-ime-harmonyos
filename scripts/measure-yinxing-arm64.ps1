param(
    [string]$Target = '',
    [ValidateRange(3, 30)]
    [int]$Samples = 5,
    [string]$EvidenceDir = 'docs\evidence\yinxing-arm64-performance',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$ImeBundle = 'com.corrosion.shuangyuime',
    [string]$ClientBundle = 'com.example.shuangyuime.acceptance',
    [string]$ClientFieldHint = 'ACCEPT_CHAT_SEND'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed ($LASTEXITCODE): $($arguments -join ' ')`n$($output -join "`n")"
    }
    return @($output)
}

if ([string]::IsNullOrWhiteSpace($Target)) {
    $targets = @(& $hdc list targets 2>&1 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $arm64Targets = @($targets | Where-Object {
        $abi = ((& $hdc -t $_ shell param get const.product.cpu.abilist 2>&1) -join '').Trim()
        $model = ((& $hdc -t $_ shell param get const.product.model 2>&1) -join '').Trim()
        $abi -match 'arm64|aarch64' -and $model -notmatch '(?i)emulator|simulator'
    })
    if ($arm64Targets.Count -ne 1) {
        throw "Expected exactly one physical ARM64 target; found $($arm64Targets.Count). Pass -Target explicitly."
    }
    $Target = $arm64Targets[0]
}

$abi = ((Invoke-Hdc shell param get const.product.cpu.abilist) -join '').Trim()
$model = ((Invoke-Hdc shell param get const.product.model) -join '').Trim()
if ($abi -notmatch 'arm64|aarch64' -or $model -match '(?i)emulator|simulator') {
    throw "Target is not a physical ARM64 device: abi=$abi model=$model"
}

$outDir = if ([IO.Path]::IsPathRooted($EvidenceDir)) {
    [IO.Path]::GetFullPath($EvidenceDir)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}
if (-not $outDir.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write evidence outside the repository: $outDir"
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Get-Nodes([string]$Path) {
    $root = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nodes = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) {
            $script:YinxingPerformanceNodes.Add($node) | Out-Null
        }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:YinxingPerformanceNodes = $nodes
    Visit $root
    return $nodes.ToArray()
}

function Get-Bounds($Node) {
    $match = [regex]::Match([string]$Node.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "invalid bounds: $($Node.attributes.bounds)" }
    return [pscustomobject]@{
        CX = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Focus-MeasurementField([int]$Sample) {
    $remote = "/data/local/tmp/yinxing-performance-$Sample.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $outDir "layout-$Sample.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    $field = Get-Nodes $local | Where-Object {
        [string]$_.attributes.hint -eq $ClientFieldHint -and
        [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
    if ($null -eq $field) { throw "visible client field not found: $ClientFieldHint" }
    $bounds = Get-Bounds $field
    Invoke-Hdc shell uitest uiInput click $bounds.CX $bounds.CY | Out-Null
}

function Get-ImeRssKb {
    $processName = $ImeBundle + ':inputMethod'
    $lines = Invoke-Hdc shell ps -A -o PID,RSS,NAME
    foreach ($line in $lines) {
        $parts = ([string]$line).Trim() -split '\s+'
        if ($parts.Count -ge 3 -and $parts[$parts.Count - 1] -eq $processName) {
            return [int]$parts[1]
        }
    }
    throw "input method process not found: $processName"
}

$results = @()
for ($sample = 1; $sample -le $Samples; $sample++) {
    Invoke-Hdc shell aa force-stop $ImeBundle | Out-Null
    Invoke-Hdc shell aa force-stop $ClientBundle | Out-Null
    Invoke-Hdc shell hilog -r | Out-Null
    Invoke-Hdc shell ime -e $ImeBundle -f | Out-Null
    Invoke-Hdc shell ime -s $ImeBundle | Out-Null
    Invoke-Hdc shell aa start -b $ClientBundle -a EntryAbility | Out-Null
    Start-Sleep -Milliseconds 800

    $readyWatch = [Diagnostics.Stopwatch]::StartNew()
    Focus-MeasurementField $sample
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $engineInitializationMs = $null
    $bundlePreparationMs = $null
    $validationMode = ''
    $matchedLogs = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $logs = (Invoke-Hdc shell hilog -x) -join "`n"
        if ($logs -match 'xiaohe-yinxing bundle (?:already installed and valid|installed successfully): validationMode=([^,]+), preparationMs=(\d+)') {
            $validationMode = $Matches[1]
            $bundlePreparationMs = [int]$Matches[2]
        }
        if ($logs -match 'engine initialized: schemeId=xiaohe-yinxing, initializationMs=(\d+)') {
            $engineInitializationMs = [int]$Matches[1]
            $matchedLogs = @($logs -split "`n" | Where-Object {
                $_ -match 'YinxingBundleInstaller|engine initialized: schemeId=xiaohe-yinxing'
            })
            break
        }
        Start-Sleep -Milliseconds 100
    }
    $readyWatch.Stop()
    if ($null -eq $engineInitializationMs) {
        throw 'Timed out waiting for xiaohe-yinxing engine initialization; confirm the persisted scheme is xiaohe-yinxing.'
    }
    $rssReadyKb = Get-ImeRssKb
    Start-Sleep -Seconds 1
    $rssSettledKb = Get-ImeRssKb
    $matchedLogs | Set-Content -LiteralPath (Join-Path $outDir "hilog-$sample.txt") -Encoding UTF8
    $results += [ordered]@{
        sample = $sample
        processColdReadyMs = [math]::Round($readyWatch.Elapsed.TotalMilliseconds, 3)
        nativeEngineInitializationMs = $engineInitializationMs
        bundlePreparationMs = $bundlePreparationMs
        validationMode = $validationMode
        rssReadyKb = $rssReadyKb
        rssSettledKb = $rssSettledKb
    }
}

$report = [ordered]@{
    schemaVersion = 'xiaohe-yinxing-arm64-performance/1'
    capturedAt = (Get-Date).ToString('o')
    target = $Target
    abi = $abi
    model = $model
    sampleCount = $Samples
    cachePolicy = 'process-cold; operating-system page cache not controlled'
    precondition = 'IME and acceptance client installed; xiaohe-yinxing persisted as active scheme'
    samples = $results
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outDir 'arm64-performance.json') -Encoding UTF8
Write-Host "YINXING_ARM64_PERFORMANCE_RESULT=PASS"
