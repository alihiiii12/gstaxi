<?php

namespace App\Console\Commands;

use App\Services\DriverSubscriptionService;
use Illuminate\Console\Command;

class ProcessDriverSubscriptions extends Command
{
    protected $signature = 'drivers:process-subscriptions';

    protected $description = 'تذكير قبل 24 ساعة وحظر السائقين منتهي الاشتراك';

    public function handle(): int
    {
        DriverSubscriptionService::processScheduled();
        $this->info('Driver subscriptions processed.');

        return self::SUCCESS;
    }
}
