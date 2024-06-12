Get-ChildItem -Filter ".\test\*_test.dart" | ForEach-Object {
  $fileName = $_.Name
  Write-Host "Running: ${fileName}"
  dart $_.FullName
  $exitCode = $LastExitCode

  if ($exitCode -ne 0) {
    Write-Error "Error running ${fileName}: Exit code ${exitCode}"
    Break
  }
}
