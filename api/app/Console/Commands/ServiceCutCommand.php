<?php

namespace App\Console\Commands;

use App\Http\Middleware\RejectWhenServiceCut;
use Illuminate\Console\Command;

class ServiceCutCommand extends Command
{
    protected $signature = 'service:cut';

    protected $description = 'قطع اتصال التطبيق ولوحة الأدمن بالسيرفر (مؤقتاً)';

    public function handle(): int
    {
        RejectWhenServiceCut::cut();
        $this->error('تم قطع الاتصال.');
        $this->line('التطبيق + لوحة الأدمن لن يعملان عبر API حتى تعيد التشغيل.');
        $this->info('للإعادة: php artisan service:restore');

        return self::SUCCESS;
    }
}
