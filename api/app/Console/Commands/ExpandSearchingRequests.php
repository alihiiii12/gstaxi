<?php

namespace App\Console\Commands;

use App\Models\RequestModel;
use App\Services\ImmediateDriverNotifier;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * توسيع نطاق البحث للطلبات الفورية حسب عمرها (حتى 3 كم بعد دقيقة) من السيرفر،
 * لأن مؤقّت تطبيق الراكب يتوقف عند إطفاء الشاشة.
 */
class ExpandSearchingRequests extends Command
{
    protected $signature = 'requests:expand-searching';

    protected $description = 'توسيع نطاق الطلبات الفورية بانتظار سائق حسب عمر الطلب';

    public function handle(ImmediateDriverNotifier $notifier): int
    {
        $maxAge = ImmediateDriverNotifier::SEARCH_TIMEOUT_SECONDS;

        $rows = RequestModel::query()
            ->where('type', RequestModel::TYPE_IMMEDIATE)
            ->where('status', RequestModel::STATUS_PENDING)
            ->whereNull('driverId')
            ->where('created_at', '>=', now()->subSeconds($maxAge))
            ->with('startLocation')
            ->limit(100)
            ->get();

        foreach ($rows as $req) {
            if (RequestModel::isAdminDispatched($req)) {
                continue;
            }
            $age = (int) $req->created_at->diffInSeconds(now(), true);
            $stage = ImmediateDriverNotifier::dueStageForAge($age);
            if ($stage <= 0) {
                continue;
            }
            try {
                $notifier->expandToStage($req, $stage);
            } catch (\Throwable $e) {
                Log::warning('[expand_searching] '.$req->id.' — '.$e->getMessage());
            }
        }

        return self::SUCCESS;
    }
}
