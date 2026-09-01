param(
    [string]$HapPath = '',
    [switch]$ResourceInputOnly,
    [string]$ResourceRoot = '',
    [string]$SourceRoot = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$resourceRoot = if ([string]::IsNullOrWhiteSpace($ResourceRoot)) {
    Join-Path $repoRoot 'entry\src\main\resources'
} else {
    [IO.Path]::GetFullPath($ResourceRoot)
}
$rawfileRoot = Join-Path $resourceRoot 'rawfile'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    Join-Path $repoRoot 'entry\src\main'
} else {
    [IO.Path]::GetFullPath($SourceRoot)
}
$debugAcceptanceText = -join (@(0x8C03, 0x8BD5, 0x4E0E, 0x9A8C, 0x6536) | ForEach-Object { [char]$_ })
$expectedProductionLexiconSize = 24049458
$expectedProductionLexiconSha256 = '005169f6050d45f93dd511d7de183338419419b67fb3556065b15432b0522a41'
$expectedQuanpinContextModelSize = 64300
$expectedQuanpinContextModelSha256 = '15b55101d77a87a64d2d414f96147291f7e260a138c98ecbea1d38af2f17b05f'
$expectedYinxingBundleSize = 56104660
$expectedYinxingBundleSha256 = '263f077c0602141c764ad1623d001bc128aae25471b450ba3bae51c68ab9bc09'
$releaseForbiddenPermissions = @(
    'ohos.permission.INTERNET',
    'ohos.permission.MICROPHONE'
)
$forbiddenDebugContent = @(
    'DebugStage10',
    'DebugCodeTable',
    'FakeAiProvider',
    'FakeSpeechProvider',
    'DebugAiProvider',
    'DebugCloudAiProvider',
    $debugAcceptanceText
)

function Stop-ReleaseGate([string]$RuleId, [string]$Path, [string]$Reason, [string]$Fix) {
    [Console]::Error.WriteLine("RULE_ID=$RuleId")
    [Console]::Error.WriteLine("FILE_PATH=$Path")
    [Console]::Error.WriteLine("REASON=$Reason")
    [Console]::Error.WriteLine("FIX=$Fix")
    exit 1
}

function Assert-ReleaseSourceInputs {
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        Stop-ReleaseGate 'REL_SOURCE_ROOT_MISSING' $sourceRoot 'Release source directory is missing' 'Restore the default Release source set.'
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object {
        $_.Extension -in @('.ets', '.ts', '.json', '.json5')
    })
    foreach ($file in $sourceFiles) {
        $content = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        foreach ($forbidden in $forbiddenDebugContent) {
            if ($content.Contains($forbidden)) {
                $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
                Stop-ReleaseGate 'REL_SOURCE_FORBIDDEN_IDENTIFIER' $relative "Release source contains forbidden identifier '$forbidden'" 'Remove the Debug, legacy, or internal-scheme reference from the Release source set.'
            }
        }
        foreach ($permission in $releaseForbiddenPermissions) {
            if ($content.Contains([string]$permission)) {
                $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
                Stop-ReleaseGate 'REL_NETWORK_PERMISSION' $relative "Release source declares forbidden permission '$permission'" 'Keep unapproved cloud and microphone capabilities disabled; add only a separately approved, exact product permission profile.'
            }
        }
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        if ($content -match '(?i)endpoint\s*:\s*[''"]https?://(localhost|127\.0\.0\.1|[^''"]+\.(test|invalid))') {
            Stop-ReleaseGate 'REL_AI_TEST_ENDPOINT' $relative 'Release source contains a localhost or reserved test AI endpoint' 'Inject only an approved production HTTPS proxy configuration outside the default unconfigured Release source.'
        }
        if ($content -match '(?i)(api[_-]?key|permanent[_-]?key)[^=\r\n]{0,64}=\s*[''"][^''"]+[''"]' -or
            $content -match '[''"]sk-[A-Za-z0-9_-]{12,}[''"]') {
            Stop-ReleaseGate 'REL_AI_PERMANENT_KEY' $relative 'Release source contains a permanent or model-vendor API key literal' 'Use short-lived proxy authentication supplied by the approved transport integration; never package permanent credentials.'
        }
        if ($content -match '-----BEGIN (RSA |EC )?PRIVATE KEY-----' -or
            $content -match '-----BEGIN CERTIFICATE-----') {
            Stop-ReleaseGate 'REL_AI_TEST_CERTIFICATE' $relative 'Release source contains embedded certificate or private-key material' 'Use the platform trust store and approved production TLS configuration.'
        }
    }

    $moduleProfilePath = Join-Path $sourceRoot 'module.json5'
    $moduleProfileText = [IO.File]::ReadAllText($moduleProfilePath, [Text.Encoding]::UTF8)
    if ($moduleProfileText -notmatch '"name"\s*:\s*"ohos\.extension\.input_method"' -or
        $moduleProfileText -notmatch '"resource"\s*:\s*"\$profile:stage0_input_method"') {
        Stop-ReleaseGate 'REL_IME_SUBTYPE_METADATA' 'module.json5' 'Input-method subtype metadata is missing or references the wrong profile' 'Declare ohos.extension.input_method metadata with $profile:stage0_input_method.'
    }

    $subtypeProfilePath = Join-Path $sourceRoot 'resources\base\profile\stage0_input_method.json'
    if (-not (Test-Path -LiteralPath $subtypeProfilePath -PathType Leaf)) {
        Stop-ReleaseGate 'REL_IME_SUBTYPE_PROFILE_MISSING' 'resources/base/profile/stage0_input_method.json' 'Input-method subtype profile is missing' 'Restore the standard subtype profile.'
    }
    try {
        $subtypeProfile = [IO.File]::ReadAllText($subtypeProfilePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        Stop-ReleaseGate 'REL_IME_SUBTYPE_PROFILE_INVALID' 'resources/base/profile/stage0_input_method.json' 'Input-method subtype profile is not valid JSON' 'Restore a valid standard subtype profile.'
    }
    $zhCnSubtypes = @($subtypeProfile.subtypes | Where-Object {
        [string]$_.id -eq 'shuangyu_zh_cn' -and [string]$_.locale -eq 'zh-CN'
    })
    if ($zhCnSubtypes.Count -ne 1) {
        Stop-ReleaseGate 'REL_IME_ZH_CN_SUBTYPE' 'resources/base/profile/stage0_input_method.json' 'The required shuangyu_zh_cn / zh-CN subtype is missing or duplicated' 'Declare exactly one standard Chinese subtype.'
    }

    $abilityPath = Join-Path $sourceRoot 'ets\inputmethod\Stage0InputMethodAbilityBase.ets'
    $abilityText = [IO.File]::ReadAllText($abilityPath, [Text.Encoding]::UTF8)
    foreach ($subscription in @("keyboardDelegate.on('keyEvent'", "keyboardDelegate.on('keyDown'", "keyboardDelegate.on('keyUp'")) {
        if (-not $abilityText.Contains($subscription)) {
            Stop-ReleaseGate 'REL_IME_PC_KEY_CHANNEL' 'ets/inputmethod/Stage0InputMethodAbilityBase.ets' "Required physical-key subscription is missing: $subscription" 'Keep both modern keyEvent and PC-compatible keyDown/keyUp subscriptions.'
        }
    }
}

function Assert-ReleaseResourceInputs {
    if (-not (Test-Path -LiteralPath $rawfileRoot -PathType Container)) {
        Stop-ReleaseGate 'REL_RAWFILE_ROOT_MISSING' $rawfileRoot 'Release rawfile directory is missing' 'Restore the audited rawfile directory.'
    }
    $approvedRawfiles = @(
        'rawfile/production.lex',
        'rawfile/quanpin-context-v2.qng',
        'rawfile/xiaohe-yinxing-production.hsyx'
    )
    $rawfiles = @(Get-ChildItem -LiteralPath $rawfileRoot -Recurse -File)
    foreach ($file in $rawfiles) {
        $relative = $file.FullName.Substring($resourceRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($relative -notin $approvedRawfiles) {
            Stop-ReleaseGate 'REL_RAWFILE_NOT_APPROVED' "resources/$relative" "Release rawfile '$relative' is not in the approved list" 'Only the audited production lexicon, quanpin context model, and Xiaohe Yinxing bundle are approved for Release.'
        }
    }
    $rawSourceFiles = @(Get-ChildItem -LiteralPath $resourceRoot -Recurse -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @('.txt', '.ini')
    })
    if ($rawSourceFiles.Count -gt 0) {
        $paths = $rawSourceFiles | ForEach-Object { $_.FullName.Substring($repoRoot.Path.Length).TrimStart('\', '/') }
        Stop-ReleaseGate 'REL_RAW_SOURCE_FILE' ($paths -join ', ') 'Release resources contain raw TXT or INI delivery data' 'Keep formal source files under the read-only delivery roots and package only an approved binary bundle.'
    }
    $sensitiveNamedFiles = @(Get-ChildItem -LiteralPath $resourceRoot -Recurse -File | Where-Object {
        $name = $_.Name.ToLowerInvariant()
        $name -match '(password|passwd|token|secret|credential|api[_-]?key)' -or
            $name -match 'xiaohe_yinxing_(security|source_audit|conflict|approval)'
    })
    if ($sensitiveNamedFiles.Count -gt 0) {
        $paths = $sensitiveNamedFiles | ForEach-Object { $_.FullName.Substring($repoRoot.Path.Length).TrimStart('\', '/') }
        Stop-ReleaseGate 'REL_SENSITIVE_AUDIT_RESOURCE' ($paths -join ', ') 'Release resources contain a credential-named file or an audit report' 'Keep security evidence and audit reports outside HAP resources.'
    }
    $forbidden = @(Get-ChildItem -LiteralPath $resourceRoot -Recurse -File | Where-Object {
        $relative = $_.FullName.Substring($resourceRoot.Length).TrimStart('\', '/').Replace('\', '/').ToLowerInvariant()
        $relative -match '(^|[/_.-])(fixture|synthetic|test)([/_.-]|$)' -or
            $relative.Contains('code-table') -or
            $relative.EndsWith('.bundle') -or
            $relative.EndsWith('fixture-manifest.json')
    })
    if ($forbidden.Count -gt 0) {
        $paths = $forbidden | ForEach-Object { $_.FullName.Substring($repoRoot.Path.Length).TrimStart('\', '/') }
        Stop-ReleaseGate 'REL_FIXTURE_RESOURCE' ($paths -join ', ') 'Release resource inputs contain fixture, synthetic, test, or code-table assets' 'Keep these resources in tests or internalDebug only.'
    }
    $productionLexicon = Join-Path $rawfileRoot 'production.lex'
    if (-not (Test-Path -LiteralPath $productionLexicon -PathType Leaf)) {
        Stop-ReleaseGate 'REL_PRODUCTION_LEXICON_MISSING' 'resources/rawfile/production.lex' 'The approved production lexicon is missing' 'Restore the audited production lexicon.'
    }
    $productionLexiconItem = Get-Item -LiteralPath $productionLexicon
    if ($productionLexiconItem.Length -ne $expectedProductionLexiconSize) {
        Stop-ReleaseGate 'REL_PRODUCTION_LEXICON_SIZE' 'resources/rawfile/production.lex' "Production lexicon size mismatch: expected $expectedProductionLexiconSize, got $($productionLexiconItem.Length)" 'Restore the audited production lexicon.'
    }
    $productionLexiconHash = (Get-FileHash -LiteralPath $productionLexicon -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($productionLexiconHash -ne $expectedProductionLexiconSha256) {
        Stop-ReleaseGate 'REL_PRODUCTION_LEXICON_HASH' 'resources/rawfile/production.lex' 'Production lexicon SHA-256 does not match the approved manifest' 'Restore the audited production lexicon and rebuild.'
    }
    $contextModel = Join-Path $rawfileRoot 'quanpin-context-v2.qng'
    if (-not (Test-Path -LiteralPath $contextModel -PathType Leaf)) {
        Stop-ReleaseGate 'REL_QUANPIN_CONTEXT_MODEL_MISSING' 'resources/rawfile/quanpin-context-v2.qng' 'The audited quanpin context model is missing' 'Rebuild it with the deterministic Rust model builder.'
    }
    $contextModelItem = Get-Item -LiteralPath $contextModel
    if ($contextModelItem.Length -ne $expectedQuanpinContextModelSize) {
        Stop-ReleaseGate 'REL_QUANPIN_CONTEXT_MODEL_SIZE' 'resources/rawfile/quanpin-context-v2.qng' "Context model size mismatch: expected $expectedQuanpinContextModelSize, got $($contextModelItem.Length)" 'Restore the audited context model.'
    }
    $contextModelHash = (Get-FileHash -LiteralPath $contextModel -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($contextModelHash -ne $expectedQuanpinContextModelSha256) {
        Stop-ReleaseGate 'REL_QUANPIN_CONTEXT_MODEL_HASH' 'resources/rawfile/quanpin-context-v2.qng' 'Context model SHA-256 does not match the approved identity' 'Restore the audited context model and rebuild.'
    }
    $formalBundle = Join-Path $rawfileRoot 'xiaohe-yinxing-production.hsyx'
    if (-not (Test-Path -LiteralPath $formalBundle -PathType Leaf)) {
        Stop-ReleaseGate 'REL_YINXING_BUNDLE_MISSING' 'resources/rawfile/xiaohe-yinxing-production.hsyx' 'The approved formal bundle is missing' 'Restore the audited formal bundle.'
    }
    $formalItem = Get-Item -LiteralPath $formalBundle
    if ($formalItem.Length -ne $expectedYinxingBundleSize) {
        Stop-ReleaseGate 'REL_YINXING_BUNDLE_SIZE' 'resources/rawfile/xiaohe-yinxing-production.hsyx' "Formal bundle size mismatch: expected $expectedYinxingBundleSize, got $($formalItem.Length)" 'Restore the audited formal bundle.'
    }
    $formalHash = (Get-FileHash -LiteralPath $formalBundle -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($formalHash -ne $expectedYinxingBundleSha256) {
        Stop-ReleaseGate 'REL_YINXING_BUNDLE_HASH' 'resources/rawfile/xiaohe-yinxing-production.hsyx' 'Formal bundle SHA-256 does not match the approved manifest' 'Restore the audited formal bundle and rebuild.'
    }
}

Assert-ReleaseSourceInputs
Assert-ReleaseResourceInputs
if ($ResourceInputOnly) {
    Write-Host 'RELEASE_RESOURCE_INPUT_VERIFY_RESULT=PASS'
    exit 0
}
if ([string]::IsNullOrWhiteSpace($HapPath)) {
    $HapPath = Join-Path $repoRoot 'entry\build\artifacts\entry-release-unsigned.hap'
}
$hap = Get-Item -LiteralPath $HapPath

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($hap.FullName)
try {
    $entries = @($archive.Entries)
    $moduleEntry = $entries | Where-Object { $_.FullName -eq 'module.json' } | Select-Object -First 1
    if ($null -eq $moduleEntry) { Stop-ReleaseGate 'REL_HAP_MODULE_MISSING' $hap.FullName 'Release HAP is missing module.json' 'Rebuild a valid Release HAP.' }

    $reader = [System.IO.StreamReader]::new($moduleEntry.Open(), [System.Text.Encoding]::UTF8)
    try { $moduleText = $reader.ReadToEnd(); $module = $moduleText | ConvertFrom-Json } finally { $reader.Dispose() }
    if ([string]$module.app.buildMode -ne 'release' -or [bool]$module.app.debug) {
        Stop-ReleaseGate 'REL_HAP_BUILD_MODE' $hap.FullName "HAP is not Release: buildMode=$($module.app.buildMode) debug=$($module.app.debug)" 'Build the default product in release mode.'
    }
    $inputMethodExtension = @($module.module.extensionAbilities | Where-Object {
        [string]$_.name -eq 'Stage0InputMethodAbility' -and [string]$_.type -eq 'inputMethod'
    }) | Select-Object -First 1
    if ($null -eq $inputMethodExtension) {
        Stop-ReleaseGate 'REL_HAP_IME_EXTENSION_MISSING' 'module.json' 'Release HAP is missing Stage0InputMethodAbility' 'Rebuild the Release HAP with the input-method extension.'
    }
    $inputMethodMetadata = @($inputMethodExtension.metadata | Where-Object {
        [string]$_.name -eq 'ohos.extension.input_method'
    }) | Select-Object -First 1
    if ($null -eq $inputMethodMetadata) {
        Stop-ReleaseGate 'REL_HAP_IME_SUBTYPE_METADATA' 'module.json' 'Packaged input-method extension is missing standard subtype metadata' 'Restore the metadata and rebuild without stale profile outputs.'
    }
    foreach ($permission in $releaseForbiddenPermissions) {
        if ($moduleText.Contains([string]$permission)) {
            Stop-ReleaseGate 'REL_NETWORK_PERMISSION' 'module.json' "Release HAP declares forbidden permission '$permission'" 'Remove the network permission and rebuild.'
        }
    }

    $entryNames = @($entries | ForEach-Object { $_.FullName })
    $subtypeEntry = $entries | Where-Object {
        $_.FullName -eq 'resources/base/profile/stage0_input_method.json'
    } | Select-Object -First 1
    if ($null -eq $subtypeEntry) {
        Stop-ReleaseGate 'REL_HAP_IME_SUBTYPE_PROFILE_MISSING' 'resources/base/profile/stage0_input_method.json' 'Release HAP is missing the input-method subtype profile' 'Restore the profile and rebuild.'
    }
    $subtypeReader = [System.IO.StreamReader]::new($subtypeEntry.Open(), [System.Text.Encoding]::UTF8)
    try {
        $packagedSubtypeProfile = $subtypeReader.ReadToEnd() | ConvertFrom-Json
    } finally {
        $subtypeReader.Dispose()
    }
    $packagedZhCnSubtypes = @($packagedSubtypeProfile.subtypes | Where-Object {
        [string]$_.id -eq 'shuangyu_zh_cn' -and [string]$_.locale -eq 'zh-CN'
    })
    if ($packagedZhCnSubtypes.Count -ne 1) {
        Stop-ReleaseGate 'REL_HAP_IME_ZH_CN_SUBTYPE' 'resources/base/profile/stage0_input_method.json' 'Packaged HAP does not contain exactly one shuangyu_zh_cn / zh-CN subtype' 'Rebuild from the corrected subtype profile.'
    }
    $packagedRawfiles = @($entryNames | Where-Object { $_ -like 'resources/rawfile/*' })
    $approvedHapRawfiles = @(
        'resources/rawfile/production.lex',
        'resources/rawfile/quanpin-context-v2.qng',
        'resources/rawfile/xiaohe-yinxing-production.hsyx'
    )
    foreach ($resource in $packagedRawfiles) {
        if ($resource -notin $approvedHapRawfiles) {
            Stop-ReleaseGate 'REL_HAP_RAWFILE_NOT_APPROVED' $resource 'Release HAP contains an unapproved rawfile resource' 'Only the audited production lexicon, quanpin context model, and Xiaohe Yinxing bundle are approved.'
        }
    }
    $forbiddenPackagedResources = @($entryNames | Where-Object {
        $name = $_.ToLowerInvariant()
        $name.StartsWith('resources/') -and (
            $name -match '(^|[/_.-])(fixture|synthetic|test)([/_.-]|$)' -or
            $name.Contains('code-table') -or
            ($name.EndsWith('.hsyx') -and $name -ne 'resources/rawfile/xiaohe-yinxing-production.hsyx') -or
            $name.EndsWith('.bundle') -or
            $name.EndsWith('fixture-manifest.json') -or
            $name.Contains('trace-index') -or
            $name.Contains('build-report') -or
            $name.Contains('source-audit') -or
            $name.EndsWith('.txt') -or
            $name.EndsWith('.ini') -or
            $name -match '(password|passwd|token|secret|credential|api[_-]?key)' -or
            $name -match 'xiaohe_yinxing_(security|source_audit|conflict|approval)'
        )
    })
    if ($forbiddenPackagedResources.Count -gt 0) {
        Stop-ReleaseGate 'REL_HAP_FIXTURE_RESOURCE' ($forbiddenPackagedResources -join ', ') 'Release HAP contains forbidden test or code-table resources' 'Remove the resources from the default target and rebuild.'
    }
    $production = $entries | Where-Object { $_.FullName -eq 'resources/rawfile/production.lex' } | Select-Object -First 1
    if ($null -eq $production -or $production.Length -ne $expectedProductionLexiconSize) {
        Stop-ReleaseGate 'REL_PRODUCTION_LEXICON_INVALID' 'resources/rawfile/production.lex' 'production.lex is missing or has an unexpected size' 'Rebuild it from the pinned stage 11.5 inputs.'
    }
    $productionStream = $production.Open()
    $productionSha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $packagedProductionHash = ([BitConverter]::ToString($productionSha256.ComputeHash($productionStream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $productionSha256.Dispose()
        $productionStream.Dispose()
    }
    if ($packagedProductionHash -ne $expectedProductionLexiconSha256) {
        Stop-ReleaseGate 'REL_HAP_PRODUCTION_LEXICON_HASH' 'resources/rawfile/production.lex' 'Packaged production lexicon SHA-256 does not match the approved manifest' 'Restore the audited production lexicon and rebuild the Release HAP.'
    }

    $contextModel = $entries | Where-Object { $_.FullName -eq 'resources/rawfile/quanpin-context-v2.qng' } | Select-Object -First 1
    if ($null -eq $contextModel -or $contextModel.Length -ne $expectedQuanpinContextModelSize) {
        Stop-ReleaseGate 'REL_HAP_QUANPIN_CONTEXT_MODEL_INVALID' 'resources/rawfile/quanpin-context-v2.qng' 'Context model is missing or has an unexpected size' 'Rebuild the audited Release HAP.'
    }
    $contextModelStream = $contextModel.Open()
    $contextModelSha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $packagedContextModelHash = ([BitConverter]::ToString($contextModelSha256.ComputeHash($contextModelStream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $contextModelSha256.Dispose()
        $contextModelStream.Dispose()
    }
    if ($packagedContextModelHash -ne $expectedQuanpinContextModelSha256) {
        Stop-ReleaseGate 'REL_HAP_QUANPIN_CONTEXT_MODEL_HASH' 'resources/rawfile/quanpin-context-v2.qng' 'Packaged context model SHA-256 does not match the approved identity' 'Restore the audited context model and rebuild the Release HAP.'
    }

    $yinxingBundle = $entries | Where-Object { $_.FullName -eq 'resources/rawfile/xiaohe-yinxing-production.hsyx' } | Select-Object -First 1
    if ($null -eq $yinxingBundle) {
        Stop-ReleaseGate 'REL_YINXING_BUNDLE_MISSING' 'resources/rawfile/xiaohe-yinxing-production.hsyx' 'xiaohe-yinxing-production.hsyx is missing from Release HAP' 'Ensure the formal bundle is in rawfile directory before building.'
    }
    if ($yinxingBundle.Length -ne $expectedYinxingBundleSize) {
        Stop-ReleaseGate 'REL_YINXING_BUNDLE_SIZE' 'resources/rawfile/xiaohe-yinxing-production.hsyx' "xiaohe-yinxing-production.hsyx has unexpected size: expected $expectedYinxingBundleSize, got $($yinxingBundle.Length)" 'Verify the bundle matches the audited source.'
    }
    $yinxingStream = $yinxingBundle.Open()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $packagedYinxingHash = ([BitConverter]::ToString($sha256.ComputeHash($yinxingStream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
        $yinxingStream.Dispose()
    }
    if ($packagedYinxingHash -ne $expectedYinxingBundleSha256) {
        Stop-ReleaseGate 'REL_HAP_YINXING_BUNDLE_HASH' 'resources/rawfile/xiaohe-yinxing-production.hsyx' 'Packaged formal bundle SHA-256 does not match the approved manifest' 'Restore the audited formal bundle and rebuild the Release HAP.'
    }

    $forbiddenIdentifiers = @(
        'DebugStage10',
        'DebugCodeTable',
        $debugAcceptanceText,
        'getTestCandidates',
        'ime_engine_get_test_candidates',
        'commitRegressionCandidate',
        'getDebugUserModelRecordCount',
        'refreshRegressionCandidates',
        'commitFixedCandidateText',
        'FakeAiProvider',
        'FakeSpeechProvider',
        'DebugAiProvider',
        'DebugCloudAiProvider'
    )
    foreach ($compiledEntry in @($entries | Where-Object {
        $_.FullName -eq 'ets/modules.abc' -or $_.FullName -like 'libs/*/libime_bridge.so'
    })) {
        $memory = [System.IO.MemoryStream]::new()
        $stream = $compiledEntry.Open()
        try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
        $bytes = $memory.ToArray()
        $memory.Dispose()
        foreach ($identifier in $forbiddenIdentifiers) {
            $containsIdentifier = [Text.Encoding]::UTF8.GetString($bytes).Contains($identifier) -or
                [Text.Encoding]::Unicode.GetString($bytes).Contains($identifier)
            if ($containsIdentifier) {
                Stop-ReleaseGate 'REL_HAP_FORBIDDEN_IDENTIFIER' $compiledEntry.FullName "compiled Release content contains forbidden identifier '$identifier'" 'Remove the Debug, legacy, or internal-scheme reference and rebuild.'
            }
        }
    }
} finally {
    $archive.Dispose()
}

$hash = Get-FileHash -LiteralPath $hap.FullName -Algorithm SHA256
Write-Host 'RELEASE_HAP_VERIFY_RESULT=PASS'
Write-Host "HAP=$($hap.FullName)"
Write-Host "HAP_SIZE=$($hap.Length)"
Write-Host "HAP_SHA256=$($hash.Hash)"
