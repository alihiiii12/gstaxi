<?php

/*
 * أضف/عدّل في RequestController::getDriverRequests — cache 4 ثوانٍ.
 * عدّل أسماء الأعمدة/الثوابت حسب مشروعك إن اختلفت.
 */
public function getDriverRequests(\Illuminate\Http\Request $request, $driverId)
{
    $user = $request->user();
    if (! $user || $user->roll !== 'Driver') {
        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
    }

    $driver = \App\Models\Driver::where('userId', $user->id)->first();
    if (! $driver || (int) $driver->id !== (int) $driverId) {
        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
    }

    $did = (int) $driverId;
    $cacheKey = 'driver_requests:'.$did;

    $rows = \Illuminate\Support\Facades\Cache::remember($cacheKey, 4, function () use ($did) {
        return \App\Models\RequestModel::query()
            ->where(function ($q) use ($did) {
                $q->where('driverId', $did)->orWhere('targetDriverId', $did);
            })
            ->whereIn('status', [
                \App\Models\RequestModel::STATUS_PENDING,
                \App\Models\RequestModel::STATUS_RESERVED,
                'DriverArrived',
                'AwaitingDestination',
                'Running',
            ])
            ->with(['user', 'startLocation', 'destLocation', 'carType'])
            ->orderByDesc('updated_at')
            ->limit(25)
            ->get();
    });

    return response()->json([
        'success' => true,
        'data' => $rows,
    ]);
}
