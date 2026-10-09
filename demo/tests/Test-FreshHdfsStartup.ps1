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

function Invoke-Docker {
  param([string[]]$Arguments)
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & docker @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

Push-Location $demoRoot
try {
  $config = Invoke-Compose -Arguments @('config', '--format', 'json')
  if ($config.ExitCode -ne 0 -or $config.Output -match 'level=warning|variable is not set') {
    throw "Compose config failed (exit $($config.ExitCode)): $($config.Output)"
  }
  try { $model = $config.Output | ConvertFrom-Json }
  catch { throw "Compose did not return valid JSON for named-volume preflight: $($config.Output)" }

  $freshVolumes = @(
    [string]$model.volumes.hdfs_namenode.name,
    [string]$model.volumes.hdfs_datanode.name
  )
  if ($freshVolumes.Count -ne 2 -or @($freshVolumes | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Compose did not resolve exactly two HDFS named volumes for project '$ProjectName'."
  }
  $expectedPrefix = "${ProjectName}_"
  if (@($freshVolumes | Where-Object { -not $_.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal) }).Count -gt 0) {
    throw "Fresh project volume prefix mismatch; expected '$expectedPrefix*' but Compose resolved: $($freshVolumes -join ', ')"
  }

  $volumeList = Invoke-Docker -Arguments @('volume', 'ls', '--format', '{{.Name}}')
  if ($volumeList.ExitCode -ne 0) {
    throw "Could not inspect Docker volumes (exit $($volumeList.ExitCode)): $($volumeList.Output)"
  }
  $allVolumeNames = @($volumeList.Output -split '\r?\n' | Where-Object { $_ })
  $existingVolumes = @($freshVolumes | Where-Object { $allVolumeNames -contains $_ })
  if ($existingVolumes.Count -gt 0) {
    throw "Fresh-volume preflight refused existing named volumes: $($existingVolumes -join ', '). Choose a different project name; volumes are never removed by this test."
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

  $freshFilePath = "/demo/fresh-startup-$([Guid]::NewGuid().ToString('N')).txt"
  $mkdir = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfs', '-mkdir', '-p', '/demo')
  if ($mkdir.ExitCode -ne 0) { throw "Could not create the fresh HDFS data path /demo: $($mkdir.Output)" }
  $touch = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfs', '-touchz', $freshFilePath)
  if ($touch.ExitCode -ne 0) { throw "Could not write to the fresh HDFS data path '$freshFilePath': $($touch.Output)" }
  $verifyFile = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfs', '-test', '-f', $freshFilePath)
  if ($verifyFile.ExitCode -ne 0) { throw "Fresh HDFS data path did not retain '$freshFilePath': $($verifyFile.Output)" }

  Write-Output "PASS: fresh project '$ProjectName' used absent volumes '$($freshVolumes -join ', ')', reached NameNode HTTP 200 with one live DataNode, and wrote '$freshFilePath'."
  Write-Output 'The isolated project is left running for inspection; its named volumes are not removed.'
}
finally {
  Pop-Location
}
