<?php

namespace App\Console\Commands;

use App\Models\RequestModel;
use App\Models\UsedDiscount;
use App\Services\DriverPollCacheService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Redis;

class ExpireStalePendingRequests extends Command
{
    protected $signature = 'requests:expire-stale-pending {--minutes=120 : الحد الأدنى لعمر الطلب بالدقائق}';

    protected $description = 'تحويل طلبات Pending القديمة (بدون قبول) إلى Removed وتحرير الكوبونات';

    public function handle(): int
    {
        $minutes = max(5, (int) $this->option('minutes'));
        $threshold = now()->subMinutes($minutes);

        // بدون سائق، أو موجّه لسائق ولم يُقبل بعد
        $q = RequestModel::query()
            ->where('status', RequestModel::STATUS_PENDING)
            ->where('updated_at', '<', $threshold)
            ->where(function ($inner) {
                $inner->whereNull('driverId')
                    ->orWhere('billing_kind', RequestModel::BILLING_KIND_APP_REQUEST)
                    ->orWhereNull('billing_kind');
            });

        $count = 0;
        $q->orderBy('id')->chunkById(100, function ($rows) use (&$count) {
            foreach ($rows as $req) {
                if ($req->billing_kind === RequestModel::BILLING_KIND_FREE_METER) {
                    continue;
                }
                $req->status = RequestModel::STATUS_REMOVED;
                $req->cancel_reason = 'auto_expire_stale_pending';
                $req->save();
                try {
                    UsedDiscount::releaseForRequest((int) $req->id);
                } catch (\Throwable $e) {
                }
                $count++;
                try {
                    Redis::del('request:'.$req->id.':eligible');
                } catch (\Throwable $e) {
                }
            }
        });

        if ($count > 0) {
            try {
                DriverPollCacheService::bust();
            } catch (\Throwable $e) {
            }
        }

        $this->info("Expired {$count} stale pending request(s).");

        return self::SUCCESS;
    }
}
