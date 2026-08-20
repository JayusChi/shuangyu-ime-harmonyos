param(
    [ValidateSet('all', 'arm64-v8a', 'x86_64')]
    [string]$Abi = 'all'
)

$ErrorActionPreference = 'Stop'

$abis = if ($Abi -eq 'all') { @('x86_64', 'arm64-v8a') } else { @($Abi) }

foreach ($item in $abis) {
    & (Join-Path $PSScriptRoot 'build-rust.ps1') -Abi $item
    & (Join-Path $PSScriptRoot 'copy-native-artifacts.ps1') -Abi $item
}
