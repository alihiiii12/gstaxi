<?php

namespace App\Services;

use App\Models\Driver;
use App\Models\RequestModel;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Redis;

class ImmediatePendingForDriver
{
    /** دقائق — طلبات حديثة يُعاد فيها فحص المسافة الحية. */
    public const FRESH_MINUTES = 3;

    /**
     * @return Collection<int, RequestModel>
     */
    public static function queryForDriver(Driver $driver): Collection
    {
        $items = RequestModel::query()
            ->where('type', RequestModel::TYPE_IMMEDIATE)
            ->where('status', RequestModel::STATUS_PENDING)
            ->where('created_at', '>=', now()->subMinutes(45))
            ->with(['user', 'startLocation', 'destLocation', 'carType'])
            ->orderByDesc('created_at')
            ->limit(40)
            ->get();

        return $items->filter(fn (RequestModel $row) => self::driverCanSee($driver, $row))->values();
    }

    public static function driverCanSee(Driver $driver, RequestModel $row): bool
    {
        if ((int) $row->carTypeId !== (int) $driver->transTypeId) {
            return false;
        }

        if ($row->driverId !== null && (int) $row->driverId !== (int) $driver->id) {
            return false;
        }

        if (! DriverNearbyService::isDriverOnline((int) $driver->id)) {
            return false;
        }

        if (! DriverSubscriptionService::isVisibleToPassengers($driver)) {
            return false;
        }

        $key = 'request:'.$row->id.':eligible';

        try {
            if (Redis::exists($key) && Redis::sismember($key, (string) $driver->id)) {
                return true;
            }
        } catch (\Throwable $e) {
        }

        // لم يُدرج عند الإنشاء (تأخر الموقع): فحص مسافة حية للطلبات الحديثة — نطاق العرض 3 كم.
        if (! self::isFreshRequest($row)) {
            return false;
        }

        $start = $row->startLocation;
        if (! $start) {
            return false;
        }

        return DriverNearbyService::isDriverNearPoint(
            (int) $driver->id,
            (float) $start->latitude,
            (float) $start->longitude,
            DriverNearbyService::maxDisplayRadiusKm()
        );
    }

    public static function isFreshRequest(RequestModel $row): bool
    {
        return $row->created_at && $row->created_at->gte(now()->subMinutes(self::FRESH_MINUTES));
    }

    /**
     * @return array<string, mixed>
     */
    public static function toDriverPayload(Driver $driver, RequestModel $row): array
    {
        $data = $row->toArray();
        $start = $row->startLocation;
        if ($start) {
            $km = DriverNearbyService::distanceKmToPoint(
                (int) $driver->id,
                (float) $start->latitude,
                (float) $start->longitude
            );
            if ($km !== null) {
                $data['distance_from_pickup_km'] = round($km, 2);
            }
        }

        return $data;
    }
}

