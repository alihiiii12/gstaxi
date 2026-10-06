<?php

/**
 * السائق غير النشط لا يظهر في «السائقون القريبون والنشطون».
 *
 * 1) أضف المسار في `routes/api.php` داخل مجموعة `drivers` مع `auth:sanctum`:
 *
 *    Route::post('/go-offline', [DriverController::class, 'goOffline'])
 *        ->middleware('auth:sanctum');
 *
 * 2) انسخ الدالة `goOffline` أدناه داخل `DriverController`.
 *
 * 3) تأكد أن `updateLocation` يضيف السائق إلى نفس مفتاح GEO (`drivers`) ونفس شكل
 *    العضو (`member`) المستخدم في `zrem` هنا — غيّر `(string) $id` إن كان عندكم
 *    مثلاً `"driver:".$id` أو JSON.
 *
 * 4) اختياري — في `RequestController` (أو حيث تُبنى قائمة القريبين): عند فشل Redis
 *    في التحقق من الأونلاين، أعد `false` وليس `true` حتى لا يُدرج سائق وهمي.
 *
 *    protected function isDriverOnline(int $driverId): bool
 *    {
 *        try {
 *            return (bool) \Illuminate\Support\Facades\Redis::exists('driver:'.$driverId.':online');
 *        } catch (\Throwable $e) {
 *            return false;
 *        }
 *    }
 *
 * 5) اختياري — اختصار TTL لمفتاح الأونلاين في `updateLocation` (مثلاً 240 ثانية)
 *    حتى تختفي البقايا بسرعة إن لم يُستدعَ go-offline (إغلاق قسري للتطبيق).
 */

/*
public function goOffline(\Illuminate\Http\Request $request)
{
    $user = $request->user();
    if (! $user || $user->roll !== 'Driver') {
        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
    }

    $driver = \App\Models\Driver::where('userId', $user->id)->first();
    if (! $driver) {
        return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
    }

    $id = (int) $driver->id;

    try {
        \Illuminate\Support\Facades\Redis::del('driver:'.$id.':online');
        \Illuminate\Support\Facades\Redis::zrem('drivers', (string) $id);
    } catch (\Throwable $e) {
        // لا نُرجع 500؛ التطبيق وضع السائق «غير متصل» محلياً.
    }

    return response()->json([
        'success' => true,
        'message' => 'OK',
    ]);
}
*/
