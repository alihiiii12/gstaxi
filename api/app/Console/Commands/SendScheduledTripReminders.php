<?php

namespace App\Console\Commands;

use App\Models\CustomerNotification;
use App\Models\Driver;
use App\Models\DriverNotification;
use App\Models\RequestModel;
use App\Models\UsedDiscount;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

class SendScheduledTripReminders extends Command
{
    protected $signature = 'bookings:send-reminders';

    protected $description = 'حجز مسبق: تذكير ~30 د، سؤال الجاهزية ~5 د (توقيت سوريا)، إلغاء عند انتهاء المهلة';

    private function appTz(): string
    {
        return config('app.timezone', 'Asia/Damascus');
    }

    /** دقائق متبقية حتى موعد الرحلة (سالب = بعد الموعد) بتوقيت التطبيق. */
    private function minutesUntilTripSigned(RequestModel $req): ?int
    {
        if (! $req->requestDate) {
            return null;
        }
        $tz = $this->appTz();
        $at = Carbon::parse($req->requestDate)->timezone($tz);
        $now = Carbon::now($tz);

        return (int) $now->diffInMinutes($at, false);
    }

    public function handle(): int
    {
        $this->processScheduledWindows();
        $this->processLegacyDayBeforeReminder();

        return self::SUCCESS;
    }

    private function processScheduledWindows(): void
    {
        $t30 = 0;
        $t0 = 0;
        $noGo = 0;

        RequestModel::query()
            ->where('type', RequestModel::TYPE_SCHEDULE)
            ->where('status', RequestModel::STATUS_RESERVED)
            ->whereNull('sched_driver_started_at')
            ->whereNotNull('driverId')
            ->whereNotNull('requestDate')
            ->chunkById(80, function ($rows) use (&$t30, &$t0, &$noGo) {
                foreach ($rows as $req) {
                    $signed = $this->minutesUntilTripSigned($req);

                    // فتح نافذة الانطلاق (~30 د قبل الموعد): إشعار للراكب وزر «انطلق للراكب» للسائق.
                    if (
                        $req->sched_t30_sent_at === null
                        && $req->sched_driver_started_at === null
                        && $signed !== null
                        && $signed <= RequestModel::SCHED_GO_WINDOW_MINUTES
                        && $signed >= -RequestModel::SCHED_NO_GO_CANCEL_AFTER_MINUTES
                    ) {
                        $req->sched_t30_sent_at = now($this->appTz());
                        $req->save();
                        $this->pushSchedT30($req);
                        $t30++;
                    }

                    // عند الموعد (±3 د): نافذة للسائق مثل قبول الفوري
                    if (
                        $req->sched_at_time_sent_at === null
                        && $req->sched_driver_started_at === null
                        && $signed !== null
                        && $signed <= 3
                        && $signed >= -5
                    ) {
                        $req->sched_at_time_sent_at = now($this->appTz());
                        if ($req->sched_ready_answered_at === null) {
                            $req->sched_ready_answered_at = now($this->appTz());
                        }
                        $req->save();
                        $this->pushSchedAtTime($req);
                        $t0++;
                    }

                    // لم ينطلق السائق حتى بعد الموعد بمهلة — إلغاء وإبلاغ الطرفين.
                    if (
                        $req->sched_driver_started_at === null
                        && $signed !== null
                        && $signed < -RequestModel::SCHED_NO_GO_CANCEL_AFTER_MINUTES
                    ) {
                        $req->status = RequestModel::STATUS_REMOVED;
                        $req->cancel_reason = 'driver_no_go_scheduled';
                        $req->save();
                        try {
                            UsedDiscount::releaseForRequest((int) $req->id);
                        } catch (\Throwable $e) {
                        }
                        $this->pushDriverNoGoCancelled($req);
                        $noGo++;
                    }
                }
            });

        if ($t30 + $t0 + $noGo > 0) {
            $this->info("Scheduled ({$this->appTz()}): t30={$t30}, t0={$t0}, no_go_cancelled={$noGo}");
        }
    }

    private function processLegacyDayBeforeReminder(): void
    {
        $tz = $this->appTz();
        $windowStart = now($tz)->addHours(23);
        $windowEnd = now($tz)->addHours(25);

        $count = 0;
        RequestModel::query()
            ->where('type', RequestModel::TYPE_SCHEDULE)
            ->whereIn('status', [RequestModel::STATUS_PENDING, RequestModel::STATUS_RESERVED])
            ->where('reminder_sent', false)
            ->whereBetween('requestDate', [$windowStart, $windowEnd])
            ->chunkById(50, function ($rows) use (&$count) {
                foreach ($rows as $req) {
                    Log::info('[booking_reminder_24h]', [
                        'request_id' => $req->id,
                        'user_id' => $req->userId,
                        'request_date' => (string) $req->requestDate,
                    ]);
                    $req->reminder_sent = true;
                    $req->save();
                    $count++;
                }
            });

        if ($count > 0) {
            $this->info("Legacy 24h reminder flags: {$count}");
        }
    }

    private function pushDriverNoGoCancelled(RequestModel $req): void
    {
        $rid = (int) $req->id;
        $payload = ['kind' => 'sched_driver_no_go', 'request_id' => $rid];
        $customerTitle = 'تم إلغاء الطلب المسبق';
        $customerBody = 'لم يبدأ السائق التوجه إليك في الموعد، فأُلغي الطلب. يمكنك إرسال طلب جديد.';

        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => $customerTitle,
                'body' => $customerBody,
                'kind' => 'sched_driver_no_go',
                'reference_type' => 'request',
                'reference_id' => $rid,
                'payload' => $payload,
            ]);
        } catch (\Throwable $e) {
            Log::warning('[sched_no_go_customer]', ['e' => $e->getMessage()]);
        }
        $this->fcmToUserId((int) $req->userId, $customerTitle, $customerBody, $payload);

        $driver = Driver::find($req->driverId);
        if (! $driver) {
            return;
        }
        $driverTitle = 'أُلغي الحجز المسبق';
        $driverBody = 'لم تضغط «انطلق للراكب» في الموعد، فأُلغي الحجز المسبق.';
        try {
            DriverNotification::create([
                'user_id' => $driver->userId,
                'title' => $driverTitle,
                'body' => $driverBody,
                'kind' => 'sched_driver_no_go',
                'reference_type' => 'request',
                'reference_id' => $rid,
                'payload' => $payload,
            ]);
        } catch (\Throwable $e) {
            Log::warning('[sched_no_go_driver]', ['e' => $e->getMessage()]);
        }
        $this->fcmToUserId((int) $driver->userId, $driverTitle, $driverBody, $payload);
    }

    private function pushSchedT30(RequestModel $req): void
    {
        $rid = (int) $req->id;
        $payload = ['kind' => 'sched_t30', 'request_id' => $rid];
        $title = 'سيبدأ طلبك المسبق';
        $customerBody = 'سيبدأ طلبك المسبق خلال نصف ساعة تقريباً — سيتوجه السائق إليك قريباً.';
        $driverTitle = 'حان وقت الانطلاق للحجز المسبق';
        $driverBody = 'حجزك المسبق يبدأ خلال نصف ساعة — اضغط «انطلق للراكب».';

        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => $title,
                'body' => $customerBody,
                'kind' => 'sched_t30',
                'reference_type' => 'request',
                'reference_id' => $rid,
                'payload' => $payload,
            ]);
        } catch (\Throwable $e) {
            Log::warning('[sched_t30_customer]', ['e' => $e->getMessage()]);
        }
        $this->fcmToUserId((int) $req->userId, $title, $customerBody, $payload);

        $driver = Driver::find($req->driverId);
        if (! $driver) {
            return;
        }

        try {
            DriverNotification::create([
                'user_id' => $driver->userId,
                'title' => $driverTitle,
                'body' => $driverBody,
                'kind' => 'sched_t30',
                'reference_type' => 'request',
                'reference_id' => $rid,
                'payload' => $payload,
            ]);
        } catch (\Throwable $e) {
            Log::warning('[sched_t30_driver]', ['e' => $e->getMessage()]);
        }
        $this->fcmToUserId((int) $driver->userId, $driverTitle, $driverBody, $payload);
    }

    /** عند حلول الموعد — نافذة/رنة للسائق لبدء التوجه مثل الفوري. */
    private function pushSchedAtTime(RequestModel $req): void
    {
        $rid = (int) $req->id;
        $payload = ['kind' => 'sched_at_time', 'request_id' => $rid];
        $when = $req->requestDate
            ? Carbon::parse($req->requestDate)->timezone($this->appTz())->format('Y-m-d H:i')
            : '';
        $title = 'حان موعد الحجز المسبق';
        $body = $when !== ''
            ? "حان موعد الرحلة ({$when}). اضغط «انطلق للراكب» الآن."
            : 'حان موعد الرحلة. اضغط «انطلق للراكب» الآن.';

        $driver = Driver::find($req->driverId);
        if (! $driver) {
            return;
        }

        try {
            DriverNotification::create([
                'user_id' => $driver->userId,
                'title' => $title,
                'body' => $body,
                'kind' => 'sched_at_time',
                'reference_type' => 'request',
                'reference_id' => $rid,
                'payload' => $payload,
            ]);
        } catch (\Throwable $e) {
            Log::warning('[sched_at_time_driver]', ['e' => $e->getMessage()]);
        }
        $this->fcmToUserId((int) $driver->userId, $title, $body, array_merge($payload, [
            'type' => 'sched_at_time',
        ]));

        try {
            CustomerNotification::create([
                'user_id' => $req->userId,
                'title' => 'حان موعد رحلتك',
                'body' => 'السائق سيبدأ التوجه إليك قريباً.',
                'kind' => 'sched_at_time_passenger',
                'reference_type' => 'request',
                'reference_id' => $rid,
                'payload' => ['kind' => 'sched_at_time_passenger', 'request_id' => $rid],
            ]);
        } catch (\Throwable $e) {
        }
        $this->fcmToUserId(
            (int) $req->userId,
            'حان موعد رحلتك',
            'السائق سيبدأ التوجه إليك قريباً.',
            ['kind' => 'sched_at_time_passenger', 'request_id' => $rid]
        );
    }

    private function fcmToUserId(int $userId, string $title, string $body, array $data): void
    {
        try {
            if (! class_exists(\App\Services\FcmPushService::class)) {
                return;
            }
            app(\App\Services\FcmPushService::class)->sendToUserId($userId, $title, $body, $data);
        } catch (\Throwable $e) {
            Log::debug('[sched_fcm] '.$e->getMessage());
        }
    }
}
