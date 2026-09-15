. outputs/feedback-acceptance-20260911/helpers.ps1
$evidence='outputs/browser-fullscreen-fix-20260911'

function Wait-Keyboard([string]$name) {
  $readyDeadline=(Get-Date).AddSeconds(25)
  do {
    Ui "$name-ready" | Out-Null
    if(@($uiNodes | Where-Object text -eq 'Q').Count -gt 0) { return }
    Start-Sleep -Milliseconds 500
  } while((Get-Date) -lt $readyDeadline)
  throw "Keyboard not ready: $name"
}

function Wait-Web([string]$name, [string]$expected) {
  $pageDeadline=(Get-Date).AddSeconds(30)
  $pageReady=$false
  do {
    Ui "$name-pending" | Out-Null
    $pageReady=(@($uiNodes | Where-Object type -eq 'Web').Count -gt 0) -and
      (@($uiNodes | Where-Object text -eq $expected).Count -gt 0)
    if(!$pageReady) { Start-Sleep -Milliseconds 500 }
  } while(!$pageReady -and (Get-Date) -lt $pageDeadline)
  Ui $name -Shot | Out-Null
  [pscustomobject]@{name=$name; expected=$expected; passed=$pageReady} | ConvertTo-Json |
    Set-Content "$evidence/$name-status.json" -Encoding utf8
  if(!$pageReady) { throw "Full webpage did not appear: $name / $expected" }
  "PASS $name / $expected"
}
