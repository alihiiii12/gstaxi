<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * يعرض حسابات Admin/Employee التي لديها جلسة نشطة (توكن Sanctum).
 */
class ListActiveStaffSessions extends Command
{
    protected $signature = 'sessions:list-active-staff';

    protected $description = 'List Admin/Employee accounts that currently have active Sanctum tokens';

    public function handle(): int
    {
        $rows = DB::table('personal_access_tokens as t')
            ->join('users as u', function ($join) {
                $join->on('u.id', '=', 't.tokenable_id')
                    ->where('t.tokenable_type', '=', User::class);
            })
            ->whereIn('u.roll', ['Admin', 'Employee'])
            ->whereNull('u.deleted_at')
            ->orderByDesc('t.last_used_at')
            ->orderByDesc('t.created_at')
            ->get([
                'u.id',
                'u.number',
                'u.firstName',
                'u.lastName',
                'u.roll',
                't.name as token_name',
                't.created_at as token_created_at',
                't.last_used_at',
            ]);

        if ($rows->isEmpty()) {
            $this->info('لا توجد جلسات نشطة لأي Admin أو Employee حالياً.');

            return self::SUCCESS;
        }

        $this->warn('جلسات نشطة لموظفي لوحة التحكم: '.$rows->count());
        $this->table(
            ['ID', 'الهاتف', 'الاسم', 'الدور', 'اسم التوكن/الجهاز', 'تاريخ الإنشاء', 'آخر استخدام'],
            $rows->map(function ($r) {
                return [
                    $r->id,
                    $r->number,
                    trim(($r->firstName ?? '').' '.($r->lastName ?? '')),
                    $r->roll,
                    $r->token_name,
                    $r->token_created_at,
                    $r->last_used_at ?? '—',
                ];
            })->all()
        );

        return self::SUCCESS;
    }
}
