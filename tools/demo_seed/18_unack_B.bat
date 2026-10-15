@echo off
"%~dp0..\..\backend\venv\Scripts\python.exe" "%~dp0seed_adaptive_demo.py" unack B > "%~dp0unack.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0unack.txt"
