param([Parameter(Mandatory=$true)][string]$SignedHap)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$baseline=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'accepted-0110-payload-hashes.json') -Raw | ConvertFrom-Json
$zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $SignedHap).Path)
$hashes=@{}
try {
 foreach($entry in $zip.Entries) {
  if($entry.FullName.EndsWith('/')){continue}
  $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
  try {$hashes[$entry.FullName]=[Convert]::ToHexString($sha.ComputeHash($stream))} finally {$stream.Dispose();$sha.Dispose()}
 }
} finally {$zip.Dispose()}
$baselineNames=@($baseline.files.PSObject.Properties.Name)
$added=@($hashes.Keys | Where-Object {$_ -notin $baselineNames})
$removed=@($baselineNames | Where-Object {-not $hashes.ContainsKey($_)})
$changed=@($baselineNames | Where-Object {$hashes.ContainsKey($_) -and $hashes[$_] -cne $baseline.files.$_})
$unexpected=@($changed | Where-Object {$_ -notin @('module.json','pack.info','resources.index')})
$result=[ordered]@{
 acceptedHapSha256=$baseline.hapSha256
 releaseHapSha256=(Get-FileHash -LiteralPath $SignedHap -Algorithm SHA256).Hash
 comparedFiles=$hashes.Count
 changedFiles=$changed
 addedFiles=$added
 removedFiles=$removed
 unexpectedChanges=$unexpected
 arktsBytecodeIdentical=$hashes['ets/modules.abc'] -ceq $baseline.files.'ets/modules.abc'
 arm64NativeIdentical=$hashes['libs/arm64-v8a/libime_bridge.so'] -ceq $baseline.files.'libs/arm64-v8a/libime_bridge.so'
 x64NativeIdentical=$hashes['libs/x86_64/libime_bridge.so'] -ceq $baseline.files.'libs/x86_64/libime_bridge.so'
 passed=($added.Count -eq 0 -and $removed.Count -eq 0 -and $unexpected.Count -eq 0)
 verifiedAt=[DateTimeOffset]::Now.ToString('o')
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'accepted-payload-verification.json') -Encoding utf8
$result | ConvertTo-Json -Depth 4
if(-not $result.passed){throw 'Unexpected payload changes since emulator acceptance'}
