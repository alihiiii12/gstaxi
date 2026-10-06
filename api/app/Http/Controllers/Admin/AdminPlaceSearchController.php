<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;

/**
 * بحث أماكن للوحة الإدارة (Proxy) — Photon ثم Nominatim.
 * المتصفح لا يستدعي Photon مباشرة بسبب CORS.
 */
class AdminPlaceSearchController extends Controller
{
    private const SYRIA_BBOX = '35.6,32.3,42.4,37.4';

    public function search(Request $request): JsonResponse
    {
        $u = $request->user();
        if (! $u || (
            ! $u->hasStaffPermission('requests.write')
            && ! $u->hasStaffPermission('requests.read')
        )) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $q = trim((string) $request->query('q', ''));
        if (mb_strlen($q) < 2) {
            return response()->json(['success' => true, 'data' => []]);
        }

        $lat = $request->query('lat');
        $lng = $request->query('lng');
        $limit = min(12, max(1, (int) $request->query('limit', 8)));

        $hits = $this->photonSearch($q, $lat, $lng, $limit);
        if ($hits === []) {
            $hits = $this->nominatimSearch($q, $lat, $lng, $limit);
        }

        return response()->json(['success' => true, 'data' => $hits]);
    }

    public function reverse(Request $request): JsonResponse
    {
        $u = $request->user();
        if (! $u || (
            ! $u->hasStaffPermission('requests.write')
            && ! $u->hasStaffPermission('requests.read')
        )) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $lat = (float) $request->query('lat', 0);
        $lng = (float) $request->query('lng', 0);
        if ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) {
            return response()->json(['success' => false, 'message' => 'إحداثيات غير صالحة'], 422);
        }

        $name = $this->nominatimReverse($lat, $lng);

        return response()->json([
            'success' => true,
            'data' => [
                'name' => $name,
                'position' => [$lat, $lng],
            ],
        ]);
    }

    /** @return list<array{name:string,subtitle:string,position:array{0:float,1:float}}> */
    private function photonSearch(string $q, $lat, $lng, int $limit): array
    {
        try {
            $params = [
                'q' => $q,
                'lang' => 'ar',
                'limit' => $limit,
                'bbox' => self::SYRIA_BBOX,
            ];
            if (is_numeric($lat) && is_numeric($lng)) {
                $params['lat'] = (string) $lat;
                $params['lon'] = (string) $lng;
            }
            $res = Http::timeout(4)
                ->withHeaders(['Accept' => 'application/json', 'User-Agent' => 'GSTaxiAdmin/1.0'])
                ->get('https://photon.komoot.io/api/', $params);
            if (! $res->ok()) {
                return [];
            }
            $features = $res->json('features') ?? [];
            $out = [];
            foreach ($features as $f) {
                if (! is_array($f)) {
                    continue;
                }
                $coords = $f['geometry']['coordinates'] ?? null;
                if (! is_array($coords) || count($coords) < 2) {
                    continue;
                }
                $lon = (float) $coords[0];
                $la = (float) $coords[1];
                $props = is_array($f['properties'] ?? null) ? $f['properties'] : [];
                $name = trim((string) ($props['name'] ?? $props['street'] ?? $props['city'] ?? 'موقع'));
                $city = trim((string) ($props['city'] ?? $props['locality'] ?? ''));
                $state = trim((string) ($props['state'] ?? $props['county'] ?? ''));
                $subtitle = implode('، ', array_filter([$city, $state]));
                $out[] = [
                    'name' => $name !== '' ? $name : 'موقع',
                    'subtitle' => $subtitle,
                    'position' => [$la, $lon],
                ];
            }

            return $out;
        } catch (\Throwable $e) {
            return [];
        }
    }

    /** @return list<array{name:string,subtitle:string,position:array{0:float,1:float}}> */
    private function nominatimSearch(string $q, $lat, $lng, int $limit): array
    {
        try {
            $params = [
                'q' => $q,
                'format' => 'jsonv2',
                'limit' => $limit,
                'accept-language' => 'ar',
                'countrycodes' => 'sy',
            ];
            if (is_numeric($lat) && is_numeric($lng)) {
                $params['viewbox'] = sprintf(
                    '%F,%F,%F,%F',
                    (float) $lng - 0.35,
                    (float) $lat + 0.35,
                    (float) $lng + 0.35,
                    (float) $lat - 0.35,
                );
                $params['bounded'] = 1;
            }
            $res = Http::timeout(5)
                ->withHeaders([
                    'Accept' => 'application/json',
                    'User-Agent' => 'GSTaxiAdmin/1.0 (gstaxi.online)',
                ])
                ->get('https://nominatim.openstreetmap.org/search', $params);
            if (! $res->ok()) {
                return [];
            }
            $rows = $res->json();
            if (! is_array($rows)) {
                return [];
            }
            $out = [];
            foreach ($rows as $row) {
                if (! is_array($row)) {
                    continue;
                }
                $la = (float) ($row['lat'] ?? 0);
                $lon = (float) ($row['lon'] ?? 0);
                if ($la == 0.0 && $lon == 0.0) {
                    continue;
                }
                $dn = trim((string) ($row['display_name'] ?? $row['name'] ?? 'موقع'));
                $parts = array_values(array_filter(array_map('trim', explode(',', $dn))));
                $name = $parts[0] ?? 'موقع';
                $subtitle = implode('، ', array_slice($parts, 1, 3));
                $out[] = [
                    'name' => $name,
                    'subtitle' => $subtitle,
                    'position' => [$la, $lon],
                ];
            }

            return $out;
        } catch (\Throwable $e) {
            return [];
        }
    }

    private function nominatimReverse(float $lat, float $lng): string
    {
        $fallback = number_format($lat, 5, '.', '').', '.number_format($lng, 5, '.', '');
        try {
            $res = Http::timeout(5)
                ->withHeaders([
                    'Accept' => 'application/json',
                    'User-Agent' => 'GSTaxiAdmin/1.0 (gstaxi.online)',
                ])
                ->get('https://nominatim.openstreetmap.org/reverse', [
                    'format' => 'jsonv2',
                    'lat' => $lat,
                    'lon' => $lng,
                    'accept-language' => 'ar',
                ]);
            if (! $res->ok()) {
                return $fallback;
            }
            $dn = trim((string) ($res->json('display_name') ?? $res->json('name') ?? ''));
            if ($dn === '') {
                return $fallback;
            }
            $parts = array_values(array_filter(array_map('trim', explode(',', $dn))));

            return implode('، ', array_slice($parts, 0, 4));
        } catch (\Throwable $e) {
            return $fallback;
        }
    }
}
