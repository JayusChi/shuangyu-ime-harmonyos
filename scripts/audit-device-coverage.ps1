param(
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\device-coverage',
    [switch]$RequirePhysicalCoverage
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$outDir = Join-Path $repoRoot $EvidenceDir

function Invoke-Hdc([string]$Target, [string[]]$Arguments) {
    $output = & $script:hdc -t $Target @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "hdc failed for $Target ($($Arguments -join ' ')): $($output -join [Environment]::NewLine)"
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Read-DeviceValue([string]$Target, [string[]]$Arguments) {
    return ((Invoke-Hdc $Target $Arguments) -join '').Trim()
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) {
    throw "hdc not found: $hdc"
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$verboseLines = @(& $hdc list targets -v 2>&1 | ForEach-Object { [string]$_ })
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list HDC targets: $($verboseLines -join [Environment]::NewLine)"
}

$targetRows = [Collections.Generic.List[object]]::new()
foreach ($line in $verboseLines) {
    $columns = @($line -split '\s+' | Where-Object { $_.Length -gt 0 })
    if ($columns.Count -lt 4) { continue }
    $targetRows.Add([ordered]@{
        target = $columns[0]
        transport = $columns[1]
        connectionState = $columns[2]
        host = $columns[3]
    }) | Out-Null
}

$connectedDevices = [Collections.Generic.List[object]]::new()
foreach ($row in @($targetRows | Where-Object { $_.connectionState -eq 'Connected' })) {
    $target = [string]$row.target
    $deviceType = Read-DeviceValue $target @('shell', 'param', 'get', 'const.product.devicetype')
    $model = Read-DeviceValue $target @('shell', 'param', 'get', 'const.product.model')
    $productName = Read-DeviceValue $target @('shell', 'param', 'get', 'const.product.name')
    $softwareVersion = Read-DeviceValue $target @('shell', 'param', 'get', 'const.product.software.version')
    $abi = Read-DeviceValue $target @('shell', 'uname', '-m')
    $inputDump = (Invoke-Hdc $target @('shell', 'hidumper', '-s', 'MultimodalInput', '-a', '-d')) -join "`n"
    $inputDumpPath = Join-Path $outDir (($target -replace '[:\\/]', '_') + '-input-devices.txt')
    $inputDump | Set-Content -LiteralPath $inputDumpPath -Encoding UTF8

    $identityText = "$target $model $productName $softwareVersion"
    $isEmulator = $identityText -match '(?i)emulator|localhost' -or $inputDump -match '(?i)QEMU|virtio'
    $isArm64 = $abi -match '(?i)arm64|aarch64'
    $usbBluetoothKeyboardMatches = @([regex]::Matches(
        $inputDump,
        '(?im)^.*deviceType:3\s+\|\s+bus:(3|5)\s+\|.*$'
    ))
    $hasUsbBluetoothKeyboard = $usbBluetoothKeyboardMatches.Count -gt 0

    $connectedDevices.Add([ordered]@{
        target = $target
        transport = [string]$row.transport
        deviceType = $deviceType
        model = $model
        productName = $productName
        softwareVersion = $softwareVersion
        abi = $abi
        isEmulator = $isEmulator
        isArm64 = $isArm64
        hasUsbBluetoothKeyboard = $hasUsbBluetoothKeyboard
        usbBluetoothKeyboardRecords = @($usbBluetoothKeyboardMatches | ForEach-Object { $_.Value.Trim() })
        inputDeviceEvidence = (Resolve-Path -LiteralPath $inputDumpPath).Path
    }) | Out-Null
}

$connected = @($connectedDevices)
$phoneCovered = @($connected | Where-Object { $_.deviceType -eq 'phone' }).Count -gt 0
$tabletCovered = @($connected | Where-Object { $_.deviceType -eq 'tablet' }).Count -gt 0
$twoInOneCovered = @($connected | Where-Object { $_.deviceType -eq '2in1' }).Count -gt 0
$arm64TwoInOneCovered = @($connected | Where-Object {
    $_.deviceType -eq '2in1' -and $_.isArm64 -and -not $_.isEmulator
}).Count -gt 0
$physicalKeyboardCovered = @($connected | Where-Object {
    $_.deviceType -eq '2in1' -and -not $_.isEmulator -and $_.hasUsbBluetoothKeyboard
}).Count -gt 0

$availableMatrixCovered = $phoneCovered -and $tabletCovered -and $twoInOneCovered
$physicalCoverageComplete = $arm64TwoInOneCovered -and $physicalKeyboardCovered
$summary = [ordered]@{
    capturedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    result = if ($availableMatrixCovered -and $physicalCoverageComplete) { 'PASS' } elseif ($availableMatrixCovered) { 'PARTIAL' } else { 'NOT_READY' }
    connectedTargetCount = $connected.Count
    offlineTargets = @($targetRows | Where-Object { $_.connectionState -ne 'Connected' })
    coverage = [ordered]@{
        phone = $phoneCovered
        tablet = $tabletCovered
        twoInOne = $twoInOneCovered
        arm64PhysicalTwoInOne = $arm64TwoInOneCovered
        usbOrBluetoothKeyboardOnPhysicalTwoInOne = $physicalKeyboardCovered
    }
    availableDeviceMatrixCovered = $availableMatrixCovered
    physicalCoverageComplete = $physicalCoverageComplete
    devices = $connected
}

$summaryPath = Join-Path $outDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "DEVICE_COVERAGE_RESULT=$($summary.result)"
Write-Host "AVAILABLE_DEVICE_MATRIX_COVERED=$($availableMatrixCovered.ToString().ToLowerInvariant())"
Write-Host "PHYSICAL_COVERAGE_COMPLETE=$($physicalCoverageComplete.ToString().ToLowerInvariant())"
Write-Host "SUMMARY=$((Resolve-Path -LiteralPath $summaryPath).Path)"

if ($RequirePhysicalCoverage -and -not $physicalCoverageComplete) {
    throw 'Physical acceptance coverage is incomplete: an ARM64 physical 2in1 with a detected USB or Bluetooth keyboard is required.'
}
