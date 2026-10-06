<?php

namespace App\Http\Middleware;

use App\Models\Driver;
use App\Services\DriverPollCacheService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * يحدّ استطلاع السائق — يُرجع آخر نتيجة مخزّنة ولا يُرجع [] فارغة (تفوت الطلبات).
 */
class ThrottleDriverPoll
{
    private const MIN_INTERVAL = 8;

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user) {
            return $next($request);
        }

        $throttleKey = 'throttle_driver_poll:'.$user->id;
        if (Cache::has($throttleKey)) {
            $cached = $this->cachedPollResponse($request, $user);
            if ($cached !== null) {
                return $cached;
            }

            return $next($request);
        }

        Cache::put($throttleKey, 1, self::MIN_INTERVAL);

        return $next($request);
    }

    private function cachedPollResponse(Request $request, $user): ?Response
    {
        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return null;
        }
        $did = (int) $driver->id;

        if ($request->is('api/driver/poll-snapshot')) {
            $snap = DriverPollCacheService::getPollSnapshotLast($did)
                ?? Cache::get(DriverPollCacheService::pollSnapshotKey($did));
            if (is_array($snap)) {
                return response()->json(['success' => true, 'data' => $snap]);
            }
        }

        if ($request->is('api/requests/immediate-pending')) {
            $pending = DriverPollCacheService::getImmediatePendingLast($did);
            if ($pending !== null) {
                return response()->json(['success' => true, 'data' => $pending]);
            }
        }

        if (preg_match('#^api/requests/driver/(\d+)$#', $request->path(), $m)) {
            if ((int) $m[1] === $did) {
                $rows = DriverPollCacheService::getDriverRequestsLast($did);
                if ($rows !== null) {
                    return response()->json(['success' => true, 'data' => $rows]);
                }
            }
        }

        return null;
    }
}
