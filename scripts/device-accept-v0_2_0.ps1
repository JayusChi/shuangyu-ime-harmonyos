param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$HapPath = '',
    [string]$ClientHapPath = '',
    [string]$EvidenceDir = 'docs\evidence\2026-07-29-v0.2.0-acceptance\device',
    [ValidateRange(10, 2000)]
    [int]$StressIterations = 200,
    [ValidateRange(0, 30)]
    [int]$SoakMinutes = 1,
    [ValidateRange(1, 100)]
    [int]$PreciseBurst = 10,
    [switch]$SkipInstall,
    [switch]$StressOnly,
    [switch]$PrepareYinxing
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$imeBundle = 'com.corrosion.shuangyuime'
$clientBundle = 'com.example.shuangyuime.acceptance'
$abaText = -join @([char]0x963F, [char]0x7238)
$sendLabel = -join @([char]0x53D1, [char]0x9001)
$goLabel = -join @([char]0x524D, [char]0x5F80)
$searchLabel = -join @([char]0x641C, [char]0x7D22)
$enterLabel = -join @([char]0x56DE, [char]0x8F66)
$chineseModeLabel = [string][char]0x4E2D
$englishModeLabel = [string][char]0x82F1
$deleteLabel = -join @([char]0x5220, [char]0x9664)
$yinxingLabel = -join @([char]0x5C0F, [char]0x9E64, [char]0x97F3, [char]0x5F62)
$outDir = if ([IO.Path]::IsPathRooted($EvidenceDir)) {
    [IO.Path]::GetFullPath($EvidenceDir)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}
if (-not $outDir.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write evidence outside the repository: $outDir"
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($HapPath)) {
    $HapPath = Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
}
if ([string]::IsNullOrWhiteSpace($ClientHapPath)) {
    $ClientHapPath = Join-Path $repoRoot 'tools\ime-acceptance-client\entry\build\default\outputs\default\entry-default-unsigned.hap'
}

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed ($LASTEXITCODE): $($arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Get-Nodes([string]$Path) {
    $root = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nodes = [Collections.Generic.List[object]]::new()
    function Visit($node) {
        if ($null -ne $node -and $null -ne $node.attributes) {
            $script:AcceptanceNodes.Add($node) | Out-Null
        }
        foreach ($child in @($node.children)) { Visit $child }
    }
    $script:AcceptanceNodes = $nodes
    Visit $root
    return $nodes.ToArray()
}

function Get-Bounds($Node) {
    $match = [regex]::Match([string]$Node.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "invalid bounds: $($Node.attributes.bounds)" }
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
    $remote = "/data/local/tmp/v020_$Name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $script:outDir "$Name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen([string]$Name) {
    $remote = "/data/local/tmp/v020_$Name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    Invoke-Hdc file recv $remote (Join-Path $script:outDir "$Name.png") | Out-Null
}

function Find-Hint([string]$Layout, [string]$Hint) {
    return Get-Nodes $Layout | Where-Object {
        [string]$_.attributes.hint -eq $Hint -and [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
}

function Find-KeyboardText([string]$Layout, [string]$Text) {
    $minimumY = [int]($script:screenHeight * 0.55)
    return Get-Nodes $Layout | Where-Object {
        [string]$_.attributes.text -ceq $Text -and [string]$_.attributes.visible -eq 'true' -and
        (Get-Bounds $_).Y1 -ge $minimumY
    } | Sort-Object { (Get-Bounds $_).Y1 } -Descending | Select-Object -First 1
}

function Tap-Node($Node, [string]$Description) {
    if ($null -eq $Node) { throw "node not found: $Description" }
    $bounds = Get-Bounds $Node
    Invoke-Hdc shell uitest uiInput click $bounds.CX $bounds.CY | Out-Null
    Start-Sleep -Milliseconds 450
}

function Open-Client {
    Invoke-Hdc shell aa force-stop $script:clientBundle | Out-Null
    Invoke-Hdc shell aa start -b $script:clientBundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
}

function Focus-Field([string]$Hint, [string]$Prefix) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $layout = Dump-Layout "${Prefix}_find_$attempt"
        $field = Find-Hint $layout $Hint
        if ($null -ne $field) {
            Tap-Node $field $Hint
            Start-Sleep -Seconds 1
            return
        }
        Invoke-Hdc shell uitest uiInput swipe ([int]($script:screenWidth / 2)) ([int]($script:screenHeight * 0.78)) `
            ([int]($script:screenWidth / 2)) ([int]($script:screenHeight * 0.28)) 700 | Out-Null
        Start-Sleep -Milliseconds 450
    }
    throw "field not visible after scrolling: $Hint"
}

function Press-Key([string]$Text, [string]$Prefix) {
    $layout = Dump-Layout "${Prefix}_$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    Tap-Node (Find-KeyboardText $layout $Text) "keyboard '$Text'"
}

function Type-YinxingAba([string]$Prefix) {
    foreach ($key in @('A', 'A', 'B', 'A')) {
        Press-Key $key "${Prefix}_key"
        Start-Sleep -Milliseconds 280
    }
}

function Ensure-ChineseKeyboard([string]$Prefix) {
    $layout = Dump-Layout "${Prefix}_mode_check"
    if ($null -ne (Find-KeyboardText $layout 'A')) { return }
    $languageKey = Find-KeyboardText $layout $script:englishModeLabel
    if ($null -eq $languageKey) { throw 'language-mode key is missing' }
    Tap-Node $languageKey 'switch to Chinese keyboard'
    Start-Sleep -Seconds 1
    $confirmed = Dump-Layout "${Prefix}_mode_confirmed"
    if ($null -eq (Find-KeyboardText $confirmed 'A')) { throw 'Chinese keyboard did not become active' }
}

function Assert-FieldText([string]$Hint, [string]$Expected, [string]$Name) {
    $layout = Dump-Layout "${Name}_assert"
    $field = Find-Hint $layout $Hint
    if ($null -eq $field) { throw "$Name field is not visible for assertion" }
    $actual = [string]$field.attributes.text
    if ($actual -cne $Expected) {
        throw "$Name text mismatch: expected '$Expected', got '$actual'"
    }
    Capture-Screen $Name
}

function Get-ImeRssKb {
    $expectedProcess = $script:imeBundle + ':inputMethod'
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $processLines = & $script:hdc -t $script:Target shell ps -A -o PID,RSS,NAME 2>&1
        foreach ($line in $processLines) {
            $parts = ([string]$line).Trim() -split '\s+'
            if ($parts.Count -ge 3 -and $parts[$parts.Count - 1] -eq $expectedProcess) {
                return [int]$parts[1]
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'inputMethod process is not running after retries'
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
if (-not $SkipInstall) {
    if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) { throw "signed HAP not found: $HapPath" }
    if (-not (Test-Path -LiteralPath $ClientHapPath -PathType Leaf)) { throw "client HAP not found: $ClientHapPath" }
    Invoke-Hdc install -r ([IO.Path]::GetFullPath($HapPath)) | Out-Null
    Invoke-Hdc install -r ([IO.Path]::GetFullPath($ClientHapPath)) | Out-Null
}

if ($PrepareYinxing) {
    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Invoke-Hdc shell bm clean -n $imeBundle -d | Out-Null
    Invoke-Hdc shell bm clean -n $clientBundle -d | Out-Null
    Invoke-Hdc shell ime -e $imeBundle -f | Out-Null
    Invoke-Hdc shell ime -s $imeBundle | Out-Null
    Invoke-Hdc shell aa start -b $imeBundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 3
    $settingsLayout = Dump-Layout 'prepare_yinxing_settings'
    $schemeNode = Get-Nodes $settingsLayout | Where-Object {
        [string]$_.attributes.text -eq $yinxingLabel -and
        [string]$_.attributes.clickable -eq 'true'
    } | Select-Object -First 1
    Tap-Node $schemeNode 'xiaohe-yinxing scheme'
    Start-Sleep -Seconds 6
    $selectedLayout = Dump-Layout 'prepare_yinxing_selected'
    $selectedNode = Get-Nodes $selectedLayout | Where-Object {
        [string]$_.attributes.text -eq $yinxingLabel
    } | Select-Object -First 1
    if ($null -eq $selectedNode -or [string]$selectedNode.attributes.backgroundColor -ne '#FFDCEBFF') {
        throw 'xiaohe-yinxing did not become the selected scheme'
    }
    Capture-Screen 'prepare_yinxing_selected'
    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
}

$bundleDump = (Invoke-Hdc shell bm dump -n $imeBundle) -join "`n"
if ($bundleDump -notmatch '"versionCode": 2000000' -or $bundleDump -notmatch '"versionName": "0\.2\.0"') {
    throw 'installed IME is not version 0.2.0/2000000'
}
Invoke-Hdc shell ime -e $imeBundle -f | Out-Null
Invoke-Hdc shell ime -s $imeBundle | Out-Null

$screen = (Invoke-Hdc shell hidumper -s RenderService -a screen) -join "`n"
if ($screen -notmatch 'activeMode:\s*(\d+)x(\d+)') { throw 'unable to read active display resolution' }
$script:screenWidth = [int]$Matches[1]
$script:screenHeight = [int]$Matches[2]
$orientation = if ($script:screenWidth -gt $script:screenHeight) { 'landscape' } else { 'portrait' }

Invoke-Hdc shell hilog -r | Out-Null

if (-not $StressOnly) {
    Open-Client
    Focus-Field 'ACCEPT_CHAT_SEND' 'chat'
    Ensure-ChineseKeyboard 'chat'
    $chatKeyboard = Dump-Layout 'chat_keyboard'
    if ($null -eq (Find-KeyboardText $chatKeyboard $sendLabel)) { throw 'chat editor did not expose Send enter action' }
    Type-YinxingAba 'chat'
    Assert-FieldText 'ACCEPT_CHAT_SEND' $abaText 'chat'

    Open-Client
    Focus-Field 'ACCEPT_BROWSER_URL' 'browser'
    $browserKeyboard = Dump-Layout 'browser_keyboard'
    if ($null -eq (Find-KeyboardText $browserKeyboard $goLabel)) { throw 'URL editor did not expose Go enter action' }
    foreach ($key in @('a', 'b', 'c')) { Press-Key $key 'browser_key' }
    $browserLayout = Dump-Layout 'browser_assert'
    $browserField = Find-Hint $browserLayout 'ACCEPT_BROWSER_URL'
    if ([string]$browserField.attributes.text -notmatch '^(?i)abc$') {
        throw "browser editor text mismatch: $($browserField.attributes.text)"
    }
    Capture-Screen 'browser'

    Open-Client
    Focus-Field 'ACCEPT_SEARCH' 'search'
    Ensure-ChineseKeyboard 'search'
    $searchKeyboard = Dump-Layout 'search_keyboard'
    if ($null -eq (Find-KeyboardText $searchKeyboard $searchLabel)) { throw 'search editor did not expose Search enter action' }
    Type-YinxingAba 'search'
    Assert-FieldText 'ACCEPT_SEARCH' $abaText 'search'

    Open-Client
    Focus-Field 'ACCEPT_MULTILINE' 'multiline'
    Ensure-ChineseKeyboard 'multiline'
    $multilineKeyboard = Dump-Layout 'multiline_keyboard'
    if ($null -eq (Find-KeyboardText $multilineKeyboard $enterLabel)) { throw 'multiline editor did not expose newline enter action' }
    Type-YinxingAba 'multiline_first'
    Press-Key $enterLabel 'multiline_newline'
    Type-YinxingAba 'multiline_second'
    Assert-FieldText 'ACCEPT_MULTILINE' "$abaText`n$abaText" 'multiline'

    Open-Client
    Focus-Field 'ACCEPT_CHAT_SEND' 'switch'
    Ensure-ChineseKeyboard 'switch'
    Type-YinxingAba 'switch'
    Invoke-Hdc shell uitest uiInput keyEvent Home | Out-Null
    Start-Sleep -Seconds 1
    Invoke-Hdc shell aa start -b $clientBundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    Assert-FieldText 'ACCEPT_CHAT_SEND' $abaText 'app_switch'

    Open-Client
    Focus-Field 'ACCEPT_CHAT_SEND' 'precise_burst'
    Ensure-ChineseKeyboard 'precise_burst'
    $burstLayout = Dump-Layout 'precise_burst_keyboard'
    $aKey = Find-KeyboardText $burstLayout 'A'
    $bKey = Find-KeyboardText $burstLayout 'B'
    if ($null -eq $aKey -or $null -eq $bKey) { throw 'precise burst keys are missing' }
    $aBounds = Get-Bounds $aKey
    $bBounds = Get-Bounds $bKey
    for ($index = 0; $index -lt $PreciseBurst; $index++) {
        foreach ($point in @($aBounds, $aBounds, $bBounds, $aBounds)) {
            Invoke-Hdc shell uitest uiInput click $point.CX $point.CY | Out-Null
        }
    }
    Start-Sleep -Seconds 3
    Assert-FieldText 'ACCEPT_CHAT_SEND' ($abaText * $PreciseBurst) 'precise_burst'

    Open-Client
    Focus-Field 'ACCEPT_CHAT_SEND' 'backspace_recovery'
    Ensure-ChineseKeyboard 'backspace_recovery'
    foreach ($key in @('A', 'A', 'B')) { Press-Key $key 'backspace_prefix' }
    Press-Key $deleteLabel 'backspace_delete'
    foreach ($key in @('B', 'A')) { Press-Key $key 'backspace_suffix' }
    Assert-FieldText 'ACCEPT_CHAT_SEND' $abaText 'backspace_recovery'

    Open-Client
    Focus-Field 'ACCEPT_CHAT_SEND' 'hide_recover'
    Ensure-ChineseKeyboard 'hide_recover'
    Type-YinxingAba 'hide_recover_first'
    Invoke-Hdc shell uitest uiInput keyEvent Back | Out-Null
    Start-Sleep -Seconds 1
    Focus-Field 'ACCEPT_CHAT_SEND' 'hide_recover_refocus'
    Ensure-ChineseKeyboard 'hide_recover_refocus'
    Type-YinxingAba 'hide_recover_second'
    Assert-FieldText 'ACCEPT_CHAT_SEND' ($abaText + $abaText) 'hide_recover'
}

Open-Client
Focus-Field 'ACCEPT_STRESS_LONG_INPUT' 'stress'
$stressKeyboard = Dump-Layout 'stress_keyboard'
$languageKey = Find-KeyboardText $stressKeyboard $chineseModeLabel
if ($null -ne $languageKey) { Tap-Node $languageKey 'switch stress editor to English' }
Start-Sleep -Seconds 1
$rssBeforeKb = Get-ImeRssKb
$burstCommand = "for i in `$(seq 1 $StressIterations); do uitest uiInput keyEvent 2017; uitest uiInput keyEvent 2018; done"
Invoke-Hdc shell $burstCommand | Out-Null
Start-Sleep -Seconds 2
$rssAfterBurstKb = Get-ImeRssKb

$soakDeadline = (Get-Date).AddMinutes($SoakMinutes)
$soakBursts = 0
while ((Get-Date) -lt $soakDeadline) {
    Invoke-Hdc shell 'for i in $(seq 1 20); do uitest uiInput keyEvent 2017; uitest uiInput keyEvent 2018; done' | Out-Null
    $null = Get-ImeRssKb
    $soakBursts += 1
    Start-Sleep -Seconds 5
}
$rssAfterSoakKb = Get-ImeRssKb
$rssGrowthKb = $rssAfterSoakKb - $rssBeforeKb
if ($rssGrowthKb -gt 131072) {
    throw "inputMethod RSS grew by more than 128 MiB: ${rssGrowthKb} KiB"
}

$fatalLog = ((Invoke-Hdc shell hilog -x) -join "`n") -split "`n" | Where-Object {
    $_ -match 'com\.corrosion\.shuangyuime' -and $_ -match '(?i)fatal|panic|SIGSEGV|process crash'
}
$fatalCount = @($fatalLog).Count
$fatalReport = if ($fatalCount -eq 0) { 'PASS: no fatal, panic, SIGSEGV, or process-crash pattern found.' } else { $fatalLog -join "`n" }
$fatalReport | Set-Content -LiteralPath (Join-Path $outDir 'fatal-scan.log') -Encoding UTF8
if ($fatalCount -gt 0) { throw 'fatal/crash pattern found in IME logs' }
Capture-Screen 'stress_final'

$summary = [ordered]@{
    result = 'PASS'
    target = $Target
    versionName = '0.2.0'
    versionCode = 2000000
    hapBytes = (Get-Item -LiteralPath $HapPath).Length
    hapSha256 = (Get-FileHash -LiteralPath $HapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    resolution = "$($script:screenWidth)x$($script:screenHeight)"
    orientation = $orientation
    independentBundle = $clientBundle
    editorCases = if ($StressOnly) { @() } else { @('chat-send', 'browser-url', 'search', 'multiline', 'precise-burst', 'backspace-recovery', 'hide-recover') }
    appSwitch = if ($StressOnly) { 'NOT_RUN in stress-only mode' } else { 'PASS' }
    stressIterations = $StressIterations
    preciseBurst = if ($StressOnly) { 0 } else { $PreciseBurst }
    soakMinutes = $SoakMinutes
    soakBursts = $soakBursts
    rssBeforeKb = $rssBeforeKb
    rssAfterBurstKb = $rssAfterBurstKb
    rssAfterSoakKb = $rssAfterSoakKb
    rssGrowthKb = $rssGrowthKb
    splitScreen = 'NOT_RUN: current simulator automation exposes no reliable split-screen control'
    physicalArm64 = 'NOT_RUN: no physical device connected'
}
$summary | ConvertTo-Json -Depth 6 | Out-File -LiteralPath (Join-Path $outDir 'acceptance-summary.json') -Encoding utf8
Write-Host 'V0_2_0_DEVICE_ACCEPTANCE_RESULT=PASS'
Write-Host "ORIENTATION=$orientation"
Write-Host "RSS_GROWTH_KB=$rssGrowthKb"
