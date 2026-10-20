@echo off
"%~dp0python\python.exe" "%~dp0launch_windows.py" %*
if errorlevel 1 pause
