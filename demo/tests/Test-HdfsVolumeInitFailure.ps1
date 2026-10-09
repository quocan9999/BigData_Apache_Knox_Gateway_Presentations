[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^knox-p01-[a-z0-9-]+$')]
  [string]$ProjectName,

  [ValidateRange(30, 180)]
  [int]$TimeoutSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @(
  '-p', $ProjectName,
  '-f', 'docker-compose.yml',
  '-f', 'docker-compose.phase01-test.yml',
  '-f', 'docker-compose.phase01-init-permission-failure.yml'
)

function Invoke-Compose {
  param([string[]]$Arguments)
  $dockerArguments = @('compose') + $script:composePrefix + $Arguments
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
  $config = Invoke-Compose -Arguments @('config', '--quiet')
  if ($config.ExitCode -ne 0 -or $config.Output -match 'level=warning|variable is not set') {
    throw "Compose config failed (exit $($config.ExitCode)): $($config.Output)"
  }

  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -eq 0) {
    throw 'Compose incorrectly reported success when volume initialization lacked permission.'
  }

  $logs = Invoke-Compose -Arguments @('logs', '--tail=40', 'hdfs-volume-init')
  if ($logs.Output -notmatch 'Permission denied|Operation not permitted|Read-only file system') {
    throw "Init failed without a clear permission error. Compose: $($start.Output); logs: $($logs.Output)"
  }

  $running = Invoke-Compose -Arguments @('ps', '--status', 'running', '--services')
  if ($running.ExitCode -ne 0 -or $running.Output -match '(^|\r?\n)(namenode|datanode)(\r?\n|$)') {
    throw "NameNode or DataNode ran despite the failed volume-init dependency: $($running.Output)"
  }

  Write-Output "PASS: Compose failed on the isolated permission error and kept NameNode/DataNode stopped."
  Write-Output $logs.Output
}
finally {
  $down = Invoke-Compose -Arguments @('down')
  if ($down.ExitCode -ne 0) { Write-Warning "Could not stop isolated test containers: $($down.Output)" }
  Pop-Location
}
