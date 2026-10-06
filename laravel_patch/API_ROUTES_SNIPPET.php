<?php

// أضف في أعلى routes/api.php بعد use الحالية:
// use App\Http\Controllers\RoutingController;

// مسار ملخص الطريق (مصادقة مطلوبة):
// Route::post('/routing/driving-summary', [RoutingController::class, 'drivingSummary'])
//     ->middleware('auth:sanctum');

// داخل مجموعة Route::prefix('requests') أضف هذه السطرين *قبل*
// Route::post('/{requestId}/accept', ...) لتجنب تعارض المعاملات:

// Route::get('/{requestId}/immediate-status', [RequestController::class, 'immediateStatus'])
//     ->middleware('auth:sanctum');
// Route::post('/{requestId}/driver-decline-immediate', [RequestController::class, 'driverDeclineImmediate'])
//     ->middleware('auth:sanctum');

// --- مجموعة السائقين (أو داخل Route::prefix('drivers') الموجودة) ---
// إزالة السائق من Redis GEO + مفتاح الأونلاين عند «غير متصل» من تطبيق Flutter:
// Route::post('/go-offline', [DriverController::class, 'goOffline'])
//     ->middleware('auth:sanctum');
// (التطبيق يستدعي: POST .../api/drivers/go-offline — انظر laravel_patch/driver_go_offline.php)
