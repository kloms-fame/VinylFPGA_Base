# VinylFPGA card flasher
$host.UI.RawUI.WindowTitle = "VinylFPGA write_card"
$ErrorActionPreference = 'Stop'

try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Not Administrator. Launch via write_card.bat instead."
    }

    Write-Host "=== VinylFPGA card flasher ===" -ForegroundColor Cyan
    Write-Host "S4 acceptance:"
    Write-Host "  1 = card_A.img         (good index + PIC1~4, only Track1 audio)"
    Write-Host "  2 = card_A_broken.img   (bad index + PIC1~4)"
    Write-Host "  3 = card_SONG.img       (good index + SONG1~4, no PIC)"
    Write-Host "  4 = card_B_broken.img   (bad index + SONG1~4, no PIC)"
    Write-Host "S5 acceptance:"
    Write-Host "  5 = card_S5.img         (good index + PIC1~4, ALL 4 songs share AUDIO.PCM)"
    $choice = Read-Host "`nEnter choice (1-5)"

    $map = @{
        '1' = 'card_A.img'
        '2' = 'card_A_broken.img'
        '3' = 'card_SONG.img'
        '4' = 'card_B_broken.img'
        '5' = 'card_S5.img'
    }
    if (-not $map.ContainsKey($choice)) { throw "invalid choice" }
    $img = Join-Path $PSScriptRoot $map[$choice]
    if (-not (Test-Path $img)) { throw "image not found: $img" }
    Write-Host ("`nWriting {0} ({1} bytes)" -f $img, (Get-Item $img).Length) -ForegroundColor Yellow

    $py = Join-Path $env:TEMP 'vf_write_evol.py'
    $pyCode = @"
import ctypes
from ctypes import wintypes
from pathlib import Path
img = Path(r'''$img''').read_bytes()
k32 = ctypes.windll.kernel32
h = k32.CreateFileW(r'\\.\E:', 0xC0000000, 0x3, None, 3, 0, None)
if h == wintypes.HANDLE(-1).value: raise ctypes.WinError()
ret = wintypes.DWORD()
if not k32.DeviceIoControl(h, 0x00090018, None, 0, None, 0, ctypes.byref(ret), None):
    k32.CloseHandle(h); raise ctypes.WinError()
print('LOCK_OK')
try:
    written = wintypes.DWORD(); off = 0
    while off < len(img):
        chunk = img[off:off+4194304]
        if not k32.WriteFile(h, chunk, len(chunk), ctypes.byref(written), None):
            raise ctypes.WinError()
        off += written.value
    if not k32.FlushFileBuffers(h): raise ctypes.WinError()
    print('WRITE_OK', len(img))
finally:
    k32.DeviceIoControl(h, 0x00090020, None, 0, None, 0, ctypes.byref(ret), None)
    k32.CloseHandle(h)
    print('UNLOCK_OK')
"@
    [IO.File]::WriteAllText($py, $pyCode, (New-Object Text.UTF8Encoding($false)))
    python $py
    if ($LASTEXITCODE -ne 0) { throw "write failed" }
    Start-Sleep -Seconds 2
    $v2 = Get-Volume -DriveLetter E
    if ($v2) {
        Write-Host ("E: now {0}MB" -f [int]($v2.Size/1MB)) -ForegroundColor Green
        Get-ChildItem E:\ -Force -ErrorAction SilentlyContinue | Select-Object Length, Name | Format-Table -AutoSize
    }
    Write-Host "`n=== DONE, safe to eject ===" -ForegroundColor Green
}
catch {
    Write-Host "`n=== FAILED ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Write-Host "`nPress Enter to close..." -ForegroundColor Yellow
    Read-Host | Out-Null
}