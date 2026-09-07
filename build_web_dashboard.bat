@echo off
cd /d "%~dp0"
echo ====================================================
echo    GROVIO SUPERMART - CORPORATE DASHBOARD BUILD
echo ====================================================

echo [1/2] Fetching dependencies...
call flutter pub get

echo [2/2] Building Web Dashboard...
call flutter build web -t lib/main_web_dashboard.dart --release

echo ====================================================
echo   SUCCESS: Web Dashboard is ready!
echo   Location: build\web\index.html
echo ====================================================
pause
