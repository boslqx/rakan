@echo off
setlocal
set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%SDK%\platform-tools\adb.exe"
set "AVD=%USERPROFILE%\.android\avd\Pixel_9_Pro.avd"
set LOG=%~dp0restart_log.txt
echo ==== %date% %time% > "%LOG%"
"%ADB%" emu kill >> "%LOG%" 2>&1
timeout /t 8 >nul
type "%AVD%\emulator-user.ini" >> "%LOG%" 2>&1
rem --- reset saved window position to the main screen
if exist "%AVD%\emulator-user.ini" (
  findstr /v /b /c:"window.x" /c:"window.y" "%AVD%\emulator-user.ini" > "%AVD%\emulator-user.tmp"
  move /y "%AVD%\emulator-user.tmp" "%AVD%\emulator-user.ini" >nul
)
echo window.x = 80>> "%AVD%\emulator-user.ini"
echo window.y = 40>> "%AVD%\emulator-user.ini"
echo --- new ini >> "%LOG%"
type "%AVD%\emulator-user.ini" >> "%LOG%" 2>&1
start "" "%SDK%\emulator\emulator.exe" -avd Pixel_9_Pro -no-snapshot-load -no-snapshot-save -dns-server 8.8.8.8
"%ADB%" wait-for-device >> "%LOG%" 2>&1
:boot
set BOOT=
for /f "tokens=*" %%a in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set BOOT=%%a
if not "%BOOT%"=="1" ( timeout /t 3 >nul & goto boot )
echo booted >> "%LOG%"
"%ADB%" install -r "%~dp0..\..\build\app\outputs\flutter-apk\app-debug.apk" >> "%LOG%" 2>&1
"%ADB%" shell pm clear com.example.rakan >> "%LOG%" 2>&1
"%ADB%" shell pm grant com.example.rakan android.permission.POST_NOTIFICATIONS >> "%LOG%" 2>&1
"%ADB%" shell settings put secure accessibility_button_targets "" >> "%LOG%" 2>&1
"%ADB%" shell settings put secure enabled_accessibility_services "" >> "%LOG%" 2>&1
"%ADB%" shell settings put system screen_off_timeout 1800000 >> "%LOG%" 2>&1
"%ADB%" shell monkey -p com.example.rakan -c android.intent.category.LAUNCHER 1 >> "%LOG%" 2>&1
echo ALL_DONE >> "%LOG%"
