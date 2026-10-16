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
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("knox-screen-f-" + [Guid]::NewGuid().ToString('N'))
$gatewayBaseUri = [Uri]'https://127.0.0.1:8443/'
$gatewayAuditPath = '/home/knox/knox/logs/gateway-audit.log'
$hdfsPath = '/demo/knox-screen-f.txt'
$expectedSha256 = '88a02dbd3b332f62b7efc3ab4bbf20dd9edf83bc4fb4971178db9bed23008e3b'
$expectedByteCount = 102
$expectedBase64 = 'QXBhY2hlIEtub3ggU2NyZWVuIEY6IFdlYkhERlMgT1BFTiB0aHJvdWdoIEdhdGV3YXkuCk5vbi1lbXB0eSBwYXlsb2FkIGZvciByZWFsIHJlZGlyZWN0IHZlcmlmaWNhdGlvbi4K'
$screenStarted = $false

function Invoke-Compose {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $dockerArguments = $script:composePrefix + $Arguments
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

function Invoke-GatewayRequest {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$Username,
    [Parameter(Mandatory)][string]$Password
  )
  $tag = [Guid]::NewGuid().ToString('N')
  $bodyPath = Join-Path $script:testDirectory "$tag.body"
  $headersPath = Join-Path $script:testDirectory "$tag.headers"
  $url = if ([Uri]::IsWellFormedUriString($Target, [UriKind]::Absolute)) {
    $Target
  }
  else {
    $script:gatewayBaseUri.GetLeftPart([UriPartial]::Authority) + $Target
  }
  $arguments = @(
    '--noproxy', '*', '--insecure', '--silent', '--show-error', '--max-time', "$TimeoutSeconds",
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
  $statusMatch = [regex]::Match($outputText, '^\s*(\d{3})\s*$')
  $statusCode = if ($statusMatch.Success) { $statusMatch.Groups[1].Value } else { 'not returned' }
  $headers = if (Test-Path -LiteralPath $headersPath) { Get-Content -Raw -LiteralPath $headersPath } else { '' }
  [pscustomobject]@{
    Label = $Label
    ExitCode = $exitCode
    StatusCode = $statusCode
    Headers = $headers
    BodyPath = $bodyPath
    Url = $url
    Output = $outputText
  }
}

function Invoke-BackendOpen {
  $request = @'
set -e
curl --silent --show-error --max-time 30 --dump-header - --output /dev/null \
  --write-out '\nHTTP_STATUS=%{http_code}\n' \
  'http://namenode:9870/webhdfs/v1/demo/knox-screen-f.txt?op=OPEN&user.name=hadoop'
'@
  Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'bash', '-ec', $request)
}

function Get-GatewayAuditLineCount {
  $result = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'wc', '-l', $script:gatewayAuditPath)
  if ($result.ExitCode -ne 0) { throw "Could not capture the Knox audit offset: $($result.Output)" }
  [int](($result.Output -split '\s+')[0])
}

function Get-GatewayAuditSince {
  param([Parameter(Mandatory)][int]$StartLine)
  Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'tail', '-n', "+$($StartLine + 1)", $script:gatewayAuditPath)
}

function Get-NameNodeOpenAuditCount {
  $result = Invoke-Compose -Arguments @('logs', '--no-color', 'namenode')
  if ($result.ExitCode -ne 0) { throw "Could not read NameNode audit output: $($result.Output)" }
  [regex]::Matches($result.Output, 'cmd=open\s+src=/demo/knox-screen-f\.txt(?:\s|$)').Count
}

function Ensure-HdfsScreenFile {
  $command = @'
set -euo pipefail
path=/demo/knox-screen-f.txt
expected_sha=__EXPECTED_SHA__
if hdfs dfs -test -e $path; then
  if ! hdfs dfs -test -f $path; then
    printf 'ERROR: expected a file at %s; refusing to change the existing HDFS entry.\n' $path >&2
    exit 20
  fi
else
  printf '%s' __EXPECTED_BASE64__ | base64 -d | hdfs dfs -put - $path
fi
actual_sha=$(hdfs dfs -cat $path | sha256sum | awk '{print $1}')
actual_bytes=$(hdfs dfs -stat '%b' $path)
printf 'HDFS_SCREEN_F_SHA256=%s\nHDFS_SCREEN_F_BYTES=%s\n' $actual_sha $actual_bytes
if [ $actual_sha != $expected_sha ]; then
  printf 'ERROR: existing HDFS content does not match the Screen F fixture; refusing to overwrite it.\n' >&2
  exit 21
fi
'@
  $command = $command.Replace('__EXPECTED_SHA__', $script:expectedSha256).Replace('__EXPECTED_BASE64__', $script:expectedBase64)
  $result = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'bash', '-ec', $command)
  if ($result.ExitCode -ne 0) {
    throw "Could not safely prepare the Screen F HDFS file (exit $($result.ExitCode)): $($result.Output)"
  }
  $expectedBytePattern = "HDFS_SCREEN_F_BYTES=$($script:expectedByteCount)(?:\s|$)"
  if ($result.Output -notmatch "HDFS_SCREEN_F_SHA256=$($script:expectedSha256)" -or
      $result.Output -notmatch $expectedBytePattern) {
    throw "HDFS did not return the expected Screen F byte count and SHA-256: $($result.Output)"
  }
  Write-Output "HDFS fixture verified: $($script:hdfsPath), $($script:expectedByteCount) bytes, SHA-256 $($script:expectedSha256)."
}

function Get-LocationHeader {
  param([Parameter(Mandatory)][string]$Headers)
  $matches = [regex]::Matches($Headers, '(?im)^Location:\s*(\S+)\s*$')
  if ($matches.Count -eq 0) { return $null }
  $matches[$matches.Count - 1].Groups[1].Value
}

function Assert-GatewayLocation {
  param([Parameter(Mandatory)][string]$Location)
  $locationUri = $null
  if (-not [Uri]::TryCreate($Location, [UriKind]::Absolute, [ref]$locationUri)) {
    throw "Knox returned a Location that is not an absolute URL: $Location"
  }
  if ($locationUri.Scheme -ne 'https' -or $locationUri.Host -ne $script:gatewayBaseUri.Host -or
      $locationUri.Port -ne $script:gatewayBaseUri.Port) {
    throw "Knox Location leaves the trusted Gateway authority ($($locationUri.GetLeftPart([UriPartial]::Authority)))."
  }
  if ($locationUri.AbsolutePath -ne '/gateway/demo/webhdfs/data/v1/webhdfs/v1/demo/knox-screen-f.txt' -or
      $locationUri.Query -notmatch '^\?_=.+$' -or $locationUri.AbsoluteUri -match '(?i)datanode|:9864') {
    throw "Knox Location did not use the encrypted WebHDFS DataNode route: $($locationUri.AbsolutePath)"
  }
  $locationUri
}

function Assert-DownloadedFile {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
  if (-not (Test-Path -LiteralPath $Path)) { throw "$Label did not write a response body." }
  $length = (Get-Item -LiteralPath $Path).Length
  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($length -ne $script:expectedByteCount -or $hash -ne $script:expectedSha256) {
    throw "$Label returned unexpected content (bytes $length, SHA-256 $hash)."
  }
  Write-Output "$Label content verified: $length bytes, SHA-256 $hash."
}

function Assert-AuditRecord {
  param(
    [Parameter(Mandatory)][string]$AuditOutput,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Label
  )
  $sanitizedAuditOutput = [regex]::Replace($AuditOutput, '([?&][^=\s|]+)=([^&\s|]*)', '$1=<redacted>')
  if ($AuditOutput -notmatch $Pattern) {
    throw "$Label lacks the expected fresh Knox audit event. Recent audit output: $sanitizedAuditOutput"
  }
  $line = @($AuditOutput -split '\r?\n' | Where-Object { $_ -match $Pattern })[-1]
  $line = [regex]::Replace($line, '([?&][^=\s|]+)=([^&\s|]*)', '$1=<redacted>')
  Write-Output "$Label audit evidence: $line"
}

New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
Push-Location $demoRoot
try {
  $config = Invoke-Compose -Arguments @('config', '--quiet')
  if ($config.ExitCode -ne 0 -or $config.Output -match 'level=warning|variable is not set') {
    throw "Compose preflight failed (exit $($config.ExitCode)): $($config.Output)"
  }
  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -ne 0) {
    throw "Docker services did not become ready (exit $($start.ExitCode)): $($start.Output)"
  }
  & (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay
  & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds

  Write-Output 'SCREEN F START'
  Ensure-HdfsScreenFile
  $screenStarted = $true

  $seedResponse = Invoke-GatewayRequest -Target '/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS' `
    -Label 'Screen F seed readiness' -Username 'admin' -Password 'admin-password'
  if ($seedResponse.ExitCode -ne 0 -or $seedResponse.StatusCode -ne '200') {
    throw "Admin LISTSTATUS precondition failed (curl exit $($seedResponse.ExitCode), HTTP '$($seedResponse.StatusCode)')."
  }
  try { $seedJson = Get-Content -Raw -LiteralPath $seedResponse.BodyPath | ConvertFrom-Json }
  catch { throw "Admin LISTSTATUS did not return valid JSON: $($_.Exception.Message)" }
  $seedItems = @($seedJson.FileStatuses.FileStatus | Where-Object { $null -ne $_ })
  foreach ($requiredName in @('apache-knox.txt', 'bigdata.txt')) {
    $matches = @($seedItems | Where-Object { $_.pathSuffix -eq $requiredName })
    if ($matches.Count -ne 1 -or [string]$matches[0].type -ne 'FILE') {
      throw "Admin LISTSTATUS did not contain required seed file '$requiredName' exactly once as type FILE."
    }
  }
  Write-Output 'F0 PASS: authenticated WebHDFS LISTSTATUS returned valid JSON and both real seed files.'

  $backendOpen = Invoke-BackendOpen
  if ($backendOpen.ExitCode -ne 0) { throw "Direct NameNode OPEN request failed (exit $($backendOpen.ExitCode)): $($backendOpen.Output)" }
  $backendStatus = [regex]::Match($backendOpen.Output, '(?m)^HTTP_STATUS=(\d{3})\s*$')
  if (-not $backendStatus.Success -or $backendStatus.Groups[1].Value -ne '307') {
    throw "NameNode WebHDFS OPEN did not return measured HTTP 307: $($backendOpen.Output)"
  }
  $backendLocation = Get-LocationHeader -Headers $backendOpen.Output
  if ([string]::IsNullOrWhiteSpace($backendLocation)) { throw 'NameNode HTTP 307 response did not include a Location header.' }
  $backendUri = $null
  if (-not [Uri]::TryCreate($backendLocation, [UriKind]::Absolute, [ref]$backendUri) -or
      $backendUri.Scheme -ne 'http' -or $backendUri.Host -ne 'datanode' -or $backendUri.Port -ne 9864 -or
      $backendUri.AbsolutePath -ne '/webhdfs/v1/demo/knox-screen-f.txt' -or
      $backendUri.Query -notmatch '(?:^|[?&])op=OPEN(?:&|$)') {
    throw "NameNode 307 did not point to the internal DataNode WebHDFS path: $backendLocation"
  }
  Write-Output "F2 PASS: NameNode returned HTTP 307 with internal Location $($backendUri.GetLeftPart([UriPartial]::Path))."

  $gatewayAuditStart = Get-GatewayAuditLineCount
  $nameNodeAuditCountBefore = Get-NameNodeOpenAuditCount
  $gatewayOpen = Invoke-GatewayRequest -Target '/gateway/demo/webhdfs/v1/demo/knox-screen-f.txt?op=OPEN' `
    -Label 'Gateway WebHDFS OPEN' -Username 'admin' -Password 'admin-password'
  if ($gatewayOpen.ExitCode -ne 0 -or @('200', '307') -notcontains $gatewayOpen.StatusCode) {
    throw "Knox WebHDFS OPEN failed (curl exit $($gatewayOpen.ExitCode), HTTP '$($gatewayOpen.StatusCode)')."
  }

  $download = $gatewayOpen
  $gatewayLocation = Get-LocationHeader -Headers $gatewayOpen.Headers
  if ($gatewayOpen.StatusCode -eq '307') {
    if ([string]::IsNullOrWhiteSpace($gatewayLocation)) { throw 'Knox HTTP 307 response did not include a Location header.' }
    $gatewayUri = Assert-GatewayLocation -Location $gatewayLocation
    Write-Output "F3 PASS: Knox rewrote Location to $($gatewayUri.GetLeftPart([UriPartial]::Path)); the internal DataNode address is hidden."
    $download = Invoke-GatewayRequest -Target $gatewayUri.AbsoluteUri -Label 'Gateway DataNode route' `
      -Username 'admin' -Password 'admin-password'
  }
  elseif (-not [string]::IsNullOrWhiteSpace($gatewayLocation)) {
    $gatewayUri = Assert-GatewayLocation -Location $gatewayLocation
    Write-Output "F3 PASS: Knox returned a Gateway-only Location $($gatewayUri.GetLeftPart([UriPartial]::Path))."
    $download = Invoke-GatewayRequest -Target $gatewayUri.AbsoluteUri -Label 'Gateway DataNode route' `
      -Username 'admin' -Password 'admin-password'
  }

  if ($download.ExitCode -ne 0 -or $download.StatusCode -ne '200') {
    throw "Gateway did not return the complete HDFS file (curl exit $($download.ExitCode), HTTP '$($download.StatusCode)')."
  }
  Assert-DownloadedFile -Path $download.BodyPath -Label 'F4 Gateway OPEN'

  $gatewayAudit = Get-GatewayAuditSince -StartLine $gatewayAuditStart
  if ($gatewayAudit.ExitCode -ne 0) { throw "Could not read fresh Knox audit: $($gatewayAudit.Output)" }
  $nameNodeDispatchPattern = '\|WEBHDFS\|admin\|\|\|dispatch\|uri\|http://namenode:9870/webhdfs/v1/demo/knox-screen-f\.txt\?op=OPEN.*\|success\|Response status: 307'
  Assert-AuditRecord -AuditOutput $gatewayAudit.Output -Pattern $nameNodeDispatchPattern -Label 'NameNode OPEN dispatch through Knox'
  $dataNodeDispatchPattern = '\|WEBHDFS\|admin\|\|\|dispatch\|uri\|http://datanode:9864/webhdfs/v1/demo/knox-screen-f\.txt\?op=OPEN.*\|success\|Response status: 200'
  Assert-AuditRecord -AuditOutput $gatewayAudit.Output -Pattern $dataNodeDispatchPattern -Label 'DataNode OPEN dispatch through Knox'
  $gatewayAccessPattern = '\|WEBHDFS\|admin\|\|\|access\|uri\|/gateway/demo/webhdfs/v1/demo/knox-screen-f\.txt\?op=OPEN\|success\|Response status: (?:200|307)'
  Assert-AuditRecord -AuditOutput $gatewayAudit.Output -Pattern $gatewayAccessPattern -Label 'Gateway OPEN access'
  $nameNodeAuditCountAfter = Get-NameNodeOpenAuditCount
  if ($nameNodeAuditCountAfter -le $nameNodeAuditCountBefore) {
    throw 'NameNode audit did not record a fresh OPEN for the Screen F file.'
  }
  Write-Output "HDFS audit evidence: NameNode cmd=open src=$hdfsPath count $nameNodeAuditCountBefore -> $nameNodeAuditCountAfter."

  $wrongPasswordAuditStart = Get-GatewayAuditLineCount
  $wrongPassword = Invoke-GatewayRequest -Target '/gateway/demo/webhdfs/v1/demo/knox-screen-f.txt?op=OPEN' `
    -Label 'Invalid admin OPEN' -Username 'admin' -Password 'wrong-password'
  if ($wrongPassword.ExitCode -ne 0 -or $wrongPassword.StatusCode -ne '401' -or
      $wrongPassword.Headers -notmatch '(?im)^WWW-Authenticate:\s*Basic') {
    throw "Invalid admin credentials were not rejected with HTTP 401 (curl exit $($wrongPassword.ExitCode), HTTP '$($wrongPassword.StatusCode)')."
  }
  $wrongPasswordAudit = Get-GatewayAuditSince -StartLine $wrongPasswordAuditStart
  if ($wrongPasswordAudit.ExitCode -ne 0) { throw "Could not read invalid-password audit: $($wrongPasswordAudit.Output)" }
  Assert-AuditRecord -AuditOutput $wrongPasswordAudit.Output `
    -Pattern '\|WEBHDFS\|\|\|\|authentication\|principal\|admin\|failure\|LDAP authentication failed\.' `
    -Label 'Invalid-password authentication denial'

  $guestAuditStart = Get-GatewayAuditLineCount
  $guest = Invoke-GatewayRequest -Target '/gateway/demo/webhdfs/v1/demo/knox-screen-f.txt?op=OPEN' `
    -Label 'Guest OPEN' -Username 'guest' -Password 'guest-password'
  if ($guest.ExitCode -ne 0 -or $guest.StatusCode -ne '403') {
    throw "Authenticated guest was not rejected by Knox with HTTP 403 (curl exit $($guest.ExitCode), HTTP '$($guest.StatusCode)')."
  }
  $guestAudit = Get-GatewayAuditSince -StartLine $guestAuditStart
  if ($guestAudit.ExitCode -ne 0) { throw "Could not read guest-denial audit: $($guestAudit.Output)" }
  Assert-AuditRecord -AuditOutput $guestAudit.Output `
    -Pattern '\|WEBHDFS\|guest\|\|\|authorization\|uri\|/gateway/demo/webhdfs/v1/demo/knox-screen-f\.txt\?op=OPEN\|failure\|' `
    -Label 'Guest ACL denial'
  if ($guestAudit.Output -match '\|WEBHDFS\|guest\|\|\|dispatch\|uri\|http://(?:namenode|datanode):') {
    throw 'Knox forwarded the denied guest OPEN request to an HDFS backend.'
  }
  Write-Output 'F5 PASS: invalid admin credentials returned 401; valid guest credentials returned 403 before HDFS dispatch.'
}
catch {
  $marker = if ($screenStarted) { 'SCREEN F FAIL' } else { 'SCREEN F BLOCKED' }
  Write-Output "$marker`: $($_.Exception.Message)"
  throw
}
finally {
  Pop-Location
  Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "SCREEN F PASS: actual NameNode 307, Knox rewrite/dispatch, HDFS bytes, audit, 401, and 403 verified."
