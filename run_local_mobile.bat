@echo off
chcp 65001 >nul
setlocal

REM عنوان API المحلي — غيّر IP إذا تغيّر عنوان الكمبيوتر على الشبكة
set API_URL=http://192.168.1.110/gstaxi/public/api

echo.
echo GS TAXI — تشغيل على الموبايل المتصل
echo API: %API_URL%
echo.

cd /d "%~dp0"
flutter run --dart-define=SYRIATAXI_API_BASE_URL=%API_URL%

endlocal
