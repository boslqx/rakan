@echo off
title Rakan demo helper (close this window when finished)
cd /d "%~dp0"
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "PY=%~dp0..\..\backend\venv\Scripts\python.exe"
set "SEED=%~dp0seed_adaptive_demo.py"
echo Rakan demo helper running. Only handles: shot NAME / setup / trigger / report.
:loop
if exist "%~dp0request.txt" (
  set /p REQ=<"%~dp0request.txt"
  del "%~dp0request.txt"
  call :handle
)
timeout /t 2 >nul
goto loop

:handle
for /f "tokens=1,2" %%a in ("%REQ%") do (set ACT=%%a& set ARG=%%b)
echo [%time%] %ACT% %ARG%
if /i "%ACT%"=="shot" (
  "%ADB%" exec-out screencap -p > "%~dp0shots\%ARG%.png"
  echo shot %ARG% done> "%~dp0result.txt"
)
if /i "%ACT%"=="setup" ( "%PY%" "%SEED%" setup > "%~dp0result.txt" 2>&1 & echo EXIT %errorlevel%>> "%~dp0result.txt" )
if /i "%ACT%"=="trigger" ( "%PY%" "%SEED%" trigger > "%~dp0result.txt" 2>&1 & echo EXIT %errorlevel%>> "%~dp0result.txt" )
if /i "%ACT%"=="report" ( "%PY%" "%SEED%" report > "%~dp0result.txt" 2>&1 & echo EXIT %errorlevel%>> "%~dp0result.txt" )
goto :eof
