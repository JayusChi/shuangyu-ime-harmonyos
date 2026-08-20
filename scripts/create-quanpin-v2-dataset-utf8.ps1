[CmdletBinding()]
param(
    [string]$OutputDirectory = 'artifacts\quanpin-lexicon-v2\dataset'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$implementationPath = Join-Path $PSScriptRoot 'create-quanpin-v2-dataset.ps1'
$implementation = Get-Content -LiteralPath $implementationPath -Raw -Encoding UTF8

# Windows PowerShell 5.1 decodes a BOM-less .ps1 as the active ANSI code page
# before executing it. The dataset implementation intentionally stays UTF-8
# without a BOM, so this ASCII-only entry point performs an explicit decode.
Push-Location $repoRoot
try {
    & ([scriptblock]::Create($implementation)) -OutputDirectory $OutputDirectory
} finally {
    Pop-Location
}
