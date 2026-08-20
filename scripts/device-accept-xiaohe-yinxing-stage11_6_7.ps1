param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [switch]$SkipInstall
)

# This wrapper covers the complete A-N runtime-page matrix, including the
# authoritative forward/reverse empty-code split contract in J/K.
$arguments = @(
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'device-accept-xiaohe-yinxing-stage11_6_3.ps1'),
    '-Target', $Target,
    '-DevEcoRoot', $DevEcoRoot,
    '-EvidenceDir', 'docs\evidence\2026-07-24-stage-11.6.7-complete\device',
    '-ResultName', 'STAGE11_6_7_COMPLETE_RUNTIME_PAGE_RESULT',
    '-CaseRegex', '^PASS . 11\.6\.7 ([A-N]) ',
    '-FailureCaseRegex', '^FAIL . 11\.6\.7 ([A-N]) ',
    '-ExpectedCaseCount', '14',
    '-ScrollCount', '18',
    '-PageWaitSeconds', '45'
)
if ($SkipInstall) { $arguments += '-SkipInstall' }
& powershell @arguments
exit $LASTEXITCODE
