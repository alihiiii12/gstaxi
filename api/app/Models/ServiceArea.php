<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ServiceArea extends Model
{
    protected $fillable = [
        'name',
        'active',
        'sort_order',
        'south_lat',
        'north_lat',
        'west_lng',
        'east_lng',
    ];

    protected $casts = [
        'active' => 'boolean',
        'sort_order' => 'integer',
        'south_lat' => 'decimal:7',
        'north_lat' => 'decimal:7',
        'west_lng' => 'decimal:7',
        'east_lng' => 'decimal:7',
    ];

    /**
     * إذا حُدّدت الحدود الأربعة يُتحقق أن نقطة الانطلاق داخل المستطيل.
     */
    public function containsPickup(float $latitude, float $longitude): bool
    {
        $s = $this->south_lat;
        $n = $this->north_lat;
        $w = $this->west_lng;
        $e = $this->east_lng;

        if ($s === null || $n === null || $w === null || $e === null) {
            return true;
        }

        $south = (float) $s;
        $north = (float) $n;
        $west = (float) $w;
        $east = (float) $e;

        return $latitude >= min($south, $north)
            && $latitude <= max($south, $north)
            && $longitude >= min($west, $east)
            && $longitude <= max($west, $east);
    }
}
