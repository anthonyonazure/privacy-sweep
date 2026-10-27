# Parse every PowerShell file in the repo. Does not execute them.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File |
  Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
$failed = 0
foreach ($file in $files) {
  $errs = $null
  $tokens = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
  if ($errs -and @($errs).Count -gt 0) {
    Write-Host "PARSE FAIL $($file.FullName)"
    foreach ($err in @($errs)) { Write-Host $err.ToString() }
    $failed++
  }
}
if ($failed -gt 0) { exit 1 }
Write-Host "Parsed $(@($files).Count) PowerShell files."
