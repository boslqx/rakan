@echo off
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
"%ADB%" logcat -d -s flutter > "%~dp0flutter_log.txt" 2>&1
echo END >> "%~dp0flutter_log.txt"
