[CmdletBinding()]
param(
  [string]$ProjectName = 'apache-knox-bigdata-demo',

  [ValidateRange(30, 600)]
  [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @(
  'compose', '-p', $ProjectName,
  '-f', 'docker-compose.yml',
  '-f', 'docker-compose.knox.yml'
)
$readinessFailureComposePrefix = $composePrefix + @('-f', 'tests/fixtures/docker-compose.knox-healthcheck-failure.yml')
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("knox-p05-failure-" + [Guid]::NewGuid().ToString('N'))
$gatewayAuditPath = '/home/knox/knox/logs/gateway-audit.log'
$gatewayLogPath = '/home/knox/knox/logs/gateway.log'
$restoreError = $null

function Invoke-Compose {
  param(
    [string[]]$Arguments,
    [switch]$ReadinessFailure
  )
  $prefix = if ($ReadinessFailure) { $script:readinessFailureComposePrefix } else { $script:composePrefix }
  $dockerArguments = $prefix + $Arguments
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

function Invoke-KnoxRequest {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Username,
    [Parameter(Mandatory)][string]$Password,
    [ValidateRange(1, 120)][int]$RequestTimeoutSeconds = 20
  )
  $tag = [Guid]::NewGuid().ToString('N')
  $bodyPath = Join-Path $script:testDirectory "$tag.body"
  $headersPath = Join-Path $script:testDirectory "$tag.headers"
  $url = 'https://127.0.0.1:8443' + $Path
  $arguments = @(
    '--noproxy', '*', '--insecure', '--silent', '--show-error', '--max-time', "$RequestTimeoutSeconds",
    '--dump-header', $headersPath, '--output', $bodyPath, '--write-out', '%{http_code}',
    '--user', ($Username + ':' + $Password), $url
  )
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & curl.exe @arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $outputText = ($output | Out-String).Trim()
  $statusMatch = [regex]::Match($outputText, '(\d{3})\s*$')
  $statusCode = if ($statusMatch.Success) { $statusMatch.Groups[1].Value } else { 'not returned' }
  $body = if (Test-Path -LiteralPath $bodyPath) { Get-Content -Raw -LiteralPath $bodyPath } else { '' }
  $headers = if (Test-Path -LiteralPath $headersPath) { Get-Content -Raw -LiteralPath $headersPath } else { '' }
  [pscustomobject]@{
    ExitCode = $exitCode
    StatusCode = $statusCode
    Body = $body
    Headers = $headers
    Output = $outputText
  }
}

function Assert-WebHdfsList {
  param(
    [Parameter(Mandatory)][pscustomobject]$Response,
    [Parameter(Mandatory)][string]$Label
  )
  if ($Response.ExitCode -ne 0 -or $Response.StatusCode -ne '200') {
    throw "$Label failed (curl exit $($Response.ExitCode), HTTP '$($Response.StatusCode)'): $($Response.Body)"
  }
  try { $json = $Response.Body | ConvertFrom-Json }
  catch { throw "$Label did not return valid WebHDFS JSON: $($Response.Body)" }
  $names = @($json.FileStatuses.FileStatus | ForEach-Object { $_.pathSuffix } | Sort-Object)
  if (($names -join '|') -ne 'apache-knox.txt|bigdata.txt') {
    throw "$Label returned unexpected HDFS paths: $($names -join ', ')"
  }
  Write-Output "$Label PASS: HTTP 200 WebHDFS JSON contains $($names -join ', ')."
}

function Get-GatewayLogLineCount {
  param([string]$Path)
  $count = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'wc', '-l', $Path)
  if ($count.ExitCode -ne 0) { throw "Could not capture the Knox log offset for path '$Path': $($count.Output)" }
  [int](($count.Output -split '\s+')[0])
}

function Get-GatewayLogSince {
  param([int]$StartLine, [string]$Path)
  Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'tail', '-n', "+$($StartLine + 1)", $Path)
}

function Assert-FreshAudit {
  param([int]$StartLine, [string]$Pattern, [string]$Label)
  $result = Get-GatewayLogSince -StartLine $StartLine -Path $script:gatewayAuditPath
  if ($result.ExitCode -ne 0) { throw "$Label could not read fresh Knox audit: $($result.Output)" }
  $auditMatches = @($result.Output -split '\r?\n' | Where-Object { $_ -match $Pattern })
  if ($auditMatches.Count -eq 0) {
    throw "$Label lacks the expected audit event after line $StartLine. Expected pattern: $Pattern. Fresh audit: $($result.Output)"
  }
  Write-Output "$Label audit evidence:"
  Write-Output $auditMatches[-1]
}

function Invoke-AdminList {
  Invoke-KnoxRequest -Path '/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS' -Username 'admin' -Password 'admin-password'
}

New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
Push-Location $demoRoot
try {
  $config = Invoke-Compose -Arguments @('config', '--quiet')
  if ($config.ExitCode -ne 0 -or $config.Output -match 'level=warning|variable is not set') {
    throw "Compose config failed (exit $($config.ExitCode)): $($config.Output)"
  }
  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -ne 0) {
    $states = Invoke-Compose -Arguments @('ps', '-a')
    $logs = Invoke-Compose -Arguments @('logs', '--tail=100', 'namenode', 'knox-gateway', 'knox-ldap')
    throw "Stack did not become ready (exit $($start.ExitCode)). $($states.Output) $($logs.Output)"
  }
  & (Join-Path $demoRoot 'scripts\Seed-HdfsDemo.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay
  & (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay
  & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  Assert-WebHdfsList -Response (Invoke-AdminList) -Label 'Baseline before failure injection'

  Write-Output 'INJECTION MISSING_ROUTE START'
  $missingRoutePath = '/gateway/demo/missing-service/v1/demo?op=LISTSTATUS'
  $missingRouteAuditStart = Get-GatewayLogLineCount -Path $gatewayAuditPath
  $missingRoute = Invoke-KnoxRequest -Path $missingRoutePath -Username 'admin' -Password 'admin-password'
  if ($missingRoute.ExitCode -ne 0 -or $missingRoute.StatusCode -ne '404' -or
      $missingRoute.Body -match 'FileStatuses|apache-knox\.txt|bigdata\.txt') {
    throw "Missing service route did not fail at Knox with HTTP 404 and no HDFS listing (curl exit $($missingRoute.ExitCode), HTTP '$($missingRoute.StatusCode)'): $($missingRoute.Body)"
  }
  $missingRouteAuditPattern = '\|access\|uri\|/gateway/demo/missing-service/v1/demo\?op=LISTSTATUS\|success\|Response status: 404'
  Assert-FreshAudit -StartLine $missingRouteAuditStart -Pattern $missingRouteAuditPattern -Label 'Missing-route 404'
  Write-Output "INJECTION MISSING_ROUTE PASS: measured HTTP 404 for $missingRoutePath; Knox access audit records the URI and response."

  Write-Output 'INJECTION BACKEND_DOWN_AND_RECOVERY START'
  $gatewayLogStart = Get-GatewayLogLineCount -Path $gatewayLogPath
  $backendAuditStart = Get-GatewayLogLineCount -Path $gatewayAuditPath
  $stopNameNode = Invoke-Compose -Arguments @('stop', 'namenode')
  if ($stopNameNode.ExitCode -ne 0) { throw "Could not stop NameNode for backend-down injection: $($stopNameNode.Output)" }
  $backendDown = Invoke-AdminList
  if ($backendDown.ExitCode -ne 0 -or $backendDown.StatusCode -ne '500' -or
      $backendDown.Body -match 'FileStatuses|apache-knox\.txt|bigdata\.txt') {
    throw "Knox did not return measured HTTP 500 without HDFS listing while NameNode was stopped (curl exit $($backendDown.ExitCode), HTTP '$($backendDown.StatusCode)'): $($backendDown.Body)"
  }
  $backendDispatchPattern = '\|WEBHDFS\|admin\|\|\|dispatch\|uri\|http://namenode:9870/webhdfs/v1/demo\?op=LISTSTATUS&user\.name=admin\|unavailable\|Request method: GET'
  Assert-FreshAudit -StartLine $backendAuditStart -Pattern $backendDispatchPattern -Label 'Backend-down dispatch failure'
  $backendLogs = Get-GatewayLogSince -StartLine $gatewayLogStart -Path $gatewayLogPath
  $connectivityPattern = 'ConnectException|Connection refused|NoRouteToHostException|NoHttpResponseException|SocketTimeoutException|UnknownHostException'
  $connectivityMatches = @($backendLogs.Output -split '\r?\n' | Where-Object { $_ -match $connectivityPattern })
  if ($backendLogs.ExitCode -ne 0 -or $connectivityMatches.Count -eq 0) {
    throw "NameNode was stopped and Knox returned HTTP '$($backendDown.StatusCode)', but fresh Knox connectivity evidence was missing: $($backendLogs.Output | Select-Object -Last 20 | Out-String)"
  }
  Write-Output "Backend connectivity log: $($connectivityMatches[0].Trim())"
  Write-Output "INJECTION BACKEND_DOWN PASS: NameNode was stopped; Knox returned HTTP '$($backendDown.StatusCode)' without HDFS JSON and logged a failed dispatch."

  $restoreNameNode = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds", 'namenode')
  if ($restoreNameNode.ExitCode -ne 0) { throw "NameNode did not restart after backend-down injection: $($restoreNameNode.Output)" }
  & (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay
  & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  Assert-WebHdfsList -Response (Invoke-AdminList) -Label 'Recovery after backend-down injection'
  Write-Output 'INJECTION BACKEND_RECOVERY PASS: NameNode and Knox are ready and admin again receives both real HDFS files.'
  Write-Output 'INJECTION BACKEND_DOWN_AND_RECOVERY PASS: backend failure returned HTTP 500 with an unavailable audit and the real route recovered.'

  Write-Output 'INJECTION READINESS_TIMEOUT_AND_RECOVERY START'
  $stopGateway = Invoke-Compose -Arguments @('stop', 'knox-gateway')
  if ($stopGateway.ExitCode -ne 0) { throw "Could not stop Knox Gateway for readiness-timeout injection: $($stopGateway.Output)" }
  $readinessFailure = Invoke-Compose -Arguments @('up', '-d', '--force-recreate', '--wait', '--wait-timeout', '5', 'knox-gateway') -ReadinessFailure
  if ($readinessFailure.ExitCode -eq 0 -or
      $readinessFailure.Output -notmatch 'timed out|timeout|unhealthy|application not healthy|failed to start|failed to become healthy') {
    throw "Five-second Compose readiness check did not fail with a measured health/timeout diagnostic (exit $($readinessFailure.ExitCode)): $($readinessFailure.Output)"
  }
  Write-Output "INJECTION READINESS_TIMEOUT PASS: Compose returned exit $($readinessFailure.ExitCode) for the five-second failing-healthcheck probe: $($readinessFailure.Output)"

  $restoreGateway = Invoke-Compose -Arguments @('up', '-d', '--force-recreate', '--wait', '--wait-timeout', "$TimeoutSeconds", 'knox-gateway')
  if ($restoreGateway.ExitCode -ne 0) { throw "Knox Gateway did not recover after readiness-timeout injection: $($restoreGateway.Output)" }
  & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  Assert-WebHdfsList -Response (Invoke-AdminList) -Label 'Recovery after readiness-timeout injection'
  Write-Output 'INJECTION READINESS_RECOVERY PASS: normal Knox readiness and admin WebHDFS request recovered.'
  Write-Output 'INJECTION READINESS_TIMEOUT_AND_RECOVERY PASS: failing healthcheck timed out and default Knox readiness recovered.'
}
finally {
  Write-Output 'INJECTION FINAL_STACK_RECOVERY START'
  try {
    $restore = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
    if ($restore.ExitCode -ne 0) {
      $restoreError = "Final Compose recovery failed (exit $($restore.ExitCode)): $($restore.Output)"
      Write-Warning $restoreError
    }
    else {
      & (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay
      & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
      Assert-WebHdfsList -Response (Invoke-AdminList) -Label 'Final stack recovery'
      Write-Output 'Stack recovery PASS: all Compose services are healthy and admin can list both HDFS files.'
      Write-Output 'INJECTION FINAL_STACK_RECOVERY PASS: all services are healthy and the real admin listing works after the suite.'
    }
  }
  catch {
    $restoreError = "Final stack recovery could not be confirmed: $($_.Exception.Message)"
    Write-Warning $restoreError
  }
  Pop-Location
  Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not [string]::IsNullOrWhiteSpace($restoreError)) {
  throw $restoreError
}
Write-Output 'Failure injection phase test PASS.'
