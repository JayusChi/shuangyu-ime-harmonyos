param(
    [string]$Path = (Join-Path $PSScriptRoot '..\docs\features\ai\AI1_HOST_ACCEPTANCE_RESULT.example.json'),
    [switch]$RequireComplete
)

$ErrorActionPreference = 'Stop'
$allowedStatuses = @('PASS', 'FAIL', 'NOT_RUN', 'BLOCKED')
$requiredEnvironmentIds = @(
    'phone-arkui',
    'pad-arkui',
    '2in1-arkui',
    'system-browser',
    'third-party-chat',
    'third-party-document',
    'sensitive-editors'
)
$requiredResultNames = @(
    'ordinaryInput',
    'localAssociation',
    'cloudActions',
    'lifecycleReplacement',
    'securityFallback'
)

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "AI1_HOST_ACCEPTANCE_INVALID: $Message"
    }
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$document = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-Condition ($document.schemaVersion -eq 1) 'schemaVersion must be 1'
Assert-Condition ($document.phase -eq 'AI-1') 'phase must be AI-1'
Assert-Condition ($allowedStatuses -contains $document.overallStatus) 'invalid overallStatus'
Assert-Condition ($null -ne $document.build) 'build is required'
Assert-Condition ($document.environments -is [System.Array]) 'environments must be an array'
Assert-Condition ($document.environments.Count -eq $requiredEnvironmentIds.Count) 'environment count mismatch'

$seen = @{}
foreach ($environment in $document.environments) {
    Assert-Condition ($requiredEnvironmentIds -contains $environment.id) "unknown environment id: $($environment.id)"
    Assert-Condition (-not $seen.ContainsKey($environment.id)) "duplicate environment id: $($environment.id)"
    $seen[$environment.id] = $true
    Assert-Condition ($allowedStatuses -contains $environment.status) "invalid status for $($environment.id)"
    Assert-Condition ($null -ne $environment.results) "results missing for $($environment.id)"
    foreach ($resultName in $requiredResultNames) {
        $property = $environment.results.PSObject.Properties[$resultName]
        Assert-Condition ($null -ne $property) "$resultName missing for $($environment.id)"
        Assert-Condition ($allowedStatuses -contains $property.Value) "invalid $resultName for $($environment.id)"
    }
    Assert-Condition ($environment.evidence -is [System.Array]) "evidence must be an array for $($environment.id)"
    if ($environment.status -eq 'PASS') {
        foreach ($resultName in $requiredResultNames) {
            Assert-Condition ($environment.results.$resultName -eq 'PASS') "PASS environment has incomplete $resultName"
        }
        Assert-Condition ($environment.evidence.Count -gt 0) "PASS environment requires evidence"
    }
}

if ($RequireComplete) {
    Assert-Condition ($document.overallStatus -eq 'PASS') 'overallStatus must be PASS for completion'
    Assert-Condition ($document.executedAt -match '^\d{4}-\d{2}-\d{2}T') 'executedAt is required for completion'
    Assert-Condition ($document.build.hapSha256 -match '^[A-Fa-f0-9]{64}$') 'valid HAP SHA-256 is required for completion'
    foreach ($environment in $document.environments) {
        Assert-Condition ($environment.status -eq 'PASS') "$($environment.id) is not PASS"
    }
}

$mode = if ($RequireComplete) { 'COMPLETE' } else { 'SCHEMA' }
Write-Host "AI1_HOST_ACCEPTANCE_${mode}=PASS"
