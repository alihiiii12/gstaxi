<?php

namespace App\Services;

use App\Models\CarType;
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
            ->where('status', RequestModel::STATUS_PENDING)
            ->where(function ($q) {
                $q->where(function ($q2) {
                    $q2->where('type', RequestModel::TYPE_IMMEDIATE)
                        ->where('created_at', '>=', now()->subMinutes(45));
                })->orWhere(function ($q2) {
                    $q2->where('type', RequestModel::TYPE_SCHEDULE)
                        ->whereNotNull('requestDate')
                        ->where('requestDate', '>', now())
                        ->where('created_at', '>=', now()->subDays(14));
                });
            })
            ->with(['user', 'startLocation', 'destLocation', 'carType'])
            ->orderByDesc('created_at')
            ->limit(50)
            ->get();

        return $items->filter(fn (RequestModel $row) => self::driverCanSee($driver, $row))->values();
    }

    public static function driverCanSee(Driver $driver, RequestModel $row): bool
    {
        if (! CarType::driverServesRequestType((int) $driver->transTypeId, (int) $row->carTypeId)) {
            return false;
        }

        if ($row->driverId !== null && (int) $row->driverId !== (int) $driver->id) {
            return false;
        }

        if ($row->driverId === null && ImmediateDriverNotifier::driverIgnored((int) $row->id, (int) $driver->id)) {
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

        // حجز مسبق: لا يُشترط القرب الجغرافي — يكفي أونلاين + نفس الفئة.
        if ($row->type === RequestModel::TYPE_SCHEDULE) {
            // إن وُجدت قائمة eligible ولم يكن ضمنها → لا يظهر.
            try {
                if (Redis::exists($key)) {
                    return false;
                }
            } catch (\Throwable $e) {
            }

            return true;
        }

        // طلب فوري: لم يُدرج عند الإنشاء — فحص مسافة حية للطلبات الحديثة فقط.
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
            DriverNearbyService::receiveRadiusKmForDriver($driver)
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
        $data['cross_category_note'] = CarType::crossCategoryNote(
            (int) $row->carTypeId,
            (int) $driver->transTypeId
        );

        return self::hidePassengerContact($data);
    }

    /** رقم الراكب لا يُكشف للسائق قبل قبوله الطلب. */
    public static function hidePassengerContact(array $row): array
    {
        if (($row['status'] ?? null) !== RequestModel::STATUS_PENDING) {
            return $row;
        }
        if (isset($row['user']) && is_array($row['user'])) {
            unset($row['user']['number'], $row['user']['phone'], $row['user']['email']);
        }
        unset($row['guest_phone']);

        return $row;
    }
}
