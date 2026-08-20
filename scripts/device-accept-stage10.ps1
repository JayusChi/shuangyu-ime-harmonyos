param(
    [string]$Target = '127.0.0.1:5555',
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' }),
    [string]$EvidenceDir = 'docs\evidence\stage10\device'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$appProfile = Get-Content -LiteralPath (Join-Path $repoRoot 'AppScope\app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundle = [string]$appProfile.app.bundleName
$hap = (Resolve-Path (Join-Path $repoRoot 'entry\build\artifacts\entry-debug-unsigned.hap')).Path
$outDir = [IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir 'stage10_device_acceptance.log'

function Invoke-Hdc {
    $Arguments = @($args)
    Write-Host "> hdc -t $Target $($Arguments -join ' ')"
    $output = & $script:hdc -t $script:Target @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if ($exitCode -ne 0) {
        throw "hdc failed ($exitCode): $($Arguments -join ' ')"
    }
    return $output
}

function Invoke-HdcAllowFail {
    $Arguments = @($args)
    Write-Host "> hdc -t $Target $($Arguments -join ' ')"
    $output = & $script:hdc -t $script:Target @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    Write-Host "exit=$exitCode"
    return $exitCode
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "ASSERT FAILED: $Message"
    }
    Write-Host "PASS: $Message"
}

function Bounds-Of {
    param($Node)
    $match = [regex]::Match([string]$Node.attributes.bounds, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
    if (-not $match.Success) { return $null }
    $x1 = [int]$match.Groups[1].Value
    $y1 = [int]$match.Groups[2].Value
    $x2 = [int]$match.Groups[3].Value
    $y2 = [int]$match.Groups[4].Value
    return [PSCustomObject]@{
        X1 = $x1
        Y1 = $y1
        X2 = $x2
        Y2 = $y2
        Width = $x2 - $x1
        Height = $y2 - $y1
        CX = [int](($x1 + $x2) / 2)
        CY = [int](($y1 + $y2) / 2)
    }
}

function Get-Nodes {
    param([string]$Path)
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[object]
    function Walk-Node($node) {
        if ($null -ne $node -and $null -ne $node.attributes) {
            $script:Stage10NodeList.Add($node) | Out-Null
        }
        foreach ($child in @($node.children)) {
            Walk-Node $child
        }
    }
    $script:Stage10NodeList = $list
    Walk-Node $json
    return $list.ToArray()
}

function Find-TextNode {
    param(
        [string]$Path,
        [string]$Text,
        [int]$MinY = 0,
        [int]$MaxY = 3000
    )
    $matches = @()
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.text -ne $Text) { continue }
        $bounds = Bounds-Of $node
        if ($null -eq $bounds) { continue }
        if ($bounds.Y1 -ge $MinY -and $bounds.Y2 -le $MaxY) {
            $matches += [PSCustomObject]@{ Node = $node; Bounds = $bounds }
        }
    }
    return $matches | Sort-Object { $_.Bounds.Y1 }, { $_.Bounds.X1 } | Select-Object -First 1
}

function Find-HintNode {
    param([string]$Path, [string]$Hint)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.hint -ne $Hint) { continue }
        $bounds = Bounds-Of $node
        if ($null -ne $bounds -and $bounds.Height -ge 70 -and $bounds.Y1 -ge 120 -and $bounds.Y2 -le 2700) {
            return [PSCustomObject]@{ Node = $node; Bounds = $bounds }
        }
    }
    return $null
}

function Find-KeyboardTextNode {
    param([string]$Path, [string]$Text)
    $keyboardRoot = Get-Nodes $Path | Where-Object {
        [string]$_.attributes.pagePath -eq 'presentation/keyboard/KeyboardRootStage3' -and
        [string]$_.attributes.visible -eq 'true'
    } | Select-Object -First 1
    if ($null -eq $keyboardRoot) { return $null }
    $keyboardBounds = Bounds-Of $keyboardRoot
    if ($null -eq $keyboardBounds) { return $null }
    return Find-TextNode -Path $Path -Text $Text -MinY $keyboardBounds.Y1 -MaxY $keyboardBounds.Y2
}

function Get-InputText {
    param([string]$Path, [string]$Hint)
    $input = Find-HintNode -Path $Path -Hint $Hint
    if ($null -eq $input) { throw "Input not found for text assertion: $Hint" }
    return [string]$input.Node.attributes.text
}

function Has-Text {
    param([string]$Path, [string]$Text, [int]$MinY = 0, [int]$MaxY = 3000)
    $node = Find-TextNode -Path $Path -Text $Text -MinY $MinY -MaxY $MaxY
    if ($null -eq $node) {
        $node = Find-KeyboardTextNode -Path $Path -Text $Text
    }
    return $null -ne $node
}

function Has-TextContaining {
    param([string]$Path, [string]$Text)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.text -like "*$Text*") { return $true }
    }
    return $false
}

function Find-IdNode {
    param([string]$Path, [string]$Id)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.id -ne $Id) { continue }
        $bounds = Bounds-Of $node
        if ($null -ne $bounds) {
            return [PSCustomObject]@{ Node = $node; Bounds = $bounds }
        }
    }
    return $null
}

function Has-SystemSecureKeyboard {
    param([string]$Path)
    foreach ($node in Get-Nodes $Path) {
        $id = [string]$node.attributes.id
        if ($id -in @('pwd_row_content', 'safeImage', 'CanvasKeyboard')) { return $true }
    }
    return $false
}

function Find-ModelProbe {
    param([string]$Path)
    foreach ($node in Get-Nodes $Path) {
        if ([string]$node.attributes.text -notmatch '^模型\d*$') { continue }
        $bounds = Bounds-Of $node
        if ($null -ne $bounds -and $bounds.Y1 -ge 1400 -and $bounds.Y2 -le 2100) {
            return [PSCustomObject]@{ Node = $node; Bounds = $bounds }
        }
    }
    return $null
}

function Dump-Layout {
    param([string]$Name)
    $remote = "/data/local/tmp/$Name.json"
    Invoke-Hdc shell uitest dumpLayout -p $remote | Out-Null
    $local = Join-Path $outDir "$Name.json"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Capture-Screen {
    param([string]$Name)
    $remote = "/data/local/tmp/$Name.png"
    Invoke-Hdc shell uitest screenCap -p $remote | Out-Null
    $local = Join-Path $outDir "$Name.png"
    Invoke-Hdc file recv $remote $local | Out-Null
    return $local
}

function Tap-XY {
    param([int]$X, [int]$Y, [string]$Label)
    Write-Host "tap $Label at ($X,$Y)"
    Invoke-Hdc shell uitest uiInput click $X $Y | Out-Null
    Start-Sleep -Milliseconds 450
}

function Tap-Text {
    param([string]$Layout, [string]$Text, [int]$MinY, [int]$MaxY, [string]$Label)
    $item = Find-TextNode -Path $Layout -Text $Text -MinY $MinY -MaxY $MaxY
    if ($null -eq $item) {
        $item = Find-KeyboardTextNode -Path $Layout -Text $Text
    }
    if ($null -eq $item) { throw "Text '$Text' not found for $Label in $Layout" }
    Tap-XY -X $item.Bounds.CX -Y $item.Bounds.CY -Label $Label
}

function Hide-KeyboardFromLayout {
    param([string]$Layout)
    $hide = Find-TextNode -Path $Layout -Text '隐藏' -MinY 1500 -MaxY 2700
    if ($null -eq $hide) {
        $hide = Find-KeyboardTextNode -Path $Layout -Text '隐藏'
    }
    if ($null -ne $hide) {
        Tap-XY -X $hide.Bounds.CX -Y $hide.Bounds.CY -Label 'hide keyboard'
        Start-Sleep -Milliseconds 700
    }
}

function Focus-Input {
    param([string]$Hint, [string]$Prefix)
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $page = Dump-Layout "${Prefix}_page_$attempt"
        $input = Find-HintNode -Path $page -Hint $Hint
        if ($null -ne $input) {
            Tap-XY -X $input.Bounds.CX -Y $input.Bounds.CY -Label "focus $Prefix"
            Start-Sleep -Seconds 1
            $layout = Dump-Layout "${Prefix}_layout"
            Capture-Screen "${Prefix}_layout" | Out-Null
            return $layout
        }
        Write-Host "scroll toward $Prefix"
        Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
        Start-Sleep -Milliseconds 600
    }
    throw "Input hint not visible after scrolling: $Hint"
}

function Scroll-ToTop {
    for ($i = 0; $i -lt 5; $i++) {
        Invoke-Hdc shell uitest uiInput swipe 660 500 660 2500 1200 | Out-Null
        Start-Sleep -Milliseconds 350
    }
}

if (-not (Test-Path -LiteralPath $hdc)) { throw "hdc not found: $hdc" }

Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    $hapItem = Get-Item -LiteralPath $hap
    $hapHash = Get-FileHash -LiteralPath $hap -Algorithm SHA256
    Write-Host "HAP=$hap"
    Write-Host "HAP_SIZE=$($hapItem.Length)"
    Write-Host "HAP_SHA256=$($hapHash.Hash)"
    Write-Host "DEVICE_TARGET=$Target"
    Invoke-Hdc list targets -v | Out-Null
    $abi = Invoke-Hdc shell param get const.product.cpu.abilist
    $version = Invoke-Hdc shell param get const.product.software.version
    Write-Host "DEVICE_ABI=$($abi -join '')"
    Write-Host "DEVICE_VERSION=$($version -join '')"

    Invoke-Hdc install -r $hap | Out-Null
    Invoke-HdcAllowFail shell aa force-stop $bundle | Out-Null
    Invoke-Hdc shell bm clean -n $bundle -d | Out-Null
    Invoke-Hdc shell ime -e $bundle -f | Out-Null
    Invoke-HdcAllowFail shell ime -s $bundle | Out-Null
    $imeStatus = Invoke-Hdc shell ime -g
    Assert-True -Condition (($imeStatus -join "`n") -match [regex]::Escape($bundle)) -Message 'stage10 IME enabled'
    Invoke-Hdc shell aa start -b $bundle -a EntryAbility | Out-Null
    Start-Sleep -Seconds 2
    $debugEntry = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        $settingsPage = Dump-Layout "stage10_debug_entry_page_$attempt"
        $debugEntry = Find-TextNode -Path $settingsPage -Text '调试与验收'
        if ($null -ne $debugEntry) { break }
        Invoke-Hdc shell uitest uiInput swipe 660 2450 660 550 1000 | Out-Null
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $debugEntry) { throw 'Debug acceptance entry not found on Stage 11 settings home.' }
    Tap-XY -X $debugEntry.Bounds.CX -Y $debugEntry.Bounds.CY -Label 'open Stage 10 debug acceptance page'
    Start-Sleep -Seconds 1
    Scroll-ToTop

    $normal = Focus-Input -Hint '普通文本：默认中文' -Prefix 'stage10_normal'
    Assert-True (-not (Has-TextContaining $normal 'chinese_placeholder')) 'development keyboard mode status is absent'
    Assert-True (-not (Has-TextContaining $normal 'Stage 3 ready')) 'development readiness status is absent'
    Assert-True (-not (Has-TextContaining $normal '学习开')) 'development learning status is absent'
    Assert-True (-not (Has-Text $normal '中文' 1500 2200)) 'idle Chinese candidate placeholder is absent'
    Assert-True (Has-Text $normal '123' 2200 2700) 'normal layout exposes number switch'
    Assert-True (Has-Text $normal '#+=' 2200 2700) 'normal layout exposes symbol switch'

    Tap-Text $normal 'n' 1800 2500 'normal Chinese key n'
    $normalAfterN = Dump-Layout 'stage10_normal_after_n'
    Assert-True ((Get-InputText $normalAfterN '普通文本：默认中文') -eq 'n') 'first Chinese letter is editor preview text'
    Tap-Text $normalAfterN 'i' 1800 2500 'normal Chinese key i'
    $normalCandidates = Dump-Layout 'stage10_normal_candidates'
    Capture-Screen 'stage10_normal_candidates' | Out-Null
    Assert-True ((Get-InputText $normalCandidates '普通文本：默认中文') -eq 'ni') 'continuous Chinese letters update editor preview text'
    Assert-True (Has-Text $normalCandidates '你' 1500 2100) 'normal Chinese candidate query works'
    Tap-Text $normalCandidates '删除' 1800 2600 'delete one Chinese preview letter'
    $normalAfterDelete = Dump-Layout 'stage10_normal_after_delete'
    Assert-True ((Get-InputText $normalAfterDelete '普通文本：默认中文') -eq 'n') 'delete updates editor preview to one letter'
    Tap-Text $normalAfterDelete 'i' 1800 2500 'restore Chinese preview for candidate click'
    $normalCandidatesRestored = Dump-Layout 'stage10_normal_candidates_restored'
    Assert-True ((Get-InputText $normalCandidatesRestored '普通文本：默认中文') -eq 'ni') 'preview can continue after delete'
    Tap-Text $normalCandidatesRestored '你' 1500 2100 'select normal test candidate'
    $normalCommitted = Dump-Layout 'stage10_normal_committed'
    Assert-True ((Get-InputText $normalCommitted '普通文本：默认中文') -eq '你') 'candidate replaces preview without duplicate letters'

    Tap-Text $normalCommitted 'n' 1800 2500 'space workflow Chinese key n'
    $normalSpaceN = Dump-Layout 'stage10_normal_space_n'
    Tap-Text $normalSpaceN 'i' 1800 2500 'space workflow Chinese key i'
    $normalSpaceCandidates = Dump-Layout 'stage10_normal_space_candidates'
    Tap-Text $normalSpaceCandidates '空格' 2200 2700 'space commits the first candidate'
    $normalSpaceCommitted = Dump-Layout 'stage10_normal_space_committed'
    Assert-True ((Get-InputText $normalSpaceCommitted '普通文本：默认中文') -eq '你你') 'space commits candidate without leaving preview letters'

    Tap-Text $normalSpaceCommitted '中' 2200 2700 'switch normal editor to English'
    $english = Dump-Layout 'stage10_english_lowercase'
    Assert-True (-not (Has-Text $english '中文' 1500 2100)) 'English mode hides candidate bar'
    Assert-True (Has-Text $english 'q' 1600 2300) 'English defaults to lowercase'

    Tap-Text $english '⇧' 1900 2500 'single shift'
    $oneShot = Dump-Layout 'stage10_shift_one_shot'
    Assert-True (Has-Text $oneShot 'Q' 1600 2300) 'single Shift shows uppercase keycaps'
    Tap-Text $oneShot 'A' 1800 2500 'commit one-shot uppercase letter'
    $afterOneShot = Dump-Layout 'stage10_shift_after_letter'
    Assert-True (Has-Text $afterOneShot 'q' 1600 2300) 'one-shot Shift returns to lowercase after letter'

    $shift = Find-TextNode -Path $afterOneShot -Text '⇧' -MinY 1900 -MaxY 2500
    if ($null -eq $shift) { $shift = Find-KeyboardTextNode -Path $afterOneShot -Text '⇧' }
    if ($null -eq $shift) { throw 'Shift key not found for double click' }
    Write-Host "double tap Shift at ($($shift.Bounds.CX),$($shift.Bounds.CY))"
    Invoke-Hdc shell uitest uiInput doubleClick $shift.Bounds.CX $shift.Bounds.CY | Out-Null
    Start-Sleep -Milliseconds 650
    $caps = Dump-Layout 'stage10_shift_caps_lock'
    Capture-Screen 'stage10_shift_caps_lock' | Out-Null
    Assert-True (Has-Text $caps '⇧锁' 1900 2500) 'double Shift enables Caps Lock visual state'
    Assert-True (Has-Text $caps 'Q' 1600 2300) 'Caps Lock shows uppercase keycaps'
    Tap-Text $caps 'B' 1900 2500 'Caps Lock letter one'
    $capsAfterOne = Dump-Layout 'stage10_shift_caps_after_one'
    Assert-True (Has-Text $capsAfterOne '⇧锁' 1900 2500) 'Caps Lock remains after first letter'
    Tap-Text $capsAfterOne 'C' 1900 2500 'Caps Lock letter two'
    $capsAfterTwo = Dump-Layout 'stage10_shift_caps_after_two'
    Assert-True (Has-Text $capsAfterTwo '⇧锁' 1900 2500) 'Caps Lock remains after second letter'
    Tap-Text $capsAfterTwo '⇧锁' 1900 2500 'disable Caps Lock'
    $englishAgain = Dump-Layout 'stage10_shift_caps_disabled'
    Assert-True (Has-Text $englishAgain 'q' 1600 2300) 'Shift exits Caps Lock to lowercase'

    Tap-Text $englishAgain '123' 2200 2700 'open temporary number mode'
    $temporaryNumber = Dump-Layout 'stage10_temporary_number'
    Assert-True (Has-Text $temporaryNumber '0' 1800 2600) 'number layout includes zero'
    Tap-Text $temporaryNumber '返回' 1800 2700 'return from number mode'
    $numberReturned = Dump-Layout 'stage10_temporary_number_returned'
    Assert-True (Has-Text $numberReturned 'q' 1600 2300) 'number mode returns to prior English mode'

    Tap-Text $numberReturned '#+=' 2200 2700 'open symbol mode'
    $symbol = Dump-Layout 'stage10_symbol'
    Assert-True (Has-Text $symbol '?' 1700 2600) 'symbol layout is usable'
    Tap-Text $symbol '返回' 1800 2700 'return from symbol mode'
    $symbolReturned = Dump-Layout 'stage10_symbol_returned'
    Assert-True (Has-Text $symbolReturned 'q' 1600 2300) 'symbol mode restores prior English mode'
    Tap-Text $symbolReturned '英' 2200 2700 'return normal editor to Chinese'
    $chineseReturned = Dump-Layout 'stage10_chinese_returned'
    Assert-True (-not (Has-Text $chineseReturned '中文' 1500 2100)) 'idle candidate bar stays hidden after returning to Chinese'
    Assert-True (-not (Has-Text $chineseReturned '回归' 1400 2100)) 'formal keyboard excludes regression control'
    Assert-True ($null -eq (Find-ModelProbe $chineseReturned)) 'formal keyboard excludes model probe'
    Hide-KeyboardFromLayout $chineseReturned
    Start-Sleep -Seconds 1

    $password = Focus-Input -Hint '密码：安全英文键盘' -Prefix 'stage10_password'
    if (Has-SystemSecureKeyboard $password) {
        Write-Host 'PASSWORD_RUNTIME_ROUTE=SYSTEM_SECURE_KEYBOARD'
        Assert-True (-not (Has-Text $password '中文' 1500 2100)) 'system password keyboard has no candidate bar'
        Assert-True ($null -ne (Find-IdNode -Path $password -Id 'safeImage')) 'system marks password input as secure'
        $secureKey = Find-IdNode -Path $password -Id 'letters_q'
        if ($null -eq $secureKey) { throw 'system secure character key not found' }
        Tap-XY -X $secureKey.Bounds.CX -Y $secureKey.Bounds.CY -Label 'system secure character (value intentionally not logged)'
        Invoke-Hdc shell uitest uiInput keyEvent Back | Out-Null
        Start-Sleep -Seconds 1

        Write-Host 'PASS: system secure password input remains outside the app IME candidate route'
    } else {
        Write-Host 'PASSWORD_RUNTIME_ROUTE=APPLICATION_SAFE_LAYOUT'
        Assert-True (-not (Has-Text $password '中文' 1500 2100)) 'password editor hides candidate bar'
        Assert-True (-not (Has-Text $password '中' 2200 2700)) 'password editor has no Chinese switch'
        Assert-True (Has-Text $password '⇧' 1800 2500) 'password English layout retains Shift'
        $secureKey = Find-TextNode -Path $password -Text 'q' -MinY 1600 -MaxY 2400
        if ($null -eq $secureKey) { $secureKey = Find-KeyboardTextNode -Path $password -Text 'q' }
        if ($null -eq $secureKey) { throw 'secure layout character key not found' }
        Tap-XY -X $secureKey.Bounds.CX -Y $secureKey.Bounds.CY -Label 'secure direct character (value intentionally not logged)'
        $passwordAfterInput = Dump-Layout 'stage10_password_after_input'
        Assert-True ($null -eq (Find-ModelProbe $passwordAfterInput)) 'password layout contains no model probe'
        Hide-KeyboardFromLayout $passwordAfterInput
    }

    $numberPassword = Focus-Input -Hint '数字密码' -Prefix 'stage10_number_password'
    if (Has-SystemSecureKeyboard $numberPassword) {
        Write-Host 'NUMBER_PASSWORD_RUNTIME_ROUTE=SYSTEM_SECURE_KEYBOARD'
        Assert-True ($null -ne (Find-IdNode -Path $numberPassword -Id 'number_0')) 'system number password keyboard includes digits'
        Assert-True (-not (Has-Text $numberPassword '中文' 1500 2100)) 'system number password keyboard has no candidate bar'
        Invoke-Hdc shell uitest uiInput keyEvent Back | Out-Null
        Start-Sleep -Milliseconds 700
    } else {
        Write-Host 'NUMBER_PASSWORD_RUNTIME_ROUTE=APPLICATION_SAFE_LAYOUT'
        Assert-True (Has-Text $numberPassword '0' 1800 2600) 'number password includes digits'
        Assert-True (-not (Has-Text $numberPassword '中文' 1500 2100)) 'number password hides candidate bar'
        Hide-KeyboardFromLayout $numberPassword
    }

    $number = Focus-Input -Hint '数字：0～9' -Prefix 'stage10_number'
    Assert-True (Has-Text $number '0' 1800 2600) 'number editor includes zero'
    Assert-True (-not (Has-Text $number '返回' 1800 2700)) 'number editor cannot escape its constrained mode'
    Hide-KeyboardFromLayout $number

    $decimal = Focus-Input -Hint '小数：包含小数点' -Prefix 'stage10_decimal'
    Assert-True (Has-Text $decimal '.' 1800 2600) 'decimal subtype exposes decimal point'
    Hide-KeyboardFromLayout $decimal

    $phone = Focus-Input -Hint '电话：包含 * # +' -Prefix 'stage10_phone'
    Assert-True (Has-Text $phone '*' 1700 2600) 'phone layout includes star'
    Assert-True (Has-Text $phone '#' 1700 2600) 'phone layout includes hash'
    Assert-True (Has-Text $phone '+' 1700 2600) 'phone layout includes plus'
    Hide-KeyboardFromLayout $phone

    $email = Focus-Input -Hint 'name@example.com' -Prefix 'stage10_email'
    Assert-True (Has-Text $email '@' 1600 2600) 'email layout exposes at sign'
    Assert-True (Has-Text $email '.' 1600 2600) 'email layout exposes dot'
    Assert-True (-not (Has-Text $email '中文' 1500 2100)) 'email editor hides candidate bar'
    Hide-KeyboardFromLayout $email

    $url = Focus-Input -Hint 'https://example.com' -Prefix 'stage10_url'
    foreach ($urlSymbol in @('.', '/', ':', '-', '_')) {
        Assert-True (Has-Text $url $urlSymbol 1500 2600) "URL layout exposes $urlSymbol"
    }
    Hide-KeyboardFromLayout $url

    $search = Focus-Input -Hint '搜索：回车执行搜索' -Prefix 'stage10_search'
    Assert-True (-not (Has-Text $search '中文' 1500 2100)) 'search editor hides idle candidate bar'
    Assert-True (Has-Text $search '搜索' 2200 2700) 'search editor shows Search action key'
    Tap-Text $search '搜索' 2200 2700 'execute Search editor action'
    Start-Sleep -Milliseconds 700
    $searchAfterAction = Dump-Layout 'stage10_search_action'
    Hide-KeyboardFromLayout $searchAfterAction
    Scroll-ToTop
    $actionStatus = Dump-Layout 'stage10_search_action_status'
    Assert-True (Has-TextContaining $actionStatus '最近编辑动作：搜索') 'Search key reaches the system editor action'

    $multiline = Focus-Input -Hint '多行文本：回车插入换行' -Prefix 'stage10_multiline'
    Assert-True (-not (Has-Text $multiline '中文' 1500 2100)) 'multiline editor hides idle candidate bar'
    Assert-True (Has-Text $multiline '回车' 2200 2700) 'multiline editor shows newline action key'
    Capture-Screen 'stage10_multiline_final' | Out-Null

    Write-Host 'STAGE10_DEVICE_ACCEPTANCE_RESULT=PASS'
} finally {
    Stop-Transcript | Out-Null
}
