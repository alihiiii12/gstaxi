<?php

// --- أضف في bootstrap/app.php (Laravel 11) أو app/Http/Kernel.php (Laravel 10) ---
// 'driver.poll' => \App\Http\Middleware\ThrottleDriverPoll::class,

// --- في routes/api.php (داخل auth:sanctum) ---

use App\Http\Controllers\DriverPollController;

Route::get('/driver/poll-snapshot', [DriverPollController::class, 'snapshot'])
    ->middleware(['auth:sanctum', 'driver.poll']);

// طبّق نفس middleware على المسارات القديمة (حتى APK قديم):
Route::get('/requests/immediate-pending', [RequestController::class, 'getPendingImmediate'])
    ->middleware(['auth:sanctum', 'driver.poll']);

Route::get('/requests/driver/{driverId}', [RequestController::class, 'getDriverRequests'])
    ->middleware(['auth:sanctum', 'driver.poll']);
