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
    $tempDir = Join-Path $engineRoot 'target\stage6-verify'
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
        $hashA = (Get-FileHash -Algorithm SHA256 -LiteralPath $tempA).Hash
        $hashB = (Get-FileHash -Algorithm SHA256 -LiteralPath $tempB).Hash
        Write-Host "temporary-a SHA256: $hashA"
        Write-Host "temporary-b SHA256: $hashB"
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

Invoke-Step 'Stage 5 Rust FFI regression tests' {
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

Invoke-Step 'Stage 6 source boundary checks' {
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\lexicon-core\src\binary.rs') -Message 'lexicon-core binary format must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'tools\lexicon-builder\src\main.rs') -Message 'lexicon-builder CLI must exist'
    Assert-FileExists -Path $sourceLexicon -Message 'stage6 test source lexicon must exist'
    Assert-FileExists -Path $generatedLexicon -Message 'stage6 generated binary lexicon must exist'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\lexicon-core\src\binary.rs') -Pattern 'HSPLEX01' -Message 'binary format magic must be fixed'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\lexicon-core\src\checksum.rs') -Pattern 'crc32_ieee' -Message 'CRC32 checksum implementation must exist'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\engine-protocol\src\composition.rs') -Pattern 'candidates: Vec::new\(\)' -Message 'formal CompositionResult must still return empty candidates'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\engine-protocol\src\composition.rs') -Pattern 'highlighted_index: -1' -Message 'formal highlighted index must remain -1'

    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\cpp') -Pattern 'lexicon-core|lexicon_builder|HSPLEX01|stage6_test' -Message 'C++ must not contain lexicon business logic' -Extensions @('.cpp', '.h')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern 'stage6_test\.lex|HSPLEX01|lexicon-builder|lexicon-core' -Message 'ArkTS must not read or parse stage6 lexicon' -Extensions @('.ets', '.ts')
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

Invoke-Step 'Artifact summary' {
    $lexicon = Get-Item -LiteralPath $generatedLexicon
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $generatedLexicon
    Write-Host "Lexicon: $($lexicon.FullName)"
    Write-Host "Size: $($lexicon.Length) bytes"
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
        Write-Host "Size: $($hap.Length) bytes"
    }
}

Write-Host ''
Write-Host '== Stage 6 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 6 lexicon build system verification completed.'
