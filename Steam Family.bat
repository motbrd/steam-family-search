@echo off
rem Steam Family Search - no window. Stops by itself when Steam closes.
rem conhost --headless: no console window at all (Windows Terminal would ignore -WindowStyle Hidden).
start "" "%WINDIR%\System32\conhost.exe" --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0steam-family.ps1"
