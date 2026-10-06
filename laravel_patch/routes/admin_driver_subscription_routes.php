<?php

use App\Http\Controllers\Admin\AdminDriverSubscriptionController;
use Illuminate\Support\Facades\Route;

// ضمن middleware admin/auth
Route::post('admin/drivers/{id}/subscription/renew', [AdminDriverSubscriptionController::class, 'renew']);
Route::post('admin/drivers/{id}/subscription/unblock', [AdminDriverSubscriptionController::class, 'unblock']);
Route::post('admin/drivers/{id}/subscription/block', [AdminDriverSubscriptionController::class, 'block']);
