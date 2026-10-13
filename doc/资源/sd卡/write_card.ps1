# VinylFPGA card flasher
# 用法:
#   1) 双击 write_card.bat          -> 交互菜单, 输入 1~9
#   2) 双击 write_firmware_card.bat -> 全自动烧录最终 r5 固件配套 SD 镜像(选项9), 无需菜单
#   3) 命令行: write_card.ps1 -FirmwareAuto -> 同上, 供脚本/提权调用
# 注意: param 必须是脚本第一句(只能有注释/ #requires 在它前面), 否则 PowerShell 会把它当命令报错并闪退
param(
    [switch]$FirmwareAuto   # 全自动烧录最终 r5 固件配套 SD 镜像(选项9)
)

$host.UI.RawUI.WindowTitle = "VinylFPGA write_card"
$ErrorActionPreference = 'Stop'
$logFile = Join-Path $env:TEMP 'vinylfpga_write_card.log'

try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Not Administrator. Launch via write_card.bat instead."
    }

    # ---------- 镜像选单 ----------
    Write-Host "=== VinylFPGA card flasher ===" -ForegroundColor Cyan
    if (-not $FirmwareAuto) {
        Write-Host "S4 acceptance:"
        Write-Host "  1 = card_A.img         (good index + PIC1~4, only Track1 audio)"
        Write-Host "  2 = card_A_broken.img   (bad index + PIC1~4)"
        Write-Host "  3 = card_SONG.img       (good index + SONG1~4, no PIC)"
        Write-Host "  4 = card_B_broken.img   (bad index + SONG1~4, no PIC)"
        Write-Host "S5 acceptance:"
        Write-Host "  5 = card_S5.img         (good index + PIC1~4, ALL 4 songs share AUDIO.PCM)"
        Write-Host "S6 acceptance:"
        Write-Host "  6 = card_S6.img         (Track1 has MV, Tracks 2/3/4 vinyl-only)"
        Write-Host "D2 test tone:"
        Write-Host "  7 = card_test_tone.img  (Track1 = 5s 1kHz tone, other covers kept)"
        Write-Host "Stage 3B backgrounds:"
        Write-Host "  8 = stage3b/card_STAGE3B.img (four song backgrounds + shared art)"
        Write-Host "Final r5 firmware SD:"
        Write-Host "  9 = stage3b/card_STAGE3B.img (final r5 firmware image, SHA256 + readback verify)"
    }

    $map = @{
        '1' = 'card_A.img'
        '2' = 'card_A_broken.img'
        '3' = 'card_SONG.img'
        '4' = 'card_B_broken.img'
        '5' = 'card_S5.img'
        '6' = 'card_S6.img'
        '7' = '..\..\..\prj\resource_opt_verified_20261005\d2_testtone_20261010\card_test_tone.img'
        '8' = 'stage3b\card_STAGE3B.img'
        '9' = 'stage3b\card_STAGE3B.img'
    }
    # 已知期望 SHA256: 仅选项9(最终 r5 固件配套镜像) 做严格预校验
    $knownSha = @{
        '9' = 'c5b3d00253ac2870ea385a427b685781d9dba553422a6a5d0c25ef823fa3630c'
    }

    if ($FirmwareAuto) {
        $choice = '9'
        Write-Host "Auto mode: burning final r5 firmware SD image (option 9)." -ForegroundColor Cyan
    } else {
        $choice = Read-Host "`nEnter choice (1-9)"
    }
    if (-not $map.ContainsKey($choice)) { throw "invalid choice" }
    $img = Join-Path $PSScriptRoot $map[$choice]
    if (-not (Test-Path $img)) { throw "image not found: $img" }
    $total = (Get-Item $img).Length

    # ---------- SHA256 预校验 ----------
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $img).Hash.ToLower()
    if ($knownSha.ContainsKey($choice)) {
        if ($sha -ne $knownSha[$choice]) {
            throw "image SHA256 mismatch: expected $($knownSha[$choice]) got $sha. Abort."
        }
        Write-Host "IMAGE_SHA_OK $sha  (matches final r5 firmware image)" -ForegroundColor Green
    } else {
        Write-Host ("IMAGE_SHA256 {0}  (informational)" -f $sha) -ForegroundColor DarkGray
    }

    # ---------- 目标盘检测与安全校验 (默认 E:) ----------
    $devLetter = 'E'
    $vol = Get-Volume -DriveLetter $devLetter -ErrorAction SilentlyContinue
    if (-not $vol) {
        throw "Drive $($devLetter): not found. 请插入 SD 测试卡并确认盘符为 $($devLetter): 后重试。"
    }
    $sysRoot = $env:SystemDrive.ToUpper()
    if ("$($devLetter):" -ieq $sysRoot) {
        throw "拒绝: $($devLetter): 是系统盘, 禁止覆盖。"
    }
    $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($devLetter):'"
    $dt = $ld.DriveType   # 2=Removable, 3=LocalDisk
    $isCard = $true
    if ($dt -ne 2) {
        if ($dt -eq 3 -and $vol.Size -lt (4GB) -and -not (Test-Path "$($devLetter):\Windows")) {
            Write-Host "注意: $($devLetter): 显示为本地盘但体积小且非系统盘, 按 SD 卡处理。" -ForegroundColor Yellow
        } else {
            throw "拒绝: $($devLetter): DriveType=$dt 不是可移动 SD 卡。请确认盘符/读卡器。"
        }
    }
    Write-Host ("Target raw device: \\.\{0}:  ({1} bytes = {2} MB)" -f $devLetter, $total, [math]::Round($total/1MB,1)) -ForegroundColor Yellow
    Write-Host ("Writing {0}" -f $img) -ForegroundColor Yellow

    # ---------- 底层写入 + 写后回读校验 ----------
    $py = Join-Path $env:TEMP 'vf_write_evol.py'
    $pyCode = @"
import ctypes, sys, time, hashlib
from ctypes import wintypes
from pathlib import Path
img = Path(r'''$img''').read_bytes()
total = len(img)
dev = r'''\\.\$($devLetter):'''
src_sha = hashlib.sha256(img).hexdigest()
k32 = ctypes.windll.kernel32
h = k32.CreateFileW(dev, 0xC0000000, 0x3, None, 3, 0, None)
if h == wintypes.HANDLE(-1).value: raise ctypes.WinError()
ret = wintypes.DWORD()
if not k32.DeviceIoControl(h, 0x00090018, None, 0, None, 0, ctypes.byref(ret), None):
    k32.CloseHandle(h); raise ctypes.WinError()
print('LOCK_OK', flush=True)
try:
    written = wintypes.DWORD(); off = 0; t0 = time.time(); CHUNK = 4*1024*1024
    while off < total:
        chunk = img[off:off+CHUNK]
        if not k32.WriteFile(h, chunk, len(chunk), ctypes.byref(written), None):
            raise ctypes.WinError()
        off += written.value
        pct = off*100//total; mb = off/1024/1024
        speed = off/1024/1024/(time.time()-t0) if time.time()-t0>0 else 0
        print(f'  {off}/{total} ({pct}%) {mb:.1f}MB  {speed:.2f} MB/s', flush=True)
    if not k32.FlushFileBuffers(h): raise ctypes.WinError()
    print(f'WRITE_OK {off} bytes in {time.time()-t0:.1f}s', flush=True)
finally:
    k32.DeviceIoControl(h, 0x00090020, None, 0, None, 0, ctypes.byref(ret), None)
    k32.CloseHandle(h)
    print('UNLOCK_OK', flush=True)

# ---- 回读校验: 重开原始设备读回整盘, 哈希须与源镜像一致 ----
h2 = k32.CreateFileW(dev, 0x80000000, 0x3, None, 3, 0, None)  # GENERIC_READ
if h2 == wintypes.HANDLE(-1).value: raise ctypes.WinError()
try:
    buf = ctypes.create_string_buffer(CHUNK); have = 0; hsh = hashlib.sha256()
    while have < total:
        toread = min(CHUNK, total - have)
        rd = wintypes.DWORD()
        if not k32.ReadFile(h2, buf, toread, ctypes.byref(rd), None): raise ctypes.WinError()
        if rd.value == 0: break
        hsh.update(buf.raw[:rd.value]); have += rd.value
    rb_sha = hsh.hexdigest()
    print(f'READBACK_VERIFY have={have} sha={rb_sha} src={src_sha}', flush=True)
    if have != total or rb_sha != src_sha:
        print('VERIFY_FAIL', flush=True); sys.exit(3)
    print('VERIFY_OK', flush=True)
finally:
    k32.CloseHandle(h2)
"@
    [IO.File]::WriteAllText($py, $pyCode, (New-Object Text.UTF8Encoding($false)))
    python $py
    if ($LASTEXITCODE -ne 0) { throw "write/verify failed (exit $LASTEXITCODE)" }
    Start-Sleep -Seconds 2
    $v2 = Get-Volume -DriveLetter $devLetter
    if ($v2) {
        Write-Host ("$($devLetter): now {0}MB" -f [int]($v2.Size/1MB)) -ForegroundColor Green
        Get-ChildItem "$($devLetter):\" -Force -ErrorAction SilentlyContinue | Select-Object Length, Name | Format-Table -AutoSize
    }
    Write-Host "`n=== DONE, safe to eject ===" -ForegroundColor Green
    Add-Content -LiteralPath $logFile -Value ((Get-Date -Format s) + "  OK  " + $img + " -> " + $devLetter + ":")
}
catch {
    Write-Host "`n=== FAILED ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Add-Content -LiteralPath $logFile -Value ((Get-Date -Format s) + "  FAIL  " + $_.Exception.Message)
}
finally {
    # 无论成功/失败都暂停, 防止自动模式窗口闪退导致看不到结果
    Write-Host "`nPress Enter to close..." -ForegroundColor Yellow
    Read-Host | Out-Null
}
