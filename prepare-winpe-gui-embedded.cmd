@echo off
REM Compatibility entry point: install the complete, maintained GUI and backend.
call "%~dp0prepare-winpe-gui.cmd" %*
exit /b %errorlevel%
