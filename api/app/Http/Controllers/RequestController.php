<?php

namespace App\Http\Controllers;

use App\Events\CustomerPickedDriverEvent;
use App\Events\NewRequestEvent;
use App\Events\RequestCancelledByCustomerEvent;
use App\Models\RequestDriverOffer;
use App\Models\RequestModel;
use App\Models\RequestHistory;
use App\Models\Driver;
use App\Models\User;
use App\Models\Discount;
use App\Models\ServiceArea;
use App\Services\PricingZoneService;
use App\Models\UsedDiscount;
use App\Http\Requests\StoreRequestRequest;
use App\Models\CarType;
use App\Models\Location;
use App\Models\CustomerNotification;
use App\Models\DriverNotification;
use App\Models\AppSetting;
use App\Services\CustomerPresenceService;
use App\Services\DriverNearbyService;
use App\Services\DriverPollCacheService;
use App\Services\DriverSubscriptionService;
use App\Services\DriverWalletService;
use App\Services\CustomerWalletService;
use App\Services\FcmPushService;
use App\Services\ImmediatePendingForDriver;
use App\Services\TripTraceService;
use Illuminate\Http\Request as HttpRequest;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Redis;

class RequestController extends Controller
{
    private function isDriverOnline(int $driverId): bool
    {
        try {
            return Redis::exists('driver:'.$driverId.':online') === 1;
        } catch (\Throwable $e) {
            // عند تعذّر التحقق لا نُظهر السائق كأونلاين (أمان القائمة للراكب).
            return false;
        }
    }

    /** @return array<int, int> */
    private function busyDriverIds(): array
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

    private function isDriverBusy(int $driverId, ?int $exceptRequestId = null): bool
    {
        $q = RequestModel::query()
            ->where('driverId', $driverId)
            ->occupyingDriver();
        if ($exceptRequestId !== null) {
            $q->where('id', '!=', $exceptRequestId);
        }

        return $q->exists();
    }

    /** دقائق يجب أن تفصل بين حجزين مسبقين لنفس السائق. */
    private const SCHED_MIN_GAP_MINUTES = 60;

    /**
     * قبول حجز مسبق: يتعارض فقط مع حجز مسبق آخر قريب زمنياً،
     * أو مع رحلة جارية إن كانت نافذة الانطلاق لهذا الحجز مفتوحة أصلاً.
     */
    private function scheduledAcceptConflict(int $driverId, RequestModel $req): ?string
    {
        if ($req->requestDate) {
            $near = RequestModel::query()
                ->where('driverId', $driverId)
                ->where('id', '!=', $req->id)
                ->where('type', RequestModel::TYPE_SCHEDULE)
                ->where('status', RequestModel::STATUS_RESERVED)
                ->whereBetween('requestDate', [
                    $req->requestDate->copy()->subMinutes(self::SCHED_MIN_GAP_MINUTES),
                    $req->requestDate->copy()->addMinutes(self::SCHED_MIN_GAP_MINUTES),
                ])
                ->exists();
            if ($near) {
                return 'لديك حجز مسبق آخر قريب من هذا الموعد (أقل من ساعة)';
            }
        }

        $windowOpen = ! $req->requestDate
            || now()->gte($req->requestDate->copy()->subMinutes(RequestModel::SCHED_GO_WINDOW_MINUTES));
        if ($windowOpen && $this->isDriverBusy($driverId, (int) $req->id)) {
            return 'لديك رحلة نشطة أخرى — أنهِها قبل قبول هذا الحجز';
        }

        return null;
    }

    private function releaseCouponForRequest(int $requestId): void
    {
        try {
            UsedDiscount::releaseForRequest($requestId);
        } catch (\Throwable $e) {
        }
    }

    private function inferTripMinutesFromKm(float $km): float
    {
        if ($km <= 0) {
            return 0.0;
        }

        return round(($km / 25.0) * 60.0, 2);
    }

    private function normalizeEstimatedDurationMinutesInput($raw): ?float
    {
        if ($raw === null || $raw === '') {
            return null;
        }
        $v = (float) $raw;

        return $v > 0 ? round($v, 2) : null;
    }

    /**
     * @param  float|null  $clientMinutes  من تطبيق الزبون (مسار تقريبي)
     * @param  float|null  $storedMinutes  من عمود الطلب
     */
    private function resolveTripMinutesForEstimate(?float $clientMinutes, ?float $storedMinutes, float $kmTrip): float
    {
        if ($clientMinutes !== null && $clientMinutes > 0) {
            return round($clientMinutes, 2);
        }
        if ($storedMinutes !== null && (float) $storedMinutes > 0) {
            return round((float) $storedMinutes, 2);
        }

        return $this->inferTripMinutesFromKm($kmTrip);
    }

    /** تسعيرة طلب التطبيق: افتتاحي + كيلومتر + دقيقة. */
    private function computeAppTripFare(?CarType $t, float $km, float $minutes): float
    {
        if (! $t) {
            return 0.0;
        }
        $openP = (float) ($t->openPrice ?? 0);
        $kmP = (float) ($t->KMPrice ?? 0);
        $timeP = (float) ($t->timePrice ?? 0);

        return round($openP + $kmP * $km + $timeP * $minutes, 2);
    }

    private function markTripRunningStarted(RequestModel $req, ?int $driverId = null): void
    {
        $did = $driverId ?? (int) ($req->driverId ?? 0);
        if ($did > 0) {
            TripTraceService::markTripStarted($req, $did);

            return;
        }
        if ($req->trip_started_at === null) {
            $req->trip_started_at = now();
        }
    }

    /**
     * @param  Location|null  $startLocation
     * @param  Location|null  $destLocation
     */
    private function refreshAppTripPredictedCost(RequestModel $req, $startLocation, $destLocation, ?float $clientMinutesOverride): void
    {
        if (! $startLocation || ! $destLocation) {
            return;
        }
        if ((float) ($req->predectedCost ?? 0) > 0) {
            return;
        }
        $carType = CarType::find($req->carTypeId);
        $kmTrip = $this->haversineKm(
            (float) $startLocation->latitude,
            (float) $startLocation->longitude,
            (float) $destLocation->latitude,
            (float) $destLocation->longitude
        );
        $minutes = $this->resolveTripMinutesForEstimate(
            $clientMinutesOverride,
            $req->estimated_duration_minutes !== null ? (float) $req->estimated_duration_minutes : null,
            $kmTrip
        );
        $req->estimated_duration_minutes = $minutes;
        if (\Illuminate\Support\Facades\Schema::hasColumn('requests', 'estimated_distance_km') && $req->estimated_distance_km === null) {
            $req->estimated_distance_km = round($kmTrip, 3);
        }
        $req->predectedCost = PricingZoneService::apply(
            $this->computeAppTripFare($carType, $kmTrip, $minutes),
            (float) ($req->zone_multiplier ?? 1) ?: 1.0,
        );
        $req->save();
    }

    /**
     * @param  Location|null  $startLocation
     * @param  Location|null  $destLocation
     */
    private function refreshAppTripPredictedCostForDriver(RequestModel $req, Driver $driver, $startLocation, $destLocation, ?float $clientMinutesOverride): void
    {
        if (! $startLocation || ! $destLocation) {
            return;
        }
        if ((float) ($req->predectedCost ?? 0) > 0) {
            return;
        }
        $t = ($req->carTypeId ? CarType::find($req->carTypeId) : null) ?? $driver->transType;
        $kmTrip = $this->haversineKm(
            (float) $startLocation->latitude,
            (float) $startLocation->longitude,
            (float) $destLocation->latitude,
            (float) $destLocation->longitude
        );
        $minutes = $this->resolveTripMinutesForEstimate(
            $clientMinutesOverride,
            $req->estimated_duration_minutes !== null ? (float) $req->estimated_duration_minutes : null,
            $kmTrip
        );
        $req->estimated_duration_minutes = $minutes;
        if (\Illuminate\Support\Facades\Schema::hasColumn('requests', 'estimated_distance_km') && $req->estimated_distance_km === null) {
            $req->estimated_distance_km = round($kmTrip, 3);
        }
        $req->predectedCost = PricingZoneService::apply(
            $this->computeAppTripFare($t, $kmTrip, $minutes),
            (float) ($req->zone_multiplier ?? 1) ?: 1.0,
        );
        $req->save();
    }

    /**
     * Create a new request (scheduled or immediate)
     */
    public function store(StoreRequestRequest $request)
    {
        //startLocationLongitude
        //startLocationLatitude
        $startLocation = Location::where('longitude', $request['startLocationLongitude'])
            ->where('latitude', $request['startLocationLatitude'])
            ->first();

        $destLng = $request->input('destLocationLongitude');
        $destLat = $request->input('destLocationLatitude');
        $destLocation = null;
        if ($destLng !== null && $destLat !== null) {
            $destLocation = Location::where('longitude', $destLng)
                ->where('latitude', $destLat)
                ->first();
        }

        $startName = trim((string) $request->input('startLocationName', ''));
        $destName = trim((string) $request->input('destLocationName', ''));
        $locationDesc = trim((string) $request->input('locationDesc', ''));
        if ($startName === '' && $locationDesc !== '') {
            $startName = $locationDesc;
        }

        if (! $startLocation) {
            $startLocation = Location::create([
                'longitude' => $request['startLocationLongitude'],
                'latitude' => $request['startLocationLatitude'],
                'name' => $startName !== '' ? $startName : null,
                'description' => $locationDesc !== '' ? $locationDesc : null,
                'type' => Location::TYPE_PICKUP,
            ]);
        } elseif ($startName !== '') {
            self::maybeUpdateLocationLabel($startLocation, $startName);
        }

        if ($destLng !== null && $destLat !== null && ! $destLocation) {
            $destLocation = Location::create([
                'longitude' => $destLng,
                'latitude' => $destLat,
                'name' => $destName !== '' ? $destName : null,
                'type' => Location::TYPE_DROPOFF,
            ]);
        } elseif ($destLocation && $destName !== '') {
            self::maybeUpdateLocationLabel($destLocation, $destName);
        }

        $requestDate = $request->type === RequestModel::TYPE_IMMEDIATE
            ? Carbon::now()->format('Y-m-d H:i:s')
            : $request->requestDate;

        // منطقة إدارية اختيارية فقط؛ الخدمة تغطي سوريا دون تقييد جغرافي للراكب.
        $rawArea = $request->input('serviceAreaId');
        $serviceAreaId = ($rawArea === null || $rawArea === '')
            ? null
            : (int) $rawArea;
        if ($serviceAreaId !== null) {
            $active = ServiceArea::query()->whereKey($serviceAreaId)->where('active', true)->exists();
            if (! $active) {
                return response()->json([
                    'success' => false,
                    'message' => 'منطقة الخدمة غير صالحة أو غير نشطة',
                ], 422);
            }
        }

        $targetDriverId = null;
        $rawT = $request->input('targetDriverId');
        // الحجز المسبق يقبل بثاً لكل السائقين القريبين (بدون targetDriverId) أو سائقاً محدداً.
        if ($rawT !== null && $rawT !== '') {
            $targetDriverId = (int) $rawT;
            $vd = Driver::with('transType')->find($targetDriverId);
            if (! $vd) {
                return response()->json([
                    'success' => false,
                    'message' => 'السائق غير موجود',
                ], 422);
            }
            if (! $this->isDriverOnline($targetDriverId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'السائق غير متصل حالياً — افتح تطبيق السائق وفعّل «متصل»',
                ], 422);
            }
            if (! CarType::driverServesRequestType((int) $vd->transTypeId, (int) $request['carTypeId'])) {
                return response()->json([
                    'success' => false,
                    'message' => 'نوع مركبة السائق لا يطابق نوع الطلب',
                ], 422);
            }
            if ($this->isDriverBusy($targetDriverId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'السائق مشغول برحلة أخرى',
                ], 422);
            }
        }

        if ($request->type === RequestModel::TYPE_SCHEDULE) {
            $hasOpenScheduled = RequestModel::query()
                ->where('userId', $request->user()->id)
                ->where('type', RequestModel::TYPE_SCHEDULE)
                ->where('status', RequestModel::STATUS_PENDING)
                ->exists();
            if ($hasOpenScheduled) {
                return response()->json([
                    'success' => false,
                    'message' => 'لديك حجز مسبق بانتظار قبول سائق. راجع «الحجوزات المسبقة» في الطلبات أو ألغِه قبل إنشاء حجز جديد.',
                ], 422);
            }
        }

        $discountCode = trim((string) $request->input('discountCode', ''));
        $discount = null;
        if ($discountCode !== '') {
            $discount = Discount::where('code', $discountCode)->first();
            if (! $discount) {
                return response()->json([
                    'success' => false,
                    'message' => 'Invalid discount code',
                    'code' => 'INVALID_CODE',
                ], 404);
            }
            if (! $discount->isActiveNow()) {
                return response()->json([
                    'success' => false,
                    'message' => 'انتهت صلاحية هذا الكوبون أو لم يبدأ بعد',
                    'code' => 'DISCOUNT_EXPIRED',
                ], 400);
            }
            if (! in_array($discount->type, [Discount::TYPE_PERCENTAGE, Discount::TYPE_FIXED], true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unsupported discount type',
                    'code' => 'UNSUPPORTED_TYPE',
                ], 400);
            }
            $phones = $discount->target_phones;
            if (is_array($phones) && count($phones) > 0) {
                $u = $request->user();
                if (! $u || ! in_array($u->number, $phones, true)) {
                    return response()->json([
                        'success' => false,
                        'message' => 'هذا الكوبون غير مخصص لرقم حسابك',
                        'code' => 'PHONE_NOT_ELIGIBLE',
                    ], 403);
                }
            }
            if ($limitMsg = $discount->usageLimitErrorFor((int) $request->user()->id)) {
                return response()->json([
                    'success' => false,
                    'message' => $limitMsg,
                    'code' => 'ALREADY_USED',
                ], 400);
            }
        }

        $estDurNorm = $this->normalizeEstimatedDurationMinutesInput($request->input('estimatedDurationMinutes'));

        $carTypeForStore = CarType::find($request['carTypeId']);
        $quotedInput = $request->input('customerQuotedFare') ?? $request->input('customer_quoted_fare');
        $predInput = $request->input('predectedCost') ?? $request->input('predected_cost');
        $predectedForStore = 0.0;
        if ($quotedInput !== null && is_numeric($quotedInput) && (float) $quotedInput > 0) {
            $predectedForStore = round((float) $quotedInput, 2);
        } elseif ($predInput !== null && is_numeric($predInput) && (float) $predInput > 0) {
            $predectedForStore = round((float) $predInput, 2);
        } elseif ($carTypeForStore && $destLocation) {
            $kmEst = (float) ($request->input('estimatedTripKm') ?? $request->input('estimated_trip_km') ?? 0);
            if ($kmEst <= 0) {
                // مجموع المقاطع عبر كل المحطات (الأخيرة = الوجهة).
                $chain = [[(float) $startLocation['latitude'], (float) $startLocation['longitude']]];
                $wpIn = $request->input('waypoints');
                if (is_array($wpIn)) {
                    foreach ($wpIn as $wp) {
                        $wLat = is_array($wp) ? ($wp['lat'] ?? $wp['latitude'] ?? null) : null;
                        $wLng = is_array($wp) ? ($wp['lng'] ?? $wp['longitude'] ?? null) : null;
                        if (is_numeric($wLat) && is_numeric($wLng)) {
                            $chain[] = [(float) $wLat, (float) $wLng];
                        }
                    }
                }
                $chain[] = [(float) $destLocation['latitude'], (float) $destLocation['longitude']];
                $kmEst = 0.0;
                for ($i = 1; $i < count($chain); $i++) {
                    $kmEst += $this->haversineKm($chain[$i - 1][0], $chain[$i - 1][1], $chain[$i][0], $chain[$i][1]);
                }
            }
            $predectedForStore = (float) ($this->computeAppTripFare($carTypeForStore, $kmEst, $estDurNorm) ?? 0);
        }

        $zoneQuote = PricingZoneService::quote(
            (float) $startLocation['latitude'],
            (float) $startLocation['longitude'],
            $destLocation ? (float) $destLocation['latitude'] : null,
            $destLocation ? (float) $destLocation['longitude'] : null,
        );
        if ($predectedForStore > 0) {
            // التطبيق الحديث يرسل السعر بعد ضربه بمعامل المنطقة؛ القديم يرسل السعر الأساسي.
            $clientApplied = filter_var($request->input('zone_multiplier_applied', false), FILTER_VALIDATE_BOOLEAN);
            $clientMult = (float) $request->input('zone_multiplier', 1);
            $base = ($clientApplied && $clientMult > 0) ? $predectedForStore / $clientMult : $predectedForStore;
            $predectedForStore = PricingZoneService::apply($base, $zoneQuote['multiplier']);
        }

        $createPayload = [
            'userId' => $request->user()->id,
            'carTypeId' => $request['carTypeId'],
            'service_area_id' => $serviceAreaId,
            'type' => $request['type'],
            'status' => RequestModel::STATUS_PENDING,
            'startLocationId' => $startLocation['id'],
            'destLocationId' => $destLocation ? $destLocation['id'] : null,
            'requestDate' => $requestDate,
            'locationDesc' => $request['locationDesc'],
            'predectedCost' => $predectedForStore > 0 ? $predectedForStore : $request['predectedCost'],
            'estimated_duration_minutes' => $estDurNorm,
            'discountId' => $discount ? $discount->id : null,
            'discountCode' => $discount ? $discount->code : null,
            'discountType' => $discount ? $discount->type : null,
            'discountValue' => $discount ? $discount->amount : null,
            'billing_kind' => RequestModel::BILLING_KIND_APP_REQUEST,
            'is_app_request' => true,
        ] + PricingZoneService::requestAttributes($zoneQuote);
        $waypointsIn = $request->input('waypoints');
        if (is_array($waypointsIn) && count($waypointsIn) > 0
            && \Illuminate\Support\Facades\Schema::hasColumn('requests', 'waypoints')) {
            $normalizedWaypoints = [];
            foreach ($waypointsIn as $wp) {
                if (! is_array($wp)) {
                    continue;
                }
                $lat = $wp['lat'] ?? $wp['latitude'] ?? null;
                $lng = $wp['lng'] ?? $wp['longitude'] ?? null;
                if (! is_numeric($lat) || ! is_numeric($lng)) {
                    continue;
                }
                $normalizedWaypoints[] = [
                    'lat' => (float) $lat,
                    'lng' => (float) $lng,
                    'name' => trim((string) ($wp['name'] ?? $wp['label'] ?? '')),
                ];
            }
            if (count($normalizedWaypoints) > 0) {
                $createPayload['waypoints'] = $normalizedWaypoints;
            }
        }
        $kmFromClient = (float) ($request->input('estimatedTripKm') ?? $request->input('estimated_trip_km') ?? 0);
        if ($kmFromClient <= 0 && isset($kmEst) && $kmEst > 0) {
            $kmFromClient = $kmEst;
        }
        if ($kmFromClient > 0 && \Illuminate\Support\Facades\Schema::hasColumn('requests', 'estimated_distance_km')) {
            $createPayload['estimated_distance_km'] = round($kmFromClient, 3);
        }

        // قفل صف الزبون يسلسل طلبات الإنشاء المتزامنة (ضغطتان/إعادة إرسال) — وإلا ينشأ طلبان
        // ويقبل كل سائق واحداً منهما فيظهر أن سائقين قبلا نفس الطلب.
        $superseded = [];
        try {
            $outcome = DB::transaction(function () use ($request, $createPayload, &$superseded) {
                User::whereKey($request->user()->id)->lockForUpdate()->first();

                $blocked = $this->openRequestConflictForCustomer((int) $request->user()->id, $createPayload, $superseded);
                if ($blocked !== null) {
                    return $blocked;
                }

                return RequestModel::create($createPayload);
            });
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        if ($outcome instanceof \Illuminate\Http\JsonResponse) {
            return $outcome;
        }
        if (is_array($outcome)) {
            /** @var RequestModel $dup */
            $dup = $outcome['duplicate'];

            return response()->json([
                'success' => true,
                'duplicate' => true,
                'data' => $dup->fresh(['discount', 'driver.user']),
                'channel' => 'trip.'.$dup->id,
                'message' => 'Request already exists',
                'dispatch' => ['mode' => 'duplicate'],
            ], 201);
        }
        $newRequest = $outcome;

        foreach ($superseded as $old) {
            $this->cleanupSupersededImmediateRequest($old);
        }

        try {
            CustomerPresenceService::touch(
                (int) $request->user()->id,
                (float) $request['startLocationLatitude'],
                (float) $request['startLocationLongitude'],
            );
        } catch (\Throwable $e) {
        }

        // lock coupon usage to this request immediately (one-time-per-user)
        if ($discount) {
            UsedDiscount::create([
                'requestId' => $newRequest->id,
                'userId' => $request->user()->id,
                'discountId' => $discount->id,
            ]);
        }

        // تقدير احتياطي فقط إن لم يُرسل الزبون تسعيرة جاهزة.
        if ($destLocation && (float) ($newRequest->predectedCost ?? 0) <= 0) {
            $this->refreshAppTripPredictedCost($newRequest, $startLocation, $destLocation, $estDurNorm);
        }

        // طلب فوري: إما إرسال لسائق محدد فقط، أو بث للمنطقة (بدون targetDriverId).
        $dispatchMeta = null;
        if ($request->type === RequestModel::TYPE_IMMEDIATE) {
            if ($targetDriverId !== null) {
                $driver = Driver::with('transType')->find($targetDriverId);
                $newRequest->driverId = $targetDriverId;
                $newRequest->save();
                if ($destLocation && (float) ($newRequest->predectedCost ?? 0) <= 0) {
                    $this->refreshAppTripPredictedCostForDriver($newRequest, $driver, $startLocation, $destLocation, $estDurNorm);
                }

                try {
                    Redis::del('request:'.$newRequest->id.':eligible');
                    Redis::sadd('request:'.$newRequest->id.':eligible', [(string) $targetDriverId]);
                    Redis::expire('request:'.$newRequest->id.':eligible', 3600);
                } catch (\Throwable $e) {
                }
                try {
                    RequestDriverOffer::where('request_id', $newRequest->id)->delete();
                } catch (\Throwable $e) {
                }
                try {
                    broadcast(new NewRequestEvent($targetDriverId, $newRequest->id));
                } catch (\Throwable $e) {
                }
                $dispatchMeta = [
                    'mode' => 'target_driver',
                    'target_driver_id' => $targetDriverId,
                    'notified' => 1,
                ];
            } else {
                $dispatchMeta = app(\App\Services\ImmediateDriverNotifier::class)->notify(
                    $newRequest,
                    (float) $request['startLocationLongitude'],
                    (float) $request['startLocationLatitude']
                );
                $dispatchMeta['mode'] = 'broadcast';
            }
            // إبطال الكاش قبل أي استطلاع لاحق — يمنع إرجاع قائمة قديمة فارغة.
            DriverPollCacheService::bust();
        } else {
            // حجز مسبق: بث للسائقين القريبين (رنة) — أو سائق محدد إن وُجد targetDriverId.
            if ($targetDriverId !== null) {
                $driver = Driver::with('transType')->find($targetDriverId);
                // لا نثبّت driverId قبل القبول — يبقى Pending حتى يقبل سائق.
                if ($destLocation && (float) ($newRequest->predectedCost ?? 0) <= 0 && $driver) {
                    $this->refreshAppTripPredictedCostForDriver(
                        $newRequest,
                        $driver,
                        $startLocation,
                        $destLocation,
                        $estDurNorm
                    );
                }
                if ($driver) {
                    app(\App\Services\ScheduledDriverNotifier::class)
                        ->notifySingleDriver($driver, $newRequest);
                    $when = $newRequest->requestDate
                        ? Carbon::parse($newRequest->requestDate)->format('Y-m-d H:i')
                        : '';
                    $this->createDriverNotification(
                        (int) $driver->userId,
                        'طلب حجز مسبق',
                        $when !== ''
                            ? "وصلك طلب حجز مسبق للموعد {$when}. اقبله من النافذة أو «الحجوزات المسبقة»."
                            : 'وصلك طلب حجز مسبق جديد.',
                        'sched_assigned',
                        (int) $newRequest->id
                    );
                    $dispatchMeta = [
                        'mode' => 'target_driver',
                        'target_driver_id' => $targetDriverId,
                        'notified' => 1,
                    ];
                }
            } else {
                $dispatchMeta = app(\App\Services\ScheduledDriverNotifier::class)->notify(
                    $newRequest,
                    (float) $request['startLocationLongitude'],
                    (float) $request['startLocationLatitude']
                );
                $dispatchMeta['mode'] = 'broadcast';
            }
            DriverPollCacheService::bust();
        }



        return response()->json([
            'success' => true,
            'data' => $newRequest->fresh(['discount', 'driver.user']),
            'channel' => 'trip.' . $newRequest['id'],
            'message' => 'Request created successfully',
            'dispatch' => $dispatchMeta,
        ], 201);
    }

    /** نفس الطلب يُعاد إرساله خلال هذه المدة (ضغطة مزدوجة/إعادة محاولة) يُعاد كما هو بدل إنشاء نسخة. */
    private const DUPLICATE_STORE_WINDOW_SECONDS = 120;

    /** رحلة فعّالة أقدم من هذا (لم تُحدَّث) تُعتبر عالقة ولا تمنع الزبون من طلب جديد. */
    private const STALE_ACTIVE_TRIP_HOURS = 4;

    /**
     * يُستدعى داخل معاملة بعد قفل صف الزبون.
     *
     * @param  array<int, RequestModel>  $superseded  طلبات فورية معلّقة أُلغيت لصالح الطلب الجديد
     * @return \Illuminate\Http\JsonResponse|array{duplicate: RequestModel}|null
     */
    private function openRequestConflictForCustomer(int $userId, array $payload, array &$superseded)
    {
        $type = $payload['type'] ?? null;

        $dup = RequestModel::query()
            ->where('userId', $userId)
            ->where('type', $type)
            ->where('is_app_request', true)
            ->where('startLocationId', $payload['startLocationId'])
            ->where('destLocationId', $payload['destLocationId'])
            ->where('carTypeId', $payload['carTypeId'])
            ->whereNotIn('status', [RequestModel::STATUS_FINISHED, RequestModel::STATUS_REMOVED])
            ->where('created_at', '>=', now()->subSeconds(self::DUPLICATE_STORE_WINDOW_SECONDS))
            ->when($type === RequestModel::TYPE_SCHEDULE, fn ($q) => $q->where('requestDate', $payload['requestDate']))
            ->latest('id')
            ->first();
        if ($dup) {
            return ['duplicate' => $dup];
        }

        if ($type === RequestModel::TYPE_SCHEDULE) {
            $hasOpenScheduled = RequestModel::query()
                ->where('userId', $userId)
                ->where('type', RequestModel::TYPE_SCHEDULE)
                ->where('status', RequestModel::STATUS_PENDING)
                ->exists();

            return $hasOpenScheduled
                ? response()->json([
                    'success' => false,
                    'message' => 'لديك حجز مسبق بانتظار قبول سائق. راجع «الحجوزات المسبقة» في الطلبات أو ألغِه قبل إنشاء حجز جديد.',
                ], 422)
                : null;
        }

        $active = RequestModel::query()
            ->where('userId', $userId)
            ->where('type', RequestModel::TYPE_IMMEDIATE)
            ->where('is_app_request', true)
            ->whereIn('status', [
                RequestModel::STATUS_RESERVED,
                RequestModel::STATUS_DRIVER_ARRIVED,
                RequestModel::STATUS_AWAITING_DESTINATION,
                RequestModel::STATUS_RUNNING,
            ])
            ->where('updated_at', '>=', now()->subHours(self::STALE_ACTIVE_TRIP_HOURS))
            ->latest('id')
            ->first();
        if ($active) {
            return response()->json([
                'success' => false,
                'code' => 'ACTIVE_TRIP_EXISTS',
                'message' => 'لديك رحلة قائمة مع سائق — أنهِها أو ألغِها قبل طلب سيارة جديدة',
                'data' => ['request_id' => (int) $active->id],
            ], 409);
        }

        $pending = RequestModel::query()
            ->where('userId', $userId)
            ->where('type', RequestModel::TYPE_IMMEDIATE)
            ->where('is_app_request', true)
            ->where('status', RequestModel::STATUS_PENDING)
            ->lockForUpdate()
            ->get();
        foreach ($pending as $old) {
            $old->status = RequestModel::STATUS_REMOVED;
            $old->cancel_reason = 'superseded_by_new_request';
            $old->save();
            $superseded[] = $old;
        }

        return null;
    }

    private function cleanupSupersededImmediateRequest(RequestModel $old): void
    {
        try {
            Redis::del('request:'.$old->id.':eligible');
        } catch (\Throwable $e) {
        }
        try {
            RequestDriverOffer::where('request_id', $old->id)->delete();
        } catch (\Throwable $e) {
        }
        $this->releaseCouponForRequest((int) $old->id);
        if ($old->driverId) {
            try {
                broadcast(new RequestCancelledByCustomerEvent((int) $old->driverId, (int) $old->id));
            } catch (\Throwable $e) {
            }
        }
    }

    /**
     * قائمة سائقين أونلاين قرب نقطة الانطلاق قبل إنشاء الطلب (عرض للراكب).
     */
    public function nearbyDriversForBooking(HttpRequest $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'pickupLatitude' => 'required|numeric|between:-90,90',
            'pickupLongitude' => 'required|numeric|between:-180,180',
            'carTypeId' => 'required|integer|exists:carTypes,id',
            'destLatitude' => 'nullable|numeric|between:-90,90',
            'destLongitude' => 'nullable|numeric|between:-180,180',
            'estimatedDurationMinutes' => 'nullable|numeric|min:0|max:10080',
            'estimatedTripKm' => 'nullable|numeric|min:0|max:2000',
        ]);

        $pickLat = (float) $v['pickupLatitude'];
        $pickLng = (float) $v['pickupLongitude'];
        $carTypeId = (int) $v['carTypeId'];
        $destLat = isset($v['destLatitude']) ? (float) $v['destLatitude'] : null;
        $destLng = isset($v['destLongitude']) ? (float) $v['destLongitude'] : null;
        $routeMinutes = $this->normalizeEstimatedDurationMinutesInput($request->input('estimatedDurationMinutes'));
        $routeKm = isset($v['estimatedTripKm']) && (float) $v['estimatedTripKm'] > 0
            ? (float) $v['estimatedTripKm']
            : null;

        try {
            CustomerPresenceService::touch((int) $user->id, $pickLat, $pickLng);
        } catch (\Throwable $e) {
        }

        $busy = $this->busyDriverIds();
        $eligibleDrivers = [];

        try {
            Redis::ping();
        } catch (\Throwable $e) {
            return response()->json([
                'success' => true,
                'data' => [],
                'message' => 'تعذر جلب السائقين — تحقق من Redis والموقع',
            ]);
        }

        $distances = DriverNearbyService::nearbyEligibleDriverDistances(
            $pickLng,
            $pickLat
        );
        $requestedType = CarType::find($carTypeId);

        foreach ($distances as $id => $kmToPickup) {
            if (in_array($id, $busy, true)) {
                continue;
            }
            $d = Driver::with(['user', 'transType'])->find($id);
            if (! $d || ! CarType::driverServesRequestType((int) $d->transTypeId, $carTypeId)) {
                continue;
            }
            if (! DriverSubscriptionService::isVisibleToPassengers($d)) {
                continue;
            }
            $eligibleDrivers[] = $this->driverPayloadForNearbyPreview(
                $d,
                round($kmToPickup, 2),
                $pickLat,
                $pickLng,
                $destLat,
                $destLng,
                $routeMinutes,
                $routeKm,
                $requestedType
            );
        }

        usort($eligibleDrivers, fn ($a, $b) => ($a['distance_from_pickup_km'] ?? 9999) <=> ($b['distance_from_pickup_km'] ?? 9999));

        return response()->json([
            'success' => true,
            'data' => $eligibleDrivers,
        ]);
    }

    /**
     * Driver requests (assigned to this driver) - immediate + scheduled.
     */
    public function getDriverRequests(HttpRequest $request, $driverId)
    {
        $driver = Driver::where('userId', $request->user()->id)->first();
        if (! $driver || (int) $driver->id !== (int) $driverId) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $did = (int) $driverId;
        $cacheKey = DriverPollCacheService::driverRequestsKey($did);

        $items = Cache::remember($cacheKey, DriverPollCacheService::TTL_DRIVER_REQUESTS, function () use ($driverId) {
            return RequestModel::where('driverId', $driverId)
                ->whereNotIn('status', [
                    RequestModel::STATUS_REMOVED,
                    RequestModel::STATUS_FINISHED,
                ])
                ->with(['user', 'startLocation', 'destLocation', 'carType'])
                ->orderBy('created_at', 'desc')
                ->get();
        });

        DriverPollCacheService::rememberDriverRequestsLast($did, $items);

        return response()->json([
            'success' => true,
            'data' => collect($items)->map(fn ($m) => $this->withCrossCategoryNote($m, $driver))->values(),
        ]);
    }

    /** @return array<string, mixed> */
    private function withCrossCategoryNote(RequestModel $m, Driver $driver): array
    {
        $row = $m->toArray();
        $row['cross_category_note'] = CarType::crossCategoryNote((int) $m->carTypeId, (int) $driver->transTypeId);

        return ImmediatePendingForDriver::hidePassengerContact($row);
    }

    /**
     * Driver arrived to pickup point.
     */
    public function driverArrived(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $req = RequestModel::with(['startLocation', 'destLocation'])->find($requestId);
        if (! $req || (int) $req->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        $status = RequestModel::normalizeTripStatus($req->status);
        if ($status !== RequestModel::STATUS_RESERVED) {
            if ($status === RequestModel::STATUS_DRIVER_ARRIVED) {
                try {
                    TripTraceService::markArrived($req, (int) $driver->id);
                } catch (\Throwable $e) {
                }

                return response()->json([
                    'success' => true,
                    'data' => $req->fresh(['startLocation', 'destLocation']),
                    'message' => 'Driver already arrived',
                ]);
            }

            return response()->json([
                'success' => false,
                'message' => 'لا يمكن تسجيل الوصول في هذه المرحلة ('.$status.')',
            ], 400);
        }

        if ($req->type === RequestModel::TYPE_SCHEDULE && $req->sched_driver_started_at === null) {
            return response()->json([
                'success' => false,
                'message' => 'حجز مسبق: اضغط «انطلق للراكب» أولاً (يُفتح قبل الموعد بنصف ساعة)',
            ], 400);
        }

        $req->status = RequestModel::STATUS_DRIVER_ARRIVED;
        $req->save();
        try {
            TripTraceService::markArrived($req, (int) $driver->id);
        } catch (\Throwable $e) {
        }

        $this->notifyPassengerTripPush(
            (int) $req->userId,
            (int) $req->id,
            'trip.driver_arrived',
            'وصل السائق',
            'السائق وصل إلى موقعك'
        );

        return response()->json([
            'success' => true,
            'data' => $req->fresh(['startLocation', 'destLocation']),
            'message' => 'Driver arrived',
        ]);
    }

    /**
     * Customer confirms driver arrival (legacy — الراكب لم يعد يؤكد من التطبيق).
     */
    public function customerConfirmDriverArrived(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->status !== RequestModel::STATUS_DRIVER_ARRIVED) {
            return response()->json(['success' => false, 'message' => 'Cannot confirm at this status'], 400);
        }

        // إن كانت الوجهة مسجّلة مسبقاً (طلب فوري مع وجهة)، نبدأ الرحلة مباشرة ليظهر للسائق التوجيه للوجهة.
        if ($req->destLocationId !== null) {
            $req->status = RequestModel::STATUS_RUNNING;
            $this->markTripRunningStarted($req);
        } else {
            $req->status = RequestModel::STATUS_AWAITING_DESTINATION;
        }
        $req->save();

        return response()->json([
            'success' => true,
            'data' => $req->fresh(['startLocation', 'destLocation']),
            'message' => 'Confirmed',
        ]);
    }

    /**
     * Customer sets destination after confirming driver arrival.
     */
    public function customerSetDestination(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'destLocationLongitude' => 'required|numeric|between:-180,180',
            'destLocationLatitude' => 'required|numeric|between:-90,90',
        ]);

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->status !== RequestModel::STATUS_AWAITING_DESTINATION) {
            return response()->json(['success' => false, 'message' => 'Cannot set destination at this status'], 400);
        }

        $destLocation = Location::where('longitude', $v['destLocationLongitude'])
            ->where('latitude', $v['destLocationLatitude'])
            ->first();
        if (! $destLocation) {
            $destLocation = Location::create([
                'longitude' => $v['destLocationLongitude'],
                'latitude' => $v['destLocationLatitude'],
            ]);
        }

        $req->destLocationId = $destLocation->id;
        $req->status = RequestModel::STATUS_RUNNING;
        $this->markTripRunningStarted($req);
        $req->save();

        return response()->json([
            'success' => true,
            'data' => $req->fresh(['startLocation', 'destLocation']),
            'message' => 'Destination set',
        ]);
    }

    /**
     * الراكب يتحرك قبل وصول السائق — نقطة الالتقاء تتبع موقعه الحي (طلب فوري فقط).
     */
    public function customerUpdatePickup(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $req = RequestModel::with('startLocation')->find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_IMMEDIATE || ! in_array($req->status, [
            RequestModel::STATUS_PENDING,
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
        ], true)) {
            return response()->json(['success' => false, 'message' => 'Cannot update pickup at this status'], 400);
        }

        $lat = (float) $v['latitude'];
        $lng = (float) $v['longitude'];
        $cur = $req->startLocation;
        if ($cur) {
            $dLat = deg2rad($lat - (float) $cur->latitude);
            $dLng = deg2rad($lng - (float) $cur->longitude);
            $a = sin($dLat / 2) ** 2
                + cos(deg2rad((float) $cur->latitude)) * cos(deg2rad($lat)) * sin($dLng / 2) ** 2;
            $meters = 6371000 * 2 * atan2(sqrt($a), sqrt(1 - $a));
            if ($meters < 15) {
                return response()->json(['success' => true, 'data' => $req, 'unchanged' => true]);
            }
        }

        $loc = Location::create([
            'longitude' => $lng,
            'latitude' => $lat,
            'name' => $cur?->name,
            'type' => Location::TYPE_PICKUP,
        ]);
        $req->startLocationId = $loc->id;
        $req->save();
        DriverPollCacheService::bust();

        return response()->json([
            'success' => true,
            'data' => $req->fresh(['startLocation', 'destLocation']),
        ]);
    }

    /**
     * ردّ الراكب على «هل أنت جاهز؟» قبل موعد الحجز المسبق.
     */
    public function scheduledPassengerReady(HttpRequest $request, int $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'ready' => 'required|boolean',
        ]);

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_SCHEDULE || $req->status !== RequestModel::STATUS_RESERVED) {
            return response()->json(['success' => false, 'message' => 'Invalid request state'], 400);
        }

        if (! $req->sched_ready_sent_at || ! $req->sched_ready_deadline_at) {
            return response()->json(['success' => false, 'message' => 'No readiness prompt for this trip'], 400);
        }

        if ($req->sched_ready_answered_at) {
            return response()->json(['success' => false, 'message' => 'Already answered'], 400);
        }

        if (now()->greaterThan($req->sched_ready_deadline_at)) {
            return response()->json(['success' => false, 'message' => 'Response deadline passed'], 400);
        }

        $req->sched_ready_answered_at = now();

        if (! $v['ready']) {
            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = 'passenger_not_ready';
            $req->save();
            $this->releaseCouponForRequest((int) $req->id);
            $this->notifyPassengerSchedPayload(
                (int) $req->userId,
                (int) $req->id,
                'sched_passenger_declined',
                'تم إلغاء الرحلة',
                'أكدت أنك غير جاهز؛ تم إلغاء الحجز المسبق.'
            );
            $this->notifyDriverTripCancelledSummary($req, 'ألغى الراكب الحجز (غير جاهز).');

            return response()->json([
                'success' => true,
                'message' => 'تم إلغاء الحجز',
            ]);
        }

        $req->sched_driver_response_deadline_at = now()->addMinutes(15);
        $req->save();

        $driver = Driver::find($req->driverId);
        if ($driver) {
            $this->createDriverNotification(
                (int) $driver->userId,
                'الراكب جاهز',
                'أكّد الراكب جاهزيته. اضغط «ابدأ الرحلة» خلال 15 دقيقة أو يُلغى الحجز.',
                'sched_passenger_ready',
                (int) $req->id
            );
        }

        return response()->json([
            'success' => true,
            'message' => 'تم؛ سيصل السائق إشعاراً.',
        ]);
    }

    /**
     * بعد إشعار «السائق مشغول»: انتظار 15 دقيقة أو إلغاء.
     */
    public function scheduledPassengerWaitOrCancel(HttpRequest $request, int $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'action' => 'required|string|in:wait,cancel',
        ]);

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_SCHEDULE || $req->status !== RequestModel::STATUS_RESERVED) {
            return response()->json(['success' => false, 'message' => 'Invalid request state'], 400);
        }

        if ($req->sched_driver_deferred_at === null) {
            return response()->json(['success' => false, 'message' => 'Nothing to respond to'], 400);
        }

        if ($v['action'] === 'cancel') {
            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = 'passenger_cancelled_after_driver_busy';
            $req->sched_driver_deferred_at = null;
            $req->sched_driver_retry_at = null;
            $req->save();
            $this->releaseCouponForRequest((int) $req->id);
            $this->notifyDriverTripCancelledSummary($req, 'ألغى الراكب الحجز بعد تأجيل السائق.');

            return response()->json(['success' => true, 'message' => 'تم إلغاء الحجز']);
        }

        $req->sched_driver_retry_at = now()->addMinutes(15);
        $req->sched_driver_deferred_at = null;
        $req->save();

        return response()->json([
            'success' => true,
            'message' => 'سنعيد التواصل مع السائق خلال 15 دقيقة.',
        ]);
    }

    /**
     * «انطلق للراكب» للحجز المسبق (start) أو تأجيل (defer).
     */
    public function scheduledDriverResponse(HttpRequest $request, int $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $v = $request->validate([
            'action' => 'required|string|in:start,defer',
        ]);

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_SCHEDULE || $req->status !== RequestModel::STATUS_RESERVED) {
            return response()->json(['success' => false, 'message' => 'Invalid request state'], 400);
        }

        if ($v['action'] === 'start') {
            if ($req->sched_driver_started_at !== null) {
                return response()->json([
                    'success' => true,
                    'data' => $req->fresh(['startLocation', 'destLocation', 'carType']),
                    'message' => 'أنت بالفعل في الطريق للراكب',
                ]);
            }
            if (! RequestModel::schedGoWindowOpen($req)) {
                $when = $req->requestDate
                    ? $req->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i')
                    : '';

                return response()->json([
                    'success' => false,
                    'code' => 'SCHED_WINDOW_CLOSED',
                    'message' => 'يُفتح الحجز قبل الموعد بنصف ساعة'.($when !== '' ? " (الموعد: {$when})" : ''),
                ], 400);
            }
            if ($this->isDriverBusy((int) $driver->id, (int) $req->id)) {
                return response()->json([
                    'success' => false,
                    'code' => 'DRIVER_BUSY',
                    'message' => 'أنهِ رحلتك الحالية أولاً ثم اضغط «انطلق للراكب»',
                ], 409);
            }
            // يبقى Reserved حتى «وصلت» و«بدء التنفيذ» — لا قفز مباشر إلى Running.
            $req->sched_driver_started_at = now();
            if ($req->sched_ready_answered_at === null) {
                $req->sched_ready_answered_at = now();
            }
            $req->sched_driver_deferred_at = null;
            $req->sched_driver_retry_at = null;
            $req->sched_driver_response_deadline_at = null;
            $req->save();

            $this->notifyPassengerTripPush(
                (int) $req->userId,
                (int) $req->id,
                'trip.sched_en_route',
                'السائق بالطريق إليك',
                'بدأ السائق التوجه إليك لطلبك المسبق — لا تغادر موقعك'
            );
            DriverPollCacheService::bust();

            return response()->json([
                'success' => true,
                'data' => $req->fresh(['startLocation', 'destLocation', 'carType']),
                'message' => 'انطلق للراكب — الراكب بانتظارك',
            ]);
        }

        $req->sched_driver_deferred_at = now();
        $req->sched_driver_response_deadline_at = null;
        $req->save();

        CustomerNotification::create([
            'user_id' => $req->userId,
            'title' => 'السائق مشغول',
            'body' => 'السائق غير متاح الآن. يمكنك إلغاء الحجز واختيار سائق آخر، أو الانتظار 15 دقيقة.',
            'kind' => 'sched_driver_busy',
            'reference_type' => 'request',
            'reference_id' => $req->id,
            'payload' => [
                'kind' => 'sched_driver_busy',
                'request_id' => $req->id,
            ],
        ]);

        return response()->json([
            'success' => true,
            'message' => 'تم إبلاغ الراكب',
        ]);
    }

    /**
     * Send notification to drivers about scheduled request
     */
    private function notifyDriversForScheduledRequest($request)
    {
        $drivers = Driver::all();

        foreach ($drivers as $driver) {
            // Send notification via Firebase or WebSocket
            // event(new NewScheduledRequest($driver, $request));
        }
    }

    /**
     * Send notification to a driver
     */
    private function sendNotificationToDriver($driver, $request)
    {
        // Implement notification sending
    }

    /**
     * Accept booking by driver
     */
    public function acceptBooking(HttpRequest $request, $requestId)
    {
        $driver = Driver::where('userId', $request->user()->id)->first();

        if (! $driver) {
            return response()->json([
                'success' => false,
                'message' => 'Driver profile not found',
            ], 404);
        }

        $driverId = $driver->id;

        $requestData = RequestModel::find($requestId);

        if (! $requestData) {
            return response()->json([
                'success' => false,
                'message' => 'Request not found',
            ], 404);
        }

        if ($requestData->status !== RequestModel::STATUS_PENDING) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot accept this request at this time',
            ], 400);
        }

        if ($requestData->type === RequestModel::TYPE_IMMEDIATE) {
            // تدفق جديد (A): إذا كان الراكب قد اختار سائقاً مسبقاً، لا يحق إلا لهذا السائق قبول الطلب
            if ($requestData->driverId !== null && (int) $requestData->driverId !== (int) $driverId) {
                return response()->json([
                    'success' => false,
                    'message' => 'هذا الطلب موجّه لسائق آخر',
                ], 403);
            }

            // إذا كان موجهاً لهذا السائق (driverId مضبوط) فقبوله يعني الحجز مباشرة
            if ($requestData->driverId !== null && (int) $requestData->driverId === (int) $driverId) {
                DB::beginTransaction();
                try {
                    $locked = RequestModel::whereKey($requestData->id)->lockForUpdate()->first();
                    if (! $locked) {
                        DB::rollBack();

                        return response()->json([
                            'success' => false,
                            'message' => 'Request not found',
                        ], 404);
                    }

                    if ($locked->status !== RequestModel::STATUS_PENDING
                        || (int) $locked->driverId !== (int) $driverId) {
                        DB::rollBack();

                        return response()->json([
                            'success' => false,
                            'message' => 'Cannot accept this request at this time',
                        ], 400);
                    }

                    if ($this->isDriverBusy($driverId, (int) $locked->id)) {
                        DB::rollBack();

                        return response()->json([
                            'success' => false,
                            'code' => 'DRIVER_BUSY',
                            'message' => 'لديك رحلة نشطة أخرى — أنهِها قبل قبول طلب جديد',
                        ], 409);
                    }

                    $locked->status = RequestModel::STATUS_RESERVED;
                    $locked->save();

                    RequestHistory::firstOrCreate(
                        ['requestId' => $locked->id],
                        [
                            'driverId' => $driverId,
                            'finalCost' => $locked->predectedCost ?? 0,
                            'descountId' => $request->discountId ?? null,
                        ]
                    );

                    DB::commit();
                    $requestData = $locked;
                } catch (\Exception $e) {
                    DB::rollBack();
                    return response()->json([
                        'success' => false,
                        'message' => 'An error occurred: '.$e->getMessage(),
                    ], 500);
                }

                // تنظيف أي عروض/eligible قديمة
                try {
                    Redis::del('request:'.$requestData->id.':eligible');
                } catch (\Throwable $e) {}
                try {
                    RequestDriverOffer::where('request_id', $requestData->id)->delete();
                } catch (\Throwable $e) {}

                // إشعار داخلي + FCM فوري للراكب
                $this->notifyPassengerTripPush(
                    (int) $requestData->userId,
                    (int) $requestData->id,
                    'trip.accepted',
                    'تم قبول الطلب',
                    'تم قبول الطلب والسائق في طريقه إليك لا تغادر موقعك'
                );

                DriverPollCacheService::bust();
                try {
                    TripTraceService::markAccepted($requestData->fresh(['startLocation']) ?? $requestData, $driverId);
                } catch (\Throwable $e) {
                }

                return response()->json([
                    'success' => true,
                    'data' => ['reserved' => true],
                    'message' => 'تم قبول الطلب',
                ]);
            }

            // بث لعدة سائقين: أول من يقبل يفوز
            if (! ImmediatePendingForDriver::driverCanSee($driver, $requestData)) {
                return response()->json([
                    'success' => false,
                    'message' => 'غير مدرج ضمن نطاق هذا الطلب',
                ], 403);
            }

            $eligibleKey = 'request:'.$requestData->id.':eligible';

            $otherDriverIds = [];
            try {
                if (Redis::exists($eligibleKey)) {
                    foreach (Redis::smembers($eligibleKey) ?: [] as $sid) {
                        $oid = (int) $sid;
                        if ($oid > 0 && $oid !== $driverId) {
                            $otherDriverIds[] = $oid;
                        }
                    }
                }
            } catch (\Throwable $e) {
            }

            DB::beginTransaction();
            try {
                $locked = RequestModel::whereKey($requestData->id)->lockForUpdate()->first();
                if (! $locked) {
                    DB::rollBack();

                    return response()->json([
                        'success' => false,
                        'message' => 'Request not found',
                    ], 404);
                }

                if ($locked->status !== RequestModel::STATUS_PENDING) {
                    DB::rollBack();
                    if ($locked->status === RequestModel::STATUS_RESERVED
                        && $locked->driverId !== null
                        && (int) $locked->driverId !== $driverId) {
                        return response()->json([
                            'success' => false,
                            'code' => 'TAKEN_BY_OTHER',
                            'message' => 'تم قبول الطلب من سائق آخر',
                        ], 409);
                    }

                    return response()->json([
                        'success' => false,
                        'message' => 'Cannot accept this request at this time',
                    ], 400);
                }

                if ($locked->driverId !== null && (int) $locked->driverId !== $driverId) {
                    DB::rollBack();

                    return response()->json([
                        'success' => false,
                        'code' => 'TAKEN_BY_OTHER',
                        'message' => 'تم قبول الطلب من سائق آخر',
                    ], 409);
                }

                if ($this->isDriverBusy($driverId, (int) $locked->id)) {
                    DB::rollBack();

                    return response()->json([
                        'success' => false,
                        'code' => 'DRIVER_BUSY',
                        'message' => 'لديك رحلة نشطة أخرى — أنهِها قبل قبول طلب جديد',
                    ], 409);
                }

                $locked->driverId = $driverId;
                $locked->status = RequestModel::STATUS_RESERVED;
                $locked->save();

                RequestHistory::firstOrCreate(
                    ['requestId' => $locked->id],
                    [
                        'driverId' => $driverId,
                        'finalCost' => $locked->predectedCost ?? 0,
                        'descountId' => $request->discountId ?? null,
                    ]
                );

                DB::commit();
            } catch (\Exception $e) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'An error occurred: '.$e->getMessage(),
                ], 500);
            }

            try {
                Redis::del($eligibleKey);
            } catch (\Throwable $e) {
            }
            try {
                RequestDriverOffer::where('request_id', $requestData->id)->delete();
            } catch (\Throwable $e) {
            }

            $this->notifyPassengerTripPush(
                (int) $requestData->userId,
                (int) $requestData->id,
                'trip.accepted',
                'تم قبول الطلب',
                'تم قبول الطلب والسائق في طريقه إليك لا تغادر موقعك'
            );

            $this->notifyOtherDriversImmediateTaken($otherDriverIds, (int) $requestData->id);

            DriverPollCacheService::bust();
            try {
                TripTraceService::markAccepted(
                    RequestModel::with('startLocation')->find($requestData->id) ?? $requestData,
                    $driverId
                );
            } catch (\Throwable $e) {
            }

            return response()->json([
                'success' => true,
                'data' => ['reserved' => true],
                'message' => 'تم قبول الطلب',
            ]);
        }

        if ($requestData->type === RequestModel::TYPE_SCHEDULE) {
            if ($requestData->driverId !== null && (int) $requestData->driverId !== (int) $driverId) {
                return response()->json([
                    'success' => false,
                    'message' => 'هذا الحجز موجّه لسائق آخر',
                ], 403);
            }
        }

        DB::beginTransaction();

        try {
            $locked = RequestModel::whereKey($requestData->id)->lockForUpdate()->first();
            if (! $locked) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'Request not found',
                ], 404);
            }

            if ($locked->status !== RequestModel::STATUS_PENDING) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'Cannot accept this request at this time',
                ], 400);
            }

            if ($locked->driverId !== null && (int) $locked->driverId !== (int) $driverId) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'هذا الحجز موجّه لسائق آخر',
                ], 403);
            }

            $conflict = $locked->type === RequestModel::TYPE_SCHEDULE
                ? $this->scheduledAcceptConflict($driverId, $locked)
                : ($this->isDriverBusy($driverId, (int) $locked->id)
                    ? 'لديك رحلة نشطة أخرى — أنهِها قبل قبول طلب جديد'
                    : null);
            if ($conflict !== null) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'code' => 'DRIVER_BUSY',
                    'message' => $conflict,
                ], 409);
            }

            $locked->status = RequestModel::STATUS_RESERVED;
            $locked->driverId = $driverId;
            $locked->sched_driver_started_at = null;
            $locked->sched_ready_answered_at = null;
            $locked->sched_driver_response_deadline_at = null;
            $locked->sched_driver_deferred_at = null;
            $locked->save();

            $history = RequestHistory::create([
                'requestId' => $locked->id,
                'driverId' => $driverId,
                'finalCost' => $locked->predectedCost ?? 0,
                'descountId' => $request->discountId ?? null,
            ]);

            DB::commit();
            $requestData = $locked;

            try {
                TripTraceService::markAccepted($requestData->fresh(['startLocation']) ?? $requestData, $driverId);
            } catch (\Throwable $e) {
            }

            $this->sendConfirmationToPassenger($requestData, $driver);

            $when = $requestData->requestDate
                ? $requestData->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i')
                : '';
            $msg = $when !== ''
                ? "تم قبول الطلب. الموعد: {$when}. يمكنك استقبال طلبات فورية والعداد الحر حتى قبل الموعد بنصف ساعة، ثم اضغط «انطلق للراكب»."
                : 'تم قبول الطلب. قبل الموعد بنصف ساعة اضغط «انطلق للراكب».';

            return response()->json([
                'success' => true,
                'data' => [
                    'request' => $requestData,
                    'history' => $history,
                    'driver' => $driver,
                ],
                'message' => $msg,
            ]);
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }
    }

    /**
     * Send confirmation to passenger
     */
    private function sendConfirmationToPassenger(RequestModel $request, Driver $driver): void
    {
        if ($request->type !== RequestModel::TYPE_SCHEDULE) {
            return;
        }

        try {
            $when = $request->requestDate
                ? $request->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i')
                : '';
            $body = $when !== ''
                ? "تم قبول طلبك المسبق. موعد الرحلة: {$when}. قبل الموعد بنصف ساعة سنرسل لك إشعاراً ويتوجه السائق إليك."
                : 'تم قبول طلبك المسبق. قبل الموعد بنصف ساعة سنرسل لك إشعاراً ويتوجه السائق إليك.';

            $this->notifyPassengerTripPush(
                (int) $request->userId,
                (int) $request->id,
                'sched_accepted',
                'تم قبول الطلب',
                $body
            );
        } catch (\Throwable $e) {
        }
    }

    /**
     * بدء رحلة عداد حر مستقلة — تُنشئ طلب Running في قاعدة البيانات.
     */
    public function startFreeMeter(HttpRequest $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $request->validate([
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'startLocationName' => 'nullable|string|max:255',
        ]);

        $carTypeId = (int) ($driver->transTypeId ?? 0);
        if ($carTypeId <= 0) {
            $fallback = CarType::query()->orderBy('id')->value('id');
            $carTypeId = (int) ($fallback ?? 0);
        }
        if ($carTypeId <= 0) {
            return response()->json([
                'success' => false,
                'message' => 'لا توجد فئة سيارة مرتبطة بالسائق',
            ], 422);
        }

        $lat = $request->filled('latitude') ? (float) $request->input('latitude') : null;
        $lng = $request->filled('longitude') ? (float) $request->input('longitude') : null;
        if ($lat === null || $lng === null || ! is_finite($lat) || ! is_finite($lng)) {
            $lat = 33.5138;
            $lng = 36.2765;
        }

        // أعمدة مؤكدة بعد الترحيلات — تجنّب Schema::hasColumn (بطيء على كل طلب).
        DB::beginTransaction();
        try {
            // رحلة تطبيق جارية فعلاً فقط — لا Pending عالق لأيام يمنع العداد الحر.
            $activeAppTrip = RequestModel::query()
                ->where('driverId', $driver->id)
                ->occupyingDriver()
                ->where('status', '!=', RequestModel::STATUS_PENDING)
                ->where(function ($q) {
                    $q->whereNull('billing_kind')
                        ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
                })
                ->lockForUpdate()
                ->first();

            if ($activeAppTrip) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'code' => 'ACTIVE_APP_TRIP',
                    'message' => RequestModel::scheduledAwaitingGo($activeAppTrip)
                        ? 'حجزك المسبق يبدأ خلال نصف ساعة — اضغط «انطلق للراكب» بدل العداد الحر'
                        : 'لديك رحلة عبر التطبيق — أنهِها أو ألغِها قبل تشغيل العداد الحر',
                ], 409);
            }

            // أغلق أي عداد حر عالق لنفس السائق قبل بدء جديد.
            $stale = RequestModel::query()
                ->where('driverId', $driver->id)
                ->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER)
                ->whereIn('status', [
                    RequestModel::STATUS_RUNNING,
                    RequestModel::STATUS_RESERVED,
                    RequestModel::STATUS_PENDING,
                    RequestModel::STATUS_DRIVER_ARRIVED,
                    RequestModel::STATUS_AWAITING_DESTINATION,
                ])
                ->lockForUpdate()
                ->get();
            foreach ($stale as $old) {
                $old->status = RequestModel::STATUS_REMOVED;
                $old->cancel_reason = 'free_meter_superseded';
                $old->save();
            }

            $startLocation = Location::create([
                'longitude' => $lng,
                'latitude' => $lat,
                'name' => trim((string) $request->input('startLocationName', 'عداد حر — نقطة البداية')) ?: 'عداد حر — نقطة البداية',
                'type' => Location::TYPE_PICKUP,
                'description' => 'free_meter',
            ]);

            $now = now();
            $newRequest = RequestModel::create([
                'userId' => $driver->userId,
                'driverId' => $driver->id,
                'carTypeId' => $carTypeId,
                'type' => RequestModel::TYPE_IMMEDIATE,
                'status' => RequestModel::STATUS_RUNNING,
                'startLocationId' => $startLocation->id,
                'destLocationId' => null,
                'requestDate' => $now,
                'locationDesc' => 'رحلة عداد حر',
                'predectedCost' => 0,
                'billing_kind' => RequestModel::BILLING_KIND_FREE_METER,
                'trip_started_at' => $now,
                'is_app_request' => false,
            ]);

            $history = RequestHistory::create([
                'requestId' => $newRequest->id,
                'driverId' => $driver->id,
                'finalCost' => 0,
                'distanceTraveledKm' => null,
            ]);

            DB::commit();

            try {
                DriverPollCacheService::bust();
            } catch (\Throwable $e) {
            }

            return response()->json([
                'success' => true,
                'state' => true,
                'data' => [
                    'id' => (int) $newRequest->id,
                    'status' => $newRequest->status,
                    'billing_kind' => $newRequest->billing_kind,
                    'driverId' => (int) $newRequest->driverId,
                ],
                'request_id' => (int) $newRequest->id,
                'history' => [
                    'id' => (int) $history->id,
                    'requestId' => (int) $history->requestId,
                ],
                'message' => 'تم بدء رحلة العداد الحر',
            ]);
        } catch (\Throwable $e) {
            DB::rollBack();
            \Illuminate\Support\Facades\Log::error('startFreeMeter: '.$e->getMessage(), [
                'driver_id' => $driver->id ?? null,
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'message' => 'تعذر بدء العداد الحر: '.$e->getMessage(),
            ], 500);
        }
    }

    /**
     * بدء الرحلة من السائق (بعد «وصلت للراكب») — يُبلّغ الراكب «وصل السائق».
     */
    public function startTrip(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $requestData = RequestModel::with(['startLocation', 'destLocation'])->find($requestId);

        if (! $requestData) {
            return response()->json([
                'success' => false,
                'message' => 'Request not found',
            ], 404);
        }

        if ((int) $requestData->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $status = RequestModel::normalizeTripStatus($requestData->status);

        if ($status === RequestModel::STATUS_RUNNING && $requestData->trip_started_at !== null) {
            return response()->json([
                'success' => true,
                'data' => $requestData->fresh(['startLocation', 'destLocation']),
                'message' => 'Trip already running',
            ]);
        }

        if (! RequestModel::canDriverStartTrip($requestData)) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن بدء الرحلة في هذه المرحلة ('.($status !== '' ? $status : 'غير معروف').')',
                'current_status' => $status,
            ], 400);
        }

        if ($requestData->type === RequestModel::TYPE_SCHEDULE && $requestData->sched_driver_started_at === null) {
            return response()->json([
                'success' => false,
                'message' => 'حجز مسبق: اضغط «انطلق للراكب» أولاً (يُفتح قبل الموعد بنصف ساعة)',
            ], 400);
        }

        if ($requestData->destLocationId !== null) {
            $requestData->status = RequestModel::STATUS_RUNNING;
            $this->markTripRunningStarted($requestData);
        } else {
            $requestData->status = RequestModel::STATUS_AWAITING_DESTINATION;
        }
        $requestData->save();

        try {
            $this->notifyPassengerTripPush(
                (int) $requestData->userId,
                (int) $requestData->id,
                'trip.started',
                'بدأت الرحلة',
                'السائق معك — الرحلة جارية.'
            );
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => $requestData->fresh(['startLocation', 'destLocation']),
            'message' => 'Trip started successfully',
        ]);
    }

    /**
     * معامل منطقة التسعير لعدّاد الرحلة: منطقة نقطة البداية ← منطقة نقطة الإنهاء الفعلية.
     * null = التطبيق قديم (لم يرسل meter_base_cost) فتبقى الأجرة كما أرسلها.
     *
     * @return array{multiplier: float, from: array, to: array, label: string}|null
     */
    private function meterZoneQuote(RequestModel $req, HttpRequest $request, int $driverId): ?array
    {
        if (! $request->has('meter_base_cost')) {
            return null;
        }

        $start = $req->startLocation;
        $startLat = $start ? (float) $start->latitude : null;
        $startLng = $start ? (float) $start->longitude : null;

        $endLat = $request->filled('end_latitude') ? (float) $request->input('end_latitude') : null;
        $endLng = $request->filled('end_longitude') ? (float) $request->input('end_longitude') : null;
        if ($endLat === null || $endLng === null || ($endLat == 0.0 && $endLng == 0.0)) {
            $c = DriverNearbyService::driverCoords($driverId);
            if ($c) {
                $endLat = (float) $c['lat'];
                $endLng = (float) $c['lng'];
            } elseif ($req->destLocation) {
                $endLat = (float) $req->destLocation->latitude;
                $endLng = (float) $req->destLocation->longitude;
            } else {
                $endLat = $startLat;
                $endLng = $startLng;
            }
        }

        return PricingZoneService::quote($startLat, $startLng, $endLat, $endLng);
    }

    /**
     * Finish trip
     */
    public function finishTrip(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->with('transType')->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $requestData = RequestModel::with(['startLocation', 'destLocation', 'carType'])->find($requestId);

        if (!$requestData) {
            return response()->json([
                'success' => false,
                'message' => 'Request not found'
            ], 404);
        }

        if ((int) $requestData->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        // مصدر الحقيقة: billing_kind المخزَّن — لا نثق بما يرسله العميل.
        $storedBilling = strtolower(trim((string) ($requestData->billing_kind ?? '')));
        $billing = $storedBilling === RequestModel::BILLING_KIND_FREE_METER
            ? RequestModel::BILLING_KIND_FREE_METER
            : RequestModel::BILLING_KIND_APP_REQUEST;

        // إنهاء متكرر لنفس رحلة العداد الحر (بعد مهلة الشبكة): اعتبره نجاحاً.
        if ($billing === RequestModel::BILLING_KIND_FREE_METER
            && $requestData->status === RequestModel::STATUS_FINISHED) {
            $hist = RequestHistory::where('requestId', $requestId)->first();
            $finalCost = (float) ($hist->finalCost ?? 0);

            return response()->json([
                'success' => true,
                'state' => true,
                'data' => $requestData->fresh(['startLocation', 'destLocation', 'carType', 'history']),
                'finalCost' => $finalCost,
                'billing_kind' => RequestModel::BILLING_KIND_FREE_METER,
                'idempotent' => true,
                'message' => 'الرحلة منتهية مسبقاً',
            ]);
        }

        $finishable = $billing === RequestModel::BILLING_KIND_FREE_METER
            ? [
                RequestModel::STATUS_RUNNING,
                RequestModel::STATUS_AWAITING_DESTINATION,
                RequestModel::STATUS_DRIVER_ARRIVED,
            ]
            : [RequestModel::STATUS_RUNNING];

        // أُغلق تلقائياً لانقطاع السائق طويلاً — نقبل الإنهاء المتأخر بأجرته الفعلية.
        $autoClosedFreeMeter = $billing === RequestModel::BILLING_KIND_FREE_METER
            && $requestData->status === RequestModel::STATUS_REMOVED
            && $requestData->cancel_reason === \App\Console\Commands\CloseStaleFreeMeters::REASON;

        if (! $autoClosedFreeMeter && ! in_array($requestData->status, $finishable, true)) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إنهاء الرحلة في حالتها الحالية ('.$requestData->status.')',
            ], 400);
        }

        $clientBilling = strtolower(trim((string) $request->input('billing_kind', '')));
        if ($clientBilling === '' && $request->boolean('free_meter')) {
            $clientBilling = RequestModel::BILLING_KIND_FREE_METER;
        }
        if ($clientBilling !== ''
            && in_array($clientBilling, [RequestModel::BILLING_KIND_APP_REQUEST, RequestModel::BILLING_KIND_FREE_METER], true)
            && $clientBilling !== $billing) {
            return response()->json([
                'success' => false,
                'code' => 'BILLING_KIND_MISMATCH',
                'message' => 'نوع الفوترة لا يطابق الرحلة المسجّلة على الخادم',
            ], 422);
        }

        if ($billing === RequestModel::BILLING_KIND_FREE_METER) {
            if (! $request->filled('finalCost') && ! $request->filled('final_cost')) {
                return response()->json([
                    'success' => false,
                    'message' => 'يجب إرسال finalCost أو final_cost لرحلة العداد الحر',
                ], 422);
            }
            $request->validate([
                'finalCost' => 'sometimes|numeric|min:0',
                'final_cost' => 'sometimes|numeric|min:0',
                'distanceTraveledKm' => 'sometimes|numeric|min:0',
                'distance_traveled_km' => 'sometimes|numeric|min:0',
                'free_meter_had_movement' => 'sometimes|boolean',
            ]);
        }

        if ($billing === RequestModel::BILLING_KIND_APP_REQUEST) {
            $request->validate([
                'finalCost' => 'sometimes|numeric|min:0',
                'final_cost' => 'sometimes|numeric|min:0',
                'distanceTraveledKm' => 'sometimes|numeric|min:0',
                'distance_traveled_km' => 'sometimes|numeric|min:0',
                'billedWaitingMinutes' => 'sometimes|integer|min:0',
                'billed_waiting_minutes' => 'sometimes|integer|min:0',
                'meterElapsedSeconds' => 'sometimes|integer|min:0',
                'meter_elapsed_seconds' => 'sometimes|integer|min:0',
            ]);
        }

        $request->validate([
            'meter_base_cost' => 'sometimes|numeric|min:0',
            'end_latitude' => 'sometimes|nullable|numeric|between:-90,90',
            'end_longitude' => 'sometimes|nullable|numeric|between:-180,180',
        ]);
        $zoneQuote = $this->meterZoneQuote($requestData, $request, (int) $driver->id);

        DB::beginTransaction();

        try {
            $history = RequestHistory::where('requestId', $requestId)->first();

            if ($billing === RequestModel::BILLING_KIND_FREE_METER) {
                // لا CarType ولا predectedCost — المبلغ من العداد فقط (الزبون في السيارة).
                $clientFinal = (float) $request->input('finalCost', $request->input('final_cost', 0));
                if ($zoneQuote !== null) {
                    $clientFinal = PricingZoneService::apply((float) $request->input('meter_base_cost'), $zoneQuote['multiplier']);
                }
                $kmMoved = (float) $request->input('distanceTraveledKm', $request->input('distance_traveled_km', 0));

                $openPrice = (float) AppSetting::getDecimal('free_meter_open_price', 0.0);
                $epsilonMoney = 0.05;
                $epsilonKm = 0.05;

                $hadMovement = $request->has('free_meter_had_movement')
                    ? $request->boolean('free_meter_had_movement')
                    : ($kmMoved > $epsilonKm);

                $countsForRevenue = $hadMovement || ($clientFinal > $openPrice + $epsilonMoney);

                $finalCost = round(max(0.0, $clientFinal), 2);

                $appliedDiscountId = null;
                $couponDeduction = 0.0;
                if ($requestData->discountId) {
                    $discount = Discount::withTrashed()->find($requestData->discountId);
                    if ($discount) {
                        $couponDeduction = (float) $discount->calculateDiscount($finalCost);
                        $finalCost = max(0, round((float) $finalCost - (float) $couponDeduction, 2));
                        $appliedDiscountId = $discount->id;
                    }
                }

                if (! $history) {
                    $history = RequestHistory::create([
                        'requestId' => $requestData->id,
                        'driverId' => $driver->id,
                        'finalCost' => $finalCost,
                        'distanceTraveledKm' => $kmMoved > 0 ? round($kmMoved, 3) : null,
                        'descountId' => $appliedDiscountId,
                    ]);
                } else {
                    $history->finalCost = $finalCost;
                    $history->distanceTraveledKm = $kmMoved > 0 ? round($kmMoved, 3) : null;
                    if ($appliedDiscountId !== null) {
                        $history->descountId = $appliedDiscountId;
                    }
                    $history->save();
                }

                $rating = (int) $request->input('driver_customer_rating', $request->input('driverCustomerRating', 0));
                if ($rating >= 1 && $rating <= 5 && \Illuminate\Support\Facades\Schema::hasColumn('requestHistories', 'driver_customer_rating')) {
                    $history->driver_customer_rating = $rating;
                    $history->save();
                }

                $requestData->billing_kind = RequestModel::BILLING_KIND_FREE_METER;
                if (\Illuminate\Support\Facades\Schema::hasColumn('requests', 'is_app_request')) {
                    $requestData->is_app_request = false;
                }
                // العداد الحر: لا تسعيرة فئة طلب — الأجرة من العداد فقط (لا predectedCost تطبيق).
                $requestData->predectedCost = 0;
                if (\Illuminate\Support\Facades\Schema::hasColumn('requests', 'free_meter_had_movement')) {
                    $requestData->free_meter_had_movement = $hadMovement;
                }
                if (\Illuminate\Support\Facades\Schema::hasColumn('requests', 'free_meter_counts_for_revenue')) {
                    $requestData->free_meter_counts_for_revenue = $countsForRevenue;
                }
                if ($zoneQuote !== null) {
                    $requestData->fill(PricingZoneService::requestAttributes($zoneQuote));
                }
                if ($autoClosedFreeMeter) {
                    $requestData->cancel_reason = null;
                }
                $requestData->status = RequestModel::STATUS_FINISHED;
                $requestData->save();
                try {
                    TripTraceService::markTripEnded($requestData, (int) $driver->id);
                } catch (\Throwable $e) {
                }

                DB::commit();

                if ($couponDeduction > 0) {
                    DriverWalletService::creditCouponCompensation(
                        (int) $driver->id,
                        (int) $requestData->id,
                        $appliedDiscountId ? (int) $appliedDiscountId : null,
                        $couponDeduction,
                    );
                }

                // لا FCM للراكب — userId هنا هو السائق نفسه في العداد الحر (كان يبطّئ الرد).
                return response()->json([
                    'success' => true,
                    'state' => true,
                    'data' => $requestData->fresh(['startLocation', 'destLocation', 'carType', 'history']),
                    'finalCost' => $finalCost,
                    'billing_kind' => RequestModel::BILLING_KIND_FREE_METER,
                    'free_meter_counts_for_revenue' => $countsForRevenue,
                    'zone' => $zoneQuote !== null ? PricingZoneService::payload($zoneQuote) : null,
                    'message' => 'تم إنهاء رحلة العداد الحر',
                ]);
            }

            // طلب التطبيق: التكلفة النهائية من عداد الرحلة (كم + وقوف + افتتاحي الفئة).
            $carType = $requestData->carType;
            $clientFinal = (float) $request->input('finalCost', $request->input('final_cost', 0));
            if ($zoneQuote !== null && (float) $request->input('meter_base_cost') > 0) {
                $clientFinal = PricingZoneService::apply((float) $request->input('meter_base_cost'), $zoneQuote['multiplier']);
            }
            $kmMoved = (float) $request->input('distanceTraveledKm', $request->input('distance_traveled_km', 0));
            $waitingMin = (int) $request->input('billedWaitingMinutes', $request->input('billed_waiting_minutes', 0));
            $elapsedSec = (int) $request->input('meterElapsedSeconds', $request->input('meter_elapsed_seconds', 0));

            if ($clientFinal <= 0) {
                return response()->json([
                    'success' => false,
                    'message' => 'يجب إرسال finalCost من عداد الرحلة',
                ], 422);
            }

            $finalCost = round(max(0.0, $clientFinal), 2);

            $appliedDiscountId = null;
            $couponDeduction = 0.0;
            if ($requestData->discountId) {
                $discount = Discount::withTrashed()->find($requestData->discountId);
                if ($discount) {
                    $couponDeduction = (float) $discount->calculateDiscount($finalCost);
                    $finalCost = max(0, round((float) $finalCost - (float) $couponDeduction, 2));
                    $appliedDiscountId = $discount->id;
                }
            }

            if ($history) {
                $history->finalCost = $finalCost;
                $history->distanceTraveledKm = $kmMoved > 0 ? round($kmMoved, 3) : null;
                if ($appliedDiscountId !== null) {
                    $history->descountId = $appliedDiscountId;
                }
                $rating = (int) $request->input('driver_customer_rating', $request->input('driverCustomerRating', 0));
                if ($rating >= 1 && $rating <= 5 && \Illuminate\Support\Facades\Schema::hasColumn('requestHistories', 'driver_customer_rating')) {
                    $history->driver_customer_rating = $rating;
                }
                $history->save();
            }

            try {
                Redis::del('request:'.$requestData->id.':live_meter');
            } catch (\Throwable $e) {
            }

            $requestData->billing_kind = RequestModel::BILLING_KIND_APP_REQUEST;
            $requestData->is_app_request = true;
            $requestData->free_meter_had_movement = null;
            $requestData->free_meter_counts_for_revenue = null;
            if ($zoneQuote !== null) {
                $requestData->fill(PricingZoneService::requestAttributes($zoneQuote));
            }
            $requestData->status = RequestModel::STATUS_FINISHED;
            CustomerWalletService::resetForFinishedTrip($requestData, $finalCost);
            $requestData->save();
            try {
                TripTraceService::markTripEnded($requestData, (int) $driver->id);
            } catch (\Throwable $e) {
            }

            DB::commit();

            if ($couponDeduction > 0) {
                DriverWalletService::creditCouponCompensation(
                    (int) $driver->id,
                    (int) $requestData->id,
                    $appliedDiscountId ? (int) $appliedDiscountId : null,
                    $couponDeduction,
                );
            }

            $this->notifyPassengerTripPush(
                (int) $requestData->userId,
                (int) $requestData->id,
                'trip.finished',
                'انتهت الرحلة',
                'شكراً لاستخدامكم التطبيق'
            );

            return response()->json([
                'success' => true,
                'data' => $requestData->fresh(['startLocation', 'destLocation', 'carType', 'history']),
                'finalCost' => $finalCost,
                'distanceTraveledKm' => $kmMoved > 0 ? round($kmMoved, 3) : null,
                'billedWaitingMinutes' => $waitingMin,
                'meterElapsedSeconds' => $elapsedSec,
                'predectedCost' => $requestData->predectedCost,
                'billing_kind' => RequestModel::BILLING_KIND_APP_REQUEST,
                'zone' => $zoneQuote !== null ? PricingZoneService::payload($zoneQuote) : null,
                'message' => 'Trip finished successfully',
            ]);
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }
    }

    /**
     * Get available bookings for drivers
     */
    public function getAvailableBookings(HttpRequest $request)
    {
        $user = $request->user();
        if (!$user || $user->roll !== 'Driver') {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $bookings = RequestModel::where('type', RequestModel::TYPE_SCHEDULE)
            ->where('status', RequestModel::STATUS_PENDING)
            ->where('requestDate', '>', now())
            ->whereIn('carTypeId', CarType::requestTypeIdsServedBy((int) $driver->transTypeId))
            ->where(function ($q) use ($driver) {
                $q->whereNull('driverId')
                    ->orWhere('driverId', $driver->id);
            })
            ->with(['user', 'startLocation', 'destLocation', 'carType'])
            ->orderBy('requestDate', 'asc')
            ->get()
            ->filter(function ($row) use ($driver) {
                return \App\Services\ImmediatePendingForDriver::driverCanSee($driver, $row);
            })
            ->map(fn ($row) => $this->withCrossCategoryNote($row, $driver))
            ->values();

        return response()->json([
            'success' => true,
            'data' => $bookings,
            'message' => 'Available bookings retrieved successfully'
        ]);
    }

    /**
     * إلغاء الطلب من الزبون (قبل بدء الرحلة)
     */
    public function cancelByCustomer(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        DB::beginTransaction();
        try {
            $req = RequestModel::whereKey($requestId)->lockForUpdate()->first();
            if (! $req || (int) $req->userId !== (int) $user->id) {
                DB::rollBack();

                return response()->json(['success' => false, 'message' => 'Request not found'], 404);
            }

            $status = RequestModel::normalizeTripStatus($req->status);
            if (! RequestModel::canAbortTrip($req)) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'لا يمكن إلغاء الطلب في هذه المرحلة ('.($status !== '' ? $status : 'غير معروف').')',
                ], 400);
            }

            $reason = trim((string) $request->input('reason', ''));
            // طلبات الإدارة الموجّهة لسائق: لا تُلغَ تلقائياً عند إعادة فتح تطبيق الزبون
            if ($reason === 'abandoned_on_reopen' && RequestModel::isAdminDispatched($req)) {
                DB::rollBack();

                return response()->json([
                    'success' => true,
                    'skipped' => true,
                    'message' => 'طلب إداري — لم يُلغَ',
                ]);
            }

            $assignedDriverId = $req->driverId ? (int) $req->driverId : null;

            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = $reason !== '' ? $reason : null;
            $req->save();

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        try {
            Redis::del('request:'.$req->id.':eligible');
        } catch (\Throwable $e) {
        }
        try {
            RequestDriverOffer::where('request_id', $req->id)->delete();
        } catch (\Throwable $e) {
        }

        $this->releaseCouponForRequest((int) $req->id);

        if ($assignedDriverId) {
            try {
                broadcast(new RequestCancelledByCustomerEvent($assignedDriverId, (int) $req->id));
            } catch (\Throwable $e) {
                // لا نمنع الإلغاء إن تعذّر البث (Redis/Reverb…)
            }
        }

        DriverPollCacheService::bust();

        return response()->json([
            'success' => true,
            'data' => $req->fresh(),
            'message' => 'Request cancelled',
        ]);
    }

    /**
     * شاشة البحث عند الراكب: توسيع نطاق طلب فوري لم يقبله أحد بعد (المرحلة 1..3).
     */
    public function expandSearch(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }
        $radii = \App\Services\ImmediateDriverNotifier::EXPAND_RADII_KM;
        $v = $request->validate([
            'stage' => 'required|integer|min:1|max:'.max(array_keys($radii)),
        ]);

        $req = RequestModel::with('startLocation')->find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        $status = RequestModel::normalizeTripStatus($req->status);
        if ($req->type !== RequestModel::TYPE_IMMEDIATE
            || $req->status !== RequestModel::STATUS_PENDING
            || $req->driverId !== null) {
            return response()->json([
                'success' => false,
                'code' => 'NOT_SEARCHING',
                'status' => $status,
                'message' => 'الطلب لم يعد بانتظار سائق',
            ], 409);
        }

        $stage = (int) $v['stage'];
        $result = app(\App\Services\ImmediateDriverNotifier::class)->expandToStage($req, $stage);

        return response()->json([
            'success' => true,
            'data' => $result + ['stage' => $stage],
        ]);
    }

    /**
     * انتهاء مهلة البحث في شاشة الراكب دون قبول: يُلغى الطلب فقط إن كان ما زال بانتظار سائق.
     * إن قبله سائق في اللحظة الأخيرة يُعاد status=Reserved ولا يُلغى شيء.
     */
    public function searchTimeout(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        DB::beginTransaction();
        try {
            $req = RequestModel::whereKey($requestId)->lockForUpdate()->first();
            if (! $req || (int) $req->userId !== (int) $user->id) {
                DB::rollBack();

                return response()->json(['success' => false, 'message' => 'Request not found'], 404);
            }

            if ($req->status !== RequestModel::STATUS_PENDING || $req->driverId !== null) {
                DB::rollBack();

                return response()->json([
                    'success' => true,
                    'data' => [
                        'cancelled' => false,
                        'status' => RequestModel::normalizeTripStatus($req->status),
                    ],
                ]);
            }

            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = 'no_driver_found';
            $req->save();
            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json(['success' => false, 'message' => 'An error occurred: '.$e->getMessage()], 500);
        }

        try {
            Redis::del('request:'.$req->id.':eligible');
        } catch (\Throwable $e) {
        }
        try {
            RequestDriverOffer::where('request_id', $req->id)->delete();
        } catch (\Throwable $e) {
        }
        $this->releaseCouponForRequest((int) $req->id);
        DriverPollCacheService::bust();

        return response()->json([
            'success' => true,
            'data' => ['cancelled' => true, 'status' => RequestModel::STATUS_REMOVED],
        ]);
    }

    /**
     * إلغاء طلب عالق — للسائق أو الراكب (قبل بدء الرحلة فعلياً).
     */
    public function abortActiveTrip(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $isDriver = $user->roll === 'Driver';
        $isCustomer = $user->roll === 'Customer';
        if (! $isDriver && ! $isCustomer) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        DB::beginTransaction();
        try {
            $req = RequestModel::whereKey($requestId)->lockForUpdate()->first();
            if (! $req) {
                DB::rollBack();

                return response()->json(['success' => false, 'message' => 'Request not found'], 404);
            }

            if ($isCustomer && (int) $req->userId !== (int) $user->id) {
                DB::rollBack();

                return response()->json(['success' => false, 'message' => 'Request not found'], 404);
            }

            $assignedDriverId = $req->driverId ? (int) $req->driverId : null;
            if ($isDriver) {
                $driver = Driver::where('userId', $user->id)->first();
                if (! $driver || $assignedDriverId === null || $assignedDriverId !== (int) $driver->id) {
                    DB::rollBack();

                    return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
                }
            }

            if (! RequestModel::canAbortTrip($req)) {
                $status = RequestModel::normalizeTripStatus($req->status);
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'لا يمكن إلغاء الطلب في هذه المرحلة ('.($status !== '' ? $status : 'غير معروف').')',
                ], 400);
            }

            $reason = trim((string) $request->input('reason', ''));
            if ($isCustomer
                && $reason === 'abandoned_on_reopen'
                && RequestModel::isAdminDispatched($req)) {
                DB::rollBack();

                return response()->json([
                    'success' => true,
                    'skipped' => true,
                    'message' => 'طلب إداري — لم يُلغَ',
                ]);
            }

            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = $reason !== ''
                ? $reason
                : ($isDriver ? 'driver_abort' : 'customer_abort');
            if ($isDriver) {
                $req->driver_cancelled_at = now();
            }
            $req->save();

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        try {
            Redis::del('request:'.$req->id.':eligible');
        } catch (\Throwable $e) {
        }
        try {
            RequestDriverOffer::where('request_id', $req->id)->delete();
        } catch (\Throwable $e) {
        }

        $this->releaseCouponForRequest((int) $req->id);

        if ($assignedDriverId && $isCustomer) {
            try {
                broadcast(new RequestCancelledByCustomerEvent($assignedDriverId, (int) $req->id));
            } catch (\Throwable $e) {
            }
        }

        DriverPollCacheService::bust();

        return response()->json([
            'success' => true,
            'data' => $req->fresh(['startLocation', 'destLocation', 'driver.user', 'user']),
            'message' => 'تم إلغاء الطلب',
        ]);
    }

    /**
     * رفض الطلب الفوري من السائق (زر «تجاهل») — إلغاء الطلب وإشعار الزبون.
     */
    /**
     * إلغاء حجز مسبق بعد قبول السائق — يتطلب اعتذاراً يُحفظ ويُسجَّل مخالفة على السائق.
     */
    public function driverCancelScheduled(HttpRequest $request, int $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $v = $request->validate([
            'apology' => 'required|string|min:15|max:2000',
        ]);

        $req = RequestModel::find($requestId);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_SCHEDULE) {
            return response()->json(['success' => false, 'message' => 'ليس حجزاً مسبقاً'], 400);
        }

        if ((int) $req->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if ($req->status !== RequestModel::STATUS_RESERVED) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إلغاء الحجز في هذه المرحلة (بعد بدء التوجه أو الرحلة).',
            ], 400);
        }

        if ($req->sched_driver_started_at) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن الإلغاء بعد بدء التوجه للراكب.',
            ], 400);
        }

        DB::beginTransaction();
        try {
            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = 'driver_cancelled_scheduled';
            $req->driver_cancel_apology = trim($v['apology']);
            $req->driver_cancelled_at = now();
            $req->save();

            $driver->scheduled_cancel_strikes = (int) ($driver->scheduled_cancel_strikes ?? 0) + 1;
            $driver->save();

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => 'اعتذر السائق عن الحجز',
                'body' => 'ألغى السائق حجزك المسبق مع اعتذار. يمكنك إنشاء حجز جديد.',
                'kind' => 'sched.driver_cancelled',
                'reference_type' => 'request',
                'reference_id' => $req->id,
                'payload' => [
                    'kind' => 'sched.driver_cancelled',
                    'request_id' => $req->id,
                ],
            ]);
        } catch (\Throwable $e) {
        }

        $this->releaseCouponForRequest((int) $req->id);

        return response()->json([
            'success' => true,
            'message' => 'تم إلغاء الحجز وتسجيل الاعتذار.',
            'data' => [
                'request' => $req->fresh(['startLocation', 'destLocation']),
                'scheduled_cancel_strikes' => (int) $driver->scheduled_cancel_strikes,
            ],
        ]);
    }

    /**
     * إلغاء الطلب من السائق بعد القبول وقبل الوصول للراكب (حالة Reserved فقط).
     */
    public function driverCancelEnRoute(HttpRequest $request, int $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $req = RequestModel::find($requestId);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ((int) $req->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if (! RequestModel::canAbortTrip($req)) {
            $status = RequestModel::normalizeTripStatus($req->status);
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن الإلغاء في هذه المرحلة ('.($status !== '' ? $status : 'غير معروف').')',
            ], 400);
        }

        if ($req->type === RequestModel::TYPE_SCHEDULE && ! $req->sched_driver_started_at) {
            return response()->json([
                'success' => false,
                'message' => 'استخدم إلغاء الحجز المسبق مع الاعتذار.',
            ], 400);
        }

        DB::beginTransaction();
        try {
            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = 'driver_cancelled_en_route';
            $req->driver_cancelled_at = now();
            $reason = trim((string) $request->input('reason', ''));
            if ($reason !== '') {
                $req->driver_cancel_apology = $reason;
            }
            $req->save();

            RequestDriverOffer::where('request_id', $req->id)->delete();
            try {
                Redis::del('request:'.$req->id.':eligible');
            } catch (\Throwable $e) {
            }

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => 'ألغى السائق الطلب',
                'body' => 'اعتذر السائق عن الرحلة قبل الوصول. يمكنك إرسال طلب جديد.',
                'kind' => 'trip.driver_cancelled_en_route',
                'reference_type' => 'request',
                'reference_id' => $req->id,
                'payload' => [
                    'kind' => 'trip.driver_cancelled_en_route',
                    'request_id' => $req->id,
                ],
            ]);
        } catch (\Throwable $e) {
        }

        DriverPollCacheService::bust();

        $this->releaseCouponForRequest((int) $req->id);

        return response()->json([
            'success' => true,
            'message' => 'تم إلغاء الطلب.',
            'data' => [
                'request' => $req->fresh(['startLocation', 'destLocation']),
            ],
        ]);
    }

    public function driverDeclineImmediate(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $driverId = (int) $driver->id;
        $rid = (int) $requestId;

        $req = RequestModel::find($rid);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_IMMEDIATE) {
            return response()->json(['success' => false, 'message' => 'Not an immediate request'], 400);
        }

        if ($req->status !== RequestModel::STATUS_PENDING) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن رفض هذا الطلب في حالته الحالية',
            ], 400);
        }

        if ($req->driverId !== null && (int) $req->driverId !== $driverId) {
            return response()->json([
                'success' => false,
                'message' => 'هذا الطلب موجّه لسائق آخر',
            ], 403);
        }

        if ($req->driverId === null) {
            $eligibleKey = 'request:'.$req->id.':eligible';
            try {
                if (Redis::exists($eligibleKey) && ! Redis::sismember($eligibleKey, (string) $driverId)) {
                    return response()->json([
                        'success' => false,
                        'message' => 'غير مدرج ضمن نطاق هذا الطلب',
                    ], 403);
                }
                Redis::srem($eligibleKey, (string) $driverId);
                $ignoredKey = \App\Services\ImmediateDriverNotifier::ignoredKey((int) $req->id);
                Redis::sadd($ignoredKey, (string) $driverId);
                Redis::expire($ignoredKey, 3600);
            } catch (\Throwable $e) {
            }
            try {
                RequestDriverOffer::where('request_id', $req->id)
                    ->where('driver_id', $driverId)
                    ->delete();
            } catch (\Throwable $e) {
            }

            return response()->json([
                'success' => true,
                'message' => 'تم تجاهل الطلب',
                'data' => ['ignored' => true],
            ]);
        }

        DB::beginTransaction();
        try {
            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = 'driver_declined_immediate';
            $req->save();

            RequestDriverOffer::where('request_id', $req->id)->delete();

            try {
                Redis::del('request:'.$req->id.':eligible');
            } catch (\Throwable $e) {
            }

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        $this->releaseCouponForRequest((int) $req->id);

        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => 'اعتذر السائق عن الطلب الفوري',
                'body' => 'يمكنك إعادة إرسال الطلب أو اختيار سائق آخر.',
                'kind' => 'immediate.driver_declined',
                'reference_type' => 'request',
                'reference_id' => $req->id,
                'payload' => [
                    'kind' => 'immediate.driver_declined',
                    'request_id' => $req->id,
                ],
            ]);
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إلغاء الطلب؛ سيُبلّغ الزبون لإعادة الإرسال أو اختيار سائق آخر.',
            'data' => ['request' => $req->fresh(['startLocation', 'destLocation'])],
        ]);
    }

    /**
     * رفض حجز مسبق معلّق (Pending) من السائق المختار —
     * يُفرَّغ السائق ويبقى الطلب معلّقاً ليختار الزبون سائقاً آخر.
     */
    public function driverDeclineScheduled(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $req = RequestModel::find((int) $requestId);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_SCHEDULE) {
            return response()->json(['success' => false, 'message' => 'ليس حجزاً مسبقاً'], 400);
        }

        if ($req->status !== RequestModel::STATUS_PENDING) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن رفض الحجز بعد القبول — استخدم إلغاء الحجز مع اعتذار',
            ], 400);
        }

        if ($req->driverId === null || (int) $req->driverId !== (int) $driver->id) {
            return response()->json([
                'success' => false,
                'message' => 'هذا الحجز غير موجّه إليك',
            ], 403);
        }

        DB::beginTransaction();
        try {
            $req->driverId = null;
            $req->cancel_reason = 'driver_declined_scheduled';
            $req->status = RequestModel::STATUS_PENDING;
            $req->save();
            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'An error occurred: '.$e->getMessage(),
            ], 500);
        }

        DriverPollCacheService::bust();

        $when = $req->requestDate
            ? $req->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i')
            : '';
        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => 'اعتذر السائق عن الحجز المسبق',
                'body' => $when !== ''
                    ? "رفض السائق حجزك للموعد {$when}. اختر سائقاً آخر قريباً ومتاحاً."
                    : 'رفض السائق حجزك المسبق. اختر سائقاً آخر قريباً ومتاحاً.',
                'kind' => 'sched_rejected',
                'reference_type' => 'request',
                'reference_id' => $req->id,
                'payload' => [
                    'kind' => 'sched_rejected',
                    'request_id' => $req->id,
                ],
            ]);
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'message' => 'تم رفض الحجز وإبلاغ الزبون لاختيار سائق آخر.',
            'data' => ['request' => $req->fresh(['startLocation', 'destLocation'])],
        ]);
    }

    /**
     * طلبات فورية معلّقة للسائق (استطلاع من التطبيق بدل WebSocket)
     */
    public function getPendingImmediate(HttpRequest $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $driverId = (int) $driver->id;
        $cacheKey = DriverPollCacheService::immediatePendingKey($driverId);

        $filtered = Cache::remember($cacheKey, DriverPollCacheService::TTL_IMMEDIATE, function () use ($driver) {
            return ImmediatePendingForDriver::queryForDriver($driver)
                ->map(fn ($m) => ImmediatePendingForDriver::toDriverPayload($driver, $m))
                ->values()
                ->all();
        });

        DriverPollCacheService::rememberImmediateLast($driverId, $filtered);

        return response()->json([
            'success' => true,
            'data' => $filtered,
        ]);
    }

    /**
     * Get passenger requests
     */
    public function getUserRequests(HttpRequest $request, $userId)
    {
        if ((int) $request->user()->id !== (int) $userId) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $requests = RequestModel::where('userId', $userId)
            ->with(['history.driver.user', 'driver.user', 'carType', 'startLocation', 'destLocation'])
            ->withExists([
                'complaints as has_complaint',
            ])
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $requests,
            'message' => 'Requests retrieved successfully',
        ]);
    }

    /**
     * رحلة الزبون النشطة فقط — خفيف بدل جلب كل السجل في كل استطلاع.
     */
    public function customerActiveTrip(HttpRequest $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $activeStatuses = [
            RequestModel::STATUS_PENDING,
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
            RequestModel::STATUS_RUNNING,
        ];

        $candidates = RequestModel::query()
            ->where('userId', $user->id)
            ->whereIn('status', $activeStatuses)
            ->where(function ($q) {
                $q->whereNull('billing_kind')
                    ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
            })
            ->with(['history.driver.user', 'driver.user', 'carType', 'startLocation', 'destLocation'])
            ->orderByDesc('updated_at')
            ->limit(8)
            ->get();

        $active = null;
        foreach ($candidates as $req) {
            $st = RequestModel::normalizeTripStatus($req->status);
            $isSched = $req->type === RequestModel::TYPE_SCHEDULE;
            if ($isSched && $st === RequestModel::STATUS_PENDING) {
                continue;
            }
            if ($isSched && $st === RequestModel::STATUS_RESERVED) {
                // مطابق لـ scheduledTripLiveOnMap: يظهر بعد بدء توجه السائق فقط.
                if (! $req->sched_driver_started_at) {
                    continue;
                }
            }
            $active = $req;
            break;
        }

        try {
            \App\Services\CustomerPresenceService::markOnline((int) $user->id);
            $latIn = $request->input('latitude', $request->input('lat'));
            $lngIn = $request->input('longitude', $request->input('lng'));
            if ($latIn !== null && $lngIn !== null) {
                \App\Services\CustomerPresenceService::touch(
                    (int) $user->id,
                    (float) $latIn,
                    (float) $lngIn,
                );
            } elseif ($active && $active->startLocation) {
                $lat = (float) ($active->startLocation->latitude ?? 0);
                $lng = (float) ($active->startLocation->longitude ?? 0);
                if ($lat != 0.0 || $lng != 0.0) {
                    \App\Services\CustomerPresenceService::touch((int) $user->id, $lat, $lng);
                }
            }
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => $active,
            'upcoming_scheduled' => $this->customerUpcomingScheduled((int) $user->id),
            'message' => $active ? 'Active trip' : 'No active trip',
        ]);
    }

    /** حجوزات مسبقة مقبولة لم ينطلق السائق إليها بعد — لأيقونة الحجز عند الراكب. */
    private function customerUpcomingScheduled(int $userId): array
    {
        try {
            return RequestModel::query()
                ->where('userId', $userId)
                ->where('type', RequestModel::TYPE_SCHEDULE)
                ->where('status', RequestModel::STATUS_RESERVED)
                ->whereNull('sched_driver_started_at')
                ->whereNotNull('driverId')
                ->with(['driver.user', 'carType', 'startLocation', 'destLocation'])
                ->orderBy('requestDate')
                ->limit(5)
                ->get()
                ->map(function (RequestModel $r) {
                    $driverUser = $r->driver?->user;

                    return [
                        'id' => (int) $r->id,
                        'type' => $r->type,
                        'status' => $r->status,
                        'requestDate' => $r->requestDate
                            ? $r->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i:s')
                            : null,
                        'request_date_ms' => $r->request_date_ms,
                        'sched_go_window_open' => RequestModel::schedGoWindowOpen($r),
                        'predectedCost' => $r->predectedCost,
                        'driver_name' => $driverUser
                            ? trim(($driverUser->firstName ?? '').' '.($driverUser->lastName ?? ''))
                            : null,
                        'car_category_name' => $r->carType?->name,
                        'startLocation' => $r->startLocation,
                        'destLocation' => $r->destLocation,
                    ];
                })
                ->values()
                ->all();
        } catch (\Throwable $e) {
            return [];
        }
    }

    /**
     * Get driver trips
     */
    public function getDriverTrips(HttpRequest $request, $driverId)
    {
        $driver = Driver::where('userId', $request->user()->id)->first();

        if (! $driver || (int) $driver->id !== (int) $driverId) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $tripsQuery = RequestHistory::where('driverId', $driverId)
            ->whereHas('request', function ($q) use ($request) {
                $q->where('status', RequestModel::STATUS_FINISHED);
                if ($request->filled('from_date')) {
                    $from = Carbon::parse($request->input('from_date'))->startOfDay();
                    $q->where(function ($inner) use ($from) {
                        $inner->whereDate('trip_started_at', '>=', $from)
                            ->orWhere(function ($o) use ($from) {
                                $o->whereNull('trip_started_at')
                                    ->whereDate('requestDate', '>=', $from);
                            });
                    });
                }
                if ($request->filled('to_date')) {
                    $to = Carbon::parse($request->input('to_date'))->endOfDay();
                    $q->where(function ($inner) use ($to) {
                        $inner->whereDate('trip_started_at', '<=', $to)
                            ->orWhere(function ($o) use ($to) {
                                $o->whereNull('trip_started_at')
                                    ->whereDate('requestDate', '<=', $to);
                            });
                    });
                }
            })
            ->with(['request' => function ($q) {
                $q->with(['user', 'startLocation', 'destLocation', 'carType']);
            }])
            ->orderBy('created_at', 'desc');

        $trips = $tripsQuery->get();

        return response()->json([
            'success' => true,
            'data' => $trips,
            'message' => 'Trips retrieved successfully'
        ]);
    }

    /**
     * Send reminder notification to driver before booking time
     */
    public function remindDriver($requestId)
    {
        $request = RequestModel::find($requestId);

        if (!$request) {
            return response()->json([
                'success' => false,
                'message' => 'Request not found'
            ], 404);
        }

        $history = RequestHistory::where('requestId', $requestId)->first();

        if (!$history) {
            return response()->json([
                'success' => false,
                'message' => 'No driver associated with this booking'
            ], 404);
        }

        // Send reminder notification to driver
        // Notification::send($history->driver, new TripReminder($request));

        return response()->json([
            'success' => true,
            'message' => 'Reminder sent to driver successfully'
        ]);
    }

    public function immediateStatus(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::with(['startLocation', 'destLocation', 'carType', 'driverOffers.driver.user'])
            ->find($requestId);

        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->type !== RequestModel::TYPE_IMMEDIATE
            && $req->type !== RequestModel::TYPE_SCHEDULE) {
            return response()->json(['success' => false, 'message' => 'Not a searchable request'], 400);
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
                $d = Driver::with(['user', 'transType'])->find($did);
                if (! $d) {
                    continue;
                }
                if (! $this->isDriverOnline($did)) {
                    continue;
                }
                $km = $this->distanceKmToPickup($req, $did);
                $eligibleDrivers[] = $this->driverPayloadForCustomer($d, $km, $req);
            }
        }

        usort($eligibleDrivers, fn ($a, $b) => ($a['distance_from_pickup_km'] ?? 9999) <=> ($b['distance_from_pickup_km'] ?? 9999));

        $offers = [];
        foreach ($req->driverOffers as $offer) {
            $d = $offer->driver;
            if (! $d) {
                continue;
            }
            $d->loadMissing(['user', 'transType']);
            $km = $this->distanceKmToPickup($req, (int) $d->id);
            $row = $this->driverPayloadForCustomer($d, $km, $req);
            $row['offered_at'] = $offer->created_at?->toIso8601String();
            $offers[] = $row;
        }

        return response()->json([
            'success' => true,
            'data' => [
                'request' => $req,
                'selected_driver_id' => $req->driverId,
                'eligible_drivers' => $eligibleDrivers,
                'offers' => $offers,
            ],
        ]);
    }

    public function selectDriver(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'driverId' => 'required|integer',
            'estimatedDurationMinutes' => 'nullable|numeric|min:0|max:10080',
        ]);

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->status !== RequestModel::STATUS_PENDING) {
            return response()->json([
                'success' => false,
                'message' => 'Cannot select driver for this request state',
            ], 400);
        }

        // فوري: اختيار أثناء الانتظار. مسبق: إعادة اختيار بعد رفض سائق (driverId فارغ).
        if ($req->type === RequestModel::TYPE_IMMEDIATE) {
            // ok
        } elseif ($req->type === RequestModel::TYPE_SCHEDULE) {
            if ($req->driverId !== null) {
                return response()->json([
                    'success' => false,
                    'message' => 'الحجز موجّه لسائق آخر حالياً — انتظر الرد أو ألغِ الحجز',
                ], 400);
            }
        } else {
            return response()->json([
                'success' => false,
                'message' => 'Cannot select driver for this request type',
            ], 400);
        }

        $driverId = (int) $v['driverId'];
        $driver = Driver::with('transType')->find($driverId);
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver not found'], 404);
        }

        if ($req->type === RequestModel::TYPE_SCHEDULE) {
            if (! $this->isDriverOnline($driverId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'السائق غير متصل حالياً',
                ], 422);
            }
        }

        if ($this->isDriverBusy($driverId, (int) $req->id)) {
            return response()->json([
                'success' => false,
                'message' => 'السائق مشغول برحلة أخرى',
            ], 422);
        }

        // نحتاج الإحداثيات لحساب التكلفة التقديرية
        $req->loadMissing(['startLocation', 'destLocation']);

        // إذا كانت هناك مجموعة eligible على Redis، لا تسمح باختيار سائق خارجها
        $eligibleKey = 'request:'.$req->id.':eligible';
        if ($req->type === RequestModel::TYPE_IMMEDIATE
            && Redis::exists($eligibleKey)
            && ! Redis::sismember($eligibleKey, (string) $driverId)) {
            return response()->json([
                'success' => false,
                'message' => 'هذا السائق خارج نطاق الطلب الحالي',
            ], 422);
        }

        // تحقق بسيط من تطابق نوع السيارة إن كان متاحاً
        if ($driver->transTypeId !== null && $req->carTypeId !== null
            && ! CarType::driverServesRequestType((int) $driver->transTypeId, (int) $req->carTypeId)) {
            return response()->json([
                'success' => false,
                'message' => 'نوع مركبة السائق لا يطابق نوع الطلب',
            ], 422);
        }

        $durOverride = $this->normalizeEstimatedDurationMinutesInput($v['estimatedDurationMinutes'] ?? null);

        DB::beginTransaction();
        try {
            $locked = RequestModel::whereKey($req->id)->lockForUpdate()->first();
            if (! $locked || (int) $locked->userId !== (int) $user->id) {
                DB::rollBack();

                return response()->json(['success' => false, 'message' => 'Request not found'], 404);
            }

            if ($locked->status !== RequestModel::STATUS_PENDING) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'Cannot select driver for this request state',
                ], 400);
            }

            if ($locked->type === RequestModel::TYPE_SCHEDULE && $locked->driverId !== null) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'الحجز موجّه لسائق آخر حالياً — انتظر الرد أو ألغِ الحجز',
                ], 400);
            }

            if ($this->isDriverBusy($driverId, (int) $locked->id)) {
                DB::rollBack();

                return response()->json([
                    'success' => false,
                    'message' => 'السائق مشغول برحلة أخرى',
                ], 422);
            }

            $locked->driverId = $driverId;
            // يبقى Pending حتى يقبل السائق
            $locked->status = RequestModel::STATUS_PENDING;
            if ($locked->type === RequestModel::TYPE_SCHEDULE) {
                $locked->cancel_reason = null;
            }

            if ($locked->startLocation && $locked->destLocation) {
                $this->refreshAppTripPredictedCostForDriver($locked, $driver, $locked->startLocation, $locked->destLocation, $durOverride);
            } else {
                $locked->loadMissing(['startLocation', 'destLocation']);
                if ($locked->startLocation && $locked->destLocation) {
                    $this->refreshAppTripPredictedCostForDriver($locked, $driver, $locked->startLocation, $locked->destLocation, $durOverride);
                }
            }
            $locked->save();
            $req = $locked;

            // نظف عروض الاهتمام القديمة (لم تعد جزءاً من التدفق الجديد)
            try {
                RequestDriverOffer::where('request_id', $req->id)->delete();
            } catch (\Throwable $e) {}

            // ضيّق eligible لهذا السائق حتى لا يرى الطلب غيره
            try {
                Redis::del($eligibleKey);
                Redis::sadd($eligibleKey, [(string) $driverId]);
                Redis::expire($eligibleKey, 60 * 60); // ساعة
            } catch (\Throwable $e) {}

            DB::commit();
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 500);
        }

        // إشعار/بث للسائق المختار (لو كان WebSocket مفعّلاً)
        try {
            broadcast(new NewRequestEvent($driverId, $req->id));
        } catch (\Throwable $e) {}

        if ($req->type === RequestModel::TYPE_SCHEDULE) {
            $when = $req->requestDate
                ? $req->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i')
                : '';
            $this->createDriverNotification(
                (int) $driver->userId,
                'طلب حجز مسبق',
                $when !== ''
                    ? "وصلك طلب حجز مسبق للموعد {$when}. راجع «الحجوزات المسبقة» للقبول."
                    : 'وصلك طلب حجز مسبق جديد. راجع «الحجوزات المسبقة» للقبول.',
                'sched_assigned',
                (int) $req->id
            );
        }

        DriverPollCacheService::bust();

        return response()->json([
            'success' => true,
            'data' => $req->fresh(['startLocation', 'destLocation']),
            'message' => $req->type === RequestModel::TYPE_SCHEDULE
                ? 'تم إرسال الحجز للسائق الجديد — بانتظار قبوله'
                : 'تم إرسال الطلب للسائق — بانتظار قبوله',
        ]);
    }

    /**
     * موقع السائق الحالي للزبون (Redis GEO) أثناء الرحلة المحجوزة أو الجارية.
     */
    public function customerTripTracking(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        $driverId = $req->driverId ? (int) $req->driverId : null;
        $status = $req->status;

        $trackCacheKey = 'customer_track:'.$requestId.':'.$status;
        // السائق يتحرك (بالطريق/واصل/جارية): موقع حي من Redis بلا كاش حتى لا تقفز السيارة.
        $liveTrack = in_array($status, [
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
            RequestModel::STATUS_RUNNING,
        ], true);
        if (! $liveTrack) {
            try {
                $cachedTrack = Cache::get($trackCacheKey);
                if (is_array($cachedTrack)) {
                    return response()->json([
                        'success' => true,
                        'data' => $cachedTrack,
                    ]);
                }
            } catch (\Throwable $e) {
            }
        }

        if (! in_array($status, [
            RequestModel::STATUS_PENDING,
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
            RequestModel::STATUS_RUNNING,
        ], true) || ! $driverId) {
            return response()->json([
                'success' => true,
                'data' => [
                    'status' => $status,
                    'driver_id' => $driverId,
                    'driver_position' => null,
                ],
            ]);
        }

        $pos = $this->coordsFromRedisDriver($driverId);

        $liveMeter = null;
        if ($status === RequestModel::STATUS_RUNNING) {
            try {
                $raw = Redis::get('request:'.$req->id.':live_meter');
                if (is_string($raw) && $raw !== '') {
                    $decoded = json_decode($raw, true);
                    if (is_array($decoded)) {
                        $liveMeter = $decoded;
                    }
                }
            } catch (\Throwable $e) {
            }
        }

        $payload = [
            'status' => $status,
            'driver_id' => $driverId,
            'driver_position' => $pos
                ? ['lat' => $pos['lat'], 'lng' => $pos['lng']]
                : null,
            'live_meter' => $liveMeter,
            'server_ts' => now()->toIso8601String(),
            'server_ts_ms' => (int) round(microtime(true) * 1000),
        ];

        try {
            if (! $liveTrack) {
                Cache::put($trackCacheKey, $payload, 5);
            }
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => $payload,
        ]);
    }

    /**
     * السائق يُرسل لقطة العداد الحي أثناء رحلة التطبيق (Running).
     */
    public function reportLiveMeter(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->driverId !== (int) $driver->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        if ($req->status !== RequestModel::STATUS_RUNNING) {
            return response()->json(['success' => false, 'message' => 'Cannot report meter at this status'], 400);
        }

        $v = $request->validate([
            'finalCost' => 'required|numeric|min:0',
            'distanceTraveledKm' => 'sometimes|numeric|min:0',
            'distance_traveled_km' => 'sometimes|numeric|min:0',
            'billedWaitingMinutes' => 'sometimes|integer|min:0',
            'billed_waiting_minutes' => 'sometimes|integer|min:0',
            'waitingSeconds' => 'sometimes|integer|min:0|max:59',
            'waiting_seconds' => 'sometimes|integer|min:0|max:59',
            'meterElapsedSeconds' => 'sometimes|integer|min:0',
            'meter_elapsed_seconds' => 'sometimes|integer|min:0',
            'isMoving' => 'sometimes|boolean',
            'openPrice' => 'sometimes|numeric|min:0',
            'open_price' => 'sometimes|numeric|min:0',
            'kmPrice' => 'sometimes|numeric|min:0',
            'km_price' => 'sometimes|numeric|min:0',
            'timePrice' => 'sometimes|numeric|min:0',
            'time_price' => 'sometimes|numeric|min:0',
            'zoneMultiplier' => 'sometimes|numeric|min:0.1|max:20',
            'zoneLabel' => 'sometimes|nullable|string|max:160',
        ]);

        $payload = [
            'finalCost' => round((float) $v['finalCost'], 2),
            'zoneMultiplier' => round((float) ($v['zoneMultiplier'] ?? 1), 3),
            'zoneLabel' => (string) ($v['zoneLabel'] ?? ''),
            'distanceTraveledKm' => round((float) ($v['distanceTraveledKm'] ?? $v['distance_traveled_km'] ?? 0), 3),
            'billedWaitingMinutes' => (int) ($v['billedWaitingMinutes'] ?? $v['billed_waiting_minutes'] ?? 0),
            'waitingSeconds' => (int) ($v['waitingSeconds'] ?? $v['waiting_seconds'] ?? 0),
            'meterElapsedSeconds' => (int) ($v['meterElapsedSeconds'] ?? $v['meter_elapsed_seconds'] ?? 0),
            'isMoving' => $request->boolean('isMoving'),
            'openPrice' => round((float) ($v['openPrice'] ?? $v['open_price'] ?? 0), 2),
            'kmPrice' => round((float) ($v['kmPrice'] ?? $v['km_price'] ?? 0), 2),
            'timePrice' => round((float) ($v['timePrice'] ?? $v['time_price'] ?? 0), 2),
            'updated_at' => now()->toIso8601String(),
            'updated_at_ms' => (int) round(microtime(true) * 1000),
        ];

        $meterKey = 'request:'.$req->id.':live_meter';
        $throttleKey = 'throttle_live_meter:'.$req->id;

        try {
            $existingRaw = Redis::get($meterKey);
            if (is_string($existingRaw) && $existingRaw !== '') {
                $existing = json_decode($existingRaw, true);
                if (is_array($existing)
                    && abs((float) ($existing['finalCost'] ?? 0) - $payload['finalCost']) < 0.01
                    && abs((float) ($existing['distanceTraveledKm'] ?? 0) - $payload['distanceTraveledKm']) < 0.02
                    && (int) ($existing['billedWaitingMinutes'] ?? 0) === $payload['billedWaitingMinutes']
                    && (int) ($existing['waitingSeconds'] ?? 0) === $payload['waitingSeconds']
                    && (int) ($existing['meterElapsedSeconds'] ?? 0) === $payload['meterElapsedSeconds']
                    && (bool) ($existing['isMoving'] ?? false) === $payload['isMoving']) {
                    return response()->json([
                        'success' => true,
                        'data' => $existing,
                        'cached' => true,
                    ]);
                }
                // التكلفة/المسافة نفسها لكن الزمن تغيّر — حدّث الساعة والحركة دائماً.
                if (is_array($existing)
                    && abs((float) ($existing['finalCost'] ?? 0) - $payload['finalCost']) < 0.01
                    && abs((float) ($existing['distanceTraveledKm'] ?? 0) - $payload['distanceTraveledKm']) < 0.02
                    && (int) ($existing['billedWaitingMinutes'] ?? 0) === $payload['billedWaitingMinutes']) {
                    $merged = array_merge($existing, [
                        'zoneMultiplier' => $payload['zoneMultiplier'],
                        'zoneLabel' => $payload['zoneLabel'],
                        'waitingSeconds' => $payload['waitingSeconds'],
                        'meterElapsedSeconds' => $payload['meterElapsedSeconds'],
                        'isMoving' => $payload['isMoving'],
                        'openPrice' => $payload['openPrice'] > 0 ? $payload['openPrice'] : ($existing['openPrice'] ?? 0),
                        'kmPrice' => $payload['kmPrice'] > 0 ? $payload['kmPrice'] : ($existing['kmPrice'] ?? 0),
                        'timePrice' => $payload['timePrice'] > 0 ? $payload['timePrice'] : ($existing['timePrice'] ?? 0),
                        'updated_at' => $payload['updated_at'],
                        'updated_at_ms' => $payload['updated_at_ms'],
                    ]);
                    Redis::setex($meterKey, 180, json_encode($merged));
                    Cache::forget('customer_track:'.$req->id.':'.RequestModel::STATUS_RUNNING);

                    return response()->json([
                        'success' => true,
                        'data' => $merged,
                        'clock_only' => true,
                    ]);
                }
            }
        } catch (\Throwable $e) {
        }

        if (Cache::has($throttleKey)) {
            try {
                // حتى مع الـ throttle حدّث حقول الزمن إن وصلت.
                $existingRaw = Redis::get($meterKey);
                if (is_string($existingRaw) && $existingRaw !== '') {
                    $existing = json_decode($existingRaw, true);
                    if (is_array($existing)) {
                        $merged = array_merge($existing, [
                            'finalCost' => $payload['finalCost'],
                            'zoneMultiplier' => $payload['zoneMultiplier'],
                            'zoneLabel' => $payload['zoneLabel'],
                            'distanceTraveledKm' => $payload['distanceTraveledKm'],
                            'billedWaitingMinutes' => $payload['billedWaitingMinutes'],
                            'waitingSeconds' => $payload['waitingSeconds'],
                            'meterElapsedSeconds' => $payload['meterElapsedSeconds'],
                            'isMoving' => $payload['isMoving'],
                            'updated_at' => $payload['updated_at'],
                            'updated_at_ms' => $payload['updated_at_ms'],
                        ]);
                        if ($payload['openPrice'] > 0) {
                            $merged['openPrice'] = $payload['openPrice'];
                        }
                        if ($payload['kmPrice'] > 0) {
                            $merged['kmPrice'] = $payload['kmPrice'];
                        }
                        if ($payload['timePrice'] > 0) {
                            $merged['timePrice'] = $payload['timePrice'];
                        }
                        Redis::setex($meterKey, 180, json_encode($merged));
                        Cache::forget('customer_track:'.$req->id.':'.RequestModel::STATUS_RUNNING);

                        return response()->json([
                            'success' => true,
                            'data' => $merged,
                            'throttled' => true,
                        ]);
                    }
                }
            } catch (\Throwable $e) {
            }
        }

        try {
            Redis::setex($meterKey, 180, json_encode($payload));
            Cache::put($throttleKey, 1, 1);
            Cache::forget('customer_track:'.$req->id.':'.RequestModel::STATUS_RUNNING);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'تعذر حفظ العداد',
            ], 503);
        }

        return response()->json([
            'success' => true,
            'data' => $payload,
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

    private function distanceKmToPickup(RequestModel $req, int $driverId): ?float
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

    private function distanceKmDriverToPoint(int $driverId, float $pickLat, float $pickLng): ?float
    {
        $c = $this->coordsFromRedisDriver($driverId);
        if (! $c) {
            return null;
        }

        return round($this->haversineKm($pickLat, $pickLng, $c['lat'], $c['lng']), 2);
    }

    /** @param  ?float  $destLat  */
    private function driverPayloadForNearbyPreview(
        Driver $driver,
        ?float $kmToPickup,
        float $pickLat,
        float $pickLng,
        ?float $destLat,
        ?float $destLng,
        ?float $estimatedRouteMinutes = null,
        ?float $estimatedTripKm = null,
        ?CarType $pricingType = null
    ): array {
        $user = $driver->user;
        $name = $user ? trim(($user->firstName ?? '').' '.($user->lastName ?? '')) : '';

        $vehicleType = $driver->transType;
        $t = $pricingType ?? $vehicleType;
        $kmPrice = $t ? (float) ($t->KMPrice ?? 0) : null;
        $minutePrice = $t ? (float) ($t->timePrice ?? 0) : null;
        $est = null;
        if ($destLat !== null && $destLng !== null && $t !== null) {
            $tripKm = $estimatedTripKm ?? $this->haversineKm($pickLat, $pickLng, $destLat, $destLng);
            $minutes = $this->resolveTripMinutesForEstimate($estimatedRouteMinutes, null, $tripKm);
            $est = PricingZoneService::apply(
                $this->computeAppTripFare($t, $tripKm, $minutes),
                PricingZoneService::quote($pickLat, $pickLng, $destLat, $destLng)['multiplier'],
            );
        }

        return [
            'driverId' => $driver->id,
            'name' => $name !== '' ? $name : ('سائق #'.$driver->id),
            'number' => $user->number ?? null,
            'carNumber' => $driver->carNumber,
            'vehicle_model' => $driver->vehicle_model,
            'car_category_name' => $vehicleType ? (string) ($vehicleType->name ?? '') : '',
            'driver_photo_url' => Driver::publicUrlForStoragePath($driver->image),
            'car_photo_url' => Driver::publicUrlForStoragePath($driver->carImage),
            'distance_from_pickup_km' => $kmToPickup,
            'km_price' => $kmPrice,
            'minute_price' => $minutePrice,
            'estimated_cost' => $est,
        ];
    }

    private function driverPayloadForCustomer(Driver $driver, ?float $km, ?RequestModel $req = null): array
    {
        $user = $driver->user;
        $name = $user ? trim(($user->firstName ?? '').' '.($user->lastName ?? '')) : '';

        $vehicleType = $driver->transType;
        $t = ($req && $req->carTypeId ? CarType::find($req->carTypeId) : null) ?? $vehicleType;
        $kmPrice = $t ? (float) ($t->KMPrice ?? 0) : null;
        $minutePrice = $t ? (float) ($t->timePrice ?? 0) : null;
        $est = null;
        if ($req && $req->startLocation && $req->destLocation && $t !== null) {
            $tripKm = $this->haversineKm(
                (float) $req->startLocation->latitude,
                (float) $req->startLocation->longitude,
                (float) $req->destLocation->latitude,
                (float) $req->destLocation->longitude
            );
            $stored = $req->estimated_duration_minutes !== null ? (float) $req->estimated_duration_minutes : null;
            $minutes = $this->resolveTripMinutesForEstimate(null, $stored, $tripKm);
            $est = PricingZoneService::apply(
                $this->computeAppTripFare($t, $tripKm, $minutes),
                (float) ($req->zone_multiplier ?? 1) ?: 1.0,
            );
        }

        return [
            'driverId' => $driver->id,
            'name' => $name !== '' ? $name : ('سائق #'.$driver->id),
            'number' => $user->number ?? null,
            'carNumber' => $driver->carNumber,
            'vehicle_model' => $driver->vehicle_model,
            'car_category_name' => $vehicleType ? (string) ($vehicleType->name ?? '') : '',
            'driver_photo_url' => Driver::publicUrlForStoragePath($driver->image),
            'car_photo_url' => Driver::publicUrlForStoragePath($driver->carImage),
            'distance_from_pickup_km' => $km,
            'km_price' => $kmPrice,
            'minute_price' => $minutePrice,
            'estimated_cost' => $est,
        ];
    }

    private function notifyPassengerTripPush(
        int $userId,
        int $requestId,
        string $kind,
        string $title,
        string $body
    ): void {
        try {
            CustomerNotification::create([
                'user_id' => $userId,
                'title' => $title,
                'body' => $body,
                'kind' => $kind,
                'reference_type' => 'request',
                'reference_id' => $requestId,
                'payload' => [
                    'kind' => $kind,
                    'request_id' => $requestId,
                ],
            ]);
        } catch (\Throwable $e) {
        }

        try {
            $user = User::find($userId);
            if ($user && class_exists(FcmPushService::class)) {
                app(FcmPushService::class)->sendToUser($user, $title, $body, [
                    'kind' => $kind,
                    'type' => $kind,
                    'request_id' => (string) $requestId,
                ]);
            }
        } catch (\Throwable $e) {
        }
    }

    private function notifyPassengerSchedPayload(
        int $userId,
        int $requestId,
        string $kind,
        string $title,
        string $body
    ): void {
        $this->notifyPassengerTripPush($userId, $requestId, $kind, $title, $body);
    }

    /**
     * @param  int[]  $otherDriverIds
     */
    private function notifyOtherDriversImmediateTaken(array $otherDriverIds, int $requestId): void
    {
        foreach ($otherDriverIds as $did) {
            $d = Driver::find($did);
            if (! $d) {
                continue;
            }
            $this->createDriverNotification(
                (int) $d->userId,
                'تم قبول الطلب',
                'تم قبول الطلب من سائق آخر',
                'immediate.taken_by_other',
                $requestId
            );
        }
    }

    private function createDriverNotification(
        int $driverUserId,
        string $title,
        string $body,
        string $kind,
        int $requestId
    ): void {
        try {
            DriverNotification::create([
                'user_id' => $driverUserId,
                'title' => $title,
                'body' => $body,
                'kind' => $kind,
                'reference_type' => 'request',
                'reference_id' => $requestId,
                'payload' => [
                    'kind' => $kind,
                    'request_id' => $requestId,
                ],
            ]);
        } catch (\Throwable $e) {
        }
    }

    private function notifyDriverTripCancelledSummary(RequestModel $req, string $body): void
    {
        $driver = Driver::find($req->driverId);
        if (! $driver) {
            return;
        }
        $this->createDriverNotification(
            (int) $driver->userId,
            'تحديث الحجز',
            $body,
            'sched_trip_cancelled',
            (int) $req->id
        );
    }

    private static function maybeUpdateLocationLabel(Location $loc, string $name): void
    {
        $name = trim($name);
        if ($name === '') {
            return;
        }
        $current = trim((string) ($loc->name ?? ''));
        if ($current === '') {
            $loc->name = $name;
            $loc->save();
        }
    }
}
