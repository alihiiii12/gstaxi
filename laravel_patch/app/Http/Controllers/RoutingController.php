<?php



namespace App\Http\Controllers;



use Illuminate\Http\Request;

use Illuminate\Support\Facades\Cache;

use Illuminate\Support\Facades\Http;



class RoutingController extends Controller

{

    public function drivingSummary(Request $request)

    {

        $v = $request->validate([

            'from_lat' => 'required|numeric|between:-90,90',

            'from_lng' => 'required|numeric|between:-180,180',

            'to_lat' => 'required|numeric|between:-90,90',

            'to_lng' => 'required|numeric|between:-180,180',

        ]);



        $lng1 = (float) $v['from_lng'];

        $lat1 = (float) $v['from_lat'];

        $lng2 = (float) $v['to_lng'];

        $lat2 = (float) $v['to_lat'];



        $cacheKey = sprintf(

            'route_summary_v2:%.3f,%.3f:%.3f,%.3f',

            $lat1,

            $lng1,

            $lat2,

            $lng2

        );



        $cached = Cache::get($cacheKey);

        if (is_array($cached)) {

            return response()->json([

                'success' => true,

                'data' => $cached + ['source' => ($cached['source'] ?? 'cache')],

            ]);

        }



        $url = sprintf(

            'https://router.project-osrm.org/route/v1/driving/%F,%F;%F,%F',

            $lng1,

            $lat1,

            $lng2,

            $lat2

        );



        try {

            $res = Http::timeout(8)

                ->withHeaders([

                    'User-Agent' => 'SyriaTaxiBackend/1.0 (+laravel)',

                    'Accept' => 'application/json',

                ])

                ->get($url, [

                    'overview' => 'full',

                    'geometries' => 'geojson',

                ]);



            if ($res->successful()) {

                $route = $res->json('routes.0');

                if (is_array($route) && isset($route['distance'])) {

                    $km = round(((float) $route['distance']) / 1000, 2);

                    $min = isset($route['duration']) ? round(((float) $route['duration']) / 60, 1) : null;

                    $coords = $route['geometry']['coordinates'] ?? null;

                    $payload = [

                        'distance_km' => $km,

                        'duration_minutes' => $min,

                        'source' => 'osrm',

                    ];

                    if (is_array($coords) && count($coords) >= 2) {

                        $payload['route_points'] = $coords;

                    }

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



        $km = round($this->haversineKm($lat1, $lng1, $lat2, $lng2), 2);

        $payload = [

            'distance_km' => $km,

            'duration_minutes' => null,

            'source' => 'straight_line_fallback',

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


