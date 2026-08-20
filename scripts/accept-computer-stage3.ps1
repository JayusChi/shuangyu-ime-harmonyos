param(
    [string]$Target = '',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\2026-08-05-computer-stage3\device',
    [switch]$SkipBuild,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
$imeBundle = 'com.corrosion.shuangyuime'
$clientBundle = 'com.example.shuangyuime.acceptance'
$systemImeBundle = 'com.huawei.hmos.inputmethod'
$browserAddressHint = -join @(
    [char]0x641C, [char]0x7D22, [char]0x6216, [char]0x8F93,
    [char]0x5165, [char]0x7F51, [char]0x5740
)
$expectedFirstCandidate = [string][char]0x4F60
$expectedSecondCandidate = [string][char]0x5BA4
$outDir = if ([IO.Path]::IsPathRooted($EvidenceDir)) {
    [IO.Path]::GetFullPath($EvidenceDir)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}
if (-not $outDir.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write evidence outside the repository: $outDir"
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Invoke-Hdc([object[]]$Arguments) {
    $output = & $hdc -t $script:Target @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Resolve-Target {
    if ($script:Target) {
        $type = ((Invoke-Hdc @('shell', 'param', 'get', 'const.product.devicetype')) -join '').Trim()
        if ($type -ne '2in1') { throw "Target is not 2in1: $script:Target ($type)" }
        return
    }
    foreach ($candidate in @(& $hdc list targets 2>&1)) {
        $candidate = ([string]$candidate).Trim()
        if (-not $candidate -or $candidate -match 'Empty') { continue }
        $type = ((& $hdc -t $candidate shell param get const.product.devicetype 2>&1) -join '').Trim()
        if ($LASTEXITCODE -eq 0 -and $type -eq '2in1') {
            $script:Target = $candidate
            return
        }
    }
    throw 'No online 2in1 target found.'
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

function Dump-Layout([string]$Name) {
    $remote = "/data/local/tmp/computer_stage3_$Name.json"
    Invoke-Hdc @('shell', 'uitest', 'dumpLayout', '-p', $remote) | Out-Null
    $local = Join-Path $outDir "$Name.json"
    Invoke-Hdc @('file', 'recv', $remote, $local) | Out-Null
    return $local
}

function Capture-Screen([string]$Name) {
    $remote = "/data/local/tmp/computer_stage3_$Name.jpeg"
    Invoke-Hdc @('shell', 'snapshot_display', '-f', $remote) | Out-Null
    Invoke-Hdc @('file', 'recv', $remote, (Join-Path $outDir "$Name.jpeg")) | Out-Null
}

function Find-Hint([string]$Layout, [string]$Hint) {
    return Get-LayoutNodes $Layout | Where-Object {
        [string]$_.attributes.hint -eq $Hint -and [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
}

function Tap-Hint([string]$Layout, [string]$Hint) {
    $node = Find-Hint $Layout $Hint
    if ($null -eq $node) { throw "Visible field not found: $Hint" }
    $center = Get-Center $node
    Invoke-Hdc @('shell', 'uitest', 'uiInput', 'click', $center.X, $center.Y) | Out-Null
    Start-Sleep -Milliseconds 500
}

function Send-Key([int]$KeyCode) {
    Invoke-Hdc @('shell', 'uitest', 'uiInput', 'keyEvent', $KeyCode) | Out-Null
    Start-Sleep -Milliseconds 120
}

function Assert-FieldText([string]$Layout, [string]$Hint, [string]$Expected) {
    $node = Find-Hint $Layout $Hint
    if ($null -eq $node) { throw "Field missing while checking text: $Hint" }
    $actual = [string]$node.attributes.text
    if ($actual -ne $Expected) { throw "Unexpected $Hint text: expected='$Expected' actual='$actual'" }
    Write-Host "PASS: $Hint text='$Expected'"
}

function Assert-Log([string]$Text, [string]$Pattern, [string]$Description) {
    if ($Text -notmatch $Pattern) { throw "Missing log evidence: $Description ($Pattern)" }
    Write-Host "PASS: $Description"
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
$script:Target = $Target
Resolve-Target

$environment = [ordered]@{
    target = $script:Target
    deviceType = ((Invoke-Hdc @('shell', 'param', 'get', 'const.product.devicetype')) -join '').Trim()
    sdkApiVersion = ((Invoke-Hdc @('shell', 'param', 'get', 'const.ohos.apiversion')) -join '').Trim()
    model = ((Invoke-Hdc @('shell', 'param', 'get', 'const.product.model')) -join '').Trim()
    abi = ((Invoke-Hdc @('shell', 'uname', '-m')) -join '').Trim()
    capturedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
}
$environment | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'environment.json') -Encoding UTF8

if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\build-hap.ps1') `
        -SkipRust -BuildMode release
    if ($LASTEXITCODE -ne 0) { throw "default Release build failed: $LASTEXITCODE" }
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
    Push-Location (Join-Path $repoRoot 'tools\ime-acceptance-client')
    try {
        & $hvigor --no-daemon --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
        if ($LASTEXITCODE -ne 0) { throw "acceptance client build failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

$hap = Join-Path $repoRoot 'entry\build\artifacts\entry-release-unsigned.hap'
$clientHap = Join-Path $repoRoot 'tools\ime-acceptance-client\entry\build\default\outputs\default\entry-default-unsigned.hap'
if (-not $SkipInstall) {
    Invoke-Hdc @('install', '-r', $hap) | Out-Null
    Invoke-Hdc @('install', '-r', $clientHap) | Out-Null
}

Invoke-Hdc @('shell', 'ime', '-e', $imeBundle, '-f') | Out-Null
Invoke-Hdc @('shell', 'ime', '-s', $imeBundle) | Out-Null
Invoke-Hdc @('shell', 'hilog', '-r') | Out-Null
Invoke-Hdc @('shell', 'aa', 'force-stop', $clientBundle) | Out-Null
Invoke-Hdc @('shell', 'aa', 'start', '-b', $clientBundle, '-a', 'EntryAbility') | Out-Null
Start-Sleep -Seconds 2

$layout = Dump-Layout 'client_initial'
Tap-Hint $layout 'ACCEPT_CHAT_SEND'
Send-Key 2030 # N
Send-Key 2025 # I
Send-Key 2050 # Space
$layout = Dump-Layout 'chat_space_commit'
Assert-FieldText $layout 'ACCEPT_CHAT_SEND' $expectedFirstCandidate

Tap-Hint $layout 'ACCEPT_BROWSER_URL'
Send-Key 2017 # A
Send-Key 2018 # B
Send-Key 2050 # Space: no composition, host consumes
$layout = Dump-Layout 'url_passthrough'
Assert-FieldText $layout 'ACCEPT_BROWSER_URL' 'ab '

Tap-Hint $layout 'ACCEPT_SEARCH'
Send-Key 2037 # U: the active xiaohe-yinxing scheme exposes two stable ui candidates
Send-Key 2025
Send-Key 2015 # Right: select candidate 2
Send-Key 2050
$layout = Dump-Layout 'search_direction_commit'
Assert-FieldText $layout 'ACCEPT_SEARCH' $expectedSecondCandidate

Tap-Hint $layout 'ACCEPT_MULTILINE'
Send-Key 2030
Send-Key 2025
Send-Key 2070 # Esc
$layout = Dump-Layout 'multiline_escape_cancel'
Assert-FieldText $layout 'ACCEPT_MULTILINE' ''
Send-Key 2050
$layout = Dump-Layout 'multiline_empty_space_passthrough'
Assert-FieldText $layout 'ACCEPT_MULTILINE' ' '
Send-Key 2055
$layout = Dump-Layout 'multiline_empty_backspace_passthrough'
Assert-FieldText $layout 'ACCEPT_MULTILINE' ''

# Bring stress/password fields into view.
Invoke-Hdc @('shell', 'uitest', 'uiInput', 'swipe', 800, 1450, 800, 400, 800) | Out-Null
Start-Sleep -Milliseconds 700
$layout = Dump-Layout 'client_scrolled'
Tap-Hint $layout 'ACCEPT_STRESS_LONG_INPUT'
Send-Key 2037
Send-Key 2025
Send-Key 2069 # PageDown
Send-Key 2068 # PageUp
Send-Key 2070 # Esc
$layout = Dump-Layout 'stress_page_cancel'
Assert-FieldText $layout 'ACCEPT_STRESS_LONG_INPUT' ''

# Rapid continuous input remains serialized; each ni+Space produces one character.
for ($index = 0; $index -lt 10; $index += 1) {
    Send-Key 2030
    Send-Key 2025
    Send-Key 2050
}
$layout = Dump-Layout 'stress_rapid_input'
$stress = Find-Hint $layout 'ACCEPT_STRESS_LONG_INPUT'
if ($null -eq $stress -or ([string]$stress.attributes.text).Length -ne 10) {
    throw "Rapid input length mismatch: '$([string]$stress.attributes.text)'"
}
Write-Host 'PASS: rapid ni+Space input committed exactly 10 characters'

if ($null -eq (Find-Hint $layout 'ACCEPT_PASSWORD')) {
    Invoke-Hdc @('shell', 'uitest', 'uiInput', 'swipe', 800, 1450, 800, 400, 800) | Out-Null
    Start-Sleep -Milliseconds 700
    $layout = Dump-Layout 'client_password_scrolled'
}
Tap-Hint $layout 'ACCEPT_PASSWORD'
Send-Key 2030
Send-Key 2025
Send-Key 2050
$layout = Dump-Layout 'password_passthrough'
$passwordLength = Get-LayoutNodes $layout | Where-Object {
    [string]$_.attributes.text -eq 'PASSWORD_LENGTH=3'
} | Select-Object -First 1
if ($null -eq $passwordLength) { throw 'Password editor did not receive three direct host characters.' }
Write-Host 'PASS: password input bypassed Chinese composition and received three host characters'
Capture-Screen 'client_stage3_complete'

Invoke-Hdc @('shell', 'aa', 'start', '-b', 'com.huawei.hmos.browser', '-a', 'MainAbility') | Out-Null
Start-Sleep -Seconds 3
$browser = Dump-Layout 'browser_initial'
Tap-Hint $browser $browserAddressHint
Send-Key 2017
Send-Key 2018
$browser = Dump-Layout 'browser_direct_input'
$address = Find-Hint $browser $browserAddressHint
if ($null -eq $address -or [string]$address.attributes.text -notmatch 'ab') {
    throw "Browser address direct input failed: '$([string]$address.attributes.text)'"
}
Write-Host 'PASS: system browser URL editor received direct physical input'
Capture-Screen 'browser_direct_input'

$allLog = Invoke-Hdc @('shell', 'hilog', '-x')
$stageLog = @($allLog | Where-Object {
    $_ -match 'InputMethodLifecycle|KeyboardController|InputSessionController'
})
$stageLog | Set-Content -LiteralPath (Join-Path $outDir 'stage3.log') -Encoding UTF8
$text = $stageLog -join "`n"
Assert-Log $text 'state=HARDWARE_READY, sessionActive=true, editorConnected=true, keyboardVisible=false' `
    '2in1 stays HARDWARE_READY without fixed keyboard'
Assert-Log $text 'physical key consumed: type=cancel, keyCode=2070' 'Esc cancellation routed'
Assert-Log $text 'physical key consumed: type=select_next, keyCode=2015' 'direction selection routed'
Assert-Log $text 'physical key consumed: type=next_page, keyCode=2069' 'PageDown routed'
Assert-Log $text 'physical key consumed: type=previous_page, keyCode=2068' 'PageUp routed'
Assert-Log $text 'candidate commit started: stage=prepare, index=1' 'selected candidate committed'
# The platform withholds the IME inputStart callback for this secure editor on
# the target image. PASSWORD_LENGTH=3 above therefore proves direct host input;
# the ArkTS editor-policy tests cover candidate/learning denial explicitly.
if ($text -match 'keyboard panel created|keyboard panel visible') {
    throw '2in1 unexpectedly created or displayed a fixed keyboard panel.'
}
if ($text -match 'fatal|panic|crash|ENGINE_INTERNAL_ERROR') {
    throw 'Fatal/runtime error marker found in stage 3 log.'
}

Invoke-Hdc @('shell', 'ime', '-s', $systemImeBundle) | Out-Null
$summary = [ordered]@{
    result = 'PASS'
    target = $script:Target
    deviceType = $environment.deviceType
    independentHost = 'PASS'
    systemBrowser = 'PASS'
    fixedKeyboardAbsent = 'PASS'
    chineseComposition = 'PASS'
    editCancelSelectionPaging = 'PASS'
    urlPasswordPassthrough = 'PASS'
    rapidInput = 'PASS'
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'summary.json') -Encoding UTF8
Write-Host "COMPUTER_STAGE3_RESULT=PASS evidence=$outDir"
