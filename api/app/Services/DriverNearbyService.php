<?php

namespace App\Services;

use App\Events\NewRequestEvent;
use App\Models\CarType;
use App\Models\Driver;
use App\Models\RequestModel;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;

/**
 * سائقون قريبون + نشطون فقط — مصدر واحد للنطاق والتحقق من المسافة.
 */
class DriverNearbyService
{
    /** أقصى مسافة لإرسال/إشعار الطلب الفوري (كم) — حد النظام الافتراضي. */
    public const DEFAULT_NOTIFY_RADIUS_KM = 1;

    /** أقصى مسافة لعرض السائقين/الطلبات في القوائم (كم). */
    public const DEFAULT_DISPLAY_RADIUS_KM = 1;

    /** نطاقات استقبال الطلب التي يختارها السائق. */
    public const ALLOWED_RECEIVE_RADII_KM = [1, 2, 3];

    public const DEFAULT_RECEIVE_RADIUS_KM = 1;

    public const MAX_RECEIVE_RADIUS_KM = 3;

    public static function maxNotifyRadiusKm(): float
    {
        $v = (float) env('DRIVER_NOTIFY_RADIUS_KM', self::DEFAULT_NOTIFY_RADIUS_KM);

        return $v > 0 ? min($v, 50.0) : self::DEFAULT_NOTIFY_RADIUS_KM;
    }

    public static function maxDisplayRadiusKm(): float
    {
        $v = (float) env('DRIVER_DISPLAY_RADIUS_KM', self::DEFAULT_DISPLAY_RADIUS_KM);

        return $v > 0 ? min($v, 50.0) : self::DEFAULT_DISPLAY_RADIUS_KM;
    }

    /** نصف قطر البحث الجغرافي قبل تصفية تفضيل كل سائق. */
    public static function searchRadiusKm(): float
    {
        return max(self::maxNotifyRadiusKm(), (float) self::MAX_RECEIVE_RADIUS_KM);
    }

    public static function normalizeReceiveRadiusKm(mixed $value): int
    {
        $km = (int) round((float) $value);
        if (! in_array($km, self::ALLOWED_RECEIVE_RADII_KM, true)) {
            return self::DEFAULT_RECEIVE_RADIUS_KM;
        }

        return $km;
    }

    public static function receiveRadiusKmForDriverId(int $driverId): float
    {
        if ($driverId <= 0) {
            return (float) self::DEFAULT_RECEIVE_RADIUS_KM;
        }

        try {
            $cached = Redis::get('driver:'.$driverId.':receive_radius');
            if ($cached !== null && $cached !== false && $cached !== '') {
                return (float) self::normalizeReceiveRadiusKm($cached);
            }
        } catch (\Throwable $e) {
        }

        $driver = Driver::query()->select(['id', 'receive_radius_km'])->find($driverId);
        $km = self::normalizeReceiveRadiusKm($driver?->receive_radius_km ?? self::DEFAULT_RECEIVE_RADIUS_KM);
        self::cacheReceiveRadius($driverId, $km);

        return (float) $km;
    }

    public static function receiveRadiusKmForDriver(Driver $driver): float
    {
        $km = self::normalizeReceiveRadiusKm($driver->receive_radius_km ?? self::DEFAULT_RECEIVE_RADIUS_KM);
        self::cacheReceiveRadius((int) $driver->id, $km);

        return (float) $km;
    }

    public static function setReceiveRadiusKm(Driver $driver, int $km): int
    {
        $km = self::normalizeReceiveRadiusKm($km);
        if (\Illuminate\Support\Facades\Schema::hasColumn('drivers', 'receive_radius_km')) {
            $driver->receive_radius_km = $km;
            $driver->save();
        }
        self::cacheReceiveRadius((int) $driver->id, $km);

        return $km;
    }

    public static function cacheReceiveRadius(int $driverId, int $km): void
    {
        try {
            Redis::set('driver:'.$driverId.':receive_radius', (string) self::normalizeReceiveRadiusKm($km));
        } catch (\Throwable $e) {
        }
    }

    /** @deprecated استخدم maxNotifyRadiusKm() */
    public static function maxRadiusKm(): float
    {
        return self::maxNotifyRadiusKm();
    }

    public static function isDriverOnline(int $driverId): bool
    {
        try {
            return Redis::exists('driver:'.$driverId.':online') === 1;
        } catch (\Throwable $e) {
            return false;
        }
    }

    /**
     * كل السائقين المسجّلين أونلاين حالياً (من مجموعة المواقع + مفتاح online).
     *
     * @return list<int>
     */
    public static function allOnlineDriverIds(): array
    {
        $out = [];
        try {
            $members = Redis::zrange('drivers', 0, -1);
            if (! is_array($members)) {
                return [];
            }
            foreach ($members as $mid) {
                $id = (int) $mid;
                if ($id <= 0) {
                    continue;
                }
                if (self::isDriverOnline($id)) {
                    $out[] = $id;
                }
            }
        } catch (\Throwable $e) {
            Log::warning('DriverNearbyService: allOnlineDriverIds failed — '.$e->getMessage());
        }

        return array_values(array_unique($out));
    }

    public static function driverCoords(int $driverId): ?array
    {
        try {
            $coords = Redis::command('geopos', ['drivers', (string) $driverId]);
        } catch (\Throwable $e) {
            return null;
        }

        $pair = is_array($coords) && isset($coords[0]) ? $coords[0] : null;
        if (! is_array($pair) || count($pair) < 2 || $pair[0] === null || $pair[1] === null) {
            return null;
        }

        return ['lng' => (float) $pair[0], 'lat' => (float) $pair[1]];
    }

    public static function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earth = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return $earth * (2 * atan2(sqrt($a), sqrt(1 - $a)));
    }

    public static function distanceKmToPoint(int $driverId, float $pickLat, float $pickLng): ?float
    {
        $c = self::driverCoords($driverId);
        if (! $c) {
            return null;
        }

        return round(self::haversineKm($pickLat, $pickLng, $c['lat'], $c['lng']), 3);
    }

    public static function isDriverNearPoint(
        int $driverId,
        float $pickLat,
        float $pickLng,
        ?float $maxKm = null
    ): bool {
        if (! self::isDriverOnline($driverId)) {
            return false;
        }

        $dist = self::distanceKmToPoint($driverId, $pickLat, $pickLng);
        if ($dist === null) {
            return false;
        }

        return $dist <= ($maxKm ?? self::maxNotifyRadiusKm());
    }

    /**
     * @return array<int, float> driverId => distanceKm
     */
    public static function nearbyOnlineDriverDistances(float $lng, float $lat, ?float $maxKm = null): array
    {
        $radius = $maxKm ?? self::maxNotifyRadiusKm();
        $out = [];

        try {
            $members = Redis::command('georadius', [
                'drivers',
                $lng,
                $lat,
                $radius,
                'km',
                'WITHDIST',
                'ASC',
            ]);
        } catch (\Throwable $e) {
            Log::warning('DriverNearbyService: georadius failed — '.$e->getMessage());

            return [];
        }

        if (! is_array($members)) {
            return [];
        }

        foreach ($members as $row) {
            $id = 0;
            $dist = null;

            if (is_array($row)) {
                $id = (int) ($row[0] ?? 0);
                $dist = isset($row[1]) ? (float) $row[1] : null;
            } else {
                $id = (int) $row;
            }

            if ($id <= 0) {
                continue;
            }
            if (! self::isDriverOnline($id)) {
                try {
                    Redis::zrem('drivers', (string) $id);
                } catch (\Throwable $e) {
                }
                continue;
            }

            if ($dist === null) {
                $dist = self::distanceKmToPoint($id, $lat, $lng);
            }
            if ($dist === null || $dist > $radius) {
                continue;
            }

            $out[$id] = $dist;
        }

        asort($out);

        return $out;
    }

    /**
     * سائقون أونلاين ضمن نطاق بحث النظام، بعد تصفية تفضيل كل سائق (1/2/3 كم).
     *
     * @return array<int, float> driverId => distanceKm
     */
    public static function nearbyEligibleDriverDistances(float $lng, float $lat): array
    {
        $raw = self::nearbyOnlineDriverDistances($lng, $lat, self::searchRadiusKm());
        $out = [];
        foreach ($raw as $id => $dist) {
            $limit = self::receiveRadiusKmForDriverId((int) $id);
            if ($dist <= $limit + 0.001) {
                $out[(int) $id] = $dist;
            }
        }
        asort($out);

        return $out;
    }

    public static function driverMatchesRequest(Driver $driver, int $carTypeId): bool
    {
        return CarType::driverServesRequestType((int) $driver->transTypeId, $carTypeId)
            && DriverSubscriptionService::isVisibleToPassengers($driver);
    }

    /**
     * عند تحديث موقع سائق: إضافته لطلبات pending القريبة التي فاتته عند الإنشاء.
     */
    public static function attachDriverToFreshPendingRequests(Driver $driver, float $lng, float $lat): void
    {
        $throttleKey = 'attach_pending:'.$driver->id;
        try {
            if (Cache::has($throttleKey)) {
                return;
            }
            Cache::put($throttleKey, 1, 35);
        } catch (\Throwable $e) {
        }

        if (! self::isDriverOnline((int) $driver->id)) {
            return;
        }
        if (! DriverSubscriptionService::isVisibleToPassengers($driver)) {
            return;
        }

        $busy = self::busyDriverIds();
        if (in_array((int) $driver->id, $busy, true)) {
            return;
        }

        $requests = RequestModel::query()
            ->where('status', RequestModel::STATUS_PENDING)
            ->whereNull('driverId')
            ->whereIn('carTypeId', CarType::requestTypeIdsServedBy((int) $driver->transTypeId))
            ->where(function ($q) {
                $q->where(function ($q2) {
                    $q2->where('type', RequestModel::TYPE_IMMEDIATE)
                        ->where('created_at', '>=', now()->subMinutes(ImmediatePendingForDriver::FRESH_MINUTES));
                })->orWhere(function ($q2) {
                    $q2->where('type', RequestModel::TYPE_SCHEDULE)
                        ->whereNotNull('requestDate')
                        ->where('requestDate', '>', now())
                        ->where('created_at', '>=', now()->subDays(14));
                });
            })
            ->with('startLocation')
            ->orderByDesc('created_at')
            ->limit(25)
            ->get();

        foreach ($requests as $req) {
            $key = 'request:'.$req->id.':eligible';
            if (ImmediateDriverNotifier::driverIgnored((int) $req->id, (int) $driver->id)) {
                continue;
            }

            if ($req->type === RequestModel::TYPE_SCHEDULE) {
                try {
                    if (! Redis::sismember($key, (string) $driver->id)) {
                        Redis::sadd($key, (string) $driver->id);
                        Redis::expire($key, 86400 * 7);
                        broadcast(new NewRequestEvent((int) $driver->id, (int) $req->id, 'scheduled_request'));
                        DriverPollCacheService::bust();
                    }
                } catch (\Throwable $e) {
                }
                continue;
            }

            $start = $req->startLocation;
            if (! $start) {
                continue;
            }
            $pickLat = (float) $start->latitude;
            $pickLng = (float) $start->longitude;
            if (! self::isDriverNearPoint(
                (int) $driver->id,
                $pickLat,
                $pickLng,
                self::receiveRadiusKmForDriver($driver)
            )) {
                continue;
            }

            try {
                if (! Redis::sismember($key, (string) $driver->id)) {
                    Redis::sadd($key, (string) $driver->id);
                    Redis::expire($key, 3600);
                    broadcast(new NewRequestEvent((int) $driver->id, (int) $req->id));
                    DriverPollCacheService::bust();
                }
            } catch (\Throwable $e) {
            }
        }
    }

    /** @return array<int, int> */
    public static function busyDriverIds(): array
    {
        return RequestModel::query()
            ->whereNotNull('driverId')
            ->occupyingDriver()
            ->pluck('driverId')
            ->map(fn ($id) => (int) $id)
            ->filter(fn ($id) => $id > 0)
            ->unique()
            ->values()
            ->all();
    }
}
