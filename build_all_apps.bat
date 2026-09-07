@echo off
:: Change directory to where the script is located
cd /d "%~dp0"

echo ====================================================
echo    GROVIO SUPERMART - ALL APPS BUILD PROCESS (v2)
echo ====================================================

:: Check if pubspec.yaml exists
if not exist "pubspec.yaml" (
    echo ERROR: pubspec.yaml not found in %cd%
    pause
    exit /b
)

echo [1/5] Cleaning and Fetching dependencies...
call flutter clean
call flutter pub get

echo [2/5] Building Customer App (Small Size)...
call flutter build apk --release --flavor customer --split-per-abi -t lib/main.dart

echo [3/5] Building Store App (Small Size)...
call flutter build apk --release --flavor store --split-per-abi -t lib/main_store.dart

echo [4/5] Building Driver App (Small Size)...
call flutter build apk --release --flavor driver --split-per-abi -t lib/main_driver.dart

echo [5/5] Organizing files into RELEASES folder...

if not exist "RELEASES" mkdir RELEASES
if not exist "RELEASES\CUSTOMER" mkdir RELEASES\CUSTOMER
if not exist "RELEASES\STORE" mkdir RELEASES\STORE
if not exist "RELEASES\DRIVER" mkdir RELEASES\DRIVER

:: Copying the most common APK (arm64-v8a) to specific folders
copy build\app\outputs\flutter-apk\app-customer-arm64-v8a-release.apk RELEASES\CUSTOMER\Grovio_Customer_v8a.apk
copy build\app\outputs\flutter-apk\app-store-arm64-v8a-release.apk RELEASES\STORE\Grovio_Partner_v8a.apk
copy build\app\outputs\flutter-apk\app-driver-arm64-v8a-release.apk RELEASES\DRIVER\Grovio_Delivery_v8a.apk

echo ====================================================
echo   SUCCESS: All Small APKs are ready in RELEASES folder!
echo ====================================================
echo Files Location:
echo CUSTOMER -> RELEASES\CUSTOMER
echo STORE    -> RELEASES\STORE
echo DRIVER   -> RELEASES\DRIVER
echo ====================================================
pause
