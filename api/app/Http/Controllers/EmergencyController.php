<?php

namespace App\Http\Controllers;

use App\Models\Driver;
use Illuminate\Http\Request;
use App\Services\AdminLimitedViewService;
use App\Services\SosLiveService;
use Illuminate\Support\Facades\Redis;

class EmergencyController extends Controller
{
    /** مفتاح Redis لتنبيه سائق. */
    public static function driverRedisKey(int $driverId): string
    {
        return (string) $driverId;
    }

    /** مفتاح Redis لتنبيه راكب. */
    public static function customerRedisKey(int $userId): string
    {
        return 'c:'.$userId;
    }

    /** POST — السائق أو الراكب يرسل إحداثيات SOS */
    public function send(Request $request)
    {
        $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $user = $request->user();
        if (! $user) {
            return response()->json([
                'state' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $lat = (float) $request->latitude;
        $lng = (float) $request->longitude;
        $name = trim(($user->firstName ?? '').' '.($user->lastName ?? ''));
        $base = [
            'userId' => (int) $user->id,
            'name' => $name !== '' ? $name : ('مستخدم #'.$user->id),
            'number' => $user->number,
            'latitude' => $lat,
            'longitude' => $lng,
            'at' => now()->toIso8601String(),
        ];

        if ($user->roll === 'Driver') {
            $driver = Driver::where('userId', $user->id)->first();
            if (! $driver) {
                return response()->json([
                    'state' => false,
                    'message' => 'لم يتم العثور على ملف السائق',
                ], 404);
            }
            $key = self::driverRedisKey((int) $driver->id);
            $payload = array_merge($base, [
                'role' => 'driver',
                'redisKey' => $key,
                'driverId' => (int) $driver->id,
            ]);
        } elseif ($user->roll === 'Customer') {
            $key = self::customerRedisKey((int) $user->id);
            $payload = array_merge($base, [
                'role' => 'customer',
                'redisKey' => $key,
                'customerId' => (int) $user->id,
            ]);
        } else {
            return response()->json([
                'state' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        Redis::hset('sos:active', $key, json_encode($payload, JSON_UNESCAPED_UNICODE));
        Redis::expire('sos:active', 86400);
        SosLiveService::resetTrail($key, $lat, $lng);

        return response()->json([
            'state' => true,
            'message' => 'تم إبلاغ الإدارة بحالة الطوارئ',
            'data' => ['redisKey' => $key, 'role' => $payload['role']],
        ]);
    }

    /** POST — تحديث موقع صاحب SOS النشط (كل بضع ثوانٍ من التطبيق) */
    public function liveUpdate(Request $request)
    {
        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $user = $request->user();
        if (! $user) {
            return response()->json(['state' => false, 'message' => 'غير مصرّح'], 403);
        }

        if ($user->roll === 'Driver') {
            $driverId = (int) Driver::where('userId', $user->id)->value('id');
            if ($driverId <= 0) {
                return response()->json(['state' => false, 'active' => false], 404);
            }
            $key = self::driverRedisKey($driverId);
        } elseif ($user->roll === 'Customer') {
            $key = self::customerRedisKey((int) $user->id);
        } else {
            return response()->json(['state' => false, 'message' => 'غير مصرّح'], 403);
        }

        $json = Redis::hget('sos:active', $key);
        $entry = is_string($json) ? json_decode($json, true) : null;
        if (! is_array($entry)) {
            return response()->json(['state' => true, 'active' => false]);
        }

        $lat = (float) $data['latitude'];
        $lng = (float) $data['longitude'];
        $now = time();
        $entry['live_latitude'] = $lat;
        $entry['live_longitude'] = $lng;
        $entry['live_at'] = $now;
        Redis::hset('sos:active', $key, json_encode($entry, JSON_UNESCAPED_UNICODE));
        SosLiveService::appendPoint($key, $lat, $lng, $now);

        return response()->json(['state' => true, 'active' => true]);
    }

    /** GET — للأدمن: متابعة مباشرة لتنبيه SOS واحد (آخر موقع + المسار) */
    public function live(Request $request, string $key)
    {
        $user = $request->user();
        if (! $user || ! $user->hasStaffPermission('requests.read')) {
            return response()->json(['success' => false, 'message' => 'غير مصرّح'], 403);
        }

        $key = rawurldecode($key);
        if (! preg_match('/^(\d+|c:\d+)$/', $key)) {
            return response()->json(['success' => false, 'message' => 'مفتاح تنبيه غير صالح'], 422);
        }

        $json = Redis::hget('sos:active', $key);
        $entry = is_string($json) ? json_decode($json, true) : null;
        if (! is_array($entry)) {
            return response()->json([
                'success' => true,
                'data' => ['active' => false, 'redisKey' => $key, 'server_time' => now()->toIso8601String()],
            ]);
        }

        $entry['redisKey'] = $entry['redisKey'] ?? $key;
        $entry['role'] = $entry['role'] ?? (str_starts_with($key, 'c:') ? 'customer' : 'driver');
        if (AdminLimitedViewService::filterSosItems($user, [$entry]) === []) {
            return response()->json(['success' => false, 'message' => 'غير مصرّح'], 403);
        }

        $pos = SosLiveService::latestPosition($entry, $key);
        SosLiveService::appendPoint($key, $pos['latitude'], $pos['longitude'], $pos['t'] ?: null);

        return response()->json([
            'success' => true,
            'data' => [
                'active' => true,
                'redisKey' => $key,
                'role' => $entry['role'],
                'name' => $entry['name'] ?? null,
                'number' => $entry['number'] ?? null,
                'driverId' => $entry['driverId'] ?? null,
                'customerId' => $entry['customerId'] ?? null,
                'sos_at' => $entry['at'] ?? null,
                'sos_latitude' => (float) ($entry['latitude'] ?? 0),
                'sos_longitude' => (float) ($entry['longitude'] ?? 0),
                'latitude' => $pos['latitude'],
                'longitude' => $pos['longitude'],
                'updated_at' => $pos['t'] > 0 ? date(DATE_ATOM, $pos['t']) : null,
                'age_seconds' => $pos['t'] > 0 ? max(0, time() - $pos['t']) : null,
                'source' => $pos['source'],
                'trail' => SosLiveService::trail($key),
                'server_time' => now()->toIso8601String(),
            ],
        ]);
    }

    /** GET — للأدمن: قائمة SOS النشطة */
    public function active(Request $request)
    {
        $user = $request->user();
        if (! $user || ! $user->hasStaffPermission('requests.read')) {
            return response()->json([
                'state' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $raw = Redis::hgetall('sos:active');
        $list = [];
        foreach ($raw as $field => $json) {
            $decoded = json_decode($json, true);
            if (! is_array($decoded)) {
                continue;
            }
            if (! isset($decoded['redisKey'])) {
                $decoded['redisKey'] = (string) $field;
            }
            if (! isset($decoded['role'])) {
                $decoded['role'] = str_starts_with((string) $field, 'c:')
                    ? 'customer'
                    : 'driver';
            }
            $list[] = $decoded;
        }

        $list = AdminLimitedViewService::filterSosItems($user, $list);

        return response()->json([
            'state' => true,
            'data' => array_values($list),
        ]);
    }

    /** DELETE — للأدمن: إزالة تنبيه SOS (سائق: رقم المعرف، راكب: c:{userId}) */
    public function clear(Request $request, string $key)
    {
        $user = $request->user();
        if (! $user || ! $user->hasStaffPermission('requests.write')) {
            return response()->json([
                'state' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $key = rawurldecode($key);
        if (! preg_match('/^(\d+|c:\d+)$/', $key)) {
            return response()->json([
                'state' => false,
                'message' => 'مفتاح تنبيه غير صالح',
            ], 422);
        }

        if (ctype_digit($key)) {
            $driverId = (int) $key;
            if ($deny = AdminLimitedViewService::assertDriverAccessible($user, $driverId)) {
                return response()->json([
                    'state' => false,
                    'message' => 'غير مصرّح',
                ], 403);
            }
        }

        Redis::hdel('sos:active', $key);
        Redis::del(SosLiveService::trailKey($key));

        return response()->json([
            'state' => true,
            'message' => 'تمت إزالة التنبيه',
        ]);
    }
}
