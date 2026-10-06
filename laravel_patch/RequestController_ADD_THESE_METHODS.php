<?php

/**
 * انسخ الدوال التالية داخل class RequestController (ولا تنفّذ هذا الملف).
 * تأكد من الاستيرادات في أعلى المتحكم:
 *
 * use App\Events\CustomerPickedDriverEvent;
 * use App\Models\RequestDriverOffer;
 * use Illuminate\Support\Facades\Redis;
 */

// --- استبدل acceptBooking بالكامل بالنسخة في ملف acceptBooking_REPLACEMENT.php ---

// --- استبدل getPendingImmediate بالنسخة في ملف getPendingImmediate_REPLACEMENT.php ---

// --- أضف cancelByCustomer تنظيف Redis + العروض (انظر MERGE_REQUEST_CONTROLLER.md) ---

public function immediateStatus(\Illuminate\Http\Request $request, $requestId)
{
    $user = $request->user();
    if (! $user || $user->roll !== 'Customer') {
        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
    }

    $req = \App\Models\RequestModel::with(['startLocation', 'destLocation', 'carType', 'driverOffers.driver.user'])
        ->find($requestId);

    if (! $req || (int) $req->userId !== (int) $user->id) {
        return response()->json(['success' => false, 'message' => 'Request not found'], 404);
    }

    if ($req->type !== \App\Models\RequestModel::TYPE_IMMEDIATE) {
        return response()->json(['success' => false, 'message' => 'Not an immediate request'], 400);
    }

    $eligibleKey = 'request:'.$req->id.':eligible';
    $eligibleDrivers = [];
    if (Redis::exists($eligibleKey)) {
        $ids = Redis::smembers($eligibleKey) ?: [];
        foreach ($ids as $sid) {
            $did = (int) $sid;
            if ($did <= 0) {
                continue;
            }
            $d = \App\Models\Driver::with('user')->find($did);
            if (! $d) {
                continue;
            }
            $km = $this->distanceKmToPickup($req, $did);
            $eligibleDrivers[] = $this->driverPayloadForCustomer($d, $km);
        }
    }

    usort($eligibleDrivers, fn ($a, $b) => ($a['distance_from_pickup_km'] ?? 9999) <=> ($b['distance_from_pickup_km'] ?? 9999));

    $offers = [];
    foreach ($req->driverOffers as $offer) {
        $d = $offer->driver;
        if (! $d) {
            continue;
        }
        $d->loadMissing('user');
        $km = $this->distanceKmToPickup($req, (int) $d->id);
        $row = $this->driverPayloadForCustomer($d, $km);
        $row['offered_at'] = $offer->created_at?->toIso8601String();
        $offers[] = $row;
    }

    return response()->json([
        'success' => true,
        'data' => [
            'request' => $req,
            'eligible_drivers' => $eligibleDrivers,
            'offers' => $offers,
        ],
    ]);
}

public function selectDriver(\Illuminate\Http\Request $request, $requestId)
{
    $user = $request->user();
    if (! $user || $user->roll !== 'Customer') {
        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
    }

    $v = $request->validate([
        'driverId' => 'required|integer',
    ]);

    $req = \App\Models\RequestModel::find($requestId);
    if (! $req || (int) $req->userId !== (int) $user->id) {
        return response()->json(['success' => false, 'message' => 'Request not found'], 404);
    }

    if ($req->type !== \App\Models\RequestModel::TYPE_IMMEDIATE || $req->status !== \App\Models\RequestModel::STATUS_PENDING) {
        return response()->json([
            'success' => false,
            'message' => 'Cannot select driver for this request state',
        ], 400);
    }

    $driverId = (int) $v['driverId'];

    $offer = RequestDriverOffer::where('request_id', $req->id)->where('driver_id', $driverId)->first();
    if (! $offer) {
        return response()->json([
            'success' => false,
            'message' => 'Driver did not accept this trip yet',
        ], 422);
    }

    $driver = \App\Models\Driver::find($driverId);
    if (! $driver) {
        return response()->json(['success' => false, 'message' => 'Driver not found'], 404);
    }

    \Illuminate\Support\Facades\DB::beginTransaction();
    try {
        $req->driverId = $driverId;
        $req->status = \App\Models\RequestModel::STATUS_RESERVED;
        $req->save();

        \App\Models\RequestHistory::create([
            'requestId' => $req->id,
            'driverId' => $driverId,
            'finalCost' => $req->predectedCost ?? 0,
            'descountId' => $request->discountId ?? null,
        ]);

        \Illuminate\Support\Facades\DB::commit();
    } catch (\Exception $e) {
        \Illuminate\Support\Facades\DB::rollBack();

        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], 500);
    }

    try {
        Redis::del('request:'.$req->id.':eligible');
    } catch (\Throwable $e) {
    }

    RequestDriverOffer::where('request_id', $req->id)->delete();

    broadcast(new CustomerPickedDriverEvent($driverId, $req->id));

    return response()->json([
        'success' => true,
        'data' => $req->fresh(['startLocation', 'destLocation']),
        'message' => 'تم اختيار السائق',
    ]);
}

private function coordsFromRedisDriver(int $driverId): ?array
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

private function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
{
    $earth = 6371.0;
    $dLat = deg2rad($lat2 - $lat1);
    $dLng = deg2rad($lng2 - $lng1);
    $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

    return $earth * (2 * atan2(sqrt($a), sqrt(1 - $a)));
}

private function distanceKmToPickup(\App\Models\RequestModel $req, int $driverId): ?float
{
    $start = $req->startLocation;
    if (! $start) {
        return null;
    }
    $c = $this->coordsFromRedisDriver($driverId);
    if (! $c) {
        return null;
    }

    return round($this->haversineKm((float) $start->latitude, (float) $start->longitude, $c['lat'], $c['lng']), 2);
}

private function driverPayloadForCustomer(\App\Models\Driver $driver, ?float $km): array
{
    $user = $driver->user;
    $name = $user ? trim(($user->firstName ?? '').' '.($user->lastName ?? '')) : '';

    return [
        'driverId' => $driver->id,
        'name' => $name !== '' ? $name : ('سائق #'.$driver->id),
        'number' => $user->number ?? null,
        'carNumber' => $driver->carNumber,
        'distance_from_pickup_km' => $km,
    ];
}
