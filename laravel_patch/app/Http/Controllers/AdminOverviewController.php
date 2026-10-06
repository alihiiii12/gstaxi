<?php

namespace App\Http\Controllers;

use App\Events\RequestCancelledByCustomerEvent;
use App\Models\AppSetting;
use App\Models\Complaint;
use App\Models\CustomerNotification;
use App\Models\Discount;
use App\Models\Driver;
use App\Models\RequestDriverOffer;
use App\Models\RequestModel;
use App\Models\ServiceArea;
use App\Models\User;
use App\Services\AdminLimitedViewService;
use App\Services\DriverNearbyService;
use App\Services\DriverPollCacheService;
use App\Services\LocationDisplayService;
use App\Services\TripTraceService;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Validation\Rule;

class AdminOverviewController extends Controller
{
    /** إدارة الموظفين والمسؤولين فقط — لا للموظف العادي */
    private function ensureAdmin(Request $request): bool
    {
        return $request->user() && $request->user()->roll === 'Admin';
    }

    private function ensureStaff(Request $request, string $permission): bool
    {
        $u = $request->user();

        return $u && $u->hasStaffPermission($permission);
    }

    /** نقاط السائقين النشطة على Redis GEO + تنبيهات SOS للخريطة */
    public function mapSnapshot(Request $request)
    {
        if (! $this->ensureStaff($request, 'requests.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $staff = $request->user();
        $driverMarkers = AdminLimitedViewService::filterDriverMarkers(
            $staff,
            $this->adminDriverMarkersFromRedis()
        );

        $sosMarkers = [];
        try {
            $raw = Redis::hgetall('sos:active');
            foreach ($raw as $json) {
                $d = json_decode($json, true);
                if (is_array($d) && isset($d['latitude'], $d['longitude'])) {
                    $d['kind'] = 'sos';
                    $sosMarkers[] = $d;
                }
            }
            $sosMarkers = AdminLimitedViewService::filterSosItems($staff, $sosMarkers);
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('admin mapSnapshot sos: '.$e->getMessage());
        }

        $runningTripsQuery = RequestModel::where('status', RequestModel::STATUS_RUNNING)
            ->with(['user', 'history.driver.user', 'startLocation', 'destLocation', 'serviceArea'])
            ->orderBy('updated_at', 'desc')
            ->limit(50);
        AdminLimitedViewService::scopeRequests($runningTripsQuery, $staff);
        $runningTrips = $runningTripsQuery->get()
            ->map(function (RequestModel $req) use ($driverMarkers) {
                $arr = LocationDisplayService::enrichRequestArray($req->toArray(), $req, allowReverse: true);
                $driverId = (int) ($req->driverId ?? 0);
                if ($driverId > 0) {
                    foreach ($driverMarkers as $m) {
                        if ((int) ($m['driverId'] ?? 0) === $driverId) {
                            $arr['driver_live'] = [
                                'latitude' => $m['latitude'],
                                'longitude' => $m['longitude'],
                            ];
                            break;
                        }
                    }
                    if (! isset($arr['driver_live'])) {
                        $live = DriverNearbyService::driverCoords($driverId);
                        if ($live) {
                            $arr['driver_live'] = [
                                'latitude' => $live['lat'],
                                'longitude' => $live['lng'],
                            ];
                        }
                    }
                }

                return $arr;
            })
            ->values();

        return response()->json([
            'success' => true,
            'data' => [
                'drivers_online' => $driverMarkers,
                'sos' => $sosMarkers,
                'running_trips' => $runningTrips,
                'snapshot_at' => now()->toIso8601String(),
            ],
        ]);
    }

    /**
     * تتبع موقع سائق محدد: الموقع المباشر + آخر المواقع المسجّلة.
     * GET /admin/drivers/location-track?name=...|&driver_id=
     */
    public function driverLocationTrack(Request $request)
    {
        if (! $this->ensureStaff($request, 'drivers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driverId = (int) $request->query('driver_id', 0);
        $nameQuery = trim((string) $request->query('name', 'محمد محمد فخري ابراهيم'));

        $driver = null;
        if ($driverId > 0) {
            $driver = Driver::with('user')->find($driverId);
        }

        if (! $driver && $nameQuery !== '') {
            $like = '%'.$nameQuery.'%';
            $driver = Driver::with('user')
                ->whereHas('user', function ($q) use ($like) {
                    $q->whereRaw(
                        "TRIM(CONCAT(COALESCE(firstName,''),' ',COALESCE(lastName,''))) LIKE ?",
                        [$like]
                    )
                        ->orWhere('firstName', 'like', $like)
                        ->orWhere('lastName', 'like', $like)
                        ->orWhere('number', 'like', $like);
                })
                ->orderByDesc('id')
                ->first();
        }

        if (! $driver) {
            return response()->json([
                'success' => false,
                'message' => 'لم يتم العثور على السائق',
                'search' => $nameQuery,
            ], 404);
        }

        $id = (int) $driver->id;
        $user = $driver->user;
        $fullName = $user
            ? trim(($user->firstName ?? '').' '.($user->lastName ?? ''))
            : null;

        $live = null;
        $online = false;
        try {
            $online = (bool) Redis::exists('driver:'.$id.':online');
            $geo = DriverNearbyService::driverCoords($id);
            if ($geo) {
                $live = [
                    'latitude' => $geo['lat'],
                    'longitude' => $geo['lng'],
                    'online' => $online,
                ];
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('driverLocationTrack live: '.$e->getMessage());
        }

        $history = [];
        try {
            $raw = Redis::lrange('driver:'.$id.':loc_history', 0, 99);
            if (is_array($raw)) {
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
                    $history[] = [
                        'latitude' => $lat,
                        'longitude' => $lng,
                        'recorded_at' => $ts ? date('c', $ts) : null,
                        'unix' => $ts,
                    ];
                }
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('driverLocationTrack history: '.$e->getMessage());
        }

        // الأحدث أولاً في Redis — نعرض المسار من الأقدم للأحدث على الخريطة
        $historyChrono = array_reverse($history);

        return response()->json([
            'success' => true,
            'data' => [
                'driver' => [
                    'id' => $id,
                    'name' => $fullName,
                    'carNumber' => $driver->carNumber,
                    'phone' => $user?->number,
                    'online' => $online,
                ],
                'live' => $live,
                'history' => $historyChrono,
                'history_count' => count($historyChrono),
                'snapshot_at' => now()->toIso8601String(),
            ],
        ]);
    }

    /** تشخيص سريع: Redis + سائقون أونلاين + طلبات فورية معلّقة */
    public function dispatchHealth(Request $request)
    {
        if (! $this->ensureStaff($request, 'requests.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $staff = $request->user();

        $redisOk = false;
        $redisError = null;
        $geoDriverCount = 0;
        $onlineKeyCount = 0;

        try {
            Redis::ping();
            $redisOk = true;
            $ids = Redis::zrange('drivers', 0, -1);
            $geoDriverCount = is_array($ids) ? count($ids) : 0;
            $onlineKeyCount = $geoDriverCount;
        } catch (\Throwable $e) {
            $redisError = $e->getMessage();
        }

        if (AdminLimitedViewService::isLimitedAdmin($staff)) {
            $scopedMarkers = AdminLimitedViewService::filterDriverMarkers(
                $staff,
                $this->adminDriverMarkersFromRedis()
            );
            $geoDriverCount = count($scopedMarkers);
            $onlineKeyCount = $geoDriverCount;
        }

        $pendingQuery = RequestModel::query()
            ->where('type', RequestModel::TYPE_IMMEDIATE)
            ->where('status', RequestModel::STATUS_PENDING)
            ->where('created_at', '>=', now()->subMinutes(45));
        AdminLimitedViewService::scopeRequests($pendingQuery, $staff);
        $pendingImmediate = $pendingQuery->count();

        $markersCount = AdminLimitedViewService::isLimitedAdmin($staff)
            ? $geoDriverCount
            : count($this->adminDriverMarkersFromRedis());

        return response()->json([
            'success' => true,
            'data' => [
                'redis_ok' => $redisOk,
                'redis_error' => $redisError,
                'drivers_in_geo' => $geoDriverCount,
                'drivers_online_markers' => $markersCount,
                'pending_immediate_requests' => $pendingImmediate,
                'notify_radius_km' => DriverNearbyService::maxNotifyRadiusKm(),
                'display_radius_km' => DriverNearbyService::maxDisplayRadiusKm(),
                'checked_at' => now()->toIso8601String(),
            ],
        ]);
    }

    /**
     * مواقع السائقين للوحة الإدارة — بدون فلتر الاشتراك (عرض الموقع الفعلي).
     *
     * @return list<array<string, mixed>>
     */
    private function adminDriverMarkersFromRedis(): array
    {
        $markers = [];
        $seen = [];

        try {
            $ids = Redis::zrange('drivers', 0, -1);
            if (! is_array($ids)) {
                $ids = [];
            }

            $driverIds = array_values(array_unique(array_map('intval', $ids)));
            $drivers = $driverIds !== []
                ? Driver::with('user')->whereIn('id', $driverIds)->get()->keyBy('id')
                : collect();

            foreach ($ids as $rawId) {
                $id = (int) $rawId;
                if ($id <= 0 || isset($seen[$id])) {
                    continue;
                }
                $geo = DriverNearbyService::driverCoords($id);
                if (! $geo) {
                    continue;
                }
                $seen[$id] = true;
                $row = $drivers->get($id);
                $markers[] = $this->adminDriverMarkerPayload($id, $geo['lat'], $geo['lng'], $row);
            }

            // سائقون في رحلة جارية قد لا يظهرون في GEO — نُضيفهم إن وُجد موقعهم.
            $tripDriverIds = RequestModel::query()
                ->where('status', RequestModel::STATUS_RUNNING)
                ->whereNotNull('driverId')
                ->pluck('driverId')
                ->unique()
                ->map(fn ($v) => (int) $v)
                ->filter(fn ($v) => $v > 0);

            $missingIds = $tripDriverIds->filter(fn ($id) => ! isset($seen[$id]))->values()->all();
            if ($missingIds !== []) {
                $extra = Driver::with('user')->whereIn('id', $missingIds)->get()->keyBy('id');
                foreach ($missingIds as $id) {
                    $geo = DriverNearbyService::driverCoords($id);
                    if (! $geo) {
                        continue;
                    }
                    $markers[] = $this->adminDriverMarkerPayload(
                        $id,
                        $geo['lat'],
                        $geo['lng'],
                        $extra->get($id)
                    );
                }
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('admin mapSnapshot redis: '.$e->getMessage());
        }

        return $markers;
    }

    private function adminDriverMarkerPayload(int $id, float $lat, float $lng, ?Driver $row): array
    {
        return [
            'driverId' => $id,
            'latitude' => $lat,
            'longitude' => $lng,
            'carNumber' => $row?->carNumber,
            'name' => $row && $row->user ? trim($row->user->firstName.' '.$row->user->lastName) : null,
            'number' => $row?->user?->number,
            'kind' => 'driver_online',
        ];
    }

    /** موظفو لوحة الإدارة */
    public function employees(Request $request)
    {
        if (! $this->ensureAdmin($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $q = User::query()
            ->whereIn('roll', ['Admin', 'Employee'])
            ->orderBy('id', 'desc');

        if ($request->filled('search')) {
            $s = '%'.$request->search.'%';
            $q->where(function ($qq) use ($s) {
                $qq->where('firstName', 'like', $s)
                    ->orWhere('lastName', 'like', $s)
                    ->orWhere('number', 'like', $s);
            });
        }

        $users = $q->get(['id', 'firstName', 'lastName', 'number', 'roll', 'banned', 'expireDate', 'permissions', 'created_at']);

        return response()->json([
            'success' => true,
            'data' => $users,
        ]);
    }

    /** حذف حساب موظف/مسؤول (حذف منطقي) */
    public function destroyEmployee(Request $request, int $id)
    {
        if (! $this->ensureAdmin($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if ((int) $request->user()->id === $id) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكنك حذف حسابك الحالي',
            ], 400);
        }

        $employee = User::find($id);
        if (! $employee || ! in_array($employee->roll, ['Employee', 'Admin'], true)) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        if ($employee->roll === 'Admin') {
            $activeAdmins = User::query()
                ->where('roll', 'Admin')
                ->count();
            if ($activeAdmins <= 1) {
                return response()->json([
                    'success' => false,
                    'message' => 'لا يمكن حذف آخر مسؤول في النظام',
                ], 400);
            }
        }

        try {
            $employee->tokens()->delete();
        } catch (\Throwable $e) {
        }
        $employee->delete();

        return response()->json([
            'success' => true,
            'message' => 'تم حذف حساب الموظف',
        ]);
    }

    /** إنشاء موظف إداري */
    public function storeEmployee(Request $request)
    {
        if (! $this->ensureAdmin($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $data = $request->validate([
            'firstName' => 'required|string|max:255',
            'lastName' => 'required|string|max:255',
            'number' => 'required|string|max:30|unique:users,number',
            'password' => 'required|string|min:6|max:255',
            'roll' => ['required', Rule::in(['Employee', 'Admin'])],
            'permissions' => 'nullable|array',
            'permissions.*' => 'string|max:64',
        ]);

        $user = User::create([
            'firstName' => $data['firstName'],
            'lastName' => $data['lastName'],
            'number' => $data['number'],
            // نموذج User يطبّق cast «hashed» — مرّر كلمة السر صافية
            'password' => $data['password'],
            'roll' => $data['roll'],
            'permissions' => $data['permissions'] ?? [],
            'banned' => false,
            'expireDate' => Carbon::today()->addYear(),
        ]);

        return response()->json([
            'success' => true,
            'data' => $user->fresh()->makeHidden(['password']),
            'message' => 'تم إنشاء الموظف',
        ], 201);
    }

    /** تحديث صلاحيات موظف */
    public function updateEmployeePermissions(Request $request, int $id)
    {
        if (! $this->ensureAdmin($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $employee = User::find($id);
        if (! $employee || ! in_array($employee->roll, ['Employee', 'Admin'], true)) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'permissions' => 'required|array',
            'permissions.*' => 'string|max:64',
        ]);

        $allowed = [
            'drivers.read', 'drivers.write',
            'requests.read', 'requests.write',
            'discounts.write',
            'areas.read', 'areas.write',
            'reports.read',
            'customers.read',
        ];

        $clean = array_values(array_intersect($data['permissions'], $allowed));
        $employee->permissions = $clean;
        $employee->save();

        return response()->json([
            'success' => true,
            'data' => $employee->fresh()->makeHidden(['password']),
        ]);
    }

    /** الزبائن المسجّلون */
    public function customers(Request $request)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $q = User::query()->where('roll', 'Customer')->orderBy('id', 'desc');
        AdminLimitedViewService::scopeCustomers($q, $request->user());
        if ($request->boolean('include_deleted')) {
            $q->withTrashed();
        }
        if ($request->filled('search')) {
            $s = '%'.$request->search.'%';
            $q->where(function ($qq) use ($s) {
                $qq->where('firstName', 'like', $s)
                    ->orWhere('lastName', 'like', $s)
                    ->orWhere('number', 'like', $s);
            });
        }

        $perPage = (int) $request->get('per_page', 50);
        $perPage = min(max($perPage, 1), 500);

        $paginated = $q->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $paginated,
        ]);
    }

    /** حذف حساب زبون (حذف منطقي) */
    public function destroyCustomer(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $customer = User::query()->where('roll', 'Customer')->find($id);
        if (! $customer) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        if ($deny = AdminLimitedViewService::assertCustomerAccessible($request->user(), (int) $customer->id)) {
            return $deny;
        }

        try {
            $customer->tokens()->delete();
        } catch (\Throwable $e) {
        }
        $customer->delete();

        return response()->json([
            'success' => true,
            'message' => 'تم حذف حساب الزبون',
        ]);
    }

    /** جميع الطلبات للمراقبة والتتبع */
    public function requests(Request $request)
    {
        if (! $this->ensureStaff($request, 'requests.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $query = RequestModel::query()
            ->with(['user', 'driver.user', 'carType', 'startLocation', 'destLocation', 'discount', 'history'])
            ->orderBy('updated_at', 'desc');
        AdminLimitedViewService::scopeRequests($query, $request->user());

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        $billing = strtolower(trim((string) $request->input('billing_kind', '')));
        if ($billing === RequestModel::BILLING_KIND_FREE_METER) {
            $query->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER);
        } elseif ($billing === RequestModel::BILLING_KIND_APP_REQUEST || $billing === 'app') {
            $query->where(function ($q) {
                $q->whereNull('billing_kind')
                    ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
            });
        }

        $search = trim((string) $request->input('search', ''));
        if ($search !== '') {
            $escaped = addcslashes($search, '%_\\');
            $like = '%'.$escaped.'%';
            $query->where(function ($q) use ($like, $search) {
                if (ctype_digit($search)) {
                    $q->orWhere('id', (int) $search);
                }
                $q->orWhereHas('driver', function ($dq) use ($like) {
                    $dq->where('carNumber', 'like', $like)
                        ->orWhereHas('user', function ($uq) use ($like) {
                            $uq->where('firstName', 'like', $like)
                                ->orWhere('lastName', 'like', $like)
                                ->orWhere('number', 'like', $like)
                                ->orWhereRaw("CONCAT(COALESCE(firstName,''),' ',COALESCE(lastName,'')) LIKE ?", [$like]);
                        });
                })->orWhereHas('user', function ($uq) use ($like) {
                    $uq->where('firstName', 'like', $like)
                        ->orWhere('lastName', 'like', $like)
                        ->orWhere('number', 'like', $like)
                        ->orWhereRaw("CONCAT(COALESCE(firstName,''),' ',COALESCE(lastName,'')) LIKE ?", [$like]);
                });
            });
        }

        $perPage = (int) $request->get('per_page', 50);
        $perPage = min(max($perPage, 1), 200);
        $paginated = $query->paginate($perPage);

        $paginated->getCollection()->transform(function (RequestModel $req) {
            $arr = $req->toArray();

            return LocationDisplayService::enrichRequestArray($arr, $req, allowReverse: false);
        });

        return response()->json([
            'success' => true,
            'data' => $paginated,
        ]);
    }

    /** إزالة طلب من لوحة التحكم — انتظار أو عالق بعد القبول */
    public function expirePendingRequest(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'requests.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::find($id);
        if ($deny = AdminLimitedViewService::assertRequestAccessible($request->user(), $req)) {
            return $deny;
        }

        $status = RequestModel::normalizeTripStatus($req->status);
        if ($status === RequestModel::STATUS_REMOVED) {
            return response()->json([
                'success' => true,
                'data' => $req->fresh(),
                'message' => 'الطلب ملغى مسبقاً',
            ]);
        }
        if ($status === RequestModel::STATUS_FINISHED) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إلغاء رحلة مكتملة',
            ], 400);
        }
        if ($status === RequestModel::STATUS_RUNNING && $req->trip_started_at !== null) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إلغاء رحلة جارية فعلياً — استخدم إنهاء الرحلة',
            ], 400);
        }

        $req->status = RequestModel::STATUS_REMOVED;
        $req->cancel_reason = $request->input('reason', 'admin_expire_pending');
        $req->save();

        try {
            Redis::del('request:'.$req->id.':eligible');
        } catch (\Throwable $e) {
        }

        try {
            DriverPollCacheService::bust();
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => $req->fresh(),
            'message' => 'تم إلغاء الطلب',
        ]);
    }

    /** إلغاء طلب نشط أو جاري — من لوحة التحكم / خريطة العمليات */
    public function cancelActiveRequest(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'requests.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::find($id);
        if ($deny = AdminLimitedViewService::assertRequestAccessible($request->user(), $req)) {
            return $deny;
        }

        $status = RequestModel::normalizeTripStatus($req->status);
        if ($status === RequestModel::STATUS_REMOVED) {
            return response()->json([
                'success' => true,
                'data' => $req->fresh(),
                'message' => 'الطلب ملغى مسبقاً',
            ]);
        }
        if ($status === RequestModel::STATUS_FINISHED) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن إلغاء رحلة مكتملة',
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

        $assignedDriverId = $req->driverId ? (int) $req->driverId : null;

        $req->status = RequestModel::STATUS_REMOVED;
        $req->cancel_reason = $request->input('reason', 'admin_map_cancel');
        $req->save();

        if ($assignedDriverId) {
            try {
                broadcast(new RequestCancelledByCustomerEvent($assignedDriverId, (int) $req->id));
            } catch (\Throwable $e) {
            }
        }

        try {
            DriverPollCacheService::bust();
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => $req->fresh(),
            'message' => 'تم إلغاء الرحلة',
        ]);
    }

    /** آراء الزبائن (شكاوى + تقييم) مع تفاصيل الرحلة */
    public function complaintsReviews(Request $request)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $query = Complaint::with([
            'request.user',
            'request.driver.user',
            'request.driver.transType',
            'request.startLocation',
            'request.destLocation',
            'request.carType',
            'request.serviceArea',
            'request.history',
            'request.discount',
            'driver.user',
            'driver.transType',
        ])->orderBy('created_at', 'desc');
        AdminLimitedViewService::scopeComplaints($query, $request->user());

        if ($request->filled('from_date')) {
            $query->whereDate('created_at', '>=', $request->from_date);
        }
        if ($request->filled('to_date')) {
            $query->whereDate('created_at', '<=', $request->to_date);
        }

        $paginated = $query->paginate((int) $request->get('per_page', 25));

        $paginated->getCollection()->transform(function (Complaint $complaint) {
            $arr = $complaint->toArray();

            $req = $complaint->request;
            if ($req) {
                $arr['request'] = LocationDisplayService::enrichRequestArray(
                    $req->toArray(),
                    $req,
                    allowReverse: true
                );
            }

            $driver = $complaint->driver ?? $req?->driver;
            $driverUser = $driver?->user;
            $passenger = $req?->user;

            $arr['passenger_name'] = $passenger
                ? trim(($passenger->firstName ?? '').' '.($passenger->lastName ?? ''))
                : null;
            $arr['passenger_phone'] = $passenger?->number;
            $arr['driver_name'] = $driverUser
                ? trim(($driverUser->firstName ?? '').' '.($driverUser->lastName ?? ''))
                : null;
            $arr['driver_phone'] = $driverUser?->number;
            $arr['car_number'] = $driver?->carNumber;
            $arr['vehicle_model'] = $driver?->vehicle_model ?? null;
            $arr['car_type_name'] = $req?->carType?->name
                ?? $driver?->transType?->name
                ?? null;

            $enrichedReq = is_array($arr['request'] ?? null) ? $arr['request'] : [];
            $arr['pickup_label'] = $enrichedReq['pickup_label']
                ?? $enrichedReq['pickupLabel']
                ?? null;
            $arr['dest_label'] = $enrichedReq['dest_label']
                ?? $enrichedReq['destLabel']
                ?? null;

            $history = $req?->history;
            $arr['final_cost'] = $history?->finalCost
                ?? $req?->predectedCost
                ?? null;
            $arr['trip_status'] = $req?->status;
            $arr['trip_type'] = $req?->type;
            $arr['predicted_cost'] = $req?->predectedCost;
            $arr['location_desc'] = $req?->locationDesc ?? null;
            $arr['service_area_name'] = $req?->serviceArea?->name;
            $arr['trip_started_at'] = $req?->trip_started_at;
            $arr['created_request_at'] = $req?->created_at;

            return $arr;
        });

        return response()->json([
            'success' => true,
            'data' => $paginated,
        ]);
    }

    /** مناطق الخدمة (دمشق وريفها — قابلة للتوسعة) */
    public function serviceAreas(Request $request)
    {
        if (! $this->ensureStaff($request, 'areas.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $areas = ServiceArea::query()->orderBy('sort_order')->orderBy('id')->get();

        return response()->json(['success' => true, 'data' => $areas]);
    }

    public function storeServiceArea(Request $request)
    {
        if (! $this->ensureStaff($request, 'areas.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $data = $request->validate([
            'name' => 'required|string|max:255',
            'active' => 'sometimes|boolean',
            'sort_order' => 'sometimes|integer|min:0',
            'south_lat' => 'sometimes|nullable|numeric|between:-90,90',
            'north_lat' => 'sometimes|nullable|numeric|between:-90,90',
            'west_lng' => 'sometimes|nullable|numeric|between:-180,180',
            'east_lng' => 'sometimes|nullable|numeric|between:-180,180',
        ]);

        $row = ServiceArea::create([
            'name' => $data['name'],
            'active' => $data['active'] ?? true,
            'sort_order' => $data['sort_order'] ?? 0,
            'south_lat' => $data['south_lat'] ?? null,
            'north_lat' => $data['north_lat'] ?? null,
            'west_lng' => $data['west_lng'] ?? null,
            'east_lng' => $data['east_lng'] ?? null,
        ]);

        return response()->json(['success' => true, 'data' => $row], 201);
    }

    public function updateServiceArea(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'areas.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $row = ServiceArea::find($id);
        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'sometimes|string|max:255',
            'active' => 'sometimes|boolean',
            'sort_order' => 'sometimes|integer|min:0',
            'south_lat' => 'sometimes|nullable|numeric|between:-90,90',
            'north_lat' => 'sometimes|nullable|numeric|between:-90,90',
            'west_lng' => 'sometimes|nullable|numeric|between:-180,180',
            'east_lng' => 'sometimes|nullable|numeric|between:-180,180',
        ]);

        $row->fill($data);
        $row->save();

        return response()->json(['success' => true, 'data' => $row->fresh()]);
    }

    /** إرسال إشعار داخل التطبيق للراكبين عن كوبون */
    public function notifyDiscountCustomers(Request $request, int $discountId)
    {
        if (! $this->ensureStaff($request, 'discounts.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $discount = Discount::find($discountId);
        if (! $discount) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $phones = $discount->target_phones;
        $q = User::query()->where('roll', 'Customer');
        AdminLimitedViewService::scopeCustomers($q, $request->user());
        if (is_array($phones) && count($phones) > 0) {
            $q->whereIn('number', $phones);
        }
        $users = $q->get(['id']);

        $title = 'كوبون خصم';
        $body = 'رمز الكوبون: '.$discount->code.'. يمكنك استخدامه مرة واحدة ضمن مدة صلاحيته.';
        $count = 0;
        foreach ($users as $u) {
            CustomerNotification::create([
                'user_id' => $u->id,
                'title' => $title,
                'body' => $body,
                'kind' => 'discount',
                'reference_type' => 'discount',
                'reference_id' => $discount->id,
            ]);
            $count++;
        }

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء '.$count.' إشعاراً للراكبين',
            'data' => ['notifications_created' => $count],
        ]);
    }

    /** تفاصيل طلب واحد للإدارة */
    public function requestDetail(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'requests.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::query()
            ->with([
                'user',
                'driver.user',
                'carType',
                'discount',
                'serviceArea',
                'startLocation',
                'destLocation',
                'history.driver.user',
            ])
            ->find($id);

        if ($deny = AdminLimitedViewService::assertRequestAccessible($request->user(), $req)) {
            return $deny;
        }

        $data = LocationDisplayService::enrichRequestArray($req->toArray(), $req, allowReverse: true);
        try {
            $data['trip_analytics'] = TripTraceService::analyticsPayload($req);
        } catch (\Throwable $e) {
            $data['trip_analytics'] = null;
        }

        // موقع السائق الحي للرحلات النشطة
        $driverId = (int) ($req->driverId ?? 0);
        $activeStatuses = [
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
            RequestModel::STATUS_RUNNING,
        ];
        if ($driverId > 0 && in_array(RequestModel::normalizeTripStatus($req->status), $activeStatuses, true)) {
            try {
                $live = DriverNearbyService::driverCoords($driverId);
                if ($live) {
                    $data['driver_live'] = [
                        'latitude' => $live['lat'],
                        'longitude' => $live['lng'],
                    ];
                }
            } catch (\Throwable $e) {
            }
        }

        return response()->json(['success' => true, 'data' => $data]);
    }

    /**
     * إنشاء طلب فوري من الأدمن وإرساله لسائق محدد (قبول/رفض كطلب عادي).
     * POST /admin/requests/dispatch-to-driver
     */
    public function dispatchToDriver(Request $request)
    {
        if (! $this->ensureStaff($request, 'requests.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $validated = $request->validate([
            'driver_id' => 'required|integer|min:1',
            'customer_id' => 'nullable|integer|min:1',
            'customer_phone' => 'nullable|string|max:40',
            'customer_first_name' => 'nullable|string|max:80',
            'customer_last_name' => 'nullable|string|max:80',
            'customer_name' => 'nullable|string|max:120',
            'start_lat' => 'required|numeric|between:-90,90',
            'start_lng' => 'required|numeric|between:-180,180',
            'dest_lat' => 'required|numeric|between:-90,90',
            'dest_lng' => 'required|numeric|between:-180,180',
            'start_name' => 'nullable|string|max:200',
            'dest_name' => 'nullable|string|max:200',
            'location_desc' => 'nullable|string|max:500',
            'car_type_id' => 'nullable|integer|min:1',
            'estimated_trip_km' => 'nullable|numeric|min:0',
            'estimated_duration_minutes' => 'nullable|numeric|min:0',
            'predected_cost' => 'nullable|numeric|min:0',
        ]);

        try {
            $out = app(\App\Services\AdminDispatchTripService::class)->dispatch($validated);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'تعذر إنشاء الطلب: '.$e->getMessage(),
            ], 500);
        }

        $req = $out['request'];
        $customer = $out['customer'];
        $driver = $out['driver'];

        return response()->json([
            'success' => true,
            'message' => 'تم إرسال الطلب للسائق — سيظهر كطلب فوري عادي للقبول أو الرفض',
            'data' => [
                'id' => $req->id,
                'status' => $req->status,
                'predectedCost' => $out['fare'],
                'estimated_distance_km' => $req->estimated_distance_km ?? null,
                'estimated_duration_minutes' => $req->estimated_duration_minutes,
                'created_customer' => $out['created_customer'],
                'customer' => [
                    'id' => $customer->id,
                    'name' => trim(($customer->firstName ?? '').' '.($customer->lastName ?? '')),
                    'number' => $customer->number,
                ],
                'driver' => [
                    'id' => $driver->id,
                    'name' => trim(($driver->user->firstName ?? '').' '.($driver->user->lastName ?? '')),
                ],
            ],
        ], 201);
    }

    /**
     * متابعة رحلة جارية مباشرة (حمولة خفيفة — بدون إعادة تحميل الخريطة كاملة).
     * GET /admin/running-trips/{id}/live
     */
    public function liveTripWatch(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'requests.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::query()->find($id);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        if ($deny = AdminLimitedViewService::assertRequestAccessible($request->user(), $req)) {
            return $deny;
        }

        return response()->json([
            'success' => true,
            'data' => TripTraceService::liveWatchPayload($req),
        ]);
    }

    /**
     * بث مستمر لموقع السائق أثناء مراقبة رحلة (SSE) — بدون استطلاع من الواجهة كل ثانية.
     * GET /admin/running-trips/{id}/live-stream
     */
    public function liveTripStream(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'requests.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = RequestModel::query()->find($id);
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        if ($deny = AdminLimitedViewService::assertRequestAccessible($request->user(), $req)) {
            return $deny;
        }

        return response()->stream(function () use ($id) {
            $lastKey = '';
            $maxTicks = 900; // ~15 دقيقة بفاصل ثانية
            for ($i = 0; $i < $maxTicks; $i++) {
                if (connection_aborted()) {
                    break;
                }
                $req = RequestModel::query()->find($id);
                if (! $req) {
                    echo 'data: '.json_encode(['ended' => true, 'status' => 'Gone'])."\n\n";
                    if (function_exists('ob_flush')) {
                        @ob_flush();
                    }
                    @flush();
                    break;
                }
                $payload = TripTraceService::liveWatchPayload($req);
                $key = json_encode([
                    $payload['status'] ?? null,
                    $payload['driver_live']['latitude'] ?? null,
                    $payload['driver_live']['longitude'] ?? null,
                    $payload['ended'] ?? false,
                ]);
                // أرسل فقط عند تغيّر الموقع/الحالة أو كل ~8 ثوانٍ كنبضة
                if ($key !== $lastKey || ($i % 8) === 0) {
                    $lastKey = $key;
                    echo 'data: '.json_encode($payload, JSON_UNESCAPED_UNICODE)."\n\n";
                    if (function_exists('ob_flush')) {
                        @ob_flush();
                    }
                    @flush();
                }
                if (! empty($payload['ended'])) {
                    break;
                }
                usleep(1000000); // فحص كل ثانية على السيرفر — الواجهة لا تعيد تحميل الصفحة
            }
        }, 200, [
            'Content-Type' => 'text/event-stream; charset=UTF-8',
            'Cache-Control' => 'no-cache, no-store',
            'Connection' => 'keep-alive',
            'X-Accel-Buffering' => 'no',
        ]);
    }

    public function destroyServiceArea(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'areas.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $row = ServiceArea::find($id);
        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        $row->delete();

        return response()->json(['success' => true]);
    }

    /** تقرير CSV بسيط: السائقون أو الزبائن */
    public function exportUsersCsv(Request $request)
    {
        if (! $this->ensureStaff($request, 'reports.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $kind = $request->get('kind', 'customers');
        $roll = $kind === 'drivers' ? 'Driver' : 'Customer';

        $rowsQuery = User::query()
            ->where('roll', $roll)
            ->orderBy('id');
        if ($roll === 'Customer') {
            AdminLimitedViewService::scopeCustomers($rowsQuery, $request->user());
        } elseif ($roll === 'Driver') {
            $driverUserIds = Driver::query();
            AdminLimitedViewService::scopeDrivers($driverUserIds, $request->user());
            $rowsQuery->whereIn('id', $driverUserIds->pluck('userId'));
        }
        $rows = $rowsQuery->get(['id', 'firstName', 'lastName', 'number', 'created_at']);

        $csv = "id,firstName,lastName,number,created_at\n";
        foreach ($rows as $u) {
            $csv .= sprintf(
                "%s,%s,%s,%s,%s\n",
                $u->id,
                str_replace(',', ' ', $u->firstName),
                str_replace(',', ' ', $u->lastName),
                $u->number,
                $u->created_at
            );
        }

        $filename = $kind.'_'.now()->format('Y-m-d').'.csv';

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
        ]);
    }

    private const FREE_METER_OPEN_KEY = 'free_meter_open_price';

    private const FREE_METER_KM_KEY = 'free_meter_km_price';

    private const FREE_METER_TIME_KEY = 'free_meter_time_price';

    /** إعدادات العداد الحر: سعر الفتح + الكيلومتر + الدقيقة (عام للوحة الإدارة) */
    public function freeMeterSettings(Request $request)
    {
        if (! $this->ensureStaff($request, 'drivers.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return response()->json([
            'success' => true,
            'data' => [
                'openPrice' => AppSetting::getDecimal(self::FREE_METER_OPEN_KEY, 0.0),
                'kmPrice' => AppSetting::getDecimal(self::FREE_METER_KM_KEY, 0.0),
                'timePrice' => AppSetting::getDecimal(self::FREE_METER_TIME_KEY, 0.0),
            ],
        ]);
    }

    public function updateFreeMeterSettings(Request $request)
    {
        if (! $this->ensureStaff($request, 'drivers.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'openPrice' => 'required|numeric|min:0|max:99999999.99',
            'kmPrice' => 'required|numeric|min:0|max:99999999.99',
            'timePrice' => 'required|numeric|min:0|max:99999999.99',
        ]);

        AppSetting::setValue(
            self::FREE_METER_OPEN_KEY,
            (string) round((float) $v['openPrice'], 2)
        );
        AppSetting::setValue(
            self::FREE_METER_KM_KEY,
            (string) round((float) $v['kmPrice'], 4)
        );
        AppSetting::setValue(
            self::FREE_METER_TIME_KEY,
            (string) round((float) $v['timePrice'], 4)
        );

        return response()->json([
            'success' => true,
            'message' => 'تم حفظ إعدادات العداد الحر',
            'data' => [
                'openPrice' => AppSetting::getDecimal(self::FREE_METER_OPEN_KEY, 0.0),
                'kmPrice' => AppSetting::getDecimal(self::FREE_METER_KM_KEY, 0.0),
                'timePrice' => AppSetting::getDecimal(self::FREE_METER_TIME_KEY, 0.0),
            ],
        ]);
    }

    /** أعداد السائقين حسب فئة المركبة (مطابقة لوحة التحكم — جدول drivers). */
    public function driverStats(Request $request)
    {
        if (! $this->ensureStaff($request, 'drivers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $driverBase = Driver::query();
        AdminLimitedViewService::scopeDrivers($driverBase, $request->user());

        $total = (clone $driverBase)->count();
        $blockedTotal = (clone $driverBase)->where('subscription_blocked', true)->count();

        $byCategory = (clone $driverBase)
            ->select('transTypeId', DB::raw('count(*) as count'))
            ->whereNotNull('transTypeId')
            ->where('transTypeId', '>', 0)
            ->groupBy('transTypeId')
            ->pluck('count', 'transTypeId');

        $byCategoryList = [];
        foreach ($byCategory as $transTypeId => $count) {
            $byCategoryList[] = [
                'transTypeId' => (int) $transTypeId,
                'count' => (int) $count,
            ];
        }

        return response()->json([
            'success' => true,
            'data' => [
                'total' => $total,
                'blocked_total' => $blockedTotal,
                'by_category' => $byCategoryList,
            ],
        ]);
    }

    /**
     * رحلات سائق معيّن مع فلتر تاريخ (من/إلى).
     * GET /admin/drivers/{id}/trips?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD
     */
    public function driverTrips(Request $request, int $id)
    {
        if (! $this->ensureStaff($request, 'drivers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }

        $driver = Driver::with('user')->find($id);
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'السائق غير موجود'], 404);
        }

        $fromDate = $request->filled('from_date')
            ? Carbon::parse($request->input('from_date'))->toDateString()
            : Carbon::today()->toDateString();
        $toDate = $request->filled('to_date')
            ? Carbon::parse($request->input('to_date'))->toDateString()
            : $fromDate;

        if ($toDate < $fromDate) {
            [$fromDate, $toDate] = [$toDate, $fromDate];
        }

        $query = RequestModel::query()
            ->where('driverId', $id)
            ->where('status', RequestModel::STATUS_FINISHED)
            ->with(['user', 'startLocation', 'destLocation', 'carType', 'history', 'discount'])
            ->where(function ($q) use ($fromDate, $toDate) {
                $q->where(function ($inner) use ($fromDate, $toDate) {
                    $inner->whereNotNull('trip_started_at')
                        ->whereDate('trip_started_at', '>=', $fromDate)
                        ->whereDate('trip_started_at', '<=', $toDate);
                })->orWhere(function ($inner) use ($fromDate, $toDate) {
                    $inner->whereNull('trip_started_at')
                        ->whereDate('requestDate', '>=', $fromDate)
                        ->whereDate('requestDate', '<=', $toDate);
                })->orWhere(function ($inner) use ($fromDate, $toDate) {
                    $inner->whereNull('trip_started_at')
                        ->whereNull('requestDate')
                        ->whereDate('created_at', '>=', $fromDate)
                        ->whereDate('created_at', '<=', $toDate);
                });
            })
            ->orderByDesc('trip_started_at')
            ->orderByDesc('id');

        AdminLimitedViewService::scopeRequests($query, $request->user());

        $rows = $query->get()->map(function (RequestModel $req) {
            $arr = LocationDisplayService::enrichRequestArray(
                $req->toArray(),
                $req,
                allowReverse: true
            );
            $hist = $req->history;
            $arr['final_cost'] = $hist?->finalCost;
            $arr['distance_traveled_km'] = $hist?->distanceTraveledKm;
            $arr['billing_kind'] = $req->billing_kind;
            $arr['path_label'] = $req->billing_kind === RequestModel::BILLING_KIND_FREE_METER
                ? 'رحلة عداد حر'
                : 'رحلة طلب عبر التطبيق';
            $arr['trip_day'] = optional($req->trip_started_at ?? $req->requestDate ?? $req->created_at)
                ?->timezone(config('app.timezone'))
                ?->toDateString();

            return $arr;
        })->values();

        $sumRevenue = 0.0;
        $freeMeterCount = 0;
        $appCount = 0;
        foreach ($rows as $row) {
            $sumRevenue += (float) ($row['final_cost'] ?? 0);
            if (($row['billing_kind'] ?? '') === RequestModel::BILLING_KIND_FREE_METER) {
                $freeMeterCount++;
            } else {
                $appCount++;
            }
        }

        return response()->json([
            'success' => true,
            'data' => [
                'driver' => [
                    'id' => $driver->id,
                    'name' => trim(($driver->user->firstName ?? '').' '.($driver->user->lastName ?? '')),
                    'car_number' => $driver->carNumber,
                ],
                'from_date' => $fromDate,
                'to_date' => $toDate,
                'summary' => [
                    'trips_count' => $rows->count(),
                    'app_trips' => $appCount,
                    'free_meter_trips' => $freeMeterCount,
                    'total_fare' => round($sumRevenue, 2),
                ],
                'trips' => $rows,
            ],
        ]);
    }
}
