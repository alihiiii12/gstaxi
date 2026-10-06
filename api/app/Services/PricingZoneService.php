<?php

namespace App\Services;

use App\Models\AppSetting;
use App\Models\PricingZone;
use App\Models\PricingZoneRule;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * معامل التسعير حسب منطقة الانطلاق ومنطقة الوجهة.
 * أي نقطة خارج كل المناطق المرسومة تُعتبر منطقة «الخارج» (id = 0، اسمها من الإعدادات).
 * عند تداخل المناطق تفوز الأصغر مساحةً (مثلاً المدينة داخل حدود الريف).
 */
class PricingZoneService
{
    public const OUTSIDE_ID = 0;

    public const OUTSIDE_NAME = 'الريف';

    public const OUTSIDE_NAME_SETTING = 'pricing_zone_outside_name';

    private const CACHE_KEY = 'pricing_zones_v2';

    public static function clearCache(): void
    {
        Cache::forget(self::CACHE_KEY);
    }

    public static function outsideName(): string
    {
        return self::data()['outside_name'];
    }

    /** مساحة نسبية (درجات²) — للترتيب فقط. */
    public static function polygonArea(array $poly): float
    {
        $sum = 0.0;
        $n = count($poly);
        for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
            $sum += ($poly[$j][1] * $poly[$i][0]) - ($poly[$i][1] * $poly[$j][0]);
        }

        return abs($sum) / 2;
    }

    /** @return array{zones: array<int, array{id:int,name:string,polygon:array,bbox:array}>, rules: array<string,float>, outside_name: string} */
    private static function data(): array
    {
        return Cache::remember(self::CACHE_KEY, 300, static function () {
            $outsideName = self::OUTSIDE_NAME;
            try {
                $outsideName = trim(AppSetting::getString(self::OUTSIDE_NAME_SETTING, self::OUTSIDE_NAME)) ?: self::OUTSIDE_NAME;
            } catch (\Throwable $e) {
            }
            if (! Schema::hasTable('pricing_zones') || ! Schema::hasTable('pricing_zone_rules')) {
                return ['zones' => [], 'rules' => [], 'outside_name' => $outsideName];
            }
            $zones = [];
            foreach (PricingZone::query()->where('is_active', true)->orderBy('sort_order')->orderBy('id')->get() as $z) {
                $poly = self::normalizePolygon($z->polygon);
                if (count($poly) < 3) {
                    continue;
                }
                $lats = array_column($poly, 0);
                $lngs = array_column($poly, 1);
                $zones[] = [
                    'id' => (int) $z->id,
                    'name' => (string) $z->name,
                    'polygon' => $poly,
                    'bbox' => [min($lats), max($lats), min($lngs), max($lngs)],
                    'area' => self::polygonArea($poly),
                ];
            }
            // الأصغر أولاً: أول منطقة تحتوي النقطة هي الأدق (التطبيقات تعتمد هذا الترتيب أيضاً).
            usort($zones, static fn (array $a, array $b) => $a['area'] <=> $b['area']);
            $rules = [];
            foreach (PricingZoneRule::query()->get() as $r) {
                $rules[$r->from_zone_id.':'.$r->to_zone_id] = (float) $r->multiplier;
            }

            return ['zones' => $zones, 'rules' => $rules, 'outside_name' => $outsideName];
        });
    }

    /** @return array<int, array{0: float, 1: float}> */
    public static function normalizePolygon($raw): array
    {
        if (! is_array($raw)) {
            return [];
        }
        $out = [];
        foreach ($raw as $p) {
            if (is_array($p) && isset($p[0], $p[1]) && is_numeric($p[0]) && is_numeric($p[1])) {
                $out[] = [(float) $p[0], (float) $p[1]];
            } elseif (is_array($p) && isset($p['lat'], $p['lng'])) {
                $out[] = [(float) $p['lat'], (float) $p['lng']];
            }
        }

        return $out;
    }

    public static function pointInPolygon(float $lat, float $lng, array $poly): bool
    {
        $inside = false;
        $n = count($poly);
        for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
            [$yi, $xi] = $poly[$i];
            [$yj, $xj] = $poly[$j];
            if ((($yi > $lat) !== ($yj > $lat))
                && ($lng < ($xj - $xi) * ($lat - $yi) / (($yj - $yi) ?: 1e-12) + $xi)) {
                $inside = ! $inside;
            }
        }

        return $inside;
    }

    /** @return array{id:int, name:string} */
    public static function zoneAt(float $lat, float $lng): array
    {
        foreach (self::data()['zones'] as $z) {
            [$minLat, $maxLat, $minLng, $maxLng] = $z['bbox'];
            if ($lat < $minLat || $lat > $maxLat || $lng < $minLng || $lng > $maxLng) {
                continue;
            }
            if (self::pointInPolygon($lat, $lng, $z['polygon'])) {
                return ['id' => $z['id'], 'name' => $z['name']];
            }
        }

        return ['id' => self::OUTSIDE_ID, 'name' => self::outsideName()];
    }

    /**
     * @return array{multiplier: float, from: array{id:int,name:string}, to: array{id:int,name:string}, label: string}
     */
    public static function quote(?float $pickLat, ?float $pickLng, ?float $destLat, ?float $destLng): array
    {
        $outside = ['id' => self::OUTSIDE_ID, 'name' => self::OUTSIDE_NAME];
        try {
            $outside['name'] = self::outsideName();
        } catch (\Throwable $e) {
        }
        $neutral = [
            'multiplier' => 1.0,
            'from' => $outside,
            'to' => $outside,
            'label' => '',
        ];
        if ($pickLat === null || $pickLng === null || $destLat === null || $destLng === null) {
            return $neutral;
        }
        try {
            $from = self::zoneAt($pickLat, $pickLng);
            $to = self::zoneAt($destLat, $destLng);
            $m = self::data()['rules'][$from['id'].':'.$to['id']] ?? 1.0;
            if (! is_finite($m) || $m <= 0) {
                $m = 1.0;
            }
            $m = round($m, 3);

            return [
                'multiplier' => $m,
                'from' => $from,
                'to' => $to,
                'label' => $m != 1.0 ? self::label($from['name'], $to['name'], $m) : '',
            ];
        } catch (\Throwable $e) {
            Log::warning('[pricing_zone] '.$e->getMessage());

            return $neutral;
        }
    }

    /** المناطق والقواعد للتطبيق (يحسب العداد المنطقة محلياً أثناء الحركة). */
    public static function mapPayload(): array
    {
        $d = self::data();
        $rules = [];
        foreach ($d['rules'] as $k => $m) {
            $rules[(string) $k] = round((float) $m, 3);
        }

        return [
            'zones' => array_map(
                static fn (array $z) => ['id' => $z['id'], 'name' => $z['name'], 'polygon' => $z['polygon']],
                $d['zones']
            ),
            'rules' => (object) $rules,
            'outside' => ['id' => self::OUTSIDE_ID, 'name' => $d['outside_name']],
            'version' => md5(json_encode($d)),
        ];
    }

    public static function label(string $from, string $to, float $m): string
    {
        $mul = rtrim(rtrim(number_format($m, 3, '.', ''), '0'), '.');

        return 'تسعيرة '.$from.' ← '.$to.' ×'.$mul;
    }

    public static function apply(float $fare, float $multiplier): float
    {
        if ($fare <= 0 || $multiplier == 1.0) {
            return round($fare, 2);
        }

        return round($fare * $multiplier, 2);
    }

    /** قيم تُحفظ مع الطلب. */
    public static function requestAttributes(array $quote): array
    {
        if (! Schema::hasColumn('requests', 'zone_multiplier')) {
            return [];
        }

        return [
            'zone_multiplier' => $quote['multiplier'],
            'pickup_zone_name' => $quote['from']['name'],
            'dest_zone_name' => $quote['to']['name'],
        ];
    }

    public static function payload(array $quote): array
    {
        return [
            'multiplier' => $quote['multiplier'],
            'from_zone' => $quote['from'],
            'to_zone' => $quote['to'],
            'label' => $quote['label'],
        ];
    }
}
