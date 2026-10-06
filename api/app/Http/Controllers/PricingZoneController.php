<?php

namespace App\Http\Controllers;

use App\Models\AppSetting;
use App\Models\PricingZone;
use App\Models\PricingZoneRule;
use App\Services\PricingZoneService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PricingZoneController extends Controller
{
    private function guard(Request $request): ?\Illuminate\Http\JsonResponse
    {
        $u = $request->user();
        if (! $u || ! $u->hasStaffPermission('drivers.write')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return null;
    }

    /** للتطبيق: معامل المنطقة لنقطتي الانطلاق والوجهة. */
    public function quote(Request $request)
    {
        $v = $request->validate([
            'pickup_lat' => 'required|numeric|between:-90,90',
            'pickup_lng' => 'required|numeric|between:-180,180',
            'dest_lat' => 'required|numeric|between:-90,90',
            'dest_lng' => 'required|numeric|between:-180,180',
        ]);
        $q = PricingZoneService::quote(
            (float) $v['pickup_lat'],
            (float) $v['pickup_lng'],
            (float) $v['dest_lat'],
            (float) $v['dest_lng'],
        );

        return response()->json(['success' => true, 'data' => PricingZoneService::payload($q)]);
    }

    /** للتطبيق: حدود المناطق + جدول المعاملات (لعدّاد الرحلة والعداد الحر). */
    public function appMap()
    {
        return response()->json(['success' => true, 'data' => PricingZoneService::mapPayload()]);
    }

    public function index(Request $request)
    {
        if ($r = $this->guard($request)) {
            return $r;
        }

        return response()->json(['success' => true, 'data' => $this->snapshot()]);
    }

    public function store(Request $request)
    {
        if ($r = $this->guard($request)) {
            return $r;
        }
        $v = $this->validateZone($request);
        $zone = DB::transaction(function () use ($v) {
            $zone = PricingZone::create($v);
            $out = PricingZoneService::OUTSIDE_ID;
            // نقاط المنطقة الجديدة كانت «خارج المناطق» — ترث معاملاته فلا تتغير الأسعار حتى تعدّلها.
            $outsideRules = PricingZoneRule::query()
                ->where('from_zone_id', $out)
                ->orWhere('to_zone_id', $out)
                ->get()
                ->mapWithKeys(fn ($r) => [$r->from_zone_id.':'.$r->to_zone_id => (float) $r->multiplier])
                ->all();
            $ids = array_merge([$out], PricingZone::query()->pluck('id')->map(fn ($id) => (int) $id)->all());
            foreach ($ids as $other) {
                $src = $other === (int) $zone->id ? $out : $other;
                foreach ([[$zone->id, $other, $out, $src], [$other, $zone->id, $src, $out]] as [$from, $to, $sf, $st]) {
                    PricingZoneRule::firstOrCreate(
                        ['from_zone_id' => $from, 'to_zone_id' => $to],
                        ['multiplier' => $outsideRules[$sf.':'.$st] ?? 1],
                    );
                }
            }

            return $zone;
        });
        PricingZoneService::clearCache();

        return response()->json(['success' => true, 'message' => 'أُضيفت المنطقة', 'data' => $this->snapshot()], 201);
    }

    public function update(Request $request, int $id)
    {
        if ($r = $this->guard($request)) {
            return $r;
        }
        $zone = PricingZone::find($id);
        if (! $zone) {
            return response()->json(['success' => false, 'message' => 'المنطقة غير موجودة'], 404);
        }
        $zone->fill($this->validateZone($request, true))->save();
        PricingZoneService::clearCache();

        return response()->json(['success' => true, 'message' => 'حُفظت المنطقة', 'data' => $this->snapshot()]);
    }

    public function destroy(Request $request, int $id)
    {
        if ($r = $this->guard($request)) {
            return $r;
        }
        $zone = PricingZone::find($id);
        if (! $zone) {
            return response()->json(['success' => false, 'message' => 'المنطقة غير موجودة'], 404);
        }
        DB::transaction(function () use ($zone) {
            PricingZoneRule::query()
                ->where('from_zone_id', $zone->id)
                ->orWhere('to_zone_id', $zone->id)
                ->delete();
            $zone->delete();
        });
        PricingZoneService::clearCache();

        return response()->json(['success' => true, 'message' => 'حُذفت المنطقة', 'data' => $this->snapshot()]);
    }

    public function updateRules(Request $request)
    {
        if ($r = $this->guard($request)) {
            return $r;
        }
        $v = $request->validate([
            'rules' => 'required|array|min:1',
            'rules.*.from_zone_id' => 'required|integer|min:0',
            'rules.*.to_zone_id' => 'required|integer|min:0',
            'rules.*.multiplier' => 'required|numeric|min:0.1|max:20',
        ]);
        $valid = array_merge([PricingZoneService::OUTSIDE_ID], PricingZone::query()->pluck('id')->all());
        DB::transaction(function () use ($v, $valid) {
            foreach ($v['rules'] as $rule) {
                $from = (int) $rule['from_zone_id'];
                $to = (int) $rule['to_zone_id'];
                if (! in_array($from, $valid, true) || ! in_array($to, $valid, true)) {
                    continue;
                }
                PricingZoneRule::updateOrCreate(
                    ['from_zone_id' => $from, 'to_zone_id' => $to],
                    ['multiplier' => round((float) $rule['multiplier'], 3)],
                );
            }
        });
        PricingZoneService::clearCache();

        return response()->json(['success' => true, 'message' => 'حُفظت المعاملات', 'data' => $this->snapshot()]);
    }

    public function updateOutside(Request $request)
    {
        if ($r = $this->guard($request)) {
            return $r;
        }
        $v = $request->validate(['name' => 'required|string|max:80']);
        AppSetting::setValue(PricingZoneService::OUTSIDE_NAME_SETTING, trim($v['name']));
        PricingZoneService::clearCache();

        return response()->json(['success' => true, 'message' => 'حُفظ الاسم', 'data' => $this->snapshot()]);
    }

    private function validateZone(Request $request, bool $partial = false): array
    {
        $req = $partial ? 'sometimes' : 'required';
        $v = $request->validate([
            'name' => $req.'|string|max:80',
            'polygon' => $req.'|array|min:3|max:2000',
            'polygon.*' => 'array|size:2',
            'polygon.*.0' => 'numeric|between:-90,90',
            'polygon.*.1' => 'numeric|between:-180,180',
            'color' => 'sometimes|nullable|string|max:16',
            'is_active' => 'sometimes|boolean',
            'sort_order' => 'sometimes|integer',
        ]);
        if (isset($v['polygon'])) {
            $v['polygon'] = array_map(
                static fn ($p) => [round((float) $p[0], 6), round((float) $p[1], 6)],
                $v['polygon'],
            );
        }
        if (array_key_exists('color', $v) && ! $v['color']) {
            unset($v['color']);
        }

        return $v;
    }

    private function snapshot(): array
    {
        $zones = PricingZone::query()->orderBy('sort_order')->orderBy('id')->get()->map(fn ($z) => [
            'id' => $z->id,
            'name' => $z->name,
            'polygon' => $z->polygon,
            'color' => $z->color,
            'is_active' => $z->is_active,
            'sort_order' => $z->sort_order,
        ])->values();
        $rules = PricingZoneRule::query()->get(['from_zone_id', 'to_zone_id', 'multiplier'])->map(fn ($r) => [
            'from_zone_id' => $r->from_zone_id,
            'to_zone_id' => $r->to_zone_id,
            'multiplier' => (float) $r->multiplier,
        ])->values();

        return [
            'zones' => $zones,
            'rules' => $rules,
            'outside' => ['id' => PricingZoneService::OUTSIDE_ID, 'name' => PricingZoneService::outsideName()],
        ];
    }
}
