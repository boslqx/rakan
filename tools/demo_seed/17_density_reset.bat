@echo off
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" shell wm density reset > "%~dp0density_log.txt" 2>&1
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" shell wm density >> "%~dp0density_log.txt" 2>&1
