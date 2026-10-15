@echo off
cd /d "%~dp0..\..\backend"
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0seed_factor_demo.py" dump C > "%~dp0dump_C.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0dump_C.txt"
