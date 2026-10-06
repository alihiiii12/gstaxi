<?php

namespace App\Services;

use App\Events\NewRequestEvent;
use App\Models\CarType;
use App\Models\Driver;
use App\Models\Location;
use App\Models\RequestModel;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * إنشاء طلب فوري من لوحة الإدارة وإرساله لسائق محدد (قبول/رفض كطلب عادي).
 */
class AdminDispatchTripService
{
    /**
     * @param  array<string, mixed>  $input
     * @return array{request: RequestModel, customer: User, driver: Driver, created_customer: bool, fare: float}
     */
    public function dispatch(array $input): array
    {
        $driverId = (int) ($input['driver_id'] ?? $input['driverId'] ?? 0);
        if ($driverId <= 0) {
            throw new \InvalidArgumentException('يجب اختيار السائق');
        }

        $driver = Driver::with(['user', 'transType'])->find($driverId);
        if (! $driver) {
            throw new \InvalidArgumentException('السائق غير موجود');
        }

        if (! DriverNearbyService::isDriverOnline($driverId)) {
            throw new \InvalidArgumentException('السائق غير متصل حالياً — افتح تطبيق السائق وفعّل «متصل»');
        }

        if ($this->isDriverBusy($driverId)) {
            throw new \InvalidArgumentException('السائق مشغول برحلة أو طلب معلّق');
        }

        $carTypeId = (int) ($input['car_type_id'] ?? $input['carTypeId'] ?? 0);
        if ($carTypeId <= 0) {
            $carTypeId = (int) ($driver->transTypeId ?? 0);
        }
        if ($carTypeId <= 0) {
            throw new \InvalidArgumentException('لا تتوفر فئة سيارة للسائق');
        }
        if ((int) $driver->transTypeId !== $carTypeId) {
            throw new \InvalidArgumentException('فئة الطلب لا تطابق فئة مركبة السائق');
        }

        $carType = CarType::find($carTypeId);
        if (! $carType) {
            throw new \InvalidArgumentException('فئة السيارة غير موجودة');
        }

        $startLat = (float) ($input['start_lat'] ?? $input['startLocationLatitude'] ?? 0);
        $startLng = (float) ($input['start_lng'] ?? $input['startLocationLongitude'] ?? 0);
        $destLat = (float) ($input['dest_lat'] ?? $input['destLocationLatitude'] ?? 0);
        $destLng = (float) ($input['dest_lng'] ?? $input['destLocationLongitude'] ?? 0);
        if (! $this->validCoord($startLat, $startLng) || ! $this->validCoord($destLat, $destLng)) {
            throw new \InvalidArgumentException('إحداثيات الانطلاق والوجهة مطلوبة وصحيحة');
        }

        $startName = trim((string) ($input['start_name'] ?? $input['startLocationName'] ?? 'موقع العميل'));
        $destName = trim((string) ($input['dest_name'] ?? $input['destLocationName'] ?? 'الوجهة'));
        $locationDesc = trim((string) ($input['location_desc'] ?? $input['locationDesc'] ?? ''));
        if ($locationDesc === '') {
            $locationDesc = 'طلب من لوحة الإدارة';
        }

        [$customer, $createdCustomer] = $this->resolveCustomer($input);

        $km = (float) ($input['estimated_trip_km'] ?? $input['estimatedTripKm'] ?? 0);
        if ($km <= 0) {
            $km = TripTraceService::haversineKm($startLat, $startLng, $destLat, $destLng);
        }
        $minutesRaw = $input['estimated_duration_minutes'] ?? $input['estimatedDurationMinutes'] ?? null;
        $minutes = is_numeric($minutesRaw) && (float) $minutesRaw > 0
            ? round((float) $minutesRaw, 2)
            : round(($km / 25.0) * 60.0, 2);

        $fareOverride = $input['predected_cost'] ?? $input['predectedCost'] ?? null;
        $fare = is_numeric($fareOverride) && (float) $fareOverride > 0
            ? round((float) $fareOverride, 2)
            : $this->computeAppTripFare($carType, $km, $minutes);

        $result = DB::transaction(function () use (
            $customer,
            $driver,
            $carTypeId,
            $startLat,
            $startLng,
            $destLat,
            $destLng,
            $startName,
            $destName,
            $locationDesc,
            $km,
            $minutes,
            $fare
        ) {
            $start = Location::create([
                'latitude' => $startLat,
                'longitude' => $startLng,
                'name' => $startName !== '' ? $startName : 'موقع العميل',
                'description' => $locationDesc,
                'type' => Location::TYPE_PICKUP,
            ]);
            $dest = Location::create([
                'latitude' => $destLat,
                'longitude' => $destLng,
                'name' => $destName !== '' ? $destName : 'الوجهة',
                'description' => null,
                'type' => Location::TYPE_DROPOFF,
            ]);

            $payload = [
                'userId' => $customer->id,
                'carTypeId' => $carTypeId,
                'service_area_id' => null,
                'type' => RequestModel::TYPE_IMMEDIATE,
                'status' => RequestModel::STATUS_PENDING,
                'startLocationId' => $start->id,
                'destLocationId' => $dest->id,
                'requestDate' => now(),
                'locationDesc' => $locationDesc,
                'driverId' => $driver->id,
                'predectedCost' => $fare,
                'estimated_duration_minutes' => $minutes,
                'billing_kind' => RequestModel::BILLING_KIND_APP_REQUEST,
                'is_app_request' => true,
            ];
            if (Schema::hasColumn('requests', 'estimated_distance_km')) {
                $payload['estimated_distance_km'] = round($km, 3);
            }

            $req = RequestModel::create($payload);

            return $req->fresh(['startLocation', 'destLocation', 'user', 'carType']);
        });

        // إشعار السائق كطلب فوري موجّه (Redis + بث + FCM)
        try {
            $key = 'request:'.$result->id.':eligible';
            Redis::del($key);
            Redis::sadd($key, [(string) $driver->id]);
            Redis::expire($key, 3600);
        } catch (\Throwable $e) {
        }

        try {
            broadcast(new NewRequestEvent((int) $driver->id, (int) $result->id));
        } catch (\Throwable $e) {
        }

        try {
            app(ImmediateDriverNotifier::class)->notifyDriverOfImmediate($driver, (int) $result->id);
        } catch (\Throwable $e) {
        }

        try {
            DriverPollCacheService::bust();
        } catch (\Throwable $e) {
        }

        return [
            'request' => $result,
            'customer' => $customer,
            'driver' => $driver,
            'created_customer' => $createdCustomer,
            'fare' => $fare,
        ];
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array{0: User, 1: bool}
     */
    private function resolveCustomer(array $input): array
    {
        $customerId = (int) ($input['customer_id'] ?? $input['customerId'] ?? 0);
        if ($customerId > 0) {
            $u = User::query()->where('roll', 'Customer')->find($customerId);
            if (! $u) {
                throw new \InvalidArgumentException('الزبون غير موجود');
            }

            return [$u, false];
        }

        $phone = $this->normalizePhone((string) ($input['customer_phone'] ?? $input['phone'] ?? ''));
        $first = trim((string) ($input['customer_first_name'] ?? $input['firstName'] ?? $input['customer_name'] ?? ''));
        $last = trim((string) ($input['customer_last_name'] ?? $input['lastName'] ?? ''));

        if ($phone === '') {
            // بدون زبون مسجّل وبدون هاتف: حساب ضيف إداري موحّد لكل طلبات الأدمن بدون رقم
            $phone = 'admin-guest';
            if ($first === '') {
                $first = 'زبون';
            }
            if ($last === '') {
                $last = 'إدارة';
            }
        }

        $existing = User::query()
            ->where('roll', 'Customer')
            ->where('number', $phone)
            ->first();
        if ($existing) {
            if ($first !== '' || $last !== '') {
                $dirty = false;
                if ($first !== '' && trim((string) $existing->firstName) === '') {
                    $existing->firstName = $first;
                    $dirty = true;
                }
                if ($last !== '' && trim((string) $existing->lastName) === '') {
                    $existing->lastName = $last;
                    $dirty = true;
                }
                if ($dirty) {
                    $existing->save();
                }
            }

            return [$existing, false];
        }

        if ($first === '') {
            $first = 'زبون';
        }
        if ($last === '') {
            $last = $phone === 'admin-guest' ? 'إدارة' : 'جديد';
        }

        $user = User::create([
            'number' => $phone === 'admin-guest' ? ('admin-guest-'.Str::lower(Str::random(8))) : $phone,
            'firstName' => $first,
            'lastName' => $last,
            'password' => Str::random(24),
            'roll' => 'Customer',
            'phone_verified_at' => null,
        ]);

        return [$user, true];
    }

    private function normalizePhone(string $raw): string
    {
        $p = trim($raw);
        $p = preg_replace('/\s+/', '', $p) ?? $p;
        if ($p === '' || strcasecmp($p, 'admin-guest') === 0) {
            return '';
        }

        return $p;
    }

    private function validCoord(float $lat, float $lng): bool
    {
        return $lat >= -90 && $lat <= 90 && $lng >= -180 && $lng <= 180
            && ! ($lat == 0.0 && $lng == 0.0);
    }

    private function computeAppTripFare(CarType $t, float $km, float $minutes): float
    {
        $openP = (float) ($t->openPrice ?? 0);
        $kmP = (float) ($t->KMPrice ?? 0);
        $timeP = (float) ($t->timePrice ?? 0);

        return round($openP + $kmP * $km + $timeP * $minutes, 2);
    }

    private function isDriverBusy(int $driverId): bool
    {
        $statuses = [
            RequestModel::STATUS_PENDING,
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
            RequestModel::STATUS_RUNNING,
        ];

        return RequestModel::query()
            ->where('driverId', $driverId)
            ->whereIn('status', $statuses)
            ->exists();
    }
}
