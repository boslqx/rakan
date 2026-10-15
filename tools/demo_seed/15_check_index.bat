@echo off
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0check_index.py" > "%~dp0index_check.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0index_check.txt"
