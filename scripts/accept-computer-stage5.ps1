param(
    [string]$Target = '',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\2026-08-06-computer-stage5\signed-release-device',
    [switch]$SkipBuild,
    [switch]$SkipDevice
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$signedHap = Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
$unsignedHap = Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'

function Assert-SourceContains([string]$Path, [string]$Pattern, [string]$Description) {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot $Path) -Raw -Encoding UTF8
    if ($text -notmatch $Pattern) { throw "Source gate failed: $Description" }
    Write-Host "PASS: $Description"
}

Assert-SourceContains 'entry\src\main\module.json5' '"2in1"' 'formal module declares 2in1'
Assert-SourceContains 'entry\src\main\module.json5' `
    '"name"\s*:\s*"ohos\.extension\.input_method"' `
    'input-method extension declares the standard subtype metadata'
Assert-SourceContains 'entry\src\main\module.json5' `
    '"resource"\s*:\s*"\$profile:stage0_input_method"' `
    'input-method extension references the subtype profile'
Assert-SourceContains 'entry\src\main\ets\inputmethod\Stage0InputMethodAbilityBase.ets' `
    "keyboardDelegate\.on\('keyEvent'" 'IME subscribes to the modern physical-key channel'
Assert-SourceContains 'entry\src\main\ets\inputmethod\Stage0InputMethodAbilityBase.ets' `
    "keyboardDelegate\.on\('keyDown'" 'IME subscribes to the PC-compatible keyDown channel'
Assert-SourceContains 'entry\src\main\ets\inputmethod\Stage0InputMethodAbilityBase.ets' `
    "keyboardDelegate\.on\('keyUp'" 'IME subscribes to the PC-compatible keyUp channel'
$subtypeProfilePath = Join-Path $repoRoot 'entry\src\main\resources\base\profile\stage0_input_method.json'
$subtypeProfile = Get-Content -LiteralPath $subtypeProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedSubtypeIds = @(
    'shuangyu_quanpin_zh_cn',
    'shuangyu_zh_cn',
    'shuangyu_yinxing_zh_cn',
    'shuangyu_en_us'
)
$expectedSubtypeModes = @('lower', 'double', 'wubi', 'lower')
$actualSubtypeIds = @($subtypeProfile.subtypes | ForEach-Object { [string]$_.id })
if (($actualSubtypeIds -join '|') -ne ($expectedSubtypeIds -join '|')) {
    throw "Source gate failed: subtype order is invalid: $($actualSubtypeIds -join ', ')"
}
$invalidSubtypeLocales = @($subtypeProfile.subtypes | Where-Object {
    $expectedLocale = if ([string]$_.id -eq 'shuangyu_en_us') { 'en-US' } else { 'zh-CN' }
    [string]$_.locale -ne $expectedLocale
})
if ($invalidSubtypeLocales.Count -ne 0) {
    throw 'Source gate failed: one or more input-method subtype locales are invalid'
}
for ($index = 0; $index -lt $expectedSubtypeModes.Count; $index++) {
    if ([string]$subtypeProfile.subtypes[$index].mode -ne $expectedSubtypeModes[$index]) {
        throw "Source gate failed: subtype mode is invalid for $($expectedSubtypeIds[$index])"
    }
}
Write-Host 'PASS: subtype profile declares ordered 全拼/双拼/音形/英文 choices'
Assert-SourceContains 'entry\src\main\ets\domain\display\InputPresentationMode.ets' `
    "normalizedDeviceType === 'tablet' && physicalKeyboardPresent" `
    'AUTO routes connected-keyboard Tablet to hardware mode'
Assert-SourceContains 'entry\src\main\ets\presentation\candidate\FloatingCandidateRoot.ets' `
    'Text\(this\.candidateText' 'floating panel renders candidate text'
if ((Get-Content -LiteralPath (Join-Path $repoRoot `
        'entry\src\main\ets\presentation\candidate\FloatingCandidateRoot.ets') -Raw -Encoding UTF8) -match `
    'preeditDisplayText|TextDecorationType\.Underline') {
    throw 'Source gate failed: floating candidate still renders preedit text'
}
Write-Host 'PASS: floating panel excludes preedit letters'

if (-not $SkipBuild) {
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
    Push-Location $repoRoot
    try {
        & $hvigor --no-daemon --mode module -p module=entry@default test
        if ($LASTEXITCODE -ne 0) { throw "ArkTS tests failed: $LASTEXITCODE" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            (Join-Path $repoRoot 'scripts\build-hap.ps1') -SkipRust -BuildMode debug
        if ($LASTEXITCODE -ne 0) { throw "internalDebug build failed: $LASTEXITCODE" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            (Join-Path $repoRoot 'scripts\build-hap.ps1') -SkipRust -BuildMode release -Product default
        if ($LASTEXITCODE -ne 0) { throw "Release build failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

foreach ($hap in @($unsignedHap, $signedHap)) {
    if (-not (Test-Path -LiteralPath $hap -PathType Leaf)) { throw "Release HAP not found: $hap" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $repoRoot 'scripts\verify-release-hap.ps1') -HapPath $hap
    if ($LASTEXITCODE -ne 0) { throw "Release HAP gate failed: $hap" }
}

if (-not $SkipDevice) {
    if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
    if ($Target.Length -eq 0) {
        $Target = ((& $hdc list targets) | Select-Object -First 1).Trim()
    }
    if ($Target.Length -eq 0) { throw 'No connected target found.' }
    $deviceType = ((& $hdc -t $Target shell param get const.product.devicetype) -join '').Trim()
    if ($deviceType -ne '2in1') { throw "Stage 5 signed Release target must be 2in1; actual=$deviceType" }
    & $hdc -t $Target install -r $signedHap | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "signed Release install failed: $LASTEXITCODE" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $repoRoot 'scripts\accept-computer-stage4.ps1') -Target $Target `
        -EvidenceDir $EvidenceDir -SkipBuild -SkipInstall
    if ($LASTEXITCODE -ne 0) { throw "signed Release computer device acceptance failed: $LASTEXITCODE" }
    $resolvedEvidenceDir = if ([IO.Path]::IsPathRooted($EvidenceDir)) {
        [IO.Path]::GetFullPath($EvidenceDir)
    } else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
    }
    $environmentPath = Join-Path $resolvedEvidenceDir 'environment.json'
    $environment = Get-Content -LiteralPath $environmentPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $environment | Add-Member -NotePropertyName hapFieldsMeaning `
        -NotePropertyValue 'accept-computer-stage4 automation reference artifact; installation was skipped' -Force
    $environment | Add-Member -NotePropertyName installedHap `
        -NotePropertyValue ([IO.Path]::GetFileName($signedHap)) -Force
    $environment | Add-Member -NotePropertyName installedHapBytes `
        -NotePropertyValue (Get-Item -LiteralPath $signedHap).Length -Force
    $environment | Add-Member -NotePropertyName installedHapSha256 `
        -NotePropertyValue (Get-FileHash -LiteralPath $signedHap -Algorithm SHA256).Hash.ToLowerInvariant() -Force
    $environment | ConvertTo-Json | Set-Content -LiteralPath $environmentPath -Encoding UTF8
    $summaryPath = Join-Path $resolvedEvidenceDir 'summary.json'
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $summary.signedRelease = 'PASS_PREINSTALLED_SIGNED_RELEASE_WITH_SKIP_INSTALL'
    $summary | ConvertTo-Json | Set-Content -LiteralPath $summaryPath -Encoding UTF8
}

Write-Host 'COMPUTER_STAGE5_RESULT=PASS'
Write-Host 'REAL_USB_BLUETOOTH_KEYBOARD=NOT_RUN'
Write-Host 'ARM64_2IN1=NOT_RUN'
