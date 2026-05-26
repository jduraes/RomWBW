# write-hd1k-combo-to-cf.ps1
# Writes RomWBW hd1k_combo.img (3.7.0) to a physical disk (CF/USB hard disk).
# MUST run as Administrator.
#
# Usage:
#   .\write-hd1k-combo-to-cf.ps1
#   .\write-hd1k-combo-to-cf.ps1 -DiskNumber 5
#   .\write-hd1k-combo-to-cf.ps1 -DiskNumber 5 -Force

param(
    [int]$DiskNumber = 5,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$imagePath = Join-Path $PSScriptRoot "Binary\hd1k_combo.img"
if (-not (Test-Path $imagePath)) {
    throw "Missing $imagePath — run build-sc720std.ps1 first."
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$imageSize = (Get-Item $imagePath).Length

Write-Host ""
Write-Host "RomWBW CF / hard disk update (hd1k_combo.img)" -ForegroundColor Cyan
Write-Host "  Image:  $imagePath"
Write-Host "  Size:   $imageSize bytes ($([math]::Round($imageSize/1MB, 1)) MB)"
Write-Host ""
Write-Host "Target physical disk:" -ForegroundColor Yellow
$disk | Format-Table Number, FriendlyName, @{N='SizeMB';E={[math]::Round($_.Size/1MB,1)}}, PartitionStyle, OperationalStatus -AutoSize

if ($imageSize -gt $disk.Size) {
    throw "Image is larger than the target disk."
}

Write-Host "This writes the first ~49 MB (partition table + slices 0-5:" -ForegroundColor Yellow
Write-Host "  CP/M 2.2, ZSDOS, NZCOM, CP/M 3, ZPM3, WordStar)." -ForegroundColor Yellow
Write-Host "Slices 6+ on the card are NOT overwritten (if your card is larger)." -ForegroundColor Yellow
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Type YES to write to PhysicalDrive$DiskNumber"
    if ($confirm -ne 'YES') {
        Write-Host "Aborted." -ForegroundColor Red
        exit 1
    }
}

# Offline disk so Windows releases the volume
Set-Disk -Number $DiskNumber -IsOffline $true

try {
    $diskPath = "\\.\PhysicalDrive$DiskNumber"
    $img = [System.IO.File]::ReadAllBytes($imagePath)
    $stream = [System.IO.File]::Open($diskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
    try {
        $stream.Write($img, 0, $img.Length)
        $stream.Flush()
    } finally {
        $stream.Close()
    }
    Write-Host ""
    Write-Host "SUCCESS: Wrote hd1k_combo.img to PhysicalDrive$DiskNumber" -ForegroundColor Green
    Write-Host "Safely eject the card, reinstall on SC720, boot from hard disk (IDE0)." -ForegroundColor Green
} finally {
    Set-Disk -Number $DiskNumber -IsOffline $false
}
