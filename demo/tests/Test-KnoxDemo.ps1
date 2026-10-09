[CmdletBinding()]
param(
  [string]$ProjectName = 'apache-knox-bigdata-demo',

  [ValidateRange(30, 600)]
  [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @(
  'compose', '-p', $ProjectName,
  '-f', 'docker-compose.yml',
  '-f', 'docker-compose.knox.yml'
)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("knox-demo-v1-$timestamp-" + [Guid]::NewGuid().ToString('N'))
$screenResults = [ordered]@{ A = 'BLOCKED'; B = 'BLOCKED'; C = 'BLOCKED'; D = 'BLOCKED'; E = 'BLOCKED' }
$suiteResults = [ordered]@{
  ISOLATION = 'BLOCKED'
  AUTHENTICATION = 'BLOCKED'
  AUTHORIZATION = 'BLOCKED'
  FAILURE_INJECTION = 'BLOCKED'
}
$regressionResults = [ordered]@{
  LDAP_OUTAGE = 'BLOCKED'
  ACL_REVERSAL = 'BLOCKED'
  MISSING_ROUTE = 'BLOCKED'
  BACKEND_DOWN_AND_RECOVERY = 'BLOCKED'
  READINESS_TIMEOUT_AND_RECOVERY = 'BLOCKED'
  FINAL_STACK_RECOVERY = 'BLOCKED'
}
$screenMarkers = @{
  A = @{ Start = 'SCREEN A START'; Pass = 'SCREEN A PASS' }
  B = @{ Start = 'SCREEN B START'; Pass = 'SCREEN B PASS' }
  C = @{ Start = 'SCREEN C START'; Pass = 'SCREEN C PASS' }
  D = @{ Start = 'SCREEN D START'; Pass = 'SCREEN D PASS' }
  E = @{ Start = 'SCREEN E START'; Pass = 'SCREEN E PASS' }
}
$regressionMarkers = @{
  LDAP_OUTAGE = @{ Start = 'REGRESSION LDAP_OUTAGE START'; Pass = 'REGRESSION LDAP_OUTAGE PASS' }
  ACL_REVERSAL = @{ Start = 'REGRESSION ACL_REVERSAL START'; Pass = 'REGRESSION ACL_REVERSAL PASS' }
  MISSING_ROUTE = @{ Start = 'INJECTION MISSING_ROUTE START'; Pass = 'INJECTION MISSING_ROUTE PASS' }
  BACKEND_DOWN_AND_RECOVERY = @{ Start = 'INJECTION BACKEND_DOWN_AND_RECOVERY START'; Pass = 'INJECTION BACKEND_DOWN_AND_RECOVERY PASS' }
  READINESS_TIMEOUT_AND_RECOVERY = @{ Start = 'INJECTION READINESS_TIMEOUT_AND_RECOVERY START'; Pass = 'INJECTION READINESS_TIMEOUT_AND_RECOVERY PASS' }
  FINAL_STACK_RECOVERY = @{ Start = 'INJECTION FINAL_STACK_RECOVERY START'; Pass = 'INJECTION FINAL_STACK_RECOVERY PASS' }
}
$continueSuites = $true

function Add-LogText {
  param([string]$Path, [string]$Text)
  Add-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Invoke-LoggedProgram {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$LogPath
  )
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  catch {
    $output = @($_.Exception.Message)
    $exitCode = 1
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($null -ne $output -and @($output).Count -gt 0) {
    $output | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
  }
  [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim() }
}

function Test-LogMarker {
  param([string]$Path, [string]$Marker)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  [bool](Select-String -LiteralPath $Path -SimpleMatch -Pattern $Marker -Quiet)
}

function Get-MarkerStatus {
  param(
    [string]$LogPath,
    [string]$StartMarker,
    [string]$PassMarker,
    [int]$ChildExitCode,
    [bool]$GatePassed,
    [bool]$PriorMarkerObserved
  )
  if (-not $GatePassed) { return 'BLOCKED' }
  if (Test-LogMarker -Path $LogPath -Marker $PassMarker) { return 'PASS' }
  if (Test-LogMarker -Path $LogPath -Marker $StartMarker) { return 'FAIL' }
  if ($ChildExitCode -eq 0 -or -not $PriorMarkerObserved) { return 'FAIL' }
  return 'BLOCKED'
}

function Invoke-ReadinessGate {
  param([string]$SuiteName)
  $logPath = Join-Path $logDirectory ("00-readiness-$SuiteName.log")
  Add-LogText -Path $logPath -Text "Readiness gate for suite $SuiteName"
  $composeArguments = $composePrefix + @('up', '-d', '--wait', '--wait-timeout', "$TimeoutSeconds")
  $composeResult = Invoke-LoggedProgram -FilePath 'docker' -Arguments $composeArguments -LogPath $logPath
  if ($composeResult.ExitCode -ne 0) {
    Add-LogText -Path $logPath -Text "Compose start/readiness failed with exit $($composeResult.ExitCode)."
    return $false
  }

  $powershellPath = (Get-Process -Id $PID).Path
  if ([string]::IsNullOrWhiteSpace($powershellPath) -or -not (Test-Path -LiteralPath $powershellPath)) {
    $powershellPath = 'powershell.exe'
  }
  $hdfsArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $demoRoot 'scripts\Wait-HdfsReady.ps1'), '-ProjectName', $ProjectName, '-TimeoutSeconds', "$TimeoutSeconds", '-IncludeKnoxOverlay')
  $hdfsResult = Invoke-LoggedProgram -FilePath $powershellPath -Arguments $hdfsArguments -LogPath $logPath
  if ($hdfsResult.ExitCode -ne 0) {
    Add-LogText -Path $logPath -Text "HDFS readiness failed with exit $($hdfsResult.ExitCode)."
    return $false
  }
  $knoxArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $demoRoot 'scripts\Wait-KnoxReady.ps1'), '-ProjectName', $ProjectName, '-TimeoutSeconds', "$TimeoutSeconds")
  $knoxResult = Invoke-LoggedProgram -FilePath $powershellPath -Arguments $knoxArguments -LogPath $logPath
  if ($knoxResult.ExitCode -ne 0) {
    Add-LogText -Path $logPath -Text "Knox readiness failed with exit $($knoxResult.ExitCode)."
    return $false
  }
  Add-LogText -Path $logPath -Text 'HDFS and Knox readiness PASS.'
  return $true
}

function Invoke-Suite {
  param(
    [string]$SuiteName,
    [string]$ResultKey,
    [string]$ScriptName,
    [string[]]$ScreenKeys,
    [string[]]$RegressionKeys
  )
  if (-not $continueSuites) {
    $suiteResults[$ResultKey] = 'BLOCKED'
    foreach ($key in $ScreenKeys) { $screenResults[$key] = 'BLOCKED' }
    foreach ($key in $RegressionKeys) { $regressionResults[$key] = 'BLOCKED' }
    return
  }

  $gatePassed = Invoke-ReadinessGate -SuiteName $SuiteName
  if (-not $gatePassed) {
    $suiteResults[$ResultKey] = 'BLOCKED'
    foreach ($key in $ScreenKeys) { $screenResults[$key] = 'BLOCKED' }
    foreach ($key in $RegressionKeys) { $regressionResults[$key] = 'BLOCKED' }
    $script:continueSuites = $false
    return
  }

  $logPath = Join-Path $logDirectory ("$SuiteName.log")
  $scriptPath = Join-Path $PSScriptRoot $ScriptName
  $powershellPath = (Get-Process -Id $PID).Path
  if ([string]::IsNullOrWhiteSpace($powershellPath) -or -not (Test-Path -LiteralPath $powershellPath)) {
    $powershellPath = 'powershell.exe'
  }
  $childArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-ProjectName', $ProjectName, '-TimeoutSeconds', "$TimeoutSeconds")
  $childResult = Invoke-LoggedProgram -FilePath $powershellPath -Arguments $childArguments -LogPath $logPath
  Add-LogText -Path $logPath -Text "Child exit code: $($childResult.ExitCode)"
  $suiteResults[$ResultKey] = if ($childResult.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
  Write-Output "$SuiteName child exit: $($childResult.ExitCode) (log: $logPath)"

  $priorMarkerObserved = $false
  foreach ($key in $ScreenKeys) {
    $markers = $screenMarkers[$key]
    $screenResults[$key] = Get-MarkerStatus -LogPath $logPath -StartMarker $markers.Start -PassMarker $markers.Pass -ChildExitCode $childResult.ExitCode -GatePassed $true -PriorMarkerObserved $priorMarkerObserved
    if ($screenResults[$key] -ne 'BLOCKED' -or (Test-LogMarker -Path $logPath -Marker $markers.Start) -or (Test-LogMarker -Path $logPath -Marker $markers.Pass)) { $priorMarkerObserved = $true }
  }
  $priorMarkerObserved = $false
  foreach ($key in $RegressionKeys) {
    $markers = $regressionMarkers[$key]
    $regressionResults[$key] = Get-MarkerStatus -LogPath $logPath -StartMarker $markers.Start -PassMarker $markers.Pass -ChildExitCode $childResult.ExitCode -GatePassed $true -PriorMarkerObserved $priorMarkerObserved
    if ($regressionResults[$key] -ne 'BLOCKED' -or (Test-LogMarker -Path $logPath -Marker $markers.Start) -or (Test-LogMarker -Path $logPath -Marker $markers.Pass)) { $priorMarkerObserved = $true }
  }
}

function Write-Summary {
  Write-Output "Local run logs: $logDirectory"
  Write-Output 'Screens:'
  foreach ($key in @('A', 'B', 'C', 'D', 'E')) { Write-Output "  Screen $key`: $($screenResults[$key])" }
  Write-Output 'Suite status:'
  foreach ($key in @('ISOLATION', 'AUTHENTICATION', 'AUTHORIZATION', 'FAILURE_INJECTION')) { Write-Output "  $key`: $($suiteResults[$key])" }
  Write-Output 'Regression and failure-injection groups:'
  foreach ($key in @('LDAP_OUTAGE', 'ACL_REVERSAL', 'MISSING_ROUTE', 'BACKEND_DOWN_AND_RECOVERY', 'READINESS_TIMEOUT_AND_RECOVERY', 'FINAL_STACK_RECOVERY')) {
    Write-Output "  $key`: $($regressionResults[$key])"
  }
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logDirectory = [System.IO.Path]::GetFullPath($logDirectory)
Push-Location $demoRoot
try {
  $dockerInfoLog = Join-Path $logDirectory '00-docker-preflight.log'
  $dockerInfo = Invoke-LoggedProgram -FilePath 'docker' -Arguments @('info') -LogPath $dockerInfoLog
  $composeConfigLog = Join-Path $logDirectory '00-compose-config.log'
  $composeConfig = Invoke-LoggedProgram -FilePath 'docker' -Arguments ($composePrefix + @('config', '--quiet')) -LogPath $composeConfigLog
  if ($dockerInfo.ExitCode -ne 0 -or $composeConfig.ExitCode -ne 0) {
    Add-LogText -Path $dockerInfoLog -Text "Docker preflight failed (docker info exit $($dockerInfo.ExitCode), Compose config exit $($composeConfig.ExitCode))."
    $script:continueSuites = $false
  }

  Invoke-Suite -SuiteName '01-screen-a-isolation' -ResultKey 'ISOLATION' -ScriptName 'Test-KnoxBackendIsolation.ps1' -ScreenKeys @('A') -RegressionKeys @()
  Invoke-Suite -SuiteName '02-screen-b-authentication' -ResultKey 'AUTHENTICATION' -ScriptName 'Test-KnoxGateway.ps1' -ScreenKeys @('B') -RegressionKeys @('LDAP_OUTAGE')
  Invoke-Suite -SuiteName '03-screens-cde-authorization' -ResultKey 'AUTHORIZATION' -ScriptName 'Test-KnoxAuthorization.ps1' -ScreenKeys @('D', 'C', 'E') -RegressionKeys @('ACL_REVERSAL')
  Invoke-Suite -SuiteName '04-failure-injection' -ResultKey 'FAILURE_INJECTION' -ScriptName 'Test-KnoxFailureInjection.ps1' -ScreenKeys @() -RegressionKeys @('MISSING_ROUTE', 'BACKEND_DOWN_AND_RECOVERY', 'READINESS_TIMEOUT_AND_RECOVERY', 'FINAL_STACK_RECOVERY')
}
finally {
  Pop-Location
}

Write-Summary
$allStatuses = @($screenResults.Values) + @($suiteResults.Values) + @($regressionResults.Values)
if (@($allStatuses | Where-Object { $_ -ne 'PASS' }).Count -eq 0) {
  Write-Output 'Apache Knox demo result: PASS.'
  exit 0
}
Write-Output 'Apache Knox demo result: FAIL or BLOCKED. See the local logs above.'
exit 1
