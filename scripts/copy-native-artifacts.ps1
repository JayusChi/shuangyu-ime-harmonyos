param(
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ohos-abi.ps1')

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$abiConfig = Get-OhosAbiConfig -Abi $Abi
$rustTarget = $abiConfig.RustTarget
$source = Join-Path $repoRoot "engine-rust\target\$rustTarget\release\libime_ffi.a"
$destinationDir = Join-Path $repoRoot "engine-rust\target\ohos\$Abi"
$destination = Join-Path $destinationDir 'libime_ffi.a'

if (-not (Test-Path $source)) {
    throw "Rust artifact not found: $source"
}

$sourceItem = Get-Item -LiteralPath $source
if ($sourceItem.Length -le 0) {
    throw "Rust artifact is empty: $source"
}

New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force

if (-not (Test-Path $destination)) {
    throw "Copied Rust artifact not found: $destination"
}

$destinationItem = Get-Item -LiteralPath $destination
if ($destinationItem.Length -le 0) {
    throw "Copied Rust artifact is empty: $destination"
}

Write-Host "Rust target: $rustTarget"
Write-Host "Source: $($sourceItem.FullName)"
Write-Host "Destination: $($destinationItem.FullName)"
Write-Host "Size: $($destinationItem.Length) bytes"
Write-Host "SHA-256: $((Get-FileHash -LiteralPath $destinationItem.FullName -Algorithm SHA256).Hash)"
