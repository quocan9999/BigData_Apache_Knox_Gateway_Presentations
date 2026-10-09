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

function Invoke-Compose {
  param([string[]]$Arguments)
  Invoke-Docker -Arguments (@('compose') + $script:composePrefix + $Arguments)
}

function Get-RunningContainerIds {
  $result = Invoke-Compose -Arguments @('ps', '--status', 'running', '-q')
  if ($result.ExitCode -ne 0) {
    throw "Could not inspect running containers for '$ProjectName': $($result.Output)"
  }
  @($result.Output -split '\r?\n' | Where-Object { $_ } | Sort-Object)
}

Push-Location $demoRoot
try {
  $config = Invoke-Compose -Arguments @('config', '--format', 'json')
  if ($config.ExitCode -ne 0) {
    throw "Could not resolve Compose named volumes for '$ProjectName': $($config.Output)"
  }
  try { $model = $config.Output | ConvertFrom-Json }
  catch { throw "Compose did not return valid JSON for '$ProjectName': $($config.Output)" }

  $expectedVolumes = @(
    [string]$model.volumes.hdfs_namenode.name,
    [string]$model.volumes.hdfs_datanode.name
  )
  if ($expectedVolumes.Count -ne 2 -or @($expectedVolumes | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Compose did not resolve exactly two HDFS named volumes for '$ProjectName'."
  }
  $expectedPrefix = "${ProjectName}_"
  if (@($expectedVolumes | Where-Object { -not $_.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal) }).Count -gt 0) {
    throw "Compose HDFS volume names do not use project prefix '$expectedPrefix': $($expectedVolumes -join ', ')"
  }

  $volumeList = Invoke-Docker -Arguments @('volume', 'ls', '--format', '{{.Name}}')
  if ($volumeList.ExitCode -ne 0) {
    throw "Could not inspect Docker named volumes: $($volumeList.Output)"
  }
  $allVolumeNames = @($volumeList.Output -split '\r?\n' | Where-Object { $_ })
  $existingVolumes = @($expectedVolumes | Where-Object { $allVolumeNames -contains $_ })
  if ($existingVolumes.Count -ne 2) {
    throw "Guard regression requires both named volumes to exist. Found: $($existingVolumes -join ', '); expected: $($expectedVolumes -join ', ')"
  }

  $runningBefore = @(Get-RunningContainerIds)
  $powerShellPath = (Get-Process -Id $PID).Path
  if ([string]::IsNullOrWhiteSpace($powerShellPath) -or -not (Test-Path -LiteralPath $powerShellPath)) {
    $powerShellPath = 'powershell.exe'
  }
  $freshTestPath = Join-Path $PSScriptRoot 'Test-FreshHdfsStartup.ps1'
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $childOutput = & $powerShellPath -NoProfile -ExecutionPolicy Bypass -File $freshTestPath -ProjectName $ProjectName -TimeoutSeconds 30 2>&1
    $childExitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $childText = ($childOutput | Out-String).Trim()
  $runningAfter = @(Get-RunningContainerIds)
  $containerStateChanged = ($runningBefore -join '|') -ne ($runningAfter -join '|')
  if ($containerStateChanged -and $runningBefore.Count -eq 0 -and $runningAfter.Count -gt 0) {
    $stop = Invoke-Compose -Arguments @('stop')
    if ($stop.ExitCode -ne 0) {
      Write-Warning "Guard test cleanup could not stop '$ProjectName'; named volumes were left intact: $($stop.Output)"
    }
    else {
      $runningAfter = @(Get-RunningContainerIds)
    }
  }

  if ($childExitCode -eq 0) {
    throw "Fresh-start test reported success despite existing named volumes: $($expectedVolumes -join ', '). Output: $childText"
  }
  if ($childText -notmatch 'Fresh-volume preflight refused existing named volumes') {
    throw "Fresh-start test failed for a reason other than the existing-volume guard: $childText"
  }
  foreach ($volumeName in $expectedVolumes) {
    if ($childText -notmatch [regex]::Escape($volumeName)) {
      throw "Fresh-start guard did not identify existing volume '$volumeName': $childText"
    }
  }

  if (($runningBefore -join '|') -ne ($runningAfter -join '|')) {
    throw "Fresh-start guard changed running container state for '$ProjectName'."
  }

  Write-Output "PASS: fresh-start guard refused both existing volumes without changing container state: $($expectedVolumes -join ', ')."
}
finally {
  Pop-Location
}
