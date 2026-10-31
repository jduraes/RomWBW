@echo off
rem ==============================================================================
rem  Build hbconfig.exe (RomWBW HBIOS config tool) on Windows.
rem  Requires gcc (MinGW-w64 / winlibs) on PATH.  Produces hbconfig.exe here.
rem ==============================================================================
setlocal
where gcc >nul 2>nul
if errorlevel 1 (
    echo hbconfig: gcc not found on PATH. Install MinGW-w64 GCC ^(e.g. scoop install mingw-winlibs^).
    exit /b 1
)
gcc -O2 -Wall -Wextra -std=c11 -o hbconfig.exe hbconfig.c
if errorlevel 1 exit /b 1
echo Built hbconfig.exe
