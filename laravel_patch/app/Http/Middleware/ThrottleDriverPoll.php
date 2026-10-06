<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * يحدّ معدل استطلاع السائق (poll-snapshot / immediate-pending / driver requests).
 */
class ThrottleDriverPoll
{
    /** أقل فترة بين طلبين poll من نفس المستخدم (ثوانٍ). */
    private const MIN_INTERVAL = 2;

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user) {
            return $next($request);
        }

        $key = 'throttle_driver_poll:'.$user->id;
        if (Cache::has($key)) {
            return response()->json([
                'success' => false,
                'message' => 'Too many poll requests',
                'code' => 'POLL_THROTTLED',
            ], 429);
        }

        Cache::put($key, 1, self::MIN_INTERVAL);

        return $next($request);
    }
}
