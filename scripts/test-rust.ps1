$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ohos-abi.ps1')
Add-CargoBinToPathIfNeeded

Push-Location (Join-Path $PSScriptRoot '..\engine-rust')
try {
    cargo fmt --check
    if ($LASTEXITCODE -ne 0) {
        throw "cargo fmt failed with exit code $LASTEXITCODE"
    }

    cargo clippy --workspace --all-targets -- -D warnings
    if ($LASTEXITCODE -ne 0) {
        throw "cargo clippy failed with exit code $LASTEXITCODE"
    }

    cargo test --workspace
    if ($LASTEXITCODE -ne 0) {
        throw "cargo test failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
