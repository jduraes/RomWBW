$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = "C:\Users\miguel\Documents\development\RomWBW\Backup\cf-physicaldrive8-$stamp.img"
$total = [int64](Get-Disk -Number 8).Size
$fs = [IO.File]::Open('\\.\PhysicalDrive8','Open','Read','ReadWrite')
$out = [IO.File]::Create($dest)
$buf = New-Object byte[] 1MB
$remaining = $total
while ($remaining -gt 0) {
    $n = $fs.Read($buf, 0, [int][Math]::Min($buf.Length, $remaining))
    if ($n -le 0) { break }
    $out.Write($buf, 0, $n)
    $remaining -= $n
}
$out.Close(); $fs.Close()
Write-Host "backup: $dest"
Write-Host ("expected: $total  written: " + (Get-Item $dest).Length)
