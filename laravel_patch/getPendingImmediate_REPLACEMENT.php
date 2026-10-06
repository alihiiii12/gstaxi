<?php



/*

 * استبدل getPendingImmediate في RequestController — مع cache قصير لكل سائق.

 */

public function getPendingImmediate(\Illuminate\Http\Request $request)

{

    $user = $request->user();

    if (! $user || $user->roll !== 'Driver') {

        return response()->json(['success' => false, 'message' => 'Forbidden'], 403);

    }



    $driver = \App\Models\Driver::where('userId', $user->id)->first();

    if (! $driver) {

        return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);

    }



    $driverId = (int) $driver->id;

    $cacheKey = 'immediate_pending:'.$driverId;



    $filtered = \Illuminate\Support\Facades\Cache::remember($cacheKey, 4, function () use ($driver) {

        return \App\Services\ImmediatePendingForDriver::queryForDriver($driver)

            ->map(fn ($m) => \App\Services\ImmediatePendingForDriver::toDriverPayload($driver, $m))

            ->values()

            ->all();

    });



    return response()->json([

        'success' => true,

        'data' => $filtered,

    ]);

}


