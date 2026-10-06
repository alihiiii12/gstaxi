<?php

namespace App\Services;

use App\Events\NewRequestEvent;
use App\Models\Driver;
use App\Models\RequestModel;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;

class ImmediateDriverNotifier
{
    /**
     * إشعار السائقين **القريبين والنشطين فقط** من موقع انطلاق الراكب.
     */
    /**
     * @return array{notified: int, nearby: int, redis_ok: bool, radius_km: float}
     */
    public function notify(RequestModel $request, float $lng, float $lat): array
    {
        $busy = DriverNearbyService::busyDriverIds();
        $key = 'request:'.$request->id.':eligible';
        $carTypeId = (int) $request->carTypeId;
        $radius = DriverNearbyService::searchRadiusKm();
        $notified = 0;

        try {
            Redis::ping();
        } catch (\Throwable $e) {
            Log::error('ImmediateDriverNotifier: Redis غير متاح — '.$e->getMessage());

            return [
                'notified' => 0,
                'nearby' => 0,
                'redis_ok' => false,
                'radius_km' => $radius,
            ];
        }

        try {
            Redis::del($key);
        } catch (\Throwable $e) {
        }

        $distances = DriverNearbyService::nearbyEligibleDriverDistances($lng, $lat);
        $nearbyCount = count($distances);

        foreach ($distances as $id => $km) {
            if (in_array($id, $busy, true)) {
                continue;
            }

            $driver = Driver::find($id);
            if (! $driver || ! DriverNearbyService::driverMatchesRequest($driver, $carTypeId)) {
                continue;
            }

            try {
                Redis::sadd($key, (string) $id);
            } catch (\Throwable $e) {
                Log::debug('ImmediateDriverNotifier: redis sadd '.$id.' — '.$e->getMessage());
            }

            // البث WebSocket منفصل عن FCM — تعطّل Reverb لا يمنع وصول الإشعار للتطبيق
            try {
                broadcast(new NewRequestEvent($id, $request->id));
            } catch (\Throwable $e) {
                Log::debug('ImmediateDriverNotifier: broadcast '.$id.' — '.$e->getMessage());
            }

            try {
                $this->pushImmediateRequestToDriver($driver, (int) $request->id);
            } catch (\Throwable $e) {
                Log::debug('ImmediateDriverNotifier: fcm '.$id.' — '.$e->getMessage());
            }

            $notified++;
        }

        if ($notified > 0) {
            try {
                Redis::expire($key, 3600);
            } catch (\Throwable $e) {
            }
            DriverPollCacheService::bust();
            Log::info('ImmediateDriverNotifier: notified '.$notified.' drivers within '.$radius.'km for request '.$request->id);
        } else {
            Log::warning('ImmediateDriverNotifier: no eligible drivers notified (nearby='.$nearbyCount.', radius='.$radius.'km) for request '.$request->id);
        }

        return [
            'notified' => $notified,
            'nearby' => $nearbyCount,
            'redis_ok' => true,
            'radius_km' => $radius,
        ];
    }

    /** مراحل توسيع البحث من شاشة الراكب: المرحلة ← نصف القطر (كم)، بغض النظر عن نطاق استقبال السائق. */
    public const EXPAND_RADII_KM = [1 => 3.0];

    /** ثانية (من إنشاء الطلب) ← المرحلة؛ تطابق CustomerSearchTimeline في التطبيق. */
    public const EXPAND_STAGE_AT_SECONDS = [1 => 60];

    /** مهلة البحث عند الراكب (ثانية) — بعدها لا يوسَّع النطاق. */
    public const SEARCH_TIMEOUT_SECONDS = 180;

    public static function expandStageKey(int $requestId): string
    {
        return 'request:'.$requestId.':expand_stage';
    }

    /** أعلى مرحلة حان وقتها حسب عمر الطلب (0 = لا شيء بعد). */
    public static function dueStageForAge(int $ageSeconds): int
    {
        $due = 0;
        foreach (self::EXPAND_STAGE_AT_SECONDS as $stage => $at) {
            if ($ageSeconds >= $at) {
                $due = max($due, $stage);
            }
        }

        return $due;
    }

    /**
     * توسيع حتى مرحلة معيّنة مرة واحدة فقط (يستدعيه تطبيق الراكب والمجدول معاً).
     *
     * @return array{notified: int, radius_km: float, eligible: int, skipped?: bool}
     */
    public function expandToStage(RequestModel $request, int $stage): array
    {
        $radius = self::EXPAND_RADII_KM[$stage];
        $key = self::expandStageKey((int) $request->id);
        try {
            $done = (int) (Redis::get($key) ?? 0);
            if ($stage <= $done) {
                return ['notified' => 0, 'radius_km' => $radius, 'eligible' => 0, 'skipped' => true];
            }
            Redis::setex($key, 3600, (string) $stage);
        } catch (\Throwable $e) {
        }

        return $this->expand($request, $radius);
    }

    public static function ignoredKey(int $requestId): string
    {
        return 'request:'.$requestId.':ignored';
    }

    public static function driverIgnored(int $requestId, int $driverId): bool
    {
        try {
            return (bool) Redis::sismember(self::ignoredKey($requestId), (string) $driverId);
        } catch (\Throwable $e) {
            return false;
        }
    }

    /**
     * توسيع نطاق طلب فوري ما زال بانتظار سائق: يُشعر فقط السائقين الجدد ضمن $radiusKm.
     *
     * @return array{notified: int, radius_km: float, eligible: int}
     */
    public function expand(RequestModel $request, float $radiusKm): array
    {
        $request->loadMissing('startLocation');
        $start = $request->startLocation;
        $key = 'request:'.$request->id.':eligible';
        $out = ['notified' => 0, 'radius_km' => $radiusKm, 'eligible' => 0];
        if (! $start) {
            return $out;
        }

        $busy = DriverNearbyService::busyDriverIds();
        $carTypeId = (int) $request->carTypeId;
        $distances = DriverNearbyService::nearbyOnlineDriverDistances(
            (float) $start->longitude,
            (float) $start->latitude,
            $radiusKm
        );

        foreach ($distances as $id => $km) {
            $id = (int) $id;
            if (in_array($id, $busy, true) || self::driverIgnored((int) $request->id, $id)) {
                continue;
            }
            try {
                if (Redis::sismember($key, (string) $id)) {
                    continue;
                }
            } catch (\Throwable $e) {
            }

            $driver = Driver::find($id);
            if (! $driver || ! DriverNearbyService::driverMatchesRequest($driver, $carTypeId)) {
                continue;
            }

            try {
                Redis::sadd($key, (string) $id);
            } catch (\Throwable $e) {
            }
            try {
                broadcast(new NewRequestEvent($id, $request->id));
            } catch (\Throwable $e) {
            }
            try {
                $this->pushImmediateRequestToDriver($driver, (int) $request->id);
            } catch (\Throwable $e) {
            }
            $out['notified']++;
        }

        try {
            if ($out['notified'] > 0) {
                Redis::expire($key, 3600);
                DriverPollCacheService::bust();
            }
            $out['eligible'] = (int) Redis::scard($key);
        } catch (\Throwable $e) {
        }

        Log::info('ImmediateDriverNotifier: expand request '.$request->id.' to '.$radiusKm.'km — notified '.$out['notified']);

        return $out;
    }

    /** إشعار سائق واحد بطلب فوري (بث مُستهدف من الأدمن أو targetDriverId). */
    public function notifyDriverOfImmediate(Driver $driver, int $requestId): void
    {
        $this->pushImmediateRequestToDriver($driver, $requestId);
    }

    private function pushImmediateRequestToDriver(Driver $driver, int $requestId): void
    {
        try {
            $driver->loadMissing('user');
            $user = $driver->user;
            $token = $user?->fcm_token ?? $user?->fcmToken ?? null;
            if (! $token || ! class_exists(FcmPushService::class)) {
                return;
            }
            app(FcmPushService::class)->sendToToken(
                $token,
                'طلب فوري جديد',
                'اضغط لعرض تفاصيل الطلب والقبول',
                [
                    'type' => 'immediate_request',
                    'kind' => 'immediate_request',
                    'request_id' => (string) $requestId,
                ]
            );
        } catch (\Throwable $e) {
            Log::debug('ImmediateDriverNotifier FCM: '.$e->getMessage());
        }
    }
}
