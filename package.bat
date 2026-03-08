@echo off
:: package.bat — builds ash.exe and creates the release zip
:: Run this from the ash source root after cloning.
:: Requires: zig, powershell (for zip)

setlocal
echo Building ash compiler...
zig build -Doptimize=ReleaseFast
if errorlevel 1 ( echo Build failed. & exit /b 1 )

set RELEASE=ash-windows-x86_64
if exist "%RELEASE%" rmdir /s /q "%RELEASE%"
mkdir "%RELEASE%\ash\bin"
mkdir "%RELEASE%\ash\runtime"
mkdir "%RELEASE%\ash\examples"

copy /Y "zig-out\bin\ash.exe"          "%RELEASE%\ash\bin\ash.exe"          >nul
copy /Y "runtime\ash_runtime.c"        "%RELEASE%\ash\runtime\ash_runtime.c" >nul
copy /Y "runtime\ash_runtime.h"        "%RELEASE%\ash\runtime\ash_runtime.h" >nul
copy /Y "install.bat"                  "%RELEASE%\ash\install.bat"           >nul
copy /Y "examples\hello.ash"           "%RELEASE%\ash\examples\hello.ash"    >nul
copy /Y "examples\fib.ash"             "%RELEASE%\ash\examples\fib.ash"      >nul
copy /Y "examples\fizzbuzz.ash"        "%RELEASE%\ash\examples\fizzbuzz.ash" >nul
copy /Y "README.md"                    "%RELEASE%\ash\README.md"             >nul

:: Create zip using PowerShell
powershell -Command "Compress-Archive -Path '%RELEASE%\ash' -DestinationPath '%RELEASE%.zip' -Force"
if errorlevel 1 ( echo Zip failed. & exit /b 1 )

rmdir /s /q "%RELEASE%"
echo.
echo Release created: %RELEASE%.zip
echo.
echo Contents:
powershell -Command "& { Add-Type -Assembly 'System.IO.Compression.FileSystem'; [System.IO.Compression.ZipFile]::OpenRead('%RELEASE%.zip').Entries | ForEach-Object { '  ' + $_.FullName } }"
endlocal
