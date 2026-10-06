<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\DriverSubscriptionService;
use Illuminate\Console\Command;

class ExpireDriverSubscriptions extends Command
{
    protected $signature = 'subscriptions:expire-drivers';

    protected $description = 'حظر السائقين منتهي الاشتراك (drivers) ورفع الحظر المؤقت المنتهي (expireDate)';

    public function handle(): int
    {
        DriverSubscriptionService::blockExpired();

        // users.expireDate للسائق = نهاية الحظر المؤقت (عقوبة شكوى)؛ الاشتراك يُدار من drivers.subscription_*.
        $count = User::query()
            ->where('roll', 'Driver')
            ->where('banned', true)
            ->whereNotNull('expireDate')
            ->whereDate('expireDate', '<', now()->toDateString())
            ->update(['banned' => false]);

        $this->info("Driver subscriptions blocked; lifted {$count} expired temporary ban(s).");

        return self::SUCCESS;
    }
}
