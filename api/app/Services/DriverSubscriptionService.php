<?php

namespace App\Services;

use App\Models\Driver;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Schema;

/**
 * اشتراك شهري 30 يوماً للسائق — تذكير قبل 24 ساعة، حظر تلقائي، تجديد يدوي من الإدارة.
 */
class DriverSubscriptionService
{
    public const REMINDER_HOURS = 24;

    public const BLOCK_MESSAGE = 'قم بالدفع — تجديد الاشتراك الشهري';

    public static function beginSubscription(Driver $driver, ?Carbon $from = null): void
    {
        $start = $from ?? Carbon::now();
        $driver->subscription_starts_at = $start;
        $driver->subscription_ends_at = $start->copy()->addDays(30);
        $driver->subscription_blocked = false;
        $driver->subscription_reminder_sent_at = null;
        $driver->save();
    }

    public static function renewFromPayment(Driver $driver): void
    {
        $now = Carbon::now();
        $driver->subscription_starts_at = $now;
        $driver->subscription_ends_at = $now->copy()->addDays(30);
        $driver->subscription_blocked = false;
        $driver->subscription_reminder_sent_at = null;
        $driver->save();

        static::removeFromOnlineGeo($driver);
    }

    /**
     * تعيين فترة اشتراك مخصصة (من تاريخ إلى تاريخ).
     */
    public static function setCustomPeriod(
        Driver $driver,
        Carbon $startsAt,
        Carbon $endsAt,
    ): void {
        if ($endsAt->lte($startsAt)) {
            throw new \InvalidArgumentException('تاريخ نهاية الاشتراك يجب أن يكون بعد تاريخ البداية');
        }

        $driver->subscription_starts_at = $startsAt->copy()->startOfDay();
        $driver->subscription_ends_at = $endsAt->copy()->endOfDay();
        $driver->subscription_blocked = $endsAt->isPast();
        $driver->subscription_reminder_sent_at = null;
        $driver->save();

        if ($driver->subscription_blocked) {
            static::removeFromOnlineGeo($driver);
        }
    }

    public static function setBlocked(Driver $driver, bool $blocked): void
    {
        $driver->subscription_blocked = $blocked;
        $driver->save();
        if ($blocked) {
            static::removeFromOnlineGeo($driver);
        }
    }

    public static function isSubscriptionActive(Driver $driver): bool
    {
        if ($driver->subscription_blocked) {
            return false;
        }
        if (! $driver->subscription_ends_at) {
            return true;
        }

        return Carbon::parse($driver->subscription_ends_at)->isFuture();
    }

    public static function loginBlockedMessage(Driver $driver): ?string
    {
        if (static::isSubscriptionActive($driver)) {
            return null;
        }

        return self::BLOCK_MESSAGE;
    }

    /** للاستبعاد من السائقين القريبين وتحديث الموقع. */
    public static function isVisibleToPassengers(Driver $driver): bool
    {
        return static::isSubscriptionActive($driver);
    }

    public static function processScheduled(): void
    {
        static::sendReminders();
        static::blockExpired();
    }

    public static function sendReminders(): void
    {
        $now = Carbon::now();
        $windowEnd = $now->copy()->addHours(self::REMINDER_HOURS);

        Driver::query()
            ->where('subscription_blocked', false)
            ->whereNotNull('subscription_ends_at')
            ->where('subscription_ends_at', '>', $now)
            ->where('subscription_ends_at', '<=', $windowEnd)
            ->whereNull('subscription_reminder_sent_at')
            ->chunkById(50, function ($drivers) {
                foreach ($drivers as $driver) {
                    static::notifyDriver(
                        $driver,
                        'تذكير تجديد الاشتراك',
                        'اشتراكك ينتهي خلال 24 ساعة. يرجى تجديد الاشتراك الشهري.',
                        'subscription_reminder',
                    );
                    $driver->subscription_reminder_sent_at = Carbon::now();
                    $driver->save();
                }
            });
    }

    public static function blockExpired(): void
    {
        $now = Carbon::now();

        Driver::query()
            ->where('subscription_blocked', false)
            ->whereNotNull('subscription_ends_at')
            ->where('subscription_ends_at', '<', $now)
            ->chunkById(50, function ($drivers) {
                foreach ($drivers as $driver) {
                    $driver->subscription_blocked = true;
                    $driver->save();
                    static::removeFromOnlineGeo($driver);
                    static::notifyDriver(
                        $driver,
                        'انتهى الاشتراك',
                        self::BLOCK_MESSAGE,
                        'subscription_expired',
                    );
                }
            });
    }

    public static function notifyDriver(
        Driver $driver,
        string $title,
        string $body,
        string $kind,
    ): void {
        $payload = json_encode([
            'kind' => $kind,
            'driver_id' => (int) $driver->id,
        ], JSON_UNESCAPED_UNICODE);

        try {
            if (Schema::hasTable('driver_notifications')) {
                DB::table('driver_notifications')->insert([
                    'driver_id' => $driver->id,
                    'title' => $title,
                    'body' => $body,
                    'data' => $payload,
                    'read_at' => null,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('driver_notifications insert: '.$e->getMessage());
        }

        try {
            $user = $driver->user ?? null;
            $token = $user?->fcm_token ?? $user?->fcmToken ?? null;
            if ($token && class_exists(\App\Services\FcmPushService::class)) {
                app(\App\Services\FcmPushService::class)->sendToToken($token, $title, $body, [
                    'kind' => $kind,
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('FCM subscription notify: '.$e->getMessage());
        }
    }

    public static function removeFromOnlineGeo(Driver $driver): void
    {
        try {
            Redis::del('driver:'.(int) $driver->id.':online');
            Redis::zrem('drivers', (string) $driver->id);
        } catch (\Throwable $e) {
            // ignore
        }
    }

}
