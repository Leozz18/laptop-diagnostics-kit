@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator rights required / Richiesta privilegi di amministratore...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%*'"
    exit /b
)

echo.
echo  Laptop diagnostics kit
echo  Folder: %cd%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Diagnostica-Laptop.ps1" -Language "%~1"
set EXITCODE=%ERRORLEVEL%
echo.
pause
exit /b %EXITCODE%
