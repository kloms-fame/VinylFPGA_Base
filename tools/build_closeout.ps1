param(
    [string]$TD = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td.exe',
    [string]$Python = 'python',
    [string]$LogDirectory = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
# A GUI instance can save stale MultiSeed settings while this build is running.
# Both GUI and batch runs also write the same syn_1/phy_1 directories.
$conflictingTD = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @('td.exe', 'run.exe', 'td_commands_prompt.exe') -and
    $_.CommandLine -and
    ($_.CommandLine.Replace('\', '/').ToLowerInvariant().Contains($projectRoot.Replace('\', '/').ToLowerInvariant()) -or
     $_.CommandLine -match 'VinylFPGA(?:\.al|_Runs[/\\])')
})
if ($conflictingTD.Count -gt 0) {
    throw ('Close this project in TD and finish/stop its other builds before rebuilding. Conflicting process IDs: ' +
           (($conflictingTD | ForEach-Object { $_.ProcessId }) -join ', '))
}
if (-not $LogDirectory) {
    $LogDirectory = Join-Path $projectRoot ('.codex_tmp/closeout_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$LogDirectory = [System.IO.Path]::GetFullPath($LogDirectory)
if (Test-Path -LiteralPath $LogDirectory) { throw 'Use a new log directory to preserve previous build evidence' }
New-Item -ItemType Directory -Path $LogDirectory | Out-Null
$stdoutFile = Join-Path $LogDirectory 'td.stdout.log'
$stderrFile = Join-Path $LogDirectory 'td.stderr.log'
$engineLog = Join-Path $LogDirectory 'td.engine.log'
$buildScript = Join-Path $PSScriptRoot 'run_closeout_project.tcl'
Push-Location -LiteralPath $projectRoot
try {
    & $Python (Join-Path $PSScriptRoot 'verify_gui_runs.py') --strategy-only
    if ($LASTEXITCODE -ne 0) { throw 'Project strategy validation failed' }
    Write-Output ('BUILD_LOG_DIRECTORY ' + $LogDirectory)
    # TD's GUI executable requires attached stdout/stderr even with -nogui.
    # Without these redirects, Tcl puts can make a completed build exit 1.
    $process = Start-Process -FilePath $TD -WorkingDirectory $projectRoot `
        -ArgumentList @('-nogui', '-b', ('"' + $buildScript + '"'), '-log', ('"' + $engineLog + '"')) `
        -WindowStyle Hidden -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
        -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "TD failed with exit $($process.ExitCode); inspect $LogDirectory" }
    if ((Get-Content -LiteralPath $stdoutFile -Raw) -notmatch 'CLOSEOUT_BUILD_TIMING_PASSED') {
        throw 'TD did not emit the validated completion marker'
    }
    & $Python (Join-Path $PSScriptRoot 'verify_gui_runs.py')
    if ($LASTEXITCODE -ne 0) { throw 'Generated GUI artifacts failed verification' }
    Write-Output 'CLOSEOUT_NATIVE_BUILD_VERIFIED'
} finally {
    Pop-Location
}
