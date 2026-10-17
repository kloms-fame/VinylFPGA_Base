param(
    [string]$ModelSimRoot='D:/modeltech64_10.6e',
    [string]$TdRoot='D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116',
    [string]$OutputDirectory=(Join-Path $env:TEMP 'vinyl_vendor_mask_isolation_20261016')
)
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$toolDir=Join-Path $ModelSimRoot 'win64'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Use a new output directory to preserve evidence'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$modelFile=Join-Path $OutputDirectory 'mt48lc2m32b2.v'
$modelUrl='https://raw.githubusercontent.com/freecores/sdr_ctrl/master/verif/model/mt48lc2m32b2.v'
$modelHash='F4A9D4392AAB3E6765D201D86DCD1350B9D1F5D6ADD016BBC5C79DA1E1AC5060'
if(!(Test-Path -LiteralPath $modelFile)) {
    & curl.exe -f -sL --max-time 45 $modelUrl -o $modelFile
    if($LASTEXITCODE -ne 0){throw 'Failed to fetch the Micron bus model'}
}
if((Get-FileHash -LiteralPath $modelFile -Algorithm SHA256).Hash -ne $modelHash){
    throw 'Micron model hash mismatch; review changed upstream source'
}
Push-Location $OutputDirectory
try {
    Set-Content -LiteralPath wave.do -Encoding ASCII -Value 'log -r /*'
    Set-Content -LiteralPath run.do -Encoding ASCII -Value 'onbreak {quit -code 1}; onerror {quit -code 1}; do wave.do; run -all; quit -f'
    & (Join-Path $toolDir 'vlib.exe') work
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    & (Join-Path $toolDir 'vmap.exe') -c
    if($LASTEXITCODE -ne 0){throw 'vmap -c failed'}
    & (Join-Path $toolDir 'vmap.exe') work work
    if($LASTEXITCODE -ne 0){throw 'vmap failed'}
    $incdir='+incdir+'+(Join-Path $repoRoot 'src/include').Replace('\','/')
    & (Join-Path $toolDir 'vlog.exe') -work work $incdir `
        (Join-Path $repoRoot 'src/include/sdr_init_ref.enc.v') `
        (Join-Path $repoRoot 'src/include/sdr_wrrd.enc.v') `
        (Join-Path $repoRoot 'src/include/sdr_as_ram.enc.v') `
        (Join-Path $TdRoot 'sim_release/eg4/eg_phy_glbl.v') `
        $modelFile (Join-Path $repoRoot 'src/audio/audio_sdram_arbiter.v') `
        (Join-Path $PSScriptRoot 'tb_vendor_mask_isolation.v')
    if($LASTEXITCODE -ne 0){throw 'vlog failed'}
    & (Join-Path $toolDir 'vsim.exe') -c -wlf vendor_mask.wlf -l vendor_mask.log `
        work.tb_vendor_mask_isolation work.glbl -do run.do
    if($LASTEXITCODE -ne 0){throw 'vsim failed'}
    $log=Get-Content -LiteralPath vendor_mask.log -Raw
    if($log -notmatch 'PASS encrypted controller:'){throw 'Missing test completion marker'}
    Write-Output ('Evidence: '+(Join-Path $OutputDirectory 'vendor_mask.log'))
    & (Join-Path $toolDir 'vlog.exe') -work work `
        (Join-Path $TdRoot 'sim_release/eg4/eg_phy_bram32k.v') `
        (Join-Path $repoRoot 'src/audio/audio_prefetch_stage.v') `
        (Join-Path $PSScriptRoot 'tb_vendor_stage.v')
    if($LASTEXITCODE -ne 0){throw 'stage vlog failed'}
    & (Join-Path $toolDir 'vsim.exe') -c -wlf vendor_stage.wlf -l vendor_stage.log `
        work.tb_vendor_stage work.glbl -do run.do
    if($LASTEXITCODE -ne 0){throw 'stage vsim failed'}
    $stageLog=Get-Content -LiteralPath vendor_stage.log -Raw
    if($stageLog -notmatch 'PASS actual EG_PHY_BRAM32K'){throw 'Missing stage completion marker'}
    Write-Output ('Evidence: '+(Join-Path $OutputDirectory 'vendor_stage.log'))
}
finally { Pop-Location }
