<?php

use App\Models\Driver;
use App\Services\DriverSubscriptionService;
use Carbon\Carbon;
use Illuminate\Database\Migrations\Migration;

return new class extends Migration
{
    public function up(): void
    {
        Driver::query()
            ->whereNull('subscription_ends_at')
            ->orderBy('id')
            ->chunkById(100, function ($drivers) {
                foreach ($drivers as $driver) {
                    $from = $driver->subscription_starts_at
                        ? Carbon::parse($driver->subscription_starts_at)
                        : ($driver->created_at ? Carbon::parse($driver->created_at) : Carbon::now());
                    DriverSubscriptionService::beginSubscription($driver, $from);
                }
            });
    }

    public function down(): void
    {
        // لا تراجع تلقائي — البيانات قد تكون مُحدَّثة يدوياً.
    }
};
