param([Parameter(Mandatory=$true)][string]$SourceApp,[Parameter(Mandatory=$true)][string]$SignedHap)
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$SourceApp=(Resolve-Path -LiteralPath $SourceApp).Path
$SignedHap=(Resolve-Path -LiteralPath $SignedHap).Path
$java='C:/Program Files/Huawei/DevEco Studio/jbr/bin/java.exe'
$signTool='C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar'
$shell=(Get-Process -Id $PID).Path
$deliveryDir=Join-Path $repoRoot 'artifacts/0.11.0'
New-Item -ItemType Directory -Path $deliveryDir -Force | Out-Null

& $java -jar $signTool verify-app -inFile $SourceApp -outCertChain (Join-Path $PSScriptRoot 'app-certificate-chain.cer') -outProfile (Join-Path $PSScriptRoot 'app-profile.p7b') *> (Join-Path $PSScriptRoot 'verify-app-signature.log')
if($LASTEXITCODE -ne 0){throw 'APP signature verification failed'}
& $java -jar $signTool verify-profile -inFile (Join-Path $PSScriptRoot 'app-profile.p7b') -outFile (Join-Path $PSScriptRoot 'profile-verification.json') *> (Join-Path $PSScriptRoot 'verify-profile.log')
if($LASTEXITCODE -ne 0){throw 'Profile signature verification failed'}
$profile=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'profile-verification.json') -Raw | ConvertFrom-Json
if(-not $profile.verifiedPassed -or $profile.content.type -ne 'release' -or $profile.content.'app-distribution-type' -ne 'app_gallery'){throw 'Verified app_gallery release profile required'}
if($profile.content.'bundle-info'.'bundle-name' -ne 'com.corrosion.shuangyuime'){throw 'Profile bundle mismatch'}
if($profile.content.'debug-info'){throw 'Release profile contains debug device restrictions'}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if($now -lt $profile.content.validity.'not-before' -or $now -ge $profile.content.validity.'not-after'){throw 'Profile validity failure'}
$previous=Get-Content -LiteralPath (Join-Path $repoRoot 'outputs/release-0.10.0/profile-verification.json') -Raw | ConvertFrom-Json
foreach($field in @('app-identifier','distribution-certificate')) {
 if($profile.content.'bundle-info'.$field -cne $previous.content.'bundle-info'.$field){throw "Customer upgrade identity mismatch: $field"}
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-ZipJson($zip,[string]$name) {
 $reader=[IO.StreamReader]::new($zip.GetEntry($name).Open())
 try {return ($reader.ReadToEnd() | ConvertFrom-Json)} finally {$reader.Dispose()}
}
$embeddedHap=Join-Path $PSScriptRoot 'entry-default.hap'
$zip=[IO.Compression.ZipFile]::OpenRead($SourceApp)
try {
 $pack=Read-ZipJson $zip 'pack.info'
 if($pack.summary.app.bundleName -ne 'com.corrosion.shuangyuime' -or $pack.summary.app.version.name -ne '0.11.0' -or $pack.summary.app.version.code -ne 11000000){throw 'APP version mismatch'}
 $haps=@($zip.Entries | Where-Object FullName -like '*.hap')
 if($haps.Count -ne 1 -or $haps[0].FullName -ne 'entry-default.hap'){throw 'Unexpected APP module set'}
 [IO.Compression.ZipFileExtensions]::ExtractToFile($haps[0],$embeddedHap,$true)
} finally {$zip.Dispose()}
foreach($check in @(@{Path=$SignedHap;Log='verify-signed-hap.log'},@{Path=$embeddedHap;Log='verify-embedded-hap.log'})) {
 & $shell -NoProfile -File (Join-Path $repoRoot 'scripts/verify-release-hap.ps1') -HapPath $check.Path *> (Join-Path $PSScriptRoot $check.Log)
 if($LASTEXITCODE -ne 0){throw "HAP content verification failed: $($check.Log)"}
}
$zip=[IO.Compression.ZipFile]::OpenRead($embeddedHap)
try {
 $module=Read-ZipJson $zip 'module.json'
 if($module.app.versionName -ne '0.11.0' -or $module.app.versionCode -ne 11000000 -or $module.app.debug -or $module.app.buildMode -ne 'release'){throw 'Embedded HAP metadata mismatch'}
 if([string]$module.app.buildVersion -ne '1' -or $module.app.minAPIVersion -ne 60101024){throw 'Build number or minimum API mismatch'}
 foreach($abi in @('arm64-v8a','x86_64')) {if(-not $zip.GetEntry("libs/$abi/libime_bridge.so")){throw "Missing ABI $abi"}}
 if(($module.module.deviceTypes -join ',') -ne 'phone,tablet,2in1'){throw 'Unexpected supported devices'}
} finally {$zip.Dispose()}

# Compare all module files; standalone signing additionally generates .pages.info.
function Zip-Hashes([string]$path) {
 $hashes=@{};$zip=[IO.Compression.ZipFile]::OpenRead($path)
 try {foreach($entry in $zip.Entries) {
  if($entry.FullName.EndsWith('/')){continue}
  if($entry.FullName -eq 'pack.info') {
   $hashes[$entry.FullName]=Read-ZipJson $zip 'pack.info' | ConvertTo-Json -Depth 30 -Compress
   continue
  }
  $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
  try {$hashes[$entry.FullName]=[Convert]::ToHexString($sha.ComputeHash($stream))} finally {$stream.Dispose();$sha.Dispose()}
 }} finally {$zip.Dispose()}
 return $hashes
}
$signedHashes=Zip-Hashes $SignedHap
$embeddedHashes=Zip-Hashes $embeddedHap
$standaloneSigningMetadata=@()
if($signedHashes.ContainsKey('.pages.info') -and -not $embeddedHashes.ContainsKey('.pages.info')) {
 $standaloneSigningMetadata=@('.pages.info')
 $signedHashes.Remove('.pages.info')
}
if($signedHashes.Count -ne $embeddedHashes.Count){throw 'Signed/embedded HAP file count mismatch'}
foreach($name in $signedHashes.Keys) {if($embeddedHashes[$name] -cne $signedHashes[$name]){throw "Signed/embedded module differs: $name"}}

$appName='ShuangYuIME-0.11.0-11000000-release-signed.app'
$hapName='ShuangYuIME-0.11.0-11000000-release-signed.hap'
Copy-Item -LiteralPath $SourceApp -Destination (Join-Path $deliveryDir $appName) -Force
Copy-Item -LiteralPath $SignedHap -Destination (Join-Path $deliveryDir $hapName) -Force
$app=Get-Item -LiteralPath (Join-Path $deliveryDir $appName)
$hash=(Get-FileHash -LiteralPath $app.FullName -Algorithm SHA256).Hash
$manifest=[ordered]@{
 file=$appName;bytes=$app.Length;sha256=$hash;bundleName=$module.app.bundleName
 versionName=$module.app.versionName;versionCode=$module.app.versionCode;buildVersion=$pack.summary.app.version.build
 buildMode=$module.app.buildMode;debug=$module.app.debug;minAPIVersion=$module.app.minAPIVersion
 devices=$module.module.deviceTypes;abis=@('arm64-v8a','x86_64');profileType=$profile.content.type
 permissions=@($module.module.requestPermissions | ForEach-Object name)
 webPermissionProfile='flypy-web-v1'
 distribution=$profile.content.'app-distribution-type';sameReleaseCertificateAndAppIdAs0100=$true
 profileExpiry=[DateTimeOffset]::FromUnixTimeSeconds($profile.content.validity.'not-after').ToString('o')
 appSignature='PASS';profileSignature='PASS';signedHapGate='PASS';embeddedHapGate='PASS'
 signedAndEmbeddedPayloadIdentical=$true;payloadFileCount=$signedHashes.Count
 standaloneSigningMetadata=$standaloneSigningMetadata
 packInfoComparison='Parsed JSON equality; APP packing reformats whitespace'
 knownLimitation='Imported custom keyboard structure/skin packages disabled: shared sandbox profile authorization pending; accepted for customer test.'
 verifiedAt=[DateTimeOffset]::Now.ToString('o')
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'delivery-verification.json') -Encoding utf8
@(foreach($file in @($appName,$hapName)) {"$((Get-FileHash -LiteralPath (Join-Path $deliveryDir $file) -Algorithm SHA256).Hash)  $file"}) | Set-Content -LiteralPath (Join-Path $deliveryDir 'SHA256SUMS.txt') -Encoding utf8
$manifest | ConvertTo-Json -Depth 5
