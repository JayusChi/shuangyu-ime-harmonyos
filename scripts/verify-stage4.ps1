param(
    [switch]$SkipHap,
    [switch]$DeviceValidation,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'

$script:Results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Result,
        [string]$Detail
    )

    $script:Results += [PSCustomObject]@{
        Step = $Name
        Result = $Result
        Detail = $Detail
    }
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host ''
    Write-Host "== $Name =="
    & $Action
    Add-Result -Name $Name -Result 'PASS' -Detail 'completed'
}

function Assert-FileExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Assert-FileContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }

    $content = Get-Content -Encoding UTF8 -LiteralPath $Path -Raw
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-TreeNotContains {
    param(
        [string]$Root,
        [string]$Pattern,
        [string]$Message,
        [string[]]$Extensions = @('*')
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        throw "Missing tree: $Root"
    }

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object {
            if ($Extensions -contains '*') {
                return $true
            }
            $Extensions -contains $_.Extension
        }

    foreach ($file in $files) {
        $content = Get-Content -Encoding UTF8 -LiteralPath $file.FullName -Raw
        if ($content -match $Pattern) {
            throw "$Message Match: $($file.FullName)"
        }
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineRoot = Join-Path $repoRoot 'engine-rust'

Invoke-Step 'Environment check' {
    & (Join-Path $PSScriptRoot 'check-environment.ps1')
}

Invoke-Step 'Rust format' {
    Push-Location $engineRoot
    try {
        cargo fmt --check
        if ($LASTEXITCODE -ne 0) {
            throw "cargo fmt failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Rust clippy' {
    Push-Location $engineRoot
    try {
        cargo clippy --workspace --all-targets -- -D warnings
        if ($LASTEXITCODE -ne 0) {
            throw "cargo clippy failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Rust workspace tests' {
    Push-Location $engineRoot
    try {
        cargo test --workspace
        if ($LASTEXITCODE -ne 0) {
            throw "cargo test failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 4 parser tests' {
    Push-Location $engineRoot
    try {
        cargo test -p pinyin-syllable
        if ($LASTEXITCODE -ne 0) {
            throw "pinyin-syllable tests failed with exit code $LASTEXITCODE"
        }

        cargo test -p shuangpin-schema
        if ($LASTEXITCODE -ne 0) {
            throw "shuangpin-schema tests failed with exit code $LASTEXITCODE"
        }

        cargo test -p shuangpin-parser --test stage4_cases
        if ($LASTEXITCODE -ne 0) {
            throw "stage4 parser fixture tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Rust x86_64 and arm64-v8a artifacts' {
    & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
}

Invoke-Step 'ArkTS unit tests' {
    $hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
    if (-not (Test-Path -LiteralPath $hvigor)) {
        throw "hvigorw not found: $hvigor"
    }

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

if ($SkipHap) {
    Write-Host ''
    Write-Host '== HAP build =='
    Write-Host 'SKIPPED HAP build by -SkipHap.'
    Add-Result -Name 'HAP build' -Result 'SKIP' -Detail 'skipped by -SkipHap'
} else {
    Invoke-Step 'C++/ArkTS/HAP build' {
        & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust
    }
}

Invoke-Step 'Stage 4 source boundary checks' {
    Assert-FileExists -Path (Join-Path $engineRoot 'schemas\xiaohe.json') -Message 'xiaohe schema must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'tests\fixtures\stage4_parser_cases.tsv') -Message 'stage4 parser fixture must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\pinyin-syllable\src\lib.rs') -Message 'pinyin-syllable crate must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\shuangpin-schema\src\lib.rs') -Message 'shuangpin-schema crate must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\shuangpin-parser\src\lib.rs') -Message 'shuangpin-parser crate must exist'

    Assert-FileContains -Path (Join-Path $engineRoot 'Cargo.toml') -Pattern 'pinyin-syllable' -Message 'pinyin-syllable must be a workspace member'
    Assert-FileContains -Path (Join-Path $engineRoot 'Cargo.toml') -Pattern 'shuangpin-schema' -Message 'shuangpin-schema must be a workspace member'
    Assert-FileContains -Path (Join-Path $engineRoot 'Cargo.toml') -Pattern 'shuangpin-parser' -Message 'shuangpin-parser must be a workspace member'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\shuangpin-schema\src\loader.rs') -Pattern 'include_str!\("\.\./\.\./\.\./schemas/xiaohe\.json"\)' -Message 'xiaohe schema must be loaded from the data file'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\shuangpin-parser\tests\stage4_cases.rs') -Pattern 'stage4_parser_cases\.tsv' -Message 'stage4 fixture tests must be registered'

    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\cpp') -Pattern 'xiaohe|shuangpin|pinyin|双拼|小鹤' -Message 'C++ must not contain shuangpin business rules' -Extensions @('.cpp', '.h')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern 'xiaohe|shuangpin-parser|shuangpin-schema|pinyin-syllable|双拼解析|小鹤' -Message 'ArkTS must not contain shuangpin parsing logic' -Extensions @('.ets')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\shuangpin-parser') -Pattern '@kit|napi|InputMethod|OH_Native|hilog' -Message 'Rust parser must not depend on HarmonyOS APIs' -Extensions @('.rs', '.toml')

    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\InputPanelController.ets') -Pattern 'KeyboardRootStage3' -Message 'Stage 3 active keyboard entry must remain intact'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\resources\base\profile\main_pages.json') -Pattern 'presentation/keyboard/KeyboardRootStage3' -Message 'Stage 3 page registration must remain intact'
}

Invoke-Step 'Artifact summary' {
    $rustRoot = Join-Path $engineRoot 'target\ohos'
    Get-ChildItem -LiteralPath $rustRoot -Recurse -Filter *.a |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize

    if (-not $SkipHap) {
        $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $hap) {
            throw 'HAP artifact not found under entry\build.'
        }
        Write-Host "HAP: $($hap.FullName)"
        Write-Host "Size: $($hap.Length) bytes"
    }
}

if ($DeviceValidation) {
    Invoke-Step 'Device install and IME status' {
        $hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
        if (-not (Test-Path -LiteralPath $hdc)) {
            throw "hdc not found: $hdc"
        }

        $targets = & $hdc list targets
        Write-Host $targets
        if (-not $targets -or $targets.Trim().Length -eq 0 -or $targets -match 'Empty') {
            throw 'No online device target found for -DeviceValidation.'
        }

        $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $hap) {
            throw 'HAP artifact not found for device validation.'
        }

        $bundleContent = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw
        if ($bundleContent -notmatch '"bundleName"\s*:\s*"([^"]+)"') {
            throw 'bundleName not found in AppScope/app.json5.'
        }
        $bundleName = $Matches[1]

        & $hdc install -r $hap.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "hdc install failed with exit code $LASTEXITCODE"
        }

        & $hdc shell ime -e $bundleName -f
        if ($LASTEXITCODE -ne 0) {
            throw "ime enable failed with exit code $LASTEXITCODE"
        }

        & $hdc shell ime -g
        if ($LASTEXITCODE -ne 0) {
            throw "ime status failed with exit code $LASTEXITCODE"
        }
    }
} else {
    Write-Host ''
    Write-Host '== Device install and IME status =='
    Write-Host 'SKIPPED device validation. Re-run with -DeviceValidation when an emulator/device is online.'
    Add-Result -Name 'Device install and IME status' -Result 'SKIP' -Detail 'not requested'
}

Write-Host ''
Write-Host '== Stage 4 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 4 shuangpin parser verification completed.'
