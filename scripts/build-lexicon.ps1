param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'dictionaries\source\rime-pinyin-simp\pinyin_simp.dict.yaml'
$shortSentenceSource = Join-Path $repoRoot 'dictionaries\source\stage11_5_short_sentences.tsv'
$manifestPath = Join-Path $repoRoot 'dictionaries\manifest.json'
$licensePath = Join-Path $repoRoot 'dictionaries\LICENSES\rime-pinyin-simp-Apache-2.0.txt'
$generatedDir = Join-Path $repoRoot 'dictionaries\generated'
$normalized = Join-Path $generatedDir 'production.normalized.tsv'
$output = Join-Path $generatedDir 'production.lex'
$rawfile = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$evidenceDir = Join-Path $repoRoot 'docs\evidence\stage11_5'
$corpusDir = Join-Path $repoRoot 'engine-rust\tests\fixtures\production_corpus'
$tempDir = Join-Path $repoRoot '.stage11_5_tmp'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

foreach ($directory in @($generatedDir, (Split-Path $rawfile), $evidenceDir, $corpusDir, $tempDir)) {
    New-Item -ItemType Directory -Force $directory | Out-Null
}
foreach ($required in @($source, $shortSentenceSource, $manifestPath, $licensePath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "required lexicon input missing: $required" }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceRecord = $manifest.sources | Where-Object { $_.sourceId -eq 'rime-pinyin-simp' }
if ($null -eq $sourceRecord -or -not $sourceRecord.redistributionAllowed) { throw 'licensed source manifest is missing or forbids redistribution' }
$actualSourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
if ($actualSourceHash -ne $sourceRecord.sourceChecksum) {
    throw "source checksum mismatch: expected $($sourceRecord.sourceChecksum), actual $actualSourceHash"
}
$shortSentenceRecord = $manifest.sources | Where-Object { $_.sourceId -eq 'project-stage11-5-short-sentences' }
if ($null -eq $shortSentenceRecord -or -not $shortSentenceRecord.redistributionAllowed) { throw 'short sentence source manifest is missing or forbids redistribution' }
$actualShortSentenceHash = (Get-FileHash -LiteralPath $shortSentenceSource -Algorithm SHA256).Hash
if ($actualShortSentenceHash -ne $shortSentenceRecord.sourceChecksum) {
    throw "short sentence checksum mismatch: expected $($shortSentenceRecord.sourceChecksum), actual $actualShortSentenceHash"
}
$shortSentenceCount = @(
    [IO.File]::ReadLines($shortSentenceSource, [Text.Encoding]::UTF8) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') }
).Count
if ($shortSentenceCount -ne $shortSentenceRecord.entryCount) {
    throw "short sentence entry count mismatch: expected $($shortSentenceRecord.entryCount), actual $shortSentenceCount"
}

$inventoryText = Get-Content -LiteralPath (Join-Path $repoRoot 'engine-rust\crates\pinyin-syllable\src\inventory.rs') -Raw -Encoding UTF8
$inventoryMatch = [regex]::Match($inventoryText, 'const VALID_SYLLABLES: &str = "(?s)(.*?)";')
if (-not $inventoryMatch.Success) { throw 'cannot read the engine pinyin inventory' }
$validSyllables = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$inventoryMatch.Groups[1].Value -split '\s+' | Where-Object { $_ } | ForEach-Object { [void]$validSyllables.Add($_) }

$accepted = [Collections.Generic.List[string]]::new()
$acceptedRecords = [Collections.Generic.List[object]]::new()
$rejected = [Collections.Generic.List[object]]::new()
$inBody = $false
$lineNumber = 0
foreach ($line in [IO.File]::ReadLines($source, [Text.Encoding]::UTF8)) {
    $lineNumber++
    if ($line -eq '...') { $inBody = $true; continue }
    if (-not $inBody -or [string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    $fields = $line -split "`t"
    if ($fields.Count -lt 2) {
        $rejected.Add([ordered]@{ line=$lineNumber; word=''; pinyin=''; errorType='field_count'; reason='expected at least word and pinyin' })
        continue
    }
    $word = $fields[0].Trim()
    $pinyinParts = @($fields[1].Trim().ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    for ($i = 0; $i -lt $pinyinParts.Count; $i++) {
        if ($pinyinParts[$i] -eq 'lue') { $pinyinParts[$i] = 'lve' }
        if ($pinyinParts[$i] -eq 'nue') { $pinyinParts[$i] = 'nve' }
    }
    $pinyin = $pinyinParts -join ' '
    $weight = 0L
    if ($fields.Count -ge 3 -and -not [long]::TryParse($fields[2].Trim(), [ref]$weight)) {
        $rejected.Add([ordered]@{ line=$lineNumber; word=$word; pinyin=$pinyin; errorType='frequency'; reason='weight is not an integer' })
        continue
    }
    $badCharacter = $null
    foreach ($character in $word.ToCharArray()) {
        if ([int]$character -lt 0x4E00 -or [int]$character -gt 0x9FFF) { $badCharacter = $character; break }
    }
    $badSyllable = $null
    foreach ($syllable in $pinyinParts) {
        if (-not $validSyllables.Contains($syllable)) { $badSyllable = $syllable; break }
    }
    $reason = $null
    $errorType = $null
    if ([string]::IsNullOrWhiteSpace($word)) { $errorType='empty_word'; $reason='word is empty' }
    elseif ($null -ne $badCharacter) { $errorType='unsupported_character'; $reason="non-BMP-common-CJK character: $badCharacter" }
    elseif ($word.Length -ne $pinyinParts.Count) { $errorType='syllable_count'; $reason="word length $($word.Length), syllables $($pinyinParts.Count)" }
    elseif ($null -ne $badSyllable) { $errorType='invalid_syllable'; $reason="unsupported syllable: $badSyllable" }
    if ($null -ne $reason) {
        $rejected.Add([ordered]@{ line=$lineNumber; word=$word; pinyin=$pinyin; errorType=$errorType; reason=$reason })
        continue
    }
    $frequency = [Math]::Min(1000000L, [Math]::Max(1L, $weight + 1L))
    $accepted.Add("$word`t$pinyin`t$frequency`trime_pinyin_simp")
    $acceptedRecords.Add([pscustomobject]@{ word=$word; pinyin=$pinyin; frequency=$frequency })
}
if ($accepted.Count -lt 3000) { throw "production source produced too few valid rows: $($accepted.Count)" }
[IO.File]::WriteAllLines($normalized, $accepted, $utf8NoBom)
$rejected | ConvertTo-Json -Depth 4 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $evidenceDir 'lexicon_rejections.json'), $_, $utf8NoBom) }

if ($Check) {
    Write-Host "LEXICON_CHECK=PASS accepted=$($accepted.Count) rejected=$($rejected.Count)"
    exit 0
}

$first = Join-Path $tempDir 'production-first.lex'
$second = Join-Path $tempDir 'production-second.lex'
Push-Location $repoRoot
try {
    & cargo run --manifest-path engine-rust\Cargo.toml -p lexicon-builder -- --input $normalized --input $shortSentenceSource --output $first --lexicon-version 115 --strict --verify
    if ($LASTEXITCODE -ne 0) { throw "first lexicon build failed: $LASTEXITCODE" }
    & cargo run --manifest-path engine-rust\Cargo.toml -p lexicon-builder -- --input $normalized --input $shortSentenceSource --output $second --lexicon-version 115 --strict --verify
    if ($LASTEXITCODE -ne 0) { throw "second lexicon build failed: $LASTEXITCODE" }
} finally { Pop-Location }
$firstHash = (Get-FileHash $first -Algorithm SHA256).Hash
$secondHash = (Get-FileHash $second -Algorithm SHA256).Hash
if ((Get-Item $first).Length -ne (Get-Item $second).Length -or $firstHash -ne $secondHash) { throw 'lexicon build is not byte deterministic' }
Copy-Item -LiteralPath $first -Destination $output -Force
Copy-Item -LiteralPath $first -Destination $rawfile -Force

$schema = Get-Content -LiteralPath (Join-Path $repoRoot 'engine-rust\schemas\xiaohe.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$initialKeys = @{}; foreach ($item in @($schema.ordinary_initials) + @($schema.double_initials)) { $initialKeys[$item.value] = $item.key }
$finalKeys = @{}; foreach ($item in $schema.finals) { foreach ($value in $item.values) { $finalKeys[$value] = $item.key } }
$special = @{}; foreach ($item in $schema.special_syllables) { $special[$item.syllable] = $item.code }
function Convert-SyllableToXiaohe([string]$syllable) {
    if ($syllable -in @('n','ng')) { return $null }
    if ($special.ContainsKey($syllable)) { return $special[$syllable] }
    $initial = ''; foreach ($candidate in @('zh','ch','sh')) { if ($syllable.StartsWith($candidate)) { $initial=$candidate; break } }
    if (-not $initial -and $syllable.Length -gt 1 -and $initialKeys.ContainsKey($syllable.Substring(0,1))) { $initial=$syllable.Substring(0,1) }
    $final = $syllable.Substring($initial.Length)
    if (-not $initial) {
        if ($syllable.Length -eq 1) { return $syllable + $syllable }
        if ($syllable -in @('ai','an','ao','ei','en','er','ou')) { return $syllable }
        if ($finalKeys.ContainsKey($syllable)) { return $syllable.Substring(0,1) + $finalKeys[$syllable] }
        return $null
    }
    if (-not $finalKeys.ContainsKey($final)) { return $null }
    return $initialKeys[$initial] + $finalKeys[$final]
}

$bestByReading = @{}
foreach ($record in $acceptedRecords) {
    if (-not $bestByReading.ContainsKey($record.pinyin) -or $record.frequency -gt $bestByReading[$record.pinyin].frequency -or ($record.frequency -eq $bestByReading[$record.pinyin].frequency -and [string]::CompareOrdinal($record.word, $bestByReading[$record.pinyin].word) -lt 0)) {
        $bestByReading[$record.pinyin] = $record
    }
}
$cases = [Collections.Generic.List[string]]::new()
$caseId = 0
$uniqueShuangpinCodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($record in $bestByReading.Values | Sort-Object @{Expression='frequency';Descending=$true}, pinyin, word) {
    $codes = @(); $encodable = $true
    foreach ($syllable in $record.pinyin -split ' ') { $code = Convert-SyllableToXiaohe $syllable; if (-not $code) { $encodable=$false; break }; $codes += $code }
    if (-not $encodable) { continue }
    [void]$uniqueShuangpinCodes.Add($codes -join '')
    if ($cases.Count -ge 5000) { continue }
    $caseId++
    $category = switch ($record.word.Length) { 1 {'single'} 2 {'double'} 3 {'multi'} 4 {'four_char'} default {'phrase'} }
    $cases.Add((@("auto-$('{0:D5}' -f $caseId)",$category,($codes -join ''),$record.pinyin,$record.word,$record.word,'',9,'generated coverage case; highest-frequency target must rank first') -join "`t"))
}
$corpusHeader = "caseId`tcategory`trawShuangpinInput`texpectedSyllables`texpectedTopCandidate`tallowedCandidates`tforbiddenCandidates`tmaxExpectedRank`tnotes"
[IO.File]::WriteAllLines((Join-Path $corpusDir 'auto_generated.tsv'), @($corpusHeader) + $cases, $utf8NoBom)

$recordsByWord = @{}
foreach ($record in $acceptedRecords) {
    if (-not $recordsByWord.ContainsKey($record.word) -or $record.frequency -gt $recordsByWord[$record.word].frequency) {
        $recordsByWord[$record.word] = $record
    }
}
$idiomWords = @(
    '一心一意','一帆风顺','一举两得','一见钟情','一目了然','一模一样','一事无成','一言为定','一针见血','一知半解',
    '三心二意','三言两语','四面八方','四通八达','五湖四海','五花八门','六神无主','七上八下','七嘴八舌','八面玲珑',
    '九牛一毛','十全十美','百发百中','百花齐放','百里挑一','百年不遇','千变万化','千方百计','千军万马','千言万语',
    '万水千山','万众一心','大吃一惊','大同小异','大显身手','大有可为','不约而同','不知不觉','不言而喻','不可思议',
    '不由自主','不折不扣','不慌不忙','不闻不问','东张西望','东山再起','乐在其中','人山人海','人来人往','人尽其才',
    '今非昔比','从容不迫','众所周知','全力以赴','全心全意','兴高采烈','再接再厉','出人意料','半途而废','名不虚传',
    '喜出望外','因地制宜','坚持不懈','天长地久','天翻地覆','如愿以偿','实事求是','小心翼翼','心安理得','心平气和',
    '心满意足','恍然大悟','情不自禁','意味深长','无忧无虑','无能为力','无边无际','日新月异','明明白白','有声有色',
    '有始有终','来之不易','欣欣向荣','津津有味','海阔天空','理所当然','生机勃勃','画蛇添足','目不转睛','相辅相成',
    '知己知彼','神采奕奕','自言自语','自相矛盾','自由自在','若有所思','迫不及待','错综复杂','随心所欲','难以置信',
    '风平浪静','高高兴兴','默默无闻'
)
$idiomCases = [Collections.Generic.List[string]]::new()
foreach ($word in $idiomWords) {
    if (-not $recordsByWord.ContainsKey($word)) { continue }
    $record = $recordsByWord[$word]
    $codes = @(); $encodable = $true
    foreach ($syllable in $record.pinyin -split ' ') { $code = Convert-SyllableToXiaohe $syllable; if (-not $code) { $encodable=$false; break }; $codes += $code }
    if (-not $encodable) { continue }
    $idiomCases.Add((@("idiom-$('{0:D3}' -f ($idiomCases.Count + 1))",'idiom',($codes -join ''),$record.pinyin,'',$word,'',9,'human-curated common idiom present in the licensed production source') -join "`t"))
}
if ($idiomCases.Count -lt 70) { throw "too few curated idioms found in production source: $($idiomCases.Count)" }
[IO.File]::WriteAllLines((Join-Path $corpusDir 'human_idioms.tsv'), @($corpusHeader) + $idiomCases, $utf8NoBom)

$shortSentenceCases = @(
    "sentence-001`tshort_sentence`tnihc`tni hao`t你好`t你好`t`t9`tcommon greeting",
    "sentence-002`tshort_sentence`txpxp`txie xie`t谢谢`t谢谢`t`t9`tcommon thanks",
    "sentence-003`tshort_sentence`tbuyskeqi`tbu yong ke qi`t不用客气`t不用客气`t`t9`tcommon polite reply",
    "sentence-004`tshort_sentence`tjbtmtmqibuco`tjin tian tian qi bu cuo`t今天天气不错`t今天天气不错`t`t9`tdecoder composition from licensed entries",
    "sentence-005`tshort_sentence`twomfmktmjm`two men ming tian jian`t我们明天见`t我们明天见`t`t9`tdecoder composition from licensed entries",
    "sentence-006`tshort_sentence`twovgzduiysuurufa`two zheng zai shi yong shu ru fa`t我正在使用输入法`t我正在使用输入法`t`t9`tdecoder composition from licensed entries",
    "sentence-007`tshort_sentence`tvegegsngyijkwjig`tzhe ge gong neng yi jing wan cheng`t这个功能已经完成`t这个功能已经完成`t`t9`tdecoder composition from licensed entries",
    "sentence-008`tshort_sentence`tqkbhwokjyixx`tqing bang wo kan yi xia`t请帮我看一下`t请帮我看一下`t`t9`tdecoder composition from licensed entries",
    "sentence-009`tshort_sentence`tuchzhvfuni`tshao hou hui fu ni`t稍后回复你`t稍后回复你`t`t9`tdecoder composition from licensed entries",
    "sentence-010`tshort_sentence`tvzmoyiqiiifj`tzhou mo yi qi chi fan`t周末一起吃饭`t周末一起吃饭`t`t9`tdecoder composition from licensed entries"
)
[IO.File]::WriteAllLines((Join-Path $corpusDir 'human_short_sentences.tsv'), @($corpusHeader) + $shortSentenceCases, $utf8NoBom)

$safetyCases = [Collections.Generic.List[string]]::new()
foreach ($key in 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()) {
    $safetyCases.Add((@("incomplete-$key",'incomplete',[string]$key,'','','','',0,'single-key incomplete input must remain safe') -join "`t"))
}
$illegalInputs = @('1','2','0','@','#','$','%','&','*','-','_','=','+','/',':',';','.',',','?','!','A','Z','a1','ni@','中','é','🙂')
for ($i = 0; $i -lt $illegalInputs.Count; $i++) {
    $safetyCases.Add((@("illegal-$('{0:D3}' -f ($i + 1))",'illegal',$illegalInputs[$i],'','','','',0,'illegal character input must not panic or expose candidates') -join "`t"))
}
[IO.File]::WriteAllLines((Join-Path $corpusDir 'generated_safety.tsv'), @($corpusHeader) + $safetyCases, $utf8NoBom)

$singleCount = 0; $doubleCount = 0; $threeCount = 0; $fourOrMoreCount = 0
$uniqueChars = [Collections.Generic.HashSet[char]]::new(); foreach ($record in $acceptedRecords) { foreach ($ch in $record.word.ToCharArray()) { [void]$uniqueChars.Add($ch) } }
$readingsByWord = @{}
foreach ($record in $acceptedRecords) {
    switch ($record.word.Length) { 1 {$singleCount++} 2 {$doubleCount++} 3 {$threeCount++} default {$fourOrMoreCount++} }
    if (-not $readingsByWord.ContainsKey($record.word)) { $readingsByWord[$record.word] = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal) }
    [void]$readingsByWord[$record.word].Add($record.pinyin)
}
$polyphonic = 0; foreach ($readingSet in $readingsByWord.Values) { if ($readingSet.Count -gt 1) { $polyphonic++ } }
$rejectionCounts = @{}; foreach ($item in $rejected) { $key = [string]$item['errorType']; if (-not $rejectionCounts.ContainsKey($key)) { $rejectionCounts[$key] = 0 }; $rejectionCounts[$key]++ }
$stats = [ordered]@{
    sourceRows=$accepted.Count + $rejected.Count + $shortSentenceCount; acceptedRows=$accepted.Count + $shortSentenceCount; rejectedRows=$rejected.Count
    entryCount=$accepted.Count + $shortSentenceCount; singleCharacter=$singleCount; doubleWord=$doubleCount
    threeCharacter=$threeCount; fourOrMore=$fourOrMoreCount + $shortSentenceCount; shortSentenceEntries=$shortSentenceCount
    uniqueCharacters=$uniqueChars.Count; polyphonicWords=$polyphonic; uniquePinyinSequences=$bestByReading.Count + $shortSentenceCount; uniqueShuangpinCodes=$uniqueShuangpinCodes.Count + $shortSentenceCount
    regressionCases=$cases.Count + 30 + $idiomCases.Count + $shortSentenceCases.Count + $safetyCases.Count; classifiedIdiomEntries=$idiomCases.Count; idiomCorpusCases=$idiomCases.Count; shortSentenceCorpusCases=$shortSentenceCases.Count; safetyCorpusCases=$safetyCases.Count
    binaryBytes=(Get-Item $output).Length; binarySha256=$firstHash; formatVersion='1.0'; lexiconVersion=115
    sourceSha256=$actualSourceHash; shortSentenceSourceSha256=$actualShortSentenceHash; deterministic=$true; rejectedByReason=@($rejectionCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { [ordered]@{ reason=$_.Name; count=$_.Value } })
}
$stats | ConvertTo-Json -Depth 6 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $evidenceDir 'lexicon_statistics.json'), $_, $utf8NoBom) }
Write-Host "LEXICON_BUILD=PASS entries=$($accepted.Count + $shortSentenceCount) rejected=$($rejected.Count) bytes=$($stats.binaryBytes) sha256=$firstHash corpus=$($stats.regressionCases)"
