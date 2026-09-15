$ErrorActionPreference = 'Stop'
$taskScript = Join-Path $PSScriptRoot 'import-shuangyu-customer-lexicon.ps1'
$taskTokens = $null
$taskErrors = $null
$taskAst = [Management.Automation.Language.Parser]::ParseFile($taskScript, [ref]$taskTokens, [ref]$taskErrors)
if ($taskErrors.Count -gt 0) { throw 'Importer syntax is invalid' }
$taskFunction = $taskAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Convert-DirectActionRows'
}, $false)
. ([scriptblock]::Create($taskFunction.Extent.Text))
$taskRows = @(
    ('$CC(default(dict.rev(clip()), "[复制反查]"), type(dict.rev(clip())))' + "`tofi"),
    ('$cmd(querycode,[复制反查])' + "`tofi"),
    ('$CC(default(dict.rev(clip()), "[复制反查]"), run(clip()))' + "`tofi")
)
$taskResult = Convert-DirectActionRows $taskRows
if ($taskResult.Records.Count -ne 2 -or $taskResult.Rejected.Count -ne 1) {
    throw 'Only the documented expression and legacy querycode should be accepted'
}
foreach ($record in $taskResult.Records) {
    if ($record.type -ne 'DIRECT_CONTROL' -or $record.action -ne 'clipboard.reverse' -or
        $record.target -ne '' -or $record.label -ne '[复制反查]' -or $record.code -ne 'ofi') {
        throw 'Reverse lookup action conversion mismatch'
    }
}
Write-Output 'CLIPBOARD_REVERSE_IMPORT=PASS'
