# اشتراك السائق الشهري — دليل سريع

## ماذا يحدث؟

1. **عند إضافة السائق:** اشتراك 30 يوماً من `created_at`.
2. **قبل 24 ساعة من الانتهاء:** إشعار FCM + سجل في إشعارات السائق.
3. **بعد الانتهاء دون دفع:** حظر تلقائي — لا يظهر للركاب ولا يستطيع تسجيل الدخول (رسالة: **قم بالدفع**).
4. **من لوحة الإدارة:** زر **دفع / تجديد** يمدّد 30 يوماً من **تاريخ الدفع** ويلغي الحظر.

## على السيرفر (`/var/www/syriataxi-api`)

```bash
# انسخ من مجلد laravel_patch:
# database/migrations/2026_05_18_120000_add_driver_subscription_fields.php
# app/Services/DriverSubscriptionService.php
# app/Http/Controllers/Admin/AdminDriverSubscriptionController.php
# app/Console/Commands/ProcessDriverSubscriptions.php
# routes (أو ألصق من routes/admin_driver_subscription_routes.php)

php artisan migrate
```

### ألصق في تسجيل الدخول

`laravel_patch/snippets/auth_login_subscription_block.php`

### ألصق في `updateLocation`

`laravel_patch/snippets/driver_update_location_subscription.php`

### أضف حقول الاشتراك في `drivers/index`

`laravel_patch/snippets/admin_drivers_index_subscription_fields.php`

### الجدولة

```php
$schedule->command('drivers:process-subscriptions')->hourly();
```

### رفع لوحة الإدارة

```bash
# من جهازك بعد npm run build في admin-web
scp -r admin-web/dist/* root@72.62.2.152:/var/www/syriataxi-api/public/admin/
```

## التطبيق (Flutter)

جاهز: عند 403 + `subscription_blocked` أو رسالة «قم بالدفع» يظهر تنبيه ولا يُسمح بالدخول.
