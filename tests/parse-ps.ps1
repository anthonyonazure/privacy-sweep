# Parse every PowerShell file in the repo. Does not execute them.
# Dot-source this file to load Test-AutomaticVariableAssignment without scanning.
# Windows PowerShell treats automatic names as case-insensitive, and several
# ($HOME, $PID, $HOST, $PROFILE, ...) are read-only. $null = is the discard
# idiom and is allowed. env: and scope-qualified variables are not automatic.

$PrivacySweepForbiddenAutomatic = @(
  'home', 'host', 'input', 'pid', 'profile', 'pshome', 'psversiontable',
  'psculture', 'psuiculture', 'psscriptroot', 'pscommandpath', 'shellid',
  'myinvocation', 'executioncontext', 'true', 'false', 'psboundparameters',
  'stacktrace'
)

function Get-AutomaticVariableName {
  param($VariableAst)
  if (-not $VariableAst) { return $null }
  $path = $null
  if ($VariableAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
    $path = $VariableAst.VariablePath
  }
  if (-not $path) { return $null }
  if ($path.DriveName) { return $null }
  $user = [string]$path.UserPath
  if (-not $user) { return $null }
  if ($user.Contains(':')) { return $null }
  return $user
}

function Test-ForbiddenAutomaticName {
  param([string]$Name)
  if (-not $Name) { return $false }
  $lower = $Name.ToLowerInvariant()
  if ($lower -eq 'null') { return $false }
  return @($PrivacySweepForbiddenAutomatic) -contains $lower
}

function Test-AutomaticVariableAssignment {
  param([string]$Path)
  $errs = $null
  $tokens = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
  if (-not $ast) { return 0 }
  $bad = 0
  $assigns = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst]
  }, $true))
  foreach ($assign in $assigns) {
    $name = Get-AutomaticVariableName $assign.Left
    if (Test-ForbiddenAutomaticName $name) {
      Write-Host "AUTO VAR ${Path}: assignment to `$$name"
      $bad++
    }
  }
  $loops = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.ForEachStatementAst]
  }, $true))
  foreach ($loop in $loops) {
    $name = Get-AutomaticVariableName $loop.Variable
    if (Test-ForbiddenAutomaticName $name) {
      Write-Host "AUTO VAR ${Path}: foreach assignment to `$$name"
      $bad++
    }
  }
  $params = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.ParameterAst]
  }, $true))
  foreach ($paramAst in $params) {
    $name = Get-AutomaticVariableName $paramAst.Name
    if (Test-ForbiddenAutomaticName $name) {
      Write-Host "AUTO VAR ${Path}: parameter `$$name"
      $bad++
    }
  }
  return $bad
}

if ($MyInvocation.InvocationName -eq '.') {
  return
}

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File |
  Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
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
  $auto = Test-AutomaticVariableAssignment $file.FullName
  if ($auto -gt 0) { $failed++ }
}
if ($failed -gt 0) { exit 1 }
Write-Host "Parsed $($files.Count) PowerShell files."
