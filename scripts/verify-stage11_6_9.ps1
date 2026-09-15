param(
    [ValidateSet('Host', 'Build', 'Phone', 'Pad', 'Arm64', 'Performance', 'Full')]
    [string]$Scope = 'Full',
    [string]$DeviceSerial = '',
    [string]$PhoneSerial = '',
    [string]$PadSerial = '',
    [string]$Arm64Serial = '',
    [switch]$SkipSignatureReview,
    [switch]$ContinueOnFailure,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$startedAt = Get-Date
$runId = '{0}-{1}' -f $startedAt.ToString('yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$evidenceRoot = Join-Path $repoRoot ('docs\evidence\{0}-stage-11.6.9-final-acceptance' -f $startedAt.ToString('yyyy-MM-dd'))
$runRoot = Join-Path $evidenceRoot ('runs\' + $runId)
$logRoot = Join-Path $runRoot 'reports'
$deviceRoot = Join-Path $runRoot 'devices'
$tempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('harmony-stage11-6-9-' + $runId)))
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
$java = Join-Path $DevEcoRoot 'jbr\bin\java.exe'
$signTool = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$results = [Collections.Generic.List[object]]::new()
$devices = [Collections.Generic.List[object]]::new()
$artifacts = [ordered]@{}

New-Item -ItemType Directory -Path $logRoot, $deviceRoot, $tempRoot -Force | Out-Null

function Convert-ToRelativePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
    }
    return [IO.Path]::GetFileName($full)
}

function Add-Result([string]$Name, [string]$Status, [string]$Detail, [double]$DurationMs = 0) {
    $results.Add([ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
        durationMs = [math]::Round($DurationMs, 3)
    }) | Out-Null
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$RequiredMarker = ''
    )
    $safeName = $Name -replace '[^0-9A-Za-z._-]', '_'
    $logPath = Join-Path $logRoot ($safeName + '.log')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "`n== $Name =="
    try {
        $global:LASTEXITCODE = 0
        $previousPreference = $ErrorActionPreference
        # Do not merge native stderr into the success pipeline. Windows
        # PowerShell represents cargo/hvigor progress and warnings as
        # ErrorRecord objects even when their process exit code is zero.
        $ErrorActionPreference = 'Continue'
        try {
            & $Action
            $stepExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($stepExitCode -ne 0) {
            throw "exit code $stepExitCode"
        }
        $watch.Stop()
        @(
            "STEP=$Name"
            'STATUS=PASS'
            "REQUIRED_MARKER=$RequiredMarker"
            "DURATION_MS=$([math]::Round($watch.Elapsed.TotalMilliseconds, 3))"
        ) | Out-File -LiteralPath $logPath -Encoding utf8
        Add-Result $Name 'PASS' (Convert-ToRelativePath $logPath) $watch.Elapsed.TotalMilliseconds
        return $true
    } catch {
        $watch.Stop()
        $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding utf8
        Add-Result $Name 'FAIL' $_.Exception.Message $watch.Elapsed.TotalMilliseconds
        Write-Host "FAIL: $Name - $($_.Exception.Message)"
        if (-not $ContinueOnFailure) { throw }
        return $false
    }
}

function Add-NotRun([string]$Name, [string]$Reason) {
    Add-Result $Name 'NOT_RUN' $Reason
}

function Get-FileIdentity([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = Convert-ToRelativePath $item.FullName
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        lastWriteTime = $item.LastWriteTime.ToString('o')
    }
}

function Assert-CurrentArtifact([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name is missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.LastWriteTime -lt $startedAt.AddMinutes(-1)) {
        throw "$Name was not produced by this run (lastWriteTime=$($item.LastWriteTime.ToString('o')))"
    }
}

function Get-GitSnapshot {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $gitOutput = @(& git -C $repoRoot status --short --branch 2>&1)
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($LASTEXITCODE -eq 0) {
        $commit = @(& git -C $repoRoot rev-parse HEAD 2>&1)
        return [ordered]@{
            available = $true
            commit = ($commit -join '').Trim()
            status = $gitOutput
        }
    }
    return [ordered]@{
        available = $false
        commit = ''
        status = @('Git metadata unavailable; repository .git directory is not recognized by git.')
    }
}

function Get-ToolVersion([string]$Command) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Command --version 2>&1)
        return (($output | Where-Object { [string]$_ -notmatch '^warn:' }) -join ' ').Trim()
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Get-ConnectedDevices {
    if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { return @() }
    $targetLines = @(& $hdc list targets -v 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'hdc target enumeration failed' }
    $found = foreach ($line in $targetLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $serial = ($line -split '\s+')[0]
        $type = ((& $hdc -t $serial shell param get const.product.devicetype 2>&1) -join '').Trim()
        $abi = ((& $hdc -t $serial shell param get const.product.cpu.abilist 2>&1) -join '').Trim()
        $api = ((& $hdc -t $serial shell param get const.ohos.apiversion 2>&1) -join '').Trim()
        $version = ((& $hdc -t $serial shell param get const.ohos.fullname 2>&1) -join '').Trim()
        $model = ((& $hdc -t $serial shell param get const.product.model 2>&1) -join '').Trim()
        $screenLines = @(& $hdc -t $serial shell hidumper -s RenderService -a screen 2>&1)
        $modeLine = ($screenLines | Select-String -Pattern 'activeMode:\s*\d+x\d+' | Select-Object -First 1).Line
        $resolution = if ($modeLine -match 'activeMode:\s*(\d+x\d+)') { $Matches[1] } else { 'unknown' }
        $connection = if ($line -match '\sTCP\s') { 'TCP' } else { 'other' }
        [ordered]@{
            serial = $serial
            type = $type.ToLowerInvariant()
            abi = $abi.ToLowerInvariant()
            api = $api
            systemVersion = $version
            model = $model
            resolution = $resolution
            connection = $connection
            emulator = ($model -match '(?i)emulator|simulator')
            orientation = if ($resolution -match '^(\d+)x(\d+)$' -and [int]$Matches[1] -gt [int]$Matches[2]) { 'landscape' } else { 'portrait' }
        }
    }
    return @($found)
}

function Select-Device([string]$Kind, [string]$ExplicitSerial) {
    $all = @($devices)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitSerial)) {
        $match = @($all | Where-Object { $_.serial -eq $ExplicitSerial })
        if ($match.Count -ne 1) { throw "Requested device is not connected: $ExplicitSerial" }
        return $match[0]
    }
    switch ($Kind) {
        'Phone' { $match = @($all | Where-Object { $_.type -eq 'phone' -and $_.abi -match 'x86_64' }) }
        'Pad' { $match = @($all | Where-Object { $_.type -in @('tablet', 'pad') -and $_.abi -match 'x86_64' }) }
        'Arm64' { $match = @($all | Where-Object { $_.abi -match 'arm64|aarch64' -and -not $_.emulator }) }
    }
    if ($match.Count -eq 0) { return $null }
    if ($match.Count -gt 1) { throw "Multiple $Kind devices are connected; specify the serial explicitly." }
    return $match[0]
}

function Compare-ProductionBuilds {
    $left = Join-Path $tempRoot 'production-left'
    $right = Join-Path $tempRoot 'production-right'
    & (Join-Path $PSScriptRoot 'build-xiaohe-yinxing-production.ps1') -OutputDirectory $left
    if ($LASTEXITCODE -ne 0) { throw 'first production build failed' }
    & (Join-Path $PSScriptRoot 'build-xiaohe-yinxing-production.ps1') -OutputDirectory $right
    if ($LASTEXITCODE -ne 0) { throw 'second production build failed' }
    $leftFiles = @(Get-ChildItem -LiteralPath $left -Recurse -File | ForEach-Object {
        $_.FullName.Substring($left.Length).TrimStart('\', '/').Replace('\', '/')
    } | Sort-Object)
    $rightFiles = @(Get-ChildItem -LiteralPath $right -Recurse -File | ForEach-Object {
        $_.FullName.Substring($right.Length).TrimStart('\', '/').Replace('\', '/')
    } | Sort-Object)
    if (($leftFiles | ConvertTo-Json -Compress) -cne ($rightFiles | ConvertTo-Json -Compress)) {
        throw 'production build file sets differ'
    }
    if ($leftFiles.Count -ne 15) { throw "expected 15 production files, got $($leftFiles.Count)" }
    foreach ($relative in $leftFiles) {
        $leftPath = Join-Path $left $relative
        $rightPath = Join-Path $right $relative
        $leftItem = Get-Item -LiteralPath $leftPath
        $rightItem = Get-Item -LiteralPath $rightPath
        if ($leftItem.Length -ne $rightItem.Length) { throw "size mismatch: $relative" }
        $leftHash = (Get-FileHash -LiteralPath $leftPath -Algorithm SHA256).Hash
        $rightHash = (Get-FileHash -LiteralPath $rightPath -Algorithm SHA256).Hash
        if ($leftHash -cne $rightHash) { throw "byte/hash mismatch: $relative" }
    }
    $bundle = Join-Path $left 'xiaohe-yinxing-production.hsyx'
    $identity = Get-FileIdentity $bundle
    if ($identity.bytes -ne 25397952 -or
        $identity.sha256 -ne '00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30') {
        throw 'frozen production bundle identity mismatch'
    }
    Write-Host 'PRODUCTION_DOUBLE_BUILD_FILE_COUNT=15'
    Write-Host "PRODUCTION_DOUBLE_BUILD_SHA256=$($identity.sha256)"
}

function Assert-VersionContracts {
    $cpp = Get-Content -LiteralPath (Join-Path $repoRoot 'entry\src\main\cpp\bridge\rust_engine_bridge.h') -Raw -Encoding UTF8
    $rust = Get-Content -LiteralPath (Join-Path $repoRoot 'engine-rust\crates\engine-protocol\src\composition.rs') -Raw -Encoding UTF8
    $settings = Get-Content -LiteralPath (Join-Path $repoRoot 'entry\src\main\ets\domain\settings\ImeSettings.ets') -Raw -Encoding UTF8
    if ($cpp -notmatch 'CURRENT_INTERFACE_VERSION\s*=\s*4' -or
        $cpp -notmatch 'CURRENT_ABI_VERSION\s*=\s*4' -or
        $rust -notmatch 'INTERFACE_VERSION_STAGE1166:\s*u32\s*=\s*4' -or
        $rust -notmatch 'ABI_VERSION_STAGE1166:\s*u32\s*=\s*4' -or
        $settings -notmatch 'CURRENT_SETTINGS_SCHEMA_VERSION:\s*number\s*=\s*2') {
        throw 'interface/ABI/settings schema version contract mismatch'
    }
    if ($settings -notmatch "DEFAULT_SCHEME_ID:\s*string\s*=\s*'xiaohe'" -or
        $settings -notmatch "XIAOHE_YINXING_SCHEME_ID:\s*string\s*=\s*'xiaohe-yinxing'" -or
        $settings -notmatch 'schemeId:\s*DEFAULT_SCHEME_ID' -or
        $settings -notmatch "AVAILABLE_SHUANGPIN_SCHEMES:[\s\S]*\{\s*id:\s*DEFAULT_SCHEME_ID[\s\S]*\{\s*id:\s*XIAOHE_YINXING_SCHEME_ID") {
        throw 'formal scheme default contract mismatch'
    }
    Write-Host 'INTERFACE_VERSION=4'
    Write-Host 'ABI_VERSION=4'
    Write-Host 'SETTINGS_SCHEMA_VERSION=2'
    Write-Host 'DEFAULT_SCHEME=xiaohe'
}

function Assert-Environment {
    foreach ($command in @('cargo', 'rustc', 'node')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "required command is unavailable: $command"
        }
    }
    foreach ($path in @($hvigor, $hdc)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "required DevEco tool is unavailable: $([IO.Path]::GetFileName($path))"
        }
    }
    Write-Host 'ENVIRONMENT_RESULT=PASS'
}

function Assert-FormalSourceIdentity {
    $auditRoot = Join-Path $repoRoot 'dictionaries\audit\xiaohe-yinxing'
    $manifestPath = Join-Path $auditRoot 'source_manifest.json'
    $contractPath = Join-Path $auditRoot 'conversion_contract.json'
    $sanitizedPath = Join-Path $auditRoot 'sanitized_configuration.json'
    $frozen = [ordered]@{
        $manifestPath = 'ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55'
        $contractPath = '2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692'
        $sanitizedPath = 'b4b7705055953e0c65d579767875516fd11c8c973af810b3821045551e0d04f0'
    }
    foreach ($item in $frozen.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $item.Key -PathType Leaf)) { throw 'frozen audit file is missing' }
        $actual = (Get-FileHash -LiteralPath $item.Key -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $item.Value) { throw 'frozen audit file SHA-256 mismatch' }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $files = @($manifest.files)
    if ($files.Count -ne 28) { throw "expected 28 formal source files, got $($files.Count)" }
    $quarantinedRelativePath = 'ime.android.ini'
    $quarantinedPath = Join-Path $repoRoot ('小鹤音形\' + $quarantinedRelativePath)
    if (Test-Path -LiteralPath $quarantinedPath) {
        throw 'quarantined customer Android configuration must not exist in the workspace'
    }
    $verifiedSourceCount = 0
    foreach ($file in $files) {
        if ([string]$file.relative_path -eq $quarantinedRelativePath) {
            continue
        }
        $path = Join-Path (Join-Path $repoRoot ([string]$file.source_root)) ([string]$file.relative_path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "formal source file is missing: $($file.source_root)/$($file.relative_path)"
        }
        $item = Get-Item -LiteralPath $path
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($item.Length -ne [long]$file.byte_size -or $hash -ne [string]$file.sha256) {
            throw "formal source identity mismatch: $($file.source_root)/$($file.relative_path)"
        }
        $verifiedSourceCount += 1
    }
    if ($verifiedSourceCount -ne 27) { throw "expected 27 retained formal source files, got $verifiedSourceCount" }
    Write-Host 'SOURCE_IMMUTABILITY_CHECK=PASS'
    Write-Host 'SOURCE_FILE_COUNT=27'
    Write-Host 'QUARANTINED_SOURCE_REMOVED=小鹤音形/ime.android.ini'
}

function Invoke-SignatureReview([string]$SignedHap) {
    if ($SkipSignatureReview) {
        Add-NotRun 'signed-release-signature-review' 'Skipped by explicit -SkipSignatureReview.'
        return
    }
    if (-not (Test-Path -LiteralPath $java) -or -not (Test-Path -LiteralPath $signTool)) {
        throw 'signature verification tool is unavailable'
    }
    $signatureTemp = Join-Path $tempRoot 'signature'
    New-Item -ItemType Directory -Path $signatureTemp -Force | Out-Null
    $cert = Join-Path $signatureTemp 'certificate-chain.cer'
    $profile = Join-Path $signatureTemp 'profile.p7b'
    & $java -jar $signTool verify-app -inFile $SignedHap -outCertChain $cert -outProfile $profile
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cert) -or -not (Test-Path -LiteralPath $profile)) {
        throw 'signed Release HAP verification failed'
    }
    Write-Host "CERTIFICATE_CHAIN_SHA256=$((Get-FileHash -LiteralPath $cert -Algorithm SHA256).Hash.ToLowerInvariant())"
    Write-Host "PROFILE_SHA256=$((Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash.ToLowerInvariant())"
    Write-Host 'SIGNED_RELEASE_SIGNATURE_REVIEW=PASS'
}

function Invoke-DeviceSuite([string]$Kind, $Device) {
    if ($null -eq $Device) {
        Add-NotRun "$Kind-device-suite" 'No matching connected device was found.'
        return
    }
    $safeSerial = $Device.serial -replace '[^0-9A-Za-z_-]', '_'
    $suiteRoot = Join-Path $deviceRoot ("$($Kind.ToLowerInvariant())-$safeSerial")
    New-Item -ItemType Directory -Path $suiteRoot -Force | Out-Null
    $relativeSuite = Convert-ToRelativePath $suiteRoot
    $debugHap = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
    if (-not (Test-Path -LiteralPath $debugHap)) {
        Add-NotRun "$Kind-device-suite" 'Current-run Debug HAP is unavailable; run Build or Full first.'
        return
    }

    Invoke-Step "$Kind-stage10-editors" {
        & (Join-Path $PSScriptRoot 'device-accept-stage10.ps1') -Target $Device.serial -DevEcoRoot $DevEcoRoot -EvidenceDir ($relativeSuite + '/stage10')
        if ($LASTEXITCODE -ne 0) { throw 'Stage 10 device suite failed' }
    } 'STAGE10_DEVICE_ACCEPTANCE_RESULT=PASS' | Out-Null

    Invoke-Step "$Kind-stage11-settings" {
        & (Join-Path $PSScriptRoot 'device-accept-stage11.ps1') -Target $Device.serial -DevEcoRoot $DevEcoRoot -EvidenceDir ($relativeSuite + '/stage11')
        if ($LASTEXITCODE -ne 0) { throw 'Stage 11 device suite failed' }
    } 'STAGE11_DEVICE_ACCEPTANCE_RESULT=PASS' | Out-Null

    $editorDump = @(& $hdc -t $Device.serial shell bm dump -n com.example.nexttest 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($editorDump -join "`n") -match '(?i)failed to get information') {
        Add-NotRun "$Kind-signed-release-independent-textinput" 'The independent ArkUI TextInput package com.example.nexttest is not installed on this device.'
    } else {
        Invoke-Step "$Kind-signed-release-independent-textinput" {
            & (Join-Path $PSScriptRoot 'device-accept-xiaohe-yinxing-stage11_6_8.ps1') `
                -Target $Device.serial `
                -DevEcoRoot $DevEcoRoot `
                -EvidenceDir ($relativeSuite + '/signed-release')
            if ($LASTEXITCODE -ne 0) { throw 'signed Release independent TextInput suite failed' }
        } 'STAGE11_6_8_POSITIVE_DEVICE_RESULT=PASS' | Out-Null
    }
}

$git = Get-GitSnapshot
$devices.Clear()
foreach ($device in @(Get-ConnectedDevices)) { $devices.Add($device) | Out-Null }

$metadata = [ordered]@{
    runId = $runId
    scope = $Scope
    startedAt = $startedAt.ToString('o')
    repository = $git
    tools = [ordered]@{
        powershell = $PSVersionTable.PSVersion.ToString()
        rustc = Get-ToolVersion 'rustc'
        cargo = Get-ToolVersion 'cargo'
        node = Get-ToolVersion 'node'
        hvigor = if (Test-Path -LiteralPath $hvigor) { 'available' } else { 'unavailable' }
        hdc = if (Test-Path -LiteralPath $hdc) { 'available' } else { 'unavailable' }
    }
    devices = @($devices)
}
$metadata | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $runRoot 'run-metadata.json') -Encoding utf8

$runHost = $Scope -in @('Host', 'Full')
$runBuild = $Scope -in @('Build', 'Full')
$runPerformance = $Scope -in @('Performance', 'Full')
$runPhone = $Scope -in @('Phone', 'Full')
$runPad = $Scope -in @('Pad', 'Full')
$runArm64 = $Scope -in @('Arm64', 'Full')

try {
    if ($runHost) {
        Invoke-Step 'environment' { Assert-Environment } 'ENVIRONMENT_RESULT=PASS' | Out-Null
        Invoke-Step 'version-contracts' { Assert-VersionContracts } 'DEFAULT_SCHEME=xiaohe' | Out-Null
        Invoke-Step 'formal-source-immutability' { Assert-FormalSourceIdentity } 'QUARANTINED_SOURCE_REMOVED=小鹤音形/ime.android.ini' | Out-Null
        Invoke-Step 'production-double-build' { Compare-ProductionBuilds } 'PRODUCTION_DOUBLE_BUILD_FILE_COUNT=15' | Out-Null
        Invoke-Step 'cargo-fmt' {
            Push-Location (Join-Path $repoRoot 'engine-rust')
            try { & cargo fmt --all --check; if ($LASTEXITCODE -ne 0) { throw 'cargo fmt failed' } } finally { Pop-Location }
        } | Out-Null
        Invoke-Step 'cargo-clippy' {
            Push-Location (Join-Path $repoRoot 'engine-rust')
            try { & cargo clippy --workspace --all-targets --all-features -- -D warnings; if ($LASTEXITCODE -ne 0) { throw 'cargo clippy failed' } } finally { Pop-Location }
        } | Out-Null
        Invoke-Step 'cargo-workspace-tests' {
            Push-Location (Join-Path $repoRoot 'engine-rust')
            try { & cargo test --workspace; if ($LASTEXITCODE -ne 0) { throw 'cargo workspace tests failed' } } finally { Pop-Location }
        } 'test result: ok' | Out-Null
        Invoke-Step 'ffi-tests' {
            Push-Location (Join-Path $repoRoot 'engine-rust')
            try { & cargo test -p ime-ffi; if ($LASTEXITCODE -ne 0) { throw 'FFI tests failed' } } finally { Pop-Location }
        } 'test result: ok' | Out-Null
        Invoke-Step 'arkts-tests' {
            $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
            & $hvigor --no-daemon --mode module -p module=entry@default test
            if ($LASTEXITCODE -ne 0) { throw 'ArkTS tests failed' }
        } 'BUILD SUCCESSFUL' | Out-Null
    }

    if ($runBuild) {
        Invoke-Step 'native-x86_64' {
            & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi x86_64
            if ($LASTEXITCODE -ne 0) { throw 'x86_64 native build failed' }
        } | Out-Null
        Invoke-Step 'native-arm64-v8a' {
            & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi arm64-v8a
            if ($LASTEXITCODE -ne 0) { throw 'arm64-v8a native build failed' }
        } | Out-Null
        Invoke-Step 'internalDebug-hap' {
            & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust -BuildMode debug -DevEcoRoot $DevEcoRoot
            if ($LASTEXITCODE -ne 0) { throw 'internalDebug HAP build failed' }
        } 'BUILD_MODE=debug' | Out-Null
        Invoke-Step 'release-hap' {
            & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust -BuildMode release -DevEcoRoot $DevEcoRoot
            if ($LASTEXITCODE -ne 0) { throw 'Release HAP build failed' }
        } 'BUILD_MODE=release' | Out-Null

        $debugHap = Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap'
        $unsignedHap = Join-Path $repoRoot 'entry\build\artifacts\entry-release-unsigned.hap'
        $signedHap = Join-Path $repoRoot 'entry\build\release\outputs\default\entry-default-signed.hap'
        Assert-CurrentArtifact $debugHap 'internalDebug HAP'
        Assert-CurrentArtifact $unsignedHap 'unsigned Release HAP'
        Assert-CurrentArtifact $signedHap 'signed Release HAP'
        $artifacts.internalDebugHap = Get-FileIdentity $debugHap
        $artifacts.unsignedReleaseHap = Get-FileIdentity $unsignedHap
        $artifacts.signedReleaseHap = Get-FileIdentity $signedHap
        $artifacts.productionBundle = Get-FileIdentity (Join-Path $repoRoot 'entry\src\main\resources\rawfile\xiaohe-yinxing-production.hsyx')

        Invoke-Step 'release-gate-unsigned' {
            & (Join-Path $PSScriptRoot 'verify-release-hap.ps1') -HapPath $unsignedHap
            if ($LASTEXITCODE -ne 0) { throw 'unsigned Release gate failed' }
        } 'RELEASE_HAP_VERIFY_RESULT=PASS' | Out-Null
        Invoke-Step 'release-gate-signed' {
            & (Join-Path $PSScriptRoot 'verify-release-hap.ps1') -HapPath $signedHap
            if ($LASTEXITCODE -ne 0) { throw 'signed Release gate failed' }
        } 'RELEASE_HAP_VERIFY_RESULT=PASS' | Out-Null
        Invoke-Step 'release-negative-resource-gate' {
            & (Join-Path $PSScriptRoot 'test-release-resource-gate.ps1')
            if ($LASTEXITCODE -ne 0) { throw 'general Release negative gate failed' }
        } | Out-Null
        Invoke-Step 'release-negative-yinxing-gate' {
            & (Join-Path $PSScriptRoot 'test-xiaohe-yinxing-stage11_6_8-release-gate.ps1')
            if ($LASTEXITCODE -ne 0) { throw 'Yinxing Release negative gate failed' }
        } | Out-Null
        if ($SkipSignatureReview) {
            Add-NotRun 'signed-release-signature-review' 'Skipped by explicit -SkipSignatureReview.'
        } else {
            Invoke-Step 'signed-release-signature-review' { Invoke-SignatureReview $signedHap } 'SIGNED_RELEASE_SIGNATURE_REVIEW=PASS' | Out-Null
        }
    }

    if ($runPerformance) {
        Invoke-Step 'host-production-performance' {
            & (Join-Path $PSScriptRoot 'verify-xiaohe-yinxing-stage11_6_3-performance.ps1') `
                -ProcessSamples 5 `
                -EvidenceDir (Join-Path $runRoot 'performance')
            if ($LASTEXITCODE -ne 0) { throw 'host production performance failed' }
        } 'STAGE11_6_3_PERFORMANCE_RESULT=PASS' | Out-Null
        Add-NotRun 'device-performance' 'No stage 11.6.9 device latency/memory collector is available yet; host measurements do not substitute for device metrics.'
    }

    if ($runPhone) {
        $explicit = if (-not [string]::IsNullOrWhiteSpace($PhoneSerial)) { $PhoneSerial } elseif ($Scope -eq 'Phone') { $DeviceSerial } else { '' }
        Invoke-DeviceSuite 'Phone' (Select-Device 'Phone' $explicit)
    }
    if ($runPad) {
        $explicit = if (-not [string]::IsNullOrWhiteSpace($PadSerial)) { $PadSerial } elseif ($Scope -eq 'Pad') { $DeviceSerial } else { '' }
        Invoke-DeviceSuite 'Pad' (Select-Device 'Pad' $explicit)
    }
    if ($runArm64) {
        $explicit = if (-not [string]::IsNullOrWhiteSpace($Arm64Serial)) { $Arm64Serial } elseif ($Scope -eq 'Arm64') { $DeviceSerial } else { '' }
        Invoke-DeviceSuite 'Arm64' (Select-Device 'Arm64' $explicit)
    }
} finally {
    $artifacts | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $runRoot 'artifacts.json') -Encoding utf8
    $resultObject = [ordered]@{
        runId = $runId
        scope = $Scope
        startedAt = $startedAt.ToString('o')
        completedAt = (Get-Date).ToString('o')
        results = @($results)
    }
    $resultObject | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $runRoot 'results.json') -Encoding utf8
    $summaryLines = @(
        '# Stage 11.6.9 run summary'
        ''
        "- Run ID: $runId"
        "- Scope: $Scope"
        "- Started: $($startedAt.ToString('o'))"
        "- Git metadata available: $($git.available)"
        ''
        '| Check | Status | Detail |'
        '| --- | --- | --- |'
    )
    foreach ($result in $results) {
        $detail = ([string]$result.detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        $summaryLines += "| $($result.name) | $($result.status) | $detail |"
    }
    $summaryLines | Out-File -LiteralPath (Join-Path $runRoot 'acceptance-summary.md') -Encoding utf8
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolvedTemp)).StartsWith('harmony-stage11-6-9-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove unverified temporary path: $resolvedTemp"
        }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

$failed = @($results | Where-Object { $_.status -eq 'FAIL' })
$notRun = @($results | Where-Object { $_.status -eq 'NOT_RUN' })
Write-Host "STAGE11_6_9_RUN_ID=$runId"
Write-Host "STAGE11_6_9_EVIDENCE=$(Convert-ToRelativePath $runRoot)"
Write-Host "STAGE11_6_9_PASS_COUNT=$(@($results | Where-Object { $_.status -eq 'PASS' }).Count)"
Write-Host "STAGE11_6_9_FAIL_COUNT=$($failed.Count)"
Write-Host "STAGE11_6_9_NOT_RUN_COUNT=$($notRun.Count)"
if ($failed.Count -gt 0) {
    Write-Host 'STAGE11_6_9_RESULT=FAILED'
    exit 1
}
if ($notRun.Count -gt 0) {
    Write-Host 'STAGE11_6_9_RESULT=PARTIALLY_COMPLETED'
    exit 2
}
Write-Host 'STAGE11_6_9_RESULT=COMPLETED'
