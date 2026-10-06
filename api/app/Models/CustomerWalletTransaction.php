<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CustomerWalletTransaction extends Model
{
    public const TYPE_TOPUP = 'admin_topup';

    public const TYPE_DEDUCT = 'admin_deduct';

    public const TYPE_ADJUST = 'admin_adjust';

    public const TYPE_TRIP_PAYMENT = 'trip_payment';

    protected $table = 'customer_wallet_transactions';

    protected $fillable = [
        'customer_wallet_id',
        'user_id',
        'type',
        'amount',
        'balance_after',
        'request_id',
        'note',
        'created_by_user_id',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'balance_after' => 'decimal:2',
    ];

    public function wallet(): BelongsTo
    {
        return $this->belongsTo(CustomerWallet::class, 'customer_wallet_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public static function typeLabel(string $type): string
    {
        return match ($type) {
            self::TYPE_TOPUP => 'تعبئة رصيد',
            self::TYPE_DEDUCT => 'خصم بواسطة الإدارة',
            self::TYPE_ADJUST => 'تصحيح رصيد',
            self::TYPE_TRIP_PAYMENT => 'دفع أجرة رحلة',
            default => $type,
        };
    }
}
