# build-rcz80std.ps1
# Builds the RCZ80 std configuration for RomWBW
# Generates rcz80std ROM files and disk images

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$romPath = Join-Path $repoRoot 'Binary\rcz80std.rom'

function Invoke-CmdBuild {
    param(
        [Parameter(Mandatory)][string]$WorkingDir,
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$PhaseName,
        [string[]]$FatalPatterns = @()
    )

    Push-Location $WorkingDir
    try {
        $null = & cmd /c $CommandLine 2>&1 | Tee-Object -Variable BuildOutput
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $buildText = ($BuildOutput | Out-String)
    if ($exitCode -ne 0) {
        throw "$PhaseName failed with exit code $exitCode."
    }

    foreach ($pattern in $FatalPatterns) {
        if ($buildText -match $pattern) {
            throw "$PhaseName reported fatal output matching pattern: $pattern"
        }
    }
}

Write-Host 'Building RCZ80 std configuration...' -ForegroundColor Cyan

try {
    Set-Location $repoRoot

    $buildStartUtc = (Get-Date).ToUniversalTime()
    $romBeforeUtc = $null
    if (Test-Path $romPath) {
        $romBeforeUtc = (Get-Item $romPath).LastWriteTimeUtc
    }

    # Build HBIOS ROM
    Write-Host "`nBuilding HBIOS ROM..." -ForegroundColor Yellow
    Invoke-CmdBuild -WorkingDir (Join-Path $repoRoot 'Source\HBIOS') `
        -CommandLine 'Build.cmd RCZ80 std rcz80std' `
        -PhaseName 'HBIOS build' `
        -FatalPatterns @('\*\*\* ERROR:', 'Number of errors = [1-9]')

    # Verify ROM artifact freshness so stale files do not look like a successful rebuild.
    if (-not (Test-Path $romPath)) {
        throw "HBIOS build did not produce expected ROM file: $romPath"
    }
    $romAfterUtc = (Get-Item $romPath).LastWriteTimeUtc
    if ($romAfterUtc -lt $buildStartUtc) {
        throw "ROM timestamp was not updated by this build (still $romAfterUtc UTC)."
    }
    if ($romBeforeUtc -and $romAfterUtc -le $romBeforeUtc) {
        throw "ROM timestamp did not advance (before: $romBeforeUtc UTC, after: $romAfterUtc UTC)."
    }

    # Build disk images
    Write-Host "`nBuilding disk images..." -ForegroundColor Yellow
    Invoke-CmdBuild -WorkingDir (Join-Path $repoRoot 'Source\Images') `
        -CommandLine 'Build.cmd' `
        -PhaseName 'Disk image build'

    # Display results
    Set-Location $repoRoot
    Write-Host "`nBuild completed!" -ForegroundColor Green
    Write-Host "`nROM files in Binary/:" -ForegroundColor Cyan
    Get-ChildItem Binary/rcz80std.* -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $_" }

    Write-Host "`nhd1k disk images in Binary/:" -ForegroundColor Cyan
    Get-ChildItem Binary/hd1k_*.img -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $_" }
}
catch {
    Set-Location $repoRoot
    Write-Host "`nBuild failed with error: $_" -ForegroundColor Red
    exit 1
}
