param(
    [string]$Target = '127.0.0.1:5557',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [switch]$SkipInstall,
    [string]$EvidenceDir = 'docs\evidence\2026-07-27-stage-11.6.8-revalidation\positive-device'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$hap = Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
$outDir = Join-Path $repoRoot $EvidenceDir
$imeBundle = 'com.corrosion.shuangyuime'
$editorBundle = 'com.example.nexttest'
$xiaoheLabel = -join @([char]0x32, [char]0x36, [char]0x20, [char]0x952E, [char]0x53CC, [char]0x62FC)
$yinxingLabel = -join @(
    [char]0x32, [char]0x36, [char]0x20, [char]0x952E,
    [char]0x5C0F, [char]0x9E64, [char]0x97F3, [char]0x5F62
)
$nihaoText = -join @([char]0x4F60, [char]0x597D)
$abaText = -join @([char]0x963F, [char]0x7238)
$spaceLabel = -join @([char]0x7A7A, [char]0x683C)
$script:keyDumpSequence = 0
New-Item -ItemType Directory -Force $outDir | Out-Null
$logPath = Join-Path $outDir 'device-acceptance.log'

function Invoke-Hdc {
    $arguments = @($args)
    $output = & $script:hdc -t $script:Target @arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if ($exitCode -ne 0) { throw "hdc failed ($exitCode): $($arguments -join ' ')" }
    return $output
}

function Dump-Layout([string]$name) {
    $remote = "/data/local/tmp/$name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $outDir "$name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen([string]$name) {
    $remote = "/data/local/tmp/$name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    Invoke-Hdc file recv $remote (Join-Path $outDir "$name.png") | Out-Null
}

function Visit-Nodes($node, [scriptblock]$visitor) {
    & $visitor $node
    foreach ($child in @($node.children)) { Visit-Nodes $child $visitor }
}

function Get-TextNodes([string]$path, [string]$text) {
    $root = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = [Collections.Generic.List[object]]::new()
    Visit-Nodes $root {
        param($node)
        if ($null -ne $node.attributes -and [string]$node.attributes.text -eq $text) {
            $result.Add($node) | Out-Null
        }
    }
    return $result.ToArray()
}

function Get-TypeNodes([string]$path, [string]$type) {
    $root = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = [Collections.Generic.List[object]]::new()
    Visit-Nodes $root {
        param($node)
        if ($null -ne $node.attributes -and [string]$node.attributes.type -eq $type) {
            $result.Add($node) | Out-Null
        }
    }
    return $result.ToArray()
}

function Get-Center([string]$bounds) {
    $match = [regex]::Match($bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "invalid bounds: $bounds" }
    return [ordered]@{
        X = [math]::Floor(([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2)
        Y = [math]::Floor(([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2)
    }
}

function Click-Text([string]$layout, [string]$text) {
    $nodes = @(Get-TextNodes $layout $text | Where-Object { $_.attributes.clickable -eq 'true' })
    if ($nodes.Count -ne 1) { throw "expected one clickable '$text', found $($nodes.Count)" }
    $center = Get-Center $nodes[0].attributes.bounds
    Invoke-Hdc shell uitest uiInput click $center.X $center.Y | Out-Null
}

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERT FAILED: $message" }
    Write-Host "PASS: $message"
}

function Get-TextInputValue([string]$layout) {
    $root = Get-Content -LiteralPath $layout -Raw -Encoding UTF8 | ConvertFrom-Json
    $values = [Collections.Generic.List[string]]::new()
    Visit-Nodes $root {
        param($node)
        if ($null -ne $node.attributes -and [string]$node.attributes.type -eq 'TextInput') {
            $values.Add([string]$node.attributes.text) | Out-Null
        }
    }
    if ($values.Count -ne 1) { throw "expected one independent TextInput, found $($values.Count)" }
    return $values[0]
}

function Open-Settings([string]$name) {
    Invoke-Hdc shell aa start -a EntryAbility -b $imeBundle | Out-Null
    Start-Sleep -Seconds 3
    return Dump-Layout $name
}

function Open-Editor {
    Invoke-Hdc shell aa force-stop $editorBundle | Out-Null
    Invoke-Hdc shell bm clean -n $editorBundle -d | Out-Null
    Invoke-Hdc shell aa start -a EntryAbility -b $editorBundle | Out-Null
    Start-Sleep -Seconds 3
    $layout = Dump-Layout 'editor-before-focus'
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $nodes = @(Get-TypeNodes $layout 'TextInput')
        if ($nodes.Count -ne 1) { throw 'independent TextInput hint not found' }
        $bounds = [regex]::Match(
            [string]$nodes[0].attributes.bounds,
            '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'
        )
        if (-not $bounds.Success) { throw 'independent TextInput bounds are invalid' }
        $focusX = [math]::Floor(([int]$bounds.Groups[1].Value + [int]$bounds.Groups[3].Value) / 2)
        # Use the upper third: the unfocused editor places its lower half under the system gesture area.
        $focusY = [int]$bounds.Groups[2].Value +
            [math]::Floor(([int]$bounds.Groups[4].Value - [int]$bounds.Groups[2].Value) / 3)
        Invoke-Hdc shell uitest uiInput click $focusX $focusY | Out-Null
        Start-Sleep -Seconds 2
        $layout = Dump-Layout "editor-focus-attempt-$attempt"
        if (@(Get-TextNodes $layout 'N').Count -eq 1) {
            return
        }
    }
    throw 'keyboard did not become visible after focusing independent TextInput'
}

function Press-VisibleKey([string]$label) {
    $script:keyDumpSequence += 1
    $layout = Dump-Layout "key-$($script:keyDumpSequence)"
    $nodes = @(Get-TextNodes $layout $label | Where-Object {
        $bounds = [regex]::Match([string]$_.attributes.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        [string]$_.attributes.type -eq 'Text' -and
            [string]$_.attributes.text -ceq $label -and
            $bounds.Success -and [int]$bounds.Groups[2].Value -ge 1800
    })
    if ($nodes.Count -ne 1) {
        throw "expected one visible keyboard key '$label', found $($nodes.Count)"
    }
    $center = Get-Center $nodes[0].attributes.bounds
    Invoke-Hdc shell uitest uiInput click $center.X $center.Y | Out-Null
    Start-Sleep -Milliseconds 500
}

function Type-XiaoheNihao {
    Press-VisibleKey 'N'
    Press-VisibleKey 'I'
    Press-VisibleKey 'H'
    Press-VisibleKey 'C'
    Press-VisibleKey $spaceLabel
}

function Type-YinxingAaba {
    Press-VisibleKey 'A'
    Press-VisibleKey 'A'
    Press-VisibleKey 'B'
    Press-VisibleKey 'A'
}

function Assert-EditorText([string]$name, [string]$expected) {
    Start-Sleep -Seconds 2
    $layout = Dump-Layout $name
    Assert-True ((Get-TextInputValue $layout) -eq $expected) "$name independent TextInput text is '$expected'"
    Capture-Screen $name
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "hdc not found: $hdc" }
if (-not (Test-Path -LiteralPath $hap -PathType Leaf)) { throw "signed Release HAP not found: $hap" }

Start-Transcript -Path $logPath -Force | Out-Null
try {
    $targetList = Invoke-Hdc list targets -v
    Assert-True (($targetList -join "`n") -match [regex]::Escape($Target)) 'target is connected'
    $abi = ((Invoke-Hdc shell param get const.product.cpu.abilist) -join ' ').Trim()
    $screen = (Invoke-Hdc shell hidumper -s RenderService -a screen) -join "`n"
    $resolution = [regex]::Match($screen, 'render resolution=(\d+x\d+)').Groups[1].Value
    Assert-True ($abi -eq 'x86_64') 'device ABI is x86_64'
    Assert-True ($resolution -eq '1320x2856') 'phone automation profile is 1320x2856'

    if (-not $SkipInstall) { Invoke-Hdc install -r $hap | Out-Null }
    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Invoke-Hdc shell bm clean -n $imeBundle -d | Out-Null
    Invoke-Hdc shell ime -e $imeBundle -f | Out-Null
    $current = (Invoke-Hdc shell ime -g) -join ' '
    if ($current -notmatch [regex]::Escape($imeBundle)) {
        Invoke-Hdc shell ime -s $imeBundle | Out-Null
    }
    Invoke-Hdc shell hilog -r | Out-Null

    $initial = Open-Settings 'a-b-default-settings'
    $xiaoheNodes = @(Get-TextNodes $initial $xiaoheLabel)
    $yinxingNodes = @(Get-TextNodes $initial $yinxingLabel)
    Assert-True ($xiaoheNodes.Count -eq 1 -and $yinxingNodes.Count -eq 1) `
        'A/B 26-key xiaohe and yinxing profiles are visible'
    if ($xiaoheNodes[0].attributes.backgroundColor -ne '#FFDCEBFF') {
        Click-Text $initial $xiaoheLabel
        Start-Sleep -Seconds 4
        $initial = Dump-Layout 'a-b-xiaohe-selected'
        $xiaoheNodes = @(Get-TextNodes $initial $xiaoheLabel)
    }
    Assert-True ($xiaoheNodes[0].attributes.backgroundColor -eq '#FFDCEBFF') `
        'A 26-key xiaohe is selected before input'
    $initialText = Get-Content -LiteralPath $initial -Raw -Encoding UTF8
    Assert-True ($initialText -notmatch 'fixture|code-table-fixture') 'B no fixture scheme is visible'
    Capture-Screen 'a-b-default-settings'

    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Open-Editor
    Type-XiaoheNihao
    Assert-EditorText 'a-xiaohe-nihao' $nihaoText

    $switch = Open-Settings 'c-before-yinxing-switch'
    Click-Text $switch $yinxingLabel
    Start-Sleep -Seconds 6
    $selected = Dump-Layout 'c-yinxing-selected'
    $selectedNode = @(Get-TextNodes $selected $yinxingLabel)
    Assert-True ($selectedNode[0].attributes.backgroundColor -eq '#FFDCEBFF') 'C yinxing is selected after Native validation'
    Capture-Screen 'c-yinxing-selected'

    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Open-Editor
    Type-YinxingAaba
    Assert-EditorText 'c-yinxing-aaba' $abaText

    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Open-Editor
    Type-YinxingAaba
    Assert-EditorText 'd-yinxing-after-force-stop' $abaText

    Press-VisibleKey 'A'
    Press-VisibleKey 'A'
    Press-VisibleKey 'B'
    $back = Open-Settings 'e-before-xiaohe-switch'
    Click-Text $back $xiaoheLabel
    Start-Sleep -Seconds 4
    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Open-Editor
    Type-XiaoheNihao
    Assert-EditorText 'e-xiaohe-after-yinxing-composition' $nihaoText

    $again = Open-Settings 'f-before-yinxing-switch'
    Click-Text $again $yinxingLabel
    Start-Sleep -Seconds 6
    $againSelected = Dump-Layout 'f-yinxing-selected'
    $againSelectedNode = @(Get-TextNodes $againSelected $yinxingLabel)
    Assert-True ($againSelectedNode[0].attributes.backgroundColor -eq '#FFDCEBFF') `
        'F yinxing is selected before force-stop'
    Capture-Screen 'f-yinxing-selected'
    Invoke-Hdc shell aa force-stop $imeBundle | Out-Null
    Open-Editor
    Type-YinxingAaba
    Assert-EditorText 'f-yinxing-reused-bundle' $abaText

    Invoke-Hdc shell hilog -x | Out-Null
    $hapItem = Get-Item -LiteralPath $hap
    $report = [ordered]@{
        capturedAt = (Get-Date).ToString('o')
        serial = $Target
        abi = $abi
        resolution = $resolution
        signedReleaseHapBytes = $hapItem.Length
        signedReleaseHapSha256 = (Get-FileHash -LiteralPath $hap -Algorithm SHA256).Hash.ToLowerInvariant()
        cases = [ordered]@{
            A = 'PASS default xiaohe and independent TextInput output'
            B = 'PASS 26-key xiaohe and xiaohe-yinxing profiles are visible'
            C = 'PASS formal bundle and independent TextInput aaba output'
            D = 'PASS force-stop restores yinxing and reuses the installed bundle'
            E = 'PASS switch to xiaohe discards old composition and xiaohe works'
            F = 'PASS second yinxing switch reuses bundle and aaba works'
        }
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir 'device-acceptance.json') -Encoding UTF8
    Write-Host 'STAGE11_6_8_POSITIVE_DEVICE_RESULT=PASS'
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host 'STAGE11_6_8_POSITIVE_DEVICE_RESULT=FAIL'
    Stop-Transcript | Out-Null
    exit 1
}
