@echo off
cd /d "%~dp0"
set OUT=%~dp0env_check.txt
echo ==== %date% %time% > "%OUT%"
set "SDK=%LOCALAPPDATA%\Android\Sdk"
echo SDK=%SDK% >> "%OUT%"
echo --- avds >> "%OUT%"
"%SDK%\emulator\emulator.exe" -list-avds >> "%OUT%" 2>&1
echo --- adb devices >> "%OUT%"
"%SDK%\platform-tools\adb.exe" devices >> "%OUT%" 2>&1
echo --- flutter >> "%OUT%"
where flutter >> "%OUT%" 2>&1
dir /b "%USERPROFILE%\flutter\bin\flutter.bat" >> "%OUT%" 2>&1
echo --- python venv >> "%OUT%"
"%~dp0..\..\backend\venv\Scripts\python.exe" --version >> "%OUT%" 2>&1
echo --- apk >> "%OUT%"
dir /b /s "%~dp0..\..\build\app\outputs\flutter-apk\*.apk" >> "%OUT%" 2>&1
echo done >> "%OUT%"
