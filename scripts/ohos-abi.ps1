$ErrorActionPreference = 'Stop'

function Get-OhosAbiConfig {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('arm64-v8a', 'x86_64')]
        [string]$Abi
    )

    switch ($Abi) {
        'arm64-v8a' {
            [pscustomobject]@{
                Abi = 'arm64-v8a'
                RustTarget = 'aarch64-unknown-linux-ohos'
                ClangTarget = 'aarch64-linux-ohos'
                CargoEnvTarget = 'AARCH64_UNKNOWN_LINUX_OHOS'
            }
            return
        }
        'x86_64' {
            [pscustomobject]@{
                Abi = 'x86_64'
                RustTarget = 'x86_64-unknown-linux-ohos'
                ClangTarget = 'x86_64-linux-ohos'
                CargoEnvTarget = 'X86_64_UNKNOWN_LINUX_OHOS'
            }
            return
        }
    }

    throw "Unsupported ABI: $Abi"
}

function Get-OhosNativeRoot {
    param(
        [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
        [string]$HarmonySdkRoot = $(if ($env:HARMONYOS_SDK_ROOT) { $env:HARMONYOS_SDK_ROOT } else { Join-Path $DevEcoRoot 'sdk\default\openharmony' })
    )

    if ($env:HARMONYOS_NATIVE_ROOT) {
        return $env:HARMONYOS_NATIVE_ROOT
    }

    return Join-Path $HarmonySdkRoot 'native'
}

function Add-CargoBinToPathIfNeeded {
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    $cargoExe = Join-Path $cargoBin 'cargo.exe'
    $pathEntries = $env:Path -split ';'
    $cargoBinInPath = $pathEntries | Where-Object { $_.TrimEnd('\') -ieq $cargoBin.TrimEnd('\') }

    if ($cargoBinInPath) {
        return
    }

    if (Test-Path $cargoExe) {
        $env:Path = "$cargoBin;$env:Path"
        Write-Host "Temporarily prepended Cargo bin to this PowerShell process: $cargoBin"
        Write-Host 'Permanent user PATH was not modified.'
        return
    }

    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        return
    }
}

function Assert-OhosNativeToolchain {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NativeRoot
    )

    $tools = @{
        Clang = Join-Path $NativeRoot 'llvm\bin\clang.exe'
        Clangxx = Join-Path $NativeRoot 'llvm\bin\clang++.exe'
        LlvmAr = Join-Path $NativeRoot 'llvm\bin\llvm-ar.exe'
        LlvmRanlib = Join-Path $NativeRoot 'llvm\bin\llvm-ranlib.exe'
        Sysroot = Join-Path $NativeRoot 'sysroot'
    }

    foreach ($item in $tools.GetEnumerator()) {
        if (-not (Test-Path $item.Value)) {
            throw "HarmonyOS native tool missing: $($item.Key) -> $($item.Value)"
        }
    }

    [pscustomobject]$tools
}
