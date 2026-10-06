<?php



namespace App\Services;



use Illuminate\Support\Facades\Cache;



/**

 * Cache استطلاع السائق — قصير + إبطال فوري عند طلب جديد.

 */

class DriverPollCacheService

{

    /** ثوانٍ — أطول تحت Starlink لتقليل الطلبات عبر الرفع الضعيف. */

    public const TTL_IMMEDIATE = 18;

    public const TTL_SNAPSHOT = 18;

    public const TTL_DRIVER_REQUESTS = 28;



    /** آخر نتيجة للـ throttle (لا تُرجع [] فارغة للسائق). */

    public const TTL_LAST = 180;



    public static function bust(): void

    {

        Cache::put('driver_poll_bust', (string) microtime(true), 600);

    }



    private static function bustToken(): string

    {

        return (string) Cache::get('driver_poll_bust', '0');

    }



    public static function immediatePendingKey(int $driverId): string

    {

        return 'immediate_pending:'.$driverId.':'.self::bustToken();

    }



    public static function pollSnapshotKey(int $driverId): string

    {

        return 'driver_poll:'.$driverId.':'.self::bustToken();

    }



    public static function driverRequestsKey(int $driverId): string

    {

        return 'driver_requests:'.$driverId.':'.self::bustToken();

    }



    public static function immediatePendingLastKey(int $driverId): string

    {

        return 'immediate_pending_last:'.$driverId.':'.self::bustToken();

    }



    public static function pollSnapshotLastKey(int $driverId): string

    {

        return 'driver_poll_last:'.$driverId.':'.self::bustToken();

    }



    public static function driverRequestsLastKey(int $driverId): string

    {

        return 'driver_requests_last:'.$driverId.':'.self::bustToken();

    }



    public static function rememberImmediateLast(int $driverId, mixed $data): void

    {

        Cache::put(self::immediatePendingLastKey($driverId), $data, self::TTL_LAST);

    }



    public static function rememberPollSnapshotLast(int $driverId, mixed $data): void

    {

        Cache::put(self::pollSnapshotLastKey($driverId), $data, self::TTL_LAST);

    }



    public static function rememberDriverRequestsLast(int $driverId, mixed $data): void

    {

        Cache::put(self::driverRequestsLastKey($driverId), $data, self::TTL_LAST);

    }



    public static function getImmediatePendingLast(int $driverId): mixed

    {

        return Cache::get(self::immediatePendingLastKey($driverId));

    }



    public static function getPollSnapshotLast(int $driverId): mixed

    {

        return Cache::get(self::pollSnapshotLastKey($driverId));

    }



    public static function getDriverRequestsLast(int $driverId): mixed

    {

        return Cache::get(self::driverRequestsLastKey($driverId));

    }

}


