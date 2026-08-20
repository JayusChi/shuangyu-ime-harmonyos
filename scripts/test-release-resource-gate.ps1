$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.stage11_6_2a_gate_test'))
if (-not $tempRoot.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to manage gate-test directory outside the repository: $tempRoot"
}
if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
$sourceRoot = Join-Path $tempRoot 'source'
$resourceRoot = Join-Path $sourceRoot 'resources'
$rawfile = Join-Path $resourceRoot 'rawfile'
New-Item -ItemType Directory -Path $rawfile -Force | Out-Null
$production = Join-Path $rawfile 'production.lex'
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex') `
    -Destination $production
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\xiaohe-yinxing-production.hsyx') `
    -Destination (Join-Path $rawfile 'xiaohe-yinxing-production.hsyx')
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\quanpin-context-v2.qng') `
    -Destination (Join-Path $rawfile 'quanpin-context-v2.qng')
$pageProfileRoot = Join-Path $resourceRoot 'base\profile'
New-Item -ItemType Directory -Path $pageProfileRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $pageProfileRoot 'main_pages.json'), '{"src":["pages/Index"]}', [Text.Encoding]::UTF8)
$etsRoot = Join-Path $sourceRoot 'ets\pages'
New-Item -ItemType Directory -Path $etsRoot -Force | Out-Null
$indexSource = Join-Path $etsRoot 'Index.ets'
[IO.File]::WriteAllText($indexSource, '@Entry struct Index {}', [Text.Encoding]::UTF8)
$debugAcceptanceText = -join (@(0x8C03, 0x8BD5, 0x4E0E, 0x9A8C, 0x6536) | ForEach-Object { [char]$_ })

function Invoke-NegativeGate {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-release-hap.ps1') `
        -ResourceInputOnly -ResourceRoot $resourceRoot -SourceRoot $sourceRoot 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($exitCode -eq 0) { throw 'Release gate accepted a deliberately invalid resource set.' }
}

try {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-release-hap.ps1') `
        -ResourceInputOnly -ResourceRoot $resourceRoot -SourceRoot $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Release gate rejected the production-only control case.' }

    $productionBytes = [IO.File]::ReadAllBytes($production)
    $productionBytes[$productionBytes.Length - 1] = $productionBytes[$productionBytes.Length - 1] -bxor 0x01
    [IO.File]::WriteAllBytes($production, $productionBytes)
    Invoke-NegativeGate
    Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex') `
        -Destination $production -Force

    $fixture = Join-Path $rawfile 'code-table-fixture-synthetic.bundle'
    [IO.File]::WriteAllBytes($fixture, [byte[]](0x54, 0x45, 0x53, 0x54))
    Invoke-NegativeGate
    Remove-Item -LiteralPath $fixture -Force

    $rawSource = Join-Path $rawfile 'formal-source.txt'
    [IO.File]::WriteAllText($rawSource, "词条`tcode", [Text.Encoding]::UTF8)
    Invoke-NegativeGate
    Remove-Item -LiteralPath $rawSource -Force

    $credentialNamed = Join-Path $rawfile 'delivery-token.bin'
    [IO.File]::WriteAllBytes($credentialNamed, [byte[]](0x46, 0x41, 0x4b, 0x45))
    Invoke-NegativeGate
    Remove-Item -LiteralPath $credentialNamed -Force

    [IO.File]::WriteAllText($indexSource, '@Entry struct DebugStage10 {}', [Text.Encoding]::UTF8)
    Invoke-NegativeGate
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private title: string = '$debugAcceptanceText'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private permission: string = 'ohos.permission.INTERNET'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate
    Write-Host 'RELEASE_RESOURCE_GATE_TEST_RESULT=PASS'
    $global:LASTEXITCODE = 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
