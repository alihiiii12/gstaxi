<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

class Driver extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'drivers';

    protected $primaryKey = 'id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'userId',
        'transTypeId',
        'receive_radius_km',
        'image',
        'IDImage',
        'carImage',
        'carNumber',
        'insurance',
        'mechanics',
        'type',
        'vehicle_model',
        'freeKMPrice',
        'freeTimePrice',
        'subscription_starts_at',
        'subscription_ends_at',
        'subscription_blocked',
        'subscription_reminder_sent_at',
        'scheduled_cancel_strikes',
    ];

    protected $appends = [
        'driver_photo_url',
        'car_photo_url',
    ];

    protected $casts = [
        'userId' => 'integer',
        'transTypeId' => 'integer',
        'receive_radius_km' => 'integer',
        'freeKMPrice' => 'decimal:2',
        'freeTimePrice' => 'decimal:2',
        'subscription_starts_at' => 'datetime',
        'subscription_ends_at' => 'datetime',
        'subscription_blocked' => 'boolean',
        'subscription_reminder_sent_at' => 'datetime',
        'scheduled_cancel_strikes' => 'integer',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // العلاقات
    public function user()
    {
        return $this->belongsTo(User::class, 'userId');
    }

    public function transType()
    {
        return $this->belongsTo(CarType::class, 'transTypeId');
    }

    public function requestOffers()
    {
        return $this->hasMany(RequestDriverOffer::class, 'driver_id');
    }

    /**
     * يوحّد مسار الصورة بعد النقل بين السيرفرات:
     * روابط كاملة قديمة، storage/public، أو اسم ملف فقط.
     */
    public static function normalizeStoragePath(?string $raw): ?string
    {
        if ($raw === null) {
            return null;
        }

        $path = trim(str_replace('\\', '/', $raw));
        if ($path === '') {
            return null;
        }

        if (preg_match('#/api/drivers/getImage/(.+)$#i', $path, $m)) {
            $path = rawurldecode($m[1]);
        } elseif (preg_match('#^https?://#i', $path)) {
            $path = (string) (parse_url($path, PHP_URL_PATH) ?? '');
        }

        $path = ltrim($path, '/');

        foreach ([
            'storage/app/public/',
            'storage/app/public',
            'storage/',
            'public/storage/',
            'public/',
            'app/public/',
        ] as $prefix) {
            if (str_starts_with($path, $prefix)) {
                $path = substr($path, strlen($prefix));
            }
        }

        $path = ltrim($path, '/');

        return $path !== '' ? $path : null;
    }

    /** يجد أول مسار موجود فعلياً على القرص (مع fallback لاسم الملف فقط). */
    public static function resolveExistingStoragePath(?string $raw): ?string
    {
        $normalized = self::normalizeStoragePath($raw);
        if ($normalized === null) {
            return null;
        }

        $disk = Storage::disk('public');
        $candidates = array_values(array_unique(array_filter([
            $normalized,
            basename($normalized),
        ])));

        foreach ($candidates as $candidate) {
            if ($candidate !== '' && $disk->exists($candidate)) {
                return $candidate;
            }
        }

        return null;
    }

    /** رابط موقّع مؤقت لعرض ملف مرفوع (لا يعتمد على مصادقة المتصفح في <img>). */
    public static function publicUrlForStoragePath(?string $relativePath): ?string
    {
        $resolved = self::resolveExistingStoragePath($relativePath);
        if ($resolved === null) {
            return null;
        }

        try {
            return \Illuminate\Support\Facades\URL::temporarySignedRoute(
                'drivers.getImage',
                now()->addHours(12),
                ['path' => $resolved],
            );
        } catch (\Throwable $e) {
            return url('api/drivers/getImage/'.rawurlencode($resolved));
        }
    }

    public function getDriverPhotoUrlAttribute(): ?string
    {
        return self::publicUrlForStoragePath($this->image);
    }

    public function getCarPhotoUrlAttribute(): ?string
    {
        return self::publicUrlForStoragePath($this->carImage);
    }
}
