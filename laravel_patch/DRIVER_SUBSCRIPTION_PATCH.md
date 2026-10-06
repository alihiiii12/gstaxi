# اشتراك السائق الشهري (30 يوم — دفع يدوي)

## القواعد

| الحالة | السلوك |
|--------|--------|
| عند إضافة سائق | `subscription_ends_at` = `created_at` + 30 يوم |
| دفع من الإدارة | تجديد 30 يوم من **تاريخ الدفع** + إلغاء الحظر |
| قبل 24 ساعة من الانتهاء | إشعار FCM + سجل `driver_notifications` |
| بعد الانتهاء دون دفع | `subscription_blocked` + إخفاء من الخريطة + منع تسجيل الدخول |
| رسالة الحظر | `قم بالدفع — تجديد الاشتراك الشهري` |

## التثبيت على السيرفر

```bash
cd /var/www/syriataxi-api

# انسخ الملفات من laravel_patch إلى المسارات المطابقة:
# - database/migrations/2026_05_18_120000_add_driver_subscription_fields.php
# - app/Services/DriverSubscriptionService.php
# - app/Http/Controllers/Admin/AdminDriverSubscriptionController.php
# - app/Console/Commands/ProcessDriverSubscriptions.php

php artisan migrate
php artisan config:cache
```

## المسارات (أضف في `routes/api.php` ضمن مجموعة admin)

```php
Route::post('admin/drivers/{id}/subscription/renew', [AdminDriverSubscriptionController::class, 'renew']);
Route::post('admin/drivers/{id}/subscription/unblock', [AdminDriverSubscriptionController::class, 'unblock']);
Route::post('admin/drivers/{id}/subscription/block', [AdminDriverSubscriptionController::class, 'block']);
```

## الجدولة (`app/Console/Kernel.php` أو `routes/console.php`)

```php
$schedule->command('drivers:process-subscriptions')->hourly();
```

## منع تسجيل الدخول (بعد نجاح التحقق من OTP للسائق)

في `AuthController` أو `DriverAuthController` عند `login` / `verifyOtp`:

```php
use App\Models\Driver;
use App\Services\DriverSubscriptionService;

$driver = Driver::where('userId', $user->id)->first();
if ($driver) {
    $msg = DriverSubscriptionService::loginBlockedMessage($driver);
    if ($msg) {
        return response()->json([
            'success' => false,
            'message' => $msg,
            'code' => 'subscription_blocked',
        ], 403);
    }
}
```

## إخفاء من الركاب

في `nearby-drivers` و `updateLocation`:

```php
if (! DriverSubscriptionService::isVisibleToPassengers($driver)) {
    // updateLocation: return 403 مع نفس الرسالة
    // nearby: استبعاد من النتائج
}
```

## قائمة السائقين للإدارة

أضف للـ JSON في `admin/drivers` أو `drivers/index`:

```php
'subscription_ends_at' => $driver->subscription_ends_at,
'subscription_blocked' => (bool) $driver->subscription_blocked,
'subscription_active' => DriverSubscriptionService::isSubscriptionActive($driver),
```

## عند إنشاء سائق جديد

```php
DriverSubscriptionService::beginSubscription($driver);
```

(أو الاعتماد على الـ migration الافتراضي من `created_at`)
