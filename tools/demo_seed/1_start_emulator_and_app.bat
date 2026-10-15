@echo off
cd /d "%~dp0"
set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%SDK%\platform-tools\adb.exe"
set LOG=%~dp0emulator_log.txt
echo ==== %date% %time% > "%LOG%"
echo starting emulator >> "%LOG%"
start "" "%SDK%\emulator\emulator.exe" -avd Pixel_9_Pro -no-snapshot-save
"%ADB%" start-server >> "%LOG%" 2>&1
echo waiting for device >> "%LOG%"
"%ADB%" wait-for-device >> "%LOG%" 2>&1
:boot
for /f "tokens=*" %%a in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set BOOT=%%a
if not "%BOOT%"=="1" ( timeout /t 3 >nul & goto boot )
echo booted >> "%LOG%"
"%ADB%" devices >> "%LOG%" 2>&1
echo installing apk >> "%LOG%"
"%ADB%" install -r "%~dp0..\..\build\app\outputs\flutter-apk\app-debug.apk" >> "%LOG%" 2>&1
echo launching >> "%LOG%"
"%ADB%" shell monkey -p com.example.rakan -c android.intent.category.LAUNCHER 1 >> "%LOG%" 2>&1
echo done >> "%LOG%"
