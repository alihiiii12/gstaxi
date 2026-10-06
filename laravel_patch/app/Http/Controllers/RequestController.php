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
use App\Models\UsedDiscount;
use App\Http\Requests\StoreRequestRequest;
use App\Models\CarType;
use App\Models\Location;
use App\Models\CustomerNotification;
use App\Models\DriverNotification;
use App\Models\AppSetting;
use App\Services\DriverNearbyService;
use App\Services\DriverPollCacheService;
use App\Services\DriverSubscriptionService;
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

    private function isDriverBusy(int $driverId): bool
    {
        return in_array($driverId, $this->busyDriverIds(), true);
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
        $req->predectedCost = $this->computeAppTripFare($carType, $kmTrip, $minutes);
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
        $t = $driver->transType;
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
        $req->predectedCost = $this->computeAppTripFare($t, $kmTrip, $minutes);
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
        if ($request->type === RequestModel::TYPE_SCHEDULE
            && ($rawT === null || $rawT === '')) {
            return response()->json([
                'success' => false,
                'message' => 'يجب اختيار سائق للحجز المسبق',
            ], 422);
        }
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
            if ((int) $vd->transTypeId !== (int) $request['carTypeId']) {
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
            // enforce percentage-only coupons for taxi trips
            if ($discount->type !== Discount::TYPE_PERCENTAGE) {
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
            if (UsedDiscount::isUsedByUser($request->user()->id, $discount->id)) {
                return response()->json([
                    'success' => false,
                    'message' => 'You have already used this code',
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
                $kmEst = $this->haversineKm(
                    (float) $startLocation['latitude'],
                    (float) $startLocation['longitude'],
                    (float) $destLocation['latitude'],
                    (float) $destLocation['longitude'],
                );
            }
            $predectedForStore = (float) ($this->computeAppTripFare($carTypeForStore, $kmEst, $estDurNorm) ?? 0);
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
        ];
        $kmFromClient = (float) ($request->input('estimatedTripKm') ?? $request->input('estimated_trip_km') ?? 0);
        if ($kmFromClient <= 0 && isset($kmEst) && $kmEst > 0) {
            $kmFromClient = $kmEst;
        }
        if ($kmFromClient > 0 && \Illuminate\Support\Facades\Schema::hasColumn('requests', 'estimated_distance_km')) {
            $createPayload['estimated_distance_km'] = round($kmFromClient, 3);
        }

        $newRequest = RequestModel::create($createPayload);

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
            if ($targetDriverId !== null) {
                $driver = Driver::with('transType')->find($targetDriverId);
                $newRequest->driverId = $targetDriverId;
                $newRequest->save();
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
                    $when = $newRequest->requestDate
                        ? Carbon::parse($newRequest->requestDate)->format('Y-m-d H:i')
                        : '';
                    $this->createDriverNotification(
                        (int) $driver->userId,
                        'طلب حجز مسبق',
                        $when !== ''
                            ? "وصلك طلب حجز مسبق للموعد {$when}. راجع «الحجوزات المسبقة» للقبول."
                            : 'وصلك طلب حجز مسبق جديد. راجع «الحجوزات المسبقة» للقبول.',
                        'sched_assigned',
                        (int) $newRequest->id
                    );
                }
            }
        }



        return response()->json([
            'success' => true,
            'data' => $newRequest->fresh(['discount', 'driver.user']),
            'channel' => 'trip.' . $newRequest['id'],
            'message' => 'Request created successfully',
            'dispatch' => $dispatchMeta,
        ], 201);
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
        ]);

        $pickLat = (float) $v['pickupLatitude'];
        $pickLng = (float) $v['pickupLongitude'];
        $carTypeId = (int) $v['carTypeId'];
        $destLat = isset($v['destLatitude']) ? (float) $v['destLatitude'] : null;
        $destLng = isset($v['destLongitude']) ? (float) $v['destLongitude'] : null;
        $routeMinutes = $this->normalizeEstimatedDurationMinutesInput($request->input('estimatedDurationMinutes'));

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

        $distances = DriverNearbyService::nearbyOnlineDriverDistances(
            $pickLng,
            $pickLat,
            DriverNearbyService::maxDisplayRadiusKm()
        );

        foreach ($distances as $id => $kmToPickup) {
            if (in_array($id, $busy, true)) {
                continue;
            }
            $d = Driver::with(['user', 'transType'])->find($id);
            if (! $d || (int) $d->transTypeId !== $carTypeId) {
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
                $routeMinutes
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
            'data' => $items,
        ]);
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
                'message' => 'حجز مسبق: انتظر تأكيد جاهزية الراكب ثم اضغط «ابدأ الرحلة» من الإشعار',
            ], 400);
        }

        $req->status = RequestModel::STATUS_DRIVER_ARRIVED;
        $req->save();
        try {
            TripTraceService::markArrived($req, (int) $driver->id);
        } catch (\Throwable $e) {
        }

        // لا إشعار للراكب هنا — يُبلَّغ عند ضغط السائق «بدء الرحلة» فقط.

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
     * ردّ السائق على إشعار جاهزية الراكب: بدء أو تأجيل.
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

        if ($req->sched_ready_answered_at === null) {
            return response()->json(['success' => false, 'message' => 'Passenger has not confirmed readiness yet'], 400);
        }

        if ($v['action'] === 'start') {
            if ($req->requestDate) {
                $earliest = $req->requestDate->copy()->subMinutes(10);
                if (now()->lt($earliest)) {
                    $when = $req->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i');

                    return response()->json([
                        'success' => false,
                        'message' => "لا يمكن بدء التوجه قبل الموعد. الموعد المحدد: {$when}",
                    ], 400);
                }
            }
            // يبقى Reserved حتى «وصلت» و«بدء التنفيذ» — لا قفز مباشر إلى Running.
            $req->sched_driver_started_at = now();
            $req->sched_driver_deferred_at = null;
            $req->sched_driver_retry_at = null;
            $req->sched_driver_response_deadline_at = null;
            $req->save();

            return response()->json([
                'success' => true,
                'data' => $req->fresh(['startLocation', 'destLocation', 'carType']),
                'message' => 'يمكنك التوجه للراكب الآن',
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
                    $requestData->status = RequestModel::STATUS_RESERVED;
                    $requestData->save();

                    RequestHistory::firstOrCreate(
                        ['requestId' => $requestData->id],
                        [
                            'driverId' => $driverId,
                            'finalCost' => $requestData->predectedCost ?? 0,
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

                // تنظيف أي عروض/eligible قديمة
                try {
                    Redis::del('request:'.$requestData->id.':eligible');
                } catch (\Throwable $e) {}
                try {
                    RequestDriverOffer::where('request_id', $requestData->id)->delete();
                } catch (\Throwable $e) {}

                // إشعار داخلي للراكب (يُقرأ من تطبيق Flutter عبر customer/notifications)
                try {
                    CustomerNotification::create([
                        'user_id' => $requestData->userId,
                        'title' => 'تم قبول الطلب',
                        'body' => 'تم قبول الطلب والسائق في طريقه إليك لا تغادر موقعك',
                        'kind' => 'trip.accepted',
                        'reference_type' => 'request',
                        'reference_id' => $requestData->id,
                        'payload' => [
                            'kind' => 'trip.accepted',
                            'request_id' => $requestData->id,
                        ],
                    ]);
                } catch (\Throwable $e) {}

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

            try {
                CustomerNotification::create([
                    'user_id' => $requestData->userId,
                    'title' => 'تم قبول الطلب',
                    'body' => 'تم قبول الطلب والسائق في طريقه إليك لا تغادر موقعك',
                    'kind' => 'trip.accepted',
                    'reference_type' => 'request',
                    'reference_id' => $requestData->id,
                    'payload' => [
                        'kind' => 'trip.accepted',
                        'request_id' => $requestData->id,
                    ],
                ]);
            } catch (\Throwable $e) {
            }

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
            $requestData->status = RequestModel::STATUS_RESERVED;
            $requestData->driverId = $driverId;
            $requestData->sched_driver_started_at = null;
            $requestData->sched_ready_answered_at = null;
            $requestData->sched_driver_response_deadline_at = null;
            $requestData->sched_driver_deferred_at = null;
            $requestData->save();

            $history = RequestHistory::create([
                'requestId' => $requestData->id,
                'driverId' => $driverId,
                'finalCost' => $requestData->predectedCost ?? 0,
                'descountId' => $request->discountId ?? null,
            ]);

            DB::commit();

            try {
                TripTraceService::markAccepted($requestData->fresh(['startLocation']) ?? $requestData, $driverId);
            } catch (\Throwable $e) {
            }

            $this->sendConfirmationToPassenger($requestData, $driver);

            $when = $requestData->requestDate
                ? $requestData->requestDate->timezone(config('app.timezone'))->format('Y-m-d H:i')
                : '';
            $msg = $when !== ''
                ? "تم قبول الحجز. الموعد: {$when}. يُفعَّل الطلب عند جاهزية الراكب و«ابدأ الرحلة»."
                : 'تم قبول الحجز. يُفعَّل الطلب عند جاهزية الراكب و«ابدأ الرحلة».';

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
                ? "تم قبول حجزك المسبق. موعد الرحلة: {$when}. سنرسل «هل أنت جاهز؟» قبل الموعد بخمس دقائق."
                : 'تم قبول حجزك المسبق. سنرسل «هل أنت جاهز؟» قبل موعد الرحلة.';

            CustomerNotification::create([
                'user_id' => $request->userId,
                'title' => 'تم قبول الحجز المسبق',
                'body' => $body,
                'kind' => 'sched_accepted',
                'reference_type' => 'request',
                'reference_id' => $request->id,
                'payload' => [
                    'kind' => 'sched_accepted',
                    'request_id' => $request->id,
                ],
            ]);
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

        DB::beginTransaction();
        try {
            // أغلق أي عداد حر عالق لنفس السائق قبل بدء جديد.
            $stale = RequestModel::query()
                ->where('driverId', $driver->id)
                ->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER)
                ->whereIn('status', [
                    RequestModel::STATUS_RUNNING,
                    RequestModel::STATUS_RESERVED,
                    RequestModel::STATUS_PENDING,
                ])
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
                'trip_started_at' => $now,
                'billing_kind' => RequestModel::BILLING_KIND_FREE_METER,
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
                'data' => $newRequest->fresh(['startLocation', 'destLocation', 'carType', 'history']),
                'history' => $history,
                'message' => 'تم بدء رحلة العداد الحر',
            ]);
        } catch (\Throwable $e) {
            DB::rollBack();

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
                'message' => 'حجز مسبق: لا يمكن بدء الرحلة قبل «ابدأ الرحلة» بعد جاهزية الراكب',
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
            CustomerNotification::create([
                'user_id' => $requestData->userId,
                'title' => 'وصل السائق',
                'body' => 'السائق معك — الرحلة بدأت.',
                'kind' => 'trip.driver_arrived',
                'reference_type' => 'request',
                'reference_id' => $requestData->id,
            ]);
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => $requestData->fresh(['startLocation', 'destLocation']),
            'message' => 'Trip started successfully',
        ]);
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

        if ($requestData->status !== RequestModel::STATUS_RUNNING) {
            return response()->json(['success' => false, 'message' => 'Cannot finish at this status'], 400);
        }

        $rawBilling = strtolower(trim((string) $request->input('billing_kind', '')));
        if ($rawBilling === '' && $request->boolean('free_meter')) {
            $rawBilling = RequestModel::BILLING_KIND_FREE_METER;
        }
        if ($rawBilling === '') {
            $rawBilling = RequestModel::BILLING_KIND_APP_REQUEST;
        }

        if (! in_array($rawBilling, [RequestModel::BILLING_KIND_APP_REQUEST, RequestModel::BILLING_KIND_FREE_METER], true)) {
            return response()->json([
                'success' => false,
                'message' => 'billing_kind يجب أن يكون app_request أو free_meter',
            ], 422);
        }

        if ($rawBilling === RequestModel::BILLING_KIND_FREE_METER) {
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

        if ($rawBilling === RequestModel::BILLING_KIND_APP_REQUEST) {
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

        DB::beginTransaction();

        try {
            $history = RequestHistory::where('requestId', $requestId)->first();

            if ($rawBilling === RequestModel::BILLING_KIND_FREE_METER) {
                // لا CarType ولا predectedCost — المبلغ من العداد فقط (الزبون في السيارة).
                $clientFinal = (float) $request->input('finalCost', $request->input('final_cost', 0));
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
                if ($requestData->discountId) {
                    $discount = Discount::find($requestData->discountId);
                    if ($discount) {
                        $deduction = $discount->calculateDiscount($finalCost);
                        $finalCost = max(0, round((float) $finalCost - (float) $deduction, 2));
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
                $requestData->is_app_request = false;
                // العداد الحر: لا تسعيرة فئة طلب — الأجرة من العداد فقط (لا predectedCost تطبيق).
                $requestData->predectedCost = 0;
                $requestData->free_meter_had_movement = $hadMovement;
                $requestData->free_meter_counts_for_revenue = $countsForRevenue;
                $requestData->status = RequestModel::STATUS_FINISHED;
                $requestData->save();
                try {
                    TripTraceService::markTripEnded($requestData, (int) $driver->id);
                } catch (\Throwable $e) {
                }

                DB::commit();

                return response()->json([
                    'success' => true,
                    'data' => $requestData->fresh(['startLocation', 'destLocation', 'carType', 'history']),
                    'finalCost' => $finalCost,
                    'billing_kind' => RequestModel::BILLING_KIND_FREE_METER,
                    'free_meter_counts_for_revenue' => $countsForRevenue,
                    'message' => 'Trip finished successfully',
                ]);
            }

            // طلب التطبيق: التكلفة النهائية من عداد الرحلة (كم + وقوف + افتتاحي الفئة).
            $carType = $requestData->carType;
            $clientFinal = (float) $request->input('finalCost', $request->input('final_cost', 0));
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
            if ($requestData->discountId) {
                $discount = Discount::find($requestData->discountId);
                if ($discount) {
                    $deduction = $discount->calculateDiscount($finalCost);
                    $finalCost = max(0, round((float) $finalCost - (float) $deduction, 2));
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
            $requestData->status = RequestModel::STATUS_FINISHED;
            $requestData->save();
            try {
                TripTraceService::markTripEnded($requestData, (int) $driver->id);
            } catch (\Throwable $e) {
            }

            DB::commit();

            return response()->json([
                'success' => true,
                'data' => $requestData->fresh(['startLocation', 'destLocation', 'carType', 'history']),
                'finalCost' => $finalCost,
                'distanceTraveledKm' => $kmMoved > 0 ? round($kmMoved, 3) : null,
                'billedWaitingMinutes' => $waitingMin,
                'meterElapsedSeconds' => $elapsedSec,
                'predectedCost' => $requestData->predectedCost,
                'billing_kind' => RequestModel::BILLING_KIND_APP_REQUEST,
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
            ->where('carTypeId', $driver->transTypeId)
            ->where(function ($q) use ($driver) {
                // موجّه لهذا السائق فقط — لا حجوزات عامة للجميع
                $q->where('driverId', $driver->id);
            })
            ->with(['user', 'startLocation', 'destLocation', 'carType'])
            ->orderBy('requestDate', 'asc')
            ->get();

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

        $req = RequestModel::find($requestId);
        if (! $req || (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        $status = RequestModel::normalizeTripStatus($req->status);
        if (! RequestModel::canAbortTrip($req)) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إلغاء الطلب في هذه المرحلة ('.($status !== '' ? $status : 'غير معروف').')',
            ], 400);
        }

        Redis::del('request:'.$req->id.':eligible');
        RequestDriverOffer::where('request_id', $req->id)->delete();

        $assignedDriverId = $req->driverId ? (int) $req->driverId : null;

        $req->status = RequestModel::STATUS_REMOVED;
        $req->cancel_reason = $request->input('reason');
        $req->save();

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
     * إلغاء طلب عالق — للسائق أو الراكب (قبل بدء الرحلة فعلياً).
     */
    public function abortActiveTrip(HttpRequest $request, $requestId)
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::find($requestId);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        $isDriver = $user->roll === 'Driver';
        $isCustomer = $user->roll === 'Customer';
        if (! $isDriver && ! $isCustomer) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if ($isCustomer && (int) $req->userId !== (int) $user->id) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }

        $assignedDriverId = $req->driverId ? (int) $req->driverId : null;
        if ($isDriver) {
            $driver = Driver::where('userId', $user->id)->first();
            if (! $driver || $assignedDriverId === null || $assignedDriverId !== (int) $driver->id) {
                return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
            }
        }

        if (! RequestModel::canAbortTrip($req)) {
            $status = RequestModel::normalizeTripStatus($req->status);

            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إلغاء الطلب في هذه المرحلة ('.($status !== '' ? $status : 'غير معروف').')',
            ], 400);
        }

        try {
            Redis::del('request:'.$req->id.':eligible');
        } catch (\Throwable $e) {
        }
        try {
            RequestDriverOffer::where('request_id', $req->id)->delete();
        } catch (\Throwable $e) {
        }

        $req->status = RequestModel::STATUS_REMOVED;
        $reason = trim((string) $request->input('reason', ''));
        $req->cancel_reason = $reason !== ''
            ? $reason
            : ($isDriver ? 'driver_abort' : 'customer_abort');
        if ($isDriver) {
            $req->driver_cancelled_at = now();
        }
        $req->save();

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

        if ($req->type !== RequestModel::TYPE_IMMEDIATE) {
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
            if ($this->isDriverBusy($driverId)) {
                return response()->json([
                    'success' => false,
                    'message' => 'السائق مشغول برحلة أخرى',
                ], 422);
            }
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
        if ($driver->transTypeId !== null && $req->carTypeId !== null && (int) $driver->transTypeId !== (int) $req->carTypeId) {
            return response()->json([
                'success' => false,
                'message' => 'نوع مركبة السائق لا يطابق نوع الطلب',
            ], 422);
        }

        $durOverride = $this->normalizeEstimatedDurationMinutesInput($v['estimatedDurationMinutes'] ?? null);

        DB::beginTransaction();
        try {
            $req->driverId = $driverId;
            // يبقى Pending حتى يقبل السائق
            $req->status = RequestModel::STATUS_PENDING;
            if ($req->type === RequestModel::TYPE_SCHEDULE) {
                $req->cancel_reason = null;
            }

            if ($req->startLocation && $req->destLocation) {
                $this->refreshAppTripPredictedCostForDriver($req, $driver, $req->startLocation, $req->destLocation, $durOverride);
            }
            $req->save();

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
        ];

        try {
            $ttl = $status === RequestModel::STATUS_RUNNING ? 6 : 8;
            Cache::put($trackCacheKey, $payload, $ttl);
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
            'meterElapsedSeconds' => 'sometimes|integer|min:0',
            'meter_elapsed_seconds' => 'sometimes|integer|min:0',
            'isMoving' => 'sometimes|boolean',
        ]);

        $payload = [
            'finalCost' => round((float) $v['finalCost'], 2),
            'distanceTraveledKm' => round((float) ($v['distanceTraveledKm'] ?? $v['distance_traveled_km'] ?? 0), 3),
            'billedWaitingMinutes' => (int) ($v['billedWaitingMinutes'] ?? $v['billed_waiting_minutes'] ?? 0),
            'meterElapsedSeconds' => (int) ($v['meterElapsedSeconds'] ?? $v['meter_elapsed_seconds'] ?? 0),
            'isMoving' => $request->boolean('isMoving'),
            'updated_at' => now()->toIso8601String(),
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
                    && (int) ($existing['billedWaitingMinutes'] ?? 0) === $payload['billedWaitingMinutes']) {
                    return response()->json([
                        'success' => true,
                        'data' => $existing,
                        'cached' => true,
                    ]);
                }
            }
        } catch (\Throwable $e) {
        }

        if (Cache::has($throttleKey)) {
            try {
                $existingRaw = Redis::get($meterKey);
                if (is_string($existingRaw) && $existingRaw !== '') {
                    $existing = json_decode($existingRaw, true);
                    if (is_array($existing)) {
                        return response()->json([
                            'success' => true,
                            'data' => $existing,
                            'throttled' => true,
                        ]);
                    }
                }
            } catch (\Throwable $e) {
            }
        }

        try {
            Redis::setex($meterKey, 180, json_encode($payload));
            Cache::put($throttleKey, 1, 10);
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
        ?float $estimatedRouteMinutes = null
    ): array {
        $user = $driver->user;
        $name = $user ? trim(($user->firstName ?? '').' '.($user->lastName ?? '')) : '';

        $t = $driver->transType;
        $kmPrice = $t ? (float) ($t->KMPrice ?? 0) : null;
        $minutePrice = $t ? (float) ($t->timePrice ?? 0) : null;
        $est = null;
        if ($destLat !== null && $destLng !== null && $t !== null) {
            $tripKm = $this->haversineKm($pickLat, $pickLng, $destLat, $destLng);
            $minutes = $this->resolveTripMinutesForEstimate($estimatedRouteMinutes, null, $tripKm);
            $est = $this->computeAppTripFare($t, $tripKm, $minutes);
        }

        return [
            'driverId' => $driver->id,
            'name' => $name !== '' ? $name : ('سائق #'.$driver->id),
            'number' => $user->number ?? null,
            'carNumber' => $driver->carNumber,
            'vehicle_model' => $driver->vehicle_model,
            'car_category_name' => $t ? (string) ($t->name ?? '') : '',
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

        $t = $driver->transType;
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
            $est = $this->computeAppTripFare($t, $tripKm, $minutes);
        }

        return [
            'driverId' => $driver->id,
            'name' => $name !== '' ? $name : ('سائق #'.$driver->id),
            'number' => $user->number ?? null,
            'carNumber' => $driver->carNumber,
            'vehicle_model' => $driver->vehicle_model,
            'car_category_name' => $t ? (string) ($t->name ?? '') : '',
            'driver_photo_url' => Driver::publicUrlForStoragePath($driver->image),
            'car_photo_url' => Driver::publicUrlForStoragePath($driver->carImage),
            'distance_from_pickup_km' => $km,
            'km_price' => $kmPrice,
            'minute_price' => $minutePrice,
            'estimated_cost' => $est,
        ];
    }

    private function notifyPassengerSchedPayload(
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
