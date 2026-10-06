<?php

/**
 * في نهاية updateLocation بعد تحديث Redis GEO ومفتاح driver:{id}:online:
 *
 * use App\Services\DriverNearbyService;
 *
 * DriverNearbyService::attachDriverToFreshPendingRequests(
 *     $driver,
 *     (float) $request->longitude,
 *     (float) $request->latitude
 * );
 *
 * \App\Services\DriverPollCacheService::bust();
 *
 * بدون هذا السطر: السائق الذي أصبح «متصلاً» أو تحرّك بعد إنشاء الطلب
 * قد لا يُضاف إلى request:{id}:eligible ولا يرى الطلب في immediate-pending.
 */
