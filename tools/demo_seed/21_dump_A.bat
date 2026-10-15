@echo off
cd /d "%~dp0..\..\backend"
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0seed_factor_demo.py" dump A > "%~dp0dump_A.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0dump_A.txt"
