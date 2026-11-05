param([switch]$EightHourSoak)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path 'pubspec.yaml')) {
  throw 'Run this script from the extracted Cantivra project root.'
}
$CantivraProjectRoot = (Get-Location).ProviderPath
$CantivraStartedAtUtc = [DateTime]::UtcNow
$CantivraRunId = $CantivraStartedAtUtc.ToString('yyyyMMddTHHmmss.fffffffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$CantivraEvidenceDirectory = Join-Path $CantivraProjectRoot "build/qa/windows-verification/$CantivraRunId"
New-Item -ItemType Directory -Path $CantivraEvidenceDirectory | Out-Null
$CantivraTranscriptStarted = $false
$CantivraRunStatus = 'failed'
$CantivraFailure = $null
$CantivraSmokeStartedAtUtc = $null
$CantivraAcceptanceStartedAtUtc = $null
$CantivraAcceptancePreviousRun = $null
$CantivraDuration = if ($EightHourSoak) { '28800' } else { '60' }
$CantivraManualGates = [ordered]@{
  nativeWindowsClose = 'Pending Windows execution: native smoke now exercises WM_CLOSE refusal and safe save. Also test the actual close button/Alt+F4 and controlled failed-save refusal.'
  physicalDisplays = 'Pending: HDMI 1080p/4K, mixed DPI, negative coordinates, disconnect/reconnect, sleep/wake and church distribution hardware.'
  cleanMachine = 'Pending: extracted normal Release package runs offline without Flutter or Visual Studio; DLL/runtime prerequisites checked.'
  nativeFonts = 'Pending: Windows fallback/layout PNG review and knowledgeable multilingual reader review.'
  trustedDistribution = 'Pending: owner-controlled release signing and clean-machine publisher/trust checks; not required for local tests.'
}

function Invoke-CantivraCheck {
  param([string]$Program, [string[]]$ArgumentList)
  & $Program @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "$Program failed with exit code $LASTEXITCODE"
  }
}

function Copy-CantivraRunEvidence {
  $CantivraSmokePath = Join-Path $CantivraProjectRoot 'build/qa/native-smoke-phase2.log'
  if ($null -ne $CantivraSmokeStartedAtUtc -and (Test-Path -LiteralPath $CantivraSmokePath)) {
    $CantivraSmokeFile = Get-Item -LiteralPath $CantivraSmokePath
    if ($CantivraSmokeFile.LastWriteTimeUtc -ge $CantivraSmokeStartedAtUtc) {
      Copy-Item -LiteralPath $CantivraSmokePath -Destination (Join-Path $CantivraEvidenceDirectory 'native-smoke-phase2.log')
    }
  }
  if ($null -eq $CantivraAcceptanceStartedAtUtc) { return }
  $CantivraLatestPath = Join-Path $CantivraProjectRoot 'build/qa/native-acceptance/latest-run.json'
  if (-not (Test-Path -LiteralPath $CantivraLatestPath)) { return }
  $CantivraLatest = Get-Content -LiteralPath $CantivraLatestPath -Raw | ConvertFrom-Json
  if (-not $CantivraLatest.runDirectory -or $CantivraLatest.runDirectory -eq $CantivraAcceptancePreviousRun) { return }
  $CantivraAcceptanceRoot = [IO.Path]::GetFullPath((Join-Path $CantivraProjectRoot 'build/qa/native-acceptance'))
  $CantivraAcceptancePath = [IO.Path]::GetFullPath((Join-Path $CantivraProjectRoot $CantivraLatest.runDirectory))
  # Only a direct run directory under this project's acceptance root is eligible.
  if (-not [string]::Equals([IO.Path]::GetDirectoryName($CantivraAcceptancePath), $CantivraAcceptanceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing an acceptance evidence directory outside this project.'
  }
  if (((Get-Item -LiteralPath $CantivraAcceptancePath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Refusing a linked acceptance evidence directory.'
  }
  if (([DateTimeOffset]::Parse($CantivraLatest.updatedAtUtc)).UtcDateTime -lt $CantivraAcceptanceStartedAtUtc) { return }
  $CantivraAcceptanceExport = Join-Path $CantivraEvidenceDirectory 'native-acceptance'
  New-Item -ItemType Directory -Path $CantivraAcceptanceExport | Out-Null
  $CantivraCopiedFiles = @()
  foreach ($CantivraFile in Get-ChildItem -LiteralPath $CantivraAcceptancePath -File) {
    # Never copy session capabilities, databases, binaries or arbitrary trees.
    if (($CantivraFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    if ($CantivraFile.Name -in @('report.json', 'events.ndjson') -or $CantivraFile.Name -cmatch '^[a-z0-9_-]+\.png$') {
      Copy-Item -LiteralPath $CantivraFile.FullName -Destination (Join-Path $CantivraAcceptanceExport $CantivraFile.Name)
      $CantivraCopiedFiles += 'native-acceptance/' + $CantivraFile.Name
    }
  }
  [ordered]@{
    status = $CantivraLatest.status
    originalRunDirectory = $CantivraLatest.runDirectory
    updatedAtUtc = $CantivraLatest.updatedAtUtc
    requestedDurationSeconds = $CantivraLatest.requestedDurationSeconds
    copiedFiles = $CantivraCopiedFiles
    note = 'These are isolated automated-test exports. Verify native Quit smoke results; physical displays, actual close-button/Alt+F4 and failed-save manual checks, and reader review remain separate.'
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $CantivraEvidenceDirectory 'acceptance-evidence.json') -Encoding UTF8
}

try {
  Start-Transcript -Path (Join-Path $CantivraEvidenceDirectory 'windows-verification.log') | Out-Null
  $CantivraTranscriptStarted = $true
  Write-Host "Evidence directory: $CantivraEvidenceDirectory"
  $CantivraHostEvidence = @{
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber
    cpu = Get-CimInstance Win32_Processor | Select-Object Name
    graphics = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
    physicalMemoryBytes = [UInt64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    manualAcceptance = $CantivraManualGates
  }
  $CantivraHostEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $CantivraEvidenceDirectory 'windows-host.json') -Encoding UTF8
  Invoke-CantivraCheck 'flutter' @('doctor', '-v')
  Invoke-CantivraCheck 'flutter' @('pub', 'get', '--enforce-lockfile')
  Invoke-CantivraCheck 'dart' @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool')
  Invoke-CantivraCheck 'flutter' @('analyze', '--fatal-infos')
  Invoke-CantivraCheck 'flutter' @('test', 'test', '--reporter', 'expanded')
  $CantivraSmokeStartedAtUtc = [DateTime]::UtcNow
  Invoke-CantivraCheck 'dart' @('run', 'tool/run_native_smoke.dart', 'windows')
  $CantivraLatestPath = Join-Path $CantivraProjectRoot 'build/qa/native-acceptance/latest-run.json'
  if (Test-Path -LiteralPath $CantivraLatestPath) {
    $CantivraAcceptancePreviousRun = (Get-Content -LiteralPath $CantivraLatestPath -Raw | ConvertFrom-Json).runDirectory
  }
  $CantivraAcceptanceStartedAtUtc = [DateTime]::UtcNow
  Invoke-CantivraCheck 'dart' @('run', 'tool/run_native_acceptance.dart', 'windows', "--duration-seconds=$CantivraDuration")
  # Rebuild lib/main.dart so the test harness can never become the deliverable.
  Invoke-CantivraCheck 'dart' @('run', 'tool/package_desktop.dart', 'windows')
  $CantivraRunStatus = 'passed'
  Write-Host 'Automated Windows checks passed. Manual acceptance remains open; follow docs/WINDOWS_TESTING.md.'
} catch {
  $CantivraFailure = $_.Exception.Message
  throw
} finally {
  try {
    Copy-CantivraRunEvidence
  } catch {
    $CantivraRunStatus = 'failed'
    if (-not $CantivraFailure) { $CantivraFailure = $_.Exception.Message }
    Write-Warning "Could not collect all test exports: $($_.Exception.Message)"
  }
  try {
    [ordered]@{
      status = $CantivraRunStatus
      startedAtUtc = $CantivraStartedAtUtc.ToString('o')
      finishedAtUtc = [DateTime]::UtcNow.ToString('o')
      requestedDurationSeconds = [int]$CantivraDuration
      failure = $CantivraFailure
      manualAcceptance = $CantivraManualGates
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $CantivraEvidenceDirectory 'verification-status.json') -Encoding UTF8
    Write-Host "Saved verification evidence: $CantivraEvidenceDirectory"
  } finally {
    if ($CantivraTranscriptStarted) {
      try { Stop-Transcript | Out-Null } catch { Write-Warning "Could not stop the transcript: $($_.Exception.Message)" }
    }
  }
}
if ($CantivraRunStatus -ne 'passed') { throw 'Windows verification or evidence collection failed. Review this run evidence directory.' }
