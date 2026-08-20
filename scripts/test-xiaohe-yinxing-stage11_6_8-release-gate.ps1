param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$gate = Join-Path $PSScriptRoot 'verify-release-hap.ps1'
$tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.stage11_6_8_release_gate_negative'))
if (-not $tempRoot.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to create negative gate inputs outside the repository.'
}

function New-ApprovedResourceRoot([string]$name) {
    $root = Join-Path $tempRoot $name
    $raw = Join-Path $root 'rawfile'
    New-Item -ItemType Directory -Force $raw | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex') -Destination $raw
    Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\quanpin-context-v2.qng') -Destination $raw
    Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\xiaohe-yinxing-production.hsyx') -Destination $raw
    return $root
}

function Assert-GateFailure([string]$name, [string]$resourceRoot, [string]$sourceRoot, [string]$expectedRule) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gate,
            '-ResourceInputOnly', '-ResourceRoot', $resourceRoot)
        if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) {
            $arguments += @('-SourceRoot', $sourceRoot)
        }
        $output = & powershell.exe @arguments 2>&1
        $gateExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($gateExitCode -eq 0) { throw "negative gate case unexpectedly passed: $name" }
    if (($output -join "`n") -notmatch "RULE_ID=$expectedRule") {
        throw "negative gate case did not report $expectedRule`: $name"
    }
    Write-Host "NEGATIVE_CASE=$name PASS rule=$expectedRule"
}

try {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    New-Item -ItemType Directory -Force $tempRoot | Out-Null

    foreach ($case in @(
        @{ Name = 'fixture'; File = 'synthetic-fixture.tsv'; Source = 'engine-rust\crates\code-table-runtime\tests\data\xiaohe_yinxing_stage11_6_3.tsv'; Rule = 'REL_RAWFILE_NOT_APPROVED' },
        @{ Name = 'raw-source'; File = 'customer-source.txt'; Source = 'engine-rust\crates\code-table-runtime\tests\data\xiaohe_yinxing_stage11_6_3.tsv'; Rule = 'REL_RAWFILE_NOT_APPROVED' },
        @{ Name = 'trace-index'; File = 'trace-index.jsonl'; Source = 'dictionaries\generated\xiaohe-yinxing-production\trace-index.jsonl'; Rule = 'REL_RAWFILE_NOT_APPROVED' },
        @{ Name = 'build-report'; File = 'build-report.json'; Source = 'dictionaries\generated\xiaohe-yinxing-production\build-report.json'; Rule = 'REL_RAWFILE_NOT_APPROVED' }
    )) {
        $root = New-ApprovedResourceRoot $case.Name
        Copy-Item -LiteralPath (Join-Path $repoRoot $case.Source) -Destination (Join-Path $root "rawfile\$($case.File)")
        Assert-GateFailure $case.Name $root '' $case.Rule
    }

    $tamperedRoot = New-ApprovedResourceRoot 'tampered-formal'
    $tamperedPath = Join-Path $tamperedRoot 'rawfile\xiaohe-yinxing-production.hsyx'
    $bytes = [IO.File]::ReadAllBytes($tamperedPath)
    $bytes[$bytes.Length - 1] = $bytes[$bytes.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes($tamperedPath, $bytes)
    Assert-GateFailure 'tampered-formal' $tamperedRoot '' 'REL_YINXING_BUNDLE_HASH'

    $networkRoot = New-ApprovedResourceRoot 'network-permission'
    $networkSource = Join-Path $tempRoot 'network-source'
    New-Item -ItemType Directory -Force $networkSource | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $networkSource 'module.json5'),
        '{"requestPermissions":[{"name":"ohos.permission.INTERNET"}]}',
        [Text.Encoding]::UTF8
    )
    Assert-GateFailure 'network-permission' $networkRoot $networkSource 'REL_NETWORK_PERMISSION'

    Write-Host 'STAGE11_6_8_RELEASE_NEGATIVE_RESULT=PASS'
    $global:LASTEXITCODE = 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
