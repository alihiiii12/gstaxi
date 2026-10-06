<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * إبطال كل جلسات Admin/Employee (Sanctum) —
 * مفيد بعد ثغرة التصعيد أو إيقاف الدخول من تطبيق قديم.
 */
class RevokeStaffSessions extends Command
{
    protected $signature = 'sessions:revoke-staff
                            {--also-demote-suspicious : إنزال حسابات Customer السابقة التي أصبحت Admin بدون إذن (اختياري)}';

    protected $description = 'Revoke all Sanctum tokens for Admin and Employee users';

    public function handle(): int
    {
        $staffIds = User::query()
            ->whereIn('roll', ['Admin', 'Employee'])
            ->pluck('id');

        if ($staffIds->isEmpty()) {
            $this->info('No staff users found.');

            return self::SUCCESS;
        }

        $deleted = DB::table('personal_access_tokens')
            ->where('tokenable_type', User::class)
            ->whereIn('tokenable_id', $staffIds)
            ->delete();

        $this->info("Revoked {$deleted} token(s) for {$staffIds->count()} staff account(s).");

        if ($this->option('also-demote-suspicious')) {
            // حسابات كان دورها يُرفع لـ Admin عبر الثغرة غالباً بدون permissions موظفين.
            $demoted = User::query()
                ->where('roll', 'Admin')
                ->where(function ($q) {
                    $q->whereNull('permissions')
                        ->orWhere('permissions', '[]')
                        ->orWhere('permissions', 'null');
                })
                ->whereNotNull('phone_verified_at')
                ->update(['roll' => 'Customer']);

            $this->warn("Demoted {$demoted} suspicious Admin account(s) back to Customer.");
        }

        $this->info('Done. Staff must log in again from the web admin panel.');

        return self::SUCCESS;
    }
}
