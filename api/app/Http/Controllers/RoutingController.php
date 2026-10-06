<?php



namespace App\Http\Controllers;



use Illuminate\Http\Request;

use Illuminate\Support\Facades\Cache;

use Illuminate\Support\Facades\Http;



class RoutingController extends Controller

{

    /**

     * ملخص مسار القيادة بين نقطتين باستخدام OSRM العام (مسافة طرق تقريبية).

     */

    public function drivingSummary(Request $request)

    {

        $v = $request->validate([

            'from_lat' => 'required|numeric|between:-90,90',

            'from_lng' => 'required|numeric|between:-180,180',

            'to_lat' => 'required|numeric|between:-90,90',

            'to_lng' => 'required|numeric|between:-180,180',

            // محطات وسيطة بالترتيب (بين الانطلاق والوجهة الأخيرة).
            'waypoints' => 'sometimes|array|max:10',

            'waypoints.*.lat' => 'required_with:waypoints|numeric|between:-90,90',

            'waypoints.*.lng' => 'required_with:waypoints|numeric|between:-180,180',

        ]);



        $lng1 = (float) $v['from_lng'];

        $lat1 = (float) $v['from_lat'];

        $lng2 = (float) $v['to_lng'];

        $lat2 = (float) $v['to_lat'];

        $points = [[$lat1, $lng1]];
        foreach ($v['waypoints'] ?? [] as $wp) {
            $points[] = [(float) $wp['lat'], (float) $wp['lng']];
        }
        $points[] = [$lat2, $lng2];

        $cacheKey = 'route_summary:'.implode(':', array_map(
            fn ($p) => sprintf('%.4f,%.4f', $p[0], $p[1]),
            $points
        ));



        $cached = Cache::get($cacheKey);

        if (is_array($cached)) {

            return response()->json([

                'success' => true,

                'data' => $cached,

            ]);

        }



        $url = 'https://router.project-osrm.org/route/v1/driving/'.implode(';', array_map(
            fn ($p) => sprintf('%F,%F', $p[1], $p[0]),
            $points
        ));



        try {

            $res = Http::timeout(8)

                ->withHeaders([

                    'User-Agent' => 'SyriaTaxiBackend/1.0 (+laravel)',

                    'Accept' => 'application/json',

                ])

                ->get($url, [

                    'overview' => 'simplified',

                    'geometries' => 'geojson',

                ]);



            if ($res->successful()) {

                $route = $res->json('routes.0');

                if (is_array($route) && isset($route['distance'])) {

                    $km = round(((float) $route['distance']) / 1000, 2);

                    $min = isset($route['duration']) ? round(((float) $route['duration']) / 60, 1) : null;



                    $routePoints = [];

                    $geom = $route['geometry'] ?? null;

                    if (is_array($geom)

                        && ($geom['type'] ?? '') === 'LineString'

                        && isset($geom['coordinates'])

                        && is_array($geom['coordinates'])) {

                        $routePoints = $geom['coordinates'];

                    }



                    $payload = [

                        'distance_km' => $km,

                        'duration_minutes' => $min,

                        'source' => 'osrm',

                        'route_points' => $routePoints,

                    ];

                    Cache::put($cacheKey, $payload, now()->addMinutes(15));



                    return response()->json([

                        'success' => true,

                        'data' => $payload,

                    ]);

                }

            }

        } catch (\Throwable $e) {

            \Illuminate\Support\Facades\Log::warning('routing osrm: '.$e->getMessage());

        }



        $kmSum = 0.0;
        for ($i = 1; $i < count($points); $i++) {
            $kmSum += $this->haversineKm($points[$i - 1][0], $points[$i - 1][1], $points[$i][0], $points[$i][1]);
        }
        $km = round($kmSum, 2);

        $payload = [

            'distance_km' => $km,

            'duration_minutes' => null,

            'source' => 'straight_line_fallback',

            'route_points' => array_map(fn ($p) => [$p[1], $p[0]], $points),

        ];

        Cache::put($cacheKey, $payload, now()->addMinutes(5));



        return response()->json([

            'success' => true,

            'data' => $payload,

        ]);

    }



    private function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float

    {

        $earth = 6371.0;

        $dLat = deg2rad($lat2 - $lat1);

        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;



        return $earth * (2 * atan2(sqrt($a), sqrt(1 - $a)));

    }

}


