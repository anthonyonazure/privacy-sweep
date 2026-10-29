# Wi-Fi profile name parser for the Windows audit.
# Dot-source this file. It prints nothing and deletes nothing.
# Only the text after the colon on a profile row is a name. Passwords are never read.
# $Matches is copied only after -match returns true. A later -match must not
# run before that copy: PowerShell keeps a single $Matches variable.

function Get-WlanProfileNames {
  param([string[]]$Lines)
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($line in @($Lines)) {
    if ($null -eq $line) { continue }
    $name = $null
    $english = $line -match '^\s*(?:All User Profile|User Profile)\s*:\s*(.*)$'
    if ($english) {
      $captured = $null
      if ($Matches.ContainsKey(1)) { $captured = $Matches[1] }
      if ($null -ne $captured) { $name = ([string]$captured).Trim() }
    } else {
      $localized = $line -match '^\s{2,}(.+?)\s*:\s*(.*)$'
      if ($localized) {
        $label = $null
        $captured = $null
        if ($Matches.ContainsKey(1)) { $label = $Matches[1] }
        if ($Matches.ContainsKey(2)) { $captured = $Matches[2] }
        $labelOk = $false
        if ($null -ne $label) {
          $labelText = [string]$label
          # English "Profile", German/French "Profil", Spanish/Portuguese "Perfil".
          # "Profiles on interface ..." is a header, not a saved network.
          if ($labelText -match '(?i)profil|perfil' -and $labelText -notmatch '(?i)interface') {
            $labelOk = $true
          }
        }
        if ($labelOk -and $null -ne $captured) { $name = ([string]$captured).Trim() }
      }
    }
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($name -eq '<None>' -or $name -match '^(?i)none$') { continue }
    $names.Add($name) | Out-Null
  }
  # Emit one name per pipeline object. The caller wraps with @() so a
  # single name still has Count 1, and an empty result has Count 0.
  foreach ($item in $names) { Write-Output $item }
}
