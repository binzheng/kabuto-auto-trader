@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoExit -File "run.ps1"
