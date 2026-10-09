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
    $ErrorActionPreference = 'Continue'
    $output = & docker @dockerArguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Get-WebHdfsStatus {
  $url = 'http://127.0.0.1:9870/webhdfs/v1/demo?op=LISTSTATUS&user.name=hadoop'
  $status = Invoke-Compose -Arguments @(
    'exec', '-T', 'namenode', 'curl', '--silent', '--show-error',
    '--output', '/dev/null', '--write-out', '%{http_code}', $url
  )
  if ($status.ExitCode -ne 0 -or $status.Output -ne '200') {
    throw "WebHDFS LISTSTATUS failed (exit $($status.ExitCode), HTTP '$($status.Output)')."
  }
  $body = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'curl', '--fail', '--silent', '--show-error', $url)
  if ($body.ExitCode -ne 0) {
    throw "WebHDFS response body failed (exit $($body.ExitCode)): $($body.Output)"
  }
  $body.Output | ConvertFrom-Json
}

Push-Location $demoRoot
try {
  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -ne 0) {
    throw "Test HDFS project did not start (exit $($start.ExitCode)): $($start.Output)"
  }

  $prepare = Invoke-Compose -Arguments @(
    'exec', '-T', 'namenode', 'bash', '-ec',
    "hdfs dfs -mkdir -p /demo; if ! hdfs dfs -test -e /demo/apache-knox.txt; then printf 'preserve-from-phase01-test' | hdfs dfs -put - /demo/apache-knox.txt; fi"
  )
  if ($prepare.ExitCode -ne 0) {
    throw "Could not prepare isolated existing-file fixture (exit $($prepare.ExitCode)): $($prepare.Output)"
  }

  $preservedBefore = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfs', '-cat', '/demo/apache-knox.txt')
  if ($preservedBefore.ExitCode -ne 0 -or $preservedBefore.Output -ne 'preserve-from-phase01-test') {
    throw "Isolated existing-file fixture is invalid: $($preservedBefore.Output)"
  }
  $before = Get-WebHdfsStatus
  $beforeItem = @($before.FileStatuses.FileStatus | Where-Object pathSuffix -eq 'apache-knox.txt')
  if ($beforeItem.Count -ne 1) { throw 'Existing file fixture is missing from WebHDFS LISTSTATUS.' }

  $seedScript = Join-Path $demoRoot 'scripts\Seed-HdfsDemo.ps1'
  if (-not (Test-Path -LiteralPath $seedScript)) {
    throw "Expected seed behavior is missing: $seedScript has not been implemented."
  }
  & $seedScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  & $seedScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds

  $preservedAfter = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'hdfs', 'dfs', '-cat', '/demo/apache-knox.txt')
  if ($preservedAfter.ExitCode -ne 0 -or $preservedAfter.Output -ne 'preserve-from-phase01-test') {
    throw "Seed rerun overwrote the pre-existing HDFS file: $($preservedAfter.Output)"
  }
  $after = Get-WebHdfsStatus
  $items = @($after.FileStatuses.FileStatus)
  $names = @($items | ForEach-Object { $_.pathSuffix } | Sort-Object)
  $expectedNames = @('apache-knox.txt', 'bigdata.txt')
  if (($names -join '|') -ne ($expectedNames -join '|')) {
    throw "Expected exactly the two seed files; WebHDFS returned: $($names -join ', ')"
  }
  $afterItem = @($items | Where-Object pathSuffix -eq 'apache-knox.txt')
  if ($afterItem.Count -ne 1 -or [long]$afterItem[0].modificationTime -ne [long]$beforeItem[0].modificationTime) {
    throw 'Seed rerun changed the existing file metadata or created an unexpected duplicate.'
  }

  Write-Output "PASS: seed reruns preserve existing content and modification time; WebHDFS returned exactly $($names -join ', ')."
}
finally {
  Pop-Location
}
