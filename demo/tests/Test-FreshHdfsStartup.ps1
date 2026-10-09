[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^knox-p01-[a-z0-9-]+$')]
  [string]$ProjectName,

  [ValidateRange(30, 600)]
  [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @(
  '-p', $ProjectName,
  '-f', 'docker-compose.yml',
  '-f', 'docker-compose.phase01-test.yml'
)

function Invoke-Compose {
  param([string[]]$Arguments)
  $dockerArguments = @('compose') + $script:composePrefix + $Arguments
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    # Windows PowerShell 5.1 promotes Docker's normal stderr progress lines to
    # NativeCommandError; capture them and rely on the process exit code.
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
  if ($start.ExitCode -ne 0) {
    $logs = Invoke-Compose -Arguments @('logs', '--tail=80', 'namenode', 'datanode')
    throw "Fresh-volume Compose startup failed (exit $($start.ExitCode)).`n$($start.Output)`n$($logs.Output)"
  }

  $report = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfsadmin', '-report')
  if ($report.ExitCode -ne 0 -or $report.Output -notmatch 'Live datanodes \(1\)') {
    $logs = Invoke-Compose -Arguments @('logs', '--tail=80', 'namenode', 'datanode')
    throw "Fresh-volume HDFS readiness failed (exit $($report.ExitCode)).`n$($report.Output)`n$($logs.Output)"
  }

  $http = Invoke-Compose -Arguments @(
    'exec', '-T', 'namenode', 'curl', '--silent', '--show-error', '--location',
    '--output', '/dev/null', '--write-out', '%{http_code}', 'http://127.0.0.1:9870/'
  )
  if ($http.ExitCode -ne 0 -or $http.Output -ne '200') {
    throw "Fresh-volume NameNode HTTP probe failed (exit $($http.ExitCode), status '$($http.Output)')."
  }

  Write-Output "PASS: fresh project '$ProjectName' has NameNode HTTP 200 and Live datanodes (1)."
  Write-Output 'The isolated project is left running for inspection; its named volumes are not removed.'
}
finally {
  Pop-Location
}
