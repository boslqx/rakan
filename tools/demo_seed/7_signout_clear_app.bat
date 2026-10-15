@echo off
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
"%ADB%" shell pm clear com.example.rakan > "%~dp0clear.txt" 2>&1
"%ADB%" shell pm grant com.example.rakan android.permission.POST_NOTIFICATIONS >> "%~dp0clear.txt" 2>&1
"%ADB%" shell pm grant com.example.rakan android.permission.CAMERA >> "%~dp0clear.txt" 2>&1
"%ADB%" shell monkey -p com.example.rakan -c android.intent.category.LAUNCHER 1 >> "%~dp0clear.txt" 2>&1
echo END >> "%~dp0clear.txt"
