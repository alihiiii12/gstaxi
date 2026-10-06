<?php

namespace App\Services;

use App\Models\RequestModel;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Schema;

/**
 * مواقع الزبائن المتصلين بالتطبيق لخريطة الإدارة.
 *
 * مصادر الظهور (بالأولوية):
 * 1) heartbeat حي (Redis GEO + مفتاح online)
 * 2) جلسة Sanctum حديثة + آخر موقع معروف
 * 3) طلب نشط حُدّث مؤخراً (نقطة الانطلاق)
 */
class CustomerPresenceService
{
    public const GEO_KEY = 'customers';

    public const ONLINE_SET = 'customers:online_set';

    /** مدة اعتبار الزبون «متصلاً» بعد آخر heartbeat / markOnline */
    public const ONLINE_TTL = 300;

    /** مدة اعتبار الجلسة نشطة من last_used_at للتوكن */
    public const SESSION_MINUTES = 360;

    /** طلبات نشطة أحدث من هذا تُعدّ مؤشراً على اتصال */
    public const ACTIVE_TRIP_MINUTES = 60;

    public static function onlineKey(int $userId): string
    {
        return 'customer:'.$userId.':online';
    }

    public static function lastPosKey(int $userId): string
    {
        return 'customer:'.$userId.':lastpos';
    }

    public static function touch(int $userId, float $lat, float $lng): void
    {
        if ($userId < 1) {
            return;
        }
        if (! is_finite($lat) || ! is_finite($lng)) {
            return;
        }
        if ($lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) {
            return;
        }
        if ($lat == 0.0 && $lng == 0.0) {
            return;
        }

        try {
            Redis::geoadd(self::GEO_KEY, $lng, $lat, (string) $userId);
            Redis::setex(self::onlineKey($userId), self::ONLINE_TTL, '1');
            Redis::sadd(self::ONLINE_SET, (string) $userId);
            Redis::setex(
                self::lastPosKey($userId),
                60 * 60 * 24 * 14,
                json_encode(['lat' => $lat, 'lng' => $lng, 't' => time()], JSON_UNESCAPED_UNICODE)
            );
        } catch (\Throwable $e) {
            Log::debug('CustomerPresenceService::touch '.$e->getMessage());
        }
    }

    /** يمدّد حالة الاتصال بدون موقع (عند استطلاع التطبيق). */
    public static function markOnline(int $userId): void
    {
        if ($userId < 1) {
            return;
        }
        try {
            Redis::setex(self::onlineKey($userId), self::ONLINE_TTL, '1');
            Redis::sadd(self::ONLINE_SET, (string) $userId);
        } catch (\Throwable $e) {
        }
    }

    public static function clear(int $userId): void
    {
        try {
            Redis::zrem(self::GEO_KEY, (string) $userId);
            Redis::srem(self::ONLINE_SET, (string) $userId);
            Redis::del(self::onlineKey($userId));
            Redis::del(self::lastPosKey($userId));
        } catch (\Throwable $e) {
        }
    }

    /**
     * @return list<array<string, mixed>>
     */
    public static function onlineMarkers(): array
    {
        $byId = [];

        foreach (self::liveRedisMarkers() as $row) {
            $id = (int) ($row['user_id'] ?? 0);
            if ($id > 0) {
                $byId[$id] = $row;
            }
        }

        foreach (self::sessionConnectedMarkers() as $row) {
            $id = (int) ($row['user_id'] ?? 0);
            if ($id > 0 && ! isset($byId[$id])) {
                $byId[$id] = $row;
            }
        }

        foreach (self::recentActiveTripMarkers() as $row) {
            $id = (int) ($row['user_id'] ?? 0);
            if ($id > 0 && ! isset($byId[$id])) {
                $byId[$id] = $row;
            }
        }

        return array_values($byId);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private static function liveRedisMarkers(): array
    {
        $out = [];
        try {
            $ids = [];
            $fromSet = Redis::smembers(self::ONLINE_SET);
            if (is_array($fromSet)) {
                foreach ($fromSet as $m) {
                    $id = (int) $m;
                    if ($id < 1) {
                        continue;
                    }
                    if (Redis::exists(self::onlineKey($id))) {
                        $ids[] = $id;
                    } else {
                        Redis::srem(self::ONLINE_SET, (string) $id);
                    }
                }
            }

            // توافق مع أعضاء GEO القديمة
            $members = Redis::zrange(self::GEO_KEY, 0, -1);
            if (is_array($members)) {
                foreach ($members as $m) {
                    $id = (int) $m;
                    if ($id > 0 && Redis::exists(self::onlineKey($id))) {
                        $ids[] = $id;
                    }
                }
            }

            $ids = array_values(array_unique($ids));
            if ($ids === []) {
                return [];
            }

            $users = User::query()
                ->where('roll', 'Customer')
                ->whereIn('id', $ids)
                ->get(['id', 'firstName', 'lastName', 'number'])
                ->keyBy('id');

            $lastLocs = self::lastPickupByUserIds($ids);

            foreach ($ids as $id) {
                $u = $users->get($id);
                if (! $u) {
                    continue;
                }
                $coords = self::coordsForUser($id);
                $source = 'live';
                if ($coords === null && isset($lastLocs[$id])) {
                    $coords = $lastLocs[$id];
                    $source = 'live_last';
                }
                if ($coords === null) {
                    $coords = [33.5138, 36.2765];
                    $source = 'live_approx';
                }
                $out[] = self::markerRow($u, $coords[0], $coords[1], $source);
            }
        } catch (\Throwable $e) {
            Log::warning('CustomerPresenceService::liveRedisMarkers '.$e->getMessage());
        }

        return $out;
    }

    /**
     * زبائن لديهم توكن Sanctum استُخدم مؤخراً = متصلون بالتطبيق.
     *
     * @return list<array<string, mixed>>
     */
    private static function sessionConnectedMarkers(): array
    {
        $out = [];
        try {
            if (! Schema::hasTable('personal_access_tokens')) {
                return [];
            }

            $since = now()->subMinutes(self::SESSION_MINUTES);
            $tokenable = User::class;

            $q = DB::table('personal_access_tokens as t')
                ->join('users as u', 'u.id', '=', 't.tokenable_id')
                ->where('t.tokenable_type', $tokenable)
                ->where('u.roll', 'Customer')
                ->where(function ($w) use ($since) {
                    $w->where('t.last_used_at', '>=', $since)
                        ->orWhere(function ($w2) use ($since) {
                            $w2->whereNull('t.last_used_at')
                                ->where('t.created_at', '>=', $since);
                        });
                });

            if (Schema::hasColumn('users', 'banned')) {
                $q->where(function ($w) {
                    $w->whereNull('u.banned')->orWhere('u.banned', false)->orWhere('u.banned', 0);
                });
            }

            $rows = $q->select([
                'u.id',
                'u.firstName',
                'u.lastName',
                'u.number',
            ])
                ->distinct()
                ->limit(500)
                ->get();

            if ($rows->isEmpty()) {
                return [];
            }

            $ids = $rows->pluck('id')->map(fn ($id) => (int) $id)->all();
            $lastLocs = self::lastPickupByUserIds($ids);

            foreach ($rows as $u) {
                $id = (int) $u->id;
                $coords = self::coordsForUser($id);
                if ($coords === null && isset($lastLocs[$id])) {
                    $coords = $lastLocs[$id];
                }
                if ($coords === null) {
                    // بدون أي موقع معروف: ضع علامة عند مركز دمشق حتى يظهر في القائمة/الخريطة
                    $coords = [33.5138, 36.2765];
                    $source = 'session_approx';
                } else {
                    $source = 'session';
                }
                $out[] = self::markerRow($u, $coords[0], $coords[1], $source);
            }
        } catch (\Throwable $e) {
            Log::warning('CustomerPresenceService::sessionConnected '.$e->getMessage());
        }

        return $out;
    }

    /**
     * طلبات نشطة حُدّثت مؤخراً فقط (لا طلبات Pending عالقة لأيام).
     *
     * @return list<array<string, mixed>>
     */
    private static function recentActiveTripMarkers(): array
    {
        $out = [];
        try {
            $statuses = [
                RequestModel::STATUS_PENDING,
                RequestModel::STATUS_RESERVED,
                RequestModel::STATUS_DRIVER_ARRIVED,
                RequestModel::STATUS_AWAITING_DESTINATION,
                RequestModel::STATUS_RUNNING,
            ];
            $since = now()->subMinutes(self::ACTIVE_TRIP_MINUTES);

            $rows = RequestModel::query()
                ->whereIn('status', $statuses)
                ->where('updated_at', '>=', $since)
                ->where(function ($q) {
                    $q->whereNull('billing_kind')
                        ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
                })
                ->with(['user:id,firstName,lastName,number,roll', 'startLocation'])
                ->orderByDesc('updated_at')
                ->limit(300)
                ->get();

            $seen = [];
            foreach ($rows as $req) {
                $uid = (int) ($req->userId ?? 0);
                if ($uid < 1 || isset($seen[$uid])) {
                    continue;
                }
                $u = $req->user;
                if (! $u || ($u->roll ?? '') !== 'Customer') {
                    continue;
                }
                $loc = $req->startLocation;
                if (! $loc) {
                    continue;
                }
                $lat = (float) ($loc->latitude ?? 0);
                $lng = (float) ($loc->longitude ?? 0);
                if (! is_finite($lat) || ! is_finite($lng) || ($lat == 0.0 && $lng == 0.0)) {
                    continue;
                }
                $seen[$uid] = true;
                $out[] = self::markerRow($u, $lat, $lng, 'active_trip');
            }
        } catch (\Throwable $e) {
            Log::debug('CustomerPresenceService::recentActiveTrip '.$e->getMessage());
        }

        return $out;
    }

    /**
     * @return array{0:float,1:float}|null  [lat, lng]
     */
    private static function coordsForUser(int $userId): ?array
    {
        try {
            if (Redis::exists(self::lastPosKey($userId))) {
                $raw = Redis::get(self::lastPosKey($userId));
                $decoded = is_string($raw) ? json_decode($raw, true) : null;
                if (is_array($decoded)) {
                    $lat = (float) ($decoded['lat'] ?? 0);
                    $lng = (float) ($decoded['lng'] ?? 0);
                    if (is_finite($lat) && is_finite($lng) && ! ($lat == 0.0 && $lng == 0.0)) {
                        return [$lat, $lng];
                    }
                }
            }
            $pos = Redis::geopos(self::GEO_KEY, (string) $userId);
            $pair = is_array($pos) ? ($pos[0] ?? null) : null;
            if (is_array($pair) && count($pair) >= 2) {
                $lng = (float) $pair[0];
                $lat = (float) $pair[1];
                if (is_finite($lat) && is_finite($lng) && ! ($lat == 0.0 && $lng == 0.0)) {
                    return [$lat, $lng];
                }
            }
        } catch (\Throwable $e) {
        }

        return null;
    }

    /**
     * @param  list<int>  $userIds
     * @return array<int, array{0:float,1:float}>
     */
    private static function lastPickupByUserIds(array $userIds): array
    {
        $out = [];
        $userIds = array_values(array_unique(array_filter(array_map('intval', $userIds))));
        if ($userIds === []) {
            return [];
        }

        try {
            foreach (array_chunk($userIds, 80) as $chunk) {
                $placeholders = implode(',', array_fill(0, count($chunk), '?'));
                $sql = "
                    SELECT r.userId AS uid, l.latitude AS lat, l.longitude AS lng
                    FROM requests r
                    INNER JOIN locations l ON l.id = r.startLocationId
                    INNER JOIN (
                        SELECT userId, MAX(id) AS max_id
                        FROM requests
                        WHERE userId IN ($placeholders)
                          AND startLocationId IS NOT NULL
                        GROUP BY userId
                    ) t ON t.max_id = r.id
                ";
                $rows = DB::select($sql, $chunk);
                foreach ($rows as $row) {
                    $uid = (int) ($row->uid ?? 0);
                    $lat = (float) ($row->lat ?? 0);
                    $lng = (float) ($row->lng ?? 0);
                    if ($uid > 0 && is_finite($lat) && is_finite($lng) && ! ($lat == 0.0 && $lng == 0.0)) {
                        $out[$uid] = [$lat, $lng];
                    }
                }
            }
        } catch (\Throwable $e) {
            Log::debug('CustomerPresenceService::lastPickup '.$e->getMessage());
        }

        return $out;
    }

    /**
     * @param  object  $u
     * @return array<string, mixed>
     */
    private static function markerRow(object $u, float $lat, float $lng, string $source): array
    {
        $id = (int) ($u->id ?? 0);
        $name = trim(($u->firstName ?? '').' '.($u->lastName ?? ''));

        return [
            'user_id' => $id,
            'name' => $name !== '' ? $name : ('زبون #'.$id),
            'number' => $u->number ?? null,
            'latitude' => $lat,
            'longitude' => $lng,
            'kind' => 'customer',
            'source' => $source,
        ];
    }
}
