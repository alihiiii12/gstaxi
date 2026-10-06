<?php

/**
 * استبدل دالة acceptBooking في RequestController بهذه النسخة كاملةً.
 */

/*
public function acceptBooking(\Illuminate\Http\Request $request, $requestId)
{
    $driver = \App\Models\Driver::where('userId', $request->user()->id)->first();

    if (! $driver) {
        return response()->json([
            'success' => false,
            'message' => 'Driver profile not found',
        ], 404);
    }

    $driverId = $driver->id;

    $requestData = \App\Models\RequestModel::find($requestId);

    if (! $requestData) {
        return response()->json([
            'success' => false,
            'message' => 'Request not found',
        ], 404);
    }

    if ($requestData->status !== \App\Models\RequestModel::STATUS_PENDING) {
        return response()->json([
            'success' => false,
            'message' => 'Cannot accept this request at this time',
        ], 400);
    }

    if ($requestData->type === \App\Models\RequestModel::TYPE_IMMEDIATE) {
        $eligibleKey = 'request:'.$requestData->id.':eligible';
        if (\Illuminate\Support\Facades\Redis::exists($eligibleKey)
            && ! \Illuminate\Support\Facades\Redis::sismember($eligibleKey, (string) $driverId)) {
            return response()->json([
                'success' => false,
                'message' => 'غير مدرج ضمن نطاق هذا الطلب',
            ], 403);
        }

        \App\Models\RequestDriverOffer::firstOrCreate([
            'request_id' => $requestData->id,
            'driver_id' => $driverId,
        ]);

        return response()->json([
            'success' => true,
            'data' => ['awaiting_passenger_choice' => true],
            'message' => 'تم تسجيل اهتمامك؛ بانتظار اختيار الزبون',
        ]);
    }

    \Illuminate\Support\Facades\DB::beginTransaction();

    try {
        $requestData->status = \App\Models\RequestModel::STATUS_RESERVED;
        $requestData->driverId = $driverId;
        $requestData->save();

        $history = \App\Models\RequestHistory::create([
            'requestId' => $requestData->id,
            'driverId' => $driverId,
            'finalCost' => $requestData->predectedCost ?? 0,
            'descountId' => $request->discountId ?? null,
        ]);

        \Illuminate\Support\Facades\DB::commit();

        $this->sendConfirmationToPassenger($requestData, $driver);

        return response()->json([
            'success' => true,
            'data' => [
                'request' => $requestData,
                'history' => $history,
                'driver' => $driver,
            ],
            'message' => 'Booking accepted successfully',
        ]);
    } catch (\Exception $e) {
        \Illuminate\Support\Facades\DB::rollBack();

        return response()->json([
            'success' => false,
            'message' => 'An error occurred: '.$e->getMessage(),
        ], 500);
    }
}
*/
