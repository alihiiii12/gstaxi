# تخفيف ضغط السيرفر — دليل الرفع

## المشكلة
كل سائق أونلاين كان يضرب **مرتين كل 2 ثانية**:
- `GET /api/requests/immediate-pending`
- `GET /api/requests/driver/{id}`

مع ~300 سائق ≈ **600 طلب/10 ثوانٍ** → CPU 97%.

## الحل
| الطبقة | التغيير |
|--------|---------|
| Flutter | استطلاع **موحّد** كل 10 ث (5 ث أثناء رحلة) — طلب واحد |
| Laravel | endpoint جديد `GET /api/driver/poll-snapshot` + cache 4 ث |
| Laravel | throttle middleware — لا أكثر من poll كل 2 ث/مستخدم |
| Laravel | cache لـ `driving-summary` 15 دقيقة |

### قبل (300 سائق)
~150 req/s على immediate-pending + ~150 req/s على driver/{id} = **~300 req/s**

### بعد (300 سائق + APK جديد)
~30 req/s على poll-snapshot فقط = **~30 req/s** (تخفيض ~90%)

---

## 1) رفع Laravel على السيرفر

انسخ من مجلد `laravel_patch/` إلى مشروع Laravel على VPS (`/var/www/...`):

| ملف محلي | وجهة على السيرفر |
|----------|------------------|
| `app/Http/Controllers/DriverPollController.php` | `app/Http/Controllers/DriverPollController.php` |
| `app/Http/Middleware/ThrottleDriverPoll.php` | `app/Http/Middleware/ThrottleDriverPoll.php` |
| `app/Http/Controllers/RoutingController.php` | **استبدال** `RoutingController.php` |
| `getPendingImmediate_REPLACEMENT.php` | **استبدال** دالة `getPendingImmediate` داخل `RequestController.php` |
| `getDriverRequests_CACHED.php` | **استبدال/إضافة** دالة `getDriverRequests` داخل `RequestController.php` |

### routes/api.php
من `DRIVER_POLL_ROUTES_SNIPPET.php`:

```php
use App\Http\Controllers\DriverPollController;

Route::get('/driver/poll-snapshot', [DriverPollController::class, 'snapshot'])
    ->middleware(['auth:sanctum', 'driver.poll']);
```

سجّل middleware في `bootstrap/app.php` (Laravel 11):

```php
->withMiddleware(function ($middleware) {
    $middleware->alias([
        'driver.poll' => \App\Http\Middleware\ThrottleDriverPoll::class,
    ]);
})
```

أو في `app/Http/Kernel.php` (Laravel 10):

```php
'driver.poll' => \App\Http\Middleware\ThrottleDriverPoll::class,
```

**اختياري لكن موصى به:** أضف `'driver.poll'` على:
- `GET /requests/immediate-pending`
- `GET /requests/driver/{driverId}`

### أوامر بعد الرفع (SSH)

```bash
cd /var/www/html   # مسار Laravel
php artisan optimize:clear
php artisan route:cache
php artisan config:cache
sudo systemctl restart php8.3-fpm
```

### تأكد أن Cache يعمل

```bash
php artisan tinker
>>> Cache::put('test', 1, 60); Cache::get('test');
```

إن كان `null` — فعّل `CACHE_DRIVER=file` أو `redis` في `.env`.

---

## 2) بناء ورفع التطبيقات

### APK سائق + عميل (Flutter)

```bash
cd syriataxi
flutter build apk --release
```

الملف: `build/app/outputs/flutter-apk/app-release.apk`

**مهم:** وزّع APK السائق أولاً — هو مصدر أغلب الضغط.

### لوحة الأدmin-web (اختياري — خريطة 30 ث بدل 5)

```bash
cd admin-web
npm run build
```

ارفع محتويات `dist/` إلى `public/admin/` على السيرفر.

---

## 3) ترتيب النشر الموصى به

1. **أعد تشغيل السيرفر** (`restart php-fpm`) إن كان متوقفاً.
2. **ارفع Laravel** (poll-snapshot + cache + middleware).
3. **اختبر:** `curl -H "Authorization: Bearer TOKEN" https://gstaxi.online/api/driver/poll-snapshot`
4. **وزّع APK السائق** الجديد.
5. **راقب CPU** في Hostinger — يجب أن ينخفض خلال 10–30 دقيقة.

---

## 4) ملفات Flutter المعدّلة (مرجع)

- `lib/Driver/Home/service/driver_server_sync_service.dart` *(جديد)*
- `lib/core/constants/driver_poll_intervals.dart` *(جديد)*
- `lib/Driver/Order/controller/immediate_bookings_controller.dart`
- `lib/Driver/Home/controller/driver_assigned_trip_controller.dart`
- `lib/Driver/Home/view/driver_main_screen.dart`
- `lib/core/network/api_endpoints.dart`
- `lib/core/services/trip_api_service.dart`
- `lib/Customer/controller/customer_active_trip_controller.dart`
- `lib/Customer/view/customer_home_screen.dart`
- `lib/Admin/view/admin_map_screen.dart`

---

## 5) APK قديم بدون poll-snapshot

التطبيق ي fallback تلقائياً إلى المسارين القديمين **بالتوازي** (وليس مضاعفاً من controllerين)، مع فترات 10 ث — still much better than before.

بعد رفع Laravel + middleware، حتى APK قديم يُحدَّ throttle و cache.
