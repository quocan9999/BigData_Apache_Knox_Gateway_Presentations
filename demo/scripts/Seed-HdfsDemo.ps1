[CmdletBinding()]
param(
  [string]$ProjectName = 'apache-knox-bigdata-demo',

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 180,

  [switch]$IncludeKnoxOverlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$demoRoot = Split-Path -Parent $PSScriptRoot
$composePrefix = @('compose', '-p', $ProjectName)
if ($IncludeKnoxOverlay) {
  $composePrefix += @('-f', 'docker-compose.yml', '-f', 'docker-compose.knox.yml')
}

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

Push-Location $demoRoot
try {
  & (Join-Path $PSScriptRoot 'Wait-HdfsReady.ps1') -ProjectName $ProjectName -TimeoutSeconds $TimeoutSeconds -IncludeKnoxOverlay:$IncludeKnoxOverlay

  $seedCommand = @'
set -eu
hdfs dfs -mkdir -p /demo
seed_if_missing() {
  path="$1"
  if hdfs dfs -test -e "$path"; then
    if ! hdfs dfs -test -f "$path"; then
      printf 'ERROR: expected an HDFS file but found a non-file at %s\n' "$path" >&2
      exit 2
    fi
    printf 'Preserving existing HDFS file: %s\n' "$path"
  else
    hdfs dfs -touchz "$path"
    printf 'Created HDFS file: %s\n' "$path"
  fi
}
seed_if_missing /demo/apache-knox.txt
seed_if_missing /demo/bigdata.txt
'@
  $seed = Invoke-Compose -Arguments @('exec', '-T', 'namenode', 'bash', '-ec', $seedCommand)
  if ($seed.ExitCode -ne 0) {
    throw "HDFS seed failed (exit $($seed.ExitCode)): $($seed.Output)"
  }
  Write-Output $seed.Output
}
finally {
  Pop-Location
}
