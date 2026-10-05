param(
    [string]$TdRoot = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116',
    [ValidateRange(1,100)][int]$Seed = 3,
    [string]$GateDb = ''
)
$ErrorActionPreference = 'Stop'
$resourceRoot = (Split-Path $PSScriptRoot -Parent).Replace('\','/')
$resourceBuild = "$resourceRoot/prj/resource_opt_20261005/seed$Seed"
New-Item -ItemType Directory -Force -Path $resourceBuild | Out-Null
# TD .al contains literal P&R attribute text, so preserve its vendor format.
$resourceProject = Get-Content -LiteralPath "$resourceRoot/prj/VinylFPGA.al" -Raw
$resourceProject = $resourceProject.Replace('"../', ('"' + $resourceRoot + '/'))
$resourceProject = $resourceProject.Replace(('Path="' + $resourceRoot + '/prj"'), ('Path="' + $resourceBuild + '"'))
[IO.File]::WriteAllText("$resourceBuild/VinylFPGA.al", $resourceProject, [Text.UTF8Encoding]::new($false))
$resourceParams = "set resource_opt_seed $Seed`nset resource_opt_gate_file {}"
if ($GateDb) {
    $resourceGatePath = (Resolve-Path -LiteralPath $GateDb).Path.Replace('\','/')
    $resourceParams = "set resource_opt_seed $Seed`nset resource_opt_gate_file {$resourceGatePath}"
}
[IO.File]::WriteAllText("$resourceBuild/build_settings.tcl", $resourceParams, [Text.UTF8Encoding]::new($false))
Push-Location $resourceBuild
try {
    & "$TdRoot/bin/td_commands_prompt.exe" "$resourceRoot/tools/build_resource_opt.tcl" *> build.log
    $resourceLog = Get-Content -LiteralPath build.log -Raw
    Get-Content -LiteralPath build.log -Tail 20
    if ($resourceLog -notmatch 'RESOURCE_OPT_BUILD_PASS') {
        throw "TD build did not pass timing/bitstream signoff. Inspect $resourceBuild/build.log"
    }
    Get-FileHash -LiteralPath "$resourceBuild/VinylFPGA_resource_opt.bit"
} finally {
    Pop-Location
}
