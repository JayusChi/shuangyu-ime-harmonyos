param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [switch]$SkipInstall
)

$arguments = @(
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'device-accept-xiaohe-yinxing-stage11_6_3.ps1'),
    '-Target', $Target,
    '-DevEcoRoot', $DevEcoRoot,
    '-EvidenceDir', 'docs\evidence\2026-07-23-stage-11.6.4-formal\device',
    '-ResultName', 'STAGE11_6_4_X86_64_DEVICE_RESULT'
)
if ($SkipInstall) { $arguments += '-SkipInstall' }
& powershell @arguments
exit $LASTEXITCODE
