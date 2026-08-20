param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$LinkerArgs
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\ohos-abi.ps1')

$abiConfig = Get-OhosAbiConfig -Abi $Abi
$nativeRoot = Get-OhosNativeRoot
$tools = Assert-OhosNativeToolchain -NativeRoot $nativeRoot
$sysroot = Join-Path $nativeRoot 'sysroot'

& $tools.Clang "--target=$($abiConfig.ClangTarget)" "--sysroot=$sysroot" '-D__MUSL__' @LinkerArgs
exit $LASTEXITCODE
