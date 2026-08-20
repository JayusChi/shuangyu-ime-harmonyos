param(
    [switch]$SkipHap
)

$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host ''
    Write-Host "== $Name =="
    & $Action
}

Invoke-Step 'Environment check' {
    & (Join-Path $PSScriptRoot 'check-environment.ps1')
}

Invoke-Step 'Rust format, clippy, and tests' {
    & (Join-Path $PSScriptRoot 'test-rust.ps1')
}

Invoke-Step 'Rust native artifacts' {
    & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
}

if ($SkipHap) {
    Write-Host 'SKIPPED HAP build by -SkipHap.'
} else {
    Invoke-Step 'HAP build' {
        & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust
    }
}

Invoke-Step 'Artifact check' {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter libime_bridge.so |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'engine-rust\target\ohos') -Recurse -Filter *.a |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize
    if (-not $SkipHap) {
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Select-Object FullName, Length, LastWriteTime |
            Format-Table -AutoSize
    }
}
