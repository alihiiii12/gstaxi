<?php

namespace App\Services;

use App\Models\Complaint;
use App\Models\RequestModel;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Schema;

/**
 * تتبع أحداث الرحلة (قبول / وصول / بدء / نهاية) والمسار الفعلي من Redis.
 *
 * المسار الافتراضي = مسار الطرق الذي يقدّره التطبيق (OSRM / تقدير الطلب).
 * المسار الفعلي = نقاط GPS لحركة السائق (قد يخرج عن الطريق).
 * المسافة الفعلية = الكيلومترات المسجّلة نظامياً في التطبيق (requestHistories.distanceTraveledKm).
 */
class TripTraceService
{
    public static function driverCoords(int $driverId): ?array
    {
        try {
            return DriverNearbyService::driverCoords($driverId);
        } catch (\Throwable $e) {
            return null;
        }
    }

    public static function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earth = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return round($earth * 2 * atan2(sqrt($a), sqrt(1 - $a)), 3);
    }

    public static function markAccepted(RequestModel $req, int $driverId): void
    {
        if (! Schema::hasColumn('requests', 'accepted_at')) {
            return;
        }
        $dirty = false;
        if ($req->accepted_at === null) {
            $req->accepted_at = now();
            $dirty = true;
        }
        $geo = self::driverCoords($driverId);
        if ($geo) {
            if ($req->accept_lat === null || $req->accept_lng === null) {
                $req->accept_lat = $geo['lat'];
                $req->accept_lng = $geo['lng'];
                $dirty = true;
            }
            $start = $req->startLocation ?? $req->startLocation()->first();
            if (
                Schema::hasColumn('requests', 'driver_to_pickup_km')
                && $req->driver_to_pickup_km === null
                && $start
                && $start->latitude !== null
                && $start->longitude !== null
            ) {
                $req->driver_to_pickup_km = self::haversineKm(
                    (float) $geo['lat'],
                    (float) $geo['lng'],
                    (float) $start->latitude,
                    (float) $start->longitude
                );
                $dirty = true;
            }
        }
        if ($dirty) {
            $req->save();
        }
    }

    public static function markArrived(RequestModel $req, int $driverId): void
    {
        if (! Schema::hasColumn('requests', 'arrived_at')) {
            return;
        }
        if ($req->arrived_at !== null) {
            return;
        }
        $req->arrived_at = now();
        // إن وُجدت إحداثيات السائق نخزّنها كنقطة وصول تقريبية عبر accept إن لم تُسجَّل
        $geo = self::driverCoords($driverId);
        if ($geo && Schema::hasColumn('requests', 'accept_lat') && $req->accept_lat === null) {
            $req->accept_lat = $geo['lat'];
            $req->accept_lng = $geo['lng'];
        }
        $req->save();
    }

    public static function markTripStarted(RequestModel $req, int $driverId): void
    {
        $dirty = false;
        if ($req->trip_started_at === null) {
            $req->trip_started_at = now();
            $dirty = true;
        }
        // إن بدأ السائق دون استدعاء «وصلت» سابقاً: سجّل وصولاً تلقائياً عند البداية
        if (Schema::hasColumn('requests', 'arrived_at') && $req->arrived_at === null) {
            $req->arrived_at = $req->trip_started_at ?? now();
            $dirty = true;
        }
        if (Schema::hasColumn('requests', 'actual_start_lat')) {
            $geo = self::driverCoords($driverId);
            if ($geo && $req->actual_start_lat === null) {
                $req->actual_start_lat = $geo['lat'];
                $req->actual_start_lng = $geo['lng'];
                $dirty = true;
            }
        }
        if ($dirty) {
            $req->save();
        }
    }

    public static function markTripEnded(RequestModel $req, int $driverId): void
    {
        if (! Schema::hasColumn('requests', 'trip_ended_at')) {
            return;
        }
        $dirty = false;
        if ($req->trip_ended_at === null) {
            $req->trip_ended_at = now();
            $dirty = true;
        }
        $geo = self::driverCoords($driverId);
        if ($geo && Schema::hasColumn('requests', 'actual_end_lat')) {
            $req->actual_end_lat = $geo['lat'];
            $req->actual_end_lng = $geo['lng'];
            $dirty = true;
        }
        if ($dirty) {
            $req->save();
        }
    }

    /**
     * مسافة المسار الافتراضي (تقدير التطبيق على الطرق عبر OSRM إن أمكن).
     */
    public static function resolvePlannedDistanceKm(RequestModel $req, $start, $dest): ?array
    {
        if (Schema::hasColumn('requests', 'estimated_distance_km') && $req->estimated_distance_km !== null) {
            return [
                'km' => (float) $req->estimated_distance_km,
                'source' => 'app_estimate',
            ];
        }

        if (! $start || ! $dest) {
            return null;
        }

        $lat1 = (float) $start->latitude;
        $lng1 = (float) $start->longitude;
        $lat2 = (float) $dest->latitude;
        $lng2 = (float) $dest->longitude;
        $cacheKey = sprintf('osrm_admin_dist:%.5f:%.5f:%.5f:%.5f', $lat1, $lng1, $lat2, $lng2);

        try {
            $cached = Cache::get($cacheKey);
            if (is_array($cached) && isset($cached['km'])) {
                return ['km' => (float) $cached['km'], 'source' => 'osrm_cached'];
            }

            $url = sprintf(
                'https://router.project-osrm.org/route/v1/driving/%.6f,%.6f;%.6f,%.6f?overview=false',
                $lng1,
                $lat1,
                $lng2,
                $lat2
            );
            $res = Http::timeout(4)->get($url);
            if ($res->ok()) {
                $meters = data_get($res->json(), 'routes.0.distance');
                if (is_numeric($meters) && (float) $meters > 0) {
                    $km = round(((float) $meters) / 1000, 3);
                    Cache::put($cacheKey, ['km' => $km], now()->addHours(6));
                    if (Schema::hasColumn('requests', 'estimated_distance_km') && $req->estimated_distance_km === null) {
                        $req->estimated_distance_km = $km;
                        $req->save();
                    }

                    return ['km' => $km, 'source' => 'osrm'];
                }
            }
        } catch (\Throwable $e) {
        }

        // احتياطي فقط إن تعذّر مسار الطرق — ليس هو «مسار التطبيق» الأساسي
        return [
            'km' => self::haversineKm($lat1, $lng1, $lat2, $lng2),
            'source' => 'straight_line_fallback',
        ];
    }

    /**
     * @return list<array{lat:float,lng:float,t:?int}>
     */
    public static function actualTrackPoints(RequestModel $req): array
    {
        $driverId = (int) ($req->driverId ?? 0);
        if ($driverId <= 0) {
            return [];
        }

        $fromTs = null;
        if ($req->accepted_at) {
            $fromTs = $req->accepted_at->getTimestamp();
        } elseif ($req->trip_started_at) {
            $fromTs = $req->trip_started_at->getTimestamp();
        } elseif ($req->created_at) {
            $fromTs = $req->created_at->getTimestamp();
        }

        $toTs = null;
        if ($req->trip_ended_at) {
            $toTs = $req->trip_ended_at->getTimestamp();
        } elseif ($req->status === RequestModel::STATUS_FINISHED && $req->updated_at) {
            $toTs = $req->updated_at->getTimestamp();
        } else {
            $toTs = time() + 60;
        }

        $out = [];
        try {
            $raw = Redis::lrange('driver:'.$driverId.':loc_history', 0, 399);
            if (! is_array($raw)) {
                return [];
            }
            foreach ($raw as $item) {
                $decoded = is_string($item) ? json_decode($item, true) : null;
                if (! is_array($decoded)) {
                    continue;
                }
                $lat = isset($decoded['lat']) ? (float) $decoded['lat'] : null;
                $lng = isset($decoded['lng']) ? (float) $decoded['lng'] : null;
                if ($lat === null || $lng === null) {
                    continue;
                }
                $ts = isset($decoded['t']) ? (int) $decoded['t'] : null;
                if ($fromTs !== null && $ts !== null && $ts < ($fromTs - 120)) {
                    continue;
                }
                if ($toTs !== null && $ts !== null && $ts > ($toTs + 120)) {
                    continue;
                }
                $out[] = ['lat' => $lat, 'lng' => $lng, 't' => $ts];
            }
        } catch (\Throwable $e) {
            return [];
        }

        return array_reverse($out);
    }

    public static function analyticsPayload(RequestModel $req): array
    {
        $start = $req->relationLoaded('startLocation')
            ? $req->startLocation
            : $req->startLocation()->first();
        $dest = $req->relationLoaded('destLocation')
            ? $req->destLocation
            : $req->destLocation()->first();
        $hist = $req->relationLoaded('history')
            ? $req->history
            : $req->history()->first();

        $planned = self::resolvePlannedDistanceKm($req, $start, $dest);
        $plannedDistanceKm = $planned['km'] ?? null;
        $plannedDistanceSource = $planned['source'] ?? null;

        $plannedDurationMin = $req->estimated_duration_minutes !== null
            ? (float) $req->estimated_duration_minutes
            : null;

        $startedAt = $req->trip_started_at;
        $endedAt = Schema::hasColumn('requests', 'trip_ended_at') ? $req->trip_ended_at : null;
        if ($endedAt === null && $req->status === RequestModel::STATUS_FINISHED && $hist?->updated_at) {
            $endedAt = $hist->updated_at;
        } elseif ($endedAt === null && $req->status === RequestModel::STATUS_FINISHED) {
            $endedAt = $req->updated_at;
        }

        $actualDurationMin = null;
        if ($startedAt && $endedAt) {
            $actualDurationMin = round(max(0, $endedAt->getTimestamp() - $startedAt->getTimestamp()) / 60, 1);
        }

        // المسافة الفعلية = ما سجّله نظام التطبيق (العداد / إنهاء الرحلة)
        $actualDistanceKm = $hist && $hist->distanceTraveledKm !== null
            ? (float) $hist->distanceTraveledKm
            : null;

        $customerRating = null;
        try {
            $complaint = Complaint::query()
                ->where('requestId', $req->id)
                ->whereNotNull('rating')
                ->orderByDesc('id')
                ->first();
            if ($complaint) {
                $customerRating = (int) $complaint->rating;
            }
        } catch (\Throwable $e) {
        }

        $driverCustomerRating = null;
        if ($hist && Schema::hasColumn('requestHistories', 'driver_customer_rating')) {
            $driverCustomerRating = $hist->driver_customer_rating !== null
                ? (int) $hist->driver_customer_rating
                : null;
        }

        $track = self::actualTrackPoints($req);
        $actualRoute = array_map(
            static fn ($p) => [(float) $p['lng'], (float) $p['lat']],
            $track
        );

        return [
            'accepted_at' => Schema::hasColumn('requests', 'accepted_at') && $req->accepted_at
                ? $req->accepted_at->toIso8601String()
                : null,
            'arrived_at' => Schema::hasColumn('requests', 'arrived_at') && $req->arrived_at
                ? $req->arrived_at->toIso8601String()
                : null,
            'trip_started_at' => $startedAt ? $startedAt->toIso8601String() : null,
            'trip_ended_at' => $endedAt ? $endedAt->toIso8601String() : null,
            'accept_point' => (Schema::hasColumn('requests', 'accept_lat') && $req->accept_lat !== null && $req->accept_lng !== null)
                ? ['latitude' => (float) $req->accept_lat, 'longitude' => (float) $req->accept_lng]
                : null,
            'actual_start_point' => (Schema::hasColumn('requests', 'actual_start_lat') && $req->actual_start_lat !== null)
                ? ['latitude' => (float) $req->actual_start_lat, 'longitude' => (float) $req->actual_start_lng]
                : null,
            'actual_end_point' => (Schema::hasColumn('requests', 'actual_end_lat') && $req->actual_end_lat !== null)
                ? ['latitude' => (float) $req->actual_end_lat, 'longitude' => (float) $req->actual_end_lng]
                : null,
            'planned_start_point' => $start
                ? ['latitude' => (float) $start->latitude, 'longitude' => (float) $start->longitude]
                : null,
            'planned_end_point' => $dest
                ? ['latitude' => (float) $dest->latitude, 'longitude' => (float) $dest->longitude]
                : null,
            'planned_duration_minutes' => $plannedDurationMin,
            'actual_duration_minutes' => $actualDurationMin,
            'planned_distance_km' => $plannedDistanceKm,
            'planned_distance_source' => $plannedDistanceSource,
            'actual_distance_km' => $actualDistanceKm,
            'driver_to_pickup_km' => Schema::hasColumn('requests', 'driver_to_pickup_km') && $req->driver_to_pickup_km !== null
                ? (float) $req->driver_to_pickup_km
                : null,
            'passenger_rating_of_trip' => $customerRating,
            'driver_rating_of_customer' => $driverCustomerRating,
            'final_cost' => $hist ? (float) ($hist->finalCost ?? 0) : null,
            'billing_kind' => $req->billing_kind,
            'actual_route_points' => $actualRoute,
            'is_free_meter' => $req->billing_kind === RequestModel::BILLING_KIND_FREE_METER,
            'notes' => [
                'planned_route' => 'مسار الطرق الذي يقدّره التطبيق بين الانطلاق والوجهة (أزرق).',
                'actual_route' => 'حركة السائق الفعلية من GPS وقد تختلف عن الطريق (أحمر).',
                'planned_distance' => 'المسافة الافتراضية = تقدير التطبيق لمسار الرحلة.',
                'actual_distance' => 'المسافة الفعلية = الكيلومترات المسجّلة نظامياً في التطبيق عند إنهاء الرحلة.',
                'timestamps' => 'وقت القبول ووقت وصول السائق يُسجَّلان تلقائياً من إجراءات السائق في الطلبات الجديدة.',
            ],
        ];
    }

    /** حمولة خفيفة لمتابعة رحلة جارية مباشرة. */
    public static function liveWatchPayload(RequestModel $req): array
    {
        $driverId = (int) ($req->driverId ?? 0);
        $live = $driverId > 0 ? self::driverCoords($driverId) : null;
        $status = RequestModel::normalizeTripStatus($req->status);
        $ended = in_array($status, [
            RequestModel::STATUS_FINISHED,
            RequestModel::STATUS_REMOVED,
        ], true);

        return [
            'id' => (int) $req->id,
            'status' => $status,
            'ended' => $ended,
            'driver_id' => $driverId,
            'driver_live' => $live
                ? ['latitude' => $live['lat'], 'longitude' => $live['lng']]
                : null,
            'accepted_at' => Schema::hasColumn('requests', 'accepted_at') && $req->accepted_at
                ? $req->accepted_at->toIso8601String()
                : null,
            'arrived_at' => Schema::hasColumn('requests', 'arrived_at') && $req->arrived_at
                ? $req->arrived_at->toIso8601String()
                : null,
            'trip_started_at' => $req->trip_started_at
                ? $req->trip_started_at->toIso8601String()
                : null,
            'server_time' => now()->toIso8601String(),
        ];
    }
}
