param(
    [string]$Target = '',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\2026-08-05-computer-stage4\device',
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
$firstCandidate = '1. ' + [string][char]0x4F60
$firstCandidateText = [string][char]0x4F60
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
        $script:Target = $candidate
        $type = ((Invoke-Hdc @('shell', 'param', 'get', 'const.product.devicetype')) -join '').Trim()
        if ($type -eq '2in1') { return }
    }
    throw 'No online 2in1 target found.'
}

function Get-Nodes([string]$Path) {
    $root = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nodes = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) { $nodes.Add($node) | Out-Null }
        foreach ($child in @($node.children)) { Visit $child }
    }
    Visit $root
    return $nodes.ToArray()
}

function Get-Bounds($Node) {
    $match = [regex]::Match([string]$Node.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid bounds: $($Node.attributes.bounds)" }
    return [pscustomobject]@{
        X1 = [int]$match.Groups[1].Value
        Y1 = [int]$match.Groups[2].Value
        X2 = [int]$match.Groups[3].Value
        Y2 = [int]$match.Groups[4].Value
        CX = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Dump-Layout([string]$Name) {
    $remote = "/data/local/tmp/computer_stage4_$Name.json"
    Invoke-Hdc @('shell', 'uitest', 'dumpLayout', '-p', $remote) | Out-Null
    $local = Join-Path $outDir "$Name.json"
    Invoke-Hdc @('file', 'recv', $remote, $local) | Out-Null
    return $local
}

function Capture-Screen([string]$Name) {
    $remote = "/data/local/tmp/computer_stage4_$Name.jpeg"
    Invoke-Hdc @('shell', 'snapshot_display', '-f', $remote) | Out-Null
    Invoke-Hdc @('file', 'recv', $remote, (Join-Path $outDir "$Name.jpeg")) | Out-Null
}

function Find-Hint([string]$Layout, [string]$Hint) {
    return Get-Nodes $Layout | Where-Object {
        [string]$_.attributes.hint -eq $Hint -and [string]$_.attributes.visible -eq 'true' -and
        [string]$_.attributes.bounds -match '^\[\d+,\d+\]\[\d+,\d+\]$'
    } | Select-Object -First 1
}

function Find-Text([string]$Layout, [string]$Text) {
    return Get-Nodes $Layout | Where-Object {
        [string]$_.attributes.text -eq $Text -and [string]$_.attributes.visible -eq 'true' -and
        [string]$_.attributes.bounds -match '^\[\d+,\d+\]\[\d+,\d+\]$'
    } | Select-Object -First 1
}

function Tap-Node($Node, [string]$Description) {
    if ($null -eq $Node) { throw "Node not found: $Description" }
    $bounds = Get-Bounds $Node
    Invoke-Hdc @('shell', 'uitest', 'uiInput', 'click', $bounds.CX, $bounds.CY) | Out-Null
    Start-Sleep -Milliseconds 500
}

function Send-Key([int]$KeyCode) {
    Invoke-Hdc @('shell', 'uitest', 'uiInput', 'keyEvent', $KeyCode) | Out-Null
    Start-Sleep -Milliseconds 350
}

function Assert-True([bool]$Condition, [string]$Description) {
    if (-not $Condition) { throw "Assertion failed: $Description" }
    Write-Host "PASS: $Description"
}

function Assert-CandidateNearField([string]$Layout, [string]$Description) {
    $field = Find-Hint $Layout 'ACCEPT_CHAT_SEND'
    $candidate = Find-Text $Layout $firstCandidate
    if ($null -eq $field -or $null -eq $candidate) { throw "Missing field/candidate: $Description" }
    $fieldBounds = Get-Bounds $field
    $candidateBounds = Get-Bounds $candidate
    Assert-True ([string]$field.attributes.focused -eq 'true') "$Description keeps host focus"
    Assert-True ($candidateBounds.Y1 -ge $fieldBounds.Y1 -and $candidateBounds.Y1 -le $fieldBounds.Y2 + 160) `
        "$Description remains near the cursor field"
    return [pscustomobject]@{ Field = $fieldBounds; Candidate = $candidateBounds }
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
$script:Target = $Target
Resolve-Target

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

$environment = [ordered]@{
    target = $script:Target
    deviceType = ((Invoke-Hdc @('shell', 'param', 'get', 'const.product.devicetype')) -join '').Trim()
    sdkApiVersion = ((Invoke-Hdc @('shell', 'param', 'get', 'const.ohos.apiversion')) -join '').Trim()
    model = ((Invoke-Hdc @('shell', 'param', 'get', 'const.product.model')) -join '').Trim()
    abi = ((Invoke-Hdc @('shell', 'uname', '-m')) -join '').Trim()
    capturedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    hapBytes = (Get-Item -LiteralPath $hap).Length
    hapSha256 = (Get-FileHash -LiteralPath $hap -Algorithm SHA256).Hash.ToLowerInvariant()
}
$environment | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'environment.json') -Encoding UTF8

# Clear logs before switching IMEs. The system may retain an input-method extension
# process across installs, so one-time initialization logs are recorded when available
# but the repeatable runtime gate is based on route, content, focus and lifecycle behavior.
Invoke-Hdc @('shell', 'hilog', '-r') | Out-Null
Invoke-Hdc @('shell', 'ime', '-s', $systemImeBundle) | Out-Null
Invoke-Hdc @('shell', 'aa', 'force-stop', $imeBundle) | Out-Null
Invoke-Hdc @('shell', 'aa', 'force-stop', $clientBundle) | Out-Null
Start-Sleep -Seconds 1
Invoke-Hdc @('shell', 'ime', '-e', $imeBundle, '-f') | Out-Null
Invoke-Hdc @('shell', 'ime', '-s', $imeBundle) | Out-Null
Invoke-Hdc @('shell', 'aa', 'start', '-b', $clientBundle, '-a', 'EntryAbility') | Out-Null
Start-Sleep -Seconds 2

$initial = Dump-Layout 'initial'
Tap-Node (Find-Hint $initial 'ACCEPT_CHAT_SEND') 'chat TextInput'
Send-Key 2030 # N
Send-Key 2025 # I
$candidate = Dump-Layout 'candidate_visible'
$initialPosition = Assert-CandidateNearField $candidate 'initial floating candidate'
Capture-Screen 'candidate_visible'

Tap-Node (Find-Text $candidate $firstCandidate) 'mouse candidate 1'
$mouseCommit = Dump-Layout 'mouse_commit'
$chat = Find-Hint $mouseCommit 'ACCEPT_CHAT_SEND'
Assert-True ([string]$chat.attributes.text -eq $firstCandidateText) 'mouse click commits candidate 1 exactly once'
Assert-True ([string]$chat.attributes.focused -eq 'true') 'mouse click preserves host focus'
Assert-True ($null -eq (Find-Text $mouseCommit $firstCandidate)) 'candidate hides after mouse commit'

Tap-Node (Find-Hint $mouseCommit 'ACCEPT_SEARCH') 'search TextInput'
Send-Key 2030
Send-Key 2025
Send-Key 2001 # numeric candidate 1
$numberCommit = Dump-Layout 'number_commit'
$search = Find-Hint $numberCommit 'ACCEPT_SEARCH'
Assert-True ([string]$search.attributes.text -eq $firstCandidateText) 'number key commits the same candidate as mouse click'

Tap-Node (Find-Hint $numberCommit 'ACCEPT_MULTILINE') 'multiline TextArea'
Send-Key 2030
Send-Key 2025
$beforeEsc = Dump-Layout 'before_esc'
Assert-True ($null -ne (Find-Text $beforeEsc $firstCandidate)) 'candidate is visible before Esc'
Send-Key 2070
$afterEsc = Dump-Layout 'after_esc'
$multiline = Find-Hint $afterEsc 'ACCEPT_MULTILINE'
Assert-True ($null -eq (Find-Text $afterEsc $firstCandidate)) 'Esc hides candidate immediately'
Assert-True ([string]$multiline.attributes.focused -eq 'true') 'Esc keeps host focus and input session'

Tap-Node (Find-Hint $afterEsc 'ACCEPT_CHAT_SEND') 'chat TextInput for window movement'
Send-Key 2030
Send-Key 2025
$moveBefore = Dump-Layout 'move_before'
$beforePosition = Assert-CandidateNearField $moveBefore 'pre-move candidate'
$preMoveField = Find-Hint $moveBefore 'ACCEPT_CHAT_SEND'
$preMoveHostWindowId = [string]$preMoveField.attributes.hostWindowId
$preMoveButtons = @(Get-Nodes $moveBefore | Where-Object {
    [string]$_.attributes.hostWindowId -eq $preMoveHostWindowId -and
    [string]$_.attributes.type -eq 'Button' -and [string]$_.attributes.clickable -eq 'true' -and
    [string]$_.attributes.bounds -match '^\[\d+,\d+\]\[\d+,\d+\]$' -and
    (Get-Bounds $_).Y2 -lt $beforePosition.Field.Y1
})
if ($preMoveButtons.Count -lt 3) { throw 'Host title controls not found for window movement.' }
$titleY = (Get-Bounds $preMoveButtons[0]).CY
Invoke-Hdc @('shell', 'uitest', 'uiInput', 'swipe', $beforePosition.Field.CX, $titleY,
    ($beforePosition.Field.CX + 400), ($titleY + 200), 1000) | Out-Null
Start-Sleep -Seconds 2
$moveAfter = Dump-Layout 'move_after'
$afterPosition = Assert-CandidateNearField $moveAfter 'post-move candidate'
$fieldDx = $afterPosition.Field.X1 - $beforePosition.Field.X1
$fieldDy = $afterPosition.Field.Y1 - $beforePosition.Field.Y1
$candidateDx = $afterPosition.Candidate.X1 - $beforePosition.Candidate.X1
$candidateDy = $afterPosition.Candidate.Y1 - $beforePosition.Candidate.Y1
Assert-True (([Math]::Abs($fieldDx) + [Math]::Abs($fieldDy)) -ge 100) 'host window actually moved'
Assert-True ([Math]::Abs($candidateDx - $fieldDx) -le 30 -and [Math]::Abs($candidateDy - $fieldDy) -le 30) `
    'candidate follows host window movement without stale coordinates'
Capture-Screen 'move_after'

$nodes = Get-Nodes $moveAfter
$hostField = Find-Hint $moveAfter 'ACCEPT_CHAT_SEND'
$hostWindowId = [string]$hostField.attributes.hostWindowId
$titleTop = $afterPosition.Field.Y1
$titleButtons = @($nodes | Where-Object {
    [string]$_.attributes.hostWindowId -eq $hostWindowId -and
    [string]$_.attributes.type -eq 'Button' -and [string]$_.attributes.clickable -eq 'true' -and
    (Get-Bounds $_).Y1 -le $titleTop + 60
} | Sort-Object { (Get-Bounds $_).CX })
if ($titleButtons.Count -lt 3) { throw 'Window resize/maximize control not found.' }
$resizeButton = $titleButtons[$titleButtons.Count - 3]
Tap-Node $resizeButton 'window resize/maximize control'
Start-Sleep -Seconds 2
$resizeAfter = Dump-Layout 'resize_after'
$resizedPosition = Assert-CandidateNearField $resizeAfter 'post-resize candidate'
Assert-True ($resizedPosition.Field.Y1 -ne $afterPosition.Field.Y1 -or
    ($resizedPosition.Field.X2 - $resizedPosition.Field.X1) -ne ($afterPosition.Field.X2 - $afterPosition.Field.X1)) `
    'host window geometry changed after resize/maximize'
Capture-Screen 'resize_after'

Invoke-Hdc @('shell', 'aa', 'start', '-b', 'com.huawei.hmos.browser', '-a', 'MainAbility') | Out-Null
Start-Sleep -Seconds 3
$browser = Dump-Layout 'browser_after_switch'
Assert-True ($null -eq (Find-Text $browser $firstCandidate)) 'application switch removes the old candidate window'
Capture-Screen 'browser_after_switch'

$browserPort = 18765
$browserFixtureDir = Join-Path $repoRoot 'tools\ime-acceptance-client'
$browserServer = $null
try {
    $browserServer = Start-Process -FilePath 'python' `
        -ArgumentList @('-m', 'http.server', "$browserPort", '--bind', '127.0.0.1', '--directory', $browserFixtureDir) `
        -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 1
    if ($browserServer.HasExited) { throw 'Local browser acceptance server exited before the test started.' }

    Invoke-Hdc @('rport', "tcp:$browserPort", "tcp:$browserPort") | Out-Null
    $browserRunId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-Hdc @(
        'shell', 'aa', 'start', '-A', 'ohos.want.action.viewData',
        '-U', "http://127.0.0.1:$browserPort/stage4-browser-input.html?run=$browserRunId"
    ) | Out-Null
    Start-Sleep -Seconds 4
    $browserPage = Dump-Layout 'browser_page'
    $browserField = Get-Nodes $browserPage | Where-Object {
        [string]$_.attributes.type -eq 'textField' -and [string]$_.attributes.visible -eq 'true' -and
        [string]$_.attributes.hint -match 'STAGE4_BROWSER_TEXT' -and
        [string]$_.attributes.bounds -match '^\[\d+,\d+\]\[\d+,\d+\]$'
    } | Select-Object -First 1
    Assert-True ([string]$browserField.attributes.text -eq '') 'local browser fixture starts with an empty field'
    Tap-Node $browserField 'local browser acceptance text field'
    Send-Key 2070
    for ($index = 0; $index -lt 30; $index += 1) {
        Invoke-Hdc @('shell', 'uitest', 'uiInput', 'keyEvent', 2055) | Out-Null
        Start-Sleep -Milliseconds 40
    }
    Send-Key 2030
    Send-Key 2025
    $browserCandidate = Dump-Layout 'browser_candidate'
    $browserCandidateNode = Find-Text $browserCandidate $firstCandidate
    $browserFocusedField = Get-Nodes $browserCandidate | Where-Object {
        [string]$_.attributes.type -eq 'textField' -and [string]$_.attributes.visible -eq 'true' -and
        [string]$_.attributes.focused -eq 'true'
    } | Select-Object -First 1
    Assert-True ($null -ne $browserCandidateNode) 'formal candidate appears in a system-browser web text field'
    Assert-True ($null -ne $browserFocusedField) 'browser web field keeps focus while candidate is visible'
    Capture-Screen 'browser_candidate'
    Tap-Node $browserCandidateNode 'browser mouse candidate 1'
    $browserCommit = Dump-Layout 'browser_mouse_commit'
    $browserCommittedField = Get-Nodes $browserCommit | Where-Object {
        [string]$_.attributes.type -eq 'textField' -and [string]$_.attributes.visible -eq 'true' -and
        [string]$_.attributes.focused -eq 'true'
    } | Select-Object -First 1
    $browserCommittedText = [string]$browserCommittedField.attributes.text
    $browserCandidateCommitCount = [regex]::Matches(
        $browserCommittedText,
        [regex]::Escape($firstCandidateText)
    ).Count
    Assert-True ($browserCandidateCommitCount -eq 1 -and $browserCommittedText.EndsWith($firstCandidateText)) `
        'browser mouse click commits one Chinese candidate (emulator raw-key echo excluded)'
    Assert-True ($null -eq (Find-Text $browserCommit $firstCandidate)) 'browser candidate hides after commit'
    Capture-Screen 'browser_mouse_commit'
} finally {
    if ($null -ne $browserServer -and -not $browserServer.HasExited) {
        Stop-Process -Id $browserServer.Id -Force
    }
    & $hdc -t $script:Target fport rm "tcp:$browserPort" "tcp:$browserPort" 2>&1 | Out-Null
}

$allLog = Invoke-Hdc @('shell', 'hilog', '-x')
$stageLog = @($allLog | Where-Object {
    $_ -match 'FloatingCandidate|SoftKeyboardPanelOwner|InputMethodLifecycle|InputPanelController|KeyboardController'
})
$stageLog | Set-Content -LiteralPath (Join-Path $outDir 'stage4.log') -Encoding UTF8
$text = $stageLog -join "`n"
$panelInitializationLog = if (
    $text -match 'candidate panel created: owner=CANDIDATE_WINDOW' -and
    $text -match 'candidate panel content ready'
) { 'OBSERVED' } else { 'REUSED_SYSTEM_PROCESS' }
Write-Host "INFO: candidate panel initialization log=$panelInitializationLog"
Assert-True ($text -match 'candidate panel shown') 'candidate panel was shown'
Assert-True ($text -match 'candidate panel hidden') 'candidate panel was hidden on terminal actions'
Assert-True ($text -match 'mouse candidate commit: index=0, success=true') 'mouse selection used the formal commit chain'
Assert-True ($text -match 'state=HARDWARE_READY, sessionActive=true, editorConnected=true, keyboardVisible=false') `
    'session stayed HARDWARE_READY without a fixed keyboard'
Assert-True ($text -notmatch 'floating candidate fallback|fatal|panic|crash|ENGINE_INTERNAL_ERROR') `
    'no floating fallback or fatal runtime marker occurred'
Assert-True ($text -notmatch 'keyboard panel created|keyboard panel visible') 'fixed keyboard remained absent'

Invoke-Hdc @('shell', 'ime', '-s', $systemImeBundle) | Out-Null
$summary = [ordered]@{
    result = 'PASS'
    route = 'A_SOFT_KEYBOARD_FLAG_CANDIDATE'
    candidatePanelInitializationLog = $panelInitializationLog
    target = $script:Target
    deviceType = $environment.deviceType
    candidateNearCursor = 'PASS'
    mouseCommit = 'PASS'
    numericCommitParity = 'PASS'
    escHide = 'PASS'
    focusRetention = 'PASS'
    windowMove = 'PASS'
    windowResize = 'PASS'
    applicationSwitchCleanup = 'PASS'
    fixedKeyboardAbsent = 'PASS'
    browserFormalChineseCandidate = 'PASS_LOCAL_HTTP_BROWSER_TEXT_FIELD'
    browserCandidateCapability = 'PASS_STAGE1_ISOLATED_PROBE_AND_STAGE4_FORMAL_RUNTIME'
    phoneTabletDeviceRegression = 'NOT_RUN_BY_THIS_SCRIPT'
    realUsbBluetoothKeyboard = 'NOT_RUN_EMULATOR_INPUT_INJECTION'
    arm64TwoInOne = 'NOT_RUN_X86_64_EMULATOR'
    signedRelease = 'NOT_RUN_UNSIGNED_RELEASE_HAP'
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'summary.json') -Encoding UTF8
Write-Host "COMPUTER_STAGE4_RESULT=PASS evidence=$outDir"
