<?php

namespace App\Http\Middleware;

use App\Models\AppSetting;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * عند تفعيل القطع عبر: php artisan service:cut
 * تُرفض كل طلبات /api (التطبيق + لوحة الأدمن) حتى: php artisan service:restore
 */
class RejectWhenServiceCut
{
    public const SETTING_KEY = 'service_link_cut';

    public const CACHE_KEY = 'service_link_cut';

    public static function isCut(): bool
    {
        try {
            $cached = Cache::get(self::CACHE_KEY);
            if ($cached !== null) {
                return (bool) $cached;
            }
        } catch (\Throwable) {
            // cache driver unavailable — fall through to DB setting
        }

        try {
            $on = AppSetting::getBool(self::SETTING_KEY, false);
            try {
                Cache::forever(self::CACHE_KEY, $on);
            } catch (\Throwable) {
            }

            return $on;
        } catch (\Throwable) {
            return false;
        }
    }

    public static function cut(): void
    {
        AppSetting::setValue(self::SETTING_KEY, '1');
        try {
            Cache::forever(self::CACHE_KEY, true);
        } catch (\Throwable) {
        }
    }

    public static function restore(): void
    {
        AppSetting::setValue(self::SETTING_KEY, '0');
        try {
            Cache::forever(self::CACHE_KEY, false);
        } catch (\Throwable) {
        }
    }

    public function handle(Request $request, Closure $next): Response
    {
        if (! self::isCut()) {
            return $next($request);
        }

        return response()->json([
            'success' => false,
            'state' => false,
            'code' => 'SERVICE_CUT',
            'message' => 'تم قطع الاتصال بالخادم مؤقتاً. أعد التشغيل من السيرفر: php artisan service:restore',
        ], 503);
    }
}
