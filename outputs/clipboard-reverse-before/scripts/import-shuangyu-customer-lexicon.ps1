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

function Read-OptionalCustomerFile([string]$Name) {
    $path = Join-Path $receivedPath $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }
    return @(Read-Utf8Lines $path)
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

function Convert-DirectActionRows([string[]]$Rows) {
    $records = [Collections.Generic.List[object]]::new()
    $rejected = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $fields = $Rows[$index].Split("`t")
        $syntax = $fields[0]
        $code = $fields[1]
        $label = $syntax
        $operation = $syntax
        if ($syntax.StartsWith('$cmd(') -and $syntax.EndsWith(')')) {
            $inner = $syntax.Substring(5, $syntax.Length - 6)
            $split = $inner.LastIndexOf(',')
            if ($split -lt 1 -or $split -ge $inner.Length - 1) {
                $rejected.Add([ordered]@{ sourceOrder = $index; code = $code; reason = 'UNPARSEABLE_COMMAND' })
                continue
            }
            # Only remove ASCII separator whitespace. Ideographic spaces can
            # be intentional committed text (for example the poem entry).
            $operation = $inner.Substring(0, $split).Trim([char[]]@(' ', "`t"))
            $label = $inner.Substring($split + 1).Trim()
        }

        $record = [ordered]@{
            id = ('customer-direct-{0:d3}-{1}' -f $index, $code)
            scope = 'DIRECT'
            code = $code
            label = $label
        }
        switch -CaseSensitive ($operation) {
            '{time}:yyyy年M月d日' { $record.type = 'DATE_TIME_TEXT'; $record.formatId = 'DATE_LOCAL_UNPADDED' }
            '{time}:yyyy-MM-dd' { $record.type = 'DATE_TIME_TEXT'; $record.formatId = 'DATE_ISO' }
            '{cttg}:yMdHm' { $record.type = 'DATE_TIME_TEXT'; $record.formatId = 'LUNAR_DATE_FESTIVAL' }
            '{time}:HH:mm ddd' { $record.type = 'DATE_TIME_TEXT'; $record.formatId = 'TIME_WEEKDAY' }
            '{time}:H点m分' { $record.type = 'DATE_TIME_TEXT'; $record.formatId = 'TIME_LOCAL_HM' }
            'run(https://flypy.cc/ix/?q={cursorbefore}{clip})' { $record.type = 'DIRECT_CONTROL'; $record.action = 'url.open'; $record.target = 'flypy-shape' }
            'run(https://flypy.cc)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'url.open'; $record.target = 'flypy-home' }
            'run(https://flypy.cc/help)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'url.open'; $record.target = 'flypy-help' }
            'run(https://flypy.cc/help/#/sj)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'url.open'; $record.target = 'flypy-help-mobile' }
            'show(设置)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'app.open'; $record.target = 'settings' }
            'open($userpath$/小鹤用户词库.txt)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'app.open'; $record.target = 'user-lexicon' }
            'add($userpath$/小鹤用户词库.txt)' { $record.type = 'IMPORT_USER_LEXICON' }
            'set(ime-hans2hant=?)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.traditional'; $record.target = 'toggle' }
            'set(ime-cnuseensymbol=?)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.punctuation'; $record.target = 'toggle' }
            'set(ime-quanjiao=?)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.fullwidth'; $record.target = 'toggle' }
            'deleteline' { $record.type = 'DIRECT_CONTROL'; $record.action = 'editor.delete-line'; $record.target = '' }
            'set(ime-adjustsymboldelay=600)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.smart-period'; $record.target = '600' }
            'set(ime-adjustsymboldelay=0)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.smart-period'; $record.target = '0' }
            'set(ime-numsymbol=.)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.numeric-period'; $record.target = 'enabled' }
            'set(ime-numsymbol=0)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.numeric-period'; $record.target = 'disabled' }
            'set(ime-maxcleancount=4)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.empty-clear'; $record.target = '4'; $record.label = '[四码空码清]' }
            'set(ime-maxcleancount=12)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.empty-clear'; $record.target = '12'; $record.label = '[空码不清]' }
            'set(ime-dinglen=4)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.commit-policy'; $record.target = 'top-screen' }
            'set(ime-dinglen=4;ime-aotu=4)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.commit-policy'; $record.target = 'auto-commit' }
            'set(ime-split=0)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.split-mode'; $record.target = 'traditional' }
            'set(ime-split=1)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.split-mode'; $record.target = 'split' }
            'set(ime-candidate-position=bar)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.candidate-position'; $record.target = 'bar' }
            'set(ime-candidate-position=floating)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.candidate-position'; $record.target = 'floating' }
            'set(ime-keyboard-height=default)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-height'; $record.target = 'default' }
            'set(ime-keyboard-height=increase)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-height'; $record.target = 'increase' }
            'set(ime-keyboard-height=decrease)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-height'; $record.target = 'decrease' }
            'set(ime-keyboard-font=default)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-font'; $record.target = 'default' }
            'set(ime-keyboard-font=increase)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-font'; $record.target = 'increase' }
            'set(ime-keyboard-font=decrease)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-font'; $record.target = 'decrease' }
            'set(ime-candidate-font=default)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.candidate-font'; $record.target = 'default' }
            'set(ime-candidate-font=increase)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.candidate-font'; $record.target = 'increase' }
            'set(ime-candidate-font=decrease)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.candidate-font'; $record.target = 'decrease' }
            'set(ime-floating-font=default)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.floating-font'; $record.target = 'default' }
            'set(ime-floating-font=increase)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.floating-font'; $record.target = 'increase' }
            'set(ime-floating-font=decrease)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.floating-font'; $record.target = 'decrease' }
            'set(ime-keyboard-profile=quanpin-26)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-profile'; $record.target = 'quanpin-26' }
            'set(ime-keyboard-profile=xiaohe-26)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-profile'; $record.target = 'xiaohe-26' }
            'set(ime-keyboard-profile=xiaohe-yinxing-26)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.keyboard-profile'; $record.target = 'xiaohe-yinxing-26' }
            'set(ime-haptic=enabled)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.haptic'; $record.target = 'enabled' }
            'set(ime-haptic=disabled)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.haptic'; $record.target = 'disabled' }
            'set(ime-key-sound=enabled)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.key-sound'; $record.target = 'enabled' }
            'set(ime-key-sound=disabled)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'settings.key-sound'; $record.target = 'disabled' }
            'set(ime-usedassisttype=-全码词-全码字-生僻字)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'category.preset'; $record.target = 'experienced' }
            'set(ime-usedassisttype=+全码词-全码字-生僻字)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'category.preset'; $record.target = 'standard' }
            'set(ime-usedassisttype=+全码词+全码字+生僻字' { $record.type = 'DIRECT_CONTROL'; $record.action = 'category.preset'; $record.target = 'beginner' }
            'set(ime-usedassisttype=+二简次选)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'category.enable'; $record.target = 'two-key-secondary' }
            'set(ime-usedassisttype=-二简次选)' { $record.type = 'DIRECT_CONTROL'; $record.action = 'category.disable'; $record.target = 'two-key-secondary' }
            'https://flypy.cc' { $record.type = 'STATIC_TEXT'; $record.text = $operation }
            default {
                if (($operation.Contains('\r\n') -or $operation.StartsWith('　')) -and
                    -not $operation.Contains('$cmd') -and -not $operation.Contains('$ddcmd')) {
                    $record.type = 'STATIC_TEXT'
                    $record.text = $operation.Replace('\r\n', "`r`n")
                } elseif (-not $syntax.StartsWith('$cmd(') -and -not $syntax.Contains('://') -and
                    -not $syntax.Contains('$cmd') -and -not $syntax.Contains('$ddcmd')) {
                    $record.type = 'STATIC_TEXT'
                    $record.text = $syntax
                } else {
                    $rejected.Add([ordered]@{ sourceOrder = $index; code = $code; reason = 'UNSUPPORTED_OR_UNSAFE_ACTION' })
                    $record = $null
                }
            }
        }
        if ($null -eq $record) {
            continue
        }
        $records.Add([pscustomobject]$record)
    }
    return [pscustomobject]@{ Records = @($records); Rejected = @($rejected) }
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
$directActionRows = @(Get-DataRows (Read-OptionalCustomerFile '5.直通.txt') '5.直通.txt')
$directActionConversion = Convert-DirectActionRows $directActionRows
$userRows = @(Get-DataRows (Read-CustomerFile '6.用户.txt') '6.用户.txt')
$symbolLines = @(Read-CustomerFile '7.符号.txt')
$fullCodeWordRows = @(Get-DataRows (Read-CustomerFile '8.全码词.txt') '8.全码词.txt')
$rareRows = @(Get-DataRows (Read-CustomerFile '9.生僻字.txt') '9.生僻字.txt')
$fullCodeCharacterRows = @(Get-DataRows (Read-CustomerFile '10.全码字.txt') '10.全码字.txt')
$quickRows = @(Get-DataRows (Read-CustomerFile '11.快符.txt') '11.快符.txt')
$receivedQuickRowCount = $quickRows.Count
$spellingRows = @(Get-DataRows (Read-CustomerFile '12.ok拼字.txt') '12.ok拼字.txt')
$existingOutOfTableRows = @(Get-DataRows (Read-Utf8Lines (Join-Path $formalSourcePath '2.4.表外字.txt')) '小鹤音形/2.4.表外字.txt')

# The customer legacy table used `;` for the colon row. In the product table,
# `_` means the bare guide key and `;` means pressing the guide key again.
# Normalize once during import so a later customer refresh cannot regress the
# physical-key behavior fixed from the 0.6.0 feedback.
$normalizedQuickRows = [Collections.Generic.List[string]]::new()
$hasBareGuide = @($quickRows | Where-Object { $_.Split("`t")[1] -ceq '_' }).Count -gt 0
$hasSelfRepeat = @($quickRows | Where-Object {
    $fields = $_.Split("`t")
    $fields[0] -cin @(';', '；') -and $fields[1] -ceq ';'
}).Count -gt 0
foreach ($row in $quickRows) {
    $fields = $row.Split("`t")
    if (-not $hasBareGuide -and $fields[0] -ceq '：' -and $fields[1] -ceq ';') {
        $normalizedQuickRows.Add("：`t_")
    } else {
        $normalizedQuickRows.Add($row)
    }
}
if (-not $hasSelfRepeat) {
    $normalizedQuickRows.Add("；`t;")
}
$quickRows = @($normalizedQuickRows)

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
Assert-Codes $directActionRows '5.直通.txt（直通动作词条）' '^[a-z]+$'
Assert-Codes $userRows '6.用户.txt' $generalCodePattern
Assert-Codes $symbolRows '7.符号.txt/符号' '^[a-z]+$'
Assert-Codes @($symbolGroupRows) '7.符号.txt/符号组' '^[a-z]+$'
Assert-Codes $fullCodeWordRows '8.全码词.txt' $generalCodePattern
Assert-Codes $rareRows '9.生僻字.txt' $generalCodePattern
Assert-Codes $fullCodeCharacterRows '10.全码字.txt' $generalCodePattern
Assert-Codes $quickRows '11.快符.txt' '^(?:_|;|[a-z]+)$'
Assert-Codes $spellingRows '12.ok拼字.txt' '^ok(?:[a-z]{4}|[a-z]{6})$'

$allCategoryRows = @($coreRows) + @($secondaryRows) + @($freeRows) +
    @($oneKeyRows) + @($twoKeyRows) + @($userRows) + @($fullCodeWordRows) +
    @($rareRows) + @($fullCodeCharacterRows)
$categoryDirectCount = @($allCategoryRows | Where-Object { $_ -cmatch '#直$' }).Count

$cleanedFiles = [ordered]@{
    '1.首选.txt' = @('## 首选') + $coreRows
    '2.分类.txt' = @('## 分类', '## 次选字词') + $secondaryRows + @('', '## 表外字') + $existingOutOfTableRows + @('', '## 随心') + $freeRows
    '3.一简次选.txt' = @('## 一简次选') + $oneKeyRows
    '4.二简次选.txt' = @('## 二简次选') + $twoKeyRows
    '5.直通.txt' = @('## 直通动作词条（编码、候选和顺序以本文件为准）') + $directActionRows
    '6.用户.txt' = @($userRows)
    '7.符号.txt' = @('## 符号') + $symbolRows + @('', '## 符号组') + @($symbolGroupExternalRows)
    '8.全码词.txt' = @('## 全码词') + $fullCodeWordRows
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
    '2.5.全码词.txt' = @('## 全码词') + $fullCodeWordRows
    '2.6.符号.txt' = @('## 符号') + $symbolRows
    '2.7.符号组.txt' = @('## 符号组（构建时添加 o 前缀）') + @($symbolGroupRows)
    '2.8.生僻字.txt' = @('## 生僻字') + $rareRows
    '2.9.全码字.txt' = @('## 全码字') + $fullCodeCharacterRows
}

foreach ($entry in $cleanedFiles.GetEnumerator()) {
    Write-Utf8Lf (Join-Path $cleanedPath $entry.Key) @($entry.Value)
}

$directActionDocument = [ordered]@{
    formatVersion = 1
    fixtureOnly = $false
    source = '双羽词库分类/双羽词库/5.直通.txt'
    sourceRecordCount = $directActionRows.Count
    rejectedRecordCount = $directActionConversion.Rejected.Count
    records = @($directActionConversion.Records)
}
$directActionJson = $directActionDocument | ConvertTo-Json -Depth 8
Write-Utf8Lf (Join-Path $cleanedPath '5.直通-规范动作.json') @($directActionJson -split "`r?`n")
$directActionReport = [ordered]@{
    source = '双羽词库分类/双羽词库/5.直通.txt'
    sourceRecordCount = $directActionRows.Count
    acceptedRecordCount = $directActionConversion.Records.Count
    rejectedRecordCount = $directActionConversion.Rejected.Count
    rejected = @($directActionConversion.Rejected)
}
$directActionReportJson = $directActionReport | ConvertTo-Json -Depth 6
Write-Utf8Lf (Join-Path $cleanedPath '5.直通-转换报告.json') @($directActionReportJson -split "`r?`n")

$report = @(
    '# 双羽客户词库清理说明',
    '',
    '- 客户原始回传词库数据保持不变；目录内提交格式说明随当前产品规则同步。',
    '- 所有输出统一为 UTF-8（无 BOM）、LF、Tab 分隔。',
    '- 分类文件中的 `#直` 是成品词条：原样保留在所属分类，不搬家、不查找、不固化。',
    '- `5.直通.txt` 是实体键盘直通动作词条来源：编码、候选标题和顺序原样取自客户文件；导入器只把受支持语义转换为类型化动作，不解释或执行原始 `$cmd`。',
    '- 增删受支持的直通行后重新导入即可生效，无需在 Rust 源码中逐编码固化；不支持或不安全的行进入转换报告且不出现在候选中。',
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
    "- 分类词库直通词条：$categoryDirectCount",
    "- 直通动作词条：$($directActionRows.Count)（接受 $($directActionConversion.Records.Count)，隔离 $($directActionConversion.Rejected.Count)）",
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
    $runtimeActionPath = Join-Path $projectPath 'engine-rust\crates\code-table-runtime\data\production-direct-actions.json'
    Write-Utf8Lf $runtimeActionPath @($directActionJson -split "`r?`n")
}

Write-Host 'SHUANGYU_CUSTOMER_LEXICON_IMPORT=PASS'
Write-Host "RECEIVED=$receivedPath"
Write-Host "CLEANED=$cleanedPath"
Write-Host "UPDATE_PROJECT=$($UpdateProject.IsPresent)"
Write-Host "CUSTOMER_RECORDS=$($coreRows.Count + $secondaryRows.Count + $freeRows.Count + $oneKeyRows.Count + $twoKeyRows.Count + $directActionRows.Count + $userRows.Count + $symbolRows.Count + $symbolGroupExternalRows.Count + $fullCodeWordRows.Count + $rareRows.Count + $fullCodeCharacterRows.Count + $receivedQuickRowCount + $spellingRows.Count)"
Write-Host "CATEGORY_DIRECT_RECORDS=$categoryDirectCount"
Write-Host "DIRECT_ACTION_RECORDS=$($directActionRows.Count)"
Write-Host "DIRECT_ACTION_ACCEPTED=$($directActionConversion.Records.Count)"
Write-Host "DIRECT_ACTION_REJECTED=$($directActionConversion.Rejected.Count)"
Write-Host "PRESERVED_OUT_OF_TABLE_RECORDS=$($existingOutOfTableRows.Count)"
