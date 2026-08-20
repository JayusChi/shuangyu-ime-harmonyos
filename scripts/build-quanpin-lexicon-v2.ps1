[CmdletBinding()]
param(
    [string]$AsOfDate = '2026-08-14',
    [ValidateSet('default','all_domains')][string]$ProductionProfile = 'all_domains',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$sourceRoot = Join-Path $repoRoot 'dictionaries\source\quanpin-v2'
$catalogPath = Join-Path $sourceRoot 'source-catalog.json'
$filterPath = Join-Path $sourceRoot 'filter-policy.txt'
$baseProduction = Join-Path $repoRoot 'dictionaries\generated\production.normalized.tsv'
$shortSentences = Join-Path $repoRoot 'dictionaries\source\stage11_5_short_sentences.tsv'
$generatedRoot = Join-Path $repoRoot 'dictionaries\generated\quanpin-v2'
$artifactRoot = Join-Path $repoRoot 'artifacts\quanpin-lexicon-v2'
$rawProduction = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$utf8 = [Text.UTF8Encoding]::new($false)
$invariant = [Globalization.CultureInfo]::InvariantCulture
$dateStyles = [Globalization.DateTimeStyles]::None
$maxRows = 10000
$maxTextChars = 16
$maxSyllables = 16
$maxFieldChars = 256
$frequencyByLayer = @{
    base = @{ core = 6000L; high = 4000L; normal = 1600L; low = 600L }
    domain = @{ core = 1600L; high = 1400L; normal = 1000L; low = 400L }
    hot = @{ core = 1000L; high = 800L; normal = 650L; low = 500L }
}
$domains = @('education','finance','legal','medical','software','technology')

foreach ($path in @($catalogPath, $filterPath, $shortSentences)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required V2 input missing: $path" }
}
$asOf = [DateTime]::MinValue
if (-not [DateTime]::TryParseExact($AsOfDate, 'yyyy-MM-dd', $invariant, $dateStyles, [ref]$asOf)) {
    throw 'AsOfDate must use yyyy-MM-dd.'
}
New-Item -ItemType Directory -Force -Path $generatedRoot, $artifactRoot | Out-Null

# Recreate the inherited production TSV from its licensed YAML source. The
# legacy script verifies its own source manifest before emitting this file.
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\build-lexicon.ps1') -Check
if ($LASTEXITCODE -ne 0) { throw "base source normalization failed: $LASTEXITCODE" }

$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$licensedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$sourceRecords = [Collections.Generic.List[object]]::new()
foreach ($source in $catalog.sources) {
    $absolute = Join-Path $repoRoot ([string]$source.path)
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "catalog source missing: $absolute" }
    if ([string]$source.license -ne 'Apache-2.0') { throw "unclear or unsupported license for $($source.path)" }
    $actualHash = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$source.sha256) { throw "source hash mismatch for $($source.path): $actualHash" }
    foreach ($sourceId in @($source.sourceIds)) { [void]$licensedIds.Add([string]$sourceId) }
    $sourceRecords.Add([ordered]@{
        path = ([string]$source.path).Replace('\','/')
        sha256 = $actualHash
        sourceIds = @($source.sourceIds)
        license = [string]$source.license
        updatedAt = [string]$source.updatedAt
        processingRule = [string]$source.processingRule
    })
}

$inventoryText = Get-Content -LiteralPath (Join-Path $repoRoot 'engine-rust\crates\pinyin-syllable\src\inventory.rs') -Raw -Encoding UTF8
$inventoryMatch = [regex]::Match($inventoryText, 'const VALID_SYLLABLES: &str = "(?s)(.*?)";')
if (-not $inventoryMatch.Success) { throw 'cannot read pinyin syllable inventory' }
$validSyllables = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$inventoryMatch.Groups[1].Value -split '\s+' | Where-Object { $_ } | ForEach-Object { [void]$validSyllables.Add($_) }
$blocked = @(
    [IO.File]::ReadLines($filterPath, [Text.Encoding]::UTF8) |
        ForEach-Object { $_.Normalize([Text.NormalizationForm]::FormC).Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
)

function Read-Date([string]$value, [string]$field, [int]$line) {
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($value, 'yyyy-MM-dd', $invariant, $dateStyles, [ref]$parsed)) {
        throw "line $line has invalid $field date: $value"
    }
    return $parsed
}

function Get-Key([string]$text, [string]$pinyin) { return "$text`0$pinyin" }

# Existing production keys are authoritative. V2 duplicates never add to an
# inherited frequency, which protects established common candidates.
$existingKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($path in @($baseProduction, $shortSentences)) {
    foreach ($line in [IO.File]::ReadLines($path, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -ge 2) {
            $normalizedPinyin = (($parts[1].Trim().ToLowerInvariant() -split '\s+') | Where-Object { $_ }) -join ' '
            [void]$existingKeys.Add((Get-Key $parts[0].Trim() $normalizedPinyin))
        }
    }
}

$accepted = [Collections.Generic.List[object]]::new()
$stats = [ordered]@{ inputRows=0; acceptedRows=0; inheritedDuplicates=0; mergedDuplicates=0; expired=0; filtered=0 }
foreach ($fileName in @('base.tsv','hotwords-2026-08.tsv','domains.tsv')) {
    $path = Join-Path $sourceRoot $fileName
    $rows = @(Import-Csv -LiteralPath $path -Delimiter "`t" -Encoding UTF8)
    foreach ($row in $rows) {
        $stats.inputRows++
        if ($stats.inputRows -gt $maxRows) { throw "V2 source exceeds hard row limit $maxRows" }
        $text = ([string]$row.text).Normalize([Text.NormalizationForm]::FormC).Trim()
        $pinyin = ((([string]$row.pinyin).Normalize([Text.NormalizationForm]::FormC).Trim().ToLowerInvariant() -split '\s+') | Where-Object { $_ }) -join ' '
        $tier = ([string]$row.frequencyTier).Trim().ToLowerInvariant()
        $category = ([string]$row.category).Trim()
        $sourceId = ([string]$row.sourceId).Trim()
        $updatedAt = ([string]$row.updatedAt).Trim()
        $expiresAt = ([string]$row.expiresAt).Trim()
        $domain = ([string]$row.domain).Trim().ToLowerInvariant()
        $layer = ([string]$row.layer).Trim().ToLowerInvariant()
        $rule = ([string]$row.processingRule).Trim()
        foreach ($field in @($text,$pinyin,$tier,$category,$sourceId,$updatedAt,$domain,$layer,$rule)) {
            if ($field.Length -gt $maxFieldChars) { throw "line $($stats.inputRows + 1) exceeds field hard limit" }
            $abnormalCharacters = @($field.ToCharArray() | Where-Object { [char]::IsControl($_) -or [char]::GetUnicodeCategory($_) -eq [Globalization.UnicodeCategory]::Format })
            if ($field.IndexOf([char]0xFFFD) -ge 0 -or $abnormalCharacters.Count -gt 0) {
                throw "line $($stats.inputRows + 1) contains abnormal Unicode"
            }
        }
        if (-not $text -or -not $pinyin -or -not $category -or -not $sourceId -or -not $rule) { throw "line $($stats.inputRows + 1) has an empty required field" }
        if (-not $licensedIds.Contains($sourceId)) { throw "line $($stats.inputRows + 1) uses unlicensed sourceId $sourceId" }
        if (-not $frequencyByLayer.ContainsKey($layer) -or -not $frequencyByLayer[$layer].ContainsKey($tier)) { throw "line $($stats.inputRows + 1) has invalid layer/tier $layer/$tier" }
        if ($layer -eq 'domain' -and $domain -notin $domains) { throw "line $($stats.inputRows + 1) has invalid domain $domain" }
        if ($layer -ne 'domain' -and $domain) { throw "line $($stats.inputRows + 1) sets domain outside domain layer" }
        if ($layer -eq 'hot' -and -not $expiresAt) { throw "line $($stats.inputRows + 1) hotword lacks expiresAt" }
        [void](Read-Date $updatedAt 'updatedAt' ($stats.inputRows + 1))
        if ($expiresAt) {
            $expiry = Read-Date $expiresAt 'expiresAt' ($stats.inputRows + 1)
            if ($expiry -lt $asOf) { $stats.expired++; continue }
        }
        if ($text.Length -gt $maxTextChars) { throw "line $($stats.inputRows + 1) text exceeds $maxTextChars characters" }
        foreach ($character in $text.ToCharArray()) {
            if ([int]$character -lt 0x4E00 -or [int]$character -gt 0x9FFF) { throw "line $($stats.inputRows + 1) has unsupported text character" }
        }
        foreach ($term in $blocked) {
            if ($text.Contains($term)) { $stats.filtered++; throw "line $($stats.inputRows + 1) rejected by safety policy" }
        }
        $syllables = @($pinyin -split ' ')
        if ($syllables.Count -gt $maxSyllables -or $syllables.Count -ne $text.Length) { throw "line $($stats.inputRows + 1) text/syllable count mismatch" }
        foreach ($syllable in $syllables) { if (-not $validSyllables.Contains($syllable)) { throw "line $($stats.inputRows + 1) invalid pinyin syllable: $syllable" } }
        $key = Get-Key $text $pinyin
        if ($existingKeys.Contains($key)) { $stats.inheritedDuplicates++; continue }
        $accepted.Add([pscustomobject]@{
            key=$key; text=$text; pinyin=$pinyin; frequency=[long]$frequencyByLayer[$layer][$tier]
            tier=$tier; category=$category; sourceId=$sourceId; updatedAt=$updatedAt; expiresAt=$expiresAt
            domain=$domain; layer=$layer; processingRule=$rule
        })
        $stats.acceptedRows++
    }
}

$merged = [ordered]@{}
foreach ($row in $accepted | Sort-Object key, sourceId, category) {
    if (-not $merged.Contains($row.key)) { $merged[$row.key] = $row; continue }
    $stats.mergedDuplicates++
    $current = $merged[$row.key]
    $layerPriority = @{ base=0; hot=1; domain=2 }
    $rowPriority = $layerPriority[$row.layer]
    $currentPriority = $layerPriority[$current.layer]
    if ($rowPriority -lt $currentPriority -or ($rowPriority -eq $currentPriority -and ($row.frequency -gt $current.frequency -or ($row.frequency -eq $current.frequency -and [string]::CompareOrdinal($row.sourceId, $current.sourceId) -lt 0)))) {
        $merged[$row.key] = $row
    }
}
$accepted = @($merged.Values | Sort-Object pinyin, text, sourceId)

function Write-Normalized([string]$path, [object[]]$rows) {
    $lines = @($rows | ForEach-Object { "$($_.text)`t$($_.pinyin)`t$($_.frequency)`t$($_.sourceId.Replace('-','_'))" })
    [IO.File]::WriteAllLines($path, $lines, $utf8)
}
$baseRows = @($accepted | Where-Object { $_.layer -in @('base','hot') })
$allRows = @($accepted)
$baseSource = Join-Path $artifactRoot 'production-v2-additions.normalized.tsv'
$allSource = Join-Path $artifactRoot 'evaluation-all-domains.normalized.tsv'
Write-Normalized $baseSource $baseRows
Write-Normalized $allSource $allRows

$sourceManifest = [ordered]@{
    schemaVersion='quanpin-v2-source-manifest/1'; asOfDate=$AsOfDate; catalogSha256=(Get-FileHash $catalogPath -Algorithm SHA256).Hash.ToLowerInvariant()
    inheritedSources=@(
        [ordered]@{ path='dictionaries/source/rime-pinyin-simp/pinyin_simp.dict.yaml'; sha256=(Get-FileHash (Join-Path $repoRoot 'dictionaries\source\rime-pinyin-simp\pinyin_simp.dict.yaml') -Algorithm SHA256).Hash.ToLowerInvariant(); license='Apache-2.0' },
        [ordered]@{ path='dictionaries/source/stage11_5_short_sentences.tsv'; sha256=(Get-FileHash $shortSentences -Algorithm SHA256).Hash.ToLowerInvariant(); license='Apache-2.0' }
    )
    v2Sources=@($sourceRecords)
    frequencyTiers=[ordered]@{ base=$frequencyByLayer.base; domain=$frequencyByLayer.domain; hot=$frequencyByLayer.hot }
    hardLimits=[ordered]@{ maxRows=$maxRows; maxTextCharacters=$maxTextChars; maxSyllables=$maxSyllables; maxFieldCharacters=$maxFieldChars; maxFrequency=6000 }
    stats=$stats
}
[IO.File]::WriteAllText((Join-Path $artifactRoot 'source-manifest.json'), ($sourceManifest | ConvertTo-Json -Depth 10), $utf8)
if ($CheckOnly) { Write-Host "QUANPIN_V2_CHECK=PASS accepted=$($accepted.Count) base=$($baseRows.Count)"; exit 0 }

function Invoke-LexiconBuild([string]$additionPath, [string]$outputPath) {
    & cargo run --release --manifest-path $rustManifest -p lexicon-builder -- --input $baseProduction --input $shortSentences --input $additionPath --output $outputPath --lexicon-version 200 --strict --verify
    if ($LASTEXITCODE -ne 0) { throw "lexicon builder failed for $outputPath" }
}

$tempRoot = Join-Path $repoRoot '.quanpin_v2_tmp'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$profiles = [ordered]@{ default=$baseRows; all_domains=$allRows }
foreach ($domainName in $domains) { $profiles[$domainName] = @($baseRows + @($accepted | Where-Object { $_.domain -eq $domainName })) }
$outputs = [Collections.Generic.List[object]]::new()
foreach ($profile in $profiles.Keys) {
    $addition = Join-Path $tempRoot "$profile.tsv"
    Write-Normalized $addition @($profiles[$profile])
    $first = Join-Path $tempRoot "$profile-first.lex"
    $second = Join-Path $tempRoot "$profile-second.lex"
    Invoke-LexiconBuild $addition $first
    Invoke-LexiconBuild $addition $second
    $firstHash = (Get-FileHash $first -Algorithm SHA256).Hash.ToLowerInvariant()
    $secondHash = (Get-FileHash $second -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($firstHash -ne $secondHash -or (Get-Item $first).Length -ne (Get-Item $second).Length) { throw "non-deterministic binary for profile $profile" }
    $destination = Join-Path $generatedRoot "$profile.lex"
    Copy-Item -LiteralPath $first -Destination $destination -Force
    [object[]]$enabledDomains = if ($profile -eq 'default') { @() } elseif ($profile -eq 'all_domains') { @($domains) } else { @($profile) }
    $outputs.Add([ordered]@{ profile=$profile; enabledDomains=$enabledDomains; entriesAdded=@($profiles[$profile]).Count; bytes=(Get-Item $destination).Length; sha256=$firstHash })
}
Copy-Item -LiteralPath (Join-Path $generatedRoot "$ProductionProfile.lex") -Destination $rawProduction -Force

$categoryCounts = [ordered]@{}
$domainCounts = [ordered]@{}
$layerCounts = [ordered]@{}
foreach ($row in $accepted) {
    if (-not $categoryCounts.Contains($row.category)) { $categoryCounts[$row.category] = 0 }; $categoryCounts[$row.category]++
    if ($row.domain) { if (-not $domainCounts.Contains($row.domain)) { $domainCounts[$row.domain] = 0 }; $domainCounts[$row.domain]++ }
    if (-not $layerCounts.Contains($row.layer)) { $layerCounts[$row.layer] = 0 }; $layerCounts[$row.layer]++
}
$buildManifest = [ordered]@{
    schemaVersion='quanpin-v2-build-manifest/1'; lexiconVersion=200; builderVersion=1; asOfDate=$AsOfDate
    sourceManifestSha256=(Get-FileHash (Join-Path $artifactRoot 'source-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    deterministic=$true; repetitions=2; defaultDomainsEnabled=@(); packagedProductionProfile=$ProductionProfile; activeHotwordPolicy='expiresAt >= asOfDate'
    mergePolicy='existing text+pinyin wins; V2 conflicts prefer base then active hot then domain, then maximum tier frequency, then lexicographically smallest sourceId; stable pinyin/text/source sort'
    categoryCounts=$categoryCounts; domainCounts=$domainCounts; layerCounts=$layerCounts; outputs=@($outputs)
}
[IO.File]::WriteAllText((Join-Path $artifactRoot 'build-manifest.json'), ($buildManifest | ConvertTo-Json -Depth 10), $utf8)
Write-Host "QUANPIN_V2_BUILD=PASS added=$($accepted.Count) default=$($baseRows.Count) productionProfile=$ProductionProfile production=$rawProduction"
