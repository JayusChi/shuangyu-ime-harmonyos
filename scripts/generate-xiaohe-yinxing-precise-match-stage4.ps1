param(
    [string]$EvidenceDir = 'docs\evidence\2026-08-05-xiaohe-yinxing-precise-match-stage4',
    [switch]$SkipValidation,
    [switch]$ReuseAudit
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineRoot = Join-Path $repoRoot 'engine-rust'
$bundle = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'
$outputRoot = Join-Path $repoRoot $EvidenceDir
$example = Join-Path $engineRoot 'target\release\examples\precise_match_stage4_audit.exe'

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Invoke-Checked([string]$Name, [scriptblock]$Action) {
    Write-Host "== $Name =="
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Report([string]$Mode, [string]$Path) {
    $lines = & $example $Mode $bundle
    if ($LASTEXITCODE -ne 0) {
        throw "stage 4 report mode '$Mode' failed with exit code $LASTEXITCODE"
    }
    $text = ($lines -join "`n") + "`n"
    Write-Utf8NoBom $Path $text
    return $text | ConvertFrom-Json
}

New-Item -ItemType Directory -Force $outputRoot | Out-Null

if (-not $SkipValidation) {
    Push-Location $engineRoot
    try {
        Invoke-Checked 'Rust format' { cargo fmt --all -- --check }
        Invoke-Checked 'Formal production regressions' {
            cargo test -p ime-engine --test xiaohe_yinxing_production
        }
        Invoke-Checked 'Build stage 4 audit (Release)' {
            cargo build --release -p ime-engine --example precise_match_stage4_audit
        }
    } finally {
        Pop-Location
    }
} elseif (-not (Test-Path -LiteralPath $example)) {
    throw "stage 4 Release audit executable is missing: $example"
}

$runOnePath = Join-Path $outputRoot 'audit-run-1.json'
$runTwoPath = Join-Path $outputRoot 'audit-run-2.json'
if ($ReuseAudit) {
    if (-not (Test-Path -LiteralPath $runOnePath) -or -not (Test-Path -LiteralPath $runTwoPath)) {
        throw 'cannot reuse stage 4 audit because one or both deterministic runs are missing'
    }
    $auditOne = Get-Content -LiteralPath $runOnePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $auditTwo = Get-Content -LiteralPath $runTwoPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $auditOne = Invoke-Report 'audit' $runOnePath
    $auditTwo = Invoke-Report 'audit' $runTwoPath
}
$runOneInfo = Get-Item -LiteralPath $runOnePath
$runTwoInfo = Get-Item -LiteralPath $runTwoPath
$runOneHash = (Get-FileHash -LiteralPath $runOnePath -Algorithm SHA256).Hash
$runTwoHash = (Get-FileHash -LiteralPath $runTwoPath -Algorithm SHA256).Hash
if ($runOneInfo.Length -ne $runTwoInfo.Length -or $runOneHash -ne $runTwoHash) {
    throw 'deterministic audit reports differ byte-for-byte'
}
if (-not $auditOne.all_checks_passed -or -not $auditTwo.all_checks_passed) {
    throw 'formal data audit reported a contract failure'
}
Copy-Item -LiteralPath $runOnePath -Destination (Join-Path $outputRoot 'audit-report.json') -Force

$progressive = Invoke-Report 'performance-progressive' (Join-Path $outputRoot 'performance-progressive.json')
$deterministic = Invoke-Report 'performance-deterministic' (Join-Path $outputRoot 'performance-deterministic.json')

function Reduction([double]$Before, [double]$After) {
    if ($Before -eq 0) { return 0.0 }
    return [Math]::Round((1.0 - ($After / $Before)) * 100.0, 4)
}

$comparison = [ordered]@{
    schema_version = 'xiaohe-yinxing-precise-match-stage4-performance-comparison/1'
    profile = 'release'
    baseline_strategy = $progressive.strategy
    precise_strategy = $deterministic.strategy
    prefix_count = [int]$deterministic.distinct_one_to_three_code_prefixes
    query_time_ns = [ordered]@{
        progressive_p50 = [long]$progressive.query_time_ns.p50
        deterministic_p50 = [long]$deterministic.query_time_ns.p50
        p50_reduction_percent = Reduction $progressive.query_time_ns.p50 $deterministic.query_time_ns.p50
        progressive_p95 = [long]$progressive.query_time_ns.p95
        deterministic_p95 = [long]$deterministic.query_time_ns.p95
        p95_reduction_percent = Reduction $progressive.query_time_ns.p95 $deterministic.query_time_ns.p95
    }
    candidate_transport = [ordered]@{
        progressive_candidates = [long]$progressive.total_candidates_transferred
        deterministic_candidates = [long]$deterministic.total_candidates_transferred
        candidate_reduction_percent = Reduction $progressive.total_candidates_transferred $deterministic.total_candidates_transferred
        progressive_json_bytes = [long]$progressive.candidate_snapshot_json_bytes
        deterministic_json_bytes = [long]$deterministic.candidate_snapshot_json_bytes
        json_byte_reduction_percent = Reduction $progressive.candidate_snapshot_json_bytes $deterministic.candidate_snapshot_json_bytes
    }
    memory = [ordered]@{
        progressive_snapshot_delta_bytes = [long]$progressive.memory.candidate_snapshot_working_set_delta_bytes
        deterministic_snapshot_delta_bytes = [long]$deterministic.memory.candidate_snapshot_working_set_delta_bytes
        snapshot_delta_reduction_percent = Reduction $progressive.memory.candidate_snapshot_working_set_delta_bytes $deterministic.memory.candidate_snapshot_working_set_delta_bytes
        note = 'Working-set values come from independent Release processes and are supporting evidence; candidate and JSON totals are deterministic.'
    }
    gates = [ordered]@{
        no_correctness_failures = [bool]$auditOne.all_checks_passed
        deterministic_report_twice_identical = $true
        p95_no_regression = ([long]$deterministic.query_time_ns.p95 -le [long]$progressive.query_time_ns.p95)
        candidate_json_volume_reduced = ([long]$deterministic.candidate_snapshot_json_bytes -lt [long]$progressive.candidate_snapshot_json_bytes)
    }
}
$comparisonPath = Join-Path $outputRoot 'performance-comparison.json'
Write-Utf8NoBom $comparisonPath (($comparison | ConvertTo-Json -Depth 8) + "`n")
if (-not $comparison.gates.p95_no_regression -or -not $comparison.gates.candidate_json_volume_reduced) {
    throw 'stage 4 performance gate failed'
}

$bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
$bundleLength = (Get-Item -LiteralPath $bundle).Length
$readme = @(
    '# Xiaohe Yinxing precise-match stage 4 evidence'
    ''
    'Date: 2026-08-05  '
    'Status: COMPLETED'
    ''
    '## Full production-data audit'
    ''
    "- Complete four-code space: $($auditOne.four_code_space)."
    "- Zero: $($auditOne.zero_candidate_codes); unique: $($auditOne.unique_four_codes); collision: $($auditOne.collision_four_codes); max collision: $($auditOne.maximum_candidates_per_four_code)."
    '- Every unique code auto-committed once; every collision waited, remained exact and stable, and kept all candidates reachable.'
    "- Source-to-runtime audit covered $($auditOne.source_entry_audit.short_code_pairs_checked) short-code pairs and $($auditOne.source_entry_audit.phrase_pairs_checked) phrase pairs."
    "- Uniqueness changes covered $($auditOne.category_disable_audit.optional_categories_checked) optional categories and $($auditOne.user_delete_audit.non_empty_four_codes_checked) non-empty four-codes."
    '- Two audit reports were byte-identical; all_checks_passed=true.'
    ''
    '## Release A/B'
    ''
    "- Covered $($comparison.prefix_count) distinct one-to-three-code prefixes from production data."
    "- Query P95: progressive $($comparison.query_time_ns.progressive_p95) ns, deterministic $($comparison.query_time_ns.deterministic_p95) ns, reduction $($comparison.query_time_ns.p95_reduction_percent)%."
    "- Candidate transfer: $($comparison.candidate_transport.progressive_candidates) to $($comparison.candidate_transport.deterministic_candidates), reduction $($comparison.candidate_transport.candidate_reduction_percent)%."
    "- Candidate snapshot JSON: $($comparison.candidate_transport.progressive_json_bytes) bytes to $($comparison.candidate_transport.deterministic_json_bytes) bytes, reduction $($comparison.candidate_transport.json_byte_reduction_percent)%."
    '- Independent Release-process working sets are supporting observations; deterministic gates use candidate and JSON byte totals.'
    ''
    '## Resource and reproduction'
    ''
    "- Formal bundle: $bundleLength bytes, SHA-256 $bundleHash."
    '- Reproduce: powershell -ExecutionPolicy Bypass -File scripts/generate-xiaohe-yinxing-precise-match-stage4.ps1.'
    '- Machine reports: audit-report.json, performance-progressive.json, performance-deterministic.json, performance-comparison.json.'
) -join "`n"
Write-Utf8NoBom (Join-Path $outputRoot 'README.md') ($readme + "`n")

Write-Host ''
Write-Host 'Stage 4 precise-match audit: PASS'
Write-Host "Evidence: $outputRoot"
