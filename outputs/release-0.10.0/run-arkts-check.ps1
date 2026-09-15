$ErrorActionPreference='Stop'
$env:DEVECO_SDK_HOME='C:/Program Files/Huawei/DevEco Studio/sdk'
$started=Get-Date
$coverage=Join-Path (Get-Location) 'entry/.test/default/intermediates/test/coverage_data/coverage.log'
$report=Join-Path (Get-Location) 'entry/.test/default/intermediates/test/coverage_data/test_result.txt'
$runner=Start-Process -FilePath $env:ComSpec -ArgumentList '/d /c ""C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --no-daemon --mode module -p module=entry@default test"' -WindowStyle Hidden -PassThru -WorkingDirectory (Get-Location).Path -RedirectStandardOutput (Join-Path $PSScriptRoot 'arkts-tests.log') -RedirectStandardError (Join-Path $PSScriptRoot 'arkts-tests-error.log')
$failure=''
while(-not $runner.WaitForExit(1000)) {
  if(Test-Path -LiteralPath $coverage) {
    $item=Get-Item -LiteralPath $coverage
    if($item.LastWriteTime -ge $started -and ((Get-Content -LiteralPath $coverage -Tail 30) -match 'atio6axx!|atig6pxx!')) {
      $failure='SDK_PREVIEWER_GRAPHICS_CRASH'
      break
    }
  }
  if(((Get-Date)-$started).TotalSeconds -gt 240) { $failure='TEST_RUNNER_TIMEOUT';break }
}
if($failure) {
  & taskkill.exe /PID $runner.Id /T /F | Out-Null
  if(Test-Path -LiteralPath $coverage) {Copy-Item -LiteralPath $coverage -Destination (Join-Path $PSScriptRoot 'arkts-previewer.log') -Force}
  "RESULT=$failure" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'arkts-check-status.txt')
  Write-Output "RESULT=$failure"
  exit 1
}
$runner.WaitForExit()
if($runner.ExitCode -ne 0 -or (Get-Item -LiteralPath $report).LastWriteTime -lt $started) {
  throw 'ArkTS task failed or did not generate a fresh report'
}
Copy-Item -LiteralPath $report -Destination (Join-Path $PSScriptRoot 'arkts-test-result.txt') -Force
Get-Content -LiteralPath $report -Tail 1 | Tee-Object -FilePath (Join-Path $PSScriptRoot 'arkts-check-status.txt')
