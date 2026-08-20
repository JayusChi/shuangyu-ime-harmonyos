param(
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$HarmonySdkRoot = $(if ($env:HARMONYOS_SDK_ROOT) { $env:HARMONYOS_SDK_ROOT } else { Join-Path $DevEcoRoot 'sdk\default\openharmony' })
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ohos-abi.ps1')

Add-CargoBinToPathIfNeeded

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "USERPROFILE: $env:USERPROFILE"
    Write-Host 'PATH:'
    $env:Path -split ';' | ForEach-Object { Write-Host "  $_" }
    throw 'cargo not detected. Install Rust toolchain and add it to PATH.'
}

$abiConfig = Get-OhosAbiConfig -Abi $Abi
$nativeRoot = Get-OhosNativeRoot -DevEcoRoot $DevEcoRoot -HarmonySdkRoot $HarmonySdkRoot
$tools = Assert-OhosNativeToolchain -NativeRoot $nativeRoot
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$linkerScript = Join-Path $repoRoot ".cargo\..\scripts\toolchains\$($abiConfig.RustTarget)-linker.cmd"
$linkerScript = (Resolve-Path $linkerScript).Path

Set-Item -Path "Env:CARGO_TARGET_$($abiConfig.CargoEnvTarget)_LINKER" -Value $linkerScript
Set-Item -Path "Env:AR_$($abiConfig.RustTarget.Replace('-', '_'))" -Value $tools.LlvmAr
Set-Item -Path "Env:RANLIB_$($abiConfig.RustTarget.Replace('-', '_'))" -Value $tools.LlvmRanlib
$env:AR = $tools.LlvmAr
$env:RANLIB = $tools.LlvmRanlib
$env:HARMONYOS_NATIVE_ROOT = $nativeRoot

Write-Host "ABI: $($abiConfig.Abi)"
Write-Host "Rust target: $($abiConfig.RustTarget)"
Write-Host "Clang target: $($abiConfig.ClangTarget)"
Write-Host "Native root: $nativeRoot"
Write-Host "Linker wrapper: $linkerScript"
Write-Host "clang: $($tools.Clang)"
Write-Host "llvm-ar: $($tools.LlvmAr)"
Write-Host "llvm-ranlib: $($tools.LlvmRanlib)"

Push-Location (Join-Path $PSScriptRoot '..\engine-rust')
try {
    cargo build -p ime-ffi --release --target $abiConfig.RustTarget
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
