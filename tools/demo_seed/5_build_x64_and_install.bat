@echo off
cd /d "%~dp0..\.."
set LOG=%~dp0build_log.txt
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "FL=%USERPROFILE%\flutter\bin\flutter.bat"
if not exist "%FL%" set "FL=flutter"
echo ==== %date% %time% build start > "%LOG%"
call "%FL%" build apk --debug --target-platform android-x64 >> "%LOG%" 2>&1
echo BUILD_EXIT %errorlevel% >> "%LOG%"
"%ADB%" install -r "build\app\outputs\flutter-apk\app-debug.apk" >> "%LOG%" 2>&1
"%ADB%" shell monkey -p com.example.rakan -c android.intent.category.LAUNCHER 1 >> "%LOG%" 2>&1
echo ALL_DONE %date% %time% >> "%LOG%"
