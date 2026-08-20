param(
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$HarmonySdkRoot = $(if ($env:HARMONYOS_SDK_ROOT) { $env:HARMONYOS_SDK_ROOT } else { Join-Path $DevEcoRoot 'sdk\default\openharmony' })
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'ohos-abi.ps1')
Add-CargoBinToPathIfNeeded

function Show-ToolVersion {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$Arguments = @('--version')
    )

    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Host "${Name}: not detected"
        return
    }

    Write-Host "${Name} path: $($resolved.Source)"
    & $resolved.Source @Arguments
}

$cmakePath = Join-Path $HarmonySdkRoot 'native\build-tools\cmake\bin\cmake.exe'
$clangPath = Join-Path $HarmonySdkRoot 'native\llvm\bin\clang.exe'
$ohpmPath = Join-Path $DevEcoRoot 'tools\ohpm\bin\ohpm.bat'
$hvigorPath = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'

Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "DevEco root: $DevEcoRoot"
Write-Host "Harmony SDK root: $HarmonySdkRoot"
Write-Host "NDK/native path: $(Join-Path $HarmonySdkRoot 'native')"
Write-Host "CMake: $(if (Test-Path $cmakePath) { $cmakePath } else { 'not detected' })"
if (Test-Path $cmakePath) { & $cmakePath --version }
Write-Host "clang: $(if (Test-Path $clangPath) { $clangPath } else { 'not detected' })"
if (Test-Path $ohpmPath) { Write-Host "ohpm: $ohpmPath"; & $ohpmPath --version } else { Write-Host 'ohpm: not detected' }
if (Test-Path $hvigorPath) { Write-Host "hvigorw: $hvigorPath"; & $hvigorPath --version } else { Write-Host 'hvigorw: not detected' }
Show-ToolVersion -Name 'node' -Command 'node'
Show-ToolVersion -Name 'rustc' -Command 'rustc'
Show-ToolVersion -Name 'cargo' -Command 'cargo'
