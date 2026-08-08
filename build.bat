@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

set "APP_NAME=Watcher"

echo.
echo ========================================
echo        WATCHER RELEASE APK BUILDER
echo ========================================
echo.

REM =========================================
REM Read version from pubspec.yaml
REM Example: version: 1.2.0+5
REM =========================================

set "FULL_VERSION="

for /f "tokens=2 delims=: " %%A in ('findstr /B /C:"version:" pubspec.yaml') do (
    set "FULL_VERSION=%%A"
)

if not defined FULL_VERSION (
    echo.
    echo ERROR: Could not find version in pubspec.yaml
    echo.
    pause
    exit /b 1
)

echo App Name     : %APP_NAME%
echo Full Version : !FULL_VERSION!
echo.

echo Building release APK...
echo.

REM =========================================
REM Build Flutter APK
REM =========================================

call flutter build apk --release

if errorlevel 1 (
    echo.
    echo ========================================
    echo BUILD FAILED
    echo ========================================
    echo.
    pause
    exit /b 1
)

REM =========================================
REM APK Paths
REM =========================================

set "APK_DIR=build\app\outputs\flutter-apk"
set "SOURCE_APK=%APK_DIR%\app-release.apk"

REM Final filename example:
REM Watcher-v1.2.0+5.apk

set "FINAL_NAME=%APP_NAME%-v!FULL_VERSION!.apk"
set "FINAL_APK=%APK_DIR%\!FINAL_NAME!"

if not exist "%SOURCE_APK%" (
    echo.
    echo ERROR: app-release.apk was not found.
    echo.
    pause
    exit /b 1
)

REM =========================================
REM Create final renamed APK
REM =========================================

copy /Y "%SOURCE_APK%" "!FINAL_APK!" >nul

if errorlevel 1 (
    echo.
    echo ERROR: Could not create renamed APK.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo          BUILD SUCCESSFUL
echo ========================================
echo.
echo APK:
echo %CD%\!FINAL_APK!
echo.
echo File name:
echo !FINAL_NAME!
echo.

pause
exit /b 0