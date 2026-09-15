$ErrorActionPreference = 'Stop'
$packager = Join-Path $PSScriptRoot 'package-keyboard-customization.ps1'
$packages = Join-Path $PSScriptRoot 'packages'

& $packager -Kind structure `
    -SourceDirectory (Join-Path $PSScriptRoot 'structure-standard') `
    -OutputFile (Join-Path $packages 'my-keyboard.sy-layout')

& $packager -Kind skin `
    -SourceDirectory (Join-Path $PSScriptRoot 'skin-color-blue') `
    -OutputFile (Join-Path $packages 'my-color-skin.sy-skin')

& $packager -Kind skin `
    -SourceDirectory (Join-Path $PSScriptRoot 'skin-image-blue') `
    -OutputFile (Join-Path $packages 'my-image-skin.sy-skin')

Write-Output 'Done. Import the files in the packages folder from keyboard settings.'
