$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\miguel\Documents\development\RomWBW\Tools\cpmtools'
& .\cpmcp.exe -f wbw_hd1k_4 '\\.\PhysicalDrive8' '0:cpm3.sys' "$env:TEMP\oncard_cpm3.sys" | Out-Null
$hits = (Select-String -Path "$env:TEMP\oncard_cpm3.sys" -Pattern 'CTRL-\' -SimpleMatch).Count
$old = (Select-String -Path "$env:TEMP\oncard_cpm3.sys" -Pattern 'CTRL-V' -SimpleMatch).Count
Write-Host "CTRL-\ occurrences on card: $hits ; CTRL-V occurrences: $old"
