<?php

/**
 * رفض الطلب الفوري من السائق (زر «تجاهل» في التطبيق).
 *
 * 1) أضف المسار داخل مجموعة `requests` مع `auth:sanctum` (قبل تعارض مع مسارات أخرى إن لزم):
 *
 *    Route::post('/{requestId}/driver-decline-immediate', [RequestController::class, 'driverDeclineImmediate'])
 *        ->middleware('auth:sanctum');
 *
 * 2) انسخ الدالة `driverDeclineImmediate` أدناه داخل `RequestController`.
 *
 * يُنصح بإرسال إشعار FCM/جدول إشعارات الزبون هنا إن كان لديكم نفس آلية الإشعارات الأخرى.
 */

/*
public function driverDeclineImmediate(\Illuminate\Http\Request $request, $requestId)
{
    $user = $request->user();
    if (! $user || $user->roll !== 'Driver') {
        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
    }

    $driver = \App\Models\Driver::where('userId', $user->id)->first();
    if (! $driver) {
        return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
    }

    $driverId = (int) $driver->id;
    $rid = (int) $requestId;

    $req = \App\Models\RequestModel::find($rid);
    if (! $req) {
        return response()->json(['success' => false, 'message' => 'Request not found'], 404);
    }

    if ($req->type !== \App\Models\RequestModel::TYPE_IMMEDIATE) {
        return response()->json(['success' => false, 'message' => 'Not an immediate request'], 400);
    }

    if ($req->status !== \App\Models\RequestModel::STATUS_PENDING) {
        return response()->json([
            'success' => false,
            'message' => 'لا يمكن رفض هذا الطلب في حالته الحالية',
        ], 400);
    }

    $target = (int) ($req->targetDriverId ?? $req->target_driver_id ?? 0);
    if ($target > 0 && $target !== $driverId) {
        return response()->json([
            'success' => false,
            'message' => 'هذا الطلب موجّه لسائق آخر',
        ], 403);
    }

    \Illuminate\Support\Facades\DB::beginTransaction();
    try {
        $req->status = \App\Models\RequestModel::STATUS_REMOVED;
        $req->save();

        if (class_exists(\App\Models\RequestDriverOffer::class)) {
            \App\Models\RequestDriverOffer::where('request_id', $req->id)->delete();
        }

        try {
            \Illuminate\Support\Facades\Redis::del('request:'.$req->id.':eligible');
        } catch (\Throwable $e) {
        }

        \Illuminate\Support\Facades\DB::commit();
    } catch (\Exception $e) {
        \Illuminate\Support\Facades\DB::rollBack();

        return response()->json([
            'success' => false,
            'message' => 'An error occurred: '.$e->getMessage(),
        ], 500);
    }

    return response()->json([
        'success' => true,
        'message' => 'تم إلغاء الطلب؛ سيُبلّغ الزبون لإعادة الإرسال أو اختيار سائق آخر.',
        'data' => ['request' => $req->fresh(['startLocation', 'destLocation'])],
    ]);
}
*/
