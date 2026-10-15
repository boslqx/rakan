@echo off
setlocal EnableDelayedExpansion
title Rakan emulator helper (close this window when finished)
cd /d "%~dp0"
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
echo Rakan emulator helper running. Handles: shot NAME / tap X Y / swipe X1 Y1 X2 Y2 MS / text STR / key CODE / restart / back
:loop
if exist "%~dp0adbreq.txt" (
  set "REQ="
  set /p REQ=<"%~dp0adbreq.txt"
  del "%~dp0adbreq.txt"
  call :handle
)
ping -n 2 127.0.0.1 >nul
goto loop

:handle
for /f "tokens=1,* delims= " %%a in ("!REQ!") do (set "ACT=%%a" & set "ARG=%%b")
echo [%time%] !ACT! !ARG!
if /i "!ACT!"=="shot"    "%ADB%" exec-out screencap -p > "%~dp0shots\!ARG!.png"
if /i "!ACT!"=="tap"     "%ADB%" shell input tap !ARG!
if /i "!ACT!"=="swipe"   "%ADB%" shell input swipe !ARG!
if /i "!ACT!"=="text"    "%ADB%" shell "input text '!ARG!'"
if /i "!ACT!"=="key"     "%ADB%" shell input keyevent !ARG!
if /i "!ACT!"=="back"    "%ADB%" shell input keyevent 4
if /i "!ACT!"=="restart" (
  "%ADB%" shell am force-stop com.example.rakan
  "%ADB%" shell monkey -p com.example.rakan -c android.intent.category.LAUNCHER 1 >nul
)
if /i "!ACT!"=="size"    "%ADB%" shell wm size > "%~dp0adbresult.txt"
echo done !ACT! !ARG!> "%~dp0adbdone.txt"
goto :eof
