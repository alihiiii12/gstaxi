<?php

namespace App\Services;

use App\Events\NewRequestEvent;
use App\Models\Driver;
use App\Models\RequestModel;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;

/**
 * بث الحجز المسبق لكل السائقين الأونلاين من نفس الفئة (بدون تقييد المسافة).
 * السبب: الموعد قد يكون لاحقاً والسائق ليس قريباً من نقطة الانطلاق الآن.
 */
class ScheduledDriverNotifier
{
    /**
     * @return array{notified: int, online: int, redis_ok: bool}
     */
    public function notify(RequestModel $request, float $lng = 0, float $lat = 0): array
    {
        $busy = DriverNearbyService::busyDriverIds();
        $key = 'request:'.$request->id.':eligible';
        $carTypeId = (int) $request->carTypeId;
        $notified = 0;

        try {
            Redis::ping();
        } catch (\Throwable $e) {
            Log::error('ScheduledDriverNotifier: Redis غير متاح — '.$e->getMessage());

            return [
                'notified' => 0,
                'online' => 0,
                'redis_ok' => false,
            ];
        }

        try {
            Redis::del($key);
        } catch (\Throwable $e) {
        }

        $onlineIds = DriverNearbyService::allOnlineDriverIds();
        $onlineCount = count($onlineIds);

        foreach ($onlineIds as $id) {
            if (in_array($id, $busy, true)) {
                continue;
            }

            $driver = Driver::find($id);
            if (! $driver || ! DriverNearbyService::driverMatchesRequest($driver, $carTypeId)) {
                continue;
            }

            try {
                Redis::sadd($key, (string) $id);
                broadcast(new NewRequestEvent($id, $request->id, 'scheduled_request'));
                $this->pushScheduledOfferToDriver($driver, $request);
                $notified++;
            } catch (\Throwable $e) {
                Log::debug('ScheduledDriverNotifier: notify driver '.$id.' — '.$e->getMessage());
            }
        }

        if ($notified > 0) {
            try {
                Redis::expire($key, 86400 * 7);
            } catch (\Throwable $e) {
            }
            DriverPollCacheService::bust();
            Log::info('ScheduledDriverNotifier: notified '.$notified.' online drivers for request '.$request->id);
        } else {
            Log::warning('ScheduledDriverNotifier: no eligible online drivers (online='.$onlineCount.') for request '.$request->id);
        }

        return [
            'notified' => $notified,
            'online' => $onlineCount,
            'redis_ok' => true,
        ];
    }

    public function notifySingleDriver(Driver $driver, RequestModel $request): void
    {
        $key = 'request:'.$request->id.':eligible';
        try {
            Redis::del($key);
            Redis::sadd($key, (string) $driver->id);
            Redis::expire($key, 86400 * 7);
        } catch (\Throwable $e) {
        }
        try {
            broadcast(new NewRequestEvent((int) $driver->id, (int) $request->id, 'scheduled_request'));
        } catch (\Throwable $e) {
        }
        $this->pushScheduledOfferToDriver($driver, $request);
        DriverPollCacheService::bust();
    }

    private function pushScheduledOfferToDriver(Driver $driver, RequestModel $request): void
    {
        try {
            $driver->loadMissing('user');
            $user = $driver->user;
            $token = $user?->fcm_token ?? $user?->fcmToken ?? null;
            if (! $token || ! class_exists(FcmPushService::class)) {
                return;
            }
            $when = '';
            if ($request->requestDate) {
                $when = $request->requestDate->timezone(config('app.timezone', 'Asia/Damascus'))
                    ->format('Y-m-d H:i');
            }
            app(FcmPushService::class)->sendToToken(
                $token,
                'حجز مسبق جديد',
                $when !== ''
                    ? "طلب حجز مسبق للموعد {$when} — اضغط للقبول"
                    : 'طلب حجز مسبق جديد — اضغط للقبول',
                [
                    'type' => 'scheduled_request',
                    'kind' => 'scheduled_request',
                    'request_id' => (string) $request->id,
                ]
            );
        } catch (\Throwable $e) {
            Log::debug('ScheduledDriverNotifier FCM: '.$e->getMessage());
        }
    }
}
