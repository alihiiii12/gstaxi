<?php

namespace App\Services;

use App\Models\Location;
use App\Models\RequestModel;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * عرض اسم نقطة انطلاق/وجهة للإدارة والتقارير (من DB أو وصف الطلب أو Nominatim).
 */
class LocationDisplayService
{
    public static function labelForLocation(
        ?Location $loc,
        ?string $fallbackDesc = null,
        bool $allowReverse = true,
    ): string {
        if ($loc) {
            foreach (['name', 'description'] as $field) {
                $v = trim((string) ($loc->{$field} ?? ''));
                if ($v !== '') {
                    return self::shorten($v);
                }
            }
        }

        $fb = trim((string) ($fallbackDesc ?? ''));
        if ($fb !== '') {
            return self::shorten($fb);
        }

        if ($allowReverse && $loc && $loc->latitude !== null && $loc->longitude !== null) {
            $rev = self::reverseGeocode((float) $loc->latitude, (float) $loc->longitude);
            if ($rev !== '') {
                return $rev;
            }
        }

        return '';
    }

    public static function labelForRequestPoint(
        RequestModel $req,
        bool $destination,
        bool $allowReverse = true,
    ): string {
        if (! $destination) {
            return self::labelForLocation($req->startLocation, $req->locationDesc, $allowReverse);
        }

        $fromDest = self::labelForLocation($req->destLocation, null, $allowReverse);
        if ($fromDest !== '') {
            return $fromDest;
        }

        $area = $req->serviceArea;
        if ($area) {
            $name = trim((string) ($area->name ?? ''));
            if ($name !== '') {
                return $name;
            }
        }

        return '';
    }

    public static function enrichRequestArray(
        array $data,
        RequestModel $req,
        bool $allowReverse = true,
    ): array {
        $pickup = self::labelForRequestPoint($req, false, $allowReverse);
        $dest = self::labelForRequestPoint($req, true, $allowReverse);

        $data['pickup_label'] = $pickup !== '' ? $pickup : null;
        $data['dest_label'] = $dest !== '' ? $dest : null;
        $data['pickupLabel'] = $data['pickup_label'];
        $data['destLabel'] = $data['dest_label'];

        return $data;
    }

    public static function reverseGeocode(float $lat, float $lng): string
    {
        if (! is_finite($lat) || ! is_finite($lng)) {
            return '';
        }

        $key = 'loc_rev_'.round($lat, 5).'_'.round($lng, 5);

        return Cache::remember($key, now()->addDays(30), function () use ($lat, $lng) {
            try {
                $res = Http::timeout(6)
                    ->withHeaders([
                        'User-Agent' => 'SyriaTaxi-API/1.0 (admin; contact: admin@syriataxi.local)',
                        'Accept-Language' => 'ar,en',
                    ])
                    ->get('https://nominatim.openstreetmap.org/reverse', [
                        'format' => 'json',
                        'lat' => $lat,
                        'lon' => $lng,
                        'zoom' => 16,
                    ]);

                if (! $res->successful()) {
                    return '';
                }

                $json = $res->json();
                $name = trim((string) ($json['display_name'] ?? ''));

                return $name !== '' ? self::shorten($name) : '';
            } catch (\Throwable $e) {
                Log::debug('LocationDisplayService reverse: '.$e->getMessage());

                return '';
            }
        });
    }

    private static function shorten(string $text, int $maxParts = 4): string
    {
        $parts = array_values(array_filter(
            array_map('trim', explode(',', $text)),
            fn ($p) => $p !== ''
        ));
        if (count($parts) <= $maxParts) {
            return implode(', ', $parts);
        }

        return implode(', ', array_slice($parts, 0, $maxParts));
    }
}
