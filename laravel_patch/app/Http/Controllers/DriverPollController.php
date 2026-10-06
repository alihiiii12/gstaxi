<?php



namespace App\Http\Controllers;



use App\Models\Driver;

use App\Models\RequestModel;

use App\Services\DriverPollCacheService;

use App\Services\ImmediatePendingForDriver;

use Illuminate\Http\Request;

use Illuminate\Support\Facades\Cache;



/**

 * استطلاع موحّد للسائق — يستبدل ضرب endpointين كل ثانيتين.

 */

class DriverPollController extends Controller

{

    /** ثوانٍ — cache قصير يمنع تكرار نفس الاستعلام من نفس السائق. */

    private const CACHE_SECONDS = 4;



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

        $cacheKey = 'driver_poll:'.$driverId;



        $payload = Cache::remember($cacheKey, self::CACHE_SECONDS, function () use ($driver, $driverId) {

            $pendingModels = ImmediatePendingForDriver::queryForDriver($driver);

            $pending = $pendingModels

                ->map(fn ($m) => ImmediatePendingForDriver::toDriverPayload($driver, $m))

                ->values()

                ->all();



            return [

                'immediate_pending' => $pending,

                'driver_requests' => $this->buildDriverRequests($driverId),

                'cached_at' => now()->toIso8601String(),

            ];

        });



        return response()->json([

            'success' => true,

            'data' => $payload,

        ]);

    }



    /**

     * @return array<int, array<string, mixed>>

     */

    private function buildDriverRequests(int $driverId): array

    {

        $rows = RequestModel::query()

            ->where(function ($q) use ($driverId) {

                $q->where('driverId', $driverId)

                    ->orWhere('targetDriverId', $driverId);

            })

            ->whereIn('status', [

                RequestModel::STATUS_PENDING,

                RequestModel::STATUS_RESERVED,

                'DriverArrived',

                'AwaitingDestination',

                'Running',

            ])

            ->with(['user', 'startLocation', 'destLocation', 'carType'])

            ->orderByDesc('updated_at')

            ->limit(25)

            ->get();



        return $rows->map(fn ($m) => $m->toArray())->all();

    }

}


