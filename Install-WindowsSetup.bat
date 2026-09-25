@echo off
title Fresh Windows Setup

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Windows.ps1"

pause