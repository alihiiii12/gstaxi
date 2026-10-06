<?php

/**
 * ألصق بعد التحقق من كلمة المرور وقبل إصدار التوكن (عند roll = Driver).
 *
 * use App\Models\Driver;
 * use App\Services\DriverSubscriptionService;
 */

$driver = Driver::where('userId', $user->id)->first();
if ($driver) {
    $blockMsg = DriverSubscriptionService::loginBlockedMessage($driver);
    if ($blockMsg !== null) {
        return response()->json([
            'success' => false,
            'state' => false,
            'message' => $blockMsg,
            'code' => 'subscription_blocked',
        ], 403);
    }
}
