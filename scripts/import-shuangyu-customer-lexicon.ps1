param(
    [string]$ProjectRoot = '',
    [string]$ReceivedDirectory = '',
    [string]$CleanedDirectory = '',
    [switch]$UpdateProject
)

$ErrorActionPreference = 'Stop'
$projectPath = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
} else {
    [IO.Path]::GetFullPath($ProjectRoot)
}
$receivedPath = if ([string]::IsNullOrWhiteSpace($ReceivedDirectory)) {
    Join-Path $projectPath '双羽词库分类\双羽词库'
} else {
    [IO.Path]::GetFullPath($ReceivedDirectory)
}
$cleanedPath = if ([string]::IsNullOrWhiteSpace($CleanedDirectory)) {
    Join-Path (Split-Path -Parent $receivedPath) '清理后'
} else {
    [IO.Path]::GetFullPath($CleanedDirectory)
}
$formalSourcePath = Join-Path $projectPath '小鹤音形'
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Read-Utf8Lines([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required customer file: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    try {
        $text = $strictUtf8.GetString($bytes)
    } catch {
        throw "Customer file is not valid UTF-8: $Path"
    }
    return @($text -split "\r\n|\n|\r")
}

function Read-CustomerFile([string]$Name) {
    return @(Read-Utf8Lines (Join-Path $receivedPath $Name))
}

function Get-DataRows([string[]]$Lines, [string]$Name) {
    $rows = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('##')) {
            continue
        }
        $fields = $line.Split("`t")
        if ($fields.Count -ne 2 -or $fields[0].Length -eq 0 -or $fields[1].Length -eq 0) {
            throw "$Name line $($index + 1) must contain exactly one Tab and two non-empty fields"
        }
        $rows.Add($line)
    }
    return @($rows)
}

function Assert-Codes([string[]]$Rows, [string]$Name, [string]$Pattern) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $fields = $Rows[$index].Split("`t")
        if ($fields[1] -cnotmatch $Pattern) {
            throw "$Name data row $($index + 1) has an invalid code: $($fields[1])"
        }
        if (-not $seen.Add($Rows[$index])) {
            throw "$Name contains a duplicate row: $($Rows[$index])"
        }
    }
}

function Get-SectionRows(
    [string[]]$Lines,
    [string]$StartHeading,
    [string]$EndHeading,
    [string]$Name
) {
    $start = -1
    $end = $Lines.Count
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -ceq $StartHeading) {
            $start = $index + 1
            continue
        }
        if ($start -ge 0 -and $Lines[$index] -ceq $EndHeading) {
            $end = $index
            break
        }
    }
    if ($start -lt 0) {
        throw "$Name is missing section heading: $StartHeading"
    }
    return @(Get-DataRows $Lines[$start..($end - 1)] $Name)
}

function Write-Utf8Lf([string]$Path, [string[]]$Lines, [switch]$NoFinalNewline) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $text = $Lines -join "`n"
    if (-not $NoFinalNewline -and $Lines.Count -gt 0) {
        $text += "`n"
    }
    [IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

if (-not (Test-Path -LiteralPath $receivedPath -PathType Container)) {
    throw "Customer directory does not exist: $receivedPath"
}
if (-not (Test-Path -LiteralPath $formalSourcePath -PathType Container)) {
    throw "Formal source directory does not exist: $formalSourcePath"
}

$required = @(
    '1.首选.txt',
    '2.分类.txt',
    '3.一简次选.txt',
    '4.二简次选.txt',
    '5.直通.txt',
    '6.用户.txt',
    '7.符号.txt',
    '8.全码词.txt',
    '9.生僻字.txt',
    '10.全码字.txt',
    '11.快符.txt',
    '12.ok拼字.txt'
)
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $receivedPath $name) -PathType Leaf)) {
        throw "Missing required customer file: $name"
    }
}

$coreRows = @(Get-DataRows (Read-CustomerFile '1.首选.txt') '1.首选.txt')
$categoryLines = @(Read-CustomerFile '2.分类.txt')
$secondaryRows = @(Get-SectionRows $categoryLines '## 次选字词' '## 随心' '2.分类.txt/次选字词')
$freeRows = @(Get-SectionRows $categoryLines '## 随心' '__END__' '2.分类.txt/随心')
$oneKeyRows = @(Get-DataRows (Read-CustomerFile '3.一简次选.txt') '3.一简次选.txt')
$twoKeyRows = @(Get-DataRows (Read-CustomerFile '4.二简次选.txt') '4.二简次选.txt')
$directRows = @(Get-DataRows (Read-CustomerFile '5.直通.txt') '5.直通.txt')
$userRows = @(Get-DataRows (Read-CustomerFile '6.用户.txt') '6.用户.txt')
$symbolLines = @(Read-CustomerFile '7.符号.txt')
$fullCodeWordRows = @(Get-DataRows (Read-CustomerFile '8.全码词.txt') '8.全码词.txt')
$rareRows = @(Get-DataRows (Read-CustomerFile '9.生僻字.txt') '9.生僻字.txt')
$fullCodeCharacterRows = @(Get-DataRows (Read-CustomerFile '10.全码字.txt') '10.全码字.txt')
$quickRows = @(Get-DataRows (Read-CustomerFile '11.快符.txt') '11.快符.txt')
$spellingRows = @(Get-DataRows (Read-CustomerFile '12.ok拼字.txt') '12.ok拼字.txt')
$existingOutOfTableRows = @(Get-DataRows (Read-Utf8Lines (Join-Path $formalSourcePath '2.4.表外字.txt')) '小鹤音形/2.4.表外字.txt')

$symbolGroupHeading = '## of引导的符号'
$symbolGroupHeadingIndex = [Array]::IndexOf($symbolLines, $symbolGroupHeading)
if ($symbolGroupHeadingIndex -lt 0) {
    throw "7.符号.txt is missing section heading: $symbolGroupHeading"
}
$symbolRows = @(Get-DataRows $symbolLines[0..($symbolGroupHeadingIndex - 1)] '7.符号.txt/符号')
$symbolGroupExternalRows = [Collections.Generic.List[string]]::new()
$allowedMetadata = [Collections.Generic.HashSet[string]]::new(
    [string[]]@("----syntax=cn, code", "----leadkey='", '----config=ime-yd.ini'),
    [StringComparer]::Ordinal
)
for ($index = $symbolGroupHeadingIndex + 1; $index -lt $symbolLines.Count; $index++) {
    $line = $symbolLines[$index]
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('##')) {
        continue
    }
    if ($allowedMetadata.Contains($line)) {
        continue
    }
    $fields = $line.Split("`t")
    if ($fields.Count -ne 2 -or $fields[0].Length -eq 0 -or $fields[1].Length -eq 0) {
        throw "7.符号.txt line $($index + 1) is neither a valid row nor approved legacy metadata"
    }
    $symbolGroupExternalRows.Add($line)
}
$symbolGroupRows = [Collections.Generic.List[string]]::new()
foreach ($row in $symbolGroupExternalRows) {
    $fields = $row.Split("`t")
    if (-not $fields[1].StartsWith('o')) {
        throw "7.符号.txt symbol-group code must start with external o prefix: $($fields[1])"
    }
    $symbolGroupRows.Add($fields[0] + "`t" + $fields[1].Substring(1))
}

$generalCodePattern = '^[a-z]+(?:#(?:固|直|删|[1-9][0-9]*))?$'
Assert-Codes $coreRows '1.首选.txt' $generalCodePattern
Assert-Codes $secondaryRows '2.分类.txt/次选字词' $generalCodePattern
Assert-Codes $freeRows '2.分类.txt/随心' $generalCodePattern
Assert-Codes $existingOutOfTableRows '小鹤音形/2.4.表外字.txt' $generalCodePattern
Assert-Codes $oneKeyRows '3.一简次选.txt' $generalCodePattern
Assert-Codes $twoKeyRows '4.二简次选.txt' $generalCodePattern
Assert-Codes $directRows '5.直通.txt' '^[a-z]+$'
Assert-Codes $userRows '6.用户.txt' $generalCodePattern
Assert-Codes $symbolRows '7.符号.txt/符号' '^[a-z]+$'
Assert-Codes @($symbolGroupRows) '7.符号.txt/符号组' '^[a-z]+$'
Assert-Codes $fullCodeWordRows '8.全码词.txt' $generalCodePattern
Assert-Codes $rareRows '9.生僻字.txt' $generalCodePattern
Assert-Codes $fullCodeCharacterRows '10.全码字.txt' $generalCodePattern
Assert-Codes $quickRows '11.快符.txt' '^(?:;|[a-z]+)$'
Assert-Codes $spellingRows '12.ok拼字.txt' '^ok(?:[a-z]{4}|[a-z]{6})$'

$markedDirectRows = [Collections.Generic.List[string]]::new()
foreach ($row in $directRows) {
    $fields = $row.Split("`t")
    $markedDirectRows.Add($fields[0] + "`t" + $fields[1] + '#直')
}
$mergedFullCodeRows = @($fullCodeWordRows) + @($markedDirectRows)
Assert-Codes $mergedFullCodeRows '8.全码词.txt（含直通）' $generalCodePattern

$cleanedFiles = [ordered]@{
    '1.首选.txt' = @('## 首选') + $coreRows
    '2.分类.txt' = @('## 分类', '## 次选字词') + $secondaryRows + @('', '## 表外字') + $existingOutOfTableRows + @('', '## 随心') + $freeRows
    '3.一简次选.txt' = @('## 一简次选') + $oneKeyRows
    '4.二简次选.txt' = @('## 二简次选') + $twoKeyRows
    '6.用户.txt' = @($userRows)
    '7.符号.txt' = @('## 符号') + $symbolRows + @('', '## 符号组') + @($symbolGroupExternalRows)
    '8.全码词.txt' = @('## 全码词') + $fullCodeWordRows + @('', '## 直通（已并入全码词）') + @($markedDirectRows)
    '9.生僻字.txt' = @('## 生僻字') + $rareRows
    '10.全码字.txt' = @('## 全码字') + $fullCodeCharacterRows
    '11.快符.txt' = @('## 快符（分号引导，编码不含入口分号）') + $quickRows
    '12.ok拼字.txt' = @('## ok拼字') + $spellingRows
}

$formalFiles = [ordered]@{
    '0.0.小鹤.txt' = @('## 首选') + $coreRows
    '0.2.拼字.txt' = @('## ok拼字') + $spellingRows
    '1.0.分类.txt' = @('## 次选字词') + $secondaryRows + @('', '## 随心') + $freeRows
    '1.2.快符-外接.txt' = @('## 快符（分号引导，编码不含入口分号）') + $quickRows
    '2.1.一简次选.txt' = @('## 一简次选') + $oneKeyRows
    '2.2.二简次选.txt' = @('## 二简次选') + $twoKeyRows
    '2.4.表外字.txt' = @('## 表外字（客户本次未提交，沿用项目现有内容）') + $existingOutOfTableRows
    '2.5.全码词.txt' = @('## 全码词') + $fullCodeWordRows + @('', '## 直通') + @($markedDirectRows)
    '2.6.符号.txt' = @('## 符号') + $symbolRows
    '2.7.符号组.txt' = @('## 符号组（构建时添加 o 前缀）') + @($symbolGroupRows)
    '2.8.生僻字.txt' = @('## 生僻字') + $rareRows
    '2.9.全码字.txt' = @('## 全码字') + $fullCodeCharacterRows
}

foreach ($entry in $cleanedFiles.GetEnumerator()) {
    Write-Utf8Lf (Join-Path $cleanedPath $entry.Key) @($entry.Value)
}

$report = @(
    '# 双羽客户词库清理说明',
    '',
    '- 客户原始回传目录保持不变。',
    '- 所有输出统一为 UTF-8（无 BOM）、LF、Tab 分隔。',
    '- `5.直通.txt` 的 44 条记录已添加 `#直` 并并入 `8.全码词.txt`，不再单独输出。',
    '- `7.符号.txt` 的 3 行旧平台元数据已移除，内容按“符号/符号组”重新分节。',
    '- 客户未提交“表外字”；为避免误删，清理稿沿用项目现有表外字。',
    '- `6.用户.txt` 没有实际记录，清理稿保留为空文件。',
    '',
    '## 数据记录数',
    '',
    "- 首选：$($coreRows.Count)",
    "- 分类（次选/随心）：$($secondaryRows.Count + $freeRows.Count)",
    "- 表外字（沿用）：$($existingOutOfTableRows.Count)",
    "- 一简次选：$($oneKeyRows.Count)",
    "- 二简次选：$($twoKeyRows.Count)",
    "- 符号：$($symbolRows.Count)",
    "- 符号组：$($symbolGroupExternalRows.Count)",
    "- 全码词：$($fullCodeWordRows.Count)",
    "- 直通：$($markedDirectRows.Count)",
    "- 生僻字：$($rareRows.Count)",
    "- 全码字：$($fullCodeCharacterRows.Count)",
    "- 快符：$($quickRows.Count)",
    "- ok拼字：$($spellingRows.Count)"
)
Write-Utf8Lf (Join-Path $cleanedPath '清理说明.md') $report

if ($UpdateProject) {
    foreach ($entry in $formalFiles.GetEnumerator()) {
        Write-Utf8Lf (Join-Path $formalSourcePath $entry.Key) @($entry.Value)
    }
}

Write-Host 'SHUANGYU_CUSTOMER_LEXICON_IMPORT=PASS'
Write-Host "RECEIVED=$receivedPath"
Write-Host "CLEANED=$cleanedPath"
Write-Host "UPDATE_PROJECT=$($UpdateProject.IsPresent)"
Write-Host "CUSTOMER_RECORDS=$($coreRows.Count + $secondaryRows.Count + $freeRows.Count + $oneKeyRows.Count + $twoKeyRows.Count + $directRows.Count + $userRows.Count + $symbolRows.Count + $symbolGroupExternalRows.Count + $fullCodeWordRows.Count + $rareRows.Count + $fullCodeCharacterRows.Count + $quickRows.Count + $spellingRows.Count)"
Write-Host "PRESERVED_OUT_OF_TABLE_RECORDS=$($existingOutOfTableRows.Count)"
