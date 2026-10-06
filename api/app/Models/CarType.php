<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Cache;

class CarType extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'carTypes';

    protected $fillable = [
        'name',
        'type',
        'timePrice',
        'KMPrice',
        'openPrice',
        'sort_order',
        'customer_badge',
        'also_dispatch_to',
    ];

    protected $casts = [
        'timePrice' => 'decimal:2',
        'KMPrice' => 'decimal:2',
        'openPrice' => 'decimal:2',
        'sort_order' => 'integer',
        'also_dispatch_to' => 'array',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // نوع السيارة إما KM أو Time
    public const TYPE_KM = 'KM';
    public const TYPE_TIME = 'Time';

    public static function getTypes()
    {
        return [
            self::TYPE_KM => 'كيلومتر',
            self::TYPE_TIME => 'وقت',
        ];
    }

    private const DISPATCH_CACHE_KEY = 'car_type_dispatch_map_v1';

    protected static function booted(): void
    {
        $forget = fn () => Cache::forget(self::DISPATCH_CACHE_KEY);
        static::saved($forget);
        static::deleted($forget);
        static::restored($forget);
    }

    /**
     * فئة الطلب ← فئات السائقين الذين يصلهم (تشمل الفئة نفسها دائماً).
     *
     * @return array<int, array{ids: int[], name: string}>
     */
    public static function dispatchMap(): array
    {
        return Cache::remember(self::DISPATCH_CACHE_KEY, 300, function () {
            $map = [];
            foreach (self::query()->get(['id', 'name', 'also_dispatch_to']) as $t) {
                $ids = [(int) $t->id];
                foreach ((array) ($t->also_dispatch_to ?? []) as $x) {
                    if ((int) $x > 0) {
                        $ids[] = (int) $x;
                    }
                }
                $map[(int) $t->id] = ['ids' => array_values(array_unique($ids)), 'name' => (string) $t->name];
            }

            return $map;
        });
    }

    /** @return int[] */
    public static function driverTypeIdsForRequest(int $requestTypeId): array
    {
        return self::dispatchMap()[$requestTypeId]['ids'] ?? [$requestTypeId];
    }

    public static function driverServesRequestType(?int $driverTypeId, ?int $requestTypeId): bool
    {
        if (! $driverTypeId || ! $requestTypeId) {
            return false;
        }

        return in_array((int) $driverTypeId, self::driverTypeIdsForRequest((int) $requestTypeId), true);
    }

    /** @return int[] فئات الطلبات التي تصل لسائق من هذه الفئة */
    public static function requestTypeIdsServedBy(int $driverTypeId): array
    {
        $out = [];
        foreach (self::dispatchMap() as $reqTypeId => $row) {
            if (in_array($driverTypeId, $row['ids'], true)) {
                $out[] = (int) $reqTypeId;
            }
        }

        return $out ?: [$driverTypeId];
    }

    /** ملاحظة لسائق يستلم طلباً من فئة غير فئته، مثل «طلب اقتصادية — الأجرة بتسعيرة الاقتصادية». */
    public static function crossCategoryNote(?int $requestTypeId, ?int $driverTypeId): ?string
    {
        if (! $requestTypeId || ! $driverTypeId || (int) $requestTypeId === (int) $driverTypeId) {
            return null;
        }
        $name = self::dispatchMap()[(int) $requestTypeId]['name'] ?? '';
        if ($name === '') {
            return null;
        }

        return 'طلب '.$name.' — الأجرة بتسعيرة '.$name;
    }

    // Scope للبحث
    public function scopeSearch($query, $search)
    {
        return $query->where('name', 'LIKE', "%{$search}%");
    }

    // Scope لفلترة حسب النوع
    public function scopeOfType($query, $type)
    {
        if ($type && in_array($type, [self::TYPE_KM, self::TYPE_TIME])) {
            return $query->where('type', $type);
        }
        return $query;
    }
}
