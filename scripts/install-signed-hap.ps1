[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$HapPath = '',
    [string[]]$Target = @(),
    [switch]$AllConnected,
    [switch]$ResetSignature,
    [string]$BundleName = 'com.corrosion.shuangyuime',
    [string]$HdcPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$resolvedHapPath = if ([string]::IsNullOrWhiteSpace($HapPath)) {
    Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
} else {
    [IO.Path]::GetFullPath($HapPath)
}
if (-not (Test-Path -LiteralPath $resolvedHapPath -PathType Leaf)) {
    throw "Signed HAP not found: $resolvedHapPath"
}

$resolvedHdcPath = if (-not [string]::IsNullOrWhiteSpace($HdcPath)) {
    [IO.Path]::GetFullPath($HdcPath)
} elseif ($env:DEVECO_STUDIO_ROOT) {
    Join-Path $env:DEVECO_STUDIO_ROOT 'sdk\default\openharmony\toolchains\hdc.exe'
} else {
    'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
}
if (-not (Test-Path -LiteralPath $resolvedHdcPath -PathType Leaf)) {
    throw "hdc.exe not found: $resolvedHdcPath"
}

function Invoke-Hdc([string]$DeviceTarget, [string[]]$HdcArgs) {
    $lines = @(& $resolvedHdcPath -t $DeviceTarget @HdcArgs 2>&1)
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Text = ($lines -join [Environment]::NewLine)
    }
}

if ($AllConnected) {
    $Target = @(& $resolvedHdcPath list targets 2>&1 | ForEach-Object { ([string]$_).Trim() } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('[')
    })
}
$Target = @($Target | Select-Object -Unique)
if ($Target.Count -eq 0) {
    throw 'No device target selected. Pass -Target <serial> or -AllConnected.'
}

$remoteDir = '/data/local/tmp/shuangyuime-signed-install'
$remoteHap = "$remoteDir/entry-signed.hap"
$failures = [Collections.Generic.List[string]]::new()

foreach ($deviceTarget in $Target) {
    $online = Invoke-Hdc $deviceTarget @('shell', 'echo', 'SHUANGYUIME_DEVICE_ONLINE')
    if (-not $online.Text.Contains('SHUANGYUIME_DEVICE_ONLINE')) {
        $failures.Add("$deviceTarget is not ready or has not been authorized for HDC")
        continue
    }

    $imeBefore = Invoke-Hdc $deviceTarget @('shell', 'ime', '-g')
    $imeListBefore = Invoke-Hdc $deviceTarget @('shell', 'ime', '-l')
    $wasCurrentIme = $imeBefore.Text.Contains($BundleName)
    $wasEnabledIme = $imeListBefore.Text.Contains("bundle: $BundleName")
    $dumpBefore = Invoke-Hdc $deviceTarget @('shell', 'bm', 'dump', '-n', $BundleName)
    $wasInstalled = $dumpBefore.Text.Contains('"bundleName": "' + $BundleName + '"')

    $mkdir = Invoke-Hdc $deviceTarget @('shell', 'mkdir', '-p', $remoteDir)
    if ($mkdir.ExitCode -ne 0 -or $mkdir.Text -match '(?im)^\[Fail\]') {
        $failures.Add("$deviceTarget could not create the device staging directory: $($mkdir.Text)")
        continue
    }
    $send = Invoke-Hdc $deviceTarget @('file', 'send', $resolvedHapPath, $remoteHap)
    if (-not $send.Text.Contains('FileTransfer finish')) {
        $failures.Add("$deviceTarget could not receive the signed HAP: $($send.Text)")
        continue
    }

    try {
        $installArgs = if ($wasInstalled) {
            @('shell', 'bm', 'install', '-r', '-p', $remoteHap)
        } else {
            @('shell', 'bm', 'install', '-p', $remoteHap)
        }
        $install = Invoke-Hdc $deviceTarget $installArgs
        $didResetSignature = $false

        if (-not $install.Text.Contains('install bundle successfully.')) {
            if (-not $install.Text.Contains('9568332')) {
                throw "install failed: $($install.Text)"
            }
            if (-not $ResetSignature) {
                throw 'installed package uses another certificate (9568332); export any needed app data, then rerun with -ResetSignature'
            }
            if (-not $PSCmdlet.ShouldProcess(
                "$deviceTarget/$BundleName",
                'remove the old certificate identity and its app sandbox, then install the fixed signed HAP'
            )) {
                continue
            }

            Write-Warning "${deviceTarget}: signature reset deletes the old app sandbox; bm uninstall -k cannot migrate across certificates."
            [void](Invoke-Hdc $deviceTarget @('shell', 'aa', 'force-stop', $BundleName))
            $uninstall = Invoke-Hdc $deviceTarget @('shell', 'bm', 'uninstall', '-n', $BundleName)
            if (-not $uninstall.Text.Contains('uninstall bundle successfully.')) {
                throw "signature reset uninstall failed: $($uninstall.Text)"
            }
            $install = Invoke-Hdc $deviceTarget @('shell', 'bm', 'install', '-p', $remoteHap)
            if (-not $install.Text.Contains('install bundle successfully.')) {
                throw "install after signature reset failed: $($install.Text)"
            }
            $didResetSignature = $true
        }

        [void](Invoke-Hdc $deviceTarget @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $BundleName))
        if ($wasEnabledIme) {
            $enable = Invoke-Hdc $deviceTarget @('shell', 'ime', '-e', $BundleName, '-f')
            if (-not $enable.Text.Contains('Succeeded in enabling IME')) {
                throw "installed, but restoring IME enablement failed: $($enable.Text)"
            }
        }
        if ($wasCurrentIme) {
            $switch = Invoke-Hdc $deviceTarget @('shell', 'ime', '-s', $BundleName)
            if (-not $switch.Text.Contains('Succeeded in switching the input method')) {
                throw "installed, but restoring the selected IME failed: $($switch.Text)"
            }
        }

        $dumpAfter = Invoke-Hdc $deviceTarget @('shell', 'bm', 'dump', '-n', $BundleName)
        $versions = @([regex]::Matches($dumpAfter.Text, '"versionName"\s*:\s*"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $version = if ($versions.Count -gt 0) { $versions[-1] } else { 'unknown' }
        Write-Host "TARGET=$deviceTarget RESULT=PASS SIGNATURE_RESET=$($didResetSignature.ToString().ToLowerInvariant()) VERSION=$version"
    } catch {
        $failures.Add("${deviceTarget}: $($_.Exception.Message)")
    } finally {
        [void](Invoke-Hdc $deviceTarget @('shell', 'rm', '-f', $remoteHap))
        [void](Invoke-Hdc $deviceTarget @('shell', 'rmdir', $remoteDir))
    }
}

if ($failures.Count -gt 0) {
    throw ("Signed HAP installation failed:`n- " + ($failures -join "`n- "))
}
