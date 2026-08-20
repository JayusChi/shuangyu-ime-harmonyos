param(
    [switch]$SkipHap,
    [switch]$DeviceValidation,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'

$script:Results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Result,
        [string]$Detail
    )

    $script:Results += [PSCustomObject]@{
        Step = $Name
        Result = $Result
        Detail = $Detail
    }
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host ''
    Write-Host "== $Name =="
    & $Action
    Add-Result -Name $Name -Result 'PASS' -Detail 'completed'
}

function Assert-FileContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }

    $content = Get-Content -Encoding UTF8 -LiteralPath $Path -Raw
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-FileNotContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }

    $content = Get-Content -Encoding UTF8 -LiteralPath $Path -Raw
    if ($content -match $Pattern) {
        throw $Message
    }
}

function Assert-FileExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

Invoke-Step 'Environment check' {
    & (Join-Path $PSScriptRoot 'check-environment.ps1')
}

Invoke-Step 'Rust format, clippy, and tests' {
    & (Join-Path $PSScriptRoot 'test-rust.ps1')
}

Invoke-Step 'Rust x86_64 and arm64-v8a artifacts' {
    & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
}

Invoke-Step 'ArkTS unit tests' {
    $hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
    if (-not (Test-Path -LiteralPath $hvigor)) {
        throw "hvigorw not found: $hvigor"
    }

    $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
    Push-Location $repoRoot
    try {
        & $hvigor --no-daemon --mode module -p module=entry@default test
        if ($LASTEXITCODE -ne 0) {
            throw "ArkTS unit tests failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

if ($SkipHap) {
    Write-Host ''
    Write-Host '== HAP build =='
    Write-Host 'SKIPPED HAP build by -SkipHap.'
    Add-Result -Name 'HAP build' -Result 'SKIP' -Detail 'skipped by -SkipHap'
} else {
    Invoke-Step 'C++/ArkTS/HAP build' {
        & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust
    }
}

Invoke-Step 'Stage 3 source checks' {
    # 检查设计常量文件存在
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\design\KeyboardMetrics.ets') -Message 'KeyboardMetrics.ets must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\design\KeyboardPalette.ets') -Message 'KeyboardPalette.ets must exist'

    # 检查布局模型文件存在
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\model\KeyboardLayoutSpec.ets') -Message 'KeyboardLayoutSpec.ets must exist'

    # 检查删除控制器存在
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\application\DeleteRepeatController.ets') -Message 'DeleteRepeatController.ets must exist'

    # 检查候选栏组件存在
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\candidate\CandidateBar.ets') -Message 'CandidateBar.ets must exist'

    # 检查基础按键组件存在
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\components\BaseKey.ets') -Message 'BaseKey.ets must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\components\DeleteKey.ets') -Message 'DeleteKey.ets must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\components\LetterKey.ets') -Message 'LetterKey.ets must exist'

    # 检查新KeyboardRoot存在
    Assert-FileExists -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRootStage3.ets') -Message 'KeyboardRootStage3.ets must exist'

    # 检查InputPanelController使用新KeyboardRoot
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\InputPanelController.ets') -Pattern 'KeyboardRootStage3' -Message 'InputPanelController must use KeyboardRootStage3'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\InputPanelController.ets') -Pattern 'if \(!created \|\| !panel\)' -Message 'InputPanelController must stop when panel creation fails'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\resources\base\profile\main_pages.json') -Pattern 'presentation/keyboard/KeyboardRootStage3' -Message 'main_pages.json must register KeyboardRootStage3 for setUiContent'

    # 检查布局数据不使用reverse
    Assert-FileNotContains -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\model\KeyboardLayoutSpec.ets') -Pattern '\.reverse\s*\(' -Message 'KeyboardLayoutSpec must not reverse row order'

    # 检查KeyboardRootStage3不直接调用IME Kit
    Assert-FileNotContains -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRootStage3.ets') -Pattern '@kit\.IMEKit' -Message 'KeyboardRootStage3 must not directly import IME Kit'
    Assert-FileNotContains -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRootStage3.ets') -Pattern 'libime_bridge' -Message 'KeyboardRootStage3 must not directly import the native bridge'

    # 检查DeleteRepeatController清理逻辑存在
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\DeleteRepeatController.ets') -Pattern 'destroy' -Message 'DeleteRepeatController must have destroy method'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\DeleteRepeatController.ets') -Pattern 'clearTimeout' -Message 'DeleteRepeatController must clear timers'

    # 保留阶段2源码检查
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\state\InputSessionStore.ets') -Pattern 'sessionActive' -Message 'InputSessionStore must keep sessionActive'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\InputSessionController.ets') -Pattern 'insertLetter' -Message 'InputSessionController must expose letter input'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\application\KeyboardController.ets') -Pattern 'KeyboardActionType' -Message 'KeyboardController must route typed keyboard actions'
    Assert-FileContains -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\ime\ImeConnectionService.ets') -Pattern 'deleteBackwardSync' -Message 'Stage 1 delete fallback must be preserved'
}

Invoke-Step 'Artifact summary' {
    $rustRoot = Join-Path $repoRoot 'engine-rust\target\ohos'
    Get-ChildItem -LiteralPath $rustRoot -Recurse -Filter *.a |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize

    if (-not $SkipHap) {
        $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $hap) {
            throw 'HAP artifact not found under entry\build.'
        }
        Write-Host "HAP: $($hap.FullName)"
        Write-Host "Size: $($hap.Length) bytes"
    }
}

if ($DeviceValidation) {
    Invoke-Step 'Device install and IME status' {
        $hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
        if (-not (Test-Path -LiteralPath $hdc)) {
            throw "hdc not found: $hdc"
        }

        $targets = & $hdc list targets
        Write-Host $targets
        if (-not $targets -or $targets.Trim().Length -eq 0 -or $targets -match 'Empty') {
            throw 'No online device target found for -DeviceValidation.'
        }

        $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $hap) {
            throw 'HAP artifact not found for device validation.'
        }

        $bundleContent = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw
        if ($bundleContent -notmatch '"bundleName"\s*:\s*"([^"]+)"') {
            throw 'bundleName not found in AppScope/app.json5.'
        }
        $bundleName = $Matches[1]

        & $hdc install -r $hap.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "hdc install failed with exit code $LASTEXITCODE"
        }

        & $hdc shell ime -e $bundleName -f
        if ($LASTEXITCODE -ne 0) {
            throw "ime enable failed with exit code $LASTEXITCODE"
        }

        & $hdc shell ime -g
        if ($LASTEXITCODE -ne 0) {
            throw "ime status failed with exit code $LASTEXITCODE"
        }
    }
} else {
    Write-Host ''
    Write-Host '== Device install and IME status =='
    Write-Host 'SKIPPED device validation. Re-run with -DeviceValidation when an emulator/device is online.'
    Add-Result -Name 'Device install and IME status' -Result 'SKIP' -Detail 'not requested'
}

Write-Host ''
Write-Host '== Stage 3 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 3 keyboard UI engineering verification completed.'
