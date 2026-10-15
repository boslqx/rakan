@echo off
cd /d "%~dp0..\..\backend"
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0seed_factor_demo.py" setup > "%~dp0setup_C.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0setup_C.txt"
