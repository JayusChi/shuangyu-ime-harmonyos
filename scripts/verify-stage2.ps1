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

function Assert-PanelHeightAtLeast {
    param(
        [string]$Path,
        [int]$MinimumHeight
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }

    $content = Get-Content -Encoding UTF8 -LiteralPath $Path -Raw
    if ($content -notmatch 'const\s+STAGE2_PANEL_HEIGHT\s*=\s*(\d+)') {
        throw 'STAGE2_PANEL_HEIGHT constant not found.'
    }

    $height = [int]$Matches[1]
    if ($height -lt $MinimumHeight) {
        throw "STAGE2_PANEL_HEIGHT must be at least $MinimumHeight px; found $height px."
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

Invoke-Step 'Stage 2 source checks' {
    Assert-FileContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\state\InputSessionStore.ets') `
        -Pattern 'sessionActive' `
        -Message 'InputSessionStore must keep sessionActive.'
    Assert-FileContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\application\InputSessionController.ets') `
        -Pattern 'insertLetter' `
        -Message 'InputSessionController must expose letter input.'
    Assert-FileContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\application\KeyboardController.ets') `
        -Pattern 'KeyboardActionType' `
        -Message 'KeyboardController must route typed keyboard actions.'
    Assert-FileContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRoot.ets') `
        -Pattern 'ForEach\(\s*QWERTY_KEY_ROWS\s*,' `
        -Message 'KeyboardRoot must render QWERTY_KEY_ROWS in natural top-to-bottom order.'
    Assert-FileNotContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRoot.ets') `
        -Pattern 'QWERTY_KEY_ROWS\s*(\.\s*slice\s*\(\s*\))?\s*\.\s*reverse\s*\(' `
        -Message 'KeyboardRoot must not reverse the QWERTY row order.'
    Assert-FileNotContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\presentation\keyboard\KeyboardRoot.ets') `
        -Pattern 'Button\s*\(\s*this\.keyLabel\s*\(\s*spec\s*\)\s*\)' `
        -Message 'Keyboard key labels must be rendered with explicit Text, not Button(label), to avoid visual clipping on narrow keys.'
    Assert-PanelHeightAtLeast `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\application\InputPanelController.ets') `
        -MinimumHeight 1100
    Assert-FileContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\ime\ImeConnectionService.ets') `
        -Pattern 'deleteBackwardSync' `
        -Message 'Stage 1 delete fallback must be preserved.'
    Assert-FileContains `
        -Path (Join-Path $repoRoot 'entry\src\main\ets\infrastructure\ime\ImeConnectionService.ets') `
        -Pattern 'selectByRange' `
        -Message 'Stage 1 range delete fallback must be preserved.'
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
Write-Host '== Stage 2 verification summary =='
$script:Results | Format-Table -AutoSize
