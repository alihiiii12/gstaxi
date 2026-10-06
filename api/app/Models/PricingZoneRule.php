<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PricingZoneRule extends Model
{
    protected $table = 'pricing_zone_rules';

    protected $fillable = ['from_zone_id', 'to_zone_id', 'multiplier'];

    protected $casts = [
        'from_zone_id' => 'integer',
        'to_zone_id' => 'integer',
        'multiplier' => 'float',
    ];
}
