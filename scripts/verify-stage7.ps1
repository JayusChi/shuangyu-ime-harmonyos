param(
    [switch]$SkipHap,
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

function Assert-FileNotContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    $content = Get-Content -Encoding UTF8 -LiteralPath $Path -Raw
    if ($content -match $Pattern) {
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
$sourceLexicon = Join-Path $repoRoot 'dictionaries\source\stage6_test.tsv'
$generatedLexicon = Join-Path $repoRoot 'dictionaries\generated\stage6_test.lex'

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

Invoke-Step 'Stage 5 and Stage 7 FFI tests' {
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

Invoke-Step 'Stage 6 lexicon build' {
    Push-Location $engineRoot
    try {
        cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output ..\dictionaries\generated\stage6_test.lex --lexicon-version 1 --strict
        if ($LASTEXITCODE -ne 0) {
            throw "stage6 lexicon build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 6 lexicon verify' {
    Push-Location $engineRoot
    try {
        cargo run -p lexicon-builder -- --verify ..\dictionaries\generated\stage6_test.lex
        if ($LASTEXITCODE -ne 0) {
            throw "stage6 lexicon verify failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 6 deterministic build' {
    $tempDir = Join-Path $engineRoot 'target\stage7-verify'
    $tempA = Join-Path $tempDir 'temporary-a.lex'
    $tempB = Join-Path $tempDir 'temporary-b.lex'
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    try {
        Push-Location $engineRoot
        try {
            cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output $tempA --lexicon-version 1 --strict
            if ($LASTEXITCODE -ne 0) {
                throw "first deterministic build failed with exit code $LASTEXITCODE"
            }
            cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output $tempB --lexicon-version 1 --strict
            if ($LASTEXITCODE -ne 0) {
                throw "second deterministic build failed with exit code $LASTEXITCODE"
            }
        } finally {
            Pop-Location
        }

        $bytesA = [System.IO.File]::ReadAllBytes($tempA)
        $bytesB = [System.IO.File]::ReadAllBytes($tempB)
        if (-not [System.Linq.Enumerable]::SequenceEqual($bytesA, $bytesB)) {
            throw 'deterministic build failed: output bytes differ'
        }
        Write-Host "temporary-a SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $tempA).Hash)"
        Write-Host "temporary-b SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $tempB).Hash)"
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

Invoke-Step 'Stage 7 query tests' {
    Push-Location $engineRoot
    try {
        cargo test -p candidate-query
        if ($LASTEXITCODE -ne 0) {
            throw "candidate-query tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 7 ranking tests' {
    Push-Location $engineRoot
    try {
        cargo test -p candidate-ranking
        if ($LASTEXITCODE -ne 0) {
            throw "candidate-ranking tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 7 pagination and cache tests' {
    Push-Location $engineRoot
    try {
        cargo test -p ime-engine
        if ($LASTEXITCODE -ne 0) {
            throw "ime-engine tests failed with exit code $LASTEXITCODE"
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

Invoke-Step 'Stage 7 architecture boundary checks' {
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\candidate-query\src\query_engine.rs') -Message 'candidate-query implementation must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\candidate-ranking\src\ranking_policy.rs') -Message 'candidate-ranking implementation must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\lexicon-core\src\runtime_index.rs') -Message 'lexicon runtime index must exist'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\resource\LexiconResourceInstaller.ets') -Pattern 'getRawFileContentSync' -Message 'ArkTS must install lexicon from rawfile'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\native\NativeEngineGateway.ets') -Pattern 'selectCandidate' -Message 'ArkTS native gateway must expose selectCandidate'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\cpp\napi\engine_napi.cpp') -Pattern 'SelectRegisteredEngineCandidate' -Message 'C++ must forward selectCandidate'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\ime-engine\src\formal.rs') -Pattern 'load_binary_lexicon' -Message 'Rust engine must load binary lexicon'

    Assert-FileNotContains -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\candidate\CandidateBar.ets') -Pattern 'libime_bridge|NativeEngineGateway|ImeConnectionService|@kit\.IMEKit' -Message 'CandidateBar must not call Native or IME Kit directly'
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern 'rank_candidates|CandidateMatchType|frequency.*candidate|\u4F60.*ni|\u8F93\u5165\u6CD5.*shu ru fa' -Message 'ArkTS must not contain candidate ranking or hardcoded formal Chinese candidates' -Extensions @('.ets', '.ts')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\cpp') -Pattern 'pinyin_key|rank_candidates|CandidateMatchType|HSPLEX01|lexicon_core|stage6_test\.tsv' -Message 'C++ must not contain pinyin index or ranking algorithms' -Extensions @('.cpp', '.h')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\candidate-query') -Pattern 'HarmonyOS|InputMethod|IMEKit|\.tsv' -Message 'candidate-query must not depend on HarmonyOS APIs or TSV runtime parsing' -Extensions @('.rs')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\ime-engine\src') -Pattern 'HarmonyOS|InputMethod|IMEKit|\.tsv' -Message 'ime-engine runtime code must not depend on HarmonyOS APIs or TSV runtime parsing' -Extensions @('.rs')
}

Invoke-Step 'Artifact summary' {
    $lexicon = Get-Item -LiteralPath $generatedLexicon
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $generatedLexicon
    Write-Host "Lexicon: $($lexicon.FullName)"
    Write-Host "Lexicon size: $($lexicon.Length) bytes"
    Write-Host "SHA256: $($hash.Hash)"

    $rustRoot = Join-Path $engineRoot 'target\ohos'
    if (Test-Path -LiteralPath $rustRoot) {
        Get-ChildItem -LiteralPath $rustRoot -Recurse -Filter *.a |
            Select-Object FullName, Length, LastWriteTime |
            Format-Table -AutoSize
    }

    if (-not $SkipHap) {
        $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $hap) {
            throw 'HAP artifact not found under entry\build.'
        }
        Write-Host "HAP: $($hap.FullName)"
        Write-Host "HAP size: $($hap.Length) bytes"
    }
}

Write-Host ''
Write-Host '== Stage 7 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 7 local verification completed. Device install and real input validation are not performed by this script.'
