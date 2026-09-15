$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
. "$PSScriptRoot/helpers.ps1"
$measurements=@()
foreach($target in @('phone','computer')) {
  foreach($variant in @('11','10')) {
    $prefix=Join-Path $PSScriptRoot "$target/final-margin$variant-keyboard"
    if(!(Test-Path "$prefix.png")){continue}
    $nodes=@(Nodes (Get-Content "$prefix.json" -Raw -Encoding UTF8 | ConvertFrom-Json))
    $label=$nodes | Where-Object text -ceq '1' | Select-Object -Last 1
    if(!$label){throw "Missing upper label in $prefix"}
    $b=@([regex]::Matches($label.bounds,'\d+') | ForEach-Object {[int]$_.Value})
    $bitmap=[Drawing.Bitmap]::new("$prefix.png")
    $xs=@()
    for($y=$b[1];$y -lt $b[3];$y++) {
      for($x=$b[0];$x -lt $b[2];$x++) {
        $pixel=$bitmap.GetPixel($x,$y)
        if($pixel.R -lt 210 -and $pixel.G -lt 210 -and $pixel.B -lt 210){$xs+=$x}
      }
    }
    $bitmap.Dispose()
    $q=$nodes | Where-Object text -ceq 'Q' | Select-Object -Last 1
    $qb=@([regex]::Matches($q.bounds,'\d+') | ForEach-Object {[int]$_.Value})
    $measurements += [pscustomobject]@{device=$target;marginVp=[int]$variant;labelBounds=$label.bounds;glyphLeft=($xs|Measure-Object -Minimum).Minimum;glyphRight=($xs|Measure-Object -Maximum).Maximum;letterHeightPx=$qb[3]-$qb[1]}
  }
}
$measurements | ConvertTo-Json | Set-Content "$PSScriptRoot/appearance-measurements.json" -Encoding UTF8
$measurements | Format-Table
