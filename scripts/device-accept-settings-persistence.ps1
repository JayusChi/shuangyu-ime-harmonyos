param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [switch]$RestoreOnly,
    [switch]$CandidateSmallOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$appProfile = Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundle = [string]$appProfile.app.bundleName
$outDir = Join-Path $repoRoot 'docs\evidence\settings-persistence\device'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir 'device_acceptance.log'
$normalHint = -join (@(0x666E, 0x901A, 0x6587, 0x672C, 0xFF1A, 0x9ED8, 0x8BA4, 0x4E2D, 0x6587) | ForEach-Object { [char]$_ })
$debugText = -join (@(0x8C03, 0x8BD5, 0x4E0E, 0x9A8C, 0x6536) | ForEach-Object { [char]$_ })
$darkText = -join (@(0x6DF1, 0x8272) | ForEach-Object { [char]$_ })
$largeText = [string][char]0x5927
$smallText = [string][char]0x5C0F
$followSystemText = -join (@(0x8DDF, 0x968F, 0x7CFB, 0x7EDF) | ForEach-Object { [char]$_ })
$standardText = -join (@(0x6807, 0x51C6) | ForEach-Object { [char]$_ })
$compactText = -join (@(0x7D27, 0x51D1) | ForEach-Object { [char]$_ })
$tallText = -join (@(0x8F83, 0x9AD8) | ForEach-Object { [char]$_ })
$settingsEntryText = -join (@(0x8BBE, 0x7F6E) | ForEach-Object { [char]$_ })

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "hdc failed: $($arguments -join ' ')" }
    return $output
}

function Force-Start-Settings {
    & $script:hdc -t $script:Target shell aa force-stop $script:bundle 2>&1 | Out-Null
    Invoke-Hdc shell aa start -b $script:bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $launcher = Dump-Layout 'settings_launcher'
    Tap-Node (Find-VisibleText $launcher $script:settingsEntryText)
    Start-Sleep -Milliseconds 500
    Invoke-Hdc shell uitest uiInput swipe 660 500 660 2700 600 | Out-Null
    Start-Sleep -Milliseconds 400
}

function Dump-Layout {
    param([string]$Name)
    $remote = "/data/local/tmp/$Name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $script:outDir "$Name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen {
    param([string]$Name)
    $remote = "/data/local/tmp/$Name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    Invoke-Hdc file recv $remote (Join-Path $script:outDir "$Name.png") | Out-Null
}

function Get-Nodes {
    param([string]$Path)
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[object]
    function Walk-Node($node) {
        if ($null -ne $node -and $null -ne $node.attributes) { $script:AcceptanceNodes.Add($node) | Out-Null }
        foreach ($child in @($node.children)) { Walk-Node $child }
    }
    $script:AcceptanceNodes = $list
    Walk-Node $json
    return $list.ToArray()
}

function Get-Center {
    param($Node)
    $match = [regex]::Match([string]$Node.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { throw "Invalid node bounds: $($Node.attributes.bounds)" }
    return [PSCustomObject]@{
        X = [int](([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        Y = [int](([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Find-VisibleText {
    param([string]$Path, [string]$Text, [switch]$Last)
    $matches = @(Get-Nodes $Path | Where-Object {
        [string]$_.attributes.text -eq $Text -and [string]$_.attributes.visible -eq 'true'
    })
    if ($matches.Count -eq 0) { throw "Visible text not found: codepoints=$([string]::Join(',', ($Text.ToCharArray() | ForEach-Object { [int]$_ })))" }
    if ($Last) { return $matches[-1] }
    return $matches[0]
}

function Find-NormalInput {
    param([string]$Path)
    $node = Get-Nodes $Path | Where-Object {
        [string]$_.attributes.hint -eq $script:normalHint -and [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
    if ($null -eq $node) { throw 'Normal input field not found.' }
    return $node
}

function Tap-Node {
    param($Node)
    $center = Get-Center $Node
    Invoke-Hdc shell uitest uiInput click $center.X $center.Y | Out-Null
    Start-Sleep -Milliseconds 600
}

function Select-Height {
    param([string]$Mode, [string]$Label)
    Force-Start-Settings
    $layout = Dump-Layout "select_height_$Mode"
    $choices = @(Get-Nodes $layout | Where-Object {
        [string]$_.attributes.text -eq $Label -and [string]$_.attributes.visible -eq 'true'
    } | Sort-Object {
        $match = [regex]::Match([string]$_.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        if ($match.Success) { -([int]$match.Groups[4].Value - [int]$match.Groups[2].Value) } else { 0 }
    })
    if ($choices.Count -eq 0) { throw "Height choice not found: $Mode" }
    Tap-Node $choices[0]
    Start-Sleep -Seconds 1
    $selectedLayout = Dump-Layout "selected_height_$Mode"
    $selectedChoice = @(Get-Nodes $selectedLayout | Where-Object {
        [string]$_.attributes.text -eq $Label -and [string]$_.attributes.visible -eq 'true'
    } | Sort-Object {
        $match = [regex]::Match([string]$_.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        if ($match.Success) { -([int]$match.Groups[4].Value - [int]$match.Groups[2].Value) } else { 0 }
    } | Select-Object -First 1)
    if ($selectedChoice.Count -eq 0) { throw "Selected height choice not found: $Mode" }
    $selectedBounds = [regex]::Match([string]$selectedChoice[0].attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    $rowTop = [int]$selectedBounds.Groups[2].Value
    $rowBottom = [int]$selectedBounds.Groups[4].Value
    $rowNodes = @(Get-Nodes $selectedLayout | Where-Object {
        $bounds = [regex]::Match([string]$_.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
        $bounds.Success -and [int]$bounds.Groups[2].Value -eq $rowTop -and
            [int]$bounds.Groups[4].Value -eq $rowBottom -and [string]$_.attributes.visible -eq 'true'
    })
    $selectedBackground = [string]$selectedChoice[0].attributes.backgroundColor
    $isSelected = @($rowNodes | Where-Object {
        [string]$_.attributes.backgroundColor -ne $selectedBackground
    }).Count -gt 0
    if (-not $isSelected) {
        throw "Height choice did not become selected: $Mode"
    }
    # Persisting settings also publishes them to the input-method process. Give
    # both asynchronous operations time to finish before force-stopping the app.
    Start-Sleep -Seconds 2
}

function Open-Debug-Input {
    & $script:hdc -t $script:Target shell aa force-stop $script:bundle 2>&1 | Out-Null
    Invoke-Hdc shell aa start -b $script:bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $launcher = Dump-Layout 'open_debug_launcher'
    Tap-Node (Find-VisibleText $launcher $script:debugText)
    $debug = Dump-Layout 'debug_input_page'
    return Find-NormalInput $debug
}

function Assert-Restarted-Height {
    param([string]$Mode, [string]$Label)
    $focusedLog = ''
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Select-Height -Mode $Mode -Label $Label
        Force-Start-Settings
        $normalInput = Open-Debug-Input
        Invoke-Hdc shell hilog -r | Out-Null
        Tap-Node $normalInput
        Start-Sleep -Seconds 3
        $rawLog = (Invoke-Hdc shell hilog -x) -join "`n"
        $focusedLog = ($rawLog -split "`n" | Where-Object {
            $_ -match 'SettingsRepository|Stage0InputMethodAbility|InputPanelController|ResizePanel'
        }) -join "`n"
        $focusedLog | Set-Content -LiteralPath (Join-Path $script:outDir "restart_$Mode.log") -Encoding UTF8
        if ($focusedLog -match "shared settings loaded:.*keyboardHeightMode=$Mode") {
            break
        }
        if ($attempt -eq 2) {
            throw "Input process did not load keyboardHeightMode=$Mode after two attempts"
        }
        Write-Host "RETRY: input process did not load keyboardHeightMode=$Mode on the first attempt"
    }
    $requestMatches = [regex]::Matches(
        $focusedLog,
        "panel resize requested:.*keyboardHeightMode=$Mode.*(?:widthPx|width)=(\d+), (?:heightPx|height)=(\d+)"
    )
    if ($requestMatches.Count -eq 0) {
        throw "Controller did not request a dynamic $Mode panel size"
    }
    $request = $requestMatches[$requestMatches.Count - 1]
    $requestedWidth = [int]$request.Groups[1].Value
    $requestedHeight = [int]$request.Groups[2].Value
    if ($requestedWidth -le 0 -or $requestedHeight -le 0) {
        throw "Controller requested an invalid $Mode panel size: $requestedWidth/$requestedHeight"
    }
    if ($focusedLog -notmatch "ResizePanel,success, width/height: $requestedWidth/$requestedHeight") {
        throw "Platform did not apply the requested $Mode panel size $requestedWidth/$requestedHeight"
    }
    Capture-Screen "restart_$Mode"
    $inputProcessPattern = [regex]::Escape("$script:bundle`:inputMethod")
    $pidLine = (Invoke-Hdc shell ps -A) | Where-Object { $_ -match $inputProcessPattern } | Select-Object -First 1
    Write-Host "PASS: restarted inputMethod restored $Mode and applied dynamic size $requestedWidth/$requestedHeight; process=$pidLine"
}

function Select-Dark-And-Large {
    Force-Start-Settings
    $homeLayout = Dump-Layout 'configure_dark_home'
    Tap-Node (Find-VisibleText $homeLayout $script:darkText)
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 500
    $feedback = Dump-Layout 'configure_large_feedback'
    Tap-Node (Find-VisibleText $feedback $script:largeText)
}

function Assert-Restarted-Candidate-Small {
    Force-Start-Settings
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 500
    $feedback = Dump-Layout 'select_candidate_small'
    Tap-Node (Find-VisibleText $feedback $script:smallText)
    Force-Start-Settings
    $normalInput = Open-Debug-Input
    Invoke-Hdc shell hilog -r | Out-Null
    Tap-Node $normalInput
    Start-Sleep -Seconds 3
    $rawLog = (Invoke-Hdc shell hilog -x) -join "`n"
    $focusedLog = ($rawLog -split "`n" | Where-Object {
        $_ -match 'SettingsRepository|InputPanelController|ResizePanel'
    }) -join "`n"
    $focusedLog | Set-Content -LiteralPath (Join-Path $script:outDir 'restart_candidate_small.log') -Encoding UTF8
    if ($focusedLog -notmatch 'shared settings loaded:.*candidateFontSizeMode=small') {
        throw 'The restarted input process did not restore small candidate font mode.'
    }
    Capture-Screen 'restart_candidate_small'
    Write-Host 'PASS: restarted inputMethod restored candidateFontSizeMode=small'
}

function Restore-Final-Defaults {
    Force-Start-Settings
    $homeLayout = Dump-Layout 'restore_home'
    Tap-Node (Find-VisibleText $homeLayout $script:followSystemText)
    $homeLayout = Dump-Layout 'restore_height_home'
    Tap-Node (Find-VisibleText $homeLayout $script:standardText)
    Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
    Start-Sleep -Milliseconds 500
    $feedback = Dump-Layout 'restore_candidate_feedback'
    Tap-Node (Find-VisibleText $feedback $script:standardText -Last)
    Force-Start-Settings
    $restored = Dump-Layout 'restored_defaults'
    $content = Get-Content -LiteralPath $restored -Raw -Encoding UTF8
    if ($content -notmatch $script:followSystemText -or $content -notmatch $script:standardText) { throw 'Final default labels are missing.' }
    Capture-Screen 'restored_defaults'
    Write-Host 'PASS: final settings restored to follow-system, standard height and standard candidate font'
}

if (-not (Test-Path -LiteralPath $hdc)) { throw "hdc not found: $hdc" }
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-Hdc shell ime -s $bundle | Out-Null
    $imeStatus = (Invoke-Hdc shell ime -g) -join "`n"
    if ($imeStatus -notmatch [regex]::Escape($bundle)) {
        throw "Current IME does not match the tested bundle: $bundle"
    }
    if ($RestoreOnly) {
        Restore-Final-Defaults
        Write-Host 'SETTINGS_PERSISTENCE_DEVICE_RESTORE_RESULT=PASS'
        return
    }
    if ($CandidateSmallOnly) {
        Assert-Restarted-Candidate-Small
        Restore-Final-Defaults
        Write-Host 'SETTINGS_PERSISTENCE_CANDIDATE_SMALL_RESULT=PASS'
        return
    }
    Select-Dark-And-Large
    Assert-Restarted-Height -Mode 'compact' -Label $compactText
    Assert-Restarted-Height -Mode 'standard' -Label $standardText
    Assert-Restarted-Height -Mode 'tall' -Label $tallText
    Restore-Final-Defaults
    Write-Host 'SETTINGS_PERSISTENCE_DEVICE_ACCEPTANCE_RESULT=PASS'
} finally {
    Stop-Transcript | Out-Null
}
