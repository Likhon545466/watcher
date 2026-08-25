@echo off
cd /d "%~dp0"

title Watcher Backup

echo ==========================
echo Watcher Backup
echo ==========================
echo.

if not exist "pubspec.yaml" (
    echo ERROR: Run this BAT from Watcher project root.
    pause
    exit /b 1
)

if not exist "lib" (
    echo ERROR: lib folder not found.
    pause
    exit /b 1
)

if not exist "backup" (
    echo ERROR: backup folder not found.
    echo Please create a folder named "backup" in the Watcher project root.
    pause
    exit /b 1
)

for /f "tokens=1-4 delims=/.- " %%a in ("%date%") do (
    set DATE=%%a-%%b-%%c
)

for /f "tokens=1-2 delims=:., " %%a in ("%time%") do (
    set TIME=%%a-%%b
)

set BACKUP_NAME=backup\watcher_lib_backup_%DATE%_%TIME%_%RANDOM%.zip

echo Creating Watcher lib backup...
echo.

powershell -NoProfile -Command "Compress-Archive -Path '.\lib\*' -DestinationPath '%BACKUP_NAME%' -Force"

if exist "%BACKUP_NAME%" (
    echo.
    echo ==========================
    echo BACKUP COMPLETED
    echo ==========================
    echo Saved:
    echo %BACKUP_NAME%
) else (
    echo.
    echo ==========================
    echo BACKUP FAILED
    echo ==========================
)

pause
