param(
    [string]$Target = '127.0.0.1:5555',
    [ValidateSet('stage3.3', 'stage3.4', 'stage3.5')]
    [string]$EvidenceStage = 'stage3.3',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$hap = (Resolve-Path (Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap')).Path
$appProfile = Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundle = [string]$appProfile.app.bundleName
$safeTarget = $Target -replace '[^0-9A-Za-z_-]', '_'
$outDir = Join-Path $repoRoot "docs\evidence\$EvidenceStage\device\$safeTarget"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$debugEntryLabel = -join @([char]0x8C03, [char]0x8BD5, [char]0x4E0E, [char]0x9A8C, [char]0x6536)
$normalInputHint = -join @([char]0x666E, [char]0x901A, [char]0x6587, [char]0x672C, [char]0xFF1A, [char]0x9ED8, [char]0x8BA4, [char]0x4E2D, [char]0x6587)
$shiftLabel = [string][char]0x21E7
$deleteLabel = -join @([char]0x5220, [char]0x9664)
$candidateNi = [string][char]0x4F60

function Invoke-Hdc {
    $arguments = @($args)
    Write-Host "> hdc -t $Target $($arguments -join ' ')"
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if ($exitCode -ne 0) { throw "hdc failed ($exitCode): $($arguments -join ' ')" }
    return $output
}

function Invoke-HdcAllowFail {
    $arguments = @($args)
    & $script:hdc -t $script:Target @arguments 2>&1 | ForEach-Object { Write-Host $_ }
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
    return $local
}

function Find-Text([string]$Path, [string]$Text) {
    return @(Get-Nodes $Path | Where-Object {
        [string]$_.Node.attributes.text -eq $Text -and $null -ne $_.Bounds
    } | Sort-Object { $_.Bounds.Y1 } -Descending | Select-Object -First 1)[0]
}

function Find-Hint([string]$Path, [string]$Hint) {
    return @(Get-Nodes $Path | Where-Object {
        [string]$_.Node.attributes.hint -eq $Hint -and $null -ne $_.Bounds
    } | Select-Object -First 1)[0]
}

function Find-KeyboardActionImage([string]$Path) {
    return @(Get-Nodes $Path | Where-Object {
        [string]$_.Node.attributes.type -eq 'Image' -and
        [string]$_.Parent.attributes.clickable -eq 'true' -and
        $null -ne $_.Bounds
    } | Sort-Object { ($_.Bounds.X2 - $_.Bounds.X1) * ($_.Bounds.Y2 - $_.Bounds.Y1) } | Select-Object -First 1)[0]
}

function Centers-Match($First, $Second, [int]$Tolerance = 2) {
    return [Math]::Abs($First.CX - $Second.CX) -le $Tolerance -and
        [Math]::Abs($First.CY - $Second.CY) -le $Tolerance
}

function Tap-Node($Item, [string]$Label) {
    if ($null -eq $Item) { throw "Node not found: $Label" }
    Write-Host "tap $Label at ($($Item.Bounds.CX),$($Item.Bounds.CY))"
    Invoke-Hdc shell uitest uiInput click $Item.Bounds.CX $Item.Bounds.CY | Out-Null
    Start-Sleep -Milliseconds 450
}

function Get-InputText([string]$Path) {
    $input = Find-Hint $Path $normalInputHint
    if ($null -eq $input) { throw 'normal input not found' }
    return [string]$input.Node.attributes.text
}

function Same-Bounds($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    return $Left.X1 -eq $Right.X1 -and $Left.Y1 -eq $Right.Y1 -and
        $Left.X2 -eq $Right.X2 -and $Left.Y2 -eq $Right.Y2
}

$logPath = Join-Path $outDir 'stage3_3_device_acceptance.log'
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    Write-Host "DEVICE_TARGET=$Target"
    Invoke-Hdc install -r $hap | Out-Null
    Invoke-HdcAllowFail shell aa force-stop $bundle
    Invoke-Hdc shell bm clean -n $bundle -d | Out-Null
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-HdcAllowFail shell ime -s $bundle
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2

    $entry = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        $entryLayout = Dump-Layout "stage3_3_entry_$attempt"
        $entry = Find-Text $entryLayout $debugEntryLabel
        if ($null -ne $entry) { break }
        $rootBounds = @(Get-Nodes $entryLayout | Where-Object { $null -ne $_.Bounds } | Sort-Object { ($_.Bounds.X2 - $_.Bounds.X1) * ($_.Bounds.Y2 - $_.Bounds.Y1) } -Descending | Select-Object -First 1)[0].Bounds
        Invoke-Hdc shell uitest uiInput swipe $rootBounds.CX ([int]($rootBounds.Y2 * 0.82)) $rootBounds.CX ([int]($rootBounds.Y2 * 0.20)) 900 | Out-Null
    }
    Tap-Node $entry 'debug acceptance entry'

    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $page = Dump-Layout "stage3_3_normal_page_$attempt"
        $input = Find-Hint $page $normalInputHint
        if ($null -ne $input) { break }
        $bounds = @(Get-Nodes $page | Where-Object { $null -ne $_.Bounds } | Sort-Object { ($_.Bounds.X2 - $_.Bounds.X1) * ($_.Bounds.Y2 - $_.Bounds.Y1) } -Descending | Select-Object -First 1)[0].Bounds
        Invoke-Hdc shell uitest uiInput swipe $bounds.CX ([int]($bounds.Y2 * 0.25)) $bounds.CX ([int]($bounds.Y2 * 0.82)) 900 | Out-Null
    }
    Tap-Node $input 'normal Chinese editor'

    $idle = Dump-Layout 'stage3_3_idle'
    Capture-Screen 'stage3_3_idle' | Out-Null
    $shift = Find-Text $idle $shiftLabel
    $hideIcon = Find-KeyboardActionImage $idle
    Assert-True ($null -ne $shift) 'idle Chinese dynamic key shows Shift'
    Assert-True ($null -ne $hideIcon) 'keyboard hidden-key vector icon is present'
    Assert-True (Centers-Match $hideIcon.Bounds (Get-Bounds $hideIcon.Parent)) `
        'keyboard hidden-key vector is geometrically centered in its action key'
    @('Q','W','E','R','T','Y','U','I','O','P','A','S','D','F','G','H','J','K','L','Z','X','C','V','B','N','M') |
        ForEach-Object { Assert-True ($null -ne (Find-Text $idle $_)) "Chinese key label is uppercase: $_" }
    $shiftButtonBounds = Get-Bounds $shift.Parent

    Tap-Node $shift 'enable Chinese uppercase direct input'
    $caps = Dump-Layout 'stage3_3_caps_enabled'
    Tap-Node (Find-Text $caps 'Q') 'direct uppercase Q'
    $afterQ = Dump-Layout 'stage3_3_after_direct_q'
    Assert-True ((Get-InputText $afterQ) -eq 'Q') 'Chinese uppercase lock commits Q directly'
    Assert-True ($null -ne (Find-Text $afterQ $shiftLabel)) 'direct uppercase input leaves composition empty'

    Tap-Node (Find-Text $afterQ $shiftLabel) 'disable Chinese uppercase direct input'
    $capsOff = Dump-Layout 'stage3_3_caps_disabled'
    Tap-Node (Find-Text $capsOff $deleteLabel) 'remove direct uppercase Q'
    $empty = Dump-Layout 'stage3_3_empty_again'
    Assert-True ((Get-InputText $empty) -eq '') 'delete restores empty editor before boundary test'

    Tap-Node (Find-Text $empty 'N') 'Chinese code n'
    $afterN = Dump-Layout 'stage3_3_after_n'
    Tap-Node (Find-Text $afterN 'I') 'Chinese code i'
    $beforeBoundary = Dump-Layout 'stage3_3_before_boundary'
    $boundary = Find-Text $beforeBoundary "'"
    Assert-True ($null -ne $boundary) 'non-empty composition changes dynamic key to segment boundary'
    Assert-True (Same-Bounds $shiftButtonBounds (Get-Bounds $boundary.Parent)) 'dynamic key keeps the same fixed hit region'

    Tap-Node $boundary 'insert structured segment boundary'
    $afterBoundary = Dump-Layout 'stage3_3_after_boundary'
    Capture-Screen 'stage3_3_after_boundary' | Out-Null
    Assert-True ((Get-InputText $afterBoundary) -eq "ni'") 'boundary updates preview without committing final text'
    Tap-Node (Find-Text $afterBoundary "'") 'reject repeated boundary'
    $afterRepeated = Dump-Layout 'stage3_3_after_repeated_boundary'
    Assert-True ((Get-InputText $afterRepeated) -eq "ni'") 'repeated invalid boundary preserves composition'

    Tap-Node (Find-Text $afterRepeated $deleteLabel) 'backspace removes boundary'
    $afterBackspace = Dump-Layout 'stage3_3_after_boundary_backspace'
    Assert-True ((Get-InputText $afterBackspace) -eq 'ni') 'backspace removes boundary deterministically'
    Tap-Node (Find-Text $afterBackspace $candidateNi) 'commit candidate through existing path'
    $committed = Dump-Layout 'stage3_3_candidate_committed'
    Assert-True ((Get-InputText $committed) -eq $candidateNi) 'candidate commit contains no boundary character'

    Write-Host 'STAGE3_3_DEVICE_ACCEPTANCE_RESULT=PASS'
} finally {
    Stop-Transcript | Out-Null
}
