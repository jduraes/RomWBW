param(
    [string]$PathA = "C:\Users\miguel\Documents\development\RomWBW",
    [string]$PathB = "Z:\RomWBW",
    [string]$LogPath = "C:\Users\miguel\romwbw_sync.log"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

function Ensure-ParentDirectory {
    param([string]$TargetPath)
    $parent = Split-Path -Path $TargetPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
}

function Copy-FileWithTimestamp {
    param(
        [string]$FromPath,
        [string]$ToPath
    )
    Ensure-ParentDirectory -TargetPath $ToPath
    Copy-Item -LiteralPath $FromPath -Destination $ToPath -Force
    $src = Get-Item -LiteralPath $FromPath
    $dst = Get-Item -LiteralPath $ToPath
    $dst.LastWriteTimeUtc = $src.LastWriteTimeUtc
}

function Get-RelativeFileMap {
    param([string]$RootPath)
    $map = @{}
    $rootResolved = (Resolve-Path -LiteralPath $RootPath).Path
    $rootPrefix = $rootResolved.TrimEnd('\') + '\'

    Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force | ForEach-Object {
        $fullPath = $_.FullName
        $relative = $fullPath.Substring($rootPrefix.Length)
        $key = $relative.ToLowerInvariant()
        $map[$key] = [PSCustomObject]@{
            RelativePath = $relative
            FullPath     = $fullPath
            Length       = $_.Length
            LastWriteUtc = $_.LastWriteTimeUtc
        }
    }

    return $map
}

if (-not (Test-Path -LiteralPath $PathA)) {
    throw "PathA not found: $PathA"
}
if (-not (Test-Path -LiteralPath $PathB)) {
    throw "PathB not found: $PathB"
}

Write-Log "Two-way sync started."
Write-Log "PathA: $PathA"
Write-Log "PathB: $PathB"

$filesA = Get-RelativeFileMap -RootPath $PathA
$filesB = Get-RelativeFileMap -RootPath $PathB
$allKeys = [System.Collections.Generic.HashSet[string]]::new()

foreach ($k in $filesA.Keys) { [void]$allKeys.Add($k) }
foreach ($k in $filesB.Keys) { [void]$allKeys.Add($k) }

$copiedAToB = 0
$copiedBToA = 0
$unchanged = 0

foreach ($key in $allKeys) {
    $hasA = $filesA.ContainsKey($key)
    $hasB = $filesB.ContainsKey($key)

    if ($hasA -and -not $hasB) {
        $a = $filesA[$key]
        $target = Join-Path $PathB $a.RelativePath
        Copy-FileWithTimestamp -FromPath $a.FullPath -ToPath $target
        Write-Log "A->B (new in A): $($a.RelativePath)"
        $copiedAToB++
        continue
    }

    if ($hasB -and -not $hasA) {
        $b = $filesB[$key]
        $target = Join-Path $PathA $b.RelativePath
        Copy-FileWithTimestamp -FromPath $b.FullPath -ToPath $target
        Write-Log "B->A (new in B): $($b.RelativePath)"
        $copiedBToA++
        continue
    }

    $a = $filesA[$key]
    $b = $filesB[$key]

    if ($a.LastWriteUtc -gt $b.LastWriteUtc) {
        $target = Join-Path $PathB $a.RelativePath
        Copy-FileWithTimestamp -FromPath $a.FullPath -ToPath $target
        Write-Log "A->B (A newer): $($a.RelativePath)"
        $copiedAToB++
        continue
    }

    if ($b.LastWriteUtc -gt $a.LastWriteUtc) {
        $target = Join-Path $PathA $b.RelativePath
        Copy-FileWithTimestamp -FromPath $b.FullPath -ToPath $target
        Write-Log "B->A (B newer): $($b.RelativePath)"
        $copiedBToA++
        continue
    }

    if ($a.Length -ne $b.Length) {
        if ($a.Length -gt $b.Length) {
            $target = Join-Path $PathB $a.RelativePath
            Copy-FileWithTimestamp -FromPath $a.FullPath -ToPath $target
            Write-Log "A->B (same time, larger A): $($a.RelativePath)"
            $copiedAToB++
        }
        else {
            $target = Join-Path $PathA $b.RelativePath
            Copy-FileWithTimestamp -FromPath $b.FullPath -ToPath $target
            Write-Log "B->A (same time, larger B): $($b.RelativePath)"
            $copiedBToA++
        }
        continue
    }

    $unchanged++
}

Write-Log "Two-way sync completed. A->B copied: $copiedAToB; B->A copied: $copiedBToA; unchanged: $unchanged; total files considered: $($allKeys.Count)"
