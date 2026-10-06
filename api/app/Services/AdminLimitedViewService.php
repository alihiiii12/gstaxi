<?php

namespace App\Services;

use App\Models\Driver;
use App\Models\RequestModel;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * عرض محدود للوحة الإدارة: مجموعة عشوائية ثابتة من السائقين والزبائن.
 */
class AdminLimitedViewService
{
    public static function isLimitedAdmin(?User $user): bool
    {
        if (! $user) {
            return false;
        }

        $needles = config('admin_limited_view.phone_numbers', []);
        if (! is_array($needles) || $needles === []) {
            return false;
        }

        $hay = self::normalizePhone($user->number);
        foreach ($needles as $phone) {
            if (self::phonesMatch($hay, self::normalizePhone((string) $phone))) {
                return true;
            }
        }

        return false;
    }

    /** @return list<int>|null null = بدون تقييد */
    public static function scopedDriverIds(?User $user): ?array
    {
        if (! self::isLimitedAdmin($user)) {
            return null;
        }

        $key = 'admin_limited_view:drivers:'.self::normalizePhone($user->number);

        return Cache::rememberForever($key, function () {
            $limit = (int) config('admin_limited_view.driver_limit', 50);

            return Driver::query()
                ->inRandomOrder()
                ->limit($limit)
                ->pluck('id')
                ->map(fn ($id) => (int) $id)
                ->values()
                ->all();
        });
    }

    /** @return list<int>|null معرّفات users للزبائن */
    public static function scopedCustomerUserIds(?User $user): ?array
    {
        if (! self::isLimitedAdmin($user)) {
            return null;
        }

        $key = 'admin_limited_view:customers:'.self::normalizePhone($user->number);

        return Cache::rememberForever($key, function () {
            $limit = (int) config('admin_limited_view.customer_limit', 60);

            return User::query()
                ->where('roll', 'Customer')
                ->inRandomOrder()
                ->limit($limit)
                ->pluck('id')
                ->map(fn ($id) => (int) $id)
                ->values()
                ->all();
        });
    }

    public static function scopeDrivers(Builder $query, ?User $user): Builder
    {
        $ids = self::scopedDriverIds($user);
        if ($ids === null) {
            return $query;
        }

        return $query->whereIn('id', $ids);
    }

    public static function scopeCustomers(Builder $query, ?User $user): Builder
    {
        $ids = self::scopedCustomerUserIds($user);
        if ($ids === null) {
            return $query;
        }

        return $query->whereIn('id', $ids);
    }

    public static function scopeRequests(Builder $query, ?User $user): Builder
    {
        $driverIds = self::scopedDriverIds($user);
        $customerIds = self::scopedCustomerUserIds($user);
        if ($driverIds === null || $customerIds === null) {
            return $query;
        }

        return $query->where(function (Builder $q) use ($driverIds, $customerIds) {
            $q->whereIn('userId', $customerIds)
                ->orWhereIn('driverId', $driverIds);
        });
    }

    public static function scopeRequestHistories(Builder $query, ?User $user): Builder
    {
        $driverIds = self::scopedDriverIds($user);
        $customerIds = self::scopedCustomerUserIds($user);
        if ($driverIds === null || $customerIds === null) {
            return $query;
        }

        return $query->where(function (Builder $q) use ($driverIds, $customerIds) {
            $q->whereIn('driverId', $driverIds)
                ->orWhereHas('request', function (Builder $rq) use ($customerIds) {
                    $rq->whereIn('userId', $customerIds);
                });
        });
    }

    public static function scopeComplaints(Builder $query, ?User $user): Builder
    {
        $driverIds = self::scopedDriverIds($user);
        $customerIds = self::scopedCustomerUserIds($user);
        if ($driverIds === null || $customerIds === null) {
            return $query;
        }

        return $query->where(function (Builder $q) use ($driverIds, $customerIds) {
            $q->whereIn('driverId', $driverIds)
                ->orWhereHas('request', function (Builder $rq) use ($customerIds) {
                    $rq->whereIn('userId', $customerIds);
                });
        });
    }

    public static function requestInScope(?User $user, RequestModel $req): bool
    {
        if (! self::isLimitedAdmin($user)) {
            return true;
        }

        $driverIds = self::scopedDriverIds($user) ?? [];
        $customerIds = self::scopedCustomerUserIds($user) ?? [];

        $customerId = (int) ($req->userId ?? 0);
        $driverId = (int) ($req->driverId ?? 0);

        if ($customerId > 0 && in_array($customerId, $customerIds, true)) {
            return true;
        }

        if ($driverId > 0 && in_array($driverId, $driverIds, true)) {
            return true;
        }

        return false;
    }

    public static function assertDriverAccessible(?User $user, int $driverId): ?JsonResponse
    {
        if (! self::isLimitedAdmin($user)) {
            return null;
        }

        $ids = self::scopedDriverIds($user) ?? [];
        if (! in_array($driverId, $ids, true)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return null;
    }

    public static function assertCustomerAccessible(?User $user, int $customerUserId): ?JsonResponse
    {
        if (! self::isLimitedAdmin($user)) {
            return null;
        }

        $ids = self::scopedCustomerUserIds($user) ?? [];
        if (! in_array($customerUserId, $ids, true)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return null;
    }

    public static function assertRequestAccessible(?User $user, ?RequestModel $req): ?JsonResponse
    {
        if (! $req) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        if (! self::requestInScope($user, $req)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return null;
    }

    public static function assertCanCreate(?User $user): ?JsonResponse
    {
        if (! self::isLimitedAdmin($user)) {
            return null;
        }

        return response()->json([
            'success' => false,
            'message' => 'غير مسموح بإضافة سجلات جديدة من هذا الحساب',
        ], 403);
    }

    /** @param list<array<string, mixed>> $markers */
    public static function filterDriverMarkers(?User $user, array $markers): array
    {
        $ids = self::scopedDriverIds($user);
        if ($ids === null) {
            return $markers;
        }

        $allowed = array_flip($ids);

        return array_values(array_filter($markers, function (array $m) use ($allowed) {
            $id = (int) ($m['driverId'] ?? 0);

            return $id > 0 && isset($allowed[$id]);
        }));
    }

    /** @param list<array<string, mixed>> $items */
    public static function filterSosItems(?User $user, array $items): array
    {
        $ids = self::scopedDriverIds($user);
        if ($ids === null) {
            return $items;
        }

        $allowed = array_flip($ids);

        return array_values(array_filter($items, function (array $item) use ($allowed) {
            $role = strtolower((string) ($item['role'] ?? 'driver'));
            // تنبيهات الركاب تظهر لكل من لديه صلاحية قراءة الطلبات (حتى ضمن النطاق المحدود).
            if ($role === 'customer') {
                return true;
            }
            $id = (int) ($item['driverId'] ?? 0);

            return $id > 0 && isset($allowed[$id]);
        }));
    }

    public static function sumRevenueBetween(?User $user, Carbon $from, Carbon $to): float
    {
        $query = RequestModel::query()
            ->where(TripRevenueService::finishedRevenueScope())
            ->whereBetween('updated_at', [$from, $to])
            ->with(['history', 'carType']);

        self::scopeRequests($query, $user);

        $revenue = 0.0;
        $query->chunkById(150, function ($rows) use (&$revenue) {
            foreach ($rows as $row) {
                $revenue += TripRevenueService::tripAmount($row);
            }
        });

        return round($revenue, 2);
    }

    /**
     * @param  'all'|'app'|'free_meter'  $billing
     */
    public static function countFinishedBetween(
        ?User $user,
        Carbon $from,
        Carbon $to,
        string $billing = 'all'
    ): int {
        $query = RequestModel::query()
            ->where('status', RequestModel::STATUS_FINISHED)
            ->whereBetween('updated_at', [$from, $to]);

        if (TripRevenueService::hasBillingColumns()) {
            if ($billing === 'free_meter') {
                $query->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER);
            } elseif ($billing === 'app') {
                $query->where(function ($q) {
                    $q->whereNull('billing_kind')
                        ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
                });
            }
        }

        return self::scopeRequests($query, $user)->count();
    }

    public static function normalizePhone(?string $number): string
    {
        return preg_replace('/\D+/', '', (string) $number) ?? '';
    }

    /** يقرأ المستخدم من الجلسة أو من Bearer token (للمسارات بدون middleware). */
    public static function resolveStaffUser(Request $request): ?User
    {
        $user = $request->user();
        if ($user instanceof User) {
            return $user;
        }

        $token = $request->bearerToken();
        if (! is_string($token) || $token === '') {
            return null;
        }

        $access = PersonalAccessToken::findToken($token);
        $tokenable = $access?->tokenable;

        return $tokenable instanceof User ? $tokenable : null;
    }

    private static function phonesMatch(string $a, string $b): bool
    {
        if ($a === '' || $b === '') {
            return false;
        }
        if ($a === $b) {
            return true;
        }

        return ltrim($a, '0') === ltrim($b, '0');
    }
}
