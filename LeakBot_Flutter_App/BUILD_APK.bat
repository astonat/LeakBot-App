@echo off
title LEAKBOT OLED // 1-CLICK ANDROID APK COMPILER
echo =====================================================================
echo   LEAKBOT APEX OLED - 1-CLICK FLUTTER APK COMPILER
echo =====================================================================
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] Flutter SDK not found in PATH.
    echo [i] Tip: You can already use the built-in OLED Web App on Android and iOS
    echo     right now by visiting http://YOUR_PC_IP:5000/app on your phone!
    echo [i] Or upload this folder to GitHub to let GitHub Actions compile the APK in the cloud for free.
    pause
    exit /b 1
)

echo [1/3] Initializing Android platform files...
call flutter create --org com.example --project-name leakbot_oled_mobile .
copy /Y "android_custom\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml"
copy /Y "android_custom\MainActivity.kt" "android\app\src\main\kotlin\com\example\leakbot_oled_mobile\MainActivity.kt"

echo [2/3] Fetching Flutter packages...
call flutter pub get

echo [3/3] Compiling Release APK...
call flutter build apk --release

echo =====================================================================
echo [SUCCESS] Your APK is ready at:
echo   build\app\outputs\flutter-apk\app-release.apk
echo =====================================================================
pause
