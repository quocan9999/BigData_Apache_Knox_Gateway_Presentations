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
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("knox-p04-" + [Guid]::NewGuid().ToString('N'))

function Invoke-Compose {
  param([string[]]$Arguments)
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

function Get-ComposeModel {
  $result = Invoke-Compose -Arguments @('config', '--format', 'json')
  if ($result.ExitCode -ne 0) {
    throw "Could not resolve the Compose model (exit $($result.ExitCode)): $($result.Output)"
  }
  try {
    return ($result.Output | ConvertFrom-Json)
  }
  catch {
    throw "Compose did not return valid JSON: $($result.Output)"
  }
}

function Get-PortMappings {
  param([Parameter(Mandatory)][object]$Service)
  $portsProperty = $Service.PSObject.Properties['ports']
  if ($null -eq $portsProperty -or $null -eq $portsProperty.Value) { return @() }
  @($portsProperty.Value | Where-Object { $null -ne $_ })
}

function Assert-ComposePortIsolation {
  $model = Get-ComposeModel
  $allMappings = @()
  foreach ($property in $model.services.PSObject.Properties) {
    foreach ($mapping in (Get-PortMappings -Service $property.Value)) {
      $allMappings += [pscustomobject]@{
        Service = $property.Name
        Target = [string]$mapping.target
        Published = [string]$mapping.published
        HostIp = [string]$mapping.host_ip
        Protocol = [string]$mapping.protocol
      }
    }
  }

  if ($allMappings.Count -ne 1) {
    $summary = ($allMappings | ForEach-Object { "$($_.Service) $($_.HostIp):$($_.Published)->$($_.Target)/$($_.Protocol)" }) -join ', '
    throw "Resolved Compose must publish only Knox HTTPS 127.0.0.1:8443:8443; found $($allMappings.Count) host mappings: $summary"
  }
  $gatewayMapping = $allMappings[0]
  if ($gatewayMapping.Service -ne 'knox-gateway' -or $gatewayMapping.Target -ne '8443' -or
      $gatewayMapping.Published -ne '8443' -or $gatewayMapping.HostIp -ne '127.0.0.1' -or
      $gatewayMapping.Protocol -ne 'tcp') {
    throw "Unexpected host mapping '$($gatewayMapping.Service) $($gatewayMapping.HostIp):$($gatewayMapping.Published)->$($gatewayMapping.Target)/$($gatewayMapping.Protocol)'; only Knox HTTPS on 127.0.0.1:8443 is allowed."
  }
  Write-Output 'Compose isolation PASS: only knox-gateway publishes 127.0.0.1:8443/tcp.'
}

function Assert-ActualPortBindings {
  foreach ($serviceName in @('namenode', 'datanode', 'knox-ldap', 'knox-gateway')) {
    $idResult = Invoke-Compose -Arguments @('ps', '-q', $serviceName)
    if ($idResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($idResult.Output)) {
      throw "Could not find a running Compose container for '$serviceName': $($idResult.Output)"
    }
    $inspect = Invoke-Docker -Arguments @('inspect', $idResult.Output.Trim())
    if ($inspect.ExitCode -ne 0) {
      throw "docker inspect failed for '$serviceName' (exit $($inspect.ExitCode)): $($inspect.Output)"
    }
    try {
      $container = @($inspect.Output | ConvertFrom-Json)[0]
    }
    catch {
      throw "docker inspect returned invalid JSON for '$serviceName': $($inspect.Output)"
    }

    $bindingProperties = @()
    if ($null -ne $container.HostConfig.PortBindings) {
      $bindingProperties = @($container.HostConfig.PortBindings.PSObject.Properties |
        Where-Object { $null -ne $_.Value -and @($_.Value).Count -gt 0 })
    }
    if ($serviceName -ne 'knox-gateway' -and $bindingProperties.Count -gt 0) {
      $published = ($bindingProperties | ForEach-Object { $_.Name }) -join ', '
      throw "Docker Engine shows host port bindings for backend/private service '$serviceName': $published"
    }
    if ($serviceName -eq 'knox-gateway') {
      if ($bindingProperties.Count -ne 1 -or $bindingProperties[0].Name -ne '8443/tcp') {
        $published = ($bindingProperties | ForEach-Object { $_.Name }) -join ', '
        throw "Docker Engine Knox bindings must contain only 8443/tcp; found '$published'."
      }
      $gatewayBindings = @($bindingProperties[0].Value)
      if ($gatewayBindings.Count -ne 1 -or $gatewayBindings[0].HostIp -ne '127.0.0.1' -or
          $gatewayBindings[0].HostPort -ne '8443') {
        throw "Docker Engine Knox binding is not loopback-only 127.0.0.1:8443: $($gatewayBindings | ConvertTo-Json -Compress)"
      }
    }
  }
  Write-Output 'Docker Engine inspection PASS: no backend or LDAP host binding; Knox alone binds loopback 8443.'
}

function Assert-NoWindowsListenerOn9870 {
  if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
    throw 'Cannot verify host port 9870: Get-NetTCPConnection is unavailable in this Windows PowerShell session.'
  }
  $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 9870 -ErrorAction SilentlyContinue)
  if ($listeners.Count -gt 0) {
    $details = foreach ($listener in $listeners) {
      $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
      $processName = if ($null -eq $process) { 'unknown process' } else { $process.ProcessName }
      "$($listener.LocalAddress):$($listener.LocalPort) PID $($listener.OwningProcess) ($processName)"
    }
    throw "Port 9870 already has a Windows listener, so a curl failure would be ambiguous: $($details -join '; ')"
  }
}

function Assert-HostCannotReachNameNode {
  Assert-NoWindowsListenerOn9870
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & curl.exe --noproxy '*' --connect-timeout 3 --max-time 5 --include --silent --write-out ' CURL_HTTP_STATUS=%{http_code}' 'http://localhost:9870/' 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $outputText = ($output | Out-String).Trim()
  if ($exitCode -eq 0 -or $outputText -match '(?im)^HTTP/\d(?:\.\d)?\s+\d{3}') {
    throw "Host unexpectedly received an HTTP response from NameNode port 9870 (curl exit $exitCode): $outputText"
  }
  Write-Output "Host isolation PASS: no Windows listener on 9870; curl.exe failed to connect (exit $exitCode): $outputText"
}

function Invoke-KnoxList {
  $tag = [Guid]::NewGuid().ToString('N')
  $bodyPath = Join-Path $script:testDirectory "$tag.body"
  $arguments = @(
    '--insecure', '--silent', '--show-error', '--max-time', '30',
    '--output', $bodyPath, '--write-out', '%{http_code}',
    '--user', 'admin:admin-password',
    'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
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
  if ($exitCode -ne 0 -or $statusCode -ne '200') {
    throw "Authorized Knox request failed (curl exit $exitCode, HTTP '$statusCode'): $body $outputText"
  }
  try {
    $json = $body | ConvertFrom-Json
  }
  catch {
    throw "Authorized Knox request did not return valid WebHDFS JSON: $body"
  }
  $entries = @($json.FileStatuses.FileStatus | ForEach-Object {
    [pscustomobject]@{
      Path = [string]$_.pathSuffix
      Type = [string]$_.type
      Length = [long]$_.length
      ModificationTime = [long]$_.modificationTime
      Owner = [string]$_.owner
      Group = [string]$_.group
      Permission = [string]$_.permission
      BlockSize = [long]$_.blockSize
      Replication = [int]$_.replication
    }
  } | Sort-Object Path)
  $names = @($entries | ForEach-Object { $_.Path })
  if (($names -join '|') -ne 'apache-knox.txt|bigdata.txt') {
    throw "Authorized Knox request returned unexpected real HDFS paths: $($names -join ', ')"
  }
  Write-Host "Knox backend PASS: HTTP 200 WebHDFS JSON contains $($names -join ', ')."
  return ,$entries
}

function Assert-KnoxDnsAndBackendForwarding {
  $dns = Invoke-Compose -Arguments @('exec', '-T', 'knox-gateway', 'getent', 'hosts', 'namenode')
  if ($dns.ExitCode -ne 0 -or $dns.Output -notmatch '(?m)\bnamenode\b') {
    throw "Knox container could not resolve the internal Docker service name 'namenode': $($dns.Output)"
  }
  Write-Output "Docker internal DNS PASS: $($dns.Output)"

  $before = Invoke-Compose -Arguments @('logs', '--no-color', '--since=10m', 'namenode')
  if ($before.ExitCode -ne 0) { throw "Could not read NameNode audit logs before request: $($before.Output)" }
  $beforeCount = @($before.Output -split '\r?\n' | Where-Object { $_ -match 'cmd=listStatus\s+src=/demo' }).Count
  $null = Invoke-KnoxList
  $after = Invoke-Compose -Arguments @('logs', '--no-color', '--since=10m', 'namenode')
  if ($after.ExitCode -ne 0) { throw "Could not read NameNode audit logs after request: $($after.Output)" }
  $afterCount = @($after.Output -split '\r?\n' | Where-Object { $_ -match 'cmd=listStatus\s+src=/demo' }).Count
  if ($afterCount -le $beforeCount) {
    throw "Knox returned WebHDFS JSON, but NameNode listStatus audit did not increase ($beforeCount -> $afterCount); backend forwarding is unproven."
  }
  Write-Output "Backend forwarding PASS: NameNode listStatus audit count increased $beforeCount -> $afterCount."
}

New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
Push-Location $demoRoot
try {
  Write-Output 'SCREEN A START'
  Assert-ComposePortIsolation

  $config = Invoke-Compose -Arguments @('config', '--quiet')
  if ($config.ExitCode -ne 0 -or $config.Output -match 'level=warning|variable is not set') {
    throw "Compose config validation failed (exit $($config.ExitCode)): $($config.Output)"
  }
  $start = Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  if ($start.ExitCode -ne 0) {
    $states = Invoke-Compose -Arguments @('ps', '-a')
    $logs = Invoke-Compose -Arguments @('logs', '--tail=100', 'namenode', 'datanode', 'knox-ldap', 'knox-gateway')
    $newline = [Environment]::NewLine
    throw "Stack startup failed (exit $($start.ExitCode)).$newline$($start.Output)$newline$($states.Output)$newline$($logs.Output)"
  }

  & (Join-Path $demoRoot 'scripts\Seed-HdfsDemo.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay
  & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  Assert-ActualPortBindings
  Assert-HostCannotReachNameNode
  Assert-KnoxDnsAndBackendForwarding
  $beforeRestart = Invoke-KnoxList

  $restartHdfs = Invoke-Compose -Arguments @('restart', 'namenode', 'datanode')
  if ($restartHdfs.ExitCode -ne 0) {
    throw "Could not restart HDFS services (exit $($restartHdfs.ExitCode)): $($restartHdfs.Output)"
  }
  & (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay

  $restartKnox = Invoke-Compose -Arguments @('restart', 'knox-ldap', 'knox-gateway')
  if ($restartKnox.ExitCode -ne 0) {
    throw "Could not restart Knox/LDAP services (exit $($restartKnox.ExitCode)): $($restartKnox.Output)"
  }
  & (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds
  & (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay

  Assert-ActualPortBindings
  Assert-HostCannotReachNameNode
  Assert-KnoxDnsAndBackendForwarding
  $afterRestart = Invoke-KnoxList
  $beforeJson = ConvertTo-Json -InputObject $beforeRestart -Depth 5 -Compress
  $afterJson = ConvertTo-Json -InputObject $afterRestart -Depth 5 -Compress
  if ($beforeJson -cne $afterJson) {
    throw "HDFS WebHDFS FileStatus data changed across service restart. Before: $beforeJson After: $afterJson"
  }
  Write-Output 'Restart persistence PASS: both HDFS file statuses are unchanged after restarting NameNode, DataNode, LDAP, and Knox.'
  $states = Invoke-Compose -Arguments @('ps', '-a')
  if ($states.ExitCode -ne 0) { throw "Could not capture final Compose status: $($states.Output)" }
  Write-Output 'Final Compose status:'
  Write-Output $states.Output
  Write-Output 'SCREEN A PASS: only Knox is host-published and the real WebHDFS listing survives the full service restart.'
  Write-Output 'Backend isolation phase test PASS.'
}
finally {
  Pop-Location
  Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
