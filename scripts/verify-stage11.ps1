param(
    [switch]$SkipNative,
    [switch]$SkipHap,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
$results = New-Object System.Collections.Generic.List[object]
$evidenceDir = Join-Path $repoRoot 'docs\evidence\stage11'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$transcriptStarted = $false
Start-Transcript -Path (Join-Path $evidenceDir 'verify-stage11.log') -Force | Out-Null
$transcriptStarted = $true

function Invoke-Stage11Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "`n== $Name =="
    try {
        & $Action
        $script:results.Add([PSCustomObject]@{ Step = $Name; Result = 'PASS' }) | Out-Null
    } catch {
        $script:results.Add([PSCustomObject]@{ Step = $Name; Result = 'FAIL' }) | Out-Null
        throw
    }
}

function Assert-FileExists {
    param([string]$RelativePath)
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath))) {
        throw "Missing Stage 11 file: $RelativePath"
    }
}

function Assert-ArkTsTestReport {
    param(
        [string]$ReportPath,
        [datetime]$StartedAt
    )
    if (-not (Test-Path -LiteralPath $ReportPath)) {
        throw "ArkTS test result report was not generated: $ReportPath"
    }
    $reportFile = Get-Item -LiteralPath $ReportPath
    if ($reportFile.LastWriteTime -lt $StartedAt.AddSeconds(-2)) {
        throw "ArkTS test result report is stale: $ReportPath"
    }
    $content = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8
    $summary = [regex]::Match(
        $content,
        'Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+),\s*Ignore:\s*(\d+)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $summary.Success) {
        throw "ArkTS test result report has no machine-readable summary: $ReportPath"
    }
    $total = [int]$summary.Groups[1].Value
    $failures = [int]$summary.Groups[2].Value
    $errors = [int]$summary.Groups[3].Value
    $passed = [int]$summary.Groups[4].Value
    $ignored = [int]$summary.Groups[5].Value
    $nonSuccessResults = [regex]::Matches(
        $content,
        '(?im)^result=(?!Success\s*$).+$'
    )
    if ($total -le 0 -or $passed + $failures + $errors + $ignored -ne $total) {
        throw "ArkTS test result summary is inconsistent: total=$total pass=$passed failure=$failures error=$errors ignore=$ignored"
    }
    if ($failures -gt 0 -or $errors -gt 0 -or $nonSuccessResults.Count -gt 0) {
        throw "ArkTS assertions failed: total=$total pass=$passed failure=$failures error=$errors ignore=$ignored"
    }
    Write-Host "ARKTS_TEST_RESULT=PASS total=$total pass=$passed failure=$failures error=$errors ignore=$ignored"
}

try {
    Invoke-Stage11Step 'Stage 11 required files' {
        @(
            'entry\src\main\ets\domain\settings\ImeSettings.ets',
            'entry\src\main\ets\domain\display\ScreenMetrics.ets',
            'entry\src\main\ets\infrastructure\display\DeviceMetricsProvider.ets',
            'entry\src\main\ets\infrastructure\storage\SettingsRepository.ets',
            'entry\src\main\ets\infrastructure\storage\SettingsMigration.ets',
            'entry\src\main\ets\infrastructure\storage\SettingsValidator.ets',
            'entry\src\main\ets\infrastructure\storage\SettingsSyncBus.ets',
            'entry\src\main\ets\infrastructure\storage\UserModelCommandBus.ets',
            'entry\src\main\ets\infrastructure\storage\UserModelCommandRepository.ets',
            'entry\src\main\ets\state\SettingsStore.ets',
            'entry\src\main\ets\application\SettingsController.ets',
            'entry\src\main\ets\infrastructure\haptic\HapticFeedbackService.ets',
            'entry\src\main\ets\infrastructure\audio\KeySoundService.ets',
            'entry\src\internalDebug\ets\pages\DebugStage10.ets',
            'entry\src\test\Stage11.test.ets',
            'docs\adr\0011-stage11-settings-theme-feedback.md',
            'docs\evidence\stage11\stage11_validation.md'
        ) | ForEach-Object { Assert-FileExists $_ }
    }

    Invoke-Stage11Step 'Architecture and privacy guards' {
        $presentation = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\src\main\ets\presentation') -Recurse -File
        foreach ($file in $presentation) {
            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            if ($content -match 'libime_bridge\.so|@kit\.IMEKit|preferences\.getPreferences') {
                throw "Presentation boundary violation: $($file.FullName)"
            }
        }
        $module = Get-Content -LiteralPath (Join-Path $repoRoot 'entry\src\main\module.json5') -Raw -Encoding UTF8
        if ($module -match 'INTERNET|MICROPHONE') { throw 'Network or microphone permission must not be added.' }
        $formalKeyboard = Get-Content -LiteralPath (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRootStage3.ets') -Raw -Encoding UTF8
        if ($formalKeyboard -match 'BuildProfile|回归|模型|Regression|getTestCandidates|getDebugUserModelRecordCount') {
            throw 'Formal keyboard must not contain interactive regression or model-debug controls.'
        }
    }

    Invoke-Stage11Step 'ArkTS Stage 9/10/11 unit regression' {
        if (-not (Test-Path -LiteralPath $hvigor)) { throw "hvigorw not found: $hvigor" }
        $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
        $testResult = Join-Path $repoRoot 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
        if (Test-Path -LiteralPath $testResult) {
            Remove-Item -LiteralPath $testResult -Force
        }
        $testStartedAt = Get-Date
        Push-Location $repoRoot
        try {
            & $hvigor --no-daemon --mode module -p module=entry@default test
            $hvigorExitCode = $LASTEXITCODE
        } finally { Pop-Location }
        Assert-ArkTsTestReport -ReportPath $testResult -StartedAt $testStartedAt
        if ($hvigorExitCode -ne 0) { throw "ArkTS tests failed with exit code $hvigorExitCode" }
    }

    if (-not $SkipNative) {
        Invoke-Stage11Step 'Rust fmt, clippy, workspace tests and Native dual ABI' {
            & (Join-Path $PSScriptRoot 'verify-stage9.ps1') -SkipHap -DevEcoRoot $DevEcoRoot
            if ($LASTEXITCODE -ne 0) { throw "Stage 9 regression failed with exit code $LASTEXITCODE" }
        }
    }

    if (-not $SkipHap) {
        Invoke-Stage11Step 'HAP build' {
            & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust -BuildMode release -DevEcoRoot $DevEcoRoot
            if ($LASTEXITCODE -ne 0) { throw "HAP build failed with exit code $LASTEXITCODE" }
            & (Join-Path $PSScriptRoot 'verify-release-hap.ps1')
            if ($LASTEXITCODE -ne 0) { throw "Release HAP verification failed with exit code $LASTEXITCODE" }
        }
    }

    $results | Format-Table -AutoSize
    Write-Host 'STAGE11_VERIFY_RESULT=PASS'
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    exit 0
} catch {
    $results | Format-Table -AutoSize
    Write-Error $_
    Write-Host 'STAGE11_VERIFY_RESULT=FAIL'
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    exit 1
}
