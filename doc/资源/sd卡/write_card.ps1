#requires -Version 5.1
param(
    [switch]$DiagnoseOnly,
    [int]$DiskNumber = -1,
    [string]$ImagePath = '',
    [string]$ExpectedSha256 = ''
)
$ErrorActionPreference = 'Stop'
$S0Sha = 'e9f24f4c8a901a820fd2a0d6b4fdad572d9d842a6af5390ca3b0fb059b0f94f1'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$writer = Join-Path $root 'tools\safe_raw_writer.py'
$releaseName = 'S0'
if ([string]::IsNullOrWhiteSpace($ImagePath) -and [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    $image = Join-Path $PSScriptRoot 'stage4\card_STAGE4.img'
    $expectedImageSha = $S0Sha
} elseif ([string]::IsNullOrWhiteSpace($ImagePath) -or [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    throw '自定义镜像路径与SHA256必须同时提供。'
} else {
    if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'ExpectedSha256必须是64位十六进制值。' }
    $image = [IO.Path]::GetFullPath($ImagePath)
    $expectedImageSha = $ExpectedSha256.ToLowerInvariant()
    $releaseName = 'S1'
}
$exitCode = 1
$transcriptStarted = $false
function Invoke-CardWriter([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    try {
        # Native stderr carries progress. PowerShell 5.1 must not treat it as a terminating error.
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 1
        & $python $writer @Arguments 2>&1 | ForEach-Object { Write-Host ([string]$_) }
        $nativeExit = $global:LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return $nativeExit
}
try {
    $python = (Get-Command python -ErrorAction Stop).Source
    if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) { throw "缺少写卡工具：$writer" }
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "缺少 $releaseName 镜像：$image" }
    $logDir = Join-Path $PSScriptRoot 'stage4\write_logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir ($releaseName + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + $PID + '.log')
    Start-Transcript -LiteralPath $logPath | Out-Null
    $transcriptStarted = $true
    Write-Host ("VinylFPGA {0}：镜像与写卡诊断" -f $releaseName) -ForegroundColor Cyan
    Write-Host ("Image: {0}" -f $image)
    Write-Host ("Expected SHA256: {0}" -f $expectedImageSha)
    Write-Host '请按配套教程确认当前固件与镜像版本匹配；本入口不提供阶段五旧候选13/14。'
    $raw = & $python $writer --list-disks
    if ($LASTEXITCODE -ne 0) { throw '无法读取设备列表，未写入。' }
    $inventory = (($raw | Out-String) | ConvertFrom-Json)
    $disks = @($inventory.disks)
    if ($disks.Count -eq 0) { throw '未发现可查询的物理磁盘。' }
    $disks | Select-Object number,friendly_name,serial_number,bus_type,
        @{Name='GiB';Expression={[math]::Round($_.size/1GB,2)}},
        is_boot,is_system,is_read_only,is_offline | Format-Table -AutoSize
    if ($DiskNumber -lt 0) {
        $answer = Read-Host '请输入 SD 卡对应的磁盘号（上表 number；输入 Q 退出）'
        if ($answer -match '^[Qq]$') { $exitCode = 0; return }
        $parsedNumber = 0
        if (-not [int]::TryParse($answer,[ref]$parsedNumber) -or $parsedNumber -lt 0) { throw '磁盘号不合法。' }
        $DiskNumber = $parsedNumber
    }
    $targets = @($disks | Where-Object { [int]$_.number -eq $DiskNumber })
    if ($targets.Count -ne 1) { throw '磁盘号无法唯一匹配当前设备。' }
    $target = $targets[0]
    Write-Host '选中设备（还未写入）：' -ForegroundColor Yellow
    $target | Format-List *
    $common = @('--image',$image,'--disk-number',([string]$DiskNumber),'--expected-sha256',$expectedImageSha)
    $diagnosticExit = Invoke-CardWriter ($common + @('--diagnose'))
    if ($diagnosticExit -ne 0) { throw '预检查未通过，停止。请保存错误信息，未写入。' }
    if ($DiagnoseOnly) { $exitCode=0; return }
    $action = Read-Host ("输入 WRITE 写入本 {0} 镜像；其他输入仅结束诊断" -f $releaseName)
    if ($action -cne 'WRITE') { $exitCode=0; return }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $admin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { throw '实际写入需要管理员权限。请右键 write_card.bat 选择“以管理员身份运行”；本次未写入。' }
    $expectedConfirm = 'ERASE ' + $DiskNumber + ' ' + [string]$target.size
    Write-Host ("写入将覆盖上面选中的整个物理盘。确认其确为测试 SD 卡后输入：{0}" -f $expectedConfirm) -ForegroundColor Yellow
    $confirm = Read-Host '确认文字'
    if ($confirm -cne $expectedConfirm) { throw '确认文字不匹配，未写入。' }
    $writeExit = Invoke-CardWriter ($common + @('--write','--confirm',$confirm))
    if ($writeExit -ne 0) { throw '写入或回读校验失败，镜像未放行。保存输出中的失败偏移和错误码。' }
    Write-Host ("{0} 写入与完整回读成功。安全弹出后再装卡验收。" -f $releaseName) -ForegroundColor Green
    $exitCode=0
} catch {
    Write-Host ($releaseName + '_FAILED：' + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($transcriptStarted) {
        Write-Host ('操作日志：' + $logPath)
        Stop-Transcript | Out-Null
    }
    if (-not $DiagnoseOnly) { Read-Host '按 Enter 关闭' | Out-Null }
}
exit $exitCode
