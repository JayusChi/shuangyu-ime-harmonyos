$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$java = 'C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe'
$signTool = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$shell = (Get-Process -Id $PID).Path
$sourceApp = Join-Path $repoRoot 'build/outputs/default/HarmonyOS_Input-default-signed.app'
$deliveryApp = Join-Path $repoRoot 'artifacts/0.9.0/ShuangYuIME-0.9.0-9000000-release-signed.app'

& $java -jar $signTool verify-app -inFile $sourceApp -outCertChain (Join-Path $PSScriptRoot 'app-certificate-chain.cer') -outProfile (Join-Path $PSScriptRoot 'app-profile.p7b') *> (Join-Path $PSScriptRoot 'verify-app-signature.log')
if ($LASTEXITCODE -ne 0) { throw 'APP signature verification failed' }
& $java -jar $signTool verify-profile -inFile (Join-Path $PSScriptRoot 'app-profile.p7b') -outFile (Join-Path $PSScriptRoot 'profile-verification.json') *> (Join-Path $PSScriptRoot 'verify-profile.log')
if ($LASTEXITCODE -ne 0) { throw 'Profile signature verification failed' }
$profile = Get-Content (Join-Path $PSScriptRoot 'profile-verification.json') -Raw | ConvertFrom-Json
if (-not $profile.verifiedPassed -or $profile.content.type -ne 'release' -or $profile.content.'app-distribution-type' -ne 'app_gallery') { throw 'A verified app_gallery Release profile is required' }
if ($profile.content.'bundle-info'.'bundle-name' -ne 'com.corrosion.shuangyuime' -or $profile.content.'bundle-info'.'app-identifier' -ne '6917611076350696172') { throw 'Release application identity mismatch' }
if ($profile.content.'debug-info') { throw 'Release profile must not contain debug device restrictions' }
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ($now -lt $profile.content.validity.'not-before' -or $now -ge $profile.content.validity.'not-after') { throw 'Release profile is outside its validity period' }
$previousProfile = Get-Content (Join-Path $repoRoot 'outputs/release-0.8.0-signature/profile-verification.json') -Raw | ConvertFrom-Json
if ($profile.content.'bundle-info'.'distribution-certificate' -cne $previousProfile.content.'bundle-info'.'distribution-certificate') { throw 'Release certificate differs from the previous customer release' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$embeddedHap = Join-Path $PSScriptRoot 'entry-default.hap'
$zip = [IO.Compression.ZipFile]::OpenRead($sourceApp)
try {
    $reader = [IO.StreamReader]::new($zip.GetEntry('pack.info').Open())
    try { $pack = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($pack.summary.app.bundleName -ne 'com.corrosion.shuangyuime' -or $pack.summary.app.version.name -ne '0.9.0' -or $pack.summary.app.version.code -ne 9000000) { throw 'APP version or bundle mismatch' }
    $haps = @($zip.Entries | Where-Object { $_.FullName -like '*.hap' })
    if ($haps.Count -ne 1 -or $haps[0].FullName -ne 'entry-default.hap') { throw 'Unexpected APP module set' }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($haps[0], $embeddedHap, $true)
} finally { $zip.Dispose() }

foreach ($check in @(
    @{ Path = (Join-Path $repoRoot 'entry/build/default/outputs/default/entry-default-signed.hap'); Log = 'verify-signed-hap.log' },
    @{ Path = $embeddedHap; Log = 'verify-embedded-hap.log' }
)) {
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts/verify-release-hap.ps1') -HapPath $check.Path *> (Join-Path $PSScriptRoot $check.Log)
    if ($LASTEXITCODE -ne 0) { throw "Release content gate failed: $($check.Log)" }
}
$zip = [IO.Compression.ZipFile]::OpenRead($embeddedHap)
try {
    $reader = [IO.StreamReader]::new($zip.GetEntry('module.json').Open())
    try { $module = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($module.app.versionName -ne '0.9.0' -or $module.app.versionCode -ne 9000000 -or $module.app.debug -or $module.app.buildMode -ne 'release') { throw 'Embedded HAP version or build mode mismatch' }
    foreach ($abi in @('arm64-v8a', 'x86_64')) {
        if ($null -eq $zip.GetEntry("libs/$abi/libime_bridge.so")) { throw "Missing native ABI: $abi" }
    }
    if (($module.module.deviceTypes -join ',') -ne 'phone,tablet,2in1') { throw 'Unexpected supported device set' }
} finally { $zip.Dispose() }

Copy-Item -LiteralPath $sourceApp -Destination $deliveryApp -Force
$app = Get-Item -LiteralPath $deliveryApp
$hash = (Get-FileHash -LiteralPath $deliveryApp -Algorithm SHA256).Hash
$manifest = [ordered]@{
    file = $app.Name
    bytes = $app.Length
    sha256 = $hash
    bundleName = $module.app.bundleName
    versionName = $module.app.versionName
    versionCode = $module.app.versionCode
    buildVersion = $pack.summary.app.version.build
    buildMode = $module.app.buildMode
    debug = $module.app.debug
    minAPIVersion = $module.app.minAPIVersion
    devices = $module.module.deviceTypes
    abis = @('arm64-v8a', 'x86_64')
    profileType = $profile.content.type
    distribution = $profile.content.'app-distribution-type'
    appId = $profile.content.'bundle-info'.'app-identifier'
    sameReleaseCertificateAs080 = $true
    profileExpiry = [DateTimeOffset]::FromUnixTimeSeconds($profile.content.validity.'not-after').ToString('o')
    appSignature = 'PASS'
    profileSignature = 'PASS'
    signedHapGate = 'PASS'
    embeddedHapGate = 'PASS'
    verifiedAt = [DateTimeOffset]::Now.ToString('o')
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PSScriptRoot 'delivery-verification.json') -Encoding utf8
"$hash  $($app.Name)" | Set-Content (Join-Path $repoRoot 'artifacts/0.9.0/SHA256SUMS.txt') -Encoding utf8
$manifest | ConvertTo-Json -Depth 5
