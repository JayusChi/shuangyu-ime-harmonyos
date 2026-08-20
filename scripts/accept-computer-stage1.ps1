param(
    [string]$Target = '',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\2026-08-05-computer-stage1\device',
    [switch]$SkipBuild,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$script:imeBundle = 'com.corrosion.shuangyuime'
$script:clientBundle = 'com.example.shuangyuime.acceptance'
$script:systemImeBundle = 'com.huawei.hmos.inputmethod'
$candidateOneText = '1 ' + [string][char]0x4F60
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

function Invoke-HdcTarget {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed ($LASTEXITCODE): $($arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Resolve-2in1Target {
    if (-not [string]::IsNullOrWhiteSpace($script:Target)) {
        $type = ((Invoke-HdcTarget shell param get const.product.devicetype) -join '').Trim()
        if ($type -ne '2in1') { throw "Target $script:Target is '$type', expected '2in1'." }
        return
    }
    foreach ($candidate in @(& $script:hdc list targets 2>&1)) {
        $serial = ([string]$candidate).Trim()
        if ([string]::IsNullOrWhiteSpace($serial) -or $serial -match 'Empty') { continue }
        $script:Target = $serial
        $type = ((Invoke-HdcTarget shell param get const.product.devicetype) -join '').Trim()
        if ($type -eq '2in1') { return }
    }
    throw 'No connected 2in1 target found.'
}

function Get-Nodes([string]$Path) {
    $root = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nodes = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) { $script:Stage1Nodes.Add($node) | Out-Null }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:Stage1Nodes = $nodes
    Visit $root
    return $nodes.ToArray()
}

function Get-Bounds($Node) {
    $match = [regex]::Match([string]$Node.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Invalid bounds: $($Node.attributes.bounds)" }
    return [pscustomobject]@{
        CX = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Dump-Layout([string]$Name) {
    $remote = "/data/local/tmp/computer_stage1_$Name.json"
    Invoke-HdcTarget shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $script:outDir "$Name.json"
    Invoke-HdcTarget file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen([string]$Name) {
    $remote = "/data/local/tmp/computer_stage1_$Name.jpeg"
    Invoke-HdcTarget shell snapshot_display -f $remote | Out-Null
    Invoke-HdcTarget file recv $remote (Join-Path $script:outDir "$Name.jpeg") | Out-Null
}

function Tap-Node($Node, [string]$Description) {
    if ($null -eq $Node) { throw "Node not found: $Description" }
    $bounds = Get-Bounds $Node
    Invoke-HdcTarget shell uitest uiInput click $bounds.CX $bounds.CY | Out-Null
    Start-Sleep -Milliseconds 600
}

function Find-Hint([string]$Layout, [string]$Hint) {
    return Get-Nodes $Layout | Where-Object {
        [string]$_.attributes.hint -eq $Hint -and [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
}

function Find-Text([string]$Layout, [string]$Text) {
    return Get-Nodes $Layout | Where-Object {
        [string]$_.attributes.text -eq $Text -and [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
}

function Save-ProbeLog([string]$Name) {
    $lines = Invoke-HdcTarget shell hilog -x
    $probe = @($lines | Where-Object { $_ -match 'ComputerStage1Probe|InputPanelController' })
    $probe | Set-Content -LiteralPath (Join-Path $script:outDir "$Name.log") -Encoding UTF8
    return ($probe -join "`n")
}

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Description) {
    if ($Text -notmatch $Pattern) { throw "Missing evidence: $Description ($Pattern)" }
    Write-Host "PASS: $Description"
}

if (-not (Test-Path -LiteralPath $script:hdc -PathType Leaf)) { throw "hdc not found: $script:hdc" }
$script:Target = $Target
Resolve-2in1Target
$script:outDir = $outDir

$environment = [ordered]@{
    target = $script:Target
    deviceType = ((Invoke-HdcTarget shell param get const.product.devicetype) -join '').Trim()
    sdkApiVersion = ((Invoke-HdcTarget shell param get const.ohos.apiversion) -join '').Trim()
    model = ((Invoke-HdcTarget shell param get const.product.model) -join '').Trim()
    abi = ((Invoke-HdcTarget shell uname -m) -join '').Trim()
    capturedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
}
$environment | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'environment.json') -Encoding UTF8

if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\build-hap.ps1') `
        -SkipRust -Clean -BuildMode debug
    if ($LASTEXITCODE -ne 0) { throw "internalDebug build failed: $LASTEXITCODE" }
}

$hap = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
$clientHap = Join-Path $repoRoot 'tools\ime-acceptance-client\entry\build\default\outputs\default\entry-default-unsigned.hap'
if (-not $SkipInstall) {
    Invoke-HdcTarget install -r $hap | Out-Null
    Invoke-HdcTarget install -r $clientHap | Out-Null
}

Invoke-HdcTarget shell ime -e $script:imeBundle -f | Out-Null
Invoke-HdcTarget shell ime -s $script:imeBundle | Out-Null
Invoke-HdcTarget shell hilog -r | Out-Null
Invoke-HdcTarget shell aa force-stop $script:clientBundle | Out-Null
Invoke-HdcTarget shell aa start -b $script:clientBundle -a EntryAbility | Out-Null
Start-Sleep -Seconds 2

$clientBefore = Dump-Layout 'client_before'
Tap-Node (Find-Hint $clientBefore 'ACCEPT_CHAT_SEND') 'ArkUI TextInput'
Start-Sleep -Seconds 2
$candidate = Dump-Layout 'textinput_candidate'
Tap-Node (Find-Text $candidate $candidateOneText) 'candidate panel mouse target'
Invoke-HdcTarget shell uitest uiInput keyEvent 2017 | Out-Null
Invoke-HdcTarget shell uitest uiInput keyEvent 2018 | Out-Null
Start-Sleep -Seconds 1
$afterKeys = Dump-Layout 'textinput_after_click_and_keys'
$chat = Find-Hint $afterKeys 'ACCEPT_CHAT_SEND'
if ([string]$chat.attributes.text -ne 'ab' -or [string]$chat.attributes.focused -ne 'true') {
    throw "TextInput focus/key continuity failed: text='$($chat.attributes.text)' focused='$($chat.attributes.focused)'"
}
Capture-Screen 'textinput_candidate'
$textInputLog = Save-ProbeLog 'textinput'

Tap-Node (Find-Hint $afterKeys 'ACCEPT_MULTILINE') 'ArkUI TextArea'
Start-Sleep -Seconds 2
Invoke-HdcTarget shell uitest uiInput keyEvent 2019 | Out-Null
Start-Sleep -Milliseconds 600
$textAreaLayout = Dump-Layout 'textarea_candidate'
$textAreaLog = Save-ProbeLog 'textarea'

Invoke-HdcTarget shell aa start -b com.huawei.hmos.browser -a MainAbility | Out-Null
Start-Sleep -Seconds 4
$browserBefore = Dump-Layout 'browser_before'
Tap-Node (Find-Hint $browserBefore $browserAddressHint) 'system browser address field'
Start-Sleep -Seconds 2
Invoke-HdcTarget shell uitest uiInput keyEvent 2020 | Out-Null
Start-Sleep -Milliseconds 700
$browserCandidate = Dump-Layout 'browser_candidate'
Capture-Screen 'browser_candidate'
$browserLog = Save-ProbeLog 'browser'

Invoke-HdcTarget shell ime -s $script:systemImeBundle | Out-Null
Start-Sleep -Seconds 2
$finalLog = Save-ProbeLog 'complete'

Assert-Contains $textInputLog 'inputStart .*fixedPanelCreateCount=0 deviceType=2in1 sdkApiVersion=24' '2in1/API/fixed-panel isolation'
Assert-Contains $textInputLog 'physicalKeyboardInventory deviceCount=\d+ alphabeticCount=[1-9]' 'alphabetic hardware keyboard detected'
Assert-Contains $textInputLog 'createPanel panel=CANDIDATE result=PASS' 'candidate panel creation'
Assert-Contains $textInputLog 'setUiContent panel=CANDIDATE result=PASS' 'candidate content loading'
Assert-Contains $textInputLog 'resize panel=CANDIDATE .* result=PASS' 'candidate resize'
Assert-Contains $textInputLog 'moveTo panel=CANDIDATE .* result=PASS' 'candidate move'
Assert-Contains $textInputLog 'show panel=CANDIDATE pass=1 result=PASS' 'candidate initial show'
Assert-Contains $textInputLog 'hide panel=CANDIDATE result=PASS' 'candidate hide'
Assert-Contains $textInputLog 'show panel=CANDIDATE pass=2 result=PASS' 'candidate re-show'
Assert-Contains $textInputLog 'mouseClick panel=CANDIDATE candidateIndex=0' 'candidate mouse click'
Assert-Contains $textInputLog 'afterPanelClick=true result=PASS' 'host focus retained after mouse click'
Assert-Contains $textAreaLog 'cursorContextChange x=\d+ y=\d+ height=[1-9]\d*' 'TextArea cursor anchor'
Assert-Contains $browserLog 'cursorContextChange x=\d+ y=\d+ height=[1-9]\d*' 'browser cursor anchor'
Assert-Contains $finalLog 'destroyPanel panel=CANDIDATE source=inputStop result=PASS' 'candidate panel destruction'
if ($finalLog -match 'InputPanelController') { throw 'Fixed keyboard controller unexpectedly ran on the isolated 2in1 probe.' }

$summary = [ordered]@{
    route = 'A'
    candidatePanel = 'PASS'
    statusBarFallback = 'NOT_RUN_CANDIDATE_PANEL_PASSED'
    textInput = 'PASS'
    textArea = 'PASS'
    browser = 'PASS'
    mouseClick = 'PASS'
    focusRetention = 'PASS'
    fixedPanelCreateCount = 0
    realUsbBluetoothKeyboard = 'NOT_RUN_EMULATOR_REPORTED_ALPHABETIC_KEYBOARD'
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'summary.json') -Encoding UTF8
Write-Host "COMPUTER_STAGE1_RESULT=PASS route=A evidence=$outDir"
