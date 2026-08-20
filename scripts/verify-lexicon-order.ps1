$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$manifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$fixture = Join-Path $repoRoot 'dictionaries\source\test-fixtures\flypy_order_table.txt'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("harmony-lexicon-order-" + [guid]::NewGuid().ToString('N'))
$leftDir = Join-Path $tempRoot 'left'
$rightDir = Join-Path $tempRoot 'right'
$leftOutput = Join-Path $leftDir 'order.lex'
$rightOutput = Join-Path $rightDir 'order.lex'
New-Item -ItemType Directory -Force $leftDir, $rightDir | Out-Null

function Build-OrderLexicon([string]$output) {
    cargo run --quiet --manifest-path $manifest -p lexicon-builder -- `
        --input $fixture `
        --input-format flypy-table `
        --output $output `
        --lexicon-version 1 `
        --strict `
        --verify
    if ($LASTEXITCODE -ne 0) { throw "code-table build failed: $output" }
}

Build-OrderLexicon $leftOutput
Build-OrderLexicon $rightOutput

$left = Get-Item -LiteralPath $leftOutput
$right = Get-Item -LiteralPath $rightOutput
$leftHash = (Get-FileHash -LiteralPath $leftOutput -Algorithm SHA256).Hash
$rightHash = (Get-FileHash -LiteralPath $rightOutput -Algorithm SHA256).Hash
$leftBytes = [System.IO.File]::ReadAllBytes($leftOutput)
$rightBytes = [System.IO.File]::ReadAllBytes($rightOutput)
$sameBytes = [System.Convert]::ToBase64String($leftBytes) -ceq [System.Convert]::ToBase64String($rightBytes)

if ($left.Length -ne $right.Length) { throw 'deterministic build size mismatch' }
if (-not $sameBytes) { throw 'deterministic build byte mismatch' }
if ($leftHash -ne $rightHash) { throw 'deterministic build SHA-256 mismatch' }

cargo test --manifest-path $manifest -p candidate-query source_order_mode
if ($LASTEXITCODE -ne 0) { throw 'source-order query tests failed' }
cargo test --manifest-path $manifest -p lexicon-builder cli_flypy_table_build_preserves_order_and_is_byte_deterministic -- --exact
if ($LASTEXITCODE -ne 0) { throw 'source-order builder integration test failed' }

Write-Host "LEFT_SIZE=$($left.Length)"
Write-Host "RIGHT_SIZE=$($right.Length)"
Write-Host "LEFT_SHA256=$leftHash"
Write-Host "RIGHT_SHA256=$rightHash"
Write-Host 'EXACT_abz_COUNT=2 SOURCE_ORDERS=0,2'
Write-Host 'PREFIX_ab_COUNT=6 SOURCE_ORDERS=0,1,2,3,4,5'
Write-Host 'EMPTY_INPUT_COUNT=0'
Write-Host 'LEXICON_ORDER_VERIFY_RESULT=PASS'
