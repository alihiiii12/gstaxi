<?php

namespace App\Console\Commands;

use App\Models\RequestModel;
use App\Services\DriverNearbyService;
use App\Services\DriverPollCacheService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * إغلاق عدادات حرة عالقة: بدأت قبل 6 ساعات أو أكثر وسائقها غير متصل.
 * تُعلَّم Removed بسبب free_meter_auto_closed (لا تُحسب في الإيرادات)،
 * وإن أنهاها السائق لاحقاً من تطبيقه يقبلها finishTrip بأجرتها الفعلية.
 */
class CloseStaleFreeMeters extends Command
{
    public const REASON = 'free_meter_auto_closed';

    public const MAX_AGE_HOURS = 6;

    protected $signature = 'free-meter:close-stale {--dry-run : عرض فقط بدون إغلاق}';

    protected $description = 'إغلاق العدادات الحرة العالقة (أقدم من 6 ساعات وسائقها غير متصل)';

    public function handle(): int
    {
        $cutoff = now()->subHours(self::MAX_AGE_HOURS);
        $dry = (bool) $this->option('dry-run');

        $rows = RequestModel::query()
            ->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER)
            ->whereIn('status', [
                RequestModel::STATUS_RUNNING,
                RequestModel::STATUS_RESERVED,
                RequestModel::STATUS_PENDING,
                RequestModel::STATUS_DRIVER_ARRIVED,
                RequestModel::STATUS_AWAITING_DESTINATION,
            ])
            ->whereRaw('COALESCE(trip_started_at, created_at) < ?', [$cutoff])
            ->limit(500)
            ->get(['id', 'driverId', 'status', 'trip_started_at', 'created_at']);

        $closed = 0;
        foreach ($rows as $req) {
            $driverId = (int) ($req->driverId ?? 0);
            if ($driverId > 0 && DriverNearbyService::isDriverOnline($driverId)) {
                continue;
            }
            if ($dry) {
                $this->line("#{$req->id} driver={$driverId} started=".($req->trip_started_at ?? $req->created_at));
                $closed++;

                continue;
            }
            $req->status = RequestModel::STATUS_REMOVED;
            $req->cancel_reason = self::REASON;
            $req->save();
            $closed++;
        }

        if ($closed > 0 && ! $dry) {
            Log::info('[free_meter] auto-closed stale free meters: '.$closed);
            try {
                DriverPollCacheService::bust();
            } catch (\Throwable $e) {
            }
        }
        $this->info(($dry ? 'would close: ' : 'closed: ').$closed);

        return self::SUCCESS;
    }
}
