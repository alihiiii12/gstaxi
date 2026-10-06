<?php

namespace App\Console\Commands;

use App\Http\Middleware\RejectWhenServiceCut;
use Illuminate\Console\Command;

class ServiceLinkStatusCommand extends Command
{
    protected $signature = 'service:status';

    protected $description = 'عرض حالة قطع/اتصال الخدمة';

    public function handle(): int
    {
        if (RejectWhenServiceCut::isCut()) {
            $this->error('الحالة: مقطوع (service:cut)');
            $this->line('للإعادة: php artisan service:restore');
        } else {
            $this->info('الحالة: متصل');
            $this->line('للقطع: php artisan service:cut');
        }

        return self::SUCCESS;
    }
}
