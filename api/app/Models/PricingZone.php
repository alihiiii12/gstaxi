<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PricingZone extends Model
{
    protected $table = 'pricing_zones';

    protected $fillable = ['name', 'polygon', 'color', 'is_active', 'sort_order'];

    protected $casts = [
        'polygon' => 'array',
        'is_active' => 'boolean',
        'sort_order' => 'integer',
    ];
}
