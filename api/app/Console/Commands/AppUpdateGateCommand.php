<?php

namespace App\Console\Commands;

use App\Models\AppSetting;
use App\Services\AppUpdatePolicy;
use Illuminate\Console\Command;

/**
 * ضبط بوابة تحديث التطبيق (فتح الدخول فوراً أو تعيين الحد الأدنى).
 */
class AppUpdateGateCommand extends Command
{
    protected $signature = 'app:update-gate
                            {--allow : إيقاف حظر النسخ القديمة (يفتح الدخول فوراً)}
                            {--block : تفعيل حظر النسخ الأقل من الحد الأدنى}
                            {--min= : رقم البناء الأدنى المطلوب}';

    protected $description = 'ضبط إجبار تحديث التطبيق (min_build / block_old_login)';

    public function handle(): int
    {
        if ($this->option('allow')) {
            AppSetting::setValue(AppUpdatePolicy::KEY_BLOCK_OLD, '0');
            $this->info('تم إيقاف حظر النسخ القديمة — يمكن تسجيل الدخول من أي نسخة.');
        }

        if ($this->option('block')) {
            AppSetting::setValue(AppUpdatePolicy::KEY_BLOCK_OLD, '1');
            $this->warn('تم تفعيل حظر النسخ القديمة.');
        }

        $min = $this->option('min');
        if ($min !== null && $min !== '') {
            $n = max(1, (int) $min);
            AppSetting::setValue(AppUpdatePolicy::KEY_MIN_BUILD, (string) $n);
            $this->info("تم تعيين الحد الأدنى للبناء: {$n}");
        }

        $cfg = AppUpdatePolicy::config();
        $this->line('الحالة الحالية:');
        $this->table(
            ['المفتاح', 'القيمة'],
            [
                ['min_build', (string) $cfg['min_build']],
                ['block_old_login', $cfg['block_old_login'] ? 'نعم' : 'لا'],
                ['download_url', (string) $cfg['download_url']],
            ],
        );

        return self::SUCCESS;
    }
}
