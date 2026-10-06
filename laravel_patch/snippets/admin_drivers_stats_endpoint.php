<?php
/**
 * أعداد السائقين في لوحة التحكم (تبويب السائقين) — مطابقة dashboard drivers_total.
 *
 * 1) AdminOverviewController: أضف use Illuminate\Support\Facades\DB;
 *    ودالة driverStats() (انظر SyriaTaxi-main AdminOverviewController).
 *
 * 2) routes/api.php داخل Route::prefix('admin'):
 *    Route::get('/drivers/stats', [AdminOverviewController::class, 'driverStats']);
 *
 * 3) على السيرفر: php artisan route:clear && php artisan route:cache
 *
 * 4) DriverController::index — حد per_page بين 1 و 100 (ترقيم صفحات).
 *
 * 5) admin-web: npm run build ثم رفع dist إلى public/admin
 *    (قائمة السائقين: 30/صفحة + أزرار السابق/التالي؛ الأعداد من /admin/drivers/stats).
 */
