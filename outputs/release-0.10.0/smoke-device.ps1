param([Parameter(Mandatory=$true)][string]$Target,[Parameter(Mandatory=$true)][string]$Name)
. (Join-Path $PSScriptRoot '../settings-ui-migration-20260909/helpers.ps1')
$device=$Target
$evidence=Join-Path $PSScriptRoot $Name
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
function Ready([string]$name,[string]$id,[switch]$Shot) {
 for($attempt=0;$attempt -lt 6;$attempt++) {
  Ui $name -Shot:$Shot | Out-Null
  if($script:uiNodes | Where-Object id -eq $id){return}
  Start-Sleep -Milliseconds 500
 }
 throw "UI did not show $id"
}
Read-Settings 'settings-before' | Out-Null
Invoke-Device shell aa force-stop com.corrosion.shuangyuime | Out-Null
Invoke-Device shell aa start -a EntryAbility -b com.corrosion.shuangyuime | Out-Null
Ready 'home' 'settings-section-about'
IdTap 'settings-section-about'
Ui 'about' -Shot | Out-Null
if(-not ($script:uiNodes | Where-Object text -eq '双羽输入法 · 0.10.0')){throw 'About version text mismatch'}
$wide=[bool]($script:uiNodes | Where-Object id -eq 'settings-section-appearance')
if(-not $wide){Key 2; Ready 'home-return' 'settings-section-appearance'}
IdTap 'settings-section-appearance'
Ready 'appearance' 'settings-customization'
IdTap 'settings-customization'
Ready 'customization' 'settings-open-customization-skin'
IdTap 'settings-open-customization-skin'
Ready 'skin' 'settings-import-skin' -Shot
if($wide -and -not ($script:uiNodes | Where-Object id -eq 'settings-section-appearance')){throw 'Wide layout lost left navigation'}
Key 2
Ready 'customization-return' 'settings-open-customization-skin'
Read-Settings 'settings-after' | Out-Null
$before=Get-Content -LiteralPath (Join-Path $evidence 'settings-before.xml') -Raw
$after=Get-Content -LiteralPath (Join-Path $evidence 'settings-after.xml') -Raw
if($before -cne $after){throw 'Settings changed during read-only navigation'}
$result=[ordered]@{target=$Target;name=$Name;deviceType=((Invoke-Device shell param get const.product.devicetype) -join '').Trim();version='0.10.0';installation='developer-signed default product from same source';aboutVersion='PASS';nestedSkinNavigation='PASS';backNavigation='PASS';layout=$(if($wide){'split'}else{'stack'});settingsUnchanged=$true;timestamp=[DateTimeOffset]::Now.ToString('o')}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'smoke-result.json') -Encoding utf8
$result | ConvertTo-Json
