param(
    [switch]$SkipRust,
    [switch]$Clean,
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'release',
    # BuildMode controls code generation; Product selects the signing identity.
    [ValidateSet('', 'default', 'release', 'internalDebug')]
    [string]$Product = '',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$HarmonySdkRoot = $(if ($env:HARMONYOS_SDK_ROOT) { $env:HARMONYOS_SDK_ROOT } else { Join-Path $DevEcoRoot 'sdk' })
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Product)) {
    $Product = if ($BuildMode -eq 'debug') { 'internalDebug' } else { 'release' }
}
if (($BuildMode -eq 'debug' -and $Product -ne 'internalDebug') -or
    ($BuildMode -eq 'release' -and $Product -eq 'internalDebug')) {
    throw 'Use internalDebug for debug fixtures, or default/release for production code.'
}
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$customizationNode = Join-Path $DevEcoRoot 'tools\node\node.exe'
& $customizationNode (Join-Path $PSScriptRoot 'configure-keyboard-customization-sharing.cjs') --check --product $Product
if ($LASTEXITCODE -ne 0) { throw 'Keyboard customization shared-group/signing configuration mismatch.' }
$debugFixtureRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.stage11_6_3_debug_fixture'))
$debugFixtureResource = [IO.Path]::GetFullPath((Join-Path $repoRoot 'entry\src\internalDebug\resources\rawfile\code-table-fixture-synthetic.bundle'))
$debugActionFixtureSource = [IO.Path]::GetFullPath((Join-Path $repoRoot 'engine-rust\tests\fixtures\code-table\stage11_6_6_actions.json'))
$debugActionFixtureResource = [IO.Path]::GetFullPath((Join-Path $repoRoot 'entry\src\internalDebug\resources\rawfile\stage11_6_6_actions.json'))
$formalBundleSource = [IO.Path]::GetFullPath((Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'))
$formalBundleResource = [IO.Path]::GetFullPath((Join-Path $repoRoot 'entry\src\internalDebug\resources\rawfile\xiaohe-yinxing-production.hsyx'))
$debugSourceSetRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'entry\src\internalDebug\ets'))
$mainSourceRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'entry\src\main\ets'))
$debugOverlayBackupRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.stage11_6_6_debug_overlay_backup'))
$debugSourceMappings = @(
    @{ Source = 'pages\DebugIndex.ets'; Destination = 'pages\DebugIndex.ets' },
    @{ Source = 'pages\DebugStage10.ets'; Destination = 'pages\DebugStage10.ets' },
    @{ Source = 'pages\DebugCodeTable.ets'; Destination = 'pages\DebugCodeTable.ets' },
    @{ Source = 'pages\DebugStage1167Editor.ets'; Destination = 'pages\DebugStage1167Editor.ets' },
    @{ Source = 'infrastructure\Stage1167DeviceCommandBus.ets'; Destination = 'infrastructure\Stage1167DeviceCommandBus.ets' },
    @{ Source = 'infrastructure\resource\CodeTableFixtureInstaller.ets'; Destination = 'infrastructure\resource\CodeTableFixtureInstaller.ets' },
    @{
        Source = 'infrastructure\ime\ComputerCandidateCapabilityProbe.ets'
        Destination = 'infrastructure\ime\ComputerCandidateCapabilityProbe.ets'
    },
    @{
        Source = 'infrastructure\ime\ComputerCandidateProbeBus.ets'
        Destination = 'infrastructure\ime\ComputerCandidateProbeBus.ets'
    },
    @{
        Source = 'presentation\candidate\ComputerCandidateProbeRoot.ets'
        Destination = 'presentation\candidate\ComputerCandidateProbeRoot.ets'
    },
    @{
        Source = 'inputmethod\Stage0InputMethodAbility.ets'
        Destination = 'inputmethod\Stage0InputMethodAbility.ets'
        Overlay = $true
    }
)
if (-not $debugFixtureRoot.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $debugFixtureResource.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $debugActionFixtureSource.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $debugActionFixtureResource.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $formalBundleSource.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $formalBundleResource.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $debugSourceSetRoot.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $debugOverlayBackupRoot.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase) -or
    -not $mainSourceRoot.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to prepare Debug fixture outside the repository.'
}
if (Test-Path -LiteralPath $debugFixtureResource) {
    Remove-Item -LiteralPath $debugFixtureResource -Force
}
if (Test-Path -LiteralPath $formalBundleResource) {
    Remove-Item -LiteralPath $formalBundleResource -Force
}
if (Test-Path -LiteralPath $debugActionFixtureResource) {
    Remove-Item -LiteralPath $debugActionFixtureResource -Force
}

if (-not $SkipRust) {
    & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
}

$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path $hvigor)) {
    throw "hvigorw not found: $hvigor"
}

$env:DEVECO_SDK_HOME = $HarmonySdkRoot
try {
    if ($BuildMode -eq 'debug') {
        if (Test-Path -LiteralPath $debugOverlayBackupRoot) {
            Remove-Item -LiteralPath $debugOverlayBackupRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $debugFixtureRoot) {
            Remove-Item -LiteralPath $debugFixtureRoot -Recurse -Force
        }
        & cargo run --quiet --manifest-path (Join-Path $repoRoot 'engine-rust\Cargo.toml') -p code-table-fixture-generator -- all $debugFixtureRoot
        if ($LASTEXITCODE -ne 0) { throw "Debug fixture generation failed with exit code $LASTEXITCODE" }
        $builtFixture = Join-Path $debugFixtureRoot 'binary\code-table-fixture-synthetic.bundle'
        if (-not (Test-Path -LiteralPath $builtFixture)) { throw "Debug fixture bundle not found: $builtFixture" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $debugFixtureResource) -Force | Out-Null
        Copy-Item -LiteralPath $builtFixture -Destination $debugFixtureResource -Force
        $actionFixture = Get-Item -LiteralPath $debugActionFixtureSource
        $actionHash = (Get-FileHash -LiteralPath $debugActionFixtureSource -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actionFixture.Length -ne 2171 -or
            $actionHash -ne '05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63') {
            throw "Stage 11.6.6 action fixture identity mismatch: bytes=$($actionFixture.Length) sha256=$actionHash"
        }
        Copy-Item -LiteralPath $debugActionFixtureSource -Destination $debugActionFixtureResource -Force
        if (-not (Test-Path -LiteralPath $formalBundleSource -PathType Leaf)) {
            throw "Frozen formal bundle not found: $formalBundleSource"
        }
        $formalBundle = Get-Item -LiteralPath $formalBundleSource
        $formalHash = (Get-FileHash -LiteralPath $formalBundleSource -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($formalBundle.Length -ne 56104310 -or
            $formalHash -ne '7c936b7e451fffba4463306d03188addb772efc38b414a6d593ea2d618f48bf0') {
            throw "Frozen formal bundle identity mismatch: bytes=$($formalBundle.Length) sha256=$formalHash"
        }
        Copy-Item -LiteralPath $formalBundleSource -Destination $formalBundleResource -Force
        foreach ($mapping in $debugSourceMappings) {
            $source = Join-Path $debugSourceSetRoot $mapping.Source
            $destination = Join-Path $mainSourceRoot $mapping.Destination
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Debug source-set file not found: $source"
            }
            if (Test-Path -LiteralPath $destination) {
                if (-not $mapping.Overlay) {
                    throw "Refusing to overwrite main source while preparing Debug build: $destination"
                }
                $backup = Join-Path $debugOverlayBackupRoot $mapping.Destination
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Copy-Item -LiteralPath $destination -Destination $backup -Force
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }

    $targetName = if ($BuildMode -eq 'debug') { 'internalDebug' } else { 'default' }
    $productName = $Product
    # Release packages must never reuse test/debug intermediates. A previous ArkTS
    # test run can leave a default-product profile with debug metadata, so Release
    # builds always start from a clean Hvigor graph even when -Clean is omitted.
    $shouldClean = $Clean -or $BuildMode -eq 'release'
    Push-Location $repoRoot
    try {
        if ($shouldClean) {
            & $hvigor --no-daemon clean
            if ($LASTEXITCODE -ne 0) {
                throw "HAP clean failed with exit code $LASTEXITCODE"
            }
        }
        & $hvigor --no-daemon --mode module -p product=$productName -p module="entry@$targetName" -p buildMode=$BuildMode assembleHap
        if ($LASTEXITCODE -ne 0) {
            throw "HAP build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} finally {
    foreach ($mapping in $debugSourceMappings) {
        $destination = Join-Path $mainSourceRoot $mapping.Destination
        $backup = Join-Path $debugOverlayBackupRoot $mapping.Destination
        if ($mapping.Overlay -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            # The compiler can briefly keep the overlaid file memory-mapped
            # after assembleHap finishes. Restore the original before cleanup.
            for ($restoreAttempt = 1; $restoreAttempt -le 5; $restoreAttempt++) {
                try {
                    Copy-Item -LiteralPath $backup -Destination $destination -Force -ErrorAction Stop
                    break
                } catch {
                    if ($restoreAttempt -eq 5) { throw }
                    Start-Sleep -Milliseconds (250 * $restoreAttempt)
                }
            }
        } elseif (-not $mapping.Overlay -and (Test-Path -LiteralPath $destination)) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    if (Test-Path -LiteralPath $debugOverlayBackupRoot) {
        Remove-Item -LiteralPath $debugOverlayBackupRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $debugFixtureResource) {
        Remove-Item -LiteralPath $debugFixtureResource -Force
    }
    if (Test-Path -LiteralPath $formalBundleResource) {
        Remove-Item -LiteralPath $formalBundleResource -Force
    }
    if (Test-Path -LiteralPath $debugActionFixtureResource) {
        Remove-Item -LiteralPath $debugActionFixtureResource -Force
    }
    if (Test-Path -LiteralPath $debugFixtureRoot) {
        Remove-Item -LiteralPath $debugFixtureRoot -Recurse -Force
    }
}

$buildVariantRoot = $Product
$hapPath = Join-Path $repoRoot "entry\build\$buildVariantRoot\outputs\$targetName\entry-$targetName-unsigned.hap"
if (-not (Test-Path -LiteralPath $hapPath)) { throw "HAP artifact not found: $hapPath" }
$hap = Get-Item -LiteralPath $hapPath

$profilePath = Join-Path $repoRoot "entry\build\$buildVariantRoot\intermediates\process_profile\$targetName\module.json"
if (-not (Test-Path -LiteralPath $profilePath)) {
    throw "Generated module profile not found: $profilePath"
}
$profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$profile.app.buildMode -ne $BuildMode -or [bool]$profile.app.debug -ne ($BuildMode -eq 'debug')) {
    throw "Generated HAP mode mismatch: requested=$BuildMode actual=$($profile.app.buildMode) debug=$($profile.app.debug)"
}

$artifactDir = Join-Path $repoRoot 'entry\build\artifacts'
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
$artifact = Join-Path $artifactDir "entry-$BuildMode-unsigned.hap"
Copy-Item -LiteralPath $hap.FullName -Destination $artifact -Force
$artifactItem = Get-Item -LiteralPath $artifact

Write-Host "BUILD_MODE=$BuildMode"
Write-Host "PRODUCT=$Product"
Write-Host "CLEAN_BUILD=$($shouldClean.ToString().ToLowerInvariant())"
Write-Host "DEBUG=$($profile.app.debug.ToString().ToLowerInvariant())"
Write-Host "HAP: $($artifactItem.FullName)"
Write-Host "Size: $($artifactItem.Length) bytes"
