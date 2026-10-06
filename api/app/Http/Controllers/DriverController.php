<?php

namespace App\Http\Controllers;
use Illuminate\Http\Response;
use App\Http\Requests\DriverActiveRequest;
use App\Http\Requests\DriverUpdateLocation;
use App\Models\AppSetting;
use App\Models\Driver;
use App\Http\Requests\StoreDriverRequest;
use App\Http\Requests\UpdateDriverRequest;
use App\Models\CarType;
use App\Models\User;
use App\Services\AdminLimitedViewService;
use App\Services\DriverSubscriptionService;
use App\Services\DriverNearbyService;
use App\Services\DriverPollCacheService;
use Exception;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Storage;

class DriverController extends Controller
{
    private function forbidUnlessDriversRead(Request $request): ?\Illuminate\Http\JsonResponse
    {
        $u = $request->user();
        if (! $u) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        // فهرس/عرض السائقين للوحة الإدارة فقط — لا للزبون أو السائق.
        if (! $u->isBackofficeStaff()) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        if ($u->roll === 'Employee' && ! $u->hasStaffPermission('drivers.read')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        return null;
    }

    private function forbidUnlessDriversWrite(Request $request): ?\Illuminate\Http\JsonResponse
    {
        $u = $request->user();
        if (! $u || ! $u->hasStaffPermission('drivers.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        return null;
    }

    public function active(Request $request)
    {
        $userId = $request->user()->id;
        return response()->json([
            'state' => true,
            'channel' => 'private-driver.' . Driver::where('userId', $userId)->value('id')
        ]);
    }
    /**
     * View list of all drivers     */
    public function index(Request $request)
    {
        if ($deny = $this->forbidUnlessDriversRead($request)) {
            return $deny;
        }

        $staff = AdminLimitedViewService::resolveStaffUser($request);
        $query = Driver::query();
        $query->with(['user', 'transType']);
        AdminLimitedViewService::scopeDrivers($query, $staff);

        // Search by car number
        if ($request->has('carNumber')) {
            $query->where('carNumber', 'like', '%' . $request->carNumber . '%');
        }

        // Search by type
        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        // Search by user
        if ($request->has('userId')) {
            $query->where('userId', $request->userId);
        }

        $transTypeId = $request->input('transTypeId', $request->input('carTypeId'));
        if ($transTypeId !== null && $transTypeId !== '') {
            $query->where('transTypeId', (int) $transTypeId);
        }

        if ($request->boolean('blocked') || $request->boolean('subscription_blocked')) {
            $query->where('subscription_blocked', true);
        }

        // بحث بالاسم أو رقم اللوحة أو الهاتف
        $nameSearch = trim((string) $request->input('search', $request->input('name', '')));
        if ($nameSearch !== '') {
            $escaped = addcslashes($nameSearch, '%_\\');
            $like = '%'.$escaped.'%';
            $query->where(function ($q) use ($like) {
                $q->where('carNumber', 'like', $like)
                    ->orWhereHas('user', function ($uq) use ($like) {
                        $uq->where('firstName', 'like', $like)
                            ->orWhere('lastName', 'like', $like)
                            ->orWhere('number', 'like', $like)
                            ->orWhereRaw("CONCAT(COALESCE(firstName,''),' ',COALESCE(lastName,'')) LIKE ?", [$like]);
                    });
            });
        }

        // Order
        $sortBy = $request->get('sort_by', 'id');
        $sortOrder = $request->get('sort_order', 'desc');
        $query->orderBy($sortBy, $sortOrder);

        // Display deleted

        if ($request->has('with_trashed') && $request->with_trashed) {
            $query->withTrashed();
        }

        $perPage = (int) $request->get('per_page', 15);
        $perPage = max(1, min(100, $perPage));
        $drivers = $query->paginate($perPage);
        $drivers->getCollection()->each(function ($driver) {
            $driver->makeHidden(['userId']);
            if ($driver->user) {
                $driver->user->makeHidden(['id', 'created_at', 'updated_at', 'deleted_at']);
            }
            if ($driver->transType) {
                $driver->transType->makeHidden(['created_at', 'updated_at', 'deleted_at']);
            }
            $driver->setAttribute(
                'subscription_active',
                DriverSubscriptionService::isSubscriptionActive($driver),
            );
            $driver->setAttribute(
                'driver_photo_url',
                Driver::publicUrlForStoragePath($driver->image),
            );
            $driver->setAttribute(
                'car_photo_url',
                Driver::publicUrlForStoragePath($driver->carImage),
            );
        });
        return response()->json([
            'success' => true,
            'data' => $drivers,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * View specific driver
     */
    public function show(Request $request, $id)
    {
        if ($deny = $this->forbidUnlessDriversRead($request)) {
            return $deny;
        }

        $driver = Driver::with(['user', 'transType'])->find($id);

        if (!$driver) {
            return response()->json([
                'success' => false,
                'message' => 'Driver not found'
            ], 404);
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible(
            AdminLimitedViewService::resolveStaffUser($request),
            (int) $driver->id
        )) {
            return $deny;
        }

        $driver->setAttribute(
            'subscription_active',
            DriverSubscriptionService::isSubscriptionActive($driver),
        );

        return response()->json([
            'success' => true,
            'data' => $driver,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Add a new driver
     */

    public function store(StoreDriverRequest $request)
    {
        if ($deny = AdminLimitedViewService::assertCanCreate(AdminLimitedViewService::resolveStaffUser($request))) {
            return $deny;
        }

        $carType = CarType::where('id', $request->CarTypeId)->first();
        if ($carType == null) {
            return response()->json([
                'success' => false,
                'message' => 'فئة السيارة غير موجودة أو مُلغاة — اختر فئة صالحة من القائمة.',
            ], 400);
        }
        DB::beginTransaction();

        try {
            // 1. إضافة نوع السيارة (CarType)


            // 2. إضافة المستخدم (User)
            $user = User::create([
                'firstName' => $request->firstName,
                'lastName' => $request->lastName,
                'number' => $request->number,
                'password' => $request->password,
                'roll' => 'Driver',
                'banned' => false,
                'expireDate' => Carbon::today()->addMonth()->format('Y-m-d'),
            ]);

            $file = $request->file('image');
            $filePath = time() . '_' . $file->getClientOriginalName();
            Storage::disk('public')->put($filePath, File::get($file));

            $file1 = $request->file('IDImage');
            $filePath1 = time() . '_' . $file1->getClientOriginalName();
            Storage::disk('public')->put($filePath1, File::get($file1));

            $fileCar = $request->file('carImage');
            $filePathCar = time() . '_' . $fileCar->getClientOriginalName();
            Storage::disk('public')->put($filePathCar, File::get($fileCar));

            $freeKm = $request->input('freeKMPrice');
            $freeTime = $request->input('freeTimePrice');
            if ($freeKm === null || $freeKm === '') {
                $freeKm = $carType->KMPrice;
            }
            if ($freeTime === null || $freeTime === '') {
                $freeTime = $carType->timePrice;
            }

            // 3. إضافة السائق (Driver)
            $vehicleModel = trim((string) $request->input('vehicle_model', $request->input('vehicleModel', '')));

            $driver = Driver::create([
                'userId' => $user->id,
                'transTypeId' => $carType->id,
                'image' => $filePath,
                'IDImage' => $filePath1,
                'carImage' => $filePathCar,
                'carNumber' => $request->carNumber,
                'insurance' => $request->insurance,
                'mechanics' => $request->mechanics,
                'type' => $request->typeCar,
                'vehicle_model' => $vehicleModel !== '' ? $vehicleModel : null,
                'freeKMPrice' => $freeKm,
                'freeTimePrice' => $freeTime,
            ]);

            // اشتراك 30 يوماً من يوم الإضافة — ساري حتى نهاية المدة.
            DriverSubscriptionService::beginSubscription($driver);

            DB::commit();

            return response()->json([
                'success' => true,
                'message' => 'تم إضافة السائق بنجاح',
                'data' => [
                    'user' => $user,
                    'carType' => $carType,
                    'driver' => $driver,
                ]
            ]);
        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'حدث خطأ أثناء إضافة السائق',
                'error' => $e->getMessage()
            ], 400);
        }
    }
    public function getImage(Request $request, $path)
    {
        // رابط موقّع مؤقت أو مستخدم مسجّل (لوحة/تطبيق).
        $signedOk = false;
        try {
            $signedOk = $request->hasValidSignature();
        } catch (\Throwable $e) {
            $signedOk = false;
        }

        $user = $request->user() ?? auth('sanctum')->user();
        if (! $signedOk && ! $user) {
            return response()->json([
                'state' => false,
                'message' => 'Unauthorized',
            ], 401);
        }

        $raw = rawurldecode((string) $path);
        if ($raw === '' || str_contains($raw, '..') || str_contains($raw, "\0")) {
            return response()->json([
                'state' => false,
                'message' => 'Invalid path',
            ], 400);
        }

        $resolved = Driver::resolveExistingStoragePath($raw);
        if ($resolved === null || str_contains($resolved, '..')) {
            return response()->json([
                'state' => false,
                'message' => 'Image not found',
            ], 404);
        }

        if (! $signedOk && $user && ! $user->isBackofficeStaff()) {
            $owns = Driver::query()
                ->where('userId', $user->id)
                ->where(function ($q) use ($resolved) {
                    $q->where('image', $resolved)
                        ->orWhere('IDImage', $resolved)
                        ->orWhere('carImage', $resolved)
                        ->orWhere('image', basename($resolved))
                        ->orWhere('IDImage', basename($resolved))
                        ->orWhere('carImage', basename($resolved));
                })
                ->exists();

            if (! $owns) {
                // زبون مرتبط برحلة نشطة مع سائق يملك الملف.
                $allowed = false;
                if ($user->roll === 'Customer') {
                    $driverIds = Driver::query()
                        ->where(function ($q) use ($resolved) {
                            $q->where('image', $resolved)
                                ->orWhere('IDImage', $resolved)
                                ->orWhere('carImage', $resolved)
                                ->orWhere('image', basename($resolved))
                                ->orWhere('IDImage', basename($resolved))
                                ->orWhere('carImage', basename($resolved));
                        })
                        ->pluck('id');
                    if ($driverIds->isNotEmpty()) {
                        $allowed = \App\Models\RequestModel::query()
                            ->where('userId', $user->id)
                            ->whereIn('driverId', $driverIds)
                            ->whereIn('status', [
                                \App\Models\RequestModel::STATUS_PENDING,
                                \App\Models\RequestModel::STATUS_RESERVED,
                                \App\Models\RequestModel::STATUS_DRIVER_ARRIVED,
                                \App\Models\RequestModel::STATUS_AWAITING_DESTINATION,
                                \App\Models\RequestModel::STATUS_RUNNING,
                            ])
                            ->exists();
                    }
                }
                if (! $allowed) {
                    return response()->json([
                        'state' => false,
                        'message' => 'Forbidden',
                    ], 403);
                }
            }
        }

        try {
            $disk = Storage::disk('public');
            $responseFile = $disk->get($resolved);

            return (new Response($responseFile, 200))
                ->header('Content-Type', $disk->mimeType($resolved))
                ->header('Cache-Control', 'private, max-age=3600');
        } catch (Exception $e) {
            return response()->json([
                'state' => false,
                'data' => $e->getMessage(),
            ], 404);
        }
    }

    public function updateLocation(DriverUpdateLocation $request)
    {
        $driver = Driver::where('userId', $request->user()->id)->first();
        if (!$driver) {
            return response()->json([
                'state' => false,
                'message' => 'لم يتم العثور على ملف السائق',
            ], 404);
        }

        if (! DriverSubscriptionService::isVisibleToPassengers($driver)) {
            DriverSubscriptionService::removeFromOnlineGeo($driver);

            return response()->json([
                'success' => false,
                'state' => false,
                'message' => DriverSubscriptionService::BLOCK_MESSAGE,
                'code' => 'subscription_blocked',
            ], 403);
        }

        $lng = $request->longitude;
        $lat = $request->latitude;
        try {
            Redis::geoadd('drivers', $lng, $lat, (string) $driver->id);
            // مؤشر أونلاين: أطول من نبض الموقع (~25ث) ليبقى نشطاً دون ضغط زائد.
            Redis::setex('driver:'.$driver->id.':online', 540, '1');
            Redis::setex(\App\Services\SosLiveService::driverLocAtKey((int) $driver->id), 86400, (string) time());
            DriverNearbyService::cacheReceiveRadius(
                (int) $driver->id,
                DriverNearbyService::normalizeReceiveRadiusKm($driver->receive_radius_km ?? 1)
            );
            self::appendDriverLocationHistory((int) $driver->id, (float) $lat, (float) $lng);
        } catch (\Throwable $e) {
            Log::warning('driver updateLocation redis: '.$e->getMessage());
            return response()->json([
                'state' => false,
                'message' => 'تعذر تحديث الموقع حالياً — تحقق من Redis',
            ], 503);
        }

        try {
            DriverNearbyService::attachDriverToFreshPendingRequests($driver, $lng, $lat);
            DriverPollCacheService::bust();
        } catch (\Throwable $e) {
            Log::debug('attachDriverToFreshPendingRequests: '.$e->getMessage());
        }

        return response()->json([
            'state' => true,
        ]);
    }

    /**
     * سجل مواقع أخيرة في Redis (للوحة الإدارة) — مع تخفيف الضغط (~30ث).
     */
    private static function appendDriverLocationHistory(int $driverId, float $lat, float $lng): void
    {
        if ($driverId <= 0) {
            return;
        }
        try {
            $key = 'driver:'.$driverId.':loc_history';
            $now = time();
            $lastRaw = Redis::lindex($key, 0);
            if (is_string($lastRaw) && $lastRaw !== '') {
                $prev = json_decode($lastRaw, true);
                if (is_array($prev) && isset($prev['t']) && ($now - (int) $prev['t']) < 30) {
                    return;
                }
            }
            Redis::lpush($key, json_encode([
                'lat' => round($lat, 7),
                'lng' => round($lng, 7),
                't' => $now,
            ], JSON_UNESCAPED_UNICODE));
            Redis::ltrim($key, 0, 149);
            Redis::expire($key, 60 * 60 * 24 * 14);
        } catch (\Throwable $e) {
            Log::debug('appendDriverLocationHistory: '.$e->getMessage());
        }
    }

    /**
     * إيقاف الظهور كسائق «نشط» في قائمة الراكب (إزالة مفتاح الأونلاين وموقع GEO).
     * يُستدعى من التطبيق عند سحب «للإيقاف» أو الخروج من وضع الاستقبال.
     */
    public function goOffline(Request $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json([
                'state' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json([
                'state' => false,
                'message' => 'لم يتم العثور على ملف السائق',
            ], 404);
        }

        try {
            Redis::del('driver:'.$driver->id.':online');
            Redis::zrem('drivers', (string) $driver->id);
        } catch (\Throwable $e) {
            Log::warning('driver goOffline redis: '.$e->getMessage());
        }

        return response()->json([
            'state' => true,
            'message' => 'تم إيقاف الظهور في قائمة السائقين القريبين',
        ]);
    }

    /** أسعار **فئة السيارة** المرتبطة بالسائق (كم/دقيقة/افتتاح من جدول الفئات) — لعرض التعرفة المرتبطة بفئة الرحلة وليس إعدادات العداد الحر. */
    public function myPricing(Request $request)
    {
        $user = $request->user();
        if (!$user || $user->roll !== 'Driver') {
            return response()->json([
                'state' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $driver = Driver::where('userId', $user->id)->with('transType')->first();
        if (!$driver || ! $driver->transType) {
            return response()->json([
                'state' => false,
                'message' => 'لم يتم ربط نوع سيارة لهذا السائق',
            ], 404);
        }

        $t = $driver->transType;

        return response()->json([
            'state' => true,
            'data' => [
                'openPrice' => (float) ($t->openPrice ?? 0),
                'kmPrice' => (float) ($t->KMPrice ?? 0),
                'timePrice' => (float) ($t->timePrice ?? 0),
                'name' => $t->name,
                'carTypeId' => $t->id,
            ],
        ]);
    }

    /** ملف السائق الحالي (مع المستخدم ونوع السيارة + روابط الصور) */
    public function myProfile(Request $request)
    {
        $user = $request->user();
        if (!$user || $user->roll !== 'Driver') {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $driver = Driver::where('userId', $user->id)
            ->with(['user', 'transType'])
            ->first();
        if (!$driver) {
            return response()->json([
                'success' => false,
                'message' => 'لم يتم العثور على ملف السائق',
            ], 404);
        }

        $payload = $driver->toArray();
        $payload['driver_photo_url'] = Driver::publicUrlForStoragePath($driver->image);
        $payload['car_photo_url'] = Driver::publicUrlForStoragePath($driver->carImage);
        $payload['receive_radius_km'] = DriverNearbyService::normalizeReceiveRadiusKm(
            $driver->receive_radius_km ?? DriverNearbyService::DEFAULT_RECEIVE_RADIUS_KM
        );
        $payload['receive_radius_options_km'] = DriverNearbyService::ALLOWED_RECEIVE_RADII_KM;

        return response()->json([
            'success' => true,
            'data' => $payload,
        ]);
    }

    /** نطاق استقبال الطلبات الحالي للسائق (1 / 2 / 3 كم). */
    public function myReceiveRadius(Request $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json([
                'success' => false,
                'message' => 'لم يتم العثور على ملف السائق',
            ], 404);
        }

        $km = DriverNearbyService::normalizeReceiveRadiusKm(
            $driver->receive_radius_km ?? DriverNearbyService::DEFAULT_RECEIVE_RADIUS_KM
        );

        return response()->json([
            'success' => true,
            'data' => [
                'receive_radius_km' => $km,
                'options_km' => DriverNearbyService::ALLOWED_RECEIVE_RADII_KM,
            ],
        ]);
    }

    /** تحديث نطاق استقبال الطلبات: 1 أو 2 أو 3 كم عن نقطة الزبون. */
    public function updateReceiveRadius(Request $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $request->validate([
            'receive_radius_km' => 'required|integer|in:1,2,3',
            'radius_km' => 'sometimes|integer|in:1,2,3',
        ]);

        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json([
                'success' => false,
                'message' => 'لم يتم العثور على ملف السائق',
            ], 404);
        }

        $km = (int) ($request->input('receive_radius_km', $request->input('radius_km', 1)));
        $km = DriverNearbyService::setReceiveRadiusKm($driver, $km);

        return response()->json([
            'success' => true,
            'message' => 'تم ضبط نطاق الاستقبال على '.$km.' كم',
            'data' => [
                'receive_radius_km' => $km,
                'options_km' => DriverNearbyService::ALLOWED_RECEIVE_RADII_KM,
            ],
        ]);
    }

    /** تسعيرة العداد الحر: جميع القيم من إعدادات لوحة التحكم العامة. */
    public function myFreeMeterPricing(Request $request)
    {
        $user = $request->user();
        if (!$user || $user->roll !== 'Driver') {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        // لا حاجة لملف السائق — التسعير عام من لوحة التحكم.
        $payload = \Illuminate\Support\Facades\Cache::remember(
            'free_meter_pricing_v1',
            300,
            static function (): array {
                return [
                    'openPrice' => AppSetting::getDecimal('free_meter_open_price', 0.0),
                    'kmPrice' => AppSetting::getDecimal('free_meter_km_price', 0.0),
                    'timePrice' => AppSetting::getDecimal('free_meter_time_price', 0.0),
                ];
            }
        );

        return response()->json([
            'state' => true,
            'success' => true,
            'data' => $payload,
        ]);
    }

    public function update(UpdateDriverRequest $request, $id)
    {
        $driver = Driver::with(['user', 'transType'])->find($id);
        if (! $driver || ! $driver->user) {
            return response()->json([
                'success' => false,
                'message' => 'Driver not found',
            ], 404);
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), (int) $driver->id)) {
            return $deny;
        }

        DB::beginTransaction();
        try {
            $user = $driver->user;
            if ($request->filled('firstName')) {
                $user->firstName = $request->string('firstName');
            }
            if ($request->filled('lastName')) {
                $user->lastName = $request->string('lastName');
            }
            if ($request->filled('number')) {
                $user->number = $request->string('number');
            }
            if ($request->filled('password')) {
                $user->password = $request->string('password');
            }
            $user->save();

            $oldTransTypeId = (int) $driver->transTypeId;
            $carTypeId = $request->input('transTypeId', $request->input('CarTypeId'));
            $newTransTypeId = null;
            if ($carTypeId !== null && $carTypeId !== '') {
                $newTransTypeId = (int) $carTypeId;
                $driver->transTypeId = $newTransTypeId;
            }

            if ($newTransTypeId !== null && $newTransTypeId !== $oldTransTypeId) {
                $ct = CarType::find($newTransTypeId);
                if ($ct) {
                    if (! $request->has('freeKMPrice')) {
                        $driver->freeKMPrice = $ct->KMPrice;
                    }
                    if (! $request->has('freeTimePrice')) {
                        $driver->freeTimePrice = $ct->timePrice;
                    }
                }
            }

            if ($request->has('carNumber')) {
                $driver->carNumber = $request->carNumber;
            }

            $typeInput = $request->input('typeCar', $request->input('type'));
            if ($typeInput !== null && $typeInput !== '') {
                $driver->type = $typeInput;
            }

            foreach (['insurance', 'mechanics'] as $f) {
                if ($request->has($f)) {
                    $driver->{$f} = $request->input($f);
                }
            }

            if ($request->has('vehicle_model') || $request->has('vehicleModel')) {
                $vm = trim((string) $request->input(
                    'vehicle_model',
                    $request->input('vehicleModel', '')
                ));
                $driver->vehicle_model = $vm !== '' ? $vm : null;
            }

            foreach (['freeKMPrice', 'freeTimePrice'] as $f) {
                if ($request->has($f)) {
                    $driver->{$f} = $request->input($f);
                }
            }

            if ($request->hasFile('image')) {
                $file = $request->file('image');
                $path = time().'_'.$file->getClientOriginalName();
                Storage::disk('public')->put($path, File::get($file));
                if ($driver->image) {
                    try {
                        Storage::disk('public')->delete($driver->image);
                    } catch (\Throwable $e) {
                    }
                }
                $driver->image = $path;
            }

            if ($request->hasFile('IDImage')) {
                $file = $request->file('IDImage');
                $path = time().'_'.$file->getClientOriginalName();
                Storage::disk('public')->put($path, File::get($file));
                if ($driver->IDImage) {
                    try {
                        Storage::disk('public')->delete($driver->IDImage);
                    } catch (\Throwable $e) {
                    }
                }
                $driver->IDImage = $path;
            }

            if ($request->hasFile('carImage')) {
                $file = $request->file('carImage');
                $path = time().'_'.$file->getClientOriginalName();
                Storage::disk('public')->put($path, File::get($file));
                if ($driver->carImage) {
                    try {
                        Storage::disk('public')->delete($driver->carImage);
                    } catch (\Throwable $e) {
                    }
                }
                $driver->carImage = $path;
            }

            $driver->save();
            DB::commit();

            return response()->json([
                'success' => true,
                'data' => $driver->fresh(['user', 'transType']),
                'message' => 'تم تحديث بيانات السائق',
            ]);
        } catch (\Throwable $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 500);
        }
    }


    public function destroy(Request $request, $id)
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }

        $driver = Driver::with('user')->find($id);

        if (!$driver) {
            return response()->json([
                'success' => false,
                'message' => 'Driver not found'
            ], 404);
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), (int) $driver->id)) {
            return $deny;
        }

        $user = $driver->user;
        $driverId = (int) $driver->id;

        try {
            \Illuminate\Support\Facades\Redis::zrem('drivers', (string) $driverId);
            \Illuminate\Support\Facades\Redis::del('driver:'.$driverId.':online');
        } catch (\Throwable $e) {
        }

        // حذف نهائي للسائق وحساب المستخدم المرتبط
        $driver->forceDelete();

        if ($user) {
            try {
                $user->tokens()->delete();
            } catch (\Throwable $e) {
            }
            $user->forceDelete();
        }

        return response()->json([
            'success' => true,
            'message' => 'تم حذف حساب السائق نهائياً',
        ]);
    }

    public function restore(Request $request, $id)
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }

        $driver = Driver::withTrashed()->find($id);

        if (!$driver) {
            return response()->json([
                'success' => false,
                'message' => 'Driver not found'
            ], 404);
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), (int) $driver->id)) {
            return $deny;
        }

        if (!$driver->trashed()) {
            return response()->json([
                'success' => false,
                'message' => 'Driver is not deleted'
            ], 400);
        }

        $driver->restore();

        return response()->json([
            'success' => true,
            'data' => $driver,
            'message' => 'Driver restored successfully'
        ]);
    }
    public function forceDelete(Request $request, $id)
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }

        $driver = Driver::withTrashed()->with('user')->find($id);

        if (!$driver) {
            return response()->json([
                'success' => false,
                'message' => 'Driver not found'
            ], 404);
        }

        $user = $driver->user;
        $driverId = (int) $driver->id;
        try {
            \Illuminate\Support\Facades\Redis::zrem('drivers', (string) $driverId);
            \Illuminate\Support\Facades\Redis::del('driver:'.$driverId.':online');
        } catch (\Throwable $e) {
        }

        $driver->forceDelete();
        if ($user) {
            try {
                $user->tokens()->delete();
            } catch (\Throwable $e) {
            }
            $user->forceDelete();
        }

        return response()->json([
            'success' => true,
            'message' => 'Driver deleted permanently'
        ]);
    }
    public function trashed(Request $request)
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }

        $drivers = Driver::onlyTrashed()->paginate(15);

        return response()->json([
            'success' => true,
            'data' => $drivers,
            'message' => 'Data fetched successfully'
        ]);
    }
}
