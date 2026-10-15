@echo off
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
"%ADB%" logcat -d -t 1500 > "%~dp0logcat.txt" 2>&1
"%ADB%" shell pm list packages rakan >> "%~dp0logcat.txt" 2>&1
"%ADB%" shell getprop ro.product.cpu.abilist >> "%~dp0logcat.txt" 2>&1
