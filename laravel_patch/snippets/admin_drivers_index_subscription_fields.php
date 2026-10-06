<?php

/**
 * عند إرجاع قائمة السائقين (admin/drivers/index أو drivers/index):
 *
 * use App\Services\DriverSubscriptionService;
 */

'subscription_starts_at' => $driver->subscription_starts_at,
'subscription_ends_at' => $driver->subscription_ends_at,
'subscription_blocked' => (bool) $driver->subscription_blocked,
'subscription_active' => DriverSubscriptionService::isSubscriptionActive($driver),
