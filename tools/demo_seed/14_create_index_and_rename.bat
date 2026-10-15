@echo off
set "PY=%~dp0..\..\backend\venv\Scripts\python.exe"
"%PY%" "%~dp0seed_adaptive_demo.py" rename > "%~dp0index_log.txt" 2>&1
"%PY%" "%~dp0create_index.py" >> "%~dp0index_log.txt" 2>&1
echo EXIT %errorlevel% >> "%~dp0index_log.txt"
