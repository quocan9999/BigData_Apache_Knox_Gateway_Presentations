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
$guestAllowedComposePrefix = $composePrefix + @('-f', 'docker-compose.knox-acl-test.yml')
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("knox-p03-" + [Guid]::NewGuid().ToString('N'))
$gatewayAuditPath = '/home/knox/knox/logs/gateway-audit.log'
$gatewayLogPath = '/home/knox/knox/logs/gateway.log'
$guestAllowedPolicyActive = $false

function Invoke-Compose {
  param(
    [string[]]$Arguments,
    [switch]$GuestAllowedPolicy
  )
  $prefix = if ($GuestAllowedPolicy) { $script:guestAllowedComposePrefix } else { $script:composePrefix }
  $dockerArguments = $prefix + $Arguments
  Write-Verbose ('Docker Compose arguments: ' + ($dockerArguments -join ' '))
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
    [Parameter(Mandatory)]
    [string]$Username,
    [Parameter(Mandatory)]
    [string]$Password,
    [ValidateRange(1, 120)]
    [int]$RequestTimeoutSeconds = 20
  )
  $tag = [Guid]::NewGuid().ToString('N')
  $bodyPath = Join-Path $script:testDirectory "$tag.body"
  $headersPath = Join-Path $script:testDirectory "$tag.headers"
  $arguments = @('--insecure', '--silent', '--show-error', '--max-time', "$RequestTimeoutSeconds", '--dump-header', $headersPath,
    '--output', $bodyPath, '--write-out', '%{http_code}', '--user', "${Username}:$Password",
    'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS')

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

function Assert-WebHdfsList {
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$Response,
    [Parameter(Mandatory)]
    [string]$Label
  )
  if ($Response.ExitCode -ne 0 -or $Response.StatusCode -ne '200') {
    throw "$Label did not reach WebHDFS (curl exit $($Response.ExitCode), HTTP '$($Response.StatusCode)'): $($Response.Body)"
  }
  try {
    $json = $Response.Body | ConvertFrom-Json
  }
  catch {
    throw "$Label did not return WebHDFS JSON: $($Response.Body)"
  }
  $names = @($json.FileStatuses.FileStatus | ForEach-Object { $_.pathSuffix } | Sort-Object)
  if (($names -join '|') -ne 'apache-knox.txt|bigdata.txt') {
    throw "$Label returned unexpected WebHDFS paths: $($names -join ', ')"
  }
  Write-Output "$Label PASS: HTTP 200 and real WebHDFS JSON contains $($names -join ', ')."
}

function Get-GatewayLogLineCount {
  param([string]$Path)
  $count = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'wc', '-l', $Path)
  if ($count.ExitCode -ne 0) { throw "Could not read the Knox log offset for $Path`: $($count.Output)" }
  [int](($count.Output -split '\s+')[0])
}

function Get-GatewayLogSince {
  param(
    [int]$StartLine,
    [string]$Path
  )
  Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'tail', '-n', "+$($StartLine + 1)", $Path)
}

function Assert-FreshGatewayAuditRecord {
  param(
    [Parameter(Mandatory)][int]$StartLine,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Label
  )
  $audit = Get-GatewayLogSince -StartLine $StartLine -Path $script:gatewayAuditPath
  if ($audit.ExitCode -ne 0) {
    throw "$Label could not read fresh Knox audit records: $($audit.Output)"
  }
  $auditMatches = @($audit.Output -split '\r?\n' | Where-Object { $_ -match $Pattern })
  if ($auditMatches.Count -eq 0) {
    throw "$Label lacked the required Knox audit fields in records after line $StartLine. Expected pattern: $Pattern. Fresh records: $($audit.Output)"
  }
  Write-Host "$Label audit PASS:"
  Write-Host $auditMatches[-1]
  return [string]$auditMatches[-1]
}

function Get-NameNodeListStatusAuditCount {
  $logs = Invoke-Compose -Arguments @('logs', '--no-color', '--since=30m', 'namenode')
  if ($logs.ExitCode -ne 0) { throw "Could not read NameNode audit logs: $($logs.Output)" }
  @($logs.Output -split '\r?\n' | Where-Object { $_ -match 'cmd=listStatus\s+src=/demo' }).Count
}

function Assert-TopologyMount {
  param([switch]$GuestAllowedPolicy)
  $config = Invoke-Compose -Arguments @('config', '--format', 'json') -GuestAllowedPolicy:$GuestAllowedPolicy
  if ($config.ExitCode -ne 0) {
    throw "Could not resolve Compose topology mount (exit $($config.ExitCode)): $($config.Output)"
  }
  try {
    $model = $config.Output | ConvertFrom-Json
  }
  catch {
    throw "Compose did not return a valid resolved JSON model: $($config.Output)"
  }

  $target = '/home/knox/knox/conf/topologies/demo.xml'
  $mounts = @($model.services.'knox-gateway'.volumes | Where-Object { $_.target -eq $target })
  if ($mounts.Count -ne 1) {
    throw "Expected exactly one Knox topology mount at '$target', found $($mounts.Count)."
  }

  $topologyName = if ($GuestAllowedPolicy) { 'demo-guest-allow.xml' } else { 'demo.xml' }
  $expectedSource = [System.IO.Path]::GetFullPath((Join-Path $script:demoRoot "knox\topologies\$topologyName"))
  $actualSource = [System.IO.Path]::GetFullPath([string]$mounts[0].source)
  if ($actualSource -ine $expectedSource) {
    throw "Compose resolved topology source '$actualSource'; expected '$expectedSource'."
  }
  Write-Output "Compose topology mount PASS: $topologyName -> $target."
}

function Assert-AclDenial {
  param(
    [Parameter(Mandatory)]
    [pscustomobject]$Response,
    [Parameter(Mandatory)]
    [string]$Principal,
    [Parameter(Mandatory)]
    [int]$GatewayAuditStart,
    [Parameter(Mandatory)]
    [int]$NameNodeAuditCountBefore
  )
  if ($Response.ExitCode -ne 0 -or $Response.StatusCode -ne '403') {
    throw "AclsAuthz denied principal '$Principal' with measured HTTP '$($Response.StatusCode)' (curl exit $($Response.ExitCode)); required demo status is 403. Headers: $($Response.Headers) Body: $($Response.Body)"
  }
  if ($Response.Headers -match '(?im)^WWW-Authenticate:\s*Basic') {
    throw "Principal '$Principal' received an authentication challenge instead of an authorization denial."
  }

  $auditPattern = ('\|WEBHDFS\|' + [regex]::Escape($Principal) + '\|\|\|authorization\|uri\|/gateway/demo/webhdfs/v1/demo\?op=LISTSTATUS\|failure\|')
  $auditRecord = Assert-FreshGatewayAuditRecord -StartLine $GatewayAuditStart -Pattern $auditPattern -Label "Authorization denial for '$Principal'"

  $nameNodeCountAfter = Get-NameNodeListStatusAuditCount
  if ($nameNodeCountAfter -gt $NameNodeAuditCountBefore) {
    throw "Knox denied '$Principal' with HTTP 403, but NameNode listStatus audit count increased from $NameNodeAuditCountBefore to $nameNodeCountAfter; origin denial is not proven."
  }
  Write-Host "PASS: AclsAuthz denied authenticated principal '$Principal' with HTTP 403, fresh Knox authorization-failure audit, and no new NameNode listStatus event."
  return $auditRecord
}

New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
Push-Location $demoRoot
try {
  Assert-TopologyMount
  $config = Invoke-Compose -Arguments @('config', '--quiet')
  if ($config.ExitCode -ne 0 -or $config.Output -match 'level=warning|variable is not set') {
    throw "Compose config failed (exit $($config.ExitCode)): $($config.Output)"
  }

  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -ne 0) {
    $states = Invoke-Compose -Arguments @('ps', '-a')
    $logs = Invoke-Compose -Arguments @('logs', '--tail=100', 'knox-gateway', 'knox-ldap')
    throw "Knox/LDAP startup failed (exit $($start.ExitCode)).`n$($start.Output)`n$($states.Output)`n$($logs.Output)"
  }

  $seedScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Seed-HdfsDemo.ps1'
  & $seedScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay

  $readyScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Wait-KnoxReady.ps1'
  & $readyScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds

  Write-Output 'SCREEN D START'
  $adminAuditStart = Get-GatewayLogLineCount -Path $script:gatewayAuditPath
  $adminBefore = Get-NameNodeListStatusAuditCount
  $admin = Invoke-KnoxRequest -Username 'admin' -Password 'admin-password'
  Assert-WebHdfsList -Response $admin -Label 'Authorized admin principal'
  $adminDispatchAuditPattern = '\|WEBHDFS\|admin\|\|\|dispatch\|uri\|http://namenode:9870/webhdfs/v1/demo\?op=LISTSTATUS&user\.name=admin\|success\|Response status: 200'
  $adminDispatchAudit = Assert-FreshGatewayAuditRecord -StartLine $adminAuditStart -Pattern $adminDispatchAuditPattern -Label 'Authorized admin WebHDFS dispatch'
  $adminAccessAuditPattern = '\|WEBHDFS\|admin\|\|\|access\|uri\|/gateway/demo/webhdfs/v1/demo\?op=LISTSTATUS\|success\|Response status: 200'
  $adminAccessAudit = Assert-FreshGatewayAuditRecord -StartLine $adminAuditStart -Pattern $adminAccessAuditPattern -Label 'Authorized admin gateway response'
  $adminAfter = Get-NameNodeListStatusAuditCount
  if ($adminAfter -le $adminBefore) {
    throw "Admin received WebHDFS JSON, but no new NameNode audit event `cmd=listStatus src=/demo` was observed (before=$adminBefore, after=$adminAfter)."
  }
  Write-Output "PASS: NameNode audit confirms the allowed admin request reached WebHDFS (listStatus count $adminBefore -> $adminAfter)."
  Write-Output 'SCREEN D PASS: admin received HTTP 200 with both real HDFS files, fresh Knox dispatch/access success records, and NameNode forwarding evidence.'

  $wrongPasswordLogStart = Get-GatewayLogLineCount -Path $script:gatewayLogPath
  $wrongPasswordAuditStart = Get-GatewayLogLineCount -Path $script:gatewayAuditPath
  $wrongPassword = Invoke-KnoxRequest -Username 'guest' -Password 'wrong-password'
  if ($wrongPassword.ExitCode -ne 0 -or $wrongPassword.StatusCode -ne '401' -or
      $wrongPassword.Headers -notmatch '(?im)^WWW-Authenticate:\s*Basic') {
    throw "Wrong credentials did not fail authentication with HTTP 401 Basic (curl exit $($wrongPassword.ExitCode), HTTP '$($wrongPassword.StatusCode)')."
  }
  $wrongPasswordLogs = Get-GatewayLogSince -StartLine $wrongPasswordLogStart -Path $script:gatewayLogPath
  if ($wrongPasswordLogs.ExitCode -ne 0 -or $wrongPasswordLogs.Output -notmatch 'INVALID_CREDENTIALS') {
    throw "HTTP 401 was returned, but fresh Knox invalid-credential evidence is missing: $($wrongPasswordLogs.Output)"
  }
  $wrongPasswordAuditPattern = '\|WEBHDFS\|\|\|\|authentication\|principal\|guest\|failure\|LDAP authentication failed\.'
  $wrongPasswordAudit = Assert-FreshGatewayAuditRecord -StartLine $wrongPasswordAuditStart -Pattern $wrongPasswordAuditPattern -Label 'Invalid-password authentication'
  Write-Output 'PASS: wrong password failed during LDAP authentication with HTTP 401 and INVALID_CREDENTIALS evidence.'

  Write-Output 'SCREEN C START'
  $guestAuditStart = Get-GatewayLogLineCount -Path $script:gatewayAuditPath
  $nameNodeCountBeforeGuest = Get-NameNodeListStatusAuditCount
  $guestDenied = Invoke-KnoxRequest -Username 'guest' -Password 'guest-password'
  $guestDenialAuditPattern = '\|WEBHDFS\|guest\|\|\|authorization\|uri\|/gateway/demo/webhdfs/v1/demo\?op=LISTSTATUS\|failure\|'
  $guestDenialAudit = Assert-AclDenial -Response $guestDenied -Principal 'guest' -GatewayAuditStart $guestAuditStart -NameNodeAuditCountBefore $nameNodeCountBeforeGuest
  Write-Output 'SCREEN C PASS: authenticated guest was denied by Knox AclsAuthz before NameNode received listStatus.'
  Write-Output 'SCREEN E START'
  if ($adminDispatchAudit -notmatch $adminDispatchAuditPattern -or $adminAccessAudit -notmatch $adminAccessAuditPattern -or
      $wrongPasswordAudit -notmatch $wrongPasswordAuditPattern -or
      $guestDenialAudit -notmatch $guestDenialAuditPattern) {
    throw 'Screen E audit review failed: one or more fresh B/C/D records did not retain the expected principal, action, resource, and outcome.'
  }
  Write-Output 'SCREEN E PASS: fresh Knox audit records identify admin dispatch/access success, guest authorization failure, and invalid-password authentication failure.'

  Write-Output 'REGRESSION ACL_REVERSAL START'
  $reverseConfig = Invoke-Compose -Arguments @('config', '--quiet') -GuestAllowedPolicy
  if ($reverseConfig.ExitCode -ne 0 -or $reverseConfig.Output -match 'level=warning|variable is not set') {
    throw "Guest-allow Compose overlay config failed (exit $($reverseConfig.ExitCode)): $($reverseConfig.Output)"
  }
  Assert-TopologyMount -GuestAllowedPolicy

  $guestAllowedPolicyActive = $true
  $reverseStart = Invoke-Compose -Arguments @('up', '-d', '--force-recreate', '--no-deps', '--wait', '--wait-timeout', "$TimeoutSeconds", 'knox-gateway') -GuestAllowedPolicy
  if ($reverseStart.ExitCode -ne 0) {
    $states = Invoke-Compose -Arguments @('ps', '-a') -GuestAllowedPolicy
    $logs = Invoke-Compose -Arguments @('logs', '--tail=100', 'knox-gateway', 'knox-ldap') -GuestAllowedPolicy
    throw "Guest-allow Knox topology failed to become ready (exit $($reverseStart.ExitCode)).`n$($reverseStart.Output)`n$($states.Output)`n$($logs.Output)"
  }
  & $readyScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeGuestAllowedAclOverlay

  $guestAllowed = Invoke-KnoxRequest -Username 'guest' -Password 'guest-password'
  Assert-WebHdfsList -Response $guestAllowed -Label 'Guest principal after reversing the ACL'

  $adminAuditStart = Get-GatewayLogLineCount -Path $script:gatewayAuditPath
  $nameNodeCountBeforeAdminDeny = Get-NameNodeListStatusAuditCount
  $adminDenied = Invoke-KnoxRequest -Username 'admin' -Password 'admin-password'
  Assert-AclDenial -Response $adminDenied -Principal 'admin' -GatewayAuditStart $adminAuditStart -NameNodeAuditCountBefore $nameNodeCountBeforeAdminDeny
  Write-Output 'PASS: reversed policy changed both principals in the expected direction.'

  $restore = Invoke-Compose -Arguments @('up', '-d', '--force-recreate', '--no-deps', '--wait', '--wait-timeout', "$TimeoutSeconds", 'knox-gateway')
  if ($restore.ExitCode -ne 0) {
    throw "Could not restore the default admin-allow Knox topology (exit $($restore.ExitCode)): $($restore.Output)"
  }
  & $readyScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  $guestAllowedPolicyActive = $false

  $adminRestored = Invoke-KnoxRequest -Username 'admin' -Password 'admin-password'
  Assert-WebHdfsList -Response $adminRestored -Label 'Admin after restoring the default ACL'
  $guestAuditStart = Get-GatewayLogLineCount -Path $script:gatewayAuditPath
  $nameNodeCountBeforeGuest = Get-NameNodeListStatusAuditCount
  $guestRestored = Invoke-KnoxRequest -Username 'guest' -Password 'guest-password'
  Assert-AclDenial -Response $guestRestored -Principal 'guest' -GatewayAuditStart $guestAuditStart -NameNodeAuditCountBefore $nameNodeCountBeforeGuest
  Write-Output 'REGRESSION ACL_REVERSAL PASS: reversed ACL changed both principals and default admin-allow/guest-deny policy was restored.'
  Write-Output 'Authorization phase test PASS: default ACL restored (admin allow, guest deny).'
}
finally {
  if ($guestAllowedPolicyActive) {
    $ErrorActionPreference = 'Continue'
    $restore = Invoke-Compose -Arguments @('up', '-d', '--force-recreate', '--no-deps', '--wait', '--wait-timeout', "$TimeoutSeconds", 'knox-gateway')
    if ($restore.ExitCode -ne 0) {
      Write-Warning "Could not restore the default admin-allow topology after test failure: $($restore.Output)"
    }
    else {
      try { & $readyScript -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds }
      catch { Write-Warning "Default topology was recreated, but readiness verification failed: $($_.Exception.Message)" }
    }
  }
  Pop-Location
  Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
