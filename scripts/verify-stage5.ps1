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

Invoke-Step 'Stage 5 Rust FFI tests' {
    Push-Location $engineRoot
    try {
        cargo test -p ime-ffi
        if ($LASTEXITCODE -ne 0) {
            throw "ime-ffi tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 4 parser regression tests' {
    Push-Location $engineRoot
    try {
        cargo test -p shuangpin-parser --test stage4_cases
        if ($LASTEXITCODE -ne 0) {
            throw "stage4 parser regression failed with exit code $LASTEXITCODE"
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
    Write-Host '== C++/ArkTS/HAP build =='
    Write-Host 'SKIPPED HAP build by -SkipHap.'
    Add-Result -Name 'C++/ArkTS/HAP build' -Result 'SKIP' -Detail 'skipped by -SkipHap'
} else {
    Invoke-Step 'C++/ArkTS/HAP build' {
        & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust
    }
}

Invoke-Step 'Stage 5 source boundary checks' {
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\ime-engine\src\formal.rs') -Message 'formal Rust ImeEngine must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\cpp\bridge\engine_registry.cpp') -Message 'EngineRegistry must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\cpp\bridge\rust_engine_handle.cpp') -Message 'RustEngineHandle must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\application\EngineCoordinator.ets') -Message 'EngineCoordinator must exist'

    Assert-FileContains -Path (Join-Path $engineRoot 'crates\ime-ffi\src\lib.rs') -Pattern 'catch_unwind' -Message 'Rust C ABI must catch panic'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\ime-ffi\src\lib.rs') -Pattern 'ime_engine_free_buffer' -Message 'Rust free_buffer must exist'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\cpp\bridge\engine_registry.cpp') -Pattern 'std::lock_guard<std::mutex>' -Message 'EngineRegistry must be mutex protected'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\cpp\napi\module_init.cpp') -Pattern 'processKey' -Message 'formal Node-API processKey must be registered'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\native\NativeEngineGateway.ets') -Pattern 'createEngine' -Message 'ArkTS gateway must create formal engine'

    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\cpp') -Pattern 'ordinary_initials|zero_initial|finals_for_key|special_syllable|pinyin-syllable' -Message 'C++ must not contain shuangpin business rules' -Extensions @('.cpp', '.h')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets\presentation') -Pattern "libime_bridge\.so" -Message 'UI components must not import the native module directly' -Extensions @('.ets')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern 'xiaohe\.json|ordinary_initials|zero_initial|finals_for_key|special_syllable' -Message 'ArkTS must not contain shuangpin parser rules' -Extensions @('.ets')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern '你好|候选1|候选2' -Message 'ArkTS must not hard-code Chinese formal candidates' -Extensions @('.ets')
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\shuangpin-parser\tests\stage4_cases.rs') -Pattern 'stage4_parser_cases\.tsv' -Message 'stage4 parser tests must remain registered'
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
    }
} else {
    Write-Host ''
    Write-Host '== Device install and IME status =='
    Write-Host 'SKIPPED device validation. Re-run with -DeviceValidation when an emulator/device is online.'
    Add-Result -Name 'Device install and IME status' -Result 'SKIP' -Detail 'not requested'
}

Write-Host ''
Write-Host '== Stage 5 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 5 formal cross-language interface verification completed.'
