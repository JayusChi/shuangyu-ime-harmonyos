param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('structure', 'skin')]
    [string]$Kind,

    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath($SourceDirectory)
$output = [IO.Path]::GetFullPath($OutputFile)
$manifest = if ($Kind -eq 'structure') { 'layout.json' } else { 'skin.json' }

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Source directory does not exist: $source"
}
if (-not (Test-Path -LiteralPath (Join-Path $source $manifest) -PathType Leaf)) {
    throw "Source directory is missing $manifest"
}

$outputDirectory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$temporaryZip = [IO.Path]::ChangeExtension($output, ".tmp.$([Guid]::NewGuid().ToString('N')).zip")
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($temporaryZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $sourcePrefix = $source.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) +
            [IO.Path]::DirectorySeparatorChar
        foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
            $relativePath = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $file.FullName,
                $relativePath,
                [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally {
        $archive.Dispose()
    }
    Move-Item -LiteralPath $temporaryZip -Destination $output -Force
    Write-Output "Created $Kind package: $output"
} finally {
    if (Test-Path -LiteralPath $temporaryZip) {
        Remove-Item -LiteralPath $temporaryZip -Force
    }
}
