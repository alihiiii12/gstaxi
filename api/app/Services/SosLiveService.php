<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;

/**
 * متابعة مباشرة لتنبيهات SOS: آخر موقع معروف + مسار الحركة منذ الإرسال.
 */
class SosLiveService
{
    public const TRAIL_MAX_POINTS = 600;

    public const TRAIL_TTL = 86400;

    /** أقل إزاحة (متر) لتسجيل نقطة جديدة في المسار. */
    public const TRAIL_MIN_METERS = 4.0;

    public static function trailKey(string $redisKey): string
    {
        return 'sos:trail:'.$redisKey;
    }

    public static function driverLocAtKey(int $driverId): string
    {
        return 'driver:'.$driverId.':loc_at';
    }

    public static function resetTrail(string $redisKey, float $lat, float $lng): void
    {
        try {
            Redis::del(self::trailKey($redisKey));
        } catch (\Throwable $e) {
        }
        self::appendPoint($redisKey, $lat, $lng, time());
    }

    public static function appendPoint(string $redisKey, float $lat, float $lng, ?int $t = null): void
    {
        if (! self::validCoords($lat, $lng)) {
            return;
        }
        $t = $t ?? time();
        $key = self::trailKey($redisKey);
        try {
            $lastRaw = Redis::lindex($key, 0);
            if (is_string($lastRaw) && $lastRaw !== '') {
                $prev = json_decode($lastRaw, true);
                if (is_array($prev) && isset($prev['lat'], $prev['lng'])) {
                    if ((int) ($prev['t'] ?? 0) >= $t) {
                        return;
                    }
                    $moved = DriverNearbyService::haversineKm(
                        (float) $prev['lat'],
                        (float) $prev['lng'],
                        $lat,
                        $lng
                    ) * 1000;
                    if ($moved < self::TRAIL_MIN_METERS) {
                        return;
                    }
                }
            }
            Redis::lpush($key, json_encode(['lat' => $lat, 'lng' => $lng, 't' => $t]));
            Redis::ltrim($key, 0, self::TRAIL_MAX_POINTS - 1);
            Redis::expire($key, self::TRAIL_TTL);
        } catch (\Throwable $e) {
            Log::debug('SosLiveService::appendPoint '.$e->getMessage());
        }
    }

    /** @return list<array{0:float,1:float}> من الأقدم إلى الأحدث */
    public static function trail(string $redisKey): array
    {
        try {
            $raw = Redis::lrange(self::trailKey($redisKey), 0, -1);
        } catch (\Throwable $e) {
            return [];
        }
        $out = [];
        foreach (array_reverse(is_array($raw) ? $raw : []) as $row) {
            $p = is_string($row) ? json_decode($row, true) : null;
            if (is_array($p) && isset($p['lat'], $p['lng'])) {
                $out[] = [(float) $p['lat'], (float) $p['lng']];
            }
        }

        return $out;
    }

    /**
     * أحدث موقع معروف لصاحب التنبيه.
     *
     * @param  array<string, mixed>  $entry
     * @return array{latitude:float, longitude:float, t:int, source:string}
     */
    public static function latestPosition(array $entry, string $redisKey): array
    {
        $sosT = strtotime((string) ($entry['at'] ?? '')) ?: 0;
        $best = [
            'latitude' => (float) ($entry['latitude'] ?? 0),
            'longitude' => (float) ($entry['longitude'] ?? 0),
            't' => $sosT,
            'source' => 'sos_initial',
        ];

        $consider = function (float $lat, float $lng, int $t, string $source) use (&$best): void {
            if (! self::validCoords($lat, $lng) || $t <= $best['t']) {
                return;
            }
            $best = ['latitude' => $lat, 'longitude' => $lng, 't' => $t, 'source' => $source];
        };

        if (isset($entry['live_latitude'], $entry['live_longitude'], $entry['live_at'])) {
            $consider(
                (float) $entry['live_latitude'],
                (float) $entry['live_longitude'],
                (int) $entry['live_at'],
                'sos_app'
            );
        }

        $isCustomer = str_starts_with($redisKey, 'c:');
        try {
            if ($isCustomer) {
                $uid = (int) substr($redisKey, 2);
                $raw = $uid > 0 ? Redis::get(CustomerPresenceService::lastPosKey($uid)) : null;
                $p = is_string($raw) ? json_decode($raw, true) : null;
                if (is_array($p) && isset($p['lat'], $p['lng'], $p['t'])) {
                    $consider((float) $p['lat'], (float) $p['lng'], (int) $p['t'], 'customer_app');
                }
            } else {
                $did = (int) $redisKey;
                if ($did > 0) {
                    $tRaw = Redis::get(self::driverLocAtKey($did));
                    $c = $tRaw ? DriverNearbyService::driverCoords($did) : null;
                    if ($c) {
                        $consider((float) $c['lat'], (float) $c['lng'], (int) $tRaw, 'driver_gps');
                    }
                }
            }
        } catch (\Throwable $e) {
            Log::debug('SosLiveService::latestPosition '.$e->getMessage());
        }

        return $best;
    }

    private static function validCoords(float $lat, float $lng): bool
    {
        return is_finite($lat) && is_finite($lng)
            && $lat >= -90 && $lat <= 90 && $lng >= -180 && $lng <= 180
            && ! ($lat == 0.0 && $lng == 0.0);
    }
}
