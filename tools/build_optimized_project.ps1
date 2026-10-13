param(
    [string]$RoundName = ('al_project_optimized_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
    [string]$Python = 'D:/Anaconda/python.exe',
    [string]$TD = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
)
$ErrorActionPreference = 'Stop'
if ($RoundName -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid build round name' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $projectRoot 'prj/VinylFPGA.al'
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw 'Missing VinylFPGA.al' }
Push-Location -LiteralPath $projectRoot
try {
    $currentBranch = (& git branch --show-current | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'main') { throw 'Build this project on main' }
    $configurationScript = (Join-Path $PSScriptRoot 'configure_optimized_project.tcl').Replace('\','/')
    $configuration = (& $TD $configurationScript 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $configuration -notmatch 'OPTIMIZED_PROJECT_CONFIGURED' -or $configuration -match '\b(?:ERROR|FATAL)\b') {
        throw ('PROJECT_CONFIGURATION_FAILED ' + $configuration)
    }
    # Archive current inputs, then use the original GUI run manager directly.
    & $Python 'tools/resource_opt_round.py' $RoundName
    if ($LASTEXITCODE -ne 0) { throw 'SNAPSHOT_FAILED' }
    $roundRoot = Join-Path $projectRoot ('prj/resource_opt_verified_20261005/' + $RoundName)
    $pipelineLog = Join-Path $roundRoot 'pipeline.log'
    ('START ' + (Get-Date -Format o)) | Out-File -LiteralPath $pipelineLog -Encoding utf8
    Write-Output ('PROJECT ' + $projectFile)
    Write-Output ('BUILD_LOG ' + $pipelineLog)
    $guiFlowScript = (Join-Path $PSScriptRoot 'run_optimized_project.tcl').Replace('\','/')
    & $TD $guiFlowScript *>> $pipelineLog
    if ($LASTEXITCODE -ne 0) {
        ('BUILD_FAILED exit=' + $LASTEXITCODE) | Out-File -LiteralPath $pipelineLog -Append -Encoding utf8
        throw 'BUILD_FAILED: inspect pipeline.log; no bitstream released'
    }
    ('BUILD_COMPLETE ' + (Get-Date -Format o)) | Out-File -LiteralPath $pipelineLog -Append -Encoding utf8
    # Verify actual MultiSeed reports and inputs; do not import other run DBs.
    & $Python 'tools/verify_gui_runs.py' --snapshot $roundRoot *>> $pipelineLog
    if ($LASTEXITCODE -ne 0) {
        ('BITGEN_FAILED exit=' + $LASTEXITCODE) | Out-File -LiteralPath $pipelineLog -Append -Encoding utf8
        throw 'GUI_RESULT_NOT_RELEASED: inspect pipeline.log'
    }
    ('NATIVE_BITGEN_COMPLETE ' + (Get-Date -Format o)) | Out-File -LiteralPath $pipelineLog -Append -Encoding utf8
    ('BITGEN_COMPLETE ' + (Get-Date -Format o)) | Out-File -LiteralPath $pipelineLog -Append -Encoding utf8
    Write-Output ('GUI_BITSTREAM ' + (Join-Path $projectRoot 'prj/VinylFPGA_Runs/phy_1/seed_5/VinylFPGA.bit'))
} finally { Pop-Location }
