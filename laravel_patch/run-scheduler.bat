@echo off
REM Syria Taxi — تشغيل جدولة Laravel كل دقيقة (مهم للحجز المسبق: T-30، T-5 «هل أنت جاهز؟»)
REM عدّل المسار أدناه إذا كان مشروعك ليس على XAMPP الافتراضي.

set BACKEND=C:\xampp\htdocs\SyriaTaxi-main

if not exist "%BACKEND%\artisan" (
  echo [خطأ] لم يُعثر على artisan في: %BACKEND%
  echo عدّل متغير BACKEND داخل run-scheduler.bat
  exit /b 1
)

cd /d "%BACKEND%"
php artisan schedule:run
echo [%date% %time%] schedule:run >> "%~dp0scheduler-log.txt"
