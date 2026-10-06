<?php

namespace App\Http\Controllers;

use App\Models\CarType;
use App\Models\Driver;
use App\Models\RequestModel;
use App\Services\DriverPollCacheService;
use App\Services\ImmediatePendingForDriver;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

/**
 * استطلاع موحّد للسائق — طلب HTTP واحد بدل immediate-pending + driver/{id}.
 */
class DriverPollController extends Controller
{
    public function snapshot(Request $request)
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
        $cacheKey = DriverPollCacheService::pollSnapshotKey($driverId);

        $payload = Cache::remember($cacheKey, DriverPollCacheService::TTL_SNAPSHOT, function () use ($driver, $driverId) {
            $pending = ImmediatePendingForDriver::queryForDriver($driver)
                ->map(fn ($m) => ImmediatePendingForDriver::toDriverPayload($driver, $m))
                ->values()
                ->all();
            $driverTypeId = (int) $driver->transTypeId;
            $assigned = array_map(function ($m) use ($driverTypeId) {
                $row = $m instanceof RequestModel ? $m->toArray() : (array) $m;
                $row['cross_category_note'] = CarType::crossCategoryNote((int) ($row['carTypeId'] ?? 0), $driverTypeId);

                return ImmediatePendingForDriver::hidePassengerContact($row);
            }, $this->buildDriverRequests($driverId));

            return [
                'immediate_pending' => $pending,
                'driver_requests' => $assigned,
                'cached_at' => now()->toIso8601String(),
            ];
        });

        DriverPollCacheService::rememberPollSnapshotLast($driverId, $payload);

        return response()->json([
            'success' => true,
            'data' => $payload,
        ]);
    }

    /**
     * @return array<int, mixed>
     */
    private function buildDriverRequests(int $driverId): array
    {
        $cacheKey = DriverPollCacheService::driverRequestsKey($driverId);

        $rows = Cache::remember($cacheKey, DriverPollCacheService::TTL_DRIVER_REQUESTS, function () use ($driverId) {
            return RequestModel::query()
                ->where('driverId', $driverId)
                ->whereNotIn('status', [
                    RequestModel::STATUS_REMOVED,
                    RequestModel::STATUS_FINISHED,
                ])
                ->with(['user', 'startLocation', 'destLocation', 'carType'])
                ->orderByDesc('created_at')
                ->get()
                ->all();
        });
        // نفس المفتاح يُخزَّن أيضاً كـ Collection من RequestController::driverRequests
        $rows = $rows instanceof \Illuminate\Support\Collection ? $rows->all() : (array) $rows;

        DriverPollCacheService::rememberDriverRequestsLast($driverId, $rows);

        return $rows;
    }
}
