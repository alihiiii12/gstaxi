<?php

namespace App\Services;

use App\Models\Driver;
use App\Models\RequestModel;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;

/**
 * مصدر واحد للسائقين المتصلين في لوحة الإدارة (الخريطة + عدّاد «متصل الآن»).
 * متصل = موقعه في GEO ومفتاح driver:{id}:online فعّال (نفس تعريف التوزيع).
 * من أغلق التطبيق دون «إيقاف» يبقى في GEO بعد انتهاء المفتاح — لا يُحسب.
 */
class AdminDriverPresenceService
{
    public const STATUS_AVAILABLE = 'available';

    public const STATUS_TO_PICKUP = 'to_pickup';

    public const STATUS_ON_TRIP = 'on_trip';

    /** @return list<int> */
    public static function onlineDriverIds(): array
    {
        $out = [];
        try {
            $members = Redis::zrange('drivers', 0, -1);
            foreach (is_array($members) ? $members : [] as $mid) {
                $id = (int) $mid;
                if ($id > 0 && ! isset($out[$id]) && Redis::exists('driver:'.$id.':online') === 1) {
                    $out[$id] = $id;
                }
            }
        } catch (\Throwable $e) {
            Log::warning('AdminDriverPresenceService: '.$e->getMessage());
        }

        return array_values($out);
    }

    /**
     * أحدث رحلة نشطة لكل سائق.
     *
     * @param  list<int>  $driverIds
     * @return array<int, array{status:string, trip_id:int, billing_kind:string}>
     */
    public static function activeTrips(array $driverIds): array
    {
        if ($driverIds === []) {
            return [];
        }
        $rows = RequestModel::query()
            ->whereIn('driverId', $driverIds)
            ->whereIn('status', [
                RequestModel::STATUS_RUNNING,
                RequestModel::STATUS_RESERVED,
                RequestModel::STATUS_DRIVER_ARRIVED,
                RequestModel::STATUS_AWAITING_DESTINATION,
            ])
            ->orderBy('id')
            ->get(['id', 'driverId', 'status', 'billing_kind']);

        $out = [];
        foreach ($rows as $r) {
            $id = (int) $r->driverId;
            $status = $r->status === RequestModel::STATUS_RUNNING ? self::STATUS_ON_TRIP : self::STATUS_TO_PICKUP;
            // «في رحلة» تغلب «متجه للراكب» إن وُجد الاثنان.
            if (isset($out[$id]) && $out[$id]['status'] === self::STATUS_ON_TRIP && $status !== self::STATUS_ON_TRIP) {
                continue;
            }
            $out[$id] = [
                'status' => $status,
                'trip_id' => (int) $r->id,
                'billing_kind' => (string) ($r->billing_kind ?? ''),
            ];
        }

        return $out;
    }

    /** @return list<array<string, mixed>> */
    public static function markers(): array
    {
        $ids = self::onlineDriverIds();
        if ($ids === []) {
            return [];
        }
        $drivers = Driver::with('user')->whereIn('id', $ids)->get()->keyBy('id');
        $trips = self::activeTrips($ids);
        $now = time();

        $markers = [];
        foreach ($ids as $id) {
            $geo = DriverNearbyService::driverCoords($id);
            if (! $geo) {
                continue;
            }
            $row = $drivers->get($id);
            $trip = $trips[$id] ?? null;
            $locAt = 0;
            try {
                $locAt = (int) Redis::get(SosLiveService::driverLocAtKey($id));
            } catch (\Throwable $e) {
            }
            $markers[] = [
                'driverId' => $id,
                'latitude' => $geo['lat'],
                'longitude' => $geo['lng'],
                'carNumber' => $row?->carNumber,
                'name' => $row && $row->user ? trim($row->user->firstName.' '.$row->user->lastName) : null,
                'number' => $row?->user?->number,
                'kind' => 'driver_online',
                'status' => $trip['status'] ?? self::STATUS_AVAILABLE,
                'trip_id' => $trip['trip_id'] ?? null,
                'billing_kind' => $trip['billing_kind'] ?? null,
                'last_seen_sec' => $locAt > 0 ? max(0, $now - $locAt) : null,
            ];
        }

        return $markers;
    }

    /**
     * @param  list<array<string, mixed>>  $markers
     * @return array{total:int, available:int, to_pickup:int, on_trip:int}
     */
    public static function counts(array $markers): array
    {
        $c = ['total' => count($markers), self::STATUS_AVAILABLE => 0, self::STATUS_TO_PICKUP => 0, self::STATUS_ON_TRIP => 0];
        foreach ($markers as $m) {
            $s = (string) ($m['status'] ?? self::STATUS_AVAILABLE);
            if (isset($c[$s])) {
                $c[$s]++;
            }
        }

        return $c;
    }
}
