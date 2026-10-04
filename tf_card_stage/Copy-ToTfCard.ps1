[CmdletBinding()]
param(
    [string]$DriveLetter = "E",
    [string]$SourceDir = "",
    [switch]$Format,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Ok([string]$Message) {
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

$drive = $DriveLetter.TrimEnd(":")
$targetRoot = "${drive}:\"
$targetFiles = @("PIC1.BMP", "PIC2.BMP", "PIC3.BMP", "PIC4.BMP", "AUDIO.PCM")

Info "Source directory: $SourceDir"
Info "Target volume   : $targetRoot"

if (-not (Test-Path -LiteralPath $targetRoot)) {
    Fail "Target drive $targetRoot is not mounted. Insert the TF card and check Disk Management."
}

$missing = @()
foreach ($name in $targetFiles) {
    $path = Join-Path $SourceDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $missing += $name
    }
}
if ($missing.Count -ne 0) {
    Fail ("Missing staging files: " + ($missing -join ", "))
}

$bmpNames = @("PIC1.BMP", "PIC2.BMP", "PIC3.BMP", "PIC4.BMP")
foreach ($name in $bmpNames) {
    $path = Join-Path $SourceDir $name
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $size = $bytes.Length
    if ($size -lt 54) {
        Fail "$name is too small to be a BMP file."
    }
    $offset = [BitConverter]::ToInt32($bytes, 10)
    $width = [BitConverter]::ToInt32($bytes, 18)
    $height = [BitConverter]::ToInt32($bytes, 22)
    $bits = [BitConverter]::ToInt16($bytes, 28)
    $compression = [BitConverter]::ToInt32($bytes, 30)
    if (($width -ne 640) -or ($height -ne 480) -or ($bits -ne 24) -or ($compression -ne 0)) {
        Fail "$name must be 640x480, 24-bit, uncompressed BMP. Got ${width}x${height}, ${bits}bit, compression=$compression."
    }
    Ok "${name}: ${width}x${height}, ${bits}bit, header offset=$offset, size=$size"
}

$pcmPath = Join-Path $SourceDir "AUDIO.PCM"
$pcmSize = (Get-Item -LiteralPath $pcmPath).Length
if (($pcmSize % 512) -ne 0) {
    Fail "AUDIO.PCM must be padded to a 512-byte sector boundary. Current size=$pcmSize."
}
if ($pcmSize -le 512) {
    Fail "AUDIO.PCM is unexpectedly small: $pcmSize bytes."
}
Ok "AUDIO.PCM: $pcmSize bytes, $($pcmSize / 512) sectors, 512-byte aligned"

$volume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive`:'"
if ($null -eq $volume) {
    Fail "Could not query logical volume $targetRoot."
}

Info "Current filesystem: $($volume.FileSystem), free space: $([math]::Round($volume.FreeSpace / 1MB, 2)) MB"

if ($Format) {
    if (-not $Force) {
        Fail "Formatting erases the whole card. Re-run with -Format -Force only after confirming the target drive."
    }
    if ($volume.FileSystem -ne "FAT32") {
        Info "The drive will be formatted as FAT32."
    }
    Info "Formatting $targetRoot as FAT32. This erases all existing card contents."
    Format-Volume -DriveLetter $drive -FileSystem FAT32 -NewFileSystemLabel "VINYLFPGA" -Confirm:$false | Out-Null
    Ok "Format completed."
}
else {
    if ($volume.FileSystem -ne "FAT32") {
        Fail "Target volume is $($volume.FileSystem), not FAT32. Re-run with -Format -Force to erase and format it."
    }
}

$requiredBytes = 0
foreach ($name in $targetFiles) {
    $requiredBytes += (Get-Item -LiteralPath (Join-Path $SourceDir $name)).Length
}
$freeBytes = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive`:'").FreeSpace
if ($freeBytes -lt $requiredBytes) {
    Fail "Not enough free space. Required=$requiredBytes bytes, free=$freeBytes bytes."
}

Info "Copying in the required order: PIC1..PIC4 first, AUDIO.PCM last."
foreach ($name in $targetFiles) {
    $source = Join-Path $SourceDir $name
    $dest = Join-Path $targetRoot $name
    Copy-Item -LiteralPath $source -Destination $dest -Force
    $srcSize = (Get-Item -LiteralPath $source).Length
    $dstSize = (Get-Item -LiteralPath $dest).Length
    if ($srcSize -ne $dstSize) {
        Fail "Size mismatch after copying $name. source=$srcSize target=$dstSize"
    }
    Ok "Copied $name ($dstSize bytes)"
}

try {
    Write-VolumeCache -DriveLetter $drive -ErrorAction Stop
    Ok "Volume write cache flushed."
}
catch {
    Info "Write-VolumeCache failed (this is often a non-admin limitation). Use Windows safe eject before removing the card."
}

Info "Final root directory:"
Get-ChildItem -LiteralPath $targetRoot -Force |
    Where-Object { $targetFiles -contains $_.Name } |
    Select-Object Name, Length |
    Format-Table -AutoSize

Ok "TF card staging copy completed. Safe eject the card before board power-up."
