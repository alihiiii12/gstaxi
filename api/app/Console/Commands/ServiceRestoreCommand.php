<?php

namespace App\Console\Commands;

use App\Http\Middleware\RejectWhenServiceCut;
use Illuminate\Console\Command;

class ServiceRestoreCommand extends Command
{
    protected $signature = 'service:restore';

    protected $description = 'إعادة اتصال التطبيق ولوحة الأدمن بالسيرفر';

    public function handle(): int
    {
        RejectWhenServiceCut::restore();
        $this->info('تم إعادة الاتصال. التطبيق ولوحة الأدمن يعملان من جديد.');

        return self::SUCCESS;
    }
}
