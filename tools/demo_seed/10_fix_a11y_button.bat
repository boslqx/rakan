@echo off
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set OUT=%~dp0a11y.txt
"%ADB%" shell settings get secure accessibility_button_targets > "%OUT%" 2>&1
"%ADB%" shell settings get secure enabled_accessibility_services >> "%OUT%" 2>&1
"%ADB%" shell settings put secure accessibility_button_targets "" >> "%OUT%" 2>&1
"%ADB%" shell settings put secure enabled_accessibility_services "" >> "%OUT%" 2>&1
"%ADB%" shell settings put secure accessibility_enabled 0 >> "%OUT%" 2>&1
echo END >> "%OUT%"
