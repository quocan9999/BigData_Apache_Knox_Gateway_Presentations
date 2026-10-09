[CmdletBinding()]
param(
  [string]$ProjectName = 'apache-knox-bigdata-demo',

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 180,

  [switch]$IncludeGuestAllowedAclOverlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @(
  'compose', '-p', $ProjectName,
  '-f', 'docker-compose.yml',
  '-f', 'docker-compose.knox.yml'
)
if ($IncludeGuestAllowedAclOverlay) {
  $composePrefix += @('-f', 'docker-compose.knox-acl-test.yml')
}

function Invoke-Compose {
  param([string[]]$Arguments)
  $dockerArguments = $script:composePrefix + $Arguments
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & docker @dockerArguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

Push-Location $demoRoot
try {
  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -ne 0) {
    $states = Invoke-Compose -Arguments @('ps', '-a')
    $logs = Invoke-Compose -Arguments @('logs', '--tail=100', 'knox-gateway', 'knox-ldap')
    throw "Compose did not reach healthy state (exit $($start.ExitCode)): $($start.Output)`nService states:`n$($states.Output)`nRecent logs:`n$($logs.Output)"
  }
  Write-Output 'Knox readiness PASS: Compose reports healthy LDAP and Gateway; Gateway healthcheck verifies the HTTPS route and Basic challenge.'
}
finally {
  Pop-Location
}
