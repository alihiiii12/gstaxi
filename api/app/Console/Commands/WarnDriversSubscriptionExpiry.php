<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\DriverSubscriptionService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class WarnDriversSubscriptionExpiry extends Command
{
    protected $signature = 'subscriptions:warn-drivers-48h';

    protected $description = 'تذكير تجديد الاشتراك (24س عبر Driver + تنبيه 48س لحسابات expireDate)';

    public function handle(): int
    {
        DriverSubscriptionService::sendReminders();

        $targetDate = now()->addDays(2)->toDateString();

        $users = User::query()
            ->where('roll', 'Driver')
            ->where('banned', false)
            ->whereDate('expireDate', $targetDate)
            ->get(['id', 'number', 'firstName', 'lastName', 'expireDate']);

        foreach ($users as $u) {
            Log::warning('[subscription_warn_48h]', [
                'user_id' => $u->id,
                'number' => $u->number,
                'name' => trim($u->firstName.' '.$u->lastName),
                'expireDate' => (string) $u->expireDate,
            ]);
        }

        $this->info('Subscription reminders processed; legacy 48h logs: '.$users->count());

        return self::SUCCESS;
    }
}
