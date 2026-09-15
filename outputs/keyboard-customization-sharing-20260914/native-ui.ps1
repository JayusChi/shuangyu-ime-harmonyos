param(
  [string]$Target = '127.0.0.1:5557',
  [ValidateSet('dump','tap','fill','screen')][string]$Action = 'dump',
  [string]$Text = '', [string]$Hint = '', [string]$Type = '', [string]$Id = '',
  [string]$Value = '', [string]$Name = 'current', [string]$Filter = '.'
)
$ErrorActionPreference = 'Stop'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$dir = Join-Path $PSScriptRoot ('device-evidence\' + $Target.Replace(':','_'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Invoke-Hdc {
  $result = & $script:hdc -t $script:Target @args 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($result -join "`n") }
  return $result
}
function Snapshot([string]$label) {
  $remote = '/data/local/tmp/skin-accept-' + $label + '.json'
  $local = Join-Path $script:dir ($label + '.json')
  Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
  Invoke-Hdc file recv $remote $local | Out-Null
  $tree = Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json
  $list = [Collections.Generic.List[object]]::new()
  function Visit($node) {
    if ($node.attributes) { $list.Add($node.attributes) }
    foreach ($child in $node.children) { Visit $child }
  }
  Visit $tree
  return $list.ToArray()
}
if ($Action -eq 'screen') {
  $remote = '/data/local/tmp/skin-accept-' + $Name + '.png'
  Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
  $local = Join-Path $dir ($Name + '.png')
  Invoke-Hdc file recv $remote $local | Out-Null
  Write-Output $local
  exit
}
$nodes = @(Snapshot ($Name + '-before'))
if ($Action -ne 'dump') {
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
  $matching = @($nodes | Where-Object {
    $_.visible -eq 'true' -and
    (!$Text -or $_.text -eq $Text) -and (!$Hint -or $_.hint -eq $Hint) -and
    (!$Type -or $_.type -eq $Type) -and (!$Id -or $_.id -eq $Id)
  })
  if ($matching.Count -eq 1) { break }
  Start-Sleep -Milliseconds 700
  $nodes = @(Snapshot ($Name + '-retry-' + $attempt))
  }
  if ($matching.Count -ne 1) { throw ('Expected one visible node; found ' + $matching.Count + ' for ' + $Text + $Hint + $Id) }
  $bounds = [regex]::Match($matching[0].bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
  if (!$bounds.Success) { throw 'Invalid node bounds' }
  $x = [int](([int]$bounds.Groups[1].Value + [int]$bounds.Groups[3].Value) / 2)
  $y = [int](([int]$bounds.Groups[2].Value + [int]$bounds.Groups[4].Value) / 2)
  Invoke-Hdc shell uitest uiInput click $x $y | Out-Null
  if ($Action -eq 'fill') {
    Invoke-Hdc shell uitest uiInput keyEvent 2072 2017 | Out-Null
    $quoted = "'" + $Value.Replace("'", "'\''") + "'"
    Invoke-Hdc shell ('uitest uiInput text ' + $quoted) | Out-Null
  }
  Start-Sleep -Milliseconds 450
  $nodes = @(Snapshot ($Name + '-after'))
  if ($Action -eq 'fill' -and @($nodes | Where-Object { $_.visible -eq 'true' -and $_.bundleName -match 'inputmethod|shuangyuime' -and $_.type -eq 'root' }).Count -gt 0) {
    Invoke-Hdc shell uitest uiInput keyEvent Back | Out-Null
    $nodes = @(Snapshot ($Name + '-keyboard-hidden'))
  }
}
$nodes | Where-Object {
  $_.visible -eq 'true' -and ($_.text -or $_.hint) -and (($_.text + ' ' + $_.hint) -match $Filter)
} | ForEach-Object {
  $_ | Select-Object text,hint,type,bounds,id | ConvertTo-Json -Compress
}

