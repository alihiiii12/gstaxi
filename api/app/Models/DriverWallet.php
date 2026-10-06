<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class DriverWallet extends Model
{
    protected $table = 'driver_wallets';

    protected $fillable = [
        'driver_id',
        'balance',
        'currency',
    ];

    protected $casts = [
        'balance' => 'decimal:2',
    ];

    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class, 'driver_id');
    }

    public function transactions(): HasMany
    {
        return $this->hasMany(DriverWalletTransaction::class, 'driver_wallet_id');
    }
}
