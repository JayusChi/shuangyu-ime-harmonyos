param(
    [string[]]$Targets = @(),
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\2026-08-05-computer-stage2\device',
    [switch]$SkipBuild,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$imeBundle = 'com.corrosion.shuangyuime'
$clientBundle = 'com.example.shuangyuime.acceptance'
$systemImeBundle = 'com.huawei.hmos.inputmethod'
$browserAddressHint = -join @(
    [char]0x641C, [char]0x7D22, [char]0x6216, [char]0x8F93,
    [char]0x5165, [char]0x7F51, [char]0x5740
)
$outDir = if ([IO.Path]::IsPathRooted($EvidenceDir)) {
    [IO.Path]::GetFullPath($EvidenceDir)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}
if (-not $outDir.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write evidence outside the repository: $outDir"
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Invoke-Hdc([string]$Target, [object[]]$Arguments) {
    $output = & $hdc -t $Target @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed for $Target ($LASTEXITCODE): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Get-LayoutNodes([string]$Path) {
    $root = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nodes = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) { $nodes.Add($node) | Out-Null }
        foreach ($child in @($node.children)) { Visit $child }
    }
    Visit $root
    return $nodes.ToArray()
}

function Get-Center($Node) {
    $match = [regex]::Match([string]$Node.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid bounds: $($Node.attributes.bounds)" }
    return [pscustomobject]@{
        X = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        Y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Dump-Layout([string]$Target, [string]$TargetDir, [string]$Name) {
    $remote = "/data/local/tmp/computer_stage2_$Name.json"
    Invoke-Hdc $Target @('shell', 'uitest', 'dumpLayout', '-p', $remote) | Out-Null
    $local = Join-Path $TargetDir "$Name.json"
    Invoke-Hdc $Target @('file', 'recv', $remote, $local) | Out-Null
    return $local
}

function Capture-Screen([string]$Target, [string]$TargetDir, [string]$Name) {
    $remote = "/data/local/tmp/computer_stage2_$Name.jpeg"
    Invoke-Hdc $Target @('shell', 'snapshot_display', '-f', $remote) | Out-Null
    Invoke-Hdc $Target @('file', 'recv', $remote, (Join-Path $TargetDir "$Name.jpeg")) | Out-Null
}

function Tap-Hint([string]$Target, [string]$Layout, [string]$Hint) {
    $node = Get-LayoutNodes $Layout | Where-Object {
        [string]$_.attributes.hint -eq $Hint -and [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
    if ($null -eq $node) { throw "Visible node not found: hint=$Hint" }
    $center = Get-Center $node
    Invoke-Hdc $Target @('shell', 'uitest', 'uiInput', 'click', $center.X, $center.Y) | Out-Null
    Start-Sleep -Milliseconds 700
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Description) {
    if ($Text -notmatch $Pattern) { throw "Missing evidence: $Description ($Pattern)" }
    Write-Host "PASS: $Description"
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\build-hap.ps1') `
        -SkipRust -BuildMode debug
    if ($LASTEXITCODE -ne 0) { throw "internalDebug build failed: $LASTEXITCODE" }
}

$hap = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
$clientHap = Join-Path $repoRoot 'tools\ime-acceptance-client\entry\build\default\outputs\default\entry-default-unsigned.hap'
if ($Targets.Count -eq 0) {
    $Targets = @(& $hdc list targets 2>&1 | ForEach-Object { ([string]$_).Trim() } | Where-Object {
        $_ -and $_ -notmatch 'Empty'
    })
}

$matrix = [Collections.Generic.List[object]]::new()
foreach ($target in $Targets) {
    $deviceType = ((Invoke-Hdc $target @('shell', 'param', 'get', 'const.product.devicetype')) -join '').Trim()
    if ($deviceType -notin @('phone', 'tablet', '2in1')) { continue }
    $targetDir = Join-Path $outDir $deviceType
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    $environment = [ordered]@{
        target = $target
        deviceType = $deviceType
        sdkApiVersion = ((Invoke-Hdc $target @('shell', 'param', 'get', 'const.ohos.apiversion')) -join '').Trim()
        model = ((Invoke-Hdc $target @('shell', 'param', 'get', 'const.product.model')) -join '').Trim()
        abi = ((Invoke-Hdc $target @('shell', 'uname', '-m')) -join '').Trim()
        capturedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    }
    $environment | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetDir 'environment.json') -Encoding UTF8

    if (-not $SkipInstall) {
        Invoke-Hdc $target @('install', '-r', $hap) | Out-Null
        Invoke-Hdc $target @('install', '-r', $clientHap) | Out-Null
    }
    Invoke-Hdc $target @('shell', 'ime', '-e', $imeBundle, '-f') | Out-Null
    Invoke-Hdc $target @('shell', 'ime', '-s', $imeBundle) | Out-Null
    Invoke-Hdc $target @('shell', 'hilog', '-r') | Out-Null
    Invoke-Hdc $target @('shell', 'aa', 'force-stop', $clientBundle) | Out-Null
    Invoke-Hdc $target @('shell', 'aa', 'start', '-b', $clientBundle, '-a', 'EntryAbility') | Out-Null
    Start-Sleep -Seconds 2

    $before = Dump-Layout $target $targetDir 'client_before'
    Tap-Hint $target $before 'ACCEPT_CHAT_SEND'
    Start-Sleep -Seconds 1
    Capture-Screen $target $targetDir 'textinput_focused'

    if ($deviceType -eq '2in1') {
        $focused = Dump-Layout $target $targetDir 'textinput_focused'
        Tap-Hint $target $focused 'ACCEPT_MULTILINE'
        Invoke-Hdc $target @('shell', 'aa', 'start', '-b', 'com.huawei.hmos.browser', '-a', 'MainAbility') | Out-Null
        Start-Sleep -Seconds 3
        $browser = Dump-Layout $target $targetDir 'browser_before'
        Tap-Hint $target $browser $browserAddressHint
        Start-Sleep -Seconds 1
        Capture-Screen $target $targetDir 'browser_focused'
    }

    $allLog = Invoke-Hdc $target @('shell', 'hilog', '-x')
    $stageLog = @($allLog | Where-Object {
        $_ -match 'InputMethodLifecycle|InputPanelController|SoftKeyboardPanelOwner|InputSessionController'
    })
    $stageLog | Set-Content -LiteralPath (Join-Path $targetDir 'stage2.log') -Encoding UTF8
    $text = $stageLog -join "`n"

    if ($deviceType -eq '2in1') {
        Assert-Match $text 'mode=HARDWARE, state=HARDWARE_READY, sessionActive=true, editorConnected=true, keyboardVisible=false' `
            '2in1 enters HARDWARE_READY with active editor session'
        if ($text -match 'keyboard panel created|keyboard panel visible') {
            throw '2in1 unexpectedly created or displayed a fixed keyboard panel.'
        }
        $readyCount = ([regex]::Matches($text, 'state=HARDWARE_READY')).Count
        if ($readyCount -lt 3) { throw "Expected rapid/app focus transitions to reach HARDWARE_READY at least 3 times; actual=$readyCount" }
        Write-Host 'PASS: 2in1 rapid TextInput/TextArea/browser focus transitions left no fixed panel'
    } else {
        Assert-Match $text 'mode=TOUCH, state=TOUCH_READY, sessionActive=true, editorConnected=true' `
            "$deviceType keeps TOUCH_READY session"
        Assert-Match $text 'keyboard panel visible' "$deviceType fixed keyboard remains visible"
    }

    Invoke-Hdc $target @('shell', 'ime', '-s', $systemImeBundle) | Out-Null
    $matrix.Add([pscustomobject]@{
        deviceType = $deviceType
        target = $target
        presentationMode = $(if ($deviceType -eq '2in1') { 'HARDWARE' } else { 'TOUCH' })
        result = 'PASS'
    }) | Out-Null
}

if (@($matrix | Where-Object deviceType -eq '2in1').Count -ne 1 -or
    @($matrix | Where-Object deviceType -eq 'phone').Count -ne 1 -or
    @($matrix | Where-Object deviceType -eq 'tablet').Count -ne 1) {
    throw "Expected one phone, one tablet, and one 2in1 result; actual=$($matrix | ConvertTo-Json -Compress)"
}
$matrix | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'summary.json') -Encoding UTF8
Write-Host "COMPUTER_STAGE2_RESULT=PASS evidence=$outDir"
