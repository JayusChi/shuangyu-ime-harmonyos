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
$stage8SourceLexicon = Join-Path $repoRoot 'dictionaries\source\stage8_sentence_test.tsv'
$stage8GeneratedLexicon = Join-Path $repoRoot 'dictionaries\generated\stage8_sentence_test.lex'
$stage8Fixture = Join-Path $engineRoot 'tests\fixtures\stage8_sentence_cases.tsv'
$stage6SourceLexicon = Join-Path $repoRoot 'dictionaries\source\stage6_test.tsv'
$stage6GeneratedLexicon = Join-Path $repoRoot 'dictionaries\generated\stage6_test.lex'

Invoke-Step 'Environment check' {
    & (Join-Path $PSScriptRoot 'check-environment.ps1')
}

Invoke-Step 'Stage 8 required files' {
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\sentence-decoder\Cargo.toml') -Message 'sentence-decoder crate must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\sentence-decoder\src\graph.rs') -Message 'sentence graph module must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\sentence-decoder\src\decoder.rs') -Message 'sentence decoder module must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\sentence-decoder\src\scorer.rs') -Message 'sentence scorer module must exist'
    Assert-FileExists -Path $stage8Fixture -Message 'stage8 fixture must exist'
    Assert-FileExists -Path $stage8SourceLexicon -Message 'stage8 source lexicon must exist'
    Assert-FileExists -Path $stage8GeneratedLexicon -Message 'stage8 generated lexicon must exist'
    Assert-FileContains -Path (Join-Path $engineRoot 'Cargo.toml') -Pattern 'crates/sentence-decoder' -Message 'workspace must contain sentence-decoder'
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

Invoke-Step 'sentence-decoder tests' {
    Push-Location $engineRoot
    try {
        cargo test -p sentence-decoder
        if ($LASTEXITCODE -ne 0) {
            throw "sentence-decoder tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 8 integrated Rust tests' {
    Push-Location $engineRoot
    try {
        cargo test -p candidate-query -p candidate-ranking -p sentence-decoder -p ime-engine
        if ($LASTEXITCODE -ne 0) {
            throw "stage8 integrated Rust tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 5/8 FFI tests' {
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

Invoke-Step 'Stage 6 lexicon build and verify' {
    Push-Location $engineRoot
    try {
        cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output ..\dictionaries\generated\stage6_test.lex --lexicon-version 1 --strict
        if ($LASTEXITCODE -ne 0) {
            throw "stage6 lexicon build failed with exit code $LASTEXITCODE"
        }
        cargo run -p lexicon-builder -- --verify ..\dictionaries\generated\stage6_test.lex
        if ($LASTEXITCODE -ne 0) {
            throw "stage6 lexicon verify failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Stage 8 lexicon build and verify' {
    Push-Location $engineRoot
    try {
        cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage8_sentence_test.tsv --output ..\dictionaries\generated\stage8_sentence_test.lex --lexicon-version 8 --strict
        if ($LASTEXITCODE -ne 0) {
            throw "stage8 lexicon build failed with exit code $LASTEXITCODE"
        }
        cargo run -p lexicon-builder -- --verify ..\dictionaries\generated\stage8_sentence_test.lex
        if ($LASTEXITCODE -ne 0) {
            throw "stage8 lexicon verify failed with exit code $LASTEXITCODE"
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

Invoke-Step 'Stage 8 architecture boundary checks' {
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\ime-engine\Cargo.toml') -Pattern 'sentence-decoder' -Message 'ime-engine must depend on sentence-decoder'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\sentence-decoder\src\decoder.rs') -Pattern 'Viterbi|PathState' -Message 'sentence decoder must own bounded path search'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\sentence-decoder\src\graph.rs') -Pattern 'SyllableGraph|WordEdge' -Message 'sentence decoder must own graph structures'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\sentence-decoder\src\scorer.rs') -Pattern 'SentenceScorer' -Message 'sentence decoder must own sentence scoring'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\resource\LexiconResourceInstaller.ets') -Pattern 'production\.lex' -Message 'ArkTS installer must use the production lexicon'

    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern 'Viterbi|Beam Search|SentenceScorer|SyllableGraph|pathScore|scorePath|HSPLEX01' -Message 'ArkTS must not contain sentence decoding or binary lexicon algorithms' -Extensions @('.ets', '.ts')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\cpp') -Pattern 'Viterbi|Beam Search|SentenceScorer|SyllableGraph|WordEdge|sentence_decoder|pinyin_key|HSPLEX01' -Message 'C++ must not contain sentence decoding, pinyin index, or binary lexicon algorithms' -Extensions @('.cpp', '.h')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\sentence-decoder\src') -Pattern '@kit|ohos|openharmony|IMEKit|inputMethodEngine|include_str!\(|fs::read.*\.tsv|File::open.*\.tsv|stage8_sentence_test' -Message 'sentence-decoder must not depend on HarmonyOS APIs or runtime TSV parsing' -Extensions @('.rs')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\ime-engine\src') -Pattern '@kit|ohos|openharmony|IMEKit|inputMethodEngine|include_str!\(|fs::read.*\.tsv|File::open.*\.tsv|stage8_sentence_test' -Message 'ime-engine runtime code must not depend on HarmonyOS APIs or runtime TSV parsing' -Extensions @('.rs')
}

Invoke-Step 'Artifact summary' {
    $stage8Lexicon = Get-Item -LiteralPath $stage8GeneratedLexicon
    $stage8Hash = Get-FileHash -Algorithm SHA256 -LiteralPath $stage8GeneratedLexicon
    Write-Host "Stage 8 source lexicon: $stage8SourceLexicon"
    Write-Host "Stage 8 generated lexicon: $($stage8Lexicon.FullName)"
    Write-Host "Stage 8 generated size: $($stage8Lexicon.Length) bytes"
    Write-Host "Stage 8 SHA256: $($stage8Hash.Hash)"

    $stage6Lexicon = Get-Item -LiteralPath $stage6GeneratedLexicon
    Write-Host "Stage 6 generated size: $($stage6Lexicon.Length) bytes"

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
Write-Host '== Stage 8 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 8 local verification completed. Device install and real input validation are not performed by this script.'
