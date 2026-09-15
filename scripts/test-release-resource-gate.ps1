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
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\keyboard-skin-editor.html') `
    -Destination (Join-Path $rawfile 'keyboard-skin-editor.html')
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex') `
    -Destination $production
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\xiaohe-yinxing-production.hsyx') `
    -Destination (Join-Path $rawfile 'xiaohe-yinxing-production.hsyx')
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\quanpin-context-v2.qng') `
    -Destination (Join-Path $rawfile 'quanpin-context-v2.qng')
$pageProfileRoot = Join-Path $resourceRoot 'base\profile'
New-Item -ItemType Directory -Path $pageProfileRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $pageProfileRoot 'main_pages.json'), '{"src":["pages/Index"]}', [Text.Encoding]::UTF8)
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\base\profile\stage0_input_method.json') `
    -Destination (Join-Path $pageProfileRoot 'stage0_input_method.json')
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\module.json5') `
    -Destination (Join-Path $sourceRoot 'module.json5')
$imeSourceRoot = Join-Path $sourceRoot 'ets\inputmethod'
New-Item -ItemType Directory -Path $imeSourceRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\ets\inputmethod\Stage0InputMethodAbilityBase.ets') `
    -Destination (Join-Path $imeSourceRoot 'Stage0InputMethodAbilityBase.ets')
$etsRoot = Join-Path $sourceRoot 'ets\pages'
New-Item -ItemType Directory -Path $etsRoot -Force | Out-Null
$indexSource = Join-Path $etsRoot 'Index.ets'
[IO.File]::WriteAllText($indexSource, '@Entry struct Index {}', [Text.Encoding]::UTF8)
$debugAcceptanceText = -join (@(0x8C03, 0x8BD5, 0x4E0E, 0x9A8C, 0x6536) | ForEach-Object { [char]$_ })

function Invoke-NegativeGate([string]$Case) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-release-hap.ps1') `
        -ResourceInputOnly -ResourceRoot $resourceRoot -SourceRoot $sourceRoot 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($exitCode -eq 0) { throw "Release gate accepted deliberately invalid case: $Case" }
}

try {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-release-hap.ps1') `
        -ResourceInputOnly -ResourceRoot $resourceRoot -SourceRoot $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Release gate rejected the production-only control case.' }

    $editorPath = Join-Path $rawfile 'keyboard-skin-editor.html'
    $editorOriginal = [IO.File]::ReadAllBytes($editorPath)
    Remove-Item -LiteralPath $editorPath
    Invoke-NegativeGate 'missing-offline-skin-editor'
    [IO.File]::WriteAllText($editorPath, '<html>outdated editor</html>')
    Invoke-NegativeGate 'outdated-offline-skin-editor'
    [IO.File]::WriteAllBytes($editorPath, $editorOriginal)

    $modulePath = Join-Path $sourceRoot 'module.json5'
    $moduleOriginal = [IO.File]::ReadAllText($modulePath, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($modulePath,
        $moduleOriginal.Replace('flypy-web-v1', 'unapproved-web-profile'), [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'unapproved-web-permission-profile'
    [IO.File]::WriteAllText($modulePath,
        $moduleOriginal.Replace('ohos.permission.VIBRATE', 'ohos.permission.CAMERA'), [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'web-profile-extra-permission'
    [IO.File]::WriteAllText($modulePath,
        ($moduleOriginal -replace '(?s)("name": "FlypyWebAbility".*?"exported": )false', '${1}true'), [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'web-ability-exported'
    [IO.File]::WriteAllText($modulePath, $moduleOriginal, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($modulePath,
        $moduleOriginal.Replace('ohos.permission.VIBRATE', 'ohos.permission.READ_PASTEBOARD'), [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'clipboard-permission-prevents-normal-apl-install'
    [IO.File]::WriteAllText($modulePath, $moduleOriginal, [Text.Encoding]::UTF8)

    $productionBytes = [IO.File]::ReadAllBytes($production)
    $productionBytes[$productionBytes.Length - 1] = $productionBytes[$productionBytes.Length - 1] -bxor 0x01
    [IO.File]::WriteAllBytes($production, $productionBytes)
    Invoke-NegativeGate 'tampered-production-lexicon'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex') `
        -Destination $production -Force

    $fixture = Join-Path $rawfile 'code-table-fixture-synthetic.bundle'
    [IO.File]::WriteAllBytes($fixture, [byte[]](0x54, 0x45, 0x53, 0x54))
    Invoke-NegativeGate 'synthetic-fixture'
    Remove-Item -LiteralPath $fixture -Force

    $rawSource = Join-Path $rawfile 'formal-source.txt'
    [IO.File]::WriteAllText($rawSource, "词条`tcode", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'raw-source'
    Remove-Item -LiteralPath $rawSource -Force

    $credentialNamed = Join-Path $rawfile 'delivery-token.bin'
    [IO.File]::WriteAllBytes($credentialNamed, [byte[]](0x46, 0x41, 0x4b, 0x45))
    Invoke-NegativeGate 'credential-resource'
    Remove-Item -LiteralPath $credentialNamed -Force

    [IO.File]::WriteAllText($indexSource, '@Entry struct DebugStage10 {}', [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'debug-provider-page'
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private title: string = '$debugAcceptanceText'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'debug-acceptance-text'
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private permission: string = 'ohos.permission.INTERNET'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'internet-permission'
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private permission: string = 'ohos.permission.MICROPHONE'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'microphone-permission'
    [IO.File]::WriteAllText($indexSource, '@Entry struct FakeAiProvider {}', [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'fake-ai-provider'
    [IO.File]::WriteAllText($indexSource, '@Entry struct DebugCloudAiProvider {}', [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'debug-cloud-provider'
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private config: string = 'endpoint: `"https://proxy.unit.test/v1/ime`"'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'reserved-test-endpoint'
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private apiKey: string = 'permanent-secret-value'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'permanent-key'
    [IO.File]::WriteAllText($indexSource, "@Entry struct Index { private key: string = '-----BEGIN PRIVATE KEY-----'; }", [Text.Encoding]::UTF8)
    Invoke-NegativeGate 'embedded-private-key'
    [IO.File]::WriteAllText($indexSource, '@Entry struct Index {}', [Text.Encoding]::UTF8)
    Write-Host 'RELEASE_RESOURCE_GATE_TEST_RESULT=PASS'
    $global:LASTEXITCODE = 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
