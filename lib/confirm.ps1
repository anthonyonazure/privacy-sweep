# Dot-source only. Typed confirmation for opt-in Windows tools.
# PRIVACY_SWEEP_CONFIRM is a test aid. -Yes does not satisfy a phrase.

function Confirm-Phrase {
  param([string]$Phrase)
  if ($env:PRIVACY_SWEEP_CONFIRM -eq $Phrase) {
    Write-Host "Confirmation accepted from PRIVACY_SWEEP_CONFIRM (test aid)."
    return $true
  }
  $answer = Read-Host "Type $Phrase to continue"
  if ($answer -ne $Phrase) {
    Write-Host "Confirmation did not match. Nothing was deleted."
    return $false
  }
  return $true
}

function Confirm-YesNo {
  param([string]$Prompt)
  if ($env:PRIVACY_SWEEP_ASSUME_ANSWER -match '^[Yy]$') { return $true }
  if ($env:PRIVACY_SWEEP_ASSUME_ANSWER -match '^[Nn]$') { return $false }
  $answer = Read-Host "$Prompt [y/N]"
  return ($answer -match '^[Yy]$')
}
