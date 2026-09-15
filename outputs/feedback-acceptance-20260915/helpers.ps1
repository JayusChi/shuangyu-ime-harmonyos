param([string]$Target='phone')
. "$PSScriptRoot/../feedback-reacceptance-20260914/run-helpers.ps1" -Target $Target
$evidence=Join-Path $PSScriptRoot $Target
function Snap([string]$name,[switch]$Shot) {
  Start-Sleep -Milliseconds 400
  Ui $name -Shot:$Shot | Out-Null
}
function FillVerified([string]$hint,[string]$value,[string]$name) {
  for($attempt=1;$attempt -le 3;$attempt++) {
    Fill-Hint $hint $value
    Start-Sleep -Milliseconds 1000
    Snap "$name-$attempt"
    if(($uiNodes | Where-Object hint -eq $hint | Select-Object -First 1).text -ceq $value){return}
  }
  throw "Field $hint did not contain $value"
}
function AddFixed([string]$word,[string]$code) {
  FillVerified '词条' $word "$code-word"
  FillVerified '编码' $code "$code-code"
  Tap ($uiNodes | Where-Object text -eq '固顶' | Select-Object -First 1)
  Start-Sleep -Milliseconds 400
  Snap "$code-pin"
  if($uiNodes | Where-Object { $_.text -ceq 'q' -or $_.text -ceq 'Q' }) {
    Key 2
    Start-Sleep -Milliseconds 500
    Snap "$code-hide-keyboard"
  }
  TextTap '保存并立即应用'
  Start-Sleep -Milliseconds 1000
  Snap "$code-saved" -Shot
}
