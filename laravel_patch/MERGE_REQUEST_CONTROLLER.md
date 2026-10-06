# دمج RequestController — الطلب الفوري + OSRM + Redis

## حالة التطبيق (مشروع Laravel المرجعي)

تم التحقق من تطبيق الخطوات 1–10 على **`SyriaTaxi-main`** (`RequestController.php`، `routes/api.php`، النماذج، الأحداث، الهجرة `2026_05_02_120000_create_request_driver_offers_table`، وخدمة `ImmediateDriverNotifier`).  
إن كنت تدمج مشروع Laravel **آخر من الصفر**، اتبع الأقسام المرقمة أدناه بنفس الترتيب.

| # | الخطوة | حالة مرجعية |
|---|--------|-------------|
| 1 | استيرادات `RequestController` | مُنفَّذ |
| 2 | `ImmediateDriverNotifier` بدل `findImmediateDriver` | مُنفَّذ |
| 3 | `acceptBooking` للفوري → عرض فقط + `request_driver_offers` | مُنفَّذ |
| 4 | دوال `immediateStatus`، `selectDriver`، التتبع، والمساعدات الخاصة | مُنفَّذ |
| 5 | `cancelByCustomer` → تنظيف Redis والعروض | مُنفَّذ |
| 6 | `getPendingImmediate` → تصفية حسب `eligible` | مُنفَّذ |
| 7 | مسارات `routing/driving-summary` و`immediate-status` و`select-driver` (و`trip-tracking` للزبون) | مُنفَّذ |
| 8 | `RequestModel::driverOffers()` | مُنفَّذ |
| 9 | `Driver::requestOffers()` | مُنفَّذ |
| 10 | `NewRequestEvent($driverId, $requestId)` | مُنفَّذ |

**ملفات مساعدة في هذا المجلد:** `acceptBooking_REPLACEMENT.php`، `RequestController_ADD_THESE_METHODS.php`، `getPendingImmediate_REPLACEMENT.php`، `API_ROUTES_SNIPPET.php`، `database/migrations/...request_driver_offers...`.

---

## 1) أعلى الملف — استيرادات إضافية

```php
use App\Events\CustomerPickedDriverEvent;
use App\Models\RequestDriverOffer;
use Illuminate\Support\Facades\Redis;
```

## 2) استبدال استدعاء `findImmediateDriver` داخل `store`

من:

```php
$this->findImmediateDriver($request['startLocationLongitude'], $request['startLocationLatitude']);
```

إلى:

```php
app(\App\Services\ImmediateDriverNotifier::class)->notify(
    $newRequest,
    (float) $request['startLocationLongitude'],
    (float) $request['startLocationLatitude']
);
```

واحذف الدالة الخاصة القديمة `findImmediateDriver` أو اتركها بدون استخدام.

## 3) استبدال دالة `acceptBooking` بالكامل

المنطق: الطلب **المسبق (Schedual)** يبقى كما كان (حجز فوري للسائق). الطلب **الفوري (Immediate)** في حالة `Pending`: لا يغيّر الحالة؛ يُسجَّل عرض في جدول `request_driver_offers`.

(انسخ المحتوى من الملف **`acceptBooking_REPLACEMENT.php`** في هذا المجلد.)

## 4) إضافة دوال جديدة للتحكم

انسخ من **`RequestController_ADD_THESE_METHODS.php`** (ويُضاف لاحقاً مسار التتبع `customerTripTracking` إن رغبت بتطبيق الزبون كما في النسخة المرجعية).

## 5) تعديل `cancelByCustomer`

قبل `$req->save()` أضف:

```php
Redis::del('request:'.$req->id.':eligible');
RequestDriverOffer::where('request_id', $req->id)->delete();
```

## 6) تعديل `getPendingImmediate`

بعد جلب `$items` صفِّ النتائج: إذا وُجد مفتاح Redis `request:{id}:eligible` فاعرض الطلب فقط إذا كان السائق الحالي عضواً في المجموعة؛ إن لم يوجد المفتاح اعرض الطلب (توافق مع الطلبات القديمة).

## 7) `routes/api.php`

```php
use App\Http\Controllers\RoutingController;

Route::post('/routing/driving-summary', [RoutingController::class, 'drivingSummary'])
    ->middleware('auth:sanctum');

// داخل مجموعة requests قبل مسارات accept/start:
Route::get('/{requestId}/trip-tracking', [RequestController::class, 'customerTripTracking'])
    ->middleware('auth:sanctum');
Route::get('/{requestId}/immediate-status', [RequestController::class, 'immediateStatus'])
    ->middleware('auth:sanctum');
Route::post('/{requestId}/select-driver', [RequestController::class, 'selectDriver'])
    ->middleware('auth:sanctum');
```

(`trip-tracking` اختياري إن لم تُضف واجهة تتبع الزبون؛ ضع هذه الأسطر قبل `/{requestId}/accept` إن وُجد لتفادي التعارض.)

## 8) `RequestModel.php`

أضف العلاقة:

```php
public function driverOffers()
{
    return $this->hasMany(RequestDriverOffer::class, 'request_id');
}
```

## 9) `Driver.php`

```php
public function requestOffers()
{
    return $this->hasMany(RequestDriverOffer::class, 'driver_id');
}
```

## 10) `NewRequestEvent`

المُنشئ يصبح `(int $driverId, int $requestId)` و`broadcastWith` يرسل `requestId`.
