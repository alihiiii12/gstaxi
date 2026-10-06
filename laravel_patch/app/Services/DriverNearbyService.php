<?php



namespace App\Services;



use App\Events\NewRequestEvent;

use App\Models\Driver;

use App\Models\RequestModel;

use Illuminate\Support\Facades\Log;

use Illuminate\Support\Facades\Redis;



/**

 * سائقون قريبون + نشطون فقط — نطاق إشعار (1 كم) منفصل عن نطاق العرض (3 كم).

 */

class DriverNearbyService

{

    /** أقصى مسافة لإرسال/إشعار الطلب الفوري (كم). */

    public const DEFAULT_NOTIFY_RADIUS_KM = 1;



    /** أقصى مسافة لعرض السائقين/الطلبات في القوائم (كم). */

    public const DEFAULT_DISPLAY_RADIUS_KM = 3;



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



    public static function driverMatchesRequest(Driver $driver, int $carTypeId): bool

    {

        return (int) $driver->transTypeId === $carTypeId

            && DriverSubscriptionService::isVisibleToPassengers($driver);

    }



    public static function attachDriverToFreshPendingRequests(Driver $driver, float $lng, float $lat): void

    {

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

            ->where('type', RequestModel::TYPE_IMMEDIATE)

            ->where('status', RequestModel::STATUS_PENDING)

            ->whereNull('driverId')

            ->where('carTypeId', $driver->transTypeId)

            ->where('created_at', '>=', now()->subMinutes(ImmediatePendingForDriver::FRESH_MINUTES))

            ->with('startLocation')

            ->orderByDesc('created_at')

            ->limit(15)

            ->get();



        foreach ($requests as $req) {

            $start = $req->startLocation;

            if (! $start) {

                continue;

            }

            $pickLat = (float) $start->latitude;

            $pickLng = (float) $start->longitude;

            if (! self::isDriverNearPoint((int) $driver->id, $pickLat, $pickLng, self::maxNotifyRadiusKm())) {

                continue;

            }



            $key = 'request:'.$req->id.':eligible';

            try {

                $added = Redis::sadd($key, (string) $driver->id);

                if ($added === 1) {

                    Redis::expire($key, 3600);

                    broadcast(new NewRequestEvent((int) $driver->id, $req->id));

                    DriverPollCacheService::bust();

                }

            } catch (\Throwable $e) {

                Log::debug('attachDriverToFreshPendingRequests: '.$e->getMessage());

            }

        }

    }



    /** @return array<int, int> */

    public static function busyDriverIds(): array

    {

        $statuses = [

            RequestModel::STATUS_PENDING,

            RequestModel::STATUS_RESERVED,

            RequestModel::STATUS_DRIVER_ARRIVED,

            RequestModel::STATUS_AWAITING_DESTINATION,

            RequestModel::STATUS_RUNNING,

        ];



        return RequestModel::query()

            ->whereNotNull('driverId')

            ->whereIn('status', $statuses)

            ->pluck('driverId')

            ->map(fn ($id) => (int) $id)

            ->filter(fn ($id) => $id > 0)

            ->unique()

            ->values()

            ->all();

    }

}


