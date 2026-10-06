<?php

namespace App\Console\Commands;

use App\Models\Driver;
use Illuminate\Console\Command;

class AuditDriverImages extends Command
{
    protected $signature = 'drivers:audit-images {--fix : تحديث مسارات DB لتطابق الملف الموجود}';

    protected $description = 'فحص صور السائقين: مسار DB مقابل الملفات على القرص';

    public function handle(): int
    {
        $fix = (bool) $this->option('fix');
        $drivers = Driver::withTrashed()->get(['id', 'image', 'carImage']);

        $stats = [
            'total' => $drivers->count(),
            'no_image_path' => 0,
            'driver_file_ok' => 0,
            'driver_file_missing' => 0,
            'car_file_ok' => 0,
            'car_file_missing' => 0,
            'fixed' => 0,
        ];

        foreach ($drivers as $driver) {
            foreach (['image' => 'driver_file', 'carImage' => 'car_file'] as $column => $prefix) {
                $raw = $driver->{$column};
                if ($raw === null || trim((string) $raw) === '') {
                    if ($column === 'image') {
                        $stats['no_image_path']++;
                    }

                    continue;
                }

                $resolved = Driver::resolveExistingStoragePath($raw);
                $keyOk = $prefix.'_ok';
                $keyMissing = $prefix.'_missing';

                if ($resolved !== null) {
                    $stats[$keyOk]++;
                    if ($fix && $resolved !== Driver::normalizeStoragePath($raw)) {
                        $driver->{$column} = $resolved;
                        $stats['fixed']++;
                    }
                } else {
                    $stats[$keyMissing]++;
                }
            }

            if ($fix && $driver->isDirty(['image', 'carImage'])) {
                $driver->save();
            }
        }

        $this->table(
            ['المؤشر', 'العدد'],
            collect($stats)->map(fn ($v, $k) => [$k, $v])->values()->all()
        );

        $diskFiles = count(glob(storage_path('app/public/*')) ?: []);
        $this->line('ملفات في storage/app/public (تقريبي): '.$diskFiles);

        if ($stats['driver_file_missing'] > 0) {
            $this->warn('ملفات ناقصة على السيرفر — لا يمكن استعادتها إلا من نسخة قديمة أو إعادة رفع الصور.');
        }

        return self::SUCCESS;
    }
}
