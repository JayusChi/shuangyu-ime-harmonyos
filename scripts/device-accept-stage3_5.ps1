param(
    [string]$Target = '127.0.0.1:5555',
    [ValidateSet('Phone', 'Pad')]
    [string]$Form = 'Phone',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$bundle = 'com.corrosion.shuangyuime'
$safeTarget = $Target -replace '[^0-9A-Za-z_-]', '_'
$outDir = Join-Path $repoRoot "docs\evidence\stage3.5\device\$safeTarget"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "hdc failed: $($arguments -join ' ')" }
    return @($output)
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Host "PASS: $Message"
}

function Get-Bounds($Node) {
    $match = [regex]::Match([string]$Node.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { return $null }
    return [PSCustomObject]@{
        X1 = [int]$match.Groups[1].Value
        Y1 = [int]$match.Groups[2].Value
        X2 = [int]$match.Groups[3].Value
        Y2 = [int]$match.Groups[4].Value
        CX = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        CY = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Get-Nodes([string]$Path) {
    $root = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = New-Object System.Collections.Generic.List[object]
    function Walk($node, $parent) {
        if ($null -ne $node -and $null -ne $node.attributes) {
            $items.Add([PSCustomObject]@{ Node = $node; Parent = $parent; Bounds = Get-Bounds $node }) | Out-Null
        }
        foreach ($child in @($node.children)) { Walk $child $node }
    }
    Walk $root $null
    return $items.ToArray()
}

function Dump-Layout([string]$Name) {
    $remote = "/data/local/tmp/$Name.json"
    $local = Join-Path $outDir "$Name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen([string]$Name) {
    $remote = "/data/local/tmp/$Name.png"
    $local = Join-Path $outDir "$Name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    Invoke-Hdc file recv $remote $local | Out-Null
}

function Get-CustomImageButtons([string]$Path) {
    return @(Get-Nodes $Path | Where-Object {
        $_.Node.attributes.type -eq 'Row' -and
        $_.Node.attributes.clickable -eq 'true' -and
        $null -ne $_.Bounds -and
        @($_.Node.children | Where-Object { $_.attributes.type -eq 'Image' }).Count -gt 0
    } | Sort-Object { $_.Bounds.Y1 }, { $_.Bounds.X1 })
}

function Get-LanguageButton([string]$Path) {
    $chineseLabel = [string][char]0x4E2D
    $englishLabel = [string][char]0x82F1
    $entry = Get-Nodes $Path | Where-Object {
        ($_.Node.attributes.text -eq $chineseLabel -or $_.Node.attributes.text -eq $englishLabel) -and
        $null -ne $_.Parent -and $_.Parent.attributes.clickable -eq 'true'
    } | Select-Object -First 1
    if ($null -eq $entry) { return $null }
    return [PSCustomObject]@{ Node = $entry.Parent; Bounds = Get-Bounds $entry.Parent }
}

function Get-CurrentIme {
    return [string]((Invoke-Hdc shell ime -g) -join "`n")
}

$logPath = Join-Path $outDir 'stage3_5_device_acceptance.log'
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $PSScriptRoot 'device-accept-stage3_3.ps1') `
        -Target $Target -EvidenceStage 'stage3.5' -DevEcoRoot $DevEcoRoot
    if ($LASTEXITCODE -ne 0) { throw 'Stage 3.3 regression acceptance failed' }

    $idlePath = Join-Path $outDir 'stage3_3_idle.json'
    $buttons = Get-CustomImageButtons $idlePath
    $switchButton = $null
    if ($Form -eq 'Phone') {
        $languageButton = Get-LanguageButton $idlePath
        Assert-True ($null -ne $languageButton) 'Phone exposes the language key for long-press picker access'
        Assert-True ($buttons.Count -lt 3) 'Phone no longer exposes a separate switch-and-hide auxiliary row'
    } else {
        Assert-True ($buttons.Count -eq 2) 'Pad adds exactly one switch button besides the fixed top hide button'
        $switchButton = $buttons[-1]
    }

    if ($Form -eq 'Phone') {
        Invoke-Hdc shell uitest uiInput longClick $languageButton.Bounds.CX $languageButton.Bounds.CY | Out-Null
        Start-Sleep -Milliseconds 800
        $pickerPath = Dump-Layout 'stage3_5_phone_language_long_press_picker'
        Capture-Screen 'stage3_5_phone_language_long_press_picker'
        $pickerTitle = -join @([char]0x9009, [char]0x62E9, [char]0x8F93, [char]0x5165, [char]0x6CD5)
        $pickerLabel = @(Get-Nodes $pickerPath | Where-Object { $_.Node.attributes.text -eq $pickerTitle })
        Assert-True ($pickerLabel.Count -gt 0) 'Phone language-key long press opens the system input method picker'
    } else {
        $beforeIme = Get-CurrentIme
        Invoke-Hdc shell uitest uiInput click $switchButton.Bounds.CX $switchButton.Bounds.CY | Out-Null
        Start-Sleep -Milliseconds 1400
        $afterIme = Get-CurrentIme
        Assert-True ($beforeIme -ne $afterIme) 'Pad short press switches to the next enabled input method'
        Dump-Layout 'stage3_5_pad_short_press_switched' | Out-Null
        Capture-Screen 'stage3_5_pad_short_press_switched'

        Invoke-Hdc shell ime -s $bundle | Out-Null
        Start-Sleep -Milliseconds 1200
        Invoke-Hdc shell uitest uiInput longClick $switchButton.Bounds.CX $switchButton.Bounds.CY | Out-Null
        Start-Sleep -Milliseconds 800
        $pickerPath = Dump-Layout 'stage3_5_pad_long_press_picker'
        Capture-Screen 'stage3_5_pad_long_press_picker'
        $pickerTitle = -join @([char]0x9009, [char]0x62E9, [char]0x8F93, [char]0x5165, [char]0x6CD5)
        $pickerLabel = @(Get-Nodes $pickerPath | Where-Object { $_.Node.attributes.text -eq $pickerTitle })
        Assert-True ($pickerLabel.Count -gt 0) 'Pad long press opens the system input method picker'
    }

    Write-Host "STAGE3_5_DEVICE_ACCEPTANCE_RESULT=PASS; FORM=$Form; TARGET=$Target"
} finally {
    Stop-Transcript | Out-Null
}
