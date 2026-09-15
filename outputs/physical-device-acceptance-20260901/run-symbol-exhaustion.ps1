param(
  [string]$Target = '192.168.1.136:44621',
  [string]$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$evidenceDirectory = Join-Path $PSScriptRoot 'symbols-52'
$sourceRelativePath = & rg --files $workspace | Where-Object { $_ -match '2\.6\.' } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($sourceRelativePath)) {
  throw 'Unable to locate the authoritative 2.6 symbol lexicon.'
}
$sourcePath = if ([System.IO.Path]::IsPathRooted($sourceRelativePath)) {
  $sourceRelativePath
} else {
  Join-Path $workspace $sourceRelativePath
}
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null

$coordinates = @{
  a = @(125, 1680); b = @(650, 1840); c = @(435, 1840); d = @(330, 1680)
  e = @(280, 1510); f = @(435, 1680); g = @(540, 1680); h = @(650, 1680)
  i = @(805, 1510); j = @(755, 1680); k = @(860, 1680); l = @(965, 1680)
  m = @(860, 1840); n = @(755, 1840); o = @(910, 1510); p = @(1015, 1510)
  q = @(70, 1510); r = @(385, 1510); s = @(225, 1680); t = @(490, 1510)
  u = @(700, 1510); v = @(540, 1840); w = @(175, 1510); x = @(330, 1840)
  y = @(595, 1510); z = @(225, 1840)
}

function Invoke-Tap([string]$letter) {
  $point = $coordinates[$letter]
  & $Hdc -t $Target shell uitest uiInput click $point[0] $point[1] | Out-Null
}

function Get-Nodes($node) {
  $items = @($node)
  foreach ($child in @($node.children)) {
    $items += Get-Nodes $child
  }
  return $items
}

function Receive-Layout([string]$code, [int]$page) {
  $remote = "/data/local/tmp/symbol-$code-$page.json"
  $local = Join-Path $evidenceDirectory "$code-page$page.json"
  & $Hdc -t $Target shell uitest dumpLayout -p $remote | Out-Null
  & $Hdc -t $Target file recv $remote $local | Out-Null
  $layout = Get-Content -Raw -Encoding UTF8 -LiteralPath $local | ConvertFrom-Json
  $visible = Get-Nodes $layout | Where-Object {
    $attributes = $_.attributes
    if ($null -eq $attributes -or $attributes.type -ne 'Text' -or $attributes.clickable -ne 'true') {
      return $false
    }
    if ($attributes.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
      return $false
    }
    $top = [int]$matches[2]
    return $top -ge 1260 -and $top -le 1410
  } | Sort-Object {
    if ($_.attributes.bounds -match '^\[(\d+),') { return [int]$matches[1] }
    return 0
  } | ForEach-Object { $_.attributes.text }
  return @($visible)
}

$sourceLines = Get-Content -LiteralPath $sourcePath -Encoding UTF8
$expectedByCode = @{}
foreach ($prefix in @('ob', 'ox')) {
  foreach ($letter in [char[]]'abcdefghijklmnopqrstuvwxyz') {
    $code = "$prefix$letter"
    $values = @()
    foreach ($line in $sourceLines) {
      $parts = $line -split "`t", 2
      if ($parts.Count -ne 2 -or $parts[1].Trim() -ne $code) { continue }
      $raw = $parts[0].Trim()
      if ($raw -match '^\$cmd\((.*?),(.*?)\)$') {
        $values += $matches[2]
      } else {
        $values += $raw
      }
    }
    $expectedByCode[$code] = @($values)
  }
}

& $Hdc -t $Target shell uitest uiInput click 80 1830 | Out-Null
$results = @()
$ordinal = 0
foreach ($prefix in @('ob', 'ox')) {
  foreach ($letter in [char[]]'abcdefghijklmnopqrstuvwxyz') {
    $ordinal += 1
    $code = "$prefix$letter"
    $expected = @($expectedByCode[$code])
    Invoke-Tap 'o'
    Invoke-Tap $prefix.Substring(1, 1)
    Invoke-Tap ([string]$letter)
    Start-Sleep -Milliseconds 260

    $actual = @()
    $page = 0
    do {
      $page += 1
      $visible = @(Receive-Layout $code $page)
      foreach ($candidate in $visible) {
        if ($actual -notcontains $candidate) { $actual += $candidate }
      }
      if ($actual.Count -ge $expected.Count -or $page -ge 6) { break }
      & $Hdc -t $Target shell uitest uiInput swipe 1000 1338 100 1338 20000 | Out-Null
      Start-Sleep -Milliseconds 180
    } while ($true)

    $pass = $actual.Count -eq $expected.Count -and (($actual -join "`u{001f}") -eq ($expected -join "`u{001f}"))
    $results += [pscustomobject]@{
      ordinal = $ordinal
      code = $code
      expectedCount = $expected.Count
      actualCount = $actual.Count
      pass = $pass
      expected = ($expected -join '|')
      actual = ($actual -join '|')
      pages = $page
    }
    Write-Output ("[{0:D2}/52] {1} expected={2} actual={3} pages={4} {5}" -f $ordinal, $code, $expected.Count, $actual.Count, $page, $(if ($pass) { 'PASS' } else { 'FAIL' }))
    & $Hdc -t $Target shell uitest uiInput click 80 1830 | Out-Null
    Start-Sleep -Milliseconds 120
  }
}

$summaryPath = Join-Path $PSScriptRoot 'symbols-52-summary.json'
$csvPath = Join-Path $PSScriptRoot 'symbols-52-summary.csv'
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$failed = @($results | Where-Object { -not $_.pass })
Write-Output ("SUMMARY total={0} passed={1} failed={2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count -gt 0) { exit 2 }
