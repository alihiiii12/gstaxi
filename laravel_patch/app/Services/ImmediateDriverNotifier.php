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
        $radius = DriverNearbyService::maxNotifyRadiusKm();
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

        $distances = DriverNearbyService::nearbyOnlineDriverDistances($lng, $lat, $radius);
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
                broadcast(new NewRequestEvent($id, $request->id));
                $this->pushImmediateRequestToDriver($driver, (int) $request->id);
                $notified++;
            } catch (\Throwable $e) {
                Log::debug('ImmediateDriverNotifier: notify driver '.$id.' — '.$e->getMessage());
            }
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
                    'request_id' => (string) $requestId,
                ]
            );
        } catch (\Throwable $e) {
            Log::debug('ImmediateDriverNotifier FCM: '.$e->getMessage());
        }
    }
}
