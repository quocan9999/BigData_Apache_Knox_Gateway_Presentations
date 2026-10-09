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
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("knox-p02-" + [Guid]::NewGuid().ToString('N'))
$gatewayAuditPath = '/home/knox/knox/logs/gateway-audit.log'
$ldapStopped = $false

function Invoke-Compose {
  param([string[]]$Arguments)
  $dockerArguments = $script:composePrefix + $Arguments
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    # Windows PowerShell 5.1 can promote Docker's normal stderr progress to an
    # error; use the native process exit code as the authority.
    $ErrorActionPreference = 'Continue'
    $output = & docker @dockerArguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Get-GatewayAuditLineCount {
  $result = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'wc', '-l', $script:gatewayAuditPath)
  if ($result.ExitCode -ne 0) { throw "Could not capture the Knox audit offset: $($result.Output)" }
  [int](($result.Output -split '\s+')[0])
}

function Get-GatewayAuditSince {
  param([int]$StartLine)
  Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'tail', '-n', "+$($StartLine + 1)", $script:gatewayAuditPath)
}

function Invoke-KnoxRequest {
  param(
    [string]$Username,
    [string]$Password,
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 15
  )
  $tag = [Guid]::NewGuid().ToString('N')
  $bodyPath = Join-Path $script:testDirectory "$tag.body"
  $headersPath = Join-Path $script:testDirectory "$tag.headers"
  $arguments = @('--insecure', '--silent', '--show-error', '--max-time', "$TimeoutSeconds", '--dump-header', $headersPath,
    '--output', $bodyPath, '--write-out', '%{http_code}')
  if ($PSBoundParameters.ContainsKey('Username')) {
    $arguments += @('--user', "${Username}:$Password")
  }
  $arguments += 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & curl.exe @arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  $body = if (Test-Path -LiteralPath $bodyPath) { Get-Content -Raw -LiteralPath $bodyPath } else { '' }
  $headers = if (Test-Path -LiteralPath $headersPath) { Get-Content -Raw -LiteralPath $headersPath } else { '' }
  $outputText = ($output | Out-String).Trim()
  $statusMatch = [regex]::Match($outputText, '(\d{3})\s*$')
  $statusCode = if ($statusMatch.Success) { $statusMatch.Groups[1].Value } else { 'not returned' }
  [pscustomobject]@{
    ExitCode = $exitCode
    StatusCode = $statusCode
    Body = $body
    Headers = $headers
    Output = $outputText
  }
}

function Invoke-ValidRequest {
  param(
    [Parameter(Mandatory)][string]$Label,
    [ValidateRange(0, 120)][int]$RetryTimeoutSeconds = 0
  )
  $deadline = [DateTime]::UtcNow.AddSeconds($RetryTimeoutSeconds)
  $attempt = 0
  while ($true) {
    $attempt++
    $response = Invoke-KnoxRequest -Username 'admin' -Password 'admin-password'
    if ($response.ExitCode -eq 0 -and $response.StatusCode -eq '200') { break }
    if ($RetryTimeoutSeconds -eq 0 -or [DateTime]::UtcNow -ge $deadline) {
      throw "$Label failed after $attempt attempt(s) (curl exit $($response.ExitCode), HTTP '$($response.StatusCode)'): $($response.Body)"
    }
    Write-Output "$Label is not ready yet (attempt $attempt, curl exit $($response.ExitCode), HTTP '$($response.StatusCode)'); retrying for up to $RetryTimeoutSeconds seconds."
    Start-Sleep -Seconds 2
  }
  try {
    $json = $response.Body | ConvertFrom-Json
  }
  catch {
    throw "$Label did not return JSON: $($response.Body)"
  }
  $names = @($json.FileStatuses.FileStatus | ForEach-Object { $_.pathSuffix } | Sort-Object)
  $expected = @('apache-knox.txt', 'bigdata.txt')
  if (($names -join '|') -ne ($expected -join '|')) {
    throw "$Label returned unexpected WebHDFS paths: $($names -join ', ')"
  }
  $attemptSummary = if ($attempt -gt 1) { " after $attempt attempts" } else { '' }
  Write-Output "$Label PASS${attemptSummary}: HTTP 200 and real WebHDFS JSON contains $($names -join ', ')."
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
    $logs = Invoke-Compose -Arguments @('logs', '--tail=100', 'knox-gateway', 'knox-ldap')
    throw "Knox/LDAP startup failed (exit $($start.ExitCode)).`n$($start.Output)`n$($logs.Output)"
  }

  $seedScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Seed-HdfsDemo.ps1'
  & $seedScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay

  $readyScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Wait-KnoxReady.ps1'
  & $readyScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds

  $unauthenticated = Invoke-KnoxRequest
  if ($unauthenticated.ExitCode -ne 0 -or $unauthenticated.StatusCode -ne '401' -or
      $unauthenticated.Headers -notmatch '(?im)^WWW-Authenticate:\s*Basic') {
    throw "Unauthenticated request did not receive Knox's Basic challenge (curl exit $($unauthenticated.ExitCode), HTTP '$($unauthenticated.StatusCode)')."
  }
  Write-Output 'PASS: unauthenticated HTTPS request received the Knox Basic challenge (HTTP 401).'

  Invoke-ValidRequest -Label 'Valid LDAP account'

  $invalidLogCountResult = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'wc', '-l', '/home/knox/knox/logs/gateway.log')
  if ($invalidLogCountResult.ExitCode -ne 0) { throw "Could not capture the Gateway log offset: $($invalidLogCountResult.Output)" }
  $invalidLogStart = [int](($invalidLogCountResult.Output -split '\s+')[0])
  Write-Output 'SCREEN B START'
  $invalidAuditStart = Get-GatewayAuditLineCount
  $invalid = Invoke-KnoxRequest -Username 'admin' -Password 'wrong-password'
  if ($invalid.ExitCode -ne 0 -or $invalid.StatusCode -ne '401' -or
      $invalid.Headers -notmatch '(?im)^WWW-Authenticate:\s*Basic') {
    throw "Invalid LDAP password was not rejected with an authentication challenge (curl exit $($invalid.ExitCode), HTTP '$($invalid.StatusCode)')."
  }
  $invalidLogs = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'tail', '-n', "+$($invalidLogStart + 1)", '/home/knox/knox/logs/gateway.log')
  if ($invalidLogs.ExitCode -ne 0 -or $invalidLogs.Output -notmatch 'INVALID_CREDENTIALS') {
    throw "HTTP 401 was returned, but Knox's LDAP invalid-credential log evidence was missing: $($invalidLogs.Output)"
  }
  $invalidAudit = Get-GatewayAuditSince -StartLine $invalidAuditStart
  $invalidAuditPattern = '\|WEBHDFS\|\|\|\|authentication\|principal\|admin\|failure\|LDAP authentication failed\.'
  if ($invalidAudit.ExitCode -ne 0 -or $invalidAudit.Output -notmatch $invalidAuditPattern) {
    throw "HTTP 401 and INVALID_CREDENTIALS were observed, but the fresh Knox authentication/principal/admin/failure audit event was missing: $($invalidAudit.Output)"
  }
  Write-Output 'PASS: wrong password was rejected at Knox with HTTP 401 and a Basic challenge.'
  Write-Output $invalidLogs.Output
  Write-Output 'SCREEN B PASS: Knox rejected the invalid password with HTTP 401, INVALID_CREDENTIALS, and an authentication failure audit event for principal admin.'
  Write-Output (($invalidAudit.Output -split '\r?\n' | Where-Object { $_ -match $invalidAuditPattern }) -join [Environment]::NewLine)

  $ldapLogCountResult = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'wc', '-l', '/home/knox/knox/logs/gateway.log')
  if ($ldapLogCountResult.ExitCode -ne 0) { throw "Could not capture the Gateway log offset: $($ldapLogCountResult.Output)" }
  $ldapLogStart = [int](($ldapLogCountResult.Output -split '\s+')[0])
  Write-Output 'REGRESSION LDAP_OUTAGE START'
  $stop = Invoke-Compose -Arguments @('stop', 'knox-ldap')
  if ($stop.ExitCode -ne 0) { throw "Could not stop LDAP for the negative test: $($stop.Output)" }
  $ldapStopped = $true

  $unavailable = Invoke-KnoxRequest -Username 'admin' -Password 'admin-password' -TimeoutSeconds 30
  if ($unavailable.ExitCode -eq 0 -and $unavailable.StatusCode -eq '200') {
    throw 'Knox accepted a request while the LDAP service was stopped.'
  }
  $ldapLogs = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'tail', '-n', "+$($ldapLogStart + 1)", '/home/knox/knox/logs/gateway.log')
  if ($ldapLogs.ExitCode -ne 0 -or $ldapLogs.Output -notmatch 'NoRouteToHostException|UnknownHostException|Connection refused|CommunicationException') {
    throw "LDAP outage was rejected, but fresh Knox connectivity evidence was missing: $($ldapLogs.Output)"
  }
  Write-Output "PASS: LDAP outage rejected valid credentials (curl exit $($unavailable.ExitCode), HTTP '$($unavailable.StatusCode)')."
  Write-Output 'LDAP outage log excerpt:'
  Write-Output $ldapLogs.Output

  $startLdap = Invoke-Compose -Arguments @('start', 'knox-ldap')
  if ($startLdap.ExitCode -ne 0) { throw "Could not restore LDAP after the negative test: $($startLdap.Output)" }
  $ldapStopped = $false

  & $readyScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  Invoke-ValidRequest -Label 'LDAP recovery' -RetryTimeoutSeconds 45
  Write-Output 'REGRESSION LDAP_OUTAGE PASS: valid credentials failed while LDAP was stopped, then authenticated successfully after LDAP recovery.'
}
finally {
  if ($ldapStopped) {
    $ErrorActionPreference = 'Continue'
    $restore = Invoke-Compose -Arguments @('start', 'knox-ldap')
    if ($restore.ExitCode -ne 0) { Write-Warning "Could not restore LDAP after test failure: $($restore.Output)" }
  }
  Pop-Location
  Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
