<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
class Location extends Model
{
     use HasFactory, SoftDeletes;

    protected $table = 'locations';

    protected $primaryKey = 'id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'longitude',
        'latitude',
        'name',
        'type',
        'description'
    ];

    protected $casts = [
        'longitude' => 'decimal:7',
        'latitude' => 'decimal:7',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // أنواع المواقع
    const TYPE_PICKUP = 'pickup';      // نقطة انطلاق
    const TYPE_DROPOFF = 'dropoff';    // نقطة وصول
    const TYPE_HOTSPOT = 'hotspot';    // منطقة نشطة
    const TYPE_LANDMARK = 'landmark';  // معلم مهم

    // العلاقات
    public function requestsAsStart()
    {
        return $this->hasMany(RequestModel::class, 'startLocationId');
    }

    public function requestsAsDest()
    {
        return $this->hasMany(RequestModel::class, 'destLocationId');
    }

    // Scope للبحث حسب النوع
    public function scopeOfType($query, $type)
    {
        return $query->where('type', $type);
    }

    // Scope للبحث بالقرب من موقع
    public function scopeNearby($query, $latitude, $longitude, $distance = 1)
    {
        // حساب المسافة باستخدام صيغة هافرسين
        return $query->selectRaw("*, ( 6371 * acos( cos( radians(?) ) * cos( radians( latitude ) ) * cos( radians( longitude ) - radians(?) ) + sin( radians(?) ) * sin( radians( latitude ) ) ) ) AS distance", [$latitude, $longitude, $latitude])
            ->having('distance', '<', $distance)
            ->orderBy('distance');
    }

    // دالة لحساب المسافة بين موقعين
    public function distanceTo($latitude, $longitude)
    {
        $theta = $this->longitude - $longitude;
        $dist = sin(deg2rad($this->latitude)) * sin(deg2rad($latitude)) + cos(deg2rad($this->latitude)) * cos(deg2rad($latitude)) * cos(deg2rad($theta));
        $dist = acos($dist);
        $dist = rad2deg($dist);
        $miles = $dist * 60 * 1.1515;
        return $miles * 1.609344; // بالكيلومتر
    }
}
