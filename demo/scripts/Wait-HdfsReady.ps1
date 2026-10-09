[CmdletBinding()]
param(
  [string]$ProjectName = 'apache-knox-bigdata-demo',

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 180,

  [ValidateRange(1, 30)]
  [int]$PollIntervalSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @('compose', '-p', $ProjectName)

function Invoke-Compose {
  param([string[]]$Arguments)
  $dockerArguments = $script:composePrefix + $Arguments
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    # Windows PowerShell 5.1 can promote native stderr progress to an error;
    # process exit codes remain the authority for Docker/Hadoop commands.
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
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  $lastHttp = $null
  $lastDatanode = $null
  $lastReport = $null
  $liveCount = 'unknown'

  while ([DateTime]::UtcNow -lt $deadline) {
    $lastHttp = Invoke-Compose -Arguments @(
      'exec', '-T', 'namenode', 'curl', '--silent', '--show-error',
      '--output', '/dev/null', '--write-out', '%{http_code}', 'http://127.0.0.1:9870/dfshealth.html'
    )
    $lastDatanode = Invoke-Compose -Arguments @('ps', '--status', 'running', '--services', 'datanode')
    $lastReport = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfsadmin', '-report')
    if ($lastReport.Output -match 'Live datanodes\s+\((\d+)\)') { $liveCount = $Matches[1] }
    $runningDatanodes = @($lastDatanode.Output -split '\r?\n' | Where-Object { $_ -eq 'datanode' })

    if ($lastHttp.ExitCode -eq 0 -and $lastHttp.Output -eq '200' -and
        $lastDatanode.ExitCode -eq 0 -and $runningDatanodes.Count -eq 1 -and
        $lastReport.ExitCode -eq 0 -and $lastReport.Output -match 'Live datanodes\s+\(1\):') {
      Write-Output 'HDFS readiness PASS: NameNode HTTP 200 and one live DataNode confirmed by dfsadmin -report.'
      return
    }

    $remaining = ($deadline - [DateTime]::UtcNow).TotalSeconds
    if ($remaining -le 0) { break }
    Start-Sleep -Seconds ([Math]::Max(1, [Math]::Min($PollIntervalSeconds, [Math]::Ceiling($remaining))))
  }

  $httpCode = if ($null -eq $lastHttp) { 'not checked' } else { $lastHttp.Output }
  $httpExit = if ($null -eq $lastHttp) { 'n/a' } else { $lastHttp.ExitCode }
  $datanodeState = if ($null -eq $lastDatanode -or [string]::IsNullOrWhiteSpace($lastDatanode.Output)) { 'not running' } else { $lastDatanode.Output }
  $reportExit = if ($null -eq $lastReport) { 'n/a' } else { $lastReport.ExitCode }
  throw "Timed out waiting for HDFS readiness after ${TimeoutSeconds}s (NameNode HTTP '$httpCode', probe exit $httpExit; DataNode service '$datanodeState'; dfsadmin exit $reportExit; live DataNodes '$liveCount')."
}
finally {
  Pop-Location
}
