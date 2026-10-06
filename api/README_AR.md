# Laravel API — نسخة مرآة (للعمل داخل Cursor)

**المشروع الأساسي للرفع على السيرفر:**  
`C:\xampp\htdocs\SyriaTaxi-main\`

هذا المجلد (`syriataxi/api/`) نسخة مرآة داخل مشروع Flutter. أي تعديل هنا يجب **نسخه فوراً** إلى `SyriaTaxi-main` قبل الرفع.

> مجلد `laravel_patch/` قديم — لا تستخدمه للتعديلات الجديدة.

## النشر على السيرفر (`gstaxi.online`)

انسخ من **`C:\xampp\htdocs\SyriaTaxi-main\`** إلى `/var/www/syriataxi-api/` (أو مسار مشروعك):

| من `SyriaTaxi-main/` | إلى السيرفر |
|-----------|-------------|
| `app/Http/Controllers/*` | `app/Http/Controllers/` |
| `app/Services/*` | `app/Services/` |
| `app/Events/*` | `app/Events/` |
| `app/Http/Middleware/*` | `app/Http/Middleware/` |
| `bootstrap/app.php` | `bootstrap/app.php` (**مهم:** middleware `driver.poll`) |
| `app/Models/*` | `app/Models/` |
| `routes/api.php` | `routes/api.php` (دمج يدوي إن لزم) |
| `database/migrations/*` | `database/migrations/` |

بعد الرفع:

```bash
php artisan migrate --force
php artisan cache:clear
php artisan route:clear
php artisan config:clear
```

**مهم:** يجب تنفيذ migration `2026_05_06_000001` لإضافة حالات `DriverArrived` و `AwaitingDestination` — بدونها يفشل «وصلت» و«بدء الرحلة».

## متطلبات تشغيل الطلبات الفورية

- **Redis يعمل** (`driver:{id}:online` + GEO `drivers`) — بدون Redis لا يصل أي طلب للسائق
- في `.env` على السيرفر:
  ```env
  REDIS_HOST=127.0.0.1
  REDIS_PASSWORD=null
  REDIS_PORT=6379
  DRIVER_NOTIFY_RADIUS_KM=1
  DRIVER_DISPLAY_RADIUS_KM=1
  ```
- بعد تعديل `.env`: `php artisan config:clear && php artisan config:cache`
- `ImmediateDriverNotifier` + `ImmediatePendingForDriver` + `DriverPollController`
- `updateLocation` يستدعي `attachDriverToFreshPendingRequests`
- FCM: `storage/firebase/service-account.json` + `FcmPushService`

### تشخيص «الطلب لا يصل للسائق»

1. **لوحة التحكم → خريطة العمليات:** هل يظهر السائق على الخريطة وهو «متصل»؟
   - لا → Redis أو تطبيق السائق لا يرسل الموقع (`updateLocation`)
2. **GET** `/api/admin/dispatch-health` (بتسجيل دخول موظف):
   - `redis_ok: false` → شغّل Redis: `sudo systemctl start redis`
   - `drivers_in_geo: 0` → السائق لم يفعّل «متصل» أو اشتراكه منتهٍ
3. **تطبيق السائق:** اسحب «للبدء»، اسمح بالموقع، انتظر 5 ثوانٍ
4. **نفس فئة السيارة** بين الراكب والسائق (`carTypeId` = `transTypeId`)
5. **المسافة:** السائق ضمن 1 كم من نقطة الانطلاق
6. **سجلات Laravel:** `storage/logs/laravel.log` — ابحث عن `ImmediateDriverNotifier`
7. **APK جديد** للسائق (ليس رفع السيرفر فقط)

## XAMPP محلي

المسار: `C:\xampp\htdocs\SyriaTaxi-main\`  
API: `http://<IP>/SyriaTaxi-main/public/api`
