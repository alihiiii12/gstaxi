<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DriverWalletTransaction extends Model
{
    public const TYPE_REWARD = 'reward';

    public const TYPE_COUPON = 'coupon_compensation';

    public const TYPE_WITHDRAW = 'admin_withdraw';

    public const TYPE_ADJUST = 'admin_adjust';

    public const TYPE_VIOLATION = 'violation';

    public const TYPE_TRIP_WALLET = 'trip_wallet_payment';

    protected $table = 'driver_wallet_transactions';

    protected $fillable = [
        'driver_wallet_id',
        'driver_id',
        'type',
        'amount',
        'balance_after',
        'request_id',
        'discount_id',
        'note',
        'created_by_user_id',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'balance_after' => 'decimal:2',
    ];

    public function wallet(): BelongsTo
    {
        return $this->belongsTo(DriverWallet::class, 'driver_wallet_id');
    }

    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class, 'driver_id');
    }

    public static function typeLabel(string $type): string
    {
        return match ($type) {
            self::TYPE_REWARD => 'مكافأة',
            self::TYPE_COUPON => 'تعويض كوبون خصم',
            self::TYPE_WITHDRAW => 'سحب بواسطة الإدارة',
            self::TYPE_ADJUST => 'تعديل رصيد',
            self::TYPE_VIOLATION => 'مخالفة',
            self::TYPE_TRIP_WALLET => 'أجرة رحلة مدفوعة من محفظة الراكب',
            default => $type,
        };
    }
}
