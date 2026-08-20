param(
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$script:Results = @()

function Add-Result {
    param([string]$Name, [string]$Result, [string]$Detail)
    $script:Results += [PSCustomObject]@{
        Step = $Name
        Result = $Result
        Detail = $Detail
    }
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ''
    Write-Host "== $Name =="
    & $Action
    Add-Result -Name $Name -Result 'PASS' -Detail 'completed'
}

function Assert-FileExists {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Assert-TreeNotContains {
    param(
        [string]$Root,
        [string]$Pattern,
        [string]$Message,
        [string[]]$Extensions
    )
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $Extensions -contains $_.Extension }
    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        if ($content -match $Pattern) {
            throw "$Message Match: $($file.FullName)"
        }
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$etsRoot = Join-Path $repoRoot 'entry\src\main\ets'
$engineRoot = Join-Path $repoRoot 'engine-rust'
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'

Invoke-Step 'Stage 10 required files' {
    $requiredFiles = @(
        'entry\src\main\ets\domain\editor\EditorContext.ets',
        'entry\src\main\ets\infrastructure\ime\EditorAttributeMapper.ets',
        'entry\src\main\ets\application\KeyboardModePolicy.ets',
        'entry\src\main\ets\application\EnglishShiftController.ets',
        'entry\src\main\ets\application\EnterActionPolicy.ets',
        'entry\src\main\ets\presentation\keyboard\layouts\Stage10KeyboardLayouts.ets',
        'entry\src\test\Stage10.test.ets',
        'docs\adr\0010-stage10-editor-context-and-keyboard-mode.md',
        'docs\evidence\stage10\stage10_validation.md'
    )
    foreach ($relativePath in $requiredFiles) {
        Assert-FileExists -Path (Join-Path $repoRoot $relativePath) -Message "Missing stage 10 file: $relativePath"
    }
}

Invoke-Step 'ArkTS unit tests' {
    Assert-FileExists -Path $hvigor -Message "hvigorw not found: $hvigor"
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
    Push-Location $repoRoot
    try {
        & $hvigor --no-daemon --mode module -p module=entry@default test
        if ($LASTEXITCODE -ne 0) {
            throw "ArkTS unit tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 9 full regression (Rust fmt, clippy, workspace tests, Native all ABI)' {
    & (Join-Path $PSScriptRoot 'verify-stage9.ps1') -SkipHap -DevEcoRoot $DevEcoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Stage 9 regression failed with exit code $LASTEXITCODE"
    }
}

Invoke-Step 'HAP build' {
    & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust -DevEcoRoot $DevEcoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "HAP build failed with exit code $LASTEXITCODE"
    }
}

Invoke-Step 'Stage 10 architecture boundaries' {
    Assert-TreeNotContains `
        -Root (Join-Path $etsRoot 'presentation') `
        -Pattern '@kit\.IMEKit|@ohos\.inputMethod|libime_bridge\.so|NativeEngineGateway' `
        -Message 'Presentation code must not call IME Kit or Native directly.' `
        -Extensions @('.ets', '.ts')
    Assert-TreeNotContains `
        -Root (Join-Path $repoRoot 'entry\src\main\cpp') `
        -Pattern 'EditorKind|KeyboardMode|ShiftState|candidateBarVisible|PATTERN_PASSWORD' `
        -Message 'C++ must not contain editor or keyboard policy.' `
        -Extensions @('.cpp', '.h')
    Assert-TreeNotContains `
        -Root (Join-Path $engineRoot 'crates') `
        -Pattern 'EditorKind|KeyboardMode|ShiftState|PhoneKeyboard|SymbolKeyboard|PATTERN_PASSWORD' `
        -Message 'Rust must not contain HarmonyOS editor or keyboard UI policy.' `
        -Extensions @('.rs')

    $patternReferences = Get-ChildItem -LiteralPath $etsRoot -Recurse -File -Filter *.ets |
        Select-String -Pattern 'inputMethodEngine\.PATTERN_'
    foreach ($reference in $patternReferences) {
        if ($reference.Path -notlike '*\infrastructure\ime\EditorAttributeMapper.ets') {
            throw "HarmonyOS editor pattern mapping must remain centralized: $($reference.Path):$($reference.LineNumber)"
        }
    }
}

Invoke-Step 'Password and sensitive log guard' {
    Assert-TreeNotContains `
        -Root $etsRoot `
        -Pattern 'Password key pressed|Password rawInput|Password candidate|password content|rawInput_SENTINEL' `
        -Message 'Source contains an obvious password plaintext log.' `
        -Extensions @('.ets', '.ts')
    Assert-TreeNotContains `
        -Root $etsRoot `
        -Pattern 'LOGGER\.(debug|info|warn|error)\([^\r\n]*\$\{(rawInput|preeditText|candidate|letter|key|text)\}' `
        -Message 'Logger interpolates sensitive plaintext.' `
        -Extensions @('.ets', '.ts')
}

Invoke-Step 'HAP artifact summary' {
    $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $hap) {
        throw 'HAP artifact not found under entry\build.'
    }
    $hash = Get-FileHash -LiteralPath $hap.FullName -Algorithm SHA256
    Write-Host "HAP: $($hap.FullName)"
    Write-Host "Size: $($hap.Length) bytes"
    Write-Host "SHA-256: $($hash.Hash)"
}

Write-Host ''
Write-Host '== Stage 10 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 10 local verification completed. Device acceptance is reported separately and is never inferred by this script.'
