$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$device = '127.0.0.1:5555'
$evidence = $PSScriptRoot
function Invoke-PickerHdc {
    $result = & $hdc -t $device @args
    if ($LASTEXITCODE -ne 0) { throw 'HDC command failed' }
    $result
}
function Get-PickerNodes($node) {
    if ($node.attributes) { $node.attributes }
    foreach ($child in $node.children) { Get-PickerNodes $child }
}
function Save-PickerUi([string]$name) {
    if ($name -notmatch '^[a-z0-9-]+$') { throw 'Invalid evidence name' }
    Invoke-PickerHdc shell uitest dumpLayout -p "/data/local/tmp/picker-$name.json" | Out-Null
    Invoke-PickerHdc file recv "/data/local/tmp/picker-$name.json" (Join-Path $evidence "$name.json") | Out-Null
    Invoke-PickerHdc shell uitest screenCap -p "/data/local/tmp/picker-$name.png" | Out-Null
    Invoke-PickerHdc file recv "/data/local/tmp/picker-$name.png" (Join-Path $evidence "$name.png") | Out-Null
    $tree = Get-Content (Join-Path $evidence "$name.json") -Raw | ConvertFrom-Json
    Get-PickerNodes $tree
}
function Click-PickerNode($node) {
    if ($null -eq $node) { throw 'Missing target UI node' }
    $bounds = [regex]::Match($node.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $bounds.Success) { throw 'Missing UI bounds' }
    $x = [int](([int]$bounds.Groups[1].Value + [int]$bounds.Groups[3].Value) / 2)
    $y = [int](([int]$bounds.Groups[2].Value + [int]$bounds.Groups[4].Value) / 2)
    Invoke-PickerHdc shell uitest uiInput click $x $y | Out-Null
}
