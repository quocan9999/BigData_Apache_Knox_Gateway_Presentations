[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^knox-p01-[a-z0-9-]+$')]
  [string]$ProjectName
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
    $ErrorActionPreference = 'Continue'
    $output = & docker @dockerArguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

$readyScript = Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1'
Push-Location $demoRoot
try {
  $stop = Invoke-Compose -Arguments @('stop', 'datanode')
  if ($stop.ExitCode -ne 0) { throw "Could not stop isolated test DataNode: $($stop.Output)" }
  if (-not (Test-Path -LiteralPath $readyScript)) {
    throw "Expected failure behavior is missing: $readyScript has not been implemented."
  }

  $failedAsExpected = $false
  try {
    & $readyScript -ProjectName $ProjectName -TimeoutSeconds 8 -PollIntervalSeconds 2
  }
  catch {
    if ($_.Exception.Message -match 'Timed out waiting for HDFS readiness') {
      $failedAsExpected = $true
      Write-Output "PASS: readiness rejected a stopped DataNode: $($_.Exception.Message)"
    }
    else {
      throw "Readiness failed for an unexpected reason: $($_.Exception.Message)"
    }
  }
  if (-not $failedAsExpected) { throw 'Readiness incorrectly passed while the DataNode was stopped.' }
}
finally {
  $start = Invoke-Compose -Arguments @('start', 'datanode')
  if ($start.ExitCode -ne 0) { throw "Could not restore isolated test DataNode: $($start.Output)" }
  if (Test-Path -LiteralPath $readyScript) {
    & $readyScript -ProjectName $ProjectName -TimeoutSeconds 120 -PollIntervalSeconds 2
  }
  Pop-Location
}
