<#
.SYNOPSIS
  In-place RomWBW 3.7 CF upgrade: updates system images and stock utilities per slice.
  Does NOT write hd1k_combo.img to LBA 0 (preserves user areas on slices 6+ and custom files).
#>
param(
    [int]$DiskNumber = 5,
    [string]$DriveLetter = 'L',
    [string]$RepoRoot = $PSScriptRoot,
    [switch]$WhatIf,
    [switch]$UsePhysicalDisk
)

$ErrorActionPreference = 'Stop'
$cpmDir = Join-Path $RepoRoot 'Tools\cpmtools'
$combo = Join-Path $RepoRoot 'Binary\hd1k_combo.img'
if ($UsePhysicalDisk) {
    $diskPath = "\\.\PhysicalDrive$DiskNumber"
    $fmtPrefix = 'wbw_hd1k_'
    $diskdefsExtra = Join-Path $cpmDir 'diskdefs_hd1k_extra'
} else {
    $diskPath = "\\.\${DriveLetter}:"
    $fmtPrefix = 'wbw_hd1k_vol_'
    $diskdefsExtra = Join-Path $cpmDir 'diskdefs_hd1k_volume'
}
$backupDir = Join-Path $RepoRoot 'Backup'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path $backupDir "cf-physicaldrive$DiskNumber-$stamp.img"
$tempDir = Join-Path $env:TEMP "romwbw-cf-patch-$stamp"

# cpmtools on Windows reads ./diskdefs from the tool directory (CPMTOOLSDSK is unreliable).
$diskdefsBak = Join-Path $cpmDir 'diskdefs.bak'
$diskdefsMain = Join-Path $cpmDir 'diskdefs'
if (-not (Test-Path $diskdefsBak)) { Copy-Item $diskdefsMain $diskdefsBak -Force }
$diskdefsExtra2 = Join-Path $cpmDir 'diskdefs_hd1k_extra'
Get-Content $diskdefsBak, $diskdefsExtra, $diskdefsExtra2 | Set-Content $diskdefsMain -Encoding ASCII

function Invoke-Cpm([string[]]$CpmArgs) {
    Push-Location $cpmDir
    try {
        $exe = Join-Path $cpmDir $CpmArgs[0]
        $out = & $exe @($CpmArgs[1..($CpmArgs.Length - 1)]) 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw ($out | Out-String) }
        return $out
    } finally { Pop-Location }
}

function Test-SlicePopulated([string]$Fmt, [string]$Image) {
    try {
        $listing = Invoke-Cpm @('cpmls.exe', '-l', '-f', $Fmt, $Image) 2>$null
        return ($listing -match '\S')
    } catch { return $false }
}

function Copy-CpmFile([string]$DstFmt, [string]$SrcImage, [string]$SrcSpec, [string]$DstImage, [string]$DstSpec, [string]$SrcFmt) {
    if (-not $SrcFmt) { $SrcFmt = $DstFmt }
    $leaf = ($SrcSpec -split ':', 2)[-1]
    $local = Join-Path $tempDir $leaf
    New-Item -ItemType Directory -Path (Split-Path $local) -Force | Out-Null
    if ($WhatIf) {
        Write-Host "  [WhatIf] $SrcImage $SrcSpec -> $DstImage $DstSpec" -ForegroundColor DarkGray
        return
    }
    if (Test-Path $local) { Remove-Item $local -Force }
    Invoke-Cpm @('cpmcp.exe', '-f', $SrcFmt, $SrcImage, $SrcSpec, $local) | Out-Null
    try { Invoke-Cpm @('cpmrm.exe', '-f', $DstFmt, $DstImage, $DstSpec) | Out-Null } catch { }
    Invoke-Cpm @('cpmcp.exe', '-f', $DstFmt, $DstImage, $local, $DstSpec) | Out-Null
}

if (-not (Test-Path $combo)) { throw "Missing combo image: $combo" }
if (-not (Test-Path $cpmDir)) { throw "Missing cpmtools: $cpmDir" }

Write-Host "RomWBW in-place CF update" -ForegroundColor Cyan
Write-Host "  Target: $diskPath"
Write-Host "  Source: $combo (3.7.0 stock files)"
Write-Host ""

# Quick access test
try { Invoke-Cpm @('cpmls.exe', '-l', '-f', "${fmtPrefix}0", $diskPath) | Select-Object -First 3 | Out-Null }
catch { throw "Cannot read $diskPath. For PhysicalDrive use -UsePhysicalDisk and run as Administrator." }

New-Item -ItemType Directory -Path $backupDir, $tempDir -Force | Out-Null

$part = Get-Partition -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
if ($UsePhysicalDisk) {
    $backupSize = (Get-Item $combo).Length
} else {
    $disk = Get-Disk -Number $part.DiskNumber
    $backupSize = [int64]$disk.Size - [int64]$part.Offset
}
Write-Host "Backing up $backupSize bytes to $backupPath ..." -ForegroundColor Yellow
if (-not $WhatIf) {
    $fs = [System.IO.File]::Open($diskPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $out = [System.IO.File]::Create($backupPath)
        try {
            if ($UsePhysicalDisk) { $fs.CopyTo($out) }
            else {
                $buf = New-Object byte[] 65536
                $remaining = $backupSize
                while ($remaining -gt 0) {
                    $read = [Math]::Min($buf.Length, $remaining)
                    $n = $fs.Read($buf, 0, $read)
                    if ($n -le 0) { break }
                    $out.Write($buf, 0, $n)
                    $remaining -= $n
                }
            }
        } finally { $out.Close() }
    } finally { $fs.Close() }
    Write-Host "  Backup OK" -ForegroundColor Green
} else {
    Write-Host "  [WhatIf] skip backup" -ForegroundColor DarkGray
}

# Per-slice: system file on 0: and RomWBW utilities from combo (stock paths only)
$slicePlan = @(
    @{ Fmt = "${fmtPrefix}0"; SrcFmt = 'wbw_hd1k_0'; Label = 'CP/M 2.2';  Sys = @('0:cpm.sys') }
    @{ Fmt = "${fmtPrefix}1"; SrcFmt = 'wbw_hd1k_1'; Label = 'ZSDOS';    Sys = @('0:zsys.sys') }
    @{ Fmt = "${fmtPrefix}2"; SrcFmt = 'wbw_hd1k_2'; Label = 'NZ-COM';   Sys = @('0:zsys.sys') }
    @{ Fmt = "${fmtPrefix}3"; SrcFmt = 'wbw_hd1k_3'; Label = 'CP/M 3';    Sys = @('0:cpmldr.sys', '0:cpm3.sys', '0:cpm3res.sys', '0:cpm3bnk.sys') }
    @{ Fmt = "${fmtPrefix}4"; SrcFmt = 'wbw_hd1k_4'; Label = 'ZPM3';     Sys = @('0:zpmldr.sys', '0:cpm3.sys') }
    @{ Fmt = "${fmtPrefix}5"; SrcFmt = 'wbw_hd1k_5'; Label = 'WordProc'; Sys = @('0:zsys.sys') }
)

$utilityNames = @(
    'assign.com','bbcbasic.com','bbcbasic.txt','cpuspd.com','reboot.com','copysl.com','copysl.doc',
    'fat.com','fdu.com','fdu.doc','format.com','mode.com','rtc.com','slabel.com','survey.com',
    'syscopy.com','sysgen.com','talk.com','htalk.com','tbasic.com','timer.com','tune.com','xm.com',
    'zmp.com','zmp.hlp','zmp.doc','zmp.cfg','zmp.fon','zmxfer.ovr','zmterm.ovr','zminit.ovr',
    'zmconfig.ovr','zmd.com','vgmplay.com','vgminfo.com'
)

foreach ($s in $slicePlan) {
    Write-Host "Slice $($s.Fmt): $($s.Label)" -ForegroundColor Cyan
    if (-not (Test-SlicePopulated $s.Fmt $diskPath)) {
        Write-Host "  (empty or unreadable - skip)" -ForegroundColor DarkYellow
        continue
    }
    foreach ($spec in $s.Sys) {
        try {
            Copy-CpmFile $s.Fmt $combo $spec $diskPath $spec -SrcFmt $s.SrcFmt
            Write-Host "  updated $spec" -ForegroundColor Green
        } catch {
            Write-Host "  skip $spec ($($_.Exception.Message.Trim()))" -ForegroundColor DarkYellow
        }
    }
    $utilOk = 0
    foreach ($name in $utilityNames) {
        $spec = "0:$name"
        try {
            Copy-CpmFile $s.Fmt $combo $spec $diskPath $spec -SrcFmt $s.SrcFmt
            $utilOk++
        } catch { }
    }
    Write-Host "  utilities synced: $utilOk files" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Reboot SC720 from CF; HBIOS/CBIOS mismatch warning should be gone." -ForegroundColor Green
Write-Host "Backup: $backupPath" -ForegroundColor Gray
if (-not $WhatIf) {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
