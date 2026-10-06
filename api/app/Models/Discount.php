<?php

namespace App\Models;

use Illuminate\Support\Carbon;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Discount extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'discounts';

    protected $primaryKey = 'id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'code',
        'amount',
        'type',
        'max_discount',
        'max_uses_per_user',
        'target_phones',
        'valid_from',
        'valid_until',
    ];

    protected $appends = ['value_label'];

    protected $casts = [
        'amount' => 'decimal:2',
        'max_discount' => 'decimal:2',
        'max_uses_per_user' => 'integer',
        'target_phones' => 'array',
        'valid_from' => 'datetime',
        'valid_until' => 'datetime',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    public function isActiveNow(?Carbon $at = null): bool
    {
        $at = $at ?: Carbon::now();
        if ($this->valid_from && $at->lt($this->valid_from)) {
            return false;
        }
        if ($this->valid_until && $at->gt($this->valid_until)) {
            return false;
        }

        return true;
    }

    // الثوابت لأنواع الخصم
    const TYPE_PERCENTAGE = 'Percentage';
    const TYPE_FIXED = 'Fixed';

    // دالة مساعدة للحصول على أنواع الخصم
    public static function getTypes()
    {
        return [
            self::TYPE_PERCENTAGE => 'نسبة مئوية',
            self::TYPE_FIXED => 'قيمة ثابتة',
        ];
    }

    /**
     * قيمة الخصم الفعلية: النسبة مقيّدة بـ max_discount، وكلاهما لا يتجاوز السعر نفسه.
     */
    public function calculateDiscount($originalPrice): float
    {
        $price = max(0.0, (float) $originalPrice);

        if ($this->type === self::TYPE_PERCENTAGE) {
            $value = $price * (float) $this->amount / 100;
            $cap = $this->max_discount !== null ? (float) $this->max_discount : null;
            if ($cap !== null && $cap > 0) {
                $value = min($value, $cap);
            }
        } else {
            $value = (float) $this->amount;
        }

        return round(min(max(0.0, $value), $price), 2);
    }

    /** وصف مختصر يُعرض للزبون/السائق: «30٪ (حد أقصى 30 ل.س)» أو «50 ل.س». */
    public function valueLabel(): string
    {
        $fmt = static fn ($n) => rtrim(rtrim(number_format((float) $n, 2, '.', ''), '0'), '.');
        if ($this->type === self::TYPE_PERCENTAGE) {
            $label = $fmt($this->amount).'٪';
            if ($this->max_discount !== null && (float) $this->max_discount > 0) {
                $label .= ' (حد أقصى '.$fmt($this->max_discount).' ل.س)';
            }

            return $label;
        }

        return $fmt($this->amount).' ل.س';
    }

    public function getValueLabelAttribute(): string
    {
        return $this->valueLabel();
    }
    // أضف هذه العلاقات
public function usedDiscounts()
{
    return $this->hasMany(UsedDiscount::class, 'discountId');
}

public function isUsedByUser($userId)
{
    return $this->usedDiscounts()->where('userId', $userId)->consumed()->exists();
}

    /** null = غير محدود. الأعمدة القديمة بدون قيمة تبقى «مرة واحدة». */
    public function usesLimitPerUser(): ?int
    {
        if (! array_key_exists('max_uses_per_user', $this->attributes)) {
            return 1;
        }
        $v = $this->attributes['max_uses_per_user'];

        return $v === null ? null : max(1, (int) $v);
    }

    public function usesByUser(int $userId): int
    {
        return UsedDiscount::where('userId', $userId)->where('discountId', $this->id)->consumed()->count();
    }

    /** رسالة الرفض إن استنفد الراكب عدد المرات، وإلا null. */
    public function usageLimitErrorFor(int $userId): ?string
    {
        $limit = $this->usesLimitPerUser();
        if ($limit === null) {
            return null;
        }
        if ($this->usesByUser($userId) < $limit) {
            return null;
        }

        return $limit === 1
            ? 'لقد استخدمت هذا الكوبون من قبل (مسموح مرة واحدة)'
            : 'لقد استخدمت هذا الكوبون '.self::timesLabel($limit).' وهو الحد المسموح';
    }

    public function usesLimitLabel(): string
    {
        $limit = $this->usesLimitPerUser();

        return $limit === null ? 'عدد غير محدود من المرات' : self::timesLabel($limit);
    }

    public static function timesLabel(int $n): string
    {
        return match (true) {
            $n === 1 => 'مرة واحدة',
            $n === 2 => 'مرتين',
            $n <= 10 => $n.' مرات',
            default => $n.' مرة',
        };
    }

public function getUsageCountAttribute()
{
    return $this->usedDiscounts()->consumed()->count();
}
}
