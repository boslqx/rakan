@echo off
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0seed_adaptive_demo.py" trigger B > "%~dp0trigger_B.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0trigger_B.txt"
