@echo off
setlocal EnableDelayedExpansion
title Ash Language Installer

:: ─────────────────────────────────────────────────────────────────
:: Ash Language Installer for Windows
:: Ships inside the release zip alongside bin\ and runtime\
::
:: Release layout:
::   ash\
::     install.bat          <- this file
::     bin\ash.exe
::     runtime\ash_runtime.c
::     runtime\ash_runtime.h
::     examples\hello.ash
::
:: Installs to:
::   %USERPROFILE%\AppData\Local\ash\
::     bin\ash.exe
::     runtime\ash_runtime.c
::     runtime\ash_runtime.h
::
:: Adds  %USERPROFILE%\AppData\Local\ash\bin  to user PATH.
:: ─────────────────────────────────────────────────────────────────

echo.
echo  ┌──────────────────────────────────────────┐
echo  │   Ash Programming Language  - Installer  │
echo  └──────────────────────────────────────────┘
echo.

:: Work relative to wherever this script lives
set SCRIPT_DIR=%~dp0
:: Strip trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

set SRC_BIN=%SCRIPT_DIR%\bin
set SRC_RUNTIME=%SCRIPT_DIR%\runtime

:: Verify source files exist before doing anything
if not exist "%SRC_BIN%\ash.exe" (
    echo  ERROR: bin\ash.exe not found next to install.bat
    echo  Make sure you extracted the full zip before running this.
    goto :fail
)
if not exist "%SRC_RUNTIME%\ash_runtime.c" (
    echo  ERROR: runtime\ash_runtime.c not found
    goto :fail
)

:: Check zig is available (required at compile time by ash)
where zig >nul 2>&1
if errorlevel 1 (
    echo  ERROR: 'zig' is not installed or not in PATH.
    echo.
    echo  Ash requires Zig to compile your programs.
    echo  Download from: https://ziglang.org/download/
    echo  Then re-run this installer.
    goto :fail
)
for /f "tokens=*" %%v in ('zig version 2^>nul') do set ZIG_VER=%%v
echo  Found zig %ZIG_VER%

:: Install destination
set ASH_HOME=%USERPROFILE%\AppData\Local\ash
set DST_BIN=%ASH_HOME%\bin
set DST_RUNTIME=%ASH_HOME%\runtime

echo  Installing to: %ASH_HOME%
echo.

:: Create directories
if not exist "%DST_BIN%"     mkdir "%DST_BIN%"
if not exist "%DST_RUNTIME%" mkdir "%DST_RUNTIME%"

:: Copy files
echo  Copying ash.exe...
copy /Y "%SRC_BIN%\ash.exe"              "%DST_BIN%\ash.exe"          >nul
echo  Copying runtime...
copy /Y "%SRC_RUNTIME%\ash_runtime.c"   "%DST_RUNTIME%\ash_runtime.c" >nul
copy /Y "%SRC_RUNTIME%\ash_runtime.h"   "%DST_RUNTIME%\ash_runtime.h" >nul

:: ── Add bin\ to user PATH ──────────────────────────────────────────
echo  Updating PATH...

:: Read current user PATH from registry
set "CURRENT_PATH="
for /f "skip=2 tokens=2,*" %%A in (
    'reg query "HKCU\Environment" /v PATH 2^>nul'
) do set "CURRENT_PATH=%%B"

:: Check if already present
echo !CURRENT_PATH! | findstr /i /c:"%DST_BIN%" >nul 2>&1
if not errorlevel 1 (
    echo  PATH already contains %DST_BIN% - skipping.
) else (
    if defined CURRENT_PATH (
        setx PATH "%DST_BIN%;!CURRENT_PATH!" >nul
    ) else (
        setx PATH "%DST_BIN%" >nul
    )
    echo  Added to PATH: %DST_BIN%
)

:: ── Done ──────────────────────────────────────────────────────────
echo.
echo  ✓  Ash installed successfully!
echo.
echo     ash.exe   →  %DST_BIN%\ash.exe
echo     runtime   →  %DST_RUNTIME%\
echo.
echo  Open a NEW terminal window, then try:
echo.
echo     ash version
echo     ash init
echo     ash run main.ash
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
