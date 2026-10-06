<?php

use App\Http\Controllers\LocationController;
use App\Http\Controllers\RequestController;
use App\Http\Controllers\ReportController;
use App\Http\Controllers\ComplaintController;
use App\Events\MessagePosted;
use App\Http\Controllers\UserController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\CarTypeController;
use App\Http\Controllers\DiscountController;
use App\Http\Controllers\DriverController;
use App\Http\Controllers\EmergencyController;
use App\Http\Controllers\Admin\AdminDriverSubscriptionController;
use App\Http\Controllers\Admin\AdminDriverWalletController;
use App\Http\Controllers\DriverWalletController;
use App\Http\Controllers\Admin\AdminCustomerWalletController;
use App\Http\Controllers\CustomerWalletController;
use App\Http\Controllers\Admin\WhatsAppBroadcastController;
use App\Http\Controllers\Admin\MtnSmsBroadcastController;
use App\Http\Controllers\AppUpdateController;
use App\Http\Controllers\AdminOverviewController;
use App\Http\Controllers\CustomerNotificationController;
use App\Http\Controllers\CustomerLocationController;
use App\Http\Controllers\DriverNotificationController;
use App\Http\Controllers\DriverPollController;
use App\Http\Controllers\RoutingController;
use App\Http\Controllers\ServiceAreaPublicController;

Route::post('/routing/driving-summary', [RoutingController::class, 'drivingSummary'])
    ->middleware('auth:sanctum');

Route::get('/driver/poll-snapshot', [DriverPollController::class, 'snapshot'])
    ->middleware(['auth:sanctum', 'driver.poll']);

/*Route::post('/broadcast',function(){
    broadcast(new MessagePosted('hello from Postman2'));
    return response()->json(['status'=>'sent']);
});*/

Route::post('/broadcast', function (Request $request) {
    Log::info('Route HIT');

    broadcast(new MessagePosted($request));

    Log::info('After broadcast');

    return response()->json(['ok' => true]);
});

//////////////////////////////////////////

Route::get('/user', function (Request $request) {
    $user = $request->user();
    if ($user && ($user->roll ?? '') === 'Customer') {
        try {
            \App\Services\CustomerPresenceService::markOnline((int) $user->id);
        } catch (\Throwable $e) {
        }
    }

    return $user;
})->middleware('auth:sanctum');

// VUL-04: حدّ الطلبات على نقاط المصادقة/OTP
Route::middleware('throttle:8,1')->group(function () {
    Route::post('/login', [UserController::class, 'login']);
    Route::post('/register', [UserController::class, 'register']);
    Route::post('/register-customer', [UserController::class, 'registerCustomer']);
});
Route::middleware('throttle:5,1')->group(function () {
    Route::post('/confirm-account', [UserController::class, 'confirmAccount']);
    Route::post('/confirmation-code/resend', [UserController::class, 'resendConfirmationCode']);
    Route::post('/forget-password', [UserController::class, 'forgotPassword']);
    Route::post('/forget-password/check-code', [UserController::class, 'confirmForgetPassword']);
    Route::post('/forget-password/reset', [UserController::class, 'resetPasswordAfterOtp']);
});

Route::post('/user/update', [UserController::class, 'update'])->middleware('auth:sanctum');
Route::post('/addEmployee', [UserController::class, 'addEmployee'])->middleware('auth:sanctum');
Route::post('/logout', [UserController::class, 'logout'])->middleware('auth:sanctum');
Route::post('/user/fcm-token', [UserController::class, 'updateFcmToken'])->middleware('auth:sanctum');
Route::get('/getProfile', [UserController::class, 'getProfile'])->middleware('auth:sanctum');
/** حذف الحساب من التطبيق — مطلوب App Store / Google Play */
Route::delete('/account', [UserController::class, 'deleteMyAccount'])->middleware('auth:sanctum');
Route::get('/test', function () {
    return 'API working';
});

Route::get('/app/update-info', [AppUpdateController::class, 'info']);

Route::get('/service-areas/active', [ServiceAreaPublicController::class, 'active']);
Route::get('/pricing/zone-quote', [\App\Http\Controllers\PricingZoneController::class, 'quote'])->middleware('auth:sanctum');
Route::get('/pricing/zones-map', [\App\Http\Controllers\PricingZoneController::class, 'appMap'])->middleware('auth:sanctum');

Route::prefix('customer')->middleware('auth:sanctum')->group(function () {
    Route::get('/notifications', [CustomerNotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [CustomerNotificationController::class, 'unreadCount']);
    Route::post('/notifications/{id}/read', [CustomerNotificationController::class, 'markRead']);
    Route::post('/update-location', [CustomerLocationController::class, 'updateLocation']);
    Route::post('/go-offline', [CustomerLocationController::class, 'goOffline']);
    Route::get('/wallet', [CustomerWalletController::class, 'me']);
});

Route::prefix('driver')->middleware('auth:sanctum')->group(function () {
    Route::get('/notifications', [DriverNotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [DriverNotificationController::class, 'unreadCount']);
    Route::post('/notifications/{id}/read', [DriverNotificationController::class, 'markRead']);
    Route::get('/wallet', [DriverWalletController::class, 'me']);
});

Route::prefix('car-types')->group(function () {
    Route::get('/index', [CarTypeController::class, 'index']);
    Route::get('/show/{id}', [CarTypeController::class, 'show']);
    Route::get('/trashed/all', [CarTypeController::class, 'trashed']);

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/store', [CarTypeController::class, 'store']);
        Route::put('/update', [CarTypeController::class, 'update']);
        Route::delete('/destroy/{id}', [CarTypeController::class, 'destroy']);
        Route::post('/{id}/restore', [CarTypeController::class, 'restore']);
        Route::delete('/{id}/force', [CarTypeController::class, 'forceDelete']);
    });
});
Route::prefix('drivers')->group(function () {
    // العمليات الأساسية
    Route::post('/store', [DriverController::class, 'store'])->middleware('auth:sanctum');
    Route::get('/getImage/{path}', [DriverController::class, 'getImage'])
        ->where('path', '.*')
        ->name('drivers.getImage');
    Route::post('/updateLocation', [DriverController::class, 'updateLocation'])->middleware('auth:sanctum');
    Route::post('/go-offline', [DriverController::class, 'goOffline'])->middleware('auth:sanctum');
    Route::get('/me/profile', [DriverController::class, 'myProfile'])->middleware('auth:sanctum');
    Route::get('/me/pricing', [DriverController::class, 'myPricing'])->middleware('auth:sanctum');
    Route::get('/me/free-meter-pricing', [DriverController::class, 'myFreeMeterPricing'])->middleware('auth:sanctum');
    Route::get('/me/receive-radius', [DriverController::class, 'myReceiveRadius'])->middleware('auth:sanctum');
    Route::put('/me/receive-radius', [DriverController::class, 'updateReceiveRadius'])->middleware('auth:sanctum');
    Route::post('/me/receive-radius', [DriverController::class, 'updateReceiveRadius'])->middleware('auth:sanctum');
    Route::get('/active', [DriverController::class, 'active'])->middleware('auth:sanctum');
    Route::get('/index', [DriverController::class, 'index'])->middleware('auth:sanctum');
    Route::get('/show/{id}', [DriverController::class, 'show'])->middleware('auth:sanctum');

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/update/{id}', [DriverController::class, 'update']);
        Route::delete('/destroy/{id}', [DriverController::class, 'destroy']);
        Route::get('/trashed/all', [DriverController::class, 'trashed']);
        Route::post('/{id}/restore', [DriverController::class, 'restore']);
        Route::delete('/{id}/force', [DriverController::class, 'forceDelete']);
    });
});
Route::prefix('discounts')->group(function () {
    // VUL-07: الخصومات للمستخدمين المسجّلين فقط (لا فهرسة عامة للأكواد)
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/index', [DiscountController::class, 'index']);
        Route::post('/store', [DiscountController::class, 'store']);
        Route::get('/show/{id}', [DiscountController::class, 'show']);
        Route::post('/update/{id}', [DiscountController::class, 'update']);
        Route::delete('/destroy/{id}', [DiscountController::class, 'destroy']);
        Route::get('/by-code/{code}', [DiscountController::class, 'findByCode']);
        Route::post('/validate', [DiscountController::class, 'validateAndApply']);
        Route::post('/confirm', [DiscountController::class, 'confirmUsage']);
        Route::get('/statistics/summary', [DiscountController::class, 'statistics']);
        Route::get('/trashed/all', [DiscountController::class, 'trashed']);
        Route::post('/{id}/restore', [DiscountController::class, 'restore']);
        Route::delete('/{id}/force', [DiscountController::class, 'forceDelete']);
    });
});

Route::prefix('locations')->middleware('auth:sanctum')->group(function () {
    Route::get('/index', [LocationController::class, 'index']);
    Route::post('/store', [LocationController::class, 'store']);
    Route::post('/bulk', [LocationController::class, 'bulkStore']);
    Route::get('/show/{id}', [LocationController::class, 'show']);
    Route::post('/update/{id}', [LocationController::class, 'update']);
    Route::delete('/destroy/{id}', [LocationController::class, 'destroy']);
    Route::post('/nearby/search', [LocationController::class, 'nearby']);
    Route::post('/distance/calculate', [LocationController::class, 'calculateDistance']);
    Route::get('/popular/pickup', [LocationController::class, 'popularPickupLocations']);
    Route::get('/popular/dropoff', [LocationController::class, 'popularDropoffLocations']);
    Route::get('/trashed/all', [LocationController::class, 'trashed']);
    Route::post('/{id}/restore', [LocationController::class, 'restore']);
    Route::delete('/{id}/force', [LocationController::class, 'forceDelete']);
});

// Routes للطلبات
Route::prefix('requests')->group(function () {
    Route::post('/store', [RequestController::class, 'store'])->middleware('auth:sanctum');
    Route::get('/nearby-drivers-booking', [RequestController::class, 'nearbyDriversForBooking'])->middleware('auth:sanctum');
    Route::get('/immediate-pending', [RequestController::class, 'getPendingImmediate'])
        ->middleware(['auth:sanctum', 'driver.poll']);
    Route::get('/available-bookings', [RequestController::class, 'getAvailableBookings'])->middleware('auth:sanctum');
    Route::get('/user/{userId}', [RequestController::class, 'getUserRequests'])->middleware('auth:sanctum');
    Route::get('/customer/active', [RequestController::class, 'customerActiveTrip'])->middleware('auth:sanctum');
    Route::get('/driver/{driverId}/trips', [RequestController::class, 'getDriverTrips'])->middleware('auth:sanctum');
    Route::get('/driver/{driverId}', [RequestController::class, 'getDriverRequests'])
        ->middleware(['auth:sanctum', 'driver.poll']);
    Route::post('/free-meter/start', [RequestController::class, 'startFreeMeter'])->middleware('auth:sanctum');
    Route::get('/{requestId}/trip-tracking', [RequestController::class, 'customerTripTracking'])->middleware('auth:sanctum');
    Route::get('/{requestId}/immediate-status', [RequestController::class, 'immediateStatus'])->middleware('auth:sanctum');
    Route::post('/{requestId}/expand-search', [RequestController::class, 'expandSearch'])->middleware('auth:sanctum');
    Route::post('/{requestId}/search-timeout', [RequestController::class, 'searchTimeout'])->middleware('auth:sanctum');
    Route::post('/{requestId}/select-driver', [RequestController::class, 'selectDriver'])->middleware('auth:sanctum');
    Route::post('/{requestId}/driver-decline-immediate', [RequestController::class, 'driverDeclineImmediate'])->middleware('auth:sanctum');
    Route::post('/{requestId}/driver-decline-scheduled', [RequestController::class, 'driverDeclineScheduled'])->middleware('auth:sanctum');
    Route::post('/{requestId}/driver-cancel-scheduled', [RequestController::class, 'driverCancelScheduled'])->middleware('auth:sanctum');
    Route::post('/{requestId}/driver-cancel-en-route', [RequestController::class, 'driverCancelEnRoute'])->middleware('auth:sanctum');
    Route::post('/{requestId}/cancel', [RequestController::class, 'cancelByCustomer'])->middleware('auth:sanctum');
    Route::post('/{requestId}/abort', [RequestController::class, 'abortActiveTrip'])->middleware('auth:sanctum');
    Route::post('/{requestId}/accept', [RequestController::class, 'acceptBooking'])->middleware('auth:sanctum');
    // السائق: وصلت (داخلي) → بدء الرحلة → Running + إشعار «وصل السائق» للراكب
    Route::post('/{requestId}/driver-arrived', [RequestController::class, 'driverArrived'])->middleware('auth:sanctum');
    Route::post('/{requestId}/confirm-driver-arrived', [RequestController::class, 'customerConfirmDriverArrived'])->middleware('auth:sanctum');
    Route::post('/{requestId}/set-destination', [RequestController::class, 'customerSetDestination'])->middleware('auth:sanctum');
    Route::post('/{requestId}/update-pickup', [RequestController::class, 'customerUpdatePickup'])->middleware('auth:sanctum');
    Route::post('/{requestId}/scheduled-passenger-ready', [RequestController::class, 'scheduledPassengerReady'])->middleware('auth:sanctum');
    Route::post('/{requestId}/scheduled-passenger-wait-or-cancel', [RequestController::class, 'scheduledPassengerWaitOrCancel'])->middleware('auth:sanctum');
    Route::post('/{requestId}/scheduled-driver-response', [RequestController::class, 'scheduledDriverResponse'])->middleware('auth:sanctum');

    // legacy (kept): startTrip (Reserved -> Running)
    Route::post('/{requestId}/start', [RequestController::class, 'startTrip'])->middleware('auth:sanctum');
    Route::post('/{requestId}/live-meter', [RequestController::class, 'reportLiveMeter'])->middleware('auth:sanctum');
    Route::post('/{requestId}/finish', [RequestController::class, 'finishTrip'])->middleware('auth:sanctum');
    Route::get('/{requestId}/payment', [CustomerWalletController::class, 'paymentStatus'])->middleware('auth:sanctum');
    Route::post('/{requestId}/pay', [CustomerWalletController::class, 'pay'])->middleware('auth:sanctum');
    Route::post('/{requestId}/remind', [RequestController::class, 'remindDriver'])->middleware('auth:sanctum');
});

Route::prefix('emergency')->group(function () {
    Route::post('/sos', [EmergencyController::class, 'send'])->middleware('auth:sanctum');
    Route::post('/sos/live', [EmergencyController::class, 'liveUpdate'])->middleware('auth:sanctum');
    Route::get('/active', [EmergencyController::class, 'active'])->middleware('auth:sanctum');
    Route::get('/live/{key}', [EmergencyController::class, 'live'])
        ->where('key', '[0-9]+|c:[0-9]+')
        ->middleware('auth:sanctum');
    Route::delete('/active/{key}', [EmergencyController::class, 'clear'])
        ->where('key', '[0-9]+|c:[0-9]+')
        ->middleware('auth:sanctum');
});

// Routes للتقارير
Route::prefix('admin')->middleware(['auth:sanctum', 'staff'])->group(function () {
    Route::get('/map-snapshot', [AdminOverviewController::class, 'mapSnapshot']);
    Route::get('/customers-map-snapshot', [AdminOverviewController::class, 'customersMapSnapshot']);
    Route::get('/running-trips/{id}/live', [AdminOverviewController::class, 'liveTripWatch']);
    Route::get('/running-trips/{id}/live-stream', [AdminOverviewController::class, 'liveTripStream']);
    Route::get('/dispatch-health', [AdminOverviewController::class, 'dispatchHealth']);
    Route::get('/employees', [AdminOverviewController::class, 'employees']);
    Route::post('/employees', [AdminOverviewController::class, 'storeEmployee']);
    Route::put('/employees/{id}/permissions', [AdminOverviewController::class, 'updateEmployeePermissions']);
    Route::delete('/employees/{id}', [AdminOverviewController::class, 'destroyEmployee']);

    Route::get('/customers', [AdminOverviewController::class, 'customers']);
    Route::delete('/customers/{id}', [AdminOverviewController::class, 'destroyCustomer']);
    Route::get('/whatsapp-broadcast/recipients-count', [WhatsAppBroadcastController::class, 'recipientsCount']);
    Route::get('/whatsapp-broadcast/last', [WhatsAppBroadcastController::class, 'lastBroadcast']);
    Route::post('/whatsapp-broadcast/reset-batch', [WhatsAppBroadcastController::class, 'resetBatch']);
    Route::get('/whatsapp-broadcast/{id}/status', [WhatsAppBroadcastController::class, 'status']);
    Route::post('/whatsapp-broadcast/{id}/cancel', [WhatsAppBroadcastController::class, 'cancel']);
    Route::post('/whatsapp-broadcast', [WhatsAppBroadcastController::class, 'send']);
    Route::get('/mtn-sms-broadcast/recipients-count', [MtnSmsBroadcastController::class, 'recipientsCount']);
    Route::get('/mtn-sms-broadcast/last', [MtnSmsBroadcastController::class, 'lastBroadcast']);
    Route::post('/mtn-sms-broadcast/reset-batch', [MtnSmsBroadcastController::class, 'resetBatch']);
    Route::get('/mtn-sms-broadcast/{id}/status', [MtnSmsBroadcastController::class, 'status']);
    Route::post('/mtn-sms-broadcast/{id}/cancel', [MtnSmsBroadcastController::class, 'cancel']);
    Route::post('/mtn-sms-broadcast', [MtnSmsBroadcastController::class, 'send']);
    Route::get('/app-update-settings', [WhatsAppBroadcastController::class, 'appUpdateSettings']);
    Route::put('/app-update-settings', [WhatsAppBroadcastController::class, 'updateAppUpdateSettings']);
    Route::get('/requests', [AdminOverviewController::class, 'requests']);
    Route::post('/requests/dispatch-to-driver', [AdminOverviewController::class, 'dispatchToDriver']);
    Route::get('/places/search', [\App\Http\Controllers\Admin\AdminPlaceSearchController::class, 'search']);
    Route::get('/places/reverse', [\App\Http\Controllers\Admin\AdminPlaceSearchController::class, 'reverse']);
    Route::get('/requests/{id}', [AdminOverviewController::class, 'requestDetail']);
    Route::post('/requests/{id}/expire-pending', [AdminOverviewController::class, 'expirePendingRequest']);
    Route::post('/requests/{id}/cancel-active', [AdminOverviewController::class, 'cancelActiveRequest']);

    Route::get('/complaints-reviews', [AdminOverviewController::class, 'complaintsReviews']);

    Route::get('/service-areas', [AdminOverviewController::class, 'serviceAreas']);
    Route::post('/service-areas', [AdminOverviewController::class, 'storeServiceArea']);
    Route::put('/service-areas/{id}', [AdminOverviewController::class, 'updateServiceArea']);
    Route::delete('/service-areas/{id}', [AdminOverviewController::class, 'destroyServiceArea']);

    Route::get('/pricing-zones', [\App\Http\Controllers\PricingZoneController::class, 'index']);
    Route::post('/pricing-zones', [\App\Http\Controllers\PricingZoneController::class, 'store']);
    Route::put('/pricing-zones/rules', [\App\Http\Controllers\PricingZoneController::class, 'updateRules']);
    Route::put('/pricing-zones/outside', [\App\Http\Controllers\PricingZoneController::class, 'updateOutside']);
    Route::put('/pricing-zones/{id}', [\App\Http\Controllers\PricingZoneController::class, 'update']);
    Route::delete('/pricing-zones/{id}', [\App\Http\Controllers\PricingZoneController::class, 'destroy']);
    Route::get('/pricing-zones/quote', [\App\Http\Controllers\PricingZoneController::class, 'quote']);

    Route::post('/discounts/{id}/notify-customers', [AdminOverviewController::class, 'notifyDiscountCustomers']);

    Route::get('/export-users.csv', [AdminOverviewController::class, 'exportUsersCsv']);

    Route::get('/free-meter-settings', [AdminOverviewController::class, 'freeMeterSettings']);
    Route::put('/free-meter-settings', [AdminOverviewController::class, 'updateFreeMeterSettings']);

    Route::get('/drivers/stats', [AdminOverviewController::class, 'driverStats']);
    Route::get('/drivers/location-track', [AdminOverviewController::class, 'driverLocationTrack']);
    Route::get('/drivers/{id}/trips', [AdminOverviewController::class, 'driverTrips']);

    Route::post('/drivers/{id}/subscription/renew', [AdminDriverSubscriptionController::class, 'renew']);
    Route::post('/drivers/{id}/subscription/set-period', [AdminDriverSubscriptionController::class, 'setPeriod']);
    Route::post('/drivers/{id}/subscription/unblock', [AdminDriverSubscriptionController::class, 'unblock']);
    Route::post('/drivers/{id}/subscription/block', [AdminDriverSubscriptionController::class, 'block']);

    Route::get('/drivers/{id}/wallet', [AdminDriverWalletController::class, 'show']);
    Route::post('/drivers/{id}/wallet/reward', [AdminDriverWalletController::class, 'reward']);
    Route::post('/drivers/{id}/wallet/withdraw', [AdminDriverWalletController::class, 'withdraw']);
    Route::post('/drivers/{id}/wallet/violation', [AdminDriverWalletController::class, 'violation']);

    Route::get('/customer-wallets/log', [AdminCustomerWalletController::class, 'log']);
    Route::get('/customers/{id}/wallet', [AdminCustomerWalletController::class, 'show']);
    Route::post('/customers/{id}/wallet/topup', [AdminCustomerWalletController::class, 'topup']);
    Route::post('/customers/{id}/wallet/deduct', [AdminCustomerWalletController::class, 'deduct']);
    Route::post('/customers/{id}/wallet/adjust', [AdminCustomerWalletController::class, 'adjust']);
});

Route::prefix('reports')->middleware(['auth:sanctum', 'staff'])->group(function () {
    Route::get('/dashboard-summary', [ReportController::class, 'dashboardSummary']);
    Route::get('/dashboard-revenue-trips', [ReportController::class, 'dashboardRevenueTrips']);
    Route::get('/financial', [ReportController::class, 'financialReport']);
    Route::get('/operational', [ReportController::class, 'operationalReport']);
    Route::get('/quality', [ReportController::class, 'qualityReport']);
});

Route::prefix('complaints')->middleware('auth:sanctum')->group(function () {
    Route::post('/', [ComplaintController::class, 'store']);
    Route::get('/request/{requestId}', [ComplaintController::class, 'getRequestComplaints']);
    // إدارة الشكاوى للموظفين فقط
    Route::middleware('staff')->group(function () {
        Route::get('/', [ComplaintController::class, 'index']);
        Route::get('/driver/{driverId}', [ComplaintController::class, 'getDriverComplaints']);
        Route::get('/statistics/summary', [ComplaintController::class, 'statistics']);
        Route::get('/{id}', [ComplaintController::class, 'show']);
        Route::put('/{id}/resolve', [ComplaintController::class, 'resolve']);
        Route::delete('/{id}', [ComplaintController::class, 'destroy']);
        Route::post('/{id}/restore', [ComplaintController::class, 'restore']);
    });
});
