@echo off
title Fresh Windows Setup

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

pause