<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class UsedDiscount extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'usedDiscounts';

    protected $primaryKey = 'id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'requestId',
        'userId',
        'discountId'
    ];

    protected $casts = [
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // العلاقات
    public function request()
    {
        return $this->belongsTo(RequestModel::class, 'requestId');
    }

    public function user()
    {
        return $this->belongsTo(User::class, 'userId');
    }

    public function discount()
    {
        return $this->belongsTo(Discount::class, 'discountId');
    }

    // التحقق مما إذا كان المستخدم قد استخدم هذا الكود من قبل
    public static function isUsedByUser($userId, $discountId)
    {
        return self::where('userId', $userId)
            ->where('discountId', $discountId)
            ->consumed()
            ->exists();
    }

    // عدد مرات استخدام كود خصم معين
    public static function usageCount($discountId)
    {
        return self::where('discountId', $discountId)->consumed()->count();
    }

    /**
     * الكوبون يُحسب مستخدَماً فقط إن كانت رحلته قائمة أو انتهت: الطلب الملغى
     * والطلب الفوري الذي ما زال بانتظار سائق لا يستهلكانه.
     */
    public function scopeConsumed($query)
    {
        return $query->whereHas('request', function ($r) {
            $r->where('status', '!=', RequestModel::STATUS_REMOVED)
                ->where(function ($w) {
                    $w->where('status', '!=', RequestModel::STATUS_PENDING)
                        ->orWhere('type', '!=', RequestModel::TYPE_IMMEDIATE);
                });
        });
    }

    /** تحرير الكوبون عند إلغاء الطلب قبل اكتمال الرحلة. */
    public static function releaseForRequest(int $requestId): int
    {
        return self::where('requestId', $requestId)->delete();
    }
}
