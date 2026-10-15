@echo off
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set OUT=%~dp0net.txt
echo ==== %time% > "%OUT%"
"%ADB%" shell ping -c 2 -W 3 8.8.8.8 >> "%OUT%" 2>&1
"%ADB%" shell ping -c 2 -W 3 firestore.googleapis.com >> "%OUT%" 2>&1
"%ADB%" shell dumpsys connectivity ^| grep -m3 "NetworkAgentInfo" >> "%OUT%" 2>&1
"%ADB%" shell settings get global airplane_mode_on >> "%OUT%" 2>&1
ping -n 1 firestore.googleapis.com >> "%OUT%" 2>&1
echo END >> "%OUT%"
