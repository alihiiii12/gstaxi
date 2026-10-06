<?php

/**
 * في بداية updateLocation بعد تحميل السائق:
 *
 * use App\Services\DriverSubscriptionService;
 */

if (! DriverSubscriptionService::isVisibleToPassengers($driver)) {
    DriverSubscriptionService::removeFromOnlineGeo($driver);

    return response()->json([
        'success' => false,
        'state' => false,
        'message' => DriverSubscriptionService::BLOCK_MESSAGE,
        'code' => 'subscription_blocked',
    ], 403);
}
