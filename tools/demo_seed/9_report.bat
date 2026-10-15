@echo off
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0seed_adaptive_demo.py" report > "%~dp0report.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0report.txt"
